# frozen_string_literal: true

module Nabu
  module Adapters
    # Lo Congrès Occitan news corpus (P80-6): Zenodo record 8411197,
    # "Occitan Corpus from Lo Congrès news v1.0" — sentences from the
    # bilingual locongres.org news site, compiled by Lo Congrès permanent
    # de la lenga occitana (the "Còrpus" project). Six dialect CSVs, one
    # aligned occitan/french sentence pair per line, 5,152 pairs total
    # (censused 2026-08-19: auvern 17, gascon 2,194, lemosin 90, lengadoc
    # 2,658, provenc 157, vivaraup 36).
    #
    # == The line grammar (`lo-congres-csv`, censused over all six files)
    #
    # `§`-separated quadruples, NO header row:
    #
    #   occitan sentence§occitan variety code§french translation§fr
    #
    # Every line has exactly 4 fields; the variety field is constant per
    # file (`oc-<dialect>-grclass`) and the trailing field is always `fr`
    # — both censused, so a deviation is damage (ParseError), never a
    # shrug. The `.csv` extension notwithstanding, this is NOT stdlib-CSV
    # material (no quoting, no headers) — a plain split carries it.
    #
    # == Identity and language (the honest verdict)
    #
    # One document per dialect file (urn:nabu:lo-congres:gascon); passage
    # identity is the 1-based line number in the local canonical file (the
    # tla-hf precedent — upstream ships no sentence ids). Passages are
    # bare `oci` — the registry does not (yet) distinguish Occitan
    # dialects, so the dialect claim stays DELIBERATELY COARSE: upstream's
    # own variety code rides as a document facet (`dialect`, the tla-hf
    # stage precedent), never an invented subtag. French translations are
    # `fra` -fr siblings, line-aligned for Query::Parallel.
    #
    # == License (verbatim, record README.txt, verified 2026-08-19)
    #
    # Record API `license: cc-by-4.0`; README: "The
    # SoftwaresOccitanTranslations corpus is distributed under the
    # Creative Commons Attribution 4.0 License" → class attribution.
    #
    # == fetch / sync policy
    #
    # Six FileFetch single-file syncs over the stable Zenodo download URLs
    # (record-versioned — the cigs pin posture: a new corpus release is a
    # new record URL the owner re-pins), each in its own subdir, two-phase
    # (the tla-hf choreography). ~1.3 MB total.
    class LoCongres < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/8411197"

      MANIFEST = Nabu::SourceManifest.new(
        id: "lo-congres",
        name: "Lo Congrès Occitan news corpus (six dialects, French-aligned)",
        license: "CC BY 4.0 (record README verbatim: \"distributed under the Creative Commons " \
                 "Attribution 4.0 License\"; cite Lo Congrès permanent de la lenga occitana)",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "lo-congres-csv"
      )

      URN_PREFIX = "urn:nabu:lo-congres:"
      SEPARATOR = "§"
      TRANSLATION_LANGUAGE_FIELD = "fr"

      # One dialect per row; iteration order is registry order. Slugs mint
      # the urns (urn:nabu:lo-congres:<slug>[-fr]:<line>); `variety` is
      # upstream's own code, riding as the `dialect` facet raw value.
      DIALECTS = %w[auvern gascon lemosin lengadoc provenc vivaraup].to_h do |slug|
        filename = "oc-#{slug}-grclass_fr.csv"
        [slug, {
          filename: filename,
          variety: "oc-#{slug}-grclass",
          url: "#{RECORD_URL}/files/#{filename}?download=1",
          title: "Lo Congrès news corpus — #{slug} Occitan"
        }.freeze]
      end.freeze

      def self.manifest
        MANIFEST
      end

      # One HEAD per Zenodo file URL against its subdir's FileFetch state
      # (reachability + Last-Modified drift). metadata_url nil: the
      # license lives in the record README, no probe-shaped endpoint.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        DIALECTS.map do |slug, dialect|
          Nabu::Adapter::HttpProbeTarget.new(
            label: dialect.fetch(:filename), zip_url: dialect.fetch(:url), metadata_url: nil,
            state_subdir: slug, state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      # +translations+: when true (the registry row's posture — French
      # coverage is 100%, censused), discover also yields one -fr sibling
      # ref per dialect, parsed from the same file.
      def initialize(translations: false)
        super()
        @translations = translations
      end

      # One DocumentRef per dialect file found (plus -fr siblings when
      # opted in), DIALECTS order. A workdir without a file yields fewer
      # refs (the day-one pre-fetch state); the same walk works under the
      # attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        DIALECTS.each do |slug, dialect|
          path = File.join(workdir, slug, dialect.fetch(:filename))
          next unless File.file?(path)

          refs(slug, dialect, path).each(&block)
        end
      end

      # Originals: one `oci` passage per line — the occitan field, NFC at
      # the boundary. -fr refs (metadata "kind" => "translation") mint one
      # `fra` passage per line, suffix-aligned for Query::Parallel.
      def parse(document_ref)
        slug = document_ref.metadata.fetch("dialect_slug")
        dialect = DIALECTS.fetch(slug)
        translation = document_ref.metadata["kind"] == "translation"
        language = translation ? "fra" : "oci"
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, title: document_ref.metadata["title"],
          canonical_path: document_ref.path,
          metadata: document_metadata(dialect, translation: translation)
        )
        each_pair(document_ref.path, dialect) do |number, occitan, french|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{number}", language: language,
            text: Normalize.nfc(translation ? french : occitan), sequence: number - 1
          )
        end
        raise ParseError, "#{document_ref.path}: no sentence pairs" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download all six files two-phase (the tla-hf FileFetch
      # choreography): all prepare with the live tree untouched, the
      # breaker sees the combined doomed set, then all complete. Report:
      # last fetch's sha (the single-pin convention), per-dialect shas in
      # notes.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each_value(&:prepare!)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.values.last.sha, fetched_at: Time.now,
                              notes: fetch_notes(fetches))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "lo-congres fetch failed into #{workdir}: #{e.message}"
      end

      private

      def refs(slug, dialect, path)
        urn = "#{URN_PREFIX}#{slug}"
        metadata = { "dialect_slug" => slug, "language" => "oci",
                     "title" => dialect.fetch(:title) }
        refs = [Nabu::DocumentRef.new(source_id: manifest.id, id: urn,
                                      path: File.expand_path(path), metadata: metadata)]
        if @translations
          refs << Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{urn}-fr", path: File.expand_path(path),
            metadata: metadata.merge("kind" => "translation", "language" => "fra",
                                     "title" => "#{dialect.fetch(:title)} — French translation")
          )
        end
        refs
      end

      def document_metadata(dialect, translation:)
        value = dialect.fetch(:variety).delete_prefix("oc-").delete_suffix("-grclass")
        metadata = {
          "facets" => { "dialect" => { "value" => value, "raw" => dialect.fetch(:variety) } }
        }
        metadata["kind"] = "translation" if translation
        metadata
      end

      # Stream the `§`-quadruples as [line number, occitan, french].
      # Censused contract: exactly 4 fields, the variety constant per
      # file, the trailing language always `fr` — a deviation is damage.
      def each_pair(path, dialect)
        File.foreach(path, encoding: Encoding::UTF_8).with_index(1) do |line, number|
          fields = line.chomp.split(SEPARATOR, -1)
          check_fields!(fields, dialect, path: path, number: number)
          yield number, fields[0], fields[2]
        end
      end

      def check_fields!(fields, dialect, path:, number:)
        unless fields.length == 4
          raise ParseError, "#{path}: line #{number} has #{fields.length} field(s), expected 4 " \
                            "(occitan§variety§french§fr — upstream format changed?)"
        end
        return if fields[1] == dialect.fetch(:variety) && fields[3] == TRANSLATION_LANGUAGE_FIELD

        raise ParseError, "#{path}: line #{number} carries variety #{fields[1].inspect} / " \
                          "language #{fields[3].inspect}, expected #{dialect.fetch(:variety).inspect} " \
                          "/ \"fr\" (constant per file, censused)"
      end

      def file_fetches(workdir, progress)
        DIALECTS.to_h do |slug, dialect|
          [slug, Nabu::FileFetch.new(
            url: dialect.fetch(:url), dir: File.join(workdir, slug),
            filename: dialect.fetch(:filename),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, slug),
            progress: progress
          )]
        end
      end

      def fetch_notes(fetches)
        shas = fetches.map { |slug, fetch| "#{slug} #{fetch.sha[0, 8]}" }
        [shas.join(" · "), attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end
    end
  end
end
