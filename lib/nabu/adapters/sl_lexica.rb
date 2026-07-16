# frozen_string_literal: true

require_relative "zrc_xml_parser"

module Nabu
  module Adapters
    # The sl-lexica adapter (P23-2; docs/clarin-si-survey.md §2): the
    # Slovenian historical dictionary shelf — three ZRC SAZU dictionary
    # deposits on CLARIN.SI, ingested as ONE source with three dictionaries
    # (the lexica LSJ/L&S precedent; census verdict journaled in
    # docs/backlog.md P23-2 — identical verbatim license, same publisher
    # conventions, same fetch shape, so no per-artifact split):
    #
    #   pletersnik (sl) — Pleteršnik, Slovenian–German dictionary 1894–95:
    #              103,185 entries; toneme-accented headwords, German
    #              glosses, dialect/place tags, source-authority sigla,
    #              etymology zones. The natural `define` target for every
    #              goo300k gold lemma.
    #   jsv        (sl) — Slovar jezika Janeza Svetokriškega: 8,461 entries
    #              (the deposit description says 8,540 — the counted delta
    #              is upstream reality) over the 233 sermons of Sacrum
    #              promptuarium (1691–1707); verbatim Baroque quotes with
    #              volume/page citations, loanword etymologies.
    #   besedje16  (sl) — Words of the 16th-Century Slovenian Literary
    #              Language: 27,759 entries, the complete word inventory of
    #              1550–1603 Slovenian print with per-word attestation
    #              sigla (TA 1550 … DB 1584 = Dalmatin's Biblia, held as
    #              goo300k/IMP zrc_00001-1584).
    #
    # == Language (censused, decided, journaled)
    #
    # One honest code: sl. All three dictionaries head their entries in
    # MODERNIZED orthography (JSV and besedje16 modernize by editorial
    # design; Pleteršnik's <ge> is the unaccented standard form), which is
    # exactly what goo300k's gold lemmas speak — a period subtag would
    # fracture the define/gloss joins for no gain. The period lives in the
    # dictionary titles and the sl language note.
    #
    # == License
    #
    # CC BY 4.0, verified verbatim at fetch time (2026-07-15) from all
    # three DSpace records: dc.rights = "Creative Commons - Attribution 4.0
    # International (CC BY 4.0)", dc.rights.uri =
    # https://creativecommons.org/licenses/by/4.0/, label PUB →
    # license_class "attribution", MCP-safe. See
    # test/fixtures/sl-lexica/README.md for the whole chain.
    #
    # == fetch / sync policy
    #
    # THREE zip bitstreams over HTTPS (Nabu::ZipFetch per dictionary into
    # its own subdir — the ORACC multi-zip recipe on the goo300k CLARIN.SI
    # URL pattern). The deposits are frozen 2015/2017 uploads →
    # sync_policy: manual, enabled: false until the owner-fired first real
    # sync. The probe HEADs each zip; no probe-shaped license endpoint
    # exists (the grant lives on the record pages), so the probe's license
    # row honestly reads unchecked.
    class SlLexica < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "sl-lexica",
        name: "sl-lexica — Slovenian historical dictionary shelf (ZRC SAZU / CLARIN.SI)",
        license: "CC BY 4.0 (verbatim dc.rights of all three CLARIN.SI records — hdl 11356/1114 " \
                 "Pleteršnik, 11356/1092 JSV, 11356/1127 besedje16: \"Creative Commons - " \
                 "Attribution 4.0 International (CC BY 4.0)\"; ZRC SAZU, Inštitut za slovenski " \
                 "jezik Frana Ramovša)",
        license_class: "attribution",
        upstream_url: "https://www.clarin.si/repository/xmlui",
        parser_family: "zrc-xml"
      )

      LANGUAGE = "sl"

      # The three dictionaries, keyed by dictionary slug, in registry (=
      # discover) order. Each is one deposit zip carrying one XML + its XSD.
      DICTIONARIES = {
        "pletersnik" => {
          file: "Pletersnik.xml",
          title: "Slovensko-nemški slovar (Pleteršnik, 1894–1895)",
          zip_url: "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1114/Pletersnik.zip"
        }.freeze,
        "jsv" => {
          file: "JSV.xml",
          title: "Slovar jezika Janeza Svetokriškega (Sacrum promptuarium, 1691–1707)",
          zip_url: "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1092/JSV.zip"
        }.freeze,
        "besedje16" => {
          file: "besedje16.xml",
          title: "Besedje slovenskega knjižnega jezika 16. stoletja " \
                 "(Words of the 16th-Century Slovenian Literary Language, 1550–1603)",
          zip_url: "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1127/besedje16.zip"
        }.freeze
      }.freeze

      # The language-notes rider (P18-6 pattern): one witness note on sl,
      # accreted idempotently by the DictionaryLoader at every load.
      LANGUAGE_NOTES = [
        ["sl", "witness:sl-lexica",
         "The Slovenian historical dictionary shelf (ZRC SAZU / CLARIN.SI, all CC BY 4.0): " \
         "Pleteršnik's Slovenian–German dictionary (1894–95; 103,185 entries — toneme-accented " \
         "headwords, German glosses, dialect and source-authority tags, 16th-c.-onward lexis), " \
         "the dictionary of Janez Svetokriški's language (8,461 entries over the Sacrum " \
         "promptuarium sermons, 1691–1707 — verbatim Baroque quotes, volume/page citations, " \
         "loanword etymologies), and Besedje 16 (27,759 entries — the complete word inventory " \
         "of 1550–1603 Slovenian print with per-word attestation sigla; DB 1584 is Dalmatin's " \
         "Biblia, held as goo300k/IMP zrc_00001-1584). Headwords are modernized orthography and " \
         "join goo300k's gold lemmas through the conventions §9 sl fold."].freeze
      ].freeze

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # [lang_code, kind, body] rows for the language-notes rider.
      def self.language_notes = LANGUAGE_NOTES

      # The probe HEADs each zip bitstream: reachability + Last-Modified
      # drift vs the per-dictionary .zip-fetch.json pin. metadata_url nil —
      # see class note.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        DICTIONARIES.map do |slug, config|
          Nabu::Adapter::HttpProbeTarget.new(
            label: File.basename(config.fetch(:zip_url)), zip_url: config.fetch(:zip_url),
            metadata_url: nil, state_subdir: slug, state_file: Nabu::ZipFetch::STATE_FILE
          )
        end
      end

      # One DocumentRef per dictionary file, registry order. A workdir
      # without the files yields nothing (the day-one pre-fetch state); the
      # same walk works under the attic (same relative shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        DICTIONARIES.each do |slug, config|
          Dir.glob(File.join(workdir, "**", config.fetch(:file))).first(1).each do |path|
            yield Nabu::DocumentRef.new(
              source_id: manifest.id,
              id: "#{slug}:#{config.fetch(:file)}",
              path: File.expand_path(path),
              metadata: { "dictionary" => slug }
            )
          end
        end
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: LANGUAGE,
          title: DICTIONARIES.fetch(slug).fetch(:title), canonical_path: document_ref.path
        )
        ZrcXmlParser.new.entries(document_ref.path, dictionary: slug).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "sl-lexica: #{document_ref.id}: #{e.message}"
      end

      # Download + unpack the three upstream zips via ZipFetch (conditional
      # GET on Last-Modified, sha256 pin, staging, attic + mass-deletion
      # guard — each dictionary in its own subdir with its own state). No
      # network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        results = DICTIONARIES.to_h do |slug, config|
          dir = File.join(workdir, slug)
          [slug, Nabu::ZipFetch.sync!(
            url: config.fetch(:zip_url), dir: dir,
            attic_dir: File.join(workdir, ATTIC_DIRNAME, slug), progress: progress,
            guard: ->(doomed) { guard_mass_deletion!(dir, doomed, force: force) }
          )]
        end
        report(results)
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "sl-lexica fetch failed into #{workdir}: #{e.message}"
      end

      private

      def report(results)
        notes = results.map { |slug, result| "#{slug}=#{result.sha[0, 12]}" }.join(" ")
        atticked = results.values.sum { |result| result.atticked.size }
        notes = "#{notes} · #{attic_notes(atticked_list(results))}" if atticked.positive?
        Nabu::FetchReport.new(
          sha: results.values.last.sha, fetched_at: Time.now, notes: notes,
          repos: results.to_h { |slug, result| [DICTIONARIES.fetch(slug).fetch(:zip_url), result.sha] }
        )
      end

      def atticked_list(results)
        results.values.flat_map(&:atticked)
      end
    end
  end
end
