# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"

require_relative "ko_wikisource_mk_parser"
require_relative "../wiki_fetch"
require_relative "../zip_fetch"
require_relative "../redirect_follow"
require_relative "../normalize"

module Nabu
  module Adapters
    # The Middle Korean vernacular shelf (P78-4 — the korean axis's
    # vernacular leg, survey P47-s4): 용비어천가 (龍飛御天歌, Songs of the
    # Dragons Flying to Heaven, 1447 — the first work ever printed in
    # hangul) from Korean Wikisource. The hosted 1447 text is public
    # domain ({{PD-old-100}} on the page); the wiki's transcription layer
    # is CC BY-SA 4.0 → license_class attribution, credit the Wikisource
    # contributors.
    #
    # == Scoping: a curated title list, not a category crawl
    #
    # ko.wikisource hangs no usable category over these works; WORKS maps
    # our stable slug → the page title. The 2026-08-18 census: the WHOLE
    # 용비어천가 lives on ONE page — {{머리말}} header (연도 = 1447, the
    # machine date), a hanmun preface (序 + 進箋: paratext, outside the
    # canto grain — a future revisit, not a claim), then all 125 cantos as
    # == 제N장 == sections. 월인천강지곡 and 석보상절 stay OUT: their
    # pages are <pages index=…/> scan transclusions or fragmentary
    # (per-text audit in the P78-4 report) — they ride only when a
    # completeness census passes.
    #
    # == The grain
    #
    # Document = one work page (urn:nabu:ko-wikisource-mk:<slug>) — the
    # page is the upstream unit of revision and fetch, and the canto (장)
    # is the citation unit WITHIN the work, so cantos are passages, not
    # 125 documents re-minted from one file. Per canto, in page order:
    # the hanmun ruby verse ({{윗주|漢字|reading}} pairs, the 1447 print's
    # parallel Chinese — language "lzh", the sillok/kanripo precedent,
    # reading gloss riding as annotation), then the Middle Korean verse
    # ({{옛한글 인라인|…}} lines — language "okm", ISO 639-3 Middle
    # Korean, THE text of this shelf), urns <doc>:<n>:hanmun / <doc>:<n>.
    # The MODERN Korean rendering (=== 현대어 ===) is part of the licensed
    # page and is carried — as a translation ANNOTATION ("modern") on the
    # MK passage, never as passage text: modern Korean must not masquerade
    # as Middle Korean. The MK layer is complete across all 125 cantos;
    # hanmun/modern coverage is per-canto community reality (34/29 of 125,
    # content-based — cantos 32–34 carry empty layer-heading scaffolding).
    #
    # == NFC facts (binding; verified empirically, survey P47-s4 + the
    #    2026-08-18 fixture check)
    #
    # - Hangul NFC is SAFE for Middle Korean: NO addition to
    #   Normalize::NFC_EXEMPT_LANGUAGES.
    # - Archaic conjoining jamo (ㆍ U+119E arae-a, ㅸ, the U+A960/U+D7B0
    #   extension blocks) survive NFC byte-identical; 방점 tone marks
    #   U+302E/302F ride verbatim.
    # - Modern-L+V+archaic-T sequences PARTIALLY compose under NFC
    #   (U+1100 U+1161 U+11F0 → U+AC00 U+11F0) — canonically equivalent
    #   and lossless, but codepoints can change at this boundary. On the
    #   fixture revision all 250 MK lines are already NFC (byte-stable).
    # - NEVER NFKC: it folds compatibility jamo (U+31xx) into conjoining
    #   jamo — destructive.
    # - Compatibility-jamo input (ㆍ typed as U+318D) is NOT NFC-equal to
    #   conjoining U+119E. Boundary decision: store what upstream has,
    #   verbatim + NFC — no folding, no repair; if upstream ever mixes
    #   jamo repertoires that is upstream reality, visible in the text.
    #
    # == Fetch
    #
    # One batched api.php revisions GET for the curated titles (WikiFetch's
    # envelope shape: title/pageid/ns/revid/timestamp/wikitext verbatim),
    # written tmp+rename to pages/<slug>.json. A curated-title fetch only
    # ever adds or replaces — nothing is upstream-doomed, so the
    # mass-deletion breaker is passed an honest empty set. The pin is the
    # sha256 of the slug→revid map (revid-driven change detection, the
    # WikiFetch doctrine).
    class KoWikisourceMk < Nabu::Adapter
      LANGUAGE = "okm"
      HANMUN_LANGUAGE = "lzh"

      API_URL = "https://ko.wikisource.org/w/api.php"
      STATE_FILE = ".ko-wikisource-fetch.json"
      PAGES_DIRNAME = "pages"

      # The curated scope (owner-adopted survey P47-s4): slug → page title.
      # Adding a work = one row here + its completeness census in the PR.
      WORKS = { "yongbieocheonga" => "용비어천가" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "ko-wikisource-mk",
        name: "용비어천가 — Middle Korean vernacular shelf (Korean Wikisource)",
        license: "1447 text PD ({{PD-old-100}} on the page); transcription layer " \
                 "Creative Commons Attribution-Share Alike 4.0 (api.php rightsinfo " \
                 "verbatim, verified 2026-08-18) — attribution, credit the contributors",
        license_class: "attribution",
        upstream_url: "https://ko.wikisource.org/wiki/용비어천가",
        parser_family: "ko-wikisource",
        credit: "Korean Wikisource (ko.wikisource.org) contributors — 용비어천가 " \
                "transcription, CC BY-SA 4.0"
      )

      def self.manifest
        MANIFEST
      end

      # P11-2: no git repo — the probe HEADs api.php (reachability; drift
      # honestly reads unknown against the revid-pinned state file).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "api.php", zip_url: "#{API_URL}?action=query&meta=siteinfo&format=json",
          metadata_url: nil, state_subdir: ".", state_file: STATE_FILE
        )]
      end

      # +http+ exists for construction-time injection symmetry; tests stub
      # HTTP with WebMock (no network in tests, ever).
      def initialize(http: Nabu::ZipFetch.default_http)
        super()
        @http = http
      end

      def fetch(workdir, progress: nil, force: false)
        pages = fetch_pages
        guard_mass_deletion!(workdir, [], force: force) # curated list: nothing is ever doomed
        revids = WORKS.to_h { |slug, title| [slug, write_envelope!(workdir, slug, pages.fetch(title))] }
        sha = Digest::SHA256.hexdigest(JSON.generate(revids.sort.to_h))
        write_state!(workdir, sha)
        progress&.call("Fetched #{revids.size} curated page(s) from ko.wikisource\n")
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now,
                              notes: "pages: #{revids.size} curated title(s), revid-pinned")
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, PAGES_DIRNAME, "*.json")).each do |path|
          slug = File.basename(path, ".json")
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "urn:nabu:#{MANIFEST.id}:#{slug}",
            path: File.expand_path(path), metadata: { "work" => slug }
          )
        end
      end

      # pages/*.json is the corpus; state file and attics are mechanics;
      # anything else non-dot is a stray — loud.
      def discovery_skips(workdir)
        strays = stray_files(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          unrecognized: strays.size,
          notes: strays.map { |path| "non-corpus file: #{path}" }
        )
      end

      def parse(document_ref)
        envelope = read_envelope(document_ref.path)
        work = parser.parse(envelope.fetch("wikitext"))
        raise Nabu::ParseError, "#{document_ref.path}: no cantos parsed" if work.cantos.empty?

        build_document(document_ref, envelope, work)
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      def parser
        @parser ||= KoWikisourceMkParser.new
      end

      # -- fetch -----------------------------------------------------------------

      # One batched revisions request (≤50 titles — the api.php cap; WORKS
      # stays far under it), title → page hash.
      def fetch_pages
        payload = get_json(
          "action" => "query", "format" => "json", "prop" => "revisions",
          "rvprop" => "content|ids|timestamp", "rvslots" => "main",
          "titles" => WORKS.values.join("|")
        )
        pages = (payload.dig("query", "pages") || {}).values.to_h { |page| [page["title"], page] }
        missing = WORKS.values - pages.keys
        raise Nabu::FetchError, "ko.wikisource is missing curated page(s): #{missing.join(', ')}" unless missing.empty?

        pages
      end

      def write_envelope!(workdir, slug, page)
        revision = page.dig("revisions", 0) or
          raise Nabu::FetchError, "ko.wikisource returned no revision for #{page['title']}"
        envelope = {
          "title" => page.fetch("title"), "pageid" => page["pageid"], "ns" => page["ns"] || 0,
          "revid" => revision["revid"], "timestamp" => revision["timestamp"],
          "wikitext" => revision.dig("slots", "main", "*").to_s
        }
        dir = File.join(workdir, PAGES_DIRNAME)
        FileUtils.mkdir_p(dir)
        target = File.join(dir, "#{slug}.json")
        File.binwrite("#{target}.tmp", "#{JSON.pretty_generate(envelope)}\n")
        File.rename("#{target}.tmp", target)
        envelope["revid"]
      end

      def write_state!(workdir, sha)
        FileUtils.mkdir_p(workdir)
        state = { "last_modified" => nil, "sha256" => sha, "url" => API_URL }
        File.write(File.join(workdir, STATE_FILE), JSON.pretty_generate(state))
      end

      def get_json(params)
        url = "#{API_URL}?#{URI.encode_www_form(params)}"
        response, = Nabu::RedirectFollow.get(url, http: @http, error: Nabu::FetchError,
                                                  headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        payload = JSON.parse(response.body.to_s)
        raise Nabu::FetchError, "api.php error for #{API_URL}: #{payload['error']}" if payload.key?("error")

        payload
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "api.php returned unparseable JSON for #{API_URL}: #{e.message}"
      end

      # -- discovery mechanics -----------------------------------------------------

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

      # -- parse -----------------------------------------------------------------

      def read_envelope(path)
        envelope = JSON.parse(File.read(path))
        raise Nabu::ParseError, "#{path}: page envelope has no wikitext" unless envelope["wikitext"].is_a?(String)

        envelope
      rescue JSON::ParserError, Errno::ENOENT => e
        raise Nabu::ParseError, "#{path}: unreadable page envelope: #{e.message}"
      end

      def build_document(document_ref, envelope, work)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: Nabu::Normalize.nfc(work.title || envelope.fetch("title")),
          metadata: { "date" => date_envelope(work) }.compact
        )
        sequence = 0
        work.cantos.each do |canto|
          # Page order: the hanmun ruby verse, then the Middle Korean verse
          # (the modern rendering riding it as annotation).
          if canto.hanmun_lines.any?
            document << hanmun_passage(document_ref, canto, sequence)
            sequence += 1
          end
          document << mk_passage(document_ref, canto, sequence)
          sequence += 1
        end
        document
      end

      # The MetadataDates :structured shape: 머리말 연도 as a one-year
      # envelope. A work without the machine date claims nothing.
      def date_envelope(work)
        return nil if work.year.nil?

        { "not_before" => work.year, "not_after" => work.year, "raw" => work.year.to_s }
      end

      def hanmun_passage(document_ref, canto, sequence)
        readings = canto.hanmun_lines.map(&:reading)
        annotations = { "canto" => canto.number }
        annotations["reading"] = Nabu::Normalize.nfc(readings.join("\n")) if readings.all?
        Nabu::Passage.new(
          urn: "#{document_ref.id}:#{canto.number}:hanmun", language: HANMUN_LANGUAGE,
          text: Nabu::Normalize.nfc(canto.hanmun_lines.map(&:text).join("\n")),
          sequence: sequence, annotations: annotations
        )
      end

      def mk_passage(document_ref, canto, sequence)
        annotations = { "canto" => canto.number }
        annotations["modern"] = Nabu::Normalize.nfc(canto.modern_lines.join("\n")) if canto.modern_lines.any?
        Nabu::Passage.new(
          urn: "#{document_ref.id}:#{canto.number}", language: LANGUAGE,
          text: Nabu::Normalize.nfc(canto.mk_lines.join("\n")),
          sequence: sequence, annotations: annotations
        )
      end
    end
  end
end
