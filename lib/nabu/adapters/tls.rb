# frozen_string_literal: true

require_relative "tls_xml_parser"

module Nabu
  module Adapters
    # TLS — Thesaurus Linguae Sericae (P33-4): Christian Harbsmeier's
    # historical-comparative encyclopaedia of Classical Chinese, from the
    # tls-kr/tls-data eXist-db repo. content_kind :dictionary, parser
    # family tls-xml, ONE source / TWO dictionaries (the hebrew-lexicon
    # grain) — the first ONOMASIOLOGICAL occupant of the dictionary shelf:
    #
    # - "tls-concepts" — the concept net: 3,018 English-named concepts
    #   (definition, synonym-group criteria notes, hypernymy/taxonymy/
    #   antonymy/see pointer lines with urn:nabu:dict:tls-concepts:<uuid>
    #   targets, source references) with the member-word list INVERTED into
    #   each body from the words side (upstream keeps the words slot empty
    #   on 3,018 of 3,019 files and tags membership on word entries).
    # - "tls-words" — the word lexicon: 20,163 superEntry words (och),
    #   each body carrying its word-x-concept entry blocks (34,808 — every
    #   one names its concept + concept urn), pinyin/OC/MC readings and
    #   60,232 sense lines with their upstream uuids verbatim (the join
    #   keys the deferred attestation crosswalk will need).
    #
    # Both shelves register och (Old Chinese — the object language; concept
    # heads are English metalanguage labels, the wiktionary-recon
    # pseudo-language precedent for "the shelf speaks its members'
    # language"). No reflexes (concept membership is onomasiological, not
    # etymological — dictionary_reflexes would pollute etym/cognates), no
    # citations (TLS attestations are seg-id-shaped, not CTS; 111,484
    # tls:ann rows live in notes/doc + notes/swl OUTSIDE the fetch cone) —
    # both recorded in 02-sources row 106, neither silently claimed.
    #
    # == Fetch: sparse GitFetch cone
    #
    # tls-data whole is ~4.7 GB / 161,357 files (translations 2.3 GB,
    # notes/search 69,050 cached search dumps, statistics 222 MB…). The
    # cone is ["concepts", "words"] (~112 MB working tree) — the two
    # ingested dirs; root files (LICENSE.md) ride along per git's cone
    # rules. The rest of the repo is censused in 02-sources row 106, not
    # fetched.
    #
    # == License
    #
    # LICENSE.md, verbatim first line: "# Creative Commons
    # Attribution-ShareAlike 4.0 International License (CC BY-SA 4.0)" —
    # sha256-identical in tls-texts and tls-data (verified 2026-07-20) →
    # attribution class (the lexica CC BY-SA precedent). HONESTY NOTE: both
    # repos' README badges claim CC BY 4.0 instead; the LICENSE.md grant is
    # the stricter and authoritative statement, recorded as BY-SA.
    class Tls < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "tls",
        name: "TLS — Thesaurus Linguae Sericae (tls-kr/tls-data: concepts + words)",
        license: "CC BY-SA 4.0 (LICENSE.md verbatim: \"This work is licensed under the Creative Commons " \
                 "Attribution-ShareAlike 4.0 International License.\" — sha256-identical in tls-texts and " \
                 "tls-data, 2026-07-20; both READMEs' CC BY 4.0 badges recorded as a discrepancy, the " \
                 "LICENSE.md grant governs)",
        license_class: "attribution",
        upstream_url: "https://github.com/tls-kr/tls-data",
        parser_family: "tls-xml"
      )

      # The sparse-checkout cone (P26-0 GitFetch): only the ingested dirs'
      # blobs come down; everything else stays upstream. P34-4 widened the
      # cone with the attestation lane (notes/doc 138 MB + notes/swl 191 MB
      # measured 2026-07-20 — one `<textid>-ann.xml` per attested text;
      # notes/search's 69,050 cached dumps stay excluded); GitFetch widens
      # an existing checkout's cone on the next pull.
      SPARSE_PATHS = %w[concepts words notes/doc notes/swl].freeze

      # The two dictionaries this source carries. :dir anchors discover;
      # the concepts parse reads the words dir as a sibling (the
      # hebrew-lexicon cross-file precedent) to invert membership.
      DICTIONARIES = {
        "tls-concepts" => {
          title: "TLS concepts — the onomasiological net (Thesaurus Linguae Sericae)",
          dir: "concepts"
        },
        "tls-words" => {
          title: "TLS words — Classical Chinese synonym lexicon (Thesaurus Linguae Sericae)",
          dir: "words"
        }
      }.freeze

      LANGUAGE = Adapters::TlsXmlParser::LANGUAGE

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # One DocumentRef per dictionary, anchored at its DIRECTORY (each
      # parse walks the small per-record files under it — 3,019 / 20,163;
      # the whole dictionary is the honest revision unit). Same shapes
      # recur under the attic, so retention costs nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        DICTIONARIES.filter_map do |slug, config|
          dir = File.join(workdir, config.fetch(:dir))
          next unless Dir.exist?(dir) && !Dir.glob(File.join(dir, "**", "*.xml")).empty?

          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{slug}:#{config.fetch(:dir)}",
            path: File.expand_path(dir),
            metadata: { "dictionary" => slug }
          )
        end.sort_by(&:id).each(&block)
      end

      # The two known upstream strays, skipped BY RULE and censused here so
      # the gap can never hide (P11-7): the percent-encoded concept
      # basename duplicating CRONY.xml's uuid, and the empty-orth
      # superEntry aggregate.
      def discovery_skips(workdir)
        parser = Adapters::TlsXmlParser.new
        notes = []
        concepts = Dir.glob(File.join(workdir, "concepts", "*.xml"))
                      .select { |path| parser.skipped_concept_basename?(File.basename(path)) }
        notes.concat(concepts.map { |path| "concept stray (percent-encoded basename): #{File.basename(path)}" })
        words = Dir.glob(File.join(workdir, "words", "*", "*.xml"))
                   .select { |path| parser.skipped_word_file?(path) }
        notes.concat(words.map { |path| "empty-orth superEntry aggregate: #{File.basename(path)}" })
        DiscoverySkips.new(skipped_by_rule: concepts.size + words.size, notes: notes)
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        config = DICTIONARIES.fetch(slug)
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: LANGUAGE,
          title: config.fetch(:title), canonical_path: document_ref.path
        )
        entries_for(slug, document_ref).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "tls: #{document_ref.id}: #{e.message}"
      end

      # Sparse clone / non-destructive pull via the shared git path
      # (GitFetch: cone, attic, pre-merge mass-deletion breaker).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      private

      # Split out so fetch tests can point a singleton at a local git
      # tmpdir (the house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end

      def entries_for(slug, document_ref)
        parser = Adapters::TlsXmlParser.new
        if slug == "tls-words"
          # The attestation lane (P34-4) reads notes/ as a sibling of the
          # words dir — the member_index cross-file precedent. No notes on
          # disk (pre-widening checkouts, attic partials) = an honest
          # citation-free parse.
          notes_dir = File.join(File.dirname(document_ref.path), "notes")
          attestations = Dir.exist?(notes_dir) ? parser.attestation_index(notes_dir) : nil
          return parser.word_entries(document_ref.path, attestations: attestations)
        end

        words_dir = File.join(File.dirname(document_ref.path), DICTIONARIES.fetch("tls-words").fetch(:dir))
        members = Dir.exist?(words_dir) ? parser.member_index(words_dir) : nil
        parser.concept_entries(document_ref.path, members: members)
      end
    end
  end
end
