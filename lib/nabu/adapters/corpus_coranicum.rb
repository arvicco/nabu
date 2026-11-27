# frozen_string_literal: true

require_relative "corpus_coranicum_cairo_parser"
require_relative "corpus_coranicum_concordance_parser"

module Nabu
  module Adapters
    # Corpus Coranicum — the TEI export of the Berlin-Brandenburg Academy's
    # Qurʾān project (2007–2024; github.com/telota/corpus-coranicum-tei,
    # one commit, 57cb2b7 of 2024-12-20, the project closed): the Cairo
    # 1924 vocalized text (the King Fuʾād edition, Ḥafṣ ʿan ʿĀṣim, the
    # project's reference text) as the documents, and Rafael Talmon's
    # concordance as the project edited it — a grammatical parse of every
    # word — as their word layer. Composes the corpus-coranicum-tei family
    # (CorpusCoranicumCairoParser, CorpusCoranicumConcordanceParser).
    #
    # == License (README, read first-hand 2026-11-27)
    #
    # "## Licence / © Berlin-Brandenburgische Akademie der Wissenschaften
    # 2024 / Creative Commons CC BY-SA 4.0
    # https://creativecommons.org/licenses/by-sa/4.0/" → attribution,
    # share-alike noted. The data files carry no licence of their own. The
    # README's citation: "Corpus Coranicum Project, ed. Michael Marx. TEI
    # Data. Berlin-Brandenburg Academy of Sciences and Humanities."
    #
    # == Delivery grains (enumerated at the pinned commit, 2026-11-27)
    #
    # data/ holds 3,240 files in six directories (the README's own list):
    # - cairo_quran/cairoquran.xml (17.5 MB) — ACCEPTED: one document per
    #   sura (114), one passage per verse (6,236). Inside the same file and
    #   NOT taken: the word-by-word Latin transcription div (it restates
    #   the concordance's word_corpus_coranicum per word) and the English,
    #   German and French translation divs (modern translations under
    #   their own rights, beside the edition; a later packet reads their
    #   provenance before any of them is carried).
    # - quran_concordance/suraNNN.xml (114 files, 197.5 MB) — ACCEPTED as
    #   the word layer of sura NNN; never documents of their own. A file
    #   naming a sura the Cairo text lacks is unrecognized (loud).
    # - quran_commentary/ (85 files: the chronological literary-critical
    #   commentary by sura), quran_intertexts/ (714: 713 intertext records
    #   + categories.xml), quran_manuscripts/ (2,323: 2,322 manuscript
    #   descriptions + places.xml), quran_variants/ (3: allvariants.xml and
    #   its reader/source authority files) — REJECTED for this source, each
    #   its own later packet: skipped by rule, one note per directory with
    #   its file count.
    # Anything else under data/ is unrecognized. schema/ (the ODD + RNG)
    # and the README are documentation, outside the census; the attic and
    # dot-paths are infrastructure.
    #
    # == Count reconciliation (census of the pinned clone, 2026-11-27)
    #
    # 114 suras / 6,236 verses / 77,432 words in the arabic text; 91,285
    # concordance rows over exactly 77,432 distinct (sura, verse, word)
    # keys — every Cairo word has its rows and every row its Cairo word,
    # residue 0 both ways. 11,938 words carry more than one analysis (up
    # to 16). Expected first sync: 114 documents / 6,236 passages / 77,432
    # tokens; 3,125 files skipped by rule (85 + 714 + 2,323 + 3), 0
    # unrecognized: 1 + 114 + 3,125 = 3,240, the whole data/ tree.
    #
    # == Identity
    #
    # Document urn:nabu:corpus-coranicum:sura-002 (upstream's own lg
    # xml:id), passage <doc>:2.255 — the sura.verse citation (Q 2:255),
    # the house chapter.verse tail. Verse numbering is the Cairo edition's
    # (the Kufan count; the basmala is verse 1 of sura 1 only).
    #
    # == Text
    #
    # The verse = its <w> forms single-space joined, verbatim: the Cairo
    # orthography with its Qurʾānic annotation signs (small high marks,
    # pause signs on the word they follow) as upstream encodes them, NFC
    # at the adapter boundary. NFC MEASURED: it changes 7 of the 77,432
    # words, all canonically equivalent rewrites — six write shadda BEFORE
    # its vowel (U+0651 U+064E / U+064B), which NFC reorders vowel-first
    # (2:143:16, 9:83:17, 11:80:3, 17:12:15, 33:61:1, 36:36:6), and one
    # writes alef + combining maddah (U+0627 U+0653), which NFC composes to
    # آ U+0622 (6:42:8). Everywhere else the text is already NFC. The
    # verse's facsimile page (the surface range covering it) rides the
    # passage annotations as "page".
    #
    # == Word layer (annotations["tokens"], the house token contract)
    #
    # One token per Cairo word, joined on (sura, verse, word number) =
    # the word's xml:id: "id" (w-002-255-001), "form" (the Arabic word),
    # then the FIRST analysis flattened (the ceipom shape): "translit"
    # (word_corpus_coranicum, the project's transcription), "lemma"
    # (base_corpus_coranicum — the lemma index's key, a transliterated
    # base: llāh, raḥmān), "root" (root_corpus_coranicum verbatim, rḥm —
    # never converted to Arabic script; a pronoun suffix's "root" is the
    # suffix itself, -hum, as upstream gives it), "pos"
    # (analyse_part_of_speech), Talmon's own ASCII columns verbatim
    # (word_/base_/root_rafi_talmon: rHm), "analysis" (analysis_number),
    # and every other analyse_* field under its name less the prefix
    # (pattern, aspect, actpass, mortality, mood, gender, number, casefld,
    # person, definite, diptotic, subcategory, semantic, semantic2, the
    # prefix1–3 and dependent_* fields, full_analyse). Empty fields are
    # omitted. Further analyses ride "alternatives" (the same keys). Not
    # kept: sura/verse/word_number (the join key, restated by "id"),
    # created_at/updated_at (database bookkeeping), and analyse_prefix
    # wherever it equals analyse_prefix1 (all 91,285 rows). The fields
    # decode as morph facets through the Query::MorphFacets corpus-coranicum
    # row (`search --lemma <base> --morph …`); `search --lemma` reads the
    # transliterated base.
    #
    # == fetch
    #
    # GitFetch (attic + mass-deletion breaker), the whole tree (the
    # rejected grains are later packets of this same repository), PINNED:
    # the repo is one frozen commit, so a moved HEAD is an event to review
    # (license + text), never a cadence — the fetch aborts loudly on drift.
    # A git checkout's identity is its HEAD; nothing is materialized
    # beside upstream's tree.
    class CorpusCoranicum < Nabu::Adapter
      REPO_URL = "https://github.com/telota/corpus-coranicum-tei"

      # The repository's only commit ("Initial commit", 2024-12-20).
      PINNED_SHA = "57cb2b7be321ecfba100cb5f7988974f47864a14"

      CITATION = "Corpus Coranicum Project, ed. Michael Marx. TEI Data. Berlin-Brandenburg Academy of " \
                 "Sciences and Humanities. https://github.com/telota/corpus-coranicum-tei — the Cairo " \
                 "1924 text and the concordance of Rafael Talmon — CC BY-SA 4.0"

      LICENSE = "CC BY-SA 4.0 — README verbatim: \"© Berlin-Brandenburgische Akademie der Wissenschaften " \
                "2024 / Creative Commons CC BY-SA 4.0 https://creativecommons.org/licenses/by-sa/4.0/\" " \
                "(read 2026-11-27); share-alike. The translations inside cairoquran.xml are not carried"

      MANIFEST = Nabu::SourceManifest.new(
        id: "corpus-coranicum",
        name: "Corpus Coranicum — the Cairo 1924 Qurʾān with the Talmon concordance (BBAW TEI export)",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "corpus-coranicum-tei",
        credit: CITATION
      )

      LANGUAGE = "ara"
      URN_PREFIX = "urn:nabu:corpus-coranicum:"
      WORK = "Qurʾān"
      EDITION = "Cairo 1924 (the King Fuʾād edition, Būlāq/Gīza 1342 AH): Ḥafṣ ʿan ʿĀṣim, rasm ʿuṯmānī"
      EDITION_YEAR = 1924

      CAIRO_FILE = File.join("data", "cairo_quran", "cairoquran.xml")
      CONCORDANCE_DIR = File.join("data", "quran_concordance")
      CONCORDANCE_FILE = /\Asura(\d{3})\.xml\z/

      # The rejected grains (class note): data/ directory => what it holds.
      REJECTED_DIRS = {
        "quran_commentary" => "the chronological literary-critical commentary, one file per sura",
        "quran_intertexts" => "the intertext records (late-antique and earlier parallels) and their categories",
        "quran_manuscripts" => "the manuscript descriptions and their places authority file",
        "quran_variants" => "the variant readings and their reader/source authority files"
      }.freeze

      # Concordance seg types that never reach a token (class note).
      DROPPED = %w[sura verse word_number created_at updated_at].freeze

      # Seg type => token key where the key is not the seg's own name
      # less "analyse_".
      RENAMED = {
        "word_corpus_coranicum" => "translit", "base_corpus_coranicum" => "lemma",
        "root_corpus_coranicum" => "root", "analyse_part_of_speech" => "pos", "analysis_number" => "analysis"
      }.freeze

      def self.manifest = MANIFEST

      # +repo_url+/+pinned_sha+ exist for the tests (local upstream repos);
      # no-arg construction stays the registry contract.
      def initialize(repo_url: REPO_URL, pinned_sha: PINNED_SHA)
        super()
        @repo_url = repo_url
        @pinned_sha = pinned_sha
      end

      # One ref per sura of the Cairo text, in sura order (= urn order).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.expand_path(File.join(workdir, CAIRO_FILE))
        return unless File.file?(path)

        cairo(path).each_key do |sura|
          yield Nabu::DocumentRef.new(source_id: manifest.id, id: urn_for(sura), path: path,
                                      metadata: { "sura" => sura })
        end
      end

      # The rejected grain directories by rule (one note each); a stray
      # data file or a concordance file naming no Cairo sura is loud.
      def discovery_skips(workdir)
        root = File.expand_path(workdir)
        suras = File.file?(File.join(root, CAIRO_FILE)) ? cairo(File.join(root, CAIRO_FILE)).keys : []
        rejected = Hash.new(0)
        unknown = []
        data_files(root).each do |rel|
          parts = rel.split("/")
          if REJECTED_DIRS.key?(parts[1]) && parts.size > 2
            rejected[parts[1]] += 1
          elsif (why = unrecognized(rel, suras))
            unknown << "#{rel}: #{why}"
          end
        end
        notes = rejected.sort.map do |dir, count|
          "data/#{dir}/: #{count} file#{'s' unless count == 1} skipped by rule — #{REJECTED_DIRS.fetch(dir)}"
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: rejected.values.sum, unrecognized: unknown.size,
                                          notes: notes + unknown)
      end

      def parse(document_ref)
        sura = document_ref.metadata.fetch("sura")
        verses = cairo(document_ref.path).fetch(sura) do
          raise Nabu::ParseError, "#{document_ref.path}: no sura #{sura} in the Cairo text"
        end
        analyses = concordance(document_ref.path, sura, verses)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: "#{WORK} — Sura #{sura}",
          canonical_path: document_ref.path, metadata: document_metadata(sura, verses)
        )
        verses.each_with_index { |verse, sequence| document << passage(document_ref.id, verse, analyses, sequence) }
        document
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "corpus-coranicum #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        report = git_fetch!(repo_url: @repo_url, workdir: workdir, progress: progress, force: force)
        return report if report.sha == @pinned_sha

        raise Nabu::FetchError,
              "#{manifest.id}: upstream #{@repo_url} is at #{report.sha[0, 12]}, but the source is pinned " \
              "to #{@pinned_sha[0, 12]} — review the new commits (license + text) and re-pin (owner " \
              "decision; the project is closed, so drift is an event, not a cadence)"
      end

      private

      def urn_for(sura) = format("%<prefix>ssura-%<sura>03d", prefix: URN_PREFIX, sura: sura)

      # The parsed Cairo text, once per path per adapter instance (114
      # documents share one 17.5 MB file).
      def cairo(path)
        @cairo ||= {}
        @cairo[path] ||= CorpusCoranicumCairoParser.new.suras(path)
      end

      def concordance_path(cairo_path, sura)
        File.join(File.dirname(cairo_path, 3), CONCORDANCE_DIR, format("sura%03d.xml", sura))
      end

      # The sura's analyses, checked exact against its Cairo words both
      # ways (orphan rows first, then words without a row).
      def concordance(cairo_path, sura, verses)
        path = concordance_path(cairo_path, sura)
        raise Nabu::ParseError, "corpus-coranicum: sura #{sura} has no concordance file #{path}" unless File.file?(path)

        rows = CorpusCoranicumConcordanceParser.new.analyses(path, sura: sura)
        words = verses.flat_map { |verse| verse.words.map { |word| [verse.number, word.number] } }
        orphan = (rows.keys - words).first
        raise Nabu::ParseError, "#{path}: concordance row #{sura}:#{orphan.join(':')} has no Cairo word" if orphan

        rows
      end

      def document_metadata(sura, verses)
        { "work" => WORK, "sura" => sura, "edition" => EDITION, "edition_year" => EDITION_YEAR,
          "verses" => verses.size, "words" => verses.sum { |verse| verse.words.size } }
      end

      def passage(doc_urn, verse, analyses, sequence)
        tokens = verse.words.map { |word| token(word, analyses, verse) }
        annotations = { "tokens" => tokens }
        annotations["page"] = verse.page if verse.page
        Nabu::Passage.new(urn: "#{doc_urn}:#{verse.sura}.#{verse.number}", language: LANGUAGE,
                          text: Normalize.nfc(verse.text), annotations: annotations, sequence: sequence)
      end

      def token(word, analyses, verse)
        rows = analyses.fetch([verse.number, word.number]) do
          raise Nabu::ParseError, "corpus-coranicum: word #{word.id} has no concordance analysis"
        end
        token = { "id" => word.id, "form" => Normalize.nfc(word.form) }.merge(analysis_fields(rows.first))
        token["alternatives"] = rows.drop(1).map { |row| analysis_fields(row) } if rows.size > 1
        token
      end

      def analysis_fields(row)
        row.each_with_object({}) do |(seg, value), fields|
          next if value.empty? || DROPPED.include?(seg)
          next if seg == "analyse_prefix" && value == row["analyse_prefix1"]

          fields[RENAMED.fetch(seg) { seg.delete_prefix("analyse_") }] = Normalize.nfc(value)
        end
      end

      # Every non-dot file under data/, workdir-relative, sorted.
      def data_files(root)
        Dir.glob("data/**/*", base: root)
           .select { |rel| File.file?(File.join(root, rel)) }
           .reject { |rel| rel.split("/").any? { |part| part.start_with?(".") } }
           .sort
      end

      # Why a data file outside the rejected dirs is unrecognized, or nil
      # when it is an accepted file.
      def unrecognized(rel, suras)
        return nil if rel == CAIRO_FILE

        dir, name = File.split(rel)
        return "not a Corpus Coranicum data file this source knows" unless dir == CONCORDANCE_DIR

        match = CONCORDANCE_FILE.match(name) or return "not a concordance sura file"
        "concordance file for no sura #{match[1].to_i} in the Cairo text" unless suras.include?(match[1].to_i)
      end
    end
  end
end
