# frozen_string_literal: true

module Nabu
  module Adapters
    # The CCMH adapter (P13-2 + P14-5): the Corpus Cyrillo-Methodianum
    # Helsingiense (University of Helsinki 1986-2017, distributed by
    # Kielipankki / the Language Bank of Finland) — the whole seven-text
    # corpus, two parser families under one source. The four gospel
    # manuscripts arrive as the corpus's own CES XML (ccmh-ces): Codex
    # Assemanianus and Savvina kniga (absent from every other holding —
    # P13-2's two prizes) plus Codex Marianus and Codex Zographensis as
    # ALTERNATIVE EDITIONS of the PROIEL/TOROT witnesses. The three
    # txt-only texts (P14-5, ccmh-txt / CcmhTxtParser): Codex
    # Suprasliensis at diplomatic folio-line grain — an ALTERNATIVE
    # EDITION of TOROT's Suprasliensis (Helsinki transliteration of
    # Severjanov's print edition vs the treebank text; the richer
    # obdurodon edition stays queued, 02-sources row 30) — and the Vitae
    # Constantini/Methodii at chapter-verse grain (new to the holdings).
    # Two editions of a work are two versions, never a dedupe
    # (conventions §3).
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
    # The txt texts (P14-5): one document per file. urn:nabu:ccmh:
    # suprasliensis, passages :<part>.<folium>.<side>.<line> (the file's
    # own Severjanov line codes, zero-padding stripped, the side digit
    # raw); urn:nabu:ccmh:vita-constantini / :vita-methodii, passages
    # :<chapter>.<verse>. The upstream file stems vita_constantini/
    # vita_methodii take nabu's hyphenated urn-slug form (the same
    # slugification the UD adapter applies to repo names); fetch keys and
    # subdirs keep the literal stems.
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
    # Seven per-text FileFetch targets (the ASPR path), one subdir each:
    # FileFetch keeps ONE state file per dir and dooms unrecognized
    # siblings, so the files must not share a directory. ORACC's two-phase
    # shape aggregates them: prepare all seven, run the mass-deletion
    # breaker once over the union, then complete — no partial tree on a
    # guard trip. Upstream is a plain HTTPS file tree (no git, no zip
    # endpoint worth the indirection; the -src zip exists but the per-file
    # URLs are the stable browse surface). Effectively frozen since 2021 →
    # sync_policy: manual.
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
      # parser_family above stays the founding "ccmh-ces" label — the field
      # is descriptive, not a dispatch key (goo300k reuses imp-tei, vulgate/
      # eng-web share usfx); the txt texts are the ccmh-txt family, see
      # CcmhTxtParser and docs/02-sources.md row 19.

      # The P13-2 v1 scope (OWNER-APPROVED 2026-07-11): the four gospel
      # manuscripts — the ones upstream encodes as CES XML. Alphabetical;
      # display names are the forms scholars cite.
      MANUSCRIPTS = {
        "assemanianus" => "Codex Assemanianus",
        "marianus" => "Codex Marianus",
        "savvina" => "Savvina kniga",
        "zographensis" => "Codex Zographensis"
      }.freeze

      # The P14-5 completion (OWNER-APPROVED 2026-07-12, line grain +
      # split-word mechanics): the three txt-only texts, keyed by the
      # literal upstream file stem.
      TXT_TEXTS = {
        "suprasliensis" => { "urn" => "urn:nabu:ccmh:suprasliensis",
                             "title" => "Codex Suprasliensis", "scheme" => "folio-line" },
        "vita_constantini" => { "urn" => "urn:nabu:ccmh:vita-constantini",
                                "title" => "Vita Constantini", "scheme" => "chapter-verse" },
        "vita_methodii" => { "urn" => "urn:nabu:ccmh:vita-methodii",
                             "title" => "Vita Methodii", "scheme" => "chapter-verse" }
      }.freeze

      # slug => upstream filename, gospels first (the P13-2 order), then
      # the txt texts — the one list fetch, probe and discover all walk.
      FILES = MANUSCRIPTS.keys.to_h { |slug| [slug, "#{slug}.xml"] }
                              .merge(TXT_TEXTS.keys.to_h { |slug| [slug, "#{slug}.txt"] }).freeze

      BOOK_TITLES = { "MAT" => "Matthew", "MAR" => "Mark", "LUK" => "Luke", "JOH" => "John" }.freeze

      def self.manifest
        MANIFEST
      end

      # The probe HEADs each file: reachability + Last-Modified drift vs
      # the per-subdir .file-fetch.json pin. metadata_url nil: the license
      # lives in the bundle README, re-read at fixture refresh, not at an
      # endpoint.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        FILES.map do |slug, filename|
          Nabu::Adapter::HttpProbeTarget.new(
            label: filename, zip_url: file_url(slug), metadata_url: nil,
            state_subdir: slug, state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      def self.file_url(slug)
        "#{BASE_URL}/#{FILES.fetch(slug)}"
      end

      # One DocumentRef per (manuscript, gospel book) — manuscripts in
      # MANUSCRIPTS order, books in file order (canonical gospel order) —
      # then one per txt text (TXT_TEXTS order), appended so the P13-2
      # documents keep their positions. Returns an Enumerator without a
      # block (the adapter contract's lazy shape). A workdir without the
      # files yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        (document_refs(workdir) + txt_document_refs(workdir)).each(&block)
      end

      # Dispatch by file extension: .txt is the ccmh-txt family, .xml the
      # ccmh-ces family (parser_family is a label, the extension is the
      # ground truth of which parser reads the bytes).
      def parse(document_ref)
        if document_ref.path.end_with?(".txt")
          CcmhTxtParser.new.parse(
            document_ref.path,
            scheme: document_ref.metadata.fetch("scheme"),
            urn: document_ref.id, language: "chu",
            title: document_ref.metadata["title"]
          )
        else
          CcmhCesParser.new.parse(
            document_ref.path,
            book_id: document_ref.metadata.fetch("book_id"),
            urn: document_ref.id, language: "chu",
            title: document_ref.metadata["title"]
          )
        end
      end

      # Download the seven corpus files via FileFetch (conditional GET,
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
          path = find_file(workdir, slug)
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

      def txt_document_refs(workdir)
        TXT_TEXTS.filter_map do |slug, text|
          path = find_file(workdir, slug)
          next unless path

          Nabu::DocumentRef.new(
            source_id: manifest.id, id: text.fetch("urn"), path: File.expand_path(path),
            metadata: { "scheme" => text.fetch("scheme"), "language" => "chu",
                        "title" => text.fetch("title") }
          )
        end
      end

      def find_file(workdir, slug)
        Dir.glob(File.join(workdir, "**", FILES.fetch(slug))).min
      end

      def file_fetches(workdir, progress)
        FILES.to_h do |slug, filename|
          [slug, Nabu::FileFetch.new(
            url: self.class.file_url(slug), dir: File.join(workdir, slug),
            filename: filename,
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
