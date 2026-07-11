# frozen_string_literal: true

module Nabu
  module Adapters
    # The CCMH adapter (P13-2): the Corpus Cyrillo-Methodianum Helsingiense
    # (University of Helsinki 1986-2017, distributed by Kielipankki / the
    # Language Bank of Finland) — the four gospel manuscripts of the OCS
    # canon in the corpus's own CES XML: Codex Assemanianus and Savvina
    # kniga (absent from every other holding — the packet's two prizes) plus
    # Codex Marianus and Codex Zographensis as ALTERNATIVE EDITIONS of the
    # PROIEL/TOROT witnesses (Helsinki transliteration of the print
    # editions; two editions of a work are two versions, never a dedupe —
    # conventions §3). The corpus's three txt-only texts (Suprasliensis,
    # Vita Constantini, Vita Methodii) ship no XML and are DEFERRED — a
    # future ccmh-txt family if wanted (owner decision 2026-07-11); TOROT
    # holds a Suprasliensis and the richer obdurodon edition is queued.
    #
    # == Identity (FROZEN minting)
    #
    # One document per (manuscript, gospel book): urn =
    # urn:nabu:ccmh:<manuscript>:<book> (urn:nabu:ccmh:assemanianus:mat),
    # book codes lowercased from upstream's MAT/MAR/LUK/JOH (MAR not MRK —
    # the literal-upstream-slug rule). Passage urns append <chapter>.<verse>
    # from the seg ids, zero-padding stripped; duplicate verse ids get the
    # ":b2" collision suffix (see CcmhCesParser). Minting is frozen once
    # used (standing rule).
    #
    # == License
    #
    # CC BY 4.0. Verbatim, the bundle's own README.txt
    # (https://www.kielipankki.fi/download/ccmh-src/README.txt): "Licence:
    # CC-BY (https://creativecommons.org/licenses/by/4.0)". The download
    # index labels ccmh-src.zip "CC BY"; the Helsinki data catalogue marks
    # the resource "Open". license_class "attribution"; attribution: CCMH,
    # University of Helsinki / Kielipankki (urn:nbn:fi:lb-20140730106).
    # See test/fixtures/ccmh/README.md for the whole chain.
    #
    # == fetch / sync policy
    #
    # Four per-manuscript FileFetch targets (the ASPR path), one subdir
    # each: FileFetch keeps ONE state file per dir and dooms unrecognized
    # siblings, so the files must not share a directory. ORACC's two-phase
    # shape aggregates them: prepare all four, run the mass-deletion breaker
    # once over the union, then complete — no partial tree on a guard trip.
    # Upstream is a plain HTTPS file tree (no git, no zip endpoint worth the
    # indirection; the -src zip exists but the per-file URLs are the stable
    # browse surface). Effectively frozen since 2021 → sync_policy: manual,
    # enabled: false until the owner-fired first real sync.
    class Ccmh < Nabu::Adapter
      BASE_URL = "https://www.kielipankki.fi/download/ccmh-src/www"

      MANIFEST = Nabu::SourceManifest.new(
        id: "ccmh",
        name: "CCMH — Corpus Cyrillo-Methodianum Helsingiense (Kielipankki)",
        license: "CC BY 4.0 (verbatim bundle README.txt: \"Licence: CC-BY " \
                 "(https://creativecommons.org/licenses/by/4.0)\")",
        license_class: "attribution",
        upstream_url: BASE_URL,
        parser_family: "ccmh-ces"
      )

      # The v1 scope (OWNER-APPROVED 2026-07-11): the four gospel
      # manuscripts — the ones upstream encodes as CES XML. Alphabetical;
      # display names are the forms scholars cite.
      MANUSCRIPTS = {
        "assemanianus" => "Codex Assemanianus",
        "marianus" => "Codex Marianus",
        "savvina" => "Savvina kniga",
        "zographensis" => "Codex Zographensis"
      }.freeze

      BOOK_TITLES = { "MAT" => "Matthew", "MAR" => "Mark", "LUK" => "Luke", "JOH" => "John" }.freeze

      def self.manifest
        MANIFEST
      end

      # The probe HEADs each manuscript file: reachability + Last-Modified
      # drift vs the per-subdir .file-fetch.json pin. metadata_url nil: the
      # license lives in the bundle README, re-read at fixture refresh, not
      # at an endpoint.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        MANUSCRIPTS.keys.map do |slug|
          Nabu::Adapter::HttpProbeTarget.new(
            label: "#{slug}.xml", zip_url: file_url(slug), metadata_url: nil,
            state_subdir: slug, state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      def self.file_url(slug)
        "#{BASE_URL}/#{slug}.xml"
      end

      # One DocumentRef per (manuscript, gospel book), manuscripts in
      # MANUSCRIPTS order, books in file order (canonical gospel order).
      # Returns an Enumerator without a block (the adapter contract's lazy
      # shape). A workdir without the files yields nothing (the day-one
      # pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        CcmhCesParser.new.parse(
          document_ref.path,
          book_id: document_ref.metadata.fetch("book_id"),
          urn: document_ref.id,
          language: "chu",
          title: document_ref.metadata["title"]
        )
      end

      # Download the four manuscript files via FileFetch (conditional GET,
      # sha pin, attic + guard contract each), two-phase so the breaker sees
      # the union of doomed paths before any tree mutation. Returns a
      # Nabu::FetchReport with a per-file url=>sha map in +repos+. No network
      # in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each_value(&:prepare!)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        report(fetches)
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "ccmh fetch failed into #{workdir}: #{e.message}"
      end

      private

      def document_refs(workdir)
        parser = CcmhCesParser.new
        MANUSCRIPTS.flat_map do |slug, display|
          path = Dir.glob(File.join(workdir, "**", "#{slug}.xml")).min
          next [] unless path

          parser.books(path).map do |book|
            Nabu::DocumentRef.new(
              source_id: manifest.id,
              id: "urn:nabu:ccmh:#{slug}:#{book.code.downcase}",
              path: File.expand_path(path),
              metadata: { "book_id" => book.id, "language" => "chu",
                          "title" => "#{display} — #{BOOK_TITLES.fetch(book.code, book.code)}" }
            )
          end
        end
      end

      def file_fetches(workdir, progress)
        MANUSCRIPTS.keys.to_h do |slug|
          [slug, Nabu::FileFetch.new(
            url: self.class.file_url(slug), dir: File.join(workdir, slug),
            filename: "#{slug}.xml",
            attic_dir: File.join(workdir, ATTIC_DIRNAME, slug), progress: progress
          )]
        end
      end

      def report(fetches)
        shas = fetches.transform_values(&:sha)
        Nabu::FetchReport.new(
          sha: shas.values.last, fetched_at: Time.now,
          notes: attic_notes(fetches.values.flat_map(&:atticked)),
          repos: shas.transform_keys { |slug| self.class.file_url(slug) }
        )
      end
    end
  end
end
