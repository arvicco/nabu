# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"

require_relative "wikisource_han_parser"
require_relative "../wiki_fetch"
require_relative "../zip_fetch"
require_relative "../redirect_follow"
require_relative "../normalize"

module Nabu
  module Adapters
    # zh-wikisource (P109-1, Q90 under №R-74): the Chinese Wikisource
    # shelf — CENSUSED WORKS, prefix-expanded (the census, 2026-09-29,
    # in .docs/p109-plan.md):
    #
    # - 全唐文 (1,001 juan subpages) — the complete Qing-compiled Tang
    #   prose canon, THE verified delta over the held Kanripo mass.
    #   Its juan pages are TRANSCLUSION SHELLS: each piece (教/詔/制…)
    #   lives on its own top-level page pulled in as {{:題}}. The fetch
    #   expands one transclusion level (batched, throttled) and stores
    #   each juan's pieces beside its shell in the envelope, so the
    #   parse stays offline.
    # - 續資治通鑑 (221 subpages) — direct text.
    # - 元朝秘史 (16 subpages, completeness census PASSED — all 15
    #   juan + 卷首 substantive) — direct text. The hosted layer is
    #   the MING 總譯 (the Chinese summary translation, inline 舌/中
    #   phonetic markers): NO Middle Mongol transcription is hosted
    #   (censused; the page banner's incompleteness refers to that
    #   missing layer), so the work claims zho — the Ming vernacular
    #   Chinese it is — and no Mongolic lect is claimed anywhere.
    # - 皇朝經世文編 FAILED census (4 front-matter subpages, no text)
    #   and is not in the cone.
    #
    # №R-74: base editions are unstated on every censused page —
    # metadata "base_edition" records the honest "unstated". Adding a
    # work = one WORKS row + its census in the PR (the viet-wikisource
    # pattern, prefix-expanded).
    #
    # == Fetch
    #
    # Per work: allpages apprefix (non-redirects) → subpage titles →
    # batched revisions (50/request, throttled, UA-identified) → one
    # envelope per subpage pages/<pageid>.json (+ "work"/"part"
    # provenance; transcluded works add "transclusions" title →
    # wikitext). Non-destructive by construction; the pin is the
    # sha256 of the pageid → revid map (piece revids included).
    class ZhWikisource < Nabu::Adapter
      API_URL = "https://zh.wikisource.org/w/api.php"
      STATE_FILE = ".zh-wikisource-fetch.json"
      PAGES_DIRNAME = "pages"
      URN_PREFIX = "urn:nabu:zh-wikisource:"

      # One censused work: +prefix+ the subpage tree, +mode+ :direct |
      # :transcluded, +language+ the work's honest claim, +dynasty+ an
      # era attribution the whole work carries (全唐文 IS the Tang
      # prose canon — its pieces' own Header times=唐; banded via the
      # ruled period table as a grade-2 era claim) or nil where a
      # work-level era would be a guess (續資治通鑑 is a Qing
      # compilation about Song–Yuan; 元朝秘史's hosted layer is Ming —
      # both claim nothing, declared).
      Work = Data.define(:prefix, :mode, :language, :dynasty)

      WORKS = [
        Work.new(prefix: "全唐文", mode: :transcluded, language: "lzh", dynasty: "唐"),
        Work.new(prefix: "續資治通鑑", mode: :direct, language: "lzh", dynasty: nil),
        Work.new(prefix: "元朝秘史", mode: :direct, language: "zho", dynasty: nil)
      ].freeze

      WORKS_BY_PREFIX = WORKS.to_h { |work| [work.prefix, work] }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "zh-wikisource",
        name: "Chinese Wikisource — censused works (全唐文 · 續資治通鑑 · 元朝秘史)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (zh.wikisource.org footer verbatim, verified 2026-09-29) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://zh.wikisource.org/",
        parser_family: "wikisource-han",
        credit: "Chinese Wikisource (zh.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "api.php", zip_url: "#{API_URL}?action=query&meta=siteinfo&format=json",
          metadata_url: nil, state_subdir: ".", state_file: STATE_FILE
        )]
      end

      def initialize(delay: Nabu::WikiFetch::DELAY, http: Nabu::ZipFetch.default_http)
        super()
        @delay = delay
        @http = http
        @requests = 0
      end

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever
      # deletes, so there is no breaker to override.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        revids = {}
        WORKS.each do |work|
          titles = subpage_titles(work.prefix)
          progress&.call("#{work.prefix}: #{titles.size} subpage(s)\n")
          fetch_work!(workdir, work, titles, revids, progress)
        end
        sha = Digest::SHA256.hexdigest(JSON.generate(revids.sort.to_h))
        write_state!(workdir, sha)
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now,
                              notes: "pages: #{revids.size} envelope(s) across #{WORKS.size} works, revid-pinned")
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, PAGES_DIRNAME, "*.json")).each do |path|
          envelope = read_envelope(path)
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{envelope.fetch('pageid')}",
            path: File.expand_path(path),
            metadata: { "work" => envelope.fetch("work"), "part" => envelope.fetch("part") }
          )
        end
      end

      def discovery_skips(workdir)
        strays = stray_files(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          unrecognized: strays.size,
          notes: strays.map { |rel| "non-corpus file: #{rel}" }
        )
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        envelope = read_envelope(document_ref.path)
        work = WORKS_BY_PREFIX[envelope.fetch("work")] or
          raise ParseError, "#{document_ref.id}: #{envelope['work'].inspect} is not a censused work"

        wikitext = composed_wikitext(envelope, work)
        result = parser.parse(wikitext, mode: :prose)
        raise ParseError, "#{document_ref.id}: no passages extracted" if result.passages.empty?

        build_document(document_ref, envelope, work, result)
      end

      # A shell's piece transclusion: {{:題}}.
      TRANSCLUSION = /\{\{:([^{}|]+)\}\}/

      # api.php batches are capped BOTH by the 50-title API limit and
      # by encoded byte length: 全唐文 piece titles are whole memorial
      # titles, and 50 of them percent-encoded blew the server's URL
      # cap (HTTP 414, censused at the first sync). ~5,000 encoded
      # bytes keeps the full query URL well under the ~8k limit.
      BATCH_BYTE_CAP = 5_000

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

      private

      def parser
        @parser ||= WikisourceHanParser.new
      end

      # -- fetch internals ---------------------------------------------------

      def subpage_titles(prefix)
        titles = []
        continue = {}
        loop do
          payload = get_json("action" => "query", "format" => "json", "list" => "allpages",
                             "apprefix" => "#{prefix}/", "aplimit" => "500",
                             "apfilterredir" => "nonredirects", **continue)
          titles.concat((payload.dig("query", "allpages") || []).map { |page| page.fetch("title") })
          token = payload.dig("continue", "apcontinue") or break

          continue = { "apcontinue" => token }
        end
        titles.sort
      end

      def fetch_work!(workdir, work, titles, revids, progress)
        title_batches(titles).each_with_index do |batch, index|
          progress&.call("#{work.prefix}: batch #{index + 1} (#{batch.size} page(s))…\n")
          pages_payload(batch).each do |page|
            revision = page.dig("revisions", 0) or next

            transclusions = work.mode == :transcluded ? fetch_transclusions!(page, revision, revids) : nil
            revids[page.fetch("pageid")] = revision["revid"]
            write_envelope!(workdir, work, page, revision, transclusions)
          end
        end
      end

      # One expansion level: the shell's {{:題}} pieces, batched. Piece
      # revids join the pin (a piece edit re-syncs its juan).
      def fetch_transclusions!(page, revision, revids)
        titles = revision.dig("slots", "main", "*").to_s.scan(TRANSCLUSION).flatten.uniq
        pieces = {}
        title_batches(titles).each do |batch|
          pages_payload(batch).each do |piece|
            piece_revision = piece.dig("revisions", 0) or next

            revids["#{page.fetch('pageid')}:#{piece.fetch('pageid')}"] = piece_revision["revid"]
            pieces[piece.fetch("title")] = piece_revision.dig("slots", "main", "*").to_s
          end
        end
        pieces
      end

      def pages_payload(batch)
        payload = get_json("action" => "query", "format" => "json", "prop" => "revisions",
                           "rvprop" => "content|ids|timestamp", "rvslots" => "main",
                           "titles" => batch.join("|"))
        (payload.dig("query", "pages") || {}).values.reject { |page| page.key?("missing") }
      end

      def write_envelope!(workdir, work, page, revision, transclusions)
        envelope = {
          "title" => page.fetch("title"), "pageid" => page.fetch("pageid"), "ns" => page["ns"] || 0,
          "revid" => revision["revid"], "timestamp" => revision["timestamp"],
          "work" => work.prefix, "part" => page.fetch("title").delete_prefix("#{work.prefix}/"),
          "wikitext" => revision.dig("slots", "main", "*").to_s
        }
        envelope["transclusions"] = transclusions if transclusions
        dir = File.join(workdir, PAGES_DIRNAME)
        FileUtils.mkdir_p(dir)
        target = File.join(dir, "#{envelope.fetch('pageid')}.json")
        File.binwrite("#{target}.tmp", "#{JSON.pretty_generate(envelope)}\n")
        File.rename("#{target}.tmp", target)
      end

      def write_state!(workdir, sha)
        FileUtils.mkdir_p(workdir)
        state = { "last_modified" => nil, "sha256" => sha, "url" => API_URL }
        File.write(File.join(workdir, STATE_FILE), JSON.pretty_generate(state))
      end

      def get_json(params)
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        url = "#{API_URL}?#{URI.encode_www_form(params)}"
        response, = Nabu::RedirectFollow.get(url, http: @http, error: Nabu::FetchError,
                                                  headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        payload = JSON.parse(response.body.to_s)
        raise Nabu::FetchError, "api.php error: #{payload['error']}" if payload.key?("error")

        payload
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "api.php returned unparseable JSON: #{e.message}"
      end

      # -- discovery/parse internals -----------------------------------------

      def read_envelope(path)
        envelope = JSON.parse(File.read(path))
        raise ParseError, "#{path}: page envelope has no wikitext" unless envelope["wikitext"].is_a?(String)

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

      # A transcluded shell composes offline: each {{:題}} becomes the
      # stored piece's includable text under the shell's own heading; a
      # piece the fetch could not resolve renders nothing (its heading
      # stays — an honest gap, loud in the passage census).
      def composed_wikitext(envelope, work)
        wikitext = envelope.fetch("wikitext")
        return wikitext unless work.mode == :transcluded

        pieces = envelope["transclusions"] || {}
        wikitext.gsub(TRANSCLUSION) { piece_text(pieces[::Regexp.last_match(1).strip]) }
      end

      # The piece's includable region: <onlyinclude> where declared
      # (the censused 全唐文 shape), else the whole piece minus its
      # own leading template block (the parser drops what remains).
      def piece_text(piece_wikitext)
        return "" if piece_wikitext.nil?

        include_blocks = piece_wikitext.scan(%r{<onlyinclude>(.*?)</onlyinclude>}m)
        return include_blocks.flatten.join("\n") unless include_blocks.empty?

        piece_wikitext
      end

      def build_document(document_ref, envelope, work, result)
        document = Nabu::Document.new(
          urn: document_ref.id, language: work.language,
          title: Nabu::Normalize.nfc(envelope.fetch("title")),
          canonical_path: document_ref.path,
          metadata: {
            "work" => envelope.fetch("work"), "part" => envelope.fetch("part"),
            # №R-74: no censused page states a 底本 — recorded honestly.
            "base_edition" => "unstated",
            "dynasty" => work.dynasty,
            "textquality" => result.header.textquality
          }.compact
        )
        result.passages.each_with_index do |passage, index|
          annotations = passage.section ? { "section" => Nabu::Normalize.nfc(passage.section) } : {}
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{index + 1}", language: work.language,
            text: Nabu::Normalize.nfc(passage.text), sequence: index + 1, annotations: annotations
          )
        end
        document
      end
    end
  end
end
