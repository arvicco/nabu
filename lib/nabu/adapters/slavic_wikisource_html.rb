# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"

require_relative "wikisource_html_parser"
require_relative "../wiki_fetch"
require_relative "../zip_fetch"
require_relative "../redirect_follow"
require_relative "../normalize"

module Nabu
  module Adapters
    # The Slavic wikisource family base (P116-3; the owner-ruled Wikisource posture —
    # premodern cone, census-first, verbatim edition strings — the
    # ja/zh-wikisource precedent carried to pl/cs/ru/uk). Subclasses are
    # pure configuration: the API endpoint, the censused CONE, the header
    # fields that state a page's edition, and the per-wiki exclusion
    # rules. Everything else — fetch, discovery, the rule census, the
    # parse — lives here once.
    #
    # == The cone (CONE, censused per wiki)
    #
    # categories: { "Kategoria:X" => depth } — ns-0 members of each
    # category, subcategories followed to +depth+ (0 = direct members);
    # prefixes: work subpage trees (allpages apprefix); titles: single
    # censused pages. A page whose wikitext is a versions/disambiguation
    # shell (VERSIONS_TEMPLATE) has its ns-0 links followed ONE level —
    # the edition pages a shell points at join the cone (provenance
    # "versions:<shell title>"), the shell itself skips by rule.
    #
    # == Envelope (pages/<pageid>.json)
    #
    # title/pageid/ns/revid/timestamp/wikitext verbatim + "cone" (how the
    # page entered) + "html": the server-rendered page (api.php
    # action=parse, oldid = the stored revid) — present only for pages
    # the wikitext rules admit, so excluded pages cost no parse call.
    # The proofread texts are transclusions of scan pages; the rendered
    # page is the only shape where they have resolved (WikisourceHtmlParser).
    # The pin is the sha256 of the pageid → revid map plus each html's
    # content digest (a scan-page edit changes the rendering, never the
    # page revid — the ja "expanded" precedent).
    #
    # == The rules (wikitext header first, then the rendering)
    #
    # Applied in this order, each a named skip-by-rule class:
    # versions (VERSIONS_TEMPLATE) · reference (REFERENCE_PREFIXES —
    # encyclopedia articles) · aggregate (AGGREGATE_SEGMENT — whole-work
    # "complete text" duplicates of held parts) · apparatus
    # (APPARATUS_SEGMENT — editorial introductions, glossaries, indexes,
    # commentary) · excluded (EXCLUDED_TITLES, each with its censused
    # reason) · modernized (MODERNIZED_SEGMENT — a modern-orthography
    # duplicate of a held old-orthography page) · translation
    # (TRANSLATOR_FIELDS filled) · edition_taint (EDITION_TAINT_POST_1930:
    # the page's edition statement — its EDITION_FIELDS, the <pages
    # index> scan names and the title's edition parenthetical, URLs
    # stripped — carries a year 1931 or later, or names a
    # TAINTED_SERIES; a post-1930 edition layer is never ingested, the
    # ruled ПВЛ-1997 case) · empty (the rendering yields no text).
    class SlavicWikisourceHtml < Nabu::Adapter
      PAGES_DIRNAME = "pages"
      CONE = { categories: {}, prefixes: [], titles: [] }.freeze
      VERSIONS_TEMPLATE = /\A\z/
      REFERENCE_PREFIXES = [].freeze
      AGGREGATE_SEGMENT = /\A\z/
      APPARATUS_SEGMENT = /\A\z/
      MODERNIZED_SEGMENT = /\A\z/
      EXCLUDED_TITLES = {}.freeze
      EDITION_FIELDS = [].freeze
      TRANSLATOR_FIELDS = [].freeze
      TAINTED_SERIES = [].freeze
      # The header's author slot(s), first filled wins — the same "author"
      # key the wikitext family (SlavicWikisource: sl/hr/sr/mk/bg) mines.
      AUTHOR_FIELDS = [].freeze
      # The header field naming the PARENT work a page belongs to (pl
      # |pochodzenie=, cs TITUL) → metadata "work"; WORK_REQUIRES gates it
      # on a field that marks the page as a part (uk: назва is the parent
      # only on a секція page). nil = the wiki states no parent work.
      WORK_FIELD = nil
      WORK_REQUIRES = nil
      # Imprint evidence a wiki states in the BODY HEAD instead of the
      # header (ru: the az.lib.ru imports open with their source book's
      # imprint between rules) — nil = header-only wiki. Only the first
      # BODY_HEAD_CHARS of the body are read, so footnote citations deep
      # in a text never count as its edition.
      BODY_EVIDENCE = nil
      BODY_HEAD_CHARS = 1_500
      # The ruled cutoff: an edition statement naming a year after 1930
      # keys the page to an edition whose editorial layer may still be
      # protected — excluded by rule (EDITION_TAINT_POST_1930).
      TAINT_AFTER_YEAR = 1930
      YEAR = /(?<!\d)(1[0-9]\d\d|20\d\d)(?!\d)/
      # The zh 414 lesson: batches cap at 50 titles AND ~5,000 encoded bytes.
      BATCH_BYTE_CAP = 5_000
      WIKILINK_TARGET = /\[\[([^\[\]|#]+)(?:[|#][^\[\]]*)?\]\]/

      RULE_NOTES = {
        versions: "versions/disambiguation shell(s) — no hosted text (their edition links were followed)",
        reference: "encyclopedia/reference article(s) — not the text",
        aggregate: "whole-work aggregate page(s) duplicating held parts",
        apparatus: "editorial apparatus page(s) (introductions, glossaries, indexes, commentary)",
        excluded: "censused exclusion(s) — each with its reason in EXCLUDED_TITLES",
        modernized: "modern-orthography duplicate(s) of held old-orthography pages",
        translation: "translation page(s) — a modern translator's layer, not the text",
        edition_taint: "page(s) excluded by EDITION_TAINT_POST_1930 (edition statement keys to a " \
                       "post-1930 edition)",
        empty: "page(s) whose rendering carries no text"
      }.freeze

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "api.php", zip_url: "#{self::API_URL}?action=query&meta=siteinfo&format=json",
          metadata_url: nil, state_subdir: ".", state_file: self::STATE_FILE
        )]
      end

      def initialize(delay: Nabu::WikiFetch::DELAY, http: Nabu::ZipFetch.default_http)
        super()
        @delay = delay
        @http = http
        @requests = 0
      end

      # -- the rules (public: the per-wiki tests exercise them directly) -----

      # The page's rule class from its envelope: a Symbol from RULE_NOTES,
      # or :text.
      def page_class(envelope)
        wikitext = envelope.fetch("wikitext")
        title = envelope.fetch("title")
        wikitext_class(title, wikitext) || (passages_for(envelope).empty? ? :empty : :text)
      end

      def wikitext_class(title, wikitext)
        return :versions if wikitext.match?(self.class::VERSIONS_TEMPLATE)
        return :reference if self.class::REFERENCE_PREFIXES.any? { |prefix| title.start_with?(prefix) }

        segments = title.split("/").drop(1)
        return :aggregate if segments.any? { |segment| segment.match?(self.class::AGGREGATE_SEGMENT) }
        return :apparatus if segments.any? { |segment| segment.match?(self.class::APPARATUS_SEGMENT) }
        return :excluded if self.class::EXCLUDED_TITLES.key?(title)
        return :modernized if title.split("/").any? { |segment| segment.match?(self.class::MODERNIZED_SEGMENT) }
        return :translation if translation?(wikitext)
        return :edition_taint if edition_taint?(title, wikitext)

        nil
      end

      # The verbatim edition statement (owner ruling): the EDITION_FIELDS values
      # as stated, the <pages index> scan names, and the title's edition
      # parenthetical — joined " · ", markup reduced to its display text.
      # "unstated" when the page states nothing.
      def edition_statement(title, wikitext)
        parts = self.class::EDITION_FIELDS.filter_map do |field|
          value = header_field(wikitext, field)
          value = display_text(value) if value
          "#{field}: #{value}" if value && !value.empty?
        end
        pages_indexes(wikitext).each { |index| parts << "index: #{index}" }
        body_evidence(wikitext).each { |evidence| parts << "body: #{evidence}" }
        title_edition_parts(title).each { |part| parts << "title: #{part}" }
        parts.empty? ? "unstated" : Nabu::Normalize.nfc(parts.uniq.join(" · "))
      end

      # The rule's evidence: every year the statement names (URLs stripped
      # — az.lib.ru-style slugs carry composition years, not editions).
      def edition_years(title, wikitext)
        statement = edition_statement(title, wikitext).gsub(%r{https?://\S+}, " ")
        statement.scan(YEAR).flatten.map { |year| Integer(year, 10) }
      end

      def edition_taint?(title, wikitext)
        return true if edition_years(title, wikitext).any? { |year| year > TAINT_AFTER_YEAR }

        statement = edition_statement(title, wikitext)
        self.class::TAINTED_SERIES.any? { |series| statement.include?(series) }
      end

      # The page's author as the header states it, display-reduced: the
      # LAST occurrence of a field wins (MediaWiki renders a duplicated
      # template parameter's last value — cs Dalimil states AUTOR twice),
      # a trailing template after the name is an editorial note and drops
      # (cs "neznámý{{Redakční poznámka|…}}"), a whole-value list template
      # reduces to its names. nil when no slot is filled.
      def header_author(wikitext)
        self.class::AUTHOR_FIELDS.each do |field|
          value = name_text(last_header_field(wikitext, field))
          return value if value
        end
        nil
      end

      # The parent work the header names (WORK_FIELD), display-reduced;
      # nil when the wiki states none, the page is not a part, or the value
      # is a label-less relative link ("[[../]]" names nothing).
      def parent_work(wikitext)
        field = self.class::WORK_FIELD or return nil

        gate = self.class::WORK_REQUIRES
        return nil if gate && name_text(header_field(wikitext, gate)).nil?

        name_text(last_header_field(wikitext, field))
      end

      def translation?(wikitext)
        self.class::TRANSLATOR_FIELDS.any? do |field|
          value = header_field(wikitext, field)
          value = display_text(value).strip if value
          value && !value.empty? && !value.match?(/\A(нет|ні|не)\z/i)
        end
      end

      # -- fetch -------------------------------------------------------------

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        cone = cone_titles(progress)
        progress&.call("Cone: #{cone.size} page(s)\n")
        pins = {}
        envelopes = fetch_wikitexts!(workdir, cone, pins, progress)
        follow_versions!(workdir, envelopes, pins, progress)
        render!(workdir, envelopes, pins, progress)
        fetch_extra!(workdir, pins, progress)
        sha = Digest::SHA256.hexdigest(JSON.generate(pins.transform_keys(&:to_s).sort.to_h))
        write_state!(workdir, sha)
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now,
                              notes: "pages: #{envelopes.size} envelope(s) over a #{cone.size}-title cone, " \
                                     "revid + rendering pinned")
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        envelope_paths(workdir).each do |path|
          envelope = read_envelope(path)
          next unless page_class(envelope) == :text

          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{self.class::URN_PREFIX}#{envelope.fetch('pageid')}",
            path: File.expand_path(path), metadata: { "title" => envelope.fetch("title") }
          )
        end
      end

      def discovery_skips(workdir)
        classes = Hash.new(0)
        envelope_paths(workdir).each do |path|
          klass = page_class(read_envelope(path))
          classes[klass] += 1 unless klass == :text
        end
        strays = stray_files(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: classes.values.sum,
          unrecognized: strays.size,
          notes: self.class::RULE_NOTES.filter_map do |klass, note|
            "#{classes[klass]} #{note}" if classes[klass].positive?
          end +
                 strays.map { |rel| "non-corpus file: #{rel}" }
        )
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        envelope = read_envelope(document_ref.path)
        klass = page_class(envelope)
        raise ParseError, "#{document_ref.id}: a #{klass} page reached parse (stale ref?)" unless klass == :text

        language = language_for(envelope)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language,
          title: Nabu::Normalize.nfc(envelope.fetch("title")),
          canonical_path: document_ref.path,
          metadata: document_metadata(envelope)
        )
        passages_for(envelope).each_with_index do |passage, index|
          annotations = passage.section ? { "section" => passage.section } : {}
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{index + 1}", language: language,
            text: passage.text, sequence: index + 1, annotations: annotations
          )
        end
        document
      end

      private

      # Subclass hooks ---------------------------------------------------------

      def language_for(_envelope) = self.class::LANGUAGE

      # Per-wiki axis metadata (era bands, edition dates); default none.
      def extra_metadata(_envelope) = {}

      # Extra fetch stages (pl's Brückner scans); default none.
      def fetch_extra!(_workdir, _pins, _progress) = nil

      # Extra non-envelope paths the fetch writes (stray census); default none.
      def corpus_path?(_rel) = false

      # Metadata ---------------------------------------------------------------

      def document_metadata(envelope)
        title = envelope.fetch("title")
        wikitext = envelope.fetch("wikitext")
        {
          "base_edition" => edition_statement(title, wikitext),
          "cone" => Array(envelope["cone"]).map { |entry| Nabu::Normalize.nfc(entry) },
          "revid" => envelope["revid"],
          "author" => header_author(wikitext),
          "work" => parent_work(wikitext)
        }.merge(extra_metadata(envelope)).compact
      end

      def passages_for(envelope)
        @passages ||= {}
        @passages[envelope.fetch("pageid")] ||= parser.parse(envelope["html"].to_s)
      end

      def parser
        @parser ||= WikisourceHtmlParser.new
      end

      # Header parsing ---------------------------------------------------------

      # A |field= value inside the page's header template, up to the next
      # top-level |field= or the closing braces; nil when absent.
      def header_field(wikitext, field)
        match = wikitext.match(/^\s*\|\s*#{Regexp.escape(field)}\s*=(.*?)(?=^\s*\|\s*[^|=\n]+=|^\s*\}\}|\z)/m)
        match && match[1].gsub(/<!--.*?-->/m, "").strip
      end

      # Every occurrence of +field+ in the header, the last one returned
      # (comments stripped); nil when absent.
      def last_header_field(wikitext, field)
        values = wikitext.scan(/^\s*\|\s*#{Regexp.escape(field)}\s*=(.*?)(?=^\s*\|\s*[^|=\n]+=|^\s*\}\}|\z)/m)
        value = values.last&.first
        value && value.gsub(/<!--.*?-->/m, "").strip
      end

      # A name-shaped header value → display text: links reduced to their
      # labels FIRST (so a list template's "|" never splits inside a link),
      # a trailing note template dropped, the rest display-reduced; nil when
      # blank or a bare relative link.
      def name_text(value)
        return nil if value.nil?

        text = value.gsub(/\[\[(?:[^\[\]|]*\|)?([^\[\]]*)\]\]/) { ::Regexp.last_match(1) }
        text = text.sub(/\{\{.*\z/m, "") unless text.lstrip.start_with?("{{")
        text = display_text(text)
        return nil if text.empty? || text.start_with?("../", "/")

        Nabu::Normalize.nfc(text)
      end

      # The body head (after the header template's closing line) → every
      # BODY_EVIDENCE match, display-reduced.
      def body_evidence(wikitext)
        pattern = self.class::BODY_EVIDENCE or return []

        closing = wikitext.match(/^\}\}[ \t]*$/)
        body = closing ? wikitext[closing.end(0)..] : wikitext
        head = body[0, self.class::BODY_HEAD_CHARS].to_s
        head.to_enum(:scan, pattern).map { display_text(::Regexp.last_match(0)) }.reject(&:empty?).uniq
      end

      def pages_indexes(wikitext)
        wikitext.scan(%r{<pages\b[^>]*?\bindex\s*=\s*(?:"([^"]+)"|'([^']+)'|(\S+?))(?=[\s>/])}i)
                .map { |captures| captures.compact.first.tr("_", " ") }.uniq
      end

      # The title's own edition marks: the root's dated parenthetical
      # ("Fraszki (Kochanowski, 1883)") and any dated subpage segment
      # ("…/1997 (ДО)", "…/Поучение детям/1893/ВТ").
      def title_edition_parts(title)
        root, *segments = title.split("/")
        [root[/\(([^()]*\d{4}[^()]*)\)/, 1], *segments.grep(/\d{4}/)].compact.map(&:strip)
      end

      # Markup to display text: [[target|label]] → label, [url label] →
      # label, templates → their last argument, refs/tags dropped.
      def display_text(value)
        text = value.gsub(%r{<ref[^>]*/>}m, "").gsub(%r{<ref[^>]*>.*?</ref>}m, "")
        3.times do
          text = text.gsub(/\{\{([^{}]*)\}\}/) do
            args = ::Regexp.last_match(1).split("|").map(&:strip).reject do |arg|
              arg.empty? || arg.match?(/\A[^=]+=\z/)
            end
            named = args.map { |arg| arg.include?("=") ? arg.split("=", 2).last.strip : arg }
            named.drop(1).reject(&:empty?).join(", ")
          end
        end
        text.gsub(/\[\[(?:[^\[\]|]*\|)?([^\[\]]*)\]\]/) { ::Regexp.last_match(1) }
            .gsub(%r{</?[a-z][^>]*>}i, " ")
            .gsub(%r{\[(https?://\S+)\s+([^\]]*)\]}) { "#{::Regexp.last_match(2)} (#{::Regexp.last_match(1)})" }
            .gsub(%r{\[(https?://[^\s\]]+)\]}) { "(#{::Regexp.last_match(1)})" }
            .gsub(/'{2,}/, "").gsub("&nbsp;", " ").gsub(/\s+/, " ").strip
      end

      # Fetch internals --------------------------------------------------------

      def cone_titles(progress)
        cone = Hash.new { |hash, key| hash[key] = [] }
        self.class::CONE.fetch(:categories, {}).each do |category, depth|
          walk_category(category, depth).each { |title| cone[title] << category }
          progress&.call("#{category}: cone at #{cone.size} page(s)\n")
        end
        self.class::CONE.fetch(:prefixes, []).each do |prefix|
          [prefix, *prefix_titles("#{prefix}/")].each { |title| cone[title] << "prefix:#{prefix}" }
        end
        self.class::CONE.fetch(:titles, []).each { |title| cone[title] << "title" }
        cone
      end

      def walk_category(category, depth)
        titles = []
        seen = {}
        queue = [[category, 0]]
        until queue.empty?
          current, level = queue.shift
          next if seen.key?(current)

          seen[current] = true
          category_members(current).each do |member|
            if member["ns"].to_i.zero?
              titles << member.fetch("title")
            elsif member["ns"] == 14 && level < depth
              queue << [member.fetch("title"), level + 1]
            end
          end
        end
        titles
      end

      def category_members(category)
        members = []
        continue = {}
        loop do
          payload = get_json("action" => "query", "format" => "json", "list" => "categorymembers",
                             "cmtitle" => category, "cmlimit" => "500", **continue)
          members.concat(payload.dig("query", "categorymembers") || [])
          token = payload.dig("continue", "cmcontinue") or break

          continue = { "cmcontinue" => token }
        end
        members
      end

      def prefix_titles(prefix)
        titles = []
        continue = {}
        loop do
          payload = get_json("action" => "query", "format" => "json", "list" => "allpages",
                             "apprefix" => prefix, "aplimit" => "500",
                             "apfilterredir" => "nonredirects", **continue)
          titles.concat((payload.dig("query", "allpages") || []).map { |page| page.fetch("title") })
          token = payload.dig("continue", "apcontinue") or break

          continue = { "apcontinue" => token }
        end
        titles
      end

      # Stage 1: every cone title's current revision → an html-less envelope.
      def fetch_wikitexts!(workdir, cone, pins, progress)
        envelopes = {}
        title_batches(cone.keys.sort).each_with_index do |batch, index|
          progress&.call("Wikitext batch #{index + 1} (#{batch.size} page(s))…\n")
          revisions_payload(batch).each do |page|
            revision = page.dig("revisions", 0) or next

            envelope = build_envelope(page, revision, cone.fetch(page.fetch("title"), ["redirect"]))
            pins[envelope.fetch("pageid")] = envelope.fetch("revid")
            envelopes[envelope.fetch("pageid")] = envelope
            write_envelope!(workdir, envelope)
          end
        end
        envelopes
      end

      # Stage 2: a versions shell's ns-0 links (one level) join the cone.
      def follow_versions!(workdir, envelopes, pins, progress)
        known = envelopes.values.to_h { |envelope| [envelope.fetch("title"), true] }
        targets = Hash.new { |hash, key| hash[key] = [] }
        envelopes.each_value do |envelope|
          next unless envelope.fetch("wikitext").match?(self.class::VERSIONS_TEMPLATE)

          version_links(envelope).each do |target|
            targets[target] << "versions:#{envelope.fetch('title')}" unless known.key?(target)
          end
        end
        return if targets.empty?

        progress&.call("Versions: following #{targets.size} edition link(s)\n")
        title_batches(targets.keys.sort).each do |batch|
          revisions_payload(batch).each do |page|
            revision = page.dig("revisions", 0) or next
            next if envelopes.key?(page.fetch("pageid"))

            envelope = build_envelope(page, revision, targets.fetch(page.fetch("title"), ["versions"]))
            pins[envelope.fetch("pageid")] = envelope.fetch("revid")
            envelopes[envelope.fetch("pageid")] = envelope
            write_envelope!(workdir, envelope)
          end
        end
      end

      # Only the shell's edition list — the links BEFORE its first heading
      # (the "see also" / encyclopedia sections below it are not editions).
      def version_links(envelope)
        base = envelope.fetch("title")
        edition_list = envelope.fetch("wikitext").split(/^==/).first.to_s
        edition_list.scan(WIKILINK_TARGET).flatten.filter_map do |link|
          link = link.strip
          link = "#{base}#{link.delete_suffix('/')}" if link.start_with?("/")
          next if link.include?(":") # namespaced (Autor:, Kategoria:, w:, File:…)
          next if link.start_with?("..")

          link.tr("_", " ")
        end.uniq
      end

      # Stage 3: the admitted pages' renderings, pinned to their revid.
      def render!(workdir, envelopes, pins, progress)
        admitted = envelopes.values.reject do |envelope|
          wikitext_class(envelope.fetch("title"), envelope.fetch("wikitext"))
        end
        progress&.call("Rendering #{admitted.size} admitted page(s) (one action=parse each)…\n")
        admitted.each_with_index do |envelope, index|
          progress&.call("  rendered #{index}/#{admitted.size}\n") if (index % 50).zero? && index.positive?
          payload = get_json("action" => "parse", "format" => "json", "oldid" => envelope.fetch("revid").to_s,
                             "prop" => "text", "disablelimitreport" => "1", "disableeditsection" => "1",
                             "disabletoc" => "1")
          html = payload.dig("parse", "text", "*").to_s
          pins["#{envelope.fetch('pageid')}:html"] = Digest::SHA256.hexdigest(html)[0, 16]
          write_envelope!(workdir, envelope.merge("html" => html))
        end
      end

      def build_envelope(page, revision, cone)
        {
          "title" => page.fetch("title"), "pageid" => page.fetch("pageid"), "ns" => page["ns"] || 0,
          "revid" => revision["revid"], "timestamp" => revision["timestamp"],
          "cone" => cone.uniq, "wikitext" => revision.dig("slots", "main", "*").to_s
        }
      end

      def revisions_payload(batch)
        payload = get_json("action" => "query", "format" => "json", "prop" => "revisions",
                           "rvprop" => "content|ids|timestamp", "rvslots" => "main",
                           "redirects" => "1", "titles" => batch.join("|"))
        (payload.dig("query", "pages") || {}).values.reject { |page| page.key?("missing") || page.key?("invalid") }
      end

      def title_batches(titles)
        batches = [[]]
        bytes = 0
        titles.each do |title|
          size = URI.encode_www_form_component(title).bytesize + 3
          if !batches.last.empty? &&
             (batches.last.size >= Nabu::WikiFetch::CONTENT_BATCH || bytes + size > BATCH_BYTE_CAP)
            batches << []
            bytes = 0
          end
          batches.last << title
          bytes += size
        end
        batches.pop if batches.last.empty?
        batches
      end

      def write_envelope!(workdir, envelope)
        dir = File.join(workdir, PAGES_DIRNAME)
        FileUtils.mkdir_p(dir)
        target = File.join(dir, "#{envelope.fetch('pageid')}.json")
        File.binwrite("#{target}.tmp", "#{JSON.pretty_generate(envelope)}\n")
        File.rename("#{target}.tmp", target)
      end

      def write_state!(workdir, sha)
        FileUtils.mkdir_p(workdir)
        state = { "last_modified" => nil, "sha256" => sha, "url" => self.class::API_URL }
        File.write(File.join(workdir, self.class::STATE_FILE), JSON.pretty_generate(state))
      end

      def get_json(params)
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        url = "#{self.class::API_URL}?#{URI.encode_www_form(params)}"
        response, = Nabu::RedirectFollow.get(url, http: @http, error: Nabu::FetchError,
                                                  headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        payload = JSON.parse(response.body.to_s)
        raise Nabu::FetchError, "api.php error: #{payload['error']}" if payload.key?("error")

        payload
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "api.php returned unparseable JSON: #{e.message}"
      end

      # Discovery internals ----------------------------------------------------

      def envelope_paths(workdir)
        Dir.glob(File.join(workdir, PAGES_DIRNAME, "*.json"))
      end

      def read_envelope(path)
        @envelopes ||= {}
        @envelopes[path] ||= begin
          envelope = JSON.parse(File.read(path))
          raise ParseError, "#{path}: page envelope has no wikitext" unless envelope["wikitext"].is_a?(String)

          envelope
        end
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable page envelope: #{e.message}"
      end

      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .reject { |path| File.basename(path).start_with?(".") }
           .grep_v(%r{/#{PAGES_DIRNAME}/[^/]+\.json\z})
           .reject { |path| File.basename(path).downcase == "readme.md" }
           .map { |path| path.delete_prefix("#{workdir}/") }
           .reject { |rel| corpus_path?(rel) }
           .sort
      end
    end
  end
end
