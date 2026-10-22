# frozen_string_literal: true

require "digest"
require "json"

require_relative "slavic_wikisource_html"
require_relative "source_read"

module Nabu
  module Adapters
    # The scan-indexed wikisource family (P120-3): the wikisource-html
    # family (SlavicWikisourceHtml — fetch, render, rules, parse) carried
    # to wikis whose texts are ProofreadPage transclusions and whose
    # EDITION is stated on the scan's Index page rather than in the page
    # header (gu / ms / th). Subclasses stay configuration.
    #
    # == The cone (adds :indexes)
    #
    # CONE[:indexes] names Index pages (without the namespace); every ns-0
    # page that transcludes the Index (list=embeddedin on the Index page —
    # a <pages index> tag registers one) joins the cone, provenance
    # "index:<name>". Categories / prefixes / titles work as in the base.
    #
    # == The Index evidence (envelope "indexes")
    #
    # Every Index a page's <pages index> tags name is fetched (redirects
    # followed) and its INDEX_FIELDS values ride the page envelope
    # VERBATIM (raw wikitext values, the wiki's own field names) with the
    # Index title/pageid/revid — the pin includes each Index revid, so an
    # Index edit (a corrected year) re-pins the page.
    #
    # == The rules (after the base's wikitext rules)
    #
    # excluded_index (a censused EXCLUDED_INDEXES entry, each with its
    # reason) · edition_taint (EDITION_TAINT_POST_1930 over the base
    # statement PLUS the Index year fields — #years_in is the per-wiki
    # calendar hook: th converts Buddhist-Era years) · edition_unstated
    # (REQUIRE_EDITION_YEAR wikis only: a page whose edition states no
    # year cannot pass the post-1930 filter, so it is excluded — the
    # conservative default).
    #
    # == ProofreadPage quality (envelope "page_quality")
    #
    # For admitted pages the fetch records the quality level of every
    # Page: page the rendering transcluded (prop=templates on the Page
    # namespace, then prop=proofread): a histogram {"0".."4", "missing"}
    # → metadata "proofread" (levels + the lowest level holding text).
    # The level is RECORDED, never a filter — the census reads it.
    #
    # == The persisted cone (cone.json — a declared materialization)
    #
    # The tree must carry everything discovery needs (the weak-identity
    # rule), so a parse-only pass re-derives exactly the live cone:
    #
    # - The fetch is all-or-nothing on canonical: every stage builds its
    #   envelopes in memory and nothing is written until the last stage
    #   lands. (2026-10-21, br-wikisource: a transport timeout mid-fetch
    #   had already rewritten the 643 envelopes sorting before the failing
    #   batch as stage-1 shells — no Index evidence, no rendering — and the
    #   next parse-only pass classed them out; the mass-deletion breaker
    #   caught it.)
    # - After the envelopes, CONE_FILE records the cone the fetch drew:
    #   "pages" (pageid → title, every envelope this fetch wrote) and
    #   "indexes" (the Index verdict table: every Index the walk judged,
    #   with its year evidence and in_cone verdict — the dated cones
    #   record their whole allpages walk, the named-Index cones their
    #   CONE[:indexes]).
    # - Discovery reads it: a listed page without its envelope, or any
    #   envelope lacking the Index stage (a stage-1 shell), stops discovery
    #   with a FetchError — never a silently smaller cone; an envelope the
    #   last fetch no longer drew (the page left the cone upstream) skips
    #   by rule (outside_cone). A tree fetched before the sidecar existed
    #   discovers from its envelopes' own evidence, under the same
    #   stage-1-shell guard; its next fetch writes the sidecar.
    class IndexedWikisource < SlavicWikisourceHtml
      INDEX_NS = "Index"
      PAGE_NS = 104
      # role => the Index template's field name (verbatim). The "year" role
      # feeds the edition-year evidence.
      INDEX_FIELDS = {}.freeze
      # role => the page header template's field name (metadata "header").
      HEADER_TEMPLATE = "header"
      HEADER_FIELDS = {}.freeze
      EXCLUDED_INDEXES = {}.freeze
      REQUIRE_EDITION_YEAR = false
      QUALITY_KEYS = %w[0 1 2 3 4 missing].freeze
      CONE_FILE = "cone.json"
      # Index roles that ride index_editions but never the edition statement
      # (workflow status, file type, the scan's contents list).
      STATEMENT_SKIP_ROLES = %w[progress source language notes remarks].freeze

      RULE_NOTES = SlavicWikisourceHtml::RULE_NOTES.merge(
        excluded_index: "page(s) transcluding a censused excluded Index — each with its reason in " \
                        "EXCLUDED_INDEXES",
        edition_unstated: "page(s) whose edition states no year — an undated edition cannot pass " \
                          "EDITION_TAINT_POST_1930 (excluded by rule)",
        outside_cone: "page(s) outside the cone the last fetch drew (CONE_FILE) — the page left the " \
                      "cone upstream; its envelope stays, never re-admitted"
      ).freeze

      def self.materialized_paths = [CONE_FILE]

      # -- the rules ---------------------------------------------------------

      def page_class(envelope)
        envelope_class(envelope) || (passages_for(envelope).empty? ? :empty : :text)
      end

      # The envelope's rule class before any rendering (nil = admitted).
      def envelope_class(envelope)
        return :outside_cone if @persisted_cone && !@persisted_cone.key?(envelope.fetch("pageid").to_s)

        wikitext_class(envelope.fetch("title"), envelope.fetch("wikitext")) || index_class(envelope)
      end

      def index_class(envelope)
        indexes = Array(envelope["indexes"])
        return :excluded_index if indexes.any? { |index| self.class::EXCLUDED_INDEXES.key?(index["name"]) }

        years = envelope_edition_years(envelope)
        return :edition_taint if years.any? { |year| year > TAINT_AFTER_YEAR }
        return :edition_unstated if self.class::REQUIRE_EDITION_YEAR && years.empty?

        nil
      end

      # The base statement's years (header EDITION_FIELDS, <pages index>
      # names, the title's edition marks) plus every Index "year" value.
      def envelope_edition_years(envelope)
        years = edition_years(envelope.fetch("title"), envelope.fetch("wikitext"))
        index_years = Array(envelope["indexes"]).flat_map { |index| years_in(index_role(index, "year").to_s) }
        (years + index_years).uniq
      end

      def edition_years(title, wikitext)
        years_in(edition_statement(title, wikitext).gsub(%r{https?://\S+}, " "))
      end

      # The per-wiki calendar hook: every year a text states, as CE.
      def years_in(text)
        text.scan(YEAR).flatten.map { |year| Integer(year, 10) }
      end

      # -- fetch -------------------------------------------------------------

      # All-or-nothing on canonical (class note): the stages' envelope
      # writes are held until the last stage lands, then the envelopes,
      # the cone sidecar, and the state file go down in that order.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        @persisted_cone = nil
        @held_envelopes = {}
        @index_verdicts = {}
        cone = cone_titles(progress)
        progress&.call("Cone: #{cone.size} page(s)\n")
        pins = {}
        envelopes = fetch_wikitexts!(workdir, cone, pins, progress)
        follow_versions!(workdir, envelopes, pins, progress)
        attach_indexes!(workdir, envelopes, pins, progress)
        render!(workdir, envelopes, pins, progress)
        attach_quality!(workdir, envelopes, pins, progress)
        commit_envelopes!(workdir)
        write_cone!(workdir, envelopes)
        sha = Digest::SHA256.hexdigest(JSON.generate(pins.transform_keys(&:to_s).sort.to_h))
        write_state!(workdir, sha)
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now,
                              notes: "pages: #{envelopes.size} envelope(s) over a #{cone.size}-title cone, " \
                                     "revid + Index + rendering + proofread levels pinned")
      ensure
        @held_envelopes = nil
        @index_verdicts = nil
      end

      private

      # Metadata ---------------------------------------------------------------

      def document_metadata(envelope)
        {
          "base_edition" => full_edition_statement(envelope),
          "index_editions" => index_editions(envelope),
          "header" => header_metadata(envelope),
          "proofread" => proofread_metadata(envelope),
          "cone" => Array(envelope["cone"]).map { |entry| Nabu::Normalize.nfc(entry) },
          "revid" => envelope["revid"]
        }.merge(extra_metadata(envelope)).compact
      end

      # The verbatim edition statement: the base statement with each
      # "index: NAME" carrying that Index's own stated fields.
      def full_edition_statement(envelope)
        statement = edition_statement(envelope.fetch("title"), envelope.fetch("wikitext"))
        Array(envelope["indexes"]).each do |index|
          fields = index_field_pairs(index)
          next if fields.empty?

          described = "index: #{index['name']} (#{fields.map { |field, value| "#{field}: #{value}" }.join('; ')})"
          statement = if statement.include?("index: #{index['name']}")
                        statement.sub("index: #{index['name']}", described)
                      else
                        [statement == "unstated" ? nil : statement, described].compact.join(" · ")
                      end
        end
        Nabu::Normalize.nfc(statement)
      end

      def index_editions(envelope)
        editions = Array(envelope["indexes"]).map do |index|
          { "index" => index["name"], "index_title" => index["title"] }
            .merge(self.class::INDEX_FIELDS.keys.to_h { |role| [role, index_role(index, role)] }.compact)
            .transform_values { |value| Nabu::Normalize.nfc(value.to_s) }
        end
        editions.empty? ? nil : editions
      end

      def header_metadata(envelope)
        args = template_args(envelope.fetch("wikitext"), self.class::HEADER_TEMPLATE)
        header = self.class::HEADER_FIELDS.filter_map do |role, field|
          value = args[field]
          value = display_text(value) if value
          [role, Nabu::Normalize.nfc(value)] if value && !value.empty?
        end.to_h
        header.empty? ? nil : header
      end

      def proofread_metadata(envelope)
        levels = envelope["page_quality"]
        return nil unless levels.is_a?(Hash) && !levels.empty?

        with_text = levels.keys.grep(/\A[1-4]\z/).map(&:to_i)
        { "levels" => levels, "lowest_text_level" => with_text.min }.compact
      end

      # An Index field by role, display-reduced; nil when empty/absent.
      def index_role(index, role)
        field = self.class::INDEX_FIELDS[role] or return nil
        value = index.dig("fields", field) or return nil
        value = display_text(value)
        value.empty? ? nil : value
      end

      def index_field_pairs(index)
        self.class::INDEX_FIELDS.filter_map do |role, field|
          next if STATEMENT_SKIP_ROLES.include?(role)

          value = index_role(index, role)
          [field, value] if value
        end
      end

      # Template parsing -------------------------------------------------------

      # The named arguments of the first {{name …}} template, raw values —
      # inline or one-per-line, nested templates/links kept whole.
      def template_args(wikitext, name)
        start = wikitext =~ /\{\{\s*#{Regexp.escape(name)}\s*(?=[|}\n])/i or return {}

        body = balanced_template(wikitext, start) or return {}
        split_top_level(body).drop(1).filter_map do |arg|
          key, value = arg.split("=", 2)
          [key.strip, value.to_s.gsub(/<!--.*?-->/m, "").strip] if value
        end.to_h
      end

      def balanced_template(text, start)
        depth = 0
        index = start
        while index < text.length
          pair = text[index, 2]
          if pair == "{{"
            depth += 1
            index += 2
          elsif pair == "}}"
            depth -= 1
            return text[(start + 2)...index] if depth.zero?

            index += 2
          else
            index += 1
          end
        end
        nil
      end

      def split_top_level(body)
        parts = [+""]
        depth = 0
        index = 0
        while index < body.length
          pair = body[index, 2]
          if ["{{", "[["].include?(pair)
            depth += 1
            parts.last << pair
            index += 2
          elsif ["}}", "]]"].include?(pair)
            depth -= 1
            parts.last << pair
            index += 2
          elsif body[index] == "|" && depth.zero?
            parts << +""
            index += 1
          else
            parts.last << body[index]
            index += 1
          end
        end
        parts
      end

      # Discovery internals ----------------------------------------------------

      # The tree's envelopes, checked against the persisted cone (class
      # note): an incomplete tree stops discovery loudly.
      def envelope_paths(workdir)
        paths = super
        @persisted_cone = read_cone(workdir)
        check_listed_pages!(workdir, paths) if @persisted_cone
        shells = paths.reject { |path| read_envelope(path).key?("indexes") }
        unless shells.empty?
          raise Nabu::FetchError,
                "#{workdir}: #{shells.size} envelope(s) lack the Index stage (e.g. " \
                "#{File.basename(shells.min)}) — the tree holds an interrupted fetch's stage-1 shells; " \
                "re-run the fetch (a parse-only pass would shrink the cone)"
        end
        paths
      end

      def check_listed_pages!(workdir, paths)
        held = paths.to_h { |path| [File.basename(path, ".json"), true] }
        missing = @persisted_cone.keys.reject { |pageid| held.key?(pageid) }
        return if missing.empty?

        raise Nabu::FetchError,
              "#{workdir}: #{missing.size} page(s) the last fetch drew have no envelope (e.g. #{missing.min}) " \
              "— #{CONE_FILE} and #{PAGES_DIRNAME}/ disagree; re-run the fetch"
      end

      # pageid (string) → title, or nil for a tree that predates the sidecar.
      def read_cone(workdir)
        path = File.join(workdir, CONE_FILE)
        return nil unless File.file?(path)

        JSON.parse(SourceRead.utf8_file(path, label: "cone sidecar")).fetch("pages")
      rescue JSON::ParserError, KeyError, Nabu::ParseError => e
        raise Nabu::FetchError, "#{path}: unreadable cone sidecar: #{e.message} — re-run the fetch"
      end

      def corpus_path?(rel) = rel == CONE_FILE || super

      # Fetch internals --------------------------------------------------------

      # Held during a fetch (class note); written through otherwise.
      def write_envelope!(workdir, envelope)
        return super if @held_envelopes.nil?

        @held_envelopes[envelope.fetch("pageid")] = envelope
      end

      def commit_envelopes!(workdir)
        held = @held_envelopes
        @held_envelopes = nil
        held.each_value { |envelope| write_envelope!(workdir, envelope) }
      end

      def write_cone!(workdir, envelopes)
        cone = {
          "pages" => envelopes.values.sort_by { |envelope| envelope.fetch("pageid") }
                              .to_h { |envelope| [envelope.fetch("pageid").to_s, envelope.fetch("title")] },
          "indexes" => @index_verdicts.sort.to_h
        }
        target = File.join(workdir, CONE_FILE)
        File.binwrite("#{target}.tmp", "#{JSON.pretty_generate(cone)}\n")
        File.rename("#{target}.tmp", target)
      end

      # One walked Index's verdict row for the sidecar (a no-op outside a fetch).
      def record_index_verdict(name, year:, in_cone:)
        @index_verdicts[name] = { "year" => year, "in_cone" => in_cone } if @index_verdicts
      end

      def cone_titles(progress)
        cone = super
        self.class::CONE.fetch(:indexes, []).each do |name|
          record_index_verdict(name, year: nil, in_cone: true)
          embedding_titles("#{self.class::INDEX_NS}:#{name}").each { |title| cone[title] << "index:#{name}" }
          progress&.call("index #{name}: cone at #{cone.size} page(s)\n")
        end
        cone
      end

      def embedding_titles(title)
        titles = []
        continue = {}
        loop do
          payload = get_json("action" => "query", "format" => "json", "list" => "embeddedin",
                             "eititle" => title, "einamespace" => "0", "eilimit" => "500", **continue)
          titles.concat((payload.dig("query", "embeddedin") || []).map { |page| page.fetch("title") })
          token = payload.dig("continue", "eicontinue") or break

          continue = { "eicontinue" => token }
        end
        titles
      end

      # Stage 1b: every named Index's fields → the page envelopes.
      def attach_indexes!(workdir, envelopes, pins, progress)
        names = envelopes.values.flat_map { |envelope| pages_indexes(envelope.fetch("wikitext")) }.uniq.sort
        progress&.call("Indexes: #{names.size} named\n")
        indexes = fetch_indexes(names)
        indexes.each_value { |index| pins["index:#{index['pageid']}"] = index["revid"] }
        envelopes.each do |pageid, envelope|
          attached = pages_indexes(envelope.fetch("wikitext")).map do |name|
            indexes.fetch(name) { { "name" => name, "title" => nil, "fields" => {} } }
          end
          envelopes[pageid] = envelope.merge("indexes" => attached)
          write_envelope!(workdir, envelopes[pageid])
        end
      end

      # name → {"name", "title", "pageid", "revid", "fields"} (redirects
      # followed; a missing Index carries no fields).
      def fetch_indexes(names)
        found = {}
        title_batches(names.map { |name| "#{self.class::INDEX_NS}:#{name}" }).each do |batch|
          payload = get_json("action" => "query", "format" => "json", "prop" => "revisions",
                             "rvprop" => "content|ids", "rvslots" => "main", "redirects" => "1",
                             "titles" => batch.join("|"))
          resolve = resolution_map(payload)
          pages = (payload.dig("query", "pages") || {}).values.to_h { |page| [page["title"], page] }
          batch.each do |requested|
            page = pages[resolve.call(requested)] or next
            revision = page.dig("revisions", 0) or next

            name = requested.delete_prefix("#{self.class::INDEX_NS}:")
            found[name] = { "name" => name, "title" => page["title"], "pageid" => page["pageid"],
                            "revid" => revision["revid"],
                            "fields" => index_fields(revision.dig("slots", "main", "*").to_s) }
          end
        end
        found
      end

      # requested title → final title (normalization, then redirects).
      def resolution_map(payload)
        normalized = (payload.dig("query", "normalized") || []).to_h { |row| [row["from"], row["to"]] }
        redirects = (payload.dig("query", "redirects") || []).to_h { |row| [row["from"], row["to"]] }
        lambda do |title|
          title = normalized.fetch(title, title)
          redirects.fetch(title, title)
        end
      end

      def index_fields(wikitext)
        self.class::INDEX_FIELDS.values.filter_map do |field|
          value = header_field(wikitext, field)
          [field, Nabu::Normalize.nfc(value)] if value && !value.empty?
        end.to_h
      end

      # Stage 3: the admitted pages' renderings, pinned to their revid.
      def render!(workdir, envelopes, pins, progress)
        admitted = envelopes.values.reject { |envelope| envelope_class(envelope) }
        progress&.call("Rendering #{admitted.size} admitted page(s) (one action=parse each)…\n")
        admitted.each_with_index do |envelope, index|
          progress&.call("  rendered #{index}/#{admitted.size}\n") if (index % 50).zero? && index.positive?
          payload = get_json("action" => "parse", "format" => "json", "oldid" => envelope.fetch("revid").to_s,
                             "prop" => "text", "disablelimitreport" => "1", "disableeditsection" => "1",
                             "disabletoc" => "1")
          html = payload.dig("parse", "text", "*").to_s
          pins["#{envelope.fetch('pageid')}:html"] = Digest::SHA256.hexdigest(html)[0, 16]
          envelopes[envelope.fetch("pageid")] = envelope.merge("html" => html)
          write_envelope!(workdir, envelopes[envelope.fetch("pageid")])
        end
      end

      # Stage 4: the ProofreadPage level of every Page: page each rendered
      # page transcludes → a per-page histogram.
      def attach_quality!(workdir, envelopes, pins, progress)
        rendered = envelopes.values.select { |envelope| envelope.key?("html") }
        return if rendered.empty?

        transcluded = page_transclusions(rendered.map { |envelope| envelope.fetch("title") })
        levels = page_levels(transcluded.values.flatten.uniq.sort)
        progress&.call("Proofread levels: #{levels.size} Page: page(s)\n")
        rendered.each do |envelope|
          histogram = Hash.new(0)
          transcluded.fetch(envelope.fetch("title"), []).each { |page| histogram[levels.fetch(page, "missing")] += 1 }
          ordered = QUALITY_KEYS.filter_map { |key| [key, histogram[key]] if histogram[key].positive? }.to_h
          pins["#{envelope.fetch('pageid')}:quality"] = ordered
          envelopes[envelope.fetch("pageid")] = envelope.merge("page_quality" => ordered)
          write_envelope!(workdir, envelopes[envelope.fetch("pageid")])
        end
      end

      def page_transclusions(titles)
        found = Hash.new { |hash, key| hash[key] = [] }
        title_batches(titles.sort).each do |batch|
          continue = {}
          loop do
            payload = get_json("action" => "query", "format" => "json", "prop" => "templates",
                               "tlnamespace" => self.class::PAGE_NS.to_s, "tllimit" => "max",
                               "titles" => batch.join("|"), **continue)
            (payload.dig("query", "pages") || {}).each_value do |page|
              Array(page["templates"]).each { |template| found[page["title"]] << template.fetch("title") }
            end
            token = payload.dig("continue", "tlcontinue") or break

            continue = { "tlcontinue" => token }
          end
        end
        found.transform_values(&:uniq)
      end

      # Page: title → "0".."4" (missing pages are absent).
      def page_levels(titles)
        levels = {}
        title_batches(titles).each do |batch|
          payload = get_json("action" => "query", "format" => "json", "prop" => "proofread",
                             "titles" => batch.join("|"))
          (payload.dig("query", "pages") || {}).each_value do |page|
            quality = page.dig("proofread", "quality")
            levels[page["title"]] = quality.to_s unless quality.nil? || page.key?("missing")
          end
        end
        levels
      end
    end
  end
end
