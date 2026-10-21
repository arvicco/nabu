# frozen_string_literal: true

require_relative "vedaweb_tei_parser"

module Nabu
  module Adapters
    # VedaWeb — the Rigveda research platform of the Cologne Center for
    # eHumanities (vedaweb.uni-koeln.de), its public data
    # github.com/VedaWebProject/vedaweb-data: the whole Rigveda with the
    # University of Zurich's word-by-word morphological annotation (Paul
    # Widmer, Salvatore Scarlata; Lubotsky's text annotated over more than
    # ten years, disambiguated in Cologne against Grassmann's dictionary) —
    # GOLD lemmata (Grassmann headwords) and Leipzig-glossing morphology on
    # all 164,758 words, the metrical strata per pada (Gunkel/Ryan after
    # Arnold), the late-addition flags per stanza and the hymn addressees.
    # The gold Vedic complement to DCS (whose Vedic slice is chapter-grain)
    # and the UD Vedic treebank (a sample). A composition of the
    # `vedaweb-tei` family (VedawebTeiParser).
    #
    # == Delivery grains (censused 2026-10-21) and the document
    #
    # rigveda/TEI/: ten book files rv_book_01…10.tei (222 MB) → 1,028 hymns
    # → 10,552 stanzas → 39,832 padas → 164,758 annotated tokens, plus the
    # corpus header vedaweb_corpus.tei (a teiCorpus: the per-source
    # licensing and bibliography + xi:includes of the books — NO text: a
    # rejected grain, skipped by rule and counted) and the ODD/RNG schema.
    # rigveda/info/ (JSON/CSV exports of the same addressees, strata, stanza
    # properties, lemma matching), rigveda/translations/ (the translations as
    # CSV) and rigveda/external-resources/ (Delbrück/Ludwig/Oldenberg
    # concordances) duplicate or extend the TEI and stay outside the sparse
    # cone. Document = hymn (urn:nabu:vedaweb:rv.<book>.<hymn>, upstream's
    # own hymn div), passage = stanza (<doc>:<stanza>, the standard RV
    # citation 1.1.1), text = the stanza's padas one per line. Reconciliation
    # against upstream's own index (rigveda/info/rv_locations.tsv, 10,552
    # stanza rows): 1,028 hymns / 10,552 stanzas, the canonical Rigveda
    # count including the eleven Vālakhilya hymns (8.49–59).
    #
    # == LICENSE — per layer (vedaweb_corpus.tei teiHeader, re-read verbatim
    # 2026-10-21; the repo README: "Every source on this repository contains
    # a specific CC licence")
    #
    # The sources this adapter reads — zurich ("Rigveda - University of
    # Zurich"), strata, stanza_properties, addressees — each: "Distributed
    # under a Creative Commons Attribution 4.0 International License." →
    # class attribution. Every other layer — the text versions lubotsky,
    # vnh (van Nooten–Holland), aufrecht, padapatha, eichler (Devanāgarī) and
    # all the translations (Geldner, Grassmann, Griffith, Renou,
    # Elizarenkova …) — is "Distributed under a Creative Commons
    # Attribution-NonCommercial-ShareAlike 4.0 International License." and
    # is DELIBERATELY NOT READ: a per-layer license scope, so the gold
    # annotation lane stays attribution-class. Those layers remain in
    # canonical/ (the books carry them); an nc-class sibling lane over them
    # is the recorded future option.
    #
    # == Morphology (the house convention: UD feats for the façade, the
    # upstream record verbatim beside it)
    #
    # Each token: "id" (pada + position, "a_01"), "pada", "form" (surface),
    # "lemma" (the Grassmann headword verbatim — "agní-", "√īḍ- ~ īḷ-"),
    # "lemma_ref" (upstream's lemma id), "gramm" (nominal stem / root /
    # invariable / pronoun), "lgr" (the Leipzig labels verbatim, alternatives
    # "/"-joined) and "feats" (UD Key=Value over FEATS_MAP; an undecided
    # <vAlt> becomes a UD multivalue, Case=Acc,Gen, which matches no
    # single-value query — honest). Mapped onto the façade's vocabulary
    # (conventions §6.1): tense PRS/IPRF/AOR/PRF/PLUPRF/FUT → pres/impf/aor/
    # perf/plup/fut; mood SBJV → sub, INJ → inj, PREC → prec, COND → cnd
    # (labels with no PROIEL/UD-core value keep their own lowercased name
    # rather than a lossy fold — the UD Vedic treebank's INJ→Jus is NOT
    # copied); IMP-si (the si-imperative) → imp; non-finite PTCP/PTCP-ta/
    # PTCP-na/INF/GDV/CVB → VerbForm Part/Inf/Gdv/Conv. Local particle (LP)
    # and secondary conjugation (CAUS/DEN/DES/INT) have no UD feature and
    # ride lgr only.
    #
    # == Metadata
    #
    # Document: book, hymn, grassmann_hymn (upstream's ana — Grassmann's
    # running hymn number, the Vālakhilya counted 1018–1028), the addressee
    # and the poet-family group (English + German, verbatim; facets addressee
    # / collection). Passage: padas (letters), strata per pada ({label,
    # strata}), stanza_properties (Grassmann/Oldenberg/Arnold/Witzel/Wüst
    # late-addition flags, verbatim). The strata are RELATIVE chronology —
    # no absolute date is minted (the dating posture says so).
    #
    # == fetch
    #
    # Sparse GitFetch cone [rigveda/TEI, README.md]. Upstream announced a
    # 2025 data update; last push 2025-06-13 → sync_policy manual.
    class Vedaweb < Nabu::Adapter
      REPO_URL = "https://github.com/VedaWebProject/vedaweb-data"
      SPARSE_PATHS = ["rigveda/TEI", "README.md"].freeze
      TEI_DIR = File.join("rigveda", "TEI")
      BOOK_FILE = /\Arv_book_(\d{2})\.tei\z/
      CORPUS_HEADER = "vedaweb_corpus.tei"
      HYMN_DIV = /<div xml:id="(b(\d+)_h(\d+))" ana="(\d+)" type="hymn">/
      LANGUAGE = "san"
      URN_PREFIX = "urn:nabu:vedaweb:rv."

      LICENSE_BY = "Distributed under a Creative Commons Attribution 4.0 International License."
      LICENSE_NC = "Distributed under a Creative Commons Attribution-NonCommercial-ShareAlike 4.0 " \
                   "International License."

      MANIFEST = Nabu::SourceManifest.new(
        id: "vedaweb",
        name: "VedaWeb — the Rigveda with the University of Zurich morphological annotation " \
              "(Cologne Center for eHumanities)",
        license: "Per-layer CC (vedaweb_corpus.tei teiHeader, verbatim). Read here — the zurich text + " \
                 "annotation, strata, stanza properties and addressees: \"#{LICENSE_BY}\" Credit: VedaWeb, " \
                 "Cologne Center for eHumanities (University of Cologne, DFG); annotation P. Widmer and " \
                 "S. Scarlata (University of Zurich) on A. Lubotsky's text, modified by J. Halfmann, " \
                 "N. Korobzow, A. Casaretto, A. Fischer, P. Coenen; strata D. Gunkel and K. M. Ryan; " \
                 "addressees D. Kölligan. NOT read — the text versions (Lubotsky, van Nooten–Holland, " \
                 "Aufrecht, Padapāṭha, Eichler) and the translations: \"#{LICENSE_NC}\"",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "vedaweb-tei"
      )

      # Leipzig category → [UD feature, {label → UD value}].
      FEATS_MAP = {
        "case" => ["Case", { "NOM" => "Nom", "ACC" => "Acc", "GEN" => "Gen", "DAT" => "Dat", "INS" => "Ins",
                             "ABL" => "Abl", "LOC" => "Loc", "VOC" => "Voc" }],
        "gender" => ["Gender", { "M" => "Masc", "F" => "Fem", "N" => "Neut" }],
        "number" => ["Number", { "SG" => "Sing", "DU" => "Dual", "PL" => "Plur" }],
        "person" => ["Person", { "1" => "1", "2" => "2", "3" => "3" }],
        "tense" => ["Tense", { "PRS" => "Pres", "IPRF" => "Impf", "AOR" => "Aor", "PRF" => "Perf",
                               "PLUPRF" => "Plup", "FUT" => "Fut" }],
        "mood" => ["Mood", { "IND" => "Ind", "IMP" => "Imp", "IMP-si" => "Imp", "OPT" => "Opt", "SBJV" => "Sub",
                             "INJ" => "Inj", "PREC" => "Prec", "COND" => "Cnd" }],
        "voice" => ["Voice", { "ACT" => "Act", "MED" => "Mid", "PASS" => "Pass" }],
        "degree" => ["Degree", { "CMP" => "Cmp", "SUP" => "Sup" }],
        "non-finite" => ["VerbForm", { "PTCP" => "Part", "PTCP-ta" => "Part", "PTCP-na" => "Part", "INF" => "Inf",
                                       "GDV" => "Gdv", "CVB" => "Conv" }]
      }.freeze

      # COND sits under upstream's "tense" category in the TEI although its
      # code table files it as a mood — the label decides, never the slot.
      LABEL_OVERRIDES = { "COND" => %w[Mood Cnd] }.freeze
      private_constant :LABEL_OVERRIDES

      def self.manifest = MANIFEST

      def initialize
        super
        @book = nil
      end

      # One DocumentRef per hymn, in book then hymn order (a cheap line scan
      # of the book files for the hymn divs).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        book_files(workdir).each do |path|
          SourceRead.utf8_file(path, label: "vedaweb").scan(HYMN_DIV) do
            m = Regexp.last_match
            book = m[2].to_i
            hymn = m[3].to_i
            yield Nabu::DocumentRef.new(
              source_id: MANIFEST.id, id: "#{URN_PREFIX}#{book}.#{hymn}", path: File.expand_path(path),
              metadata: { "book" => book, "hymn" => hymn, "hymn_id" => m[1], "grassmann_hymn" => m[4].to_i }
            )
          end
        end
      end

      # vedaweb_corpus.tei is the rejected header grain; any other .tei
      # beside the books is unrecognized.
      def discovery_skips(workdir)
        names = Dir.glob(File.join(workdir, TEI_DIR, "*.tei")).map { |path| File.basename(path) }
        others = names.grep_v(BOOK_FILE)
        header, stray = others.partition { |name| name == CORPUS_HEADER }
        notes = header.map { |name| "#{name} (the teiCorpus header: licensing + bibliography, no text)" }
        notes += stray.map { |name| "unrecognized TEI file beside the books: #{name}" }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: header.size, unrecognized: stray.size, notes: notes)
      end

      def parse(document_ref)
        hymn = hymns_for(document_ref.path)[document_ref.metadata.fetch("hymn_id")]
        raise Nabu::ParseError, "#{document_ref.path}: no hymn #{document_ref.metadata['hymn_id']}" unless hymn

        build_document(hymn, urn: document_ref.id, path: document_ref.path)
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url = REPO_URL

      def book_files(workdir)
        Dir.glob(File.join(workdir, TEI_DIR, "*.tei")).select { |path| File.basename(path).match?(BOOK_FILE) }.sort
      end

      # One book streamed once; only the current book is held (refs arrive
      # in book order).
      def hymns_for(path)
        return @book.last if @book&.first == path

        hymns = VedawebTeiParser.new.each_hymn(path).to_h { |hymn| [hymn.id, hymn] }
        @book = [path, hymns]
        hymns
      end

      def build_document(hymn, urn:, path:)
        document = Nabu::Document.new(
          urn: urn, language: LANGUAGE, canonical_path: path, metadata: document_metadata(hymn),
          title: ["Rigveda #{hymn.book}.#{hymn.number}", hymn.addressee["eng"]].compact.join(" — ")
        )
        hymn.stanzas.each_with_index do |stanza, sequence|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{stanza.number}", language: LANGUAGE, sequence: sequence,
            text: Nabu::Normalize.nfc(stanza.padas.values.join("\n")), annotations: stanza_annotations(stanza)
          )
        end
        document
      end

      def document_metadata(hymn)
        {
          "book" => hymn.book, "hymn" => hymn.number, "grassmann_hymn" => hymn.grassmann,
          "addressee" => hymn.addressee["eng"], "addressee_de" => hymn.addressee["deu"],
          "group" => hymn.group["eng"], "group_de" => hymn.group["deu"], "group_n" => hymn.group["n"]
        }.compact
      end

      def stanza_annotations(stanza)
        annotations = { "padas" => stanza.padas.keys, "tokens" => stanza.tokens.map { |token| token_hash(token) } }
        annotations["strata"] = stanza.strata unless stanza.strata.empty?
        annotations["stanza_properties"] = stanza.properties unless stanza.properties.empty?
        annotations
      end

      def token_hash(token)
        lgr = token.morphosyntax.transform_values { |labels| labels.join("/") }
        feats = feats(token.morphosyntax)
        {
          "id" => token.id, "pada" => token.pada, "form" => token.surface, "lemma" => token.lemma,
          "lemma_ref" => token.lemma_ref, "gramm" => token.gramm,
          "feats" => feats.empty? ? nil : feats, "lgr" => lgr.empty? ? nil : lgr
        }.reject { |_key, value| value.nil? || value == "" }
      end

      # "Case=Acc,Gen|Gender=Masc|…" — UD order (features alphabetical,
      # multivalues alphabetical); unmapped labels contribute nothing.
      def feats(morphosyntax)
        features = Hash.new { |hash, key| hash[key] = [] }
        morphosyntax.each do |category, labels|
          labels.each do |label|
            feature, value = LABEL_OVERRIDES[label] || begin
              name, values = FEATS_MAP[category]
              [name, values&.[](label)]
            end
            features[feature] << value if feature && value
          end
        end
        features.sort.map { |feature, values| "#{feature}=#{values.uniq.sort.join(',')}" }.join("|")
      end
    end
  end
end
