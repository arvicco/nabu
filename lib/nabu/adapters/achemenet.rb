# frozen_string_literal: true

require_relative "baby_conllu_parser"
require_relative "../zip_fetch"

module Nabu
  module Adapters
    # Achemenet Babylonian (P77-r18, №R-33 PKG-1): the Helsinki
    # "Linguistically Annotated Achemenet Babylonian Texts" — 2,830
    # Achaemenid-period (550–330 BCE) legal/administrative texts and
    # letters (the CT55, Bēl-rēmanni, Murašû, Strassmaier and YOS7
    # publication groups), the December-2020 Achemenet snapshot converted
    # to Oracc ATF and lemmatized with BabyLemmatizer (Alstola, Sahala,
    # Valk & Ong; Zenodo 19067652, CC BY 4.0 per the deposit page — the
    # in-zip Readme carries no license line, the deposit is the grant's
    # authority, read 2026-08-17).
    #
    # Document = one text block (`# P261571 = Murašu BE 9, 2`): urn
    # urn:nabu:achemenet:p261571 — the id lowercased, MATCHING the cdli
    # urn convention so the shared P-number space is a future crosswalk
    # join for free (X-ids are Helsinki-local placeholders for texts with
    # no CDLI entry — real upstream ids, same lane). Passage = the whole
    # text (:1): the format carries NO line or sentence grain (tokens
    # only, no blank-line blocks), so one flowing transliteration passage
    # is the honest citation unit; the token layer (form, lemma, POS,
    # English gloss, lemmatizer confidence score) rides annotations.
    #
    # LEMMA TIER: SILVER (sources.yml lemma_tier) — BabyLemmatizer with
    # partial manual correction, upstream's own account; the GLAUx rule.
    class Achemenet < Nabu::Adapter
      LANGUAGE = "akk"

      ARTIFACT_URL = "https://zenodo.org/records/19067652/files/Achemenet.zip"
      ATTIC_DIRNAME = ".attic"

      MANIFEST = Nabu::SourceManifest.new(
        id: "achemenet",
        name: "Achemenet Babylonian — linguistically annotated Achaemenid-period texts (Helsinki)",
        license: "CC-BY-4.0 (the Zenodo deposit's license field, record 19067652 v1.1.1, " \
                 "read 2026-08-17; the in-zip Readme carries no license line)",
        license_class: "attribution",
        upstream_url: "https://zenodo.org/records/19067652",
        parser_family: "baby-conllu",
        credit: "Alstola, Sahala, Valk & Ong (University of Helsinki), Linguistically " \
                "Annotated Achemenet Babylonian Texts, v1.1.1, Zenodo, " \
                "doi:10.5281/zenodo.19067652; texts courtesy of the Achemenet project " \
                "(achemenet.com)"
      )

      def self.manifest
        MANIFEST
      end

      # P79-2: one static Zenodo artifact; the record serves no usable
      # Last-Modified (state records null), so drift rides URL identity —
      # a new deposit version mints a new artifact URL.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "Achemenet.zip", zip_url: ARTIFACT_URL, metadata_url: nil, state_subdir: ""
        )]
      end

      # +zip_fetch_factory+ exists for the tests (a rigged fetch — no
      # network in the suite, ever); no-arg construction stays the
      # registry contract.
      def initialize(zip_fetch_factory: Nabu::ZipFetch.method(:new))
        super()
        @zip_fetch_factory = zip_fetch_factory
      end

      # The clics ZipFetch choreography WHOLE (the 2026-08-18 live-crash
      # lesson: the first sync loaded 2,830 docs then died on the return
      # value — complete! answers a count, the SyncRunner contract wants
      # a FetchReport).
      def fetch(workdir, progress: nil, force: false)
        fetch = @zip_fetch_factory.call(url: ARTIFACT_URL, dir: workdir,
                                        attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: ["Achemenet.zip"])
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "achemenet fetch failed into #{workdir}: #{e.message}"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        corpus_files(workdir).each do |path|
          archive = File.basename(path, ".conllu")
          parsed_docs(path).each do |doc|
            yield Nabu::DocumentRef.new(
              source_id: MANIFEST.id,
              id: "urn:nabu:achemenet:#{doc.id.downcase}",
              path: File.expand_path(path),
              metadata: { "id" => doc.id, "designation" => doc.designation, "archive" => archive }
            )
          end
        end
      end

      # The census: the Readme is a recognized non-corpus file; anything
      # else that is not a .conllu is unrecognized — loud.
      def discovery_skips(workdir)
        strays = Dir.children(workdir).sort
                    .reject { |name| name.end_with?(".conllu") }
                    .reject { |name| name.downcase == "readme.md" || name == ATTIC_DIRNAME || name.start_with?(".") }
        Nabu::Adapter::DiscoverySkips.new(
          unrecognized: strays.size,
          notes: strays.map { |name| "non-corpus file: #{name}" }
        )
      end

      def parse(document_ref)
        doc = parsed_docs(document_ref.path).find { |candidate| candidate.id == document_ref.metadata["id"] }
        raise Nabu::ParseError, "#{document_ref.id}: block #{document_ref.metadata['id']} vanished" if doc.nil?

        if doc.tokens.empty?
          # The Readme's own caveat ("Some texts have zero words") — none
          # in the current snapshot; counted, never quarantined.
          raise Nabu::DocumentSkipped.new("zero words upstream", reason: "zero-word text (upstream caveat)")
        end

        build_document(document_ref, doc)
      end

      private

      def corpus_files(workdir)
        Dir.glob(File.join(workdir, "*.conllu"))
      end

      # One file parsed per call, memoized single-slot: discover and the
      # per-document parse calls walk file by file (the osta tables_for
      # pattern), so the memo hits for every document of the current file.
      def parsed_docs(path)
        expanded = File.expand_path(path)
        return @parsed_docs if @parsed_path == expanded

        @parsed_path = expanded
        @parsed_docs = parser.parse_file(expanded)
      end

      def parser
        @parser ||= BabyConlluParser.new
      end

      def build_document(document_ref, doc)
        meta = document_ref.metadata
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: doc.designation,
          metadata: { "designation" => doc.designation, "archive" => meta["archive"],
                      "cdli_p" => (doc.id if doc.id.start_with?("P")),
                      "facets" => { "archive" => { "value" => meta["archive"] } } }.compact
        )
        text = Nabu::Normalize.nfc(doc.tokens.filter_map { |token| token["form"] }.join(" "))
        document << Nabu::Passage.new(
          urn: "#{document_ref.id}:1", language: LANGUAGE, text: text,
          annotations: { "tokens" => doc.tokens.map { |token| annotation(token) } }, sequence: 0
        )
        document
      end

      # The annotation layer: transliterated form, SILVER lemma, the
      # BabyLemmatizer POS (xpos), the English gloss and the lemmatizer
      # confidence class — nothing invented, absent cells stay absent.
      def annotation(token)
        { "form" => token["form"], "lemma" => token["lemma"], "pos" => token["xpos"],
          "eng" => token["eng"], "score" => token["score"] }.compact
      end
    end
  end
end
