# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"

require_relative "wikisource_slavic_parser"
require_relative "../wiki_fetch"
require_relative "../zip_fetch"
require_relative "../redirect_follow"
require_relative "../normalize"

module Nabu
  module Adapters
    # The South Slavic wikisource family base (P116-2, part 1, under
    # the owner-ruled wikisource posture: premodern category cone, census-
    # first, verbatim edition strings as provenance, category-derived
    # dating where the wiki has it). The ja-wikisource fetch mold,
    # generalized: each concrete adapter (sr/hr/sl/mk/bg) declares its
    # CONE (category roots + walk depth), its EXCLUSIONS (named category
    # rules), and its per-page claims (language, dating, provenance); this
    # class owns the shared machinery.
    #
    # == Fetch
    #
    # Stage 1 walks every cone root (categorymembers, subcategories to the
    # root's depth) into a title → cone-label map; stage 2 fetches the
    # titles in batches of at most 50 titles AND URL_BYTE_CAP encoded URL
    # bytes (prop=revisions|categories, continuation-
    # merged) and writes one envelope per page: pages/<pageid>.json —
    # title/pageid/ns/revid/timestamp verbatim, "cone" (the roots that
    # reached the page), "categories" (every category the page carries,
    # verbatim — the provenance the exclusion rules and metadata read),
    # "wikitext" byte-verbatim. NON-DESTRUCTIVE by construction: a page
    # that leaves the cone upstream is simply kept. The pin is the sha256
    # of the pageid → revid map.
    #
    # == Discover
    #
    # One ref per TEXT envelope. Skip-by-rule classes (counted and named in
    # discovery_skips): redirects, pages carrying an excluded category
    # (the adapter's named rules), author pages, adapter-specific title
    # rules, and pages whose extraction yields no text (index/navigation
    # pages, empty shells).
    class SlavicWikisource < Nabu::Adapter
      PAGES_DIRNAME = "pages"

      # One cone root: the category title (namespace-prefixed, as the API
      # wants it), the subcategory walk depth, the label recorded on every
      # page it reaches.
      Cone = Data.define(:category, :depth, :label)

      REDIRECT = /\A\s*#(?:redirect|преусмери|preusmjeri|preusmeritev|пренасочване|пренасочи)\b/i

      # Headings whose sections are apparatus across the family (sources,
      # editorial notes, interventions, modern renderings) — cut from the
      # text, returned beside it.
      APPARATUS_HEADINGS = [
        "Извор", "Извори", "Избор", "Интервенције", "Напомене", "Коментар", "Литература",
        "Певач и место записа", "Izvor", "Izvori", "Napomene", "Bilješke", "Literatura",
        "Viri", "Opombe", "Наводи", "Забелешки", "Надворешни врски", "Источници",
        "Източници", "Бележки", "На съвременен български език", "Превод", "Външни препратки",
        "Поврзано"
      ].freeze

      # The mk 414 (live first sync, 2026-10-10): a 50-title batch of long
      # Cyrillic titles percent-encodes at ~6 bytes a letter and overran the
      # server's URI limit. Batches bound by the ENCODED request URL as well
      # as by title count: 6,000 bytes sits safely under the common 8 KiB
      # request-line limits (Apache/nginx/varnish defaults), and the
      # CONTINUE_RESERVE leaves room for the rvcontinue/clcontinue tokens
      # a continuation request appends to the same query.
      URL_BYTE_CAP = 6_000
      CONTINUE_RESERVE = 1_000

      TRANSLATOR_PARAMS = %w[преводилац prevoditelj prevajalec преведувач преводач translator].freeze

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

      # -- per-wiki hooks (the concrete adapters override) ---------------------

      # Array of Cone roots.
      def cone = self.class::CONE

      # { category title => human reason } — a page carrying any of these is
      # skipped by rule.
      def exclusions = self.class::EXCLUSIONS

      # Header template names this wiki writes.
      def header_templates = self.class::HEADER_TEMPLATES

      # An extra skip reason for +envelope+ (title rules), or nil.
      def page_skip_reason(_envelope, _result) = nil

      # The document language for +envelope+.
      def language_for(_envelope, _result) = self.class::LANGUAGE

      # Wiki-specific metadata merged over the shared provenance block.
      def extra_metadata(_envelope, _result) = {}

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever deletes,
      # so there is no breaker to override.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        labels_by_title = walk_cone(progress)
        progress&.call("Cone: #{labels_by_title.size} page(s) across #{cone.size} root(s)\n")
        revids = fetch_pages!(workdir, labels_by_title, progress)
        sha = Digest::SHA256.hexdigest(JSON.generate(revids.transform_keys(&:to_s).sort.to_h))
        write_state!(workdir, sha)
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now,
                              notes: "pages: #{revids.size} of #{labels_by_title.size} cone titles, revid-pinned")
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        envelope_paths(workdir).each do |path|
          envelope = read_envelope(path)
          next unless skip_reason(envelope).nil?

          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{self.class::URN_PREFIX}#{envelope.fetch('pageid')}",
            path: File.expand_path(path), metadata: { "title" => envelope.fetch("title") }
          )
        end
      end

      def discovery_skips(workdir)
        reasons = Hash.new(0)
        envelope_paths(workdir).each do |path|
          reason = skip_reason(read_envelope(path))
          reasons[reason] += 1 if reason
        end
        strays = stray_files(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: reasons.values.sum,
          unrecognized: strays.size,
          notes: reasons.sort.map { |reason, count| "#{count} page(s) skipped by rule: #{reason}" } +
                 strays.map { |rel| "non-corpus file: #{rel}" }
        )
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        envelope = read_envelope(document_ref.path)
        reason = skip_reason(envelope)
        raise ParseError, "#{document_ref.id}: a skip-by-rule page reached parse (#{reason})" if reason

        result = parsed(envelope)
        language = language_for(envelope, result)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language,
          title: Nabu::Normalize.nfc(envelope.fetch("title")),
          canonical_path: document_ref.path,
          metadata: document_metadata(envelope, result)
        )
        append_passages!(document, document_ref, result, language)
        raise ParseError, "#{document_ref.id}: no text extracted" if document.empty?

        document
      end

      private

      def parser
        @parser ||= WikisourceSlavicParser.new(header_templates: header_templates,
                                               apparatus_headings: APPARATUS_HEADINGS)
      end

      # Memoizes only the most recent page: discover classifies every
      # envelope (a parse each) and a whole-cone cache would pin the sr
      # cone's ~43 MB of wikitext and its parse trees in memory.
      def parsed(envelope)
        pageid = envelope.fetch("pageid")
        @parsed = [pageid, parser.parse(envelope.fetch("wikitext"))] unless @parsed&.first == pageid
        @parsed.last
      end

      # The page's passages — the hook concrete adapters override when a
      # page class extracts differently (the bg original-script lane).
      def passages_for(_envelope, result) = result.passages

      def append_passages!(document, document_ref, result, language)
        passages_for(read_envelope(document_ref.path), result).each_with_index do |passage, index|
          annotations = { "section" => passage.section && Nabu::Normalize.nfc(passage.section),
                          "stanza" => passage.stanza }.compact
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{index + 1}", language: language,
            text: Nabu::Normalize.nfc(passage.text), sequence: index + 1, annotations: annotations
          )
        end
      end

      # The shared provenance block (owner ruling): the cone roots, every category
      # verbatim, the header's author/notes, the base edition, the verse/
      # prose grain, the wiki's own quality stamp.
      def document_metadata(envelope, result)
        header = result.header.transform_values { |value| Nabu::Normalize.nfc(value) }
        {
          "cone" => Array(envelope["cone"]),
          "categories" => Array(envelope["categories"]).map { |c| Nabu::Normalize.nfc(c.sub(/\A[^:]+:/, "")) },
          "author" => header_value(header, %w[аутор autor avtor автор]),
          "notes" => header_value(header, %w[белешке bilješke opombe забелешки бележки]),
          "base_edition" => base_edition(envelope, result),
          "grain" => grain(result),
          "apparatus" => (apparatus(result) unless result.apparatus.empty?),
          "textquality" => textquality(envelope, header)
        }.merge(extra_metadata(envelope, result)).compact
      end

      def header_value(header, keys)
        key = header.keys.find { |k| keys.include?(k.strip.downcase) }
        key ? header[key] : nil
      end

      # The Wikisource posture: the page's stated source edition verbatim — the wiki's own
      # source section (Извор/Избор/Izvor…), else the header's publication
      # fields, else the honest "unstated". Concrete adapters refine.
      def base_edition(_envelope, result)
        source = result.apparatus.find { |heading, _| heading.match?(/\A(Извор|Избор|Izvor)[.:]?\z/i) }
        return Nabu::Normalize.nfc(source[1].gsub(/\A[*\s]+/, "").gsub(/\s+/, " ")) if source

        "unstated"
      end

      def apparatus(result)
        result.apparatus.to_h { |heading, text| [Nabu::Normalize.nfc(heading), Nabu::Normalize.nfc(text)] }
      end

      def grain(result)
        verse = result.passages.count(&:verse)
        return "verse" if verse == result.passages.size && verse.positive?
        return "prose" if verse.zero?

        "mixed"
      end

      def textquality(envelope, header)
        stamp = envelope.fetch("wikitext")[/\{\{\s*(?:Квалитет|Textquality)\s*\|\s*(\d+%?)\s*\}\}/i, 1]
        stamp || header_value(header, %w[obdelano])
      end

      # -- classification ----------------------------------------------------

      def skip_reason(envelope)
        @skip_reasons ||= {}
        pageid = envelope.fetch("pageid")
        return @skip_reasons[pageid] if @skip_reasons.key?(pageid)

        @skip_reasons[pageid] = compute_skip_reason(envelope)
      end

      def compute_skip_reason(envelope)
        wikitext = envelope.fetch("wikitext")
        return "redirect" if wikitext.match?(REDIRECT)

        excluded = Array(envelope["categories"]).find { |category| exclusions.key?(category) }
        return "#{exclusions.fetch(excluded)} (#{excluded})" if excluded

        result = parsed(envelope)
        return "author page (biography furniture, no hosted text)" if result.author_page
        return "translation (the header names a translator)" if translated?(result)

        page_skip_reason(envelope, result) || shell_reason(envelope, result)
      end

      # An index page is mostly navigation list items (the volume/collection
      # tables of contents); an empty extraction is a shell.
      def shell_reason(envelope, result)
        passages = passages_for(envelope, result)
        return "no hosted text (empty shell)" if passages.empty?
        return "index page (navigation list, no hosted text)" if
          result.index_items >= 3 && result.index_items > passages.size

        nil
      end

      def translated?(result)
        result.header.any? { |key, value| TRANSLATOR_PARAMS.include?(key.strip.downcase) && !value.strip.empty? }
      end

      # -- fetch internals ---------------------------------------------------

      def walk_cone(progress)
        labels = Hash.new { |hash, key| hash[key] = [] }
        cone.each do |root|
          seen = {}
          queue = [[root.category, 0]]
          until queue.empty?
            category, depth = queue.shift
            next if seen.key?(category)

            seen[category] = true
            category_members(category).each do |member|
              if member["ns"] == 0 # rubocop:disable Style/NumericPredicate
                labels[member.fetch("title")] << root.label
              elsif member["ns"] == 14 && depth < root.depth
                queue << [member.fetch("title"), depth + 1]
              end
            end
          end
          progress&.call("#{root.label}: cone at #{labels.size} page(s)\n")
        end
        order = cone.map(&:label)
        labels.transform_values { |list| list.uniq.sort_by { |label| order.index(label) } }
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

      def fetch_pages!(workdir, labels_by_title, progress)
        revids = {}
        title_batches(labels_by_title.keys.sort).each_with_index do |batch, index|
          progress&.call("Fetching batch #{index + 1} (#{batch.size} page(s))…\n")
          pages_payload(batch).each do |page|
            revision = page.dig("revisions", 0) or next
            labels = labels_by_title[page.fetch("title")]
            revids[page.fetch("pageid")] = write_envelope!(workdir, page, revision, labels)
          end
        end
        revids
      end

      # Slices +titles+ at CONTENT_BATCH titles or the URL_BYTE_CAP (less
      # the CONTINUE_RESERVE) of the encoded first request, whichever binds
      # first. A lone title past the cap still goes out alone — MediaWiki
      # titles cap at 255 bytes, so that cannot reach the limit.
      def title_batches(titles)
        budget = URL_BYTE_CAP - CONTINUE_RESERVE
        titles.each_with_object([[]]) do |title, batches|
          candidate = batches.last + [title]
          if !batches.last.empty? &&
             (candidate.size > Nabu::WikiFetch::CONTENT_BATCH || api_url(pages_params(candidate)).bytesize > budget)
            batches << [title]
          else
            batches.last << title
          end
        end.reject(&:empty?)
      end

      def pages_params(batch)
        { "action" => "query", "format" => "json", "prop" => "revisions|categories",
          "rvprop" => "content|ids|timestamp", "rvslots" => "main",
          "cllimit" => "max", "titles" => batch.join("|") }
      end

      def api_url(params) = "#{self.class::API_URL}?#{URI.encode_www_form(params)}"

      # One batch, continuation-merged: big pages can push revision content
      # and the category lists across several responses (rvcontinue/
      # clcontinue); pages merge by pageid.
      def pages_payload(batch)
        pages = {}
        continue = {}
        loop do
          payload = get_json(**pages_params(batch), **continue)
          (payload.dig("query", "pages") || {}).each_value do |page|
            next if page.key?("missing")

            merged = (pages[page.fetch("pageid")] ||= page.merge("categories" => []))
            merged["revisions"] ||= page["revisions"] if page["revisions"]
            merged["categories"] |= Array(page["categories"]).map { |c| c.fetch("title") }
          end
          continue = payload["continue"] or break
        end
        pages.values
      end

      def write_envelope!(workdir, page, revision, labels)
        envelope = {
          "title" => page.fetch("title"), "pageid" => page.fetch("pageid"), "ns" => page["ns"] || 0,
          "revid" => revision["revid"], "timestamp" => revision["timestamp"],
          "cone" => labels, "categories" => page["categories"].sort,
          "wikitext" => revision.dig("slots", "main", "*").to_s
        }
        dir = File.join(workdir, PAGES_DIRNAME)
        FileUtils.mkdir_p(dir)
        target = File.join(dir, "#{envelope.fetch('pageid')}.json")
        File.binwrite("#{target}.tmp", "#{JSON.pretty_generate(envelope)}\n")
        File.rename("#{target}.tmp", target)
        envelope["revid"]
      end

      def write_state!(workdir, sha)
        FileUtils.mkdir_p(workdir)
        state = { "last_modified" => nil, "sha256" => sha, "url" => self.class::API_URL }
        File.write(File.join(workdir, self.class::STATE_FILE), JSON.pretty_generate(state))
      end

      def get_json(params)
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        url = api_url(params)
        response, = Nabu::RedirectFollow.get(url, http: @http, error: Nabu::FetchError,
                                                  headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        payload = JSON.parse(response.body.to_s)
        raise Nabu::FetchError, "api.php error: #{payload['error']}" if payload.key?("error")

        payload
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "api.php returned unparseable JSON: #{e.message}"
      end

      # -- discovery internals -----------------------------------------------

      def envelope_paths(workdir)
        Dir.glob(File.join(workdir, PAGES_DIRNAME, "*.json"))
      end

      # Most-recent memo only (the parsed rationale: no whole-cone cache).
      def read_envelope(path)
        return @envelope.last if @envelope&.first == path

        envelope = JSON.parse(File.read(path))
        raise ParseError, "#{path}: page envelope has no wikitext" unless envelope["wikitext"].is_a?(String)

        @envelope = [path, envelope]
        envelope
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
           .sort
      end
    end
  end
end
