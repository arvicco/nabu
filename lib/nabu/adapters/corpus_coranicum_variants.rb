# frozen_string_literal: true

require_relative "corpus_coranicum"
require_relative "corpus_coranicum_clone"
require_relative "corpus_coranicum_variants_parser"

module Nabu
  module Adapters
    # Corpus Coranicum — the variant readings (the TEI export of the
    # Berlin-Brandenburg Academy's Qurʾān project; github.com/telota/
    # corpus-coranicum-tei at 57cb2b7): Michael Marx's database of the
    # readings (qirāʾāt) the classical sources ascribe to the readers of the
    # first Islamic centuries — the canonical Seven and their transmitters,
    # the Companions' codices, the non-canonical (šawāḏḏ) readers — word by
    # word against the Qurʾān text, in transliteration. Composes the
    # corpus-coranicum-tei family (CorpusCoranicumVariantsParser).
    #
    # == Shape (the call, and why)
    #
    # A NEW SOURCE beside corpus-coranicum reading the SAME pinned clone
    # (CorpusCoranicumClone; `requires: [corpus-coranicum]`). The readings
    # are documents, not an apparatus layer on the Cairo verses: the
    # DDbDP-style `apparatus` key carries an editor's alternatives to its
    # own lemma inside one source, whereas these are 18,000 attributed
    # readings — searchable text in their own right (a transliterated
    # reading never reaches FTS inside an annotation), dated by their
    # readers and placed by their readers' cities, axes the Cairo suras do
    # not have. ONE DOCUMENT PER READER (the authority's person — upstream's
    # own unit of attribution, the reader as creator), ONE PASSAGE PER VERSE
    # the reader has readings in, cited sura.verse
    # (urn:nabu:corpus-coranicum-variants:reader-40:20.2 beside
    # urn:nabu:corpus-coranicum:sura-020:20.2), the word grain in the tokens
    # (id = upstream's word key "020:002:004", the Cairo word id's numbers —
    # the join is census-exact, below). A reading ascribed to several
    # readers stands in each one's document (the sources ascribe it to each;
    # the co-readers ride "with"). The authority's "readers" are upstream's
    # units of ascription, kept as such: persons (Abū ʿAmr, al-Kisāʾī, Ibn
    # Kaṯīr …), codices ("Kodex des Ibn Masʿūd"), groups ("Koranleser in
    # Kufa"), the reference reading ("Referenztext", 784 verses) and the
    # unnamed ("unbenannt (ohne nähere Angaben)", 813). The 14 worded readings ascribed to no
    # reader form one document, urn:…:unattributed: 13 name none, and
    # variant_1841 names only reader 328 — upstream's own test record
    # (main name "test", no display name), an ascription to nobody.
    #
    # == License (README, read first-hand 2026-11-27)
    #
    # The repository README: "© Berlin-Brandenburgische Akademie der
    # Wissenschaften 2024 / Creative Commons CC BY-SA 4.0" → attribution,
    # share-alike. The three files carry no licence statement of their own.
    # The reader authority's notes quote the classical biographical sources
    # (aḏ-Ḏahabī, Ibn al-Ǧazarī's Ġāyat an-Nihāya in the 1933 Bergsträßer–
    # Pretzl edition) as the project excerpted them; they ride metadata.
    #
    # == Delivery grains (data/quran_variants/, 3 files at the pin)
    #
    # - allvariants.xml — ACCEPTED: the 18,000 readings → the documents.
    # - reader.xml — ACCEPTED as the authority: 870 readers (753 cited by a
    #   reading), each document's metadata; never a document.
    # - sources.xml — REJECTED, skipped by rule: the authority of the
    #   readings' sources (the Iʿrāb and šawāḏḏ works) is cited by NO
    #   reading — every item's <title key="variantsource_"/> is blank — so
    #   it attaches to nothing.
    # Anything else in the directory is unrecognized. Reconciliation: 1 + 1
    # + 1 = 3, the directory.
    #
    # == Count reconciliation (dry parse of the pinned clone, 2026-11-27)
    #
    # 18,000 items (ids 28–18306): 17,998 with words (two empty — variant_
    # 12427 with no reader, variant_12428 "keine Angabe" — carry nothing and
    # are dropped); 30,112 reader ascriptions over 753 distinct readers (11,871
    # items name one reader, 6,115 two to seventeen, 14 none — 13 of them
    # worded). → 753 documents (752 readers — the 753 cited less the test
    # record — + unattributed) / 22,658 passages (distinct reader × verse
    # pairs; the unattributed document's 14). Word keys: 12,943 distinct
    # over 3,495 verses of all 114 suras; against the held Cairo text
    # 12,937 name a Cairo word, 5 a verse the Cairo text lacks and 1
    # (111:3:6) a word past the verse's end — kept verbatim.
    #
    # == Text
    #
    # The verse passage = the reader's readings of that verse in file order,
    # "; "-joined, each reading its words' transliterations single-space
    # joined (upstream's "…" = the word unchanged, its "|" = alternatives
    # one source gives — both verbatim). The project's DMG-style
    # transliteration (ʾ ʿ ā ī ū ḥ ḫ ḏ ṯ ǧ š ṣ ḍ ṭ ẓ ġ), never rendered into
    # Arabic script: language ara-Latn. NFC at the boundary.
    #
    # == Axes
    #
    # dating: the reader's <death> prose → an open-start "date" whose
    # not_after is the latest CE year it names (the readings are his by
    # the time he died; CorpusCoranicumVariantsParser.death_bound), class
    # composition (an attribution date — the diccas author-life precedent);
    # 194 of the 753 documents. places: the reader's <residence> (Kufa,
    # Basra, Medina, Mekka, "Region Syrien" …) → "place" verbatim, minus
    # upstream's non-places (NO_PLACE: "unbekannt", "WO???", "badw" — the
    # bedouin, a people); the reading tradition's city — 68 documents. The
    # sigle, full name and the biographical note ride metadata; the
    # author is the display name (the main name for readers 167 and 438,
    # which carry none).
    #
    # == fetch
    #
    # No network: CorpusCoranicumClone.fetch! verifies the clone at the pin
    # and records it (the only materialized file).
    class CorpusCoranicumVariants < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "corpus-coranicum-variants",
        name: "Corpus Coranicum — the variant readings of the Qurʾān by reader (BBAW TEI export)",
        license: CorpusCoranicum::LICENSE.sub(/; share-alike\..*\z/, "; share-alike"),
        license_class: "attribution",
        upstream_url: CorpusCoranicum::REPO_URL,
        parser_family: "corpus-coranicum-tei",
        credit: "Corpus Coranicum Project, ed. Michael Marx. TEI Data. Berlin-Brandenburg Academy of Sciences " \
                "and Humanities. https://github.com/telota/corpus-coranicum-tei — the variant readings " \
                "database (Michael Marx with Tobias J. Jocham et al.) — CC BY-SA 4.0"
      )

      LANGUAGE = "ara-Latn"
      URN_PREFIX = "urn:nabu:corpus-coranicum-variants:"
      WORK = "Qurʾān"
      DIR = File.join("data", "quran_variants")
      ITEMS = "allvariants.xml"
      READERS = "reader.xml"
      UNUSED = {
        "sources.xml" => "the readings' source authority, cited by no reading (every source key is blank)"
      }.freeze
      UNATTRIBUTED = "unattributed"
      NO_PLACE = ["unbekannt", "WO???", "badw"].freeze

      def self.manifest = MANIFEST

      def self.materialized_paths = [CorpusCoranicumClone::PIN_FILE]

      # No remote of its own: the fetch reads the sibling source's pinned
      # clone on disk and never touches the network, so there is no
      # upstream repository for the remote probe to compare against — the
      # clone's liveness is corpus-coranicum's probe.
      def self.upstream_repo_urls = []

      def initialize(clone_dir: nil, pinned_sha: CorpusCoranicum::PINNED_SHA)
        super()
        @clone_dir = clone_dir
        @pinned_sha = pinned_sha
      end

      # One ref per reader with a worded reading, in authority-number
      # order, then the unattributed readings.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(clone(workdir), DIR, ITEMS)
        return unless File.file?(path)

        grouped(path).each_key do |reader|
          yield Nabu::DocumentRef.new(source_id: manifest.id, id: urn_for(reader), path: path,
                                      metadata: { "reader" => reader })
        end
      end

      def discovery_skips(workdir)
        dir = File.join(clone(workdir), DIR)
        names = File.directory?(dir) ? Dir.children(dir).reject { |name| name.start_with?(".") }.sort : []
        skipped = names.select { |name| UNUSED.key?(name) }
        unknown = names - skipped - [ITEMS, READERS]
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: skipped.size, unrecognized: unknown.size,
          notes: skipped.map { |name| "#{File.join(DIR, name)}: skipped by rule — #{UNUSED.fetch(name)}" } +
                 unknown.map { |name| "#{File.join(DIR, name)}: not a Corpus Coranicum variants file" }
        )
      end

      def parse(document_ref)
        reader = document_ref.metadata.fetch("reader")
        verses = grouped(document_ref.path).fetch(reader) do
          raise Nabu::ParseError, "#{document_ref.path}: no readings for reader #{reader}"
        end
        person = reader == UNATTRIBUTED ? nil : authority(document_ref.path).fetch(reader)
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, title: title(person),
                                      canonical_path: document_ref.path, metadata: metadata(person, verses))
        verses.each_with_index do |((sura, verse), items), sequence|
          document << passage(document_ref.id, reader, sura, verse, items, sequence)
        end
        document
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "corpus-coranicum-variants #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        CorpusCoranicumClone.fetch!(source_id: manifest.id, workdir: workdir, clone: clone(workdir),
                                    pinned_sha: @pinned_sha)
      end

      private

      def clone(workdir) = @clone_dir ? File.expand_path(@clone_dir) : CorpusCoranicumClone.dir_for(workdir)

      def urn_for(reader) = reader == UNATTRIBUTED ? "#{URN_PREFIX}#{UNATTRIBUTED}" : "#{URN_PREFIX}reader-#{reader}"

      def parser = @parser ||= CorpusCoranicumVariantsParser.new

      # {reader => {[sura, verse] => [Item …]}} — readers in authority-number
      # order (unattributed last), verses in Qurʾān order, items in file
      # order; memoized per path (753 documents share one 8 MB file). Every
      # cited reader must be in the authority.
      def grouped(path)
        (@grouped ||= {})[path] ||= begin
          known = authority(path)
          by_reader = Hash.new { |hash, key| hash[key] = Hash.new { |verses, verse| verses[verse] = [] } }
          parser.items(path).each do |item|
            next if item.words.empty?

            item.readers.each do |reader|
              next if known.key?(reader)

              raise Nabu::ParseError, "#{path}: #{item.id} cites reader #{reader}, absent from #{READERS}"
            end
            verse = [item.words.first.sura, item.words.first.verse]
            readers = item.readers.uniq.reject { |reader| test_record?(known.fetch(reader)) }
            ascribed[item.id] = readers
            (readers.empty? ? [UNATTRIBUTED] : readers).each { |reader| by_reader[reader][verse] << item }
          end
          by_reader.sort_by { |reader, _| reader == UNATTRIBUTED ? Float::INFINITY : reader.to_i }
                   .to_h { |reader, verses| [reader, verses.sort.to_h] }
        end
      end

      # Upstream's own test record (reader 328, main name "test", no display
      # name — cited by variant_1841): an ascription to it names no reader.
      def test_record?(person) = person.name.nil? && person.full_name.to_s.casecmp?("test")

      # {item id => the readers it is ascribed to, test record removed},
      # filled by #grouped.
      def ascribed = @ascribed ||= {}

      def authority(items_path)
        path = File.join(File.dirname(items_path), READERS)
        (@authority ||= {})[path] ||= begin
          raise Nabu::ParseError, "#{path}: the reader authority is missing" unless File.file?(path)

          parser.readers(path)
        end
      end

      # The display name, else the authority's main name (readers 151, 167
      # and 438 carry no display name; 167 and 438 are cited).
      def name_of(person) = person.name || person.full_name || "reader #{person.id}"

      def title(person) = person ? "#{WORK} — the readings of #{name_of(person)}" : "#{WORK} — unattributed readings"

      def metadata(person, verses)
        items = verses.values.flatten.uniq(&:id)
        meta = { "work" => WORK, "readings" => items.size, "verses" => verses.size }
        return meta.merge("reader" => UNATTRIBUTED) if person.nil?

        meta.merge(
          "reader" => person.id, "author" => name_of(person), "reader_full_name" => person.full_name,
          "sigle" => person.sigle, "residence" => person.residence, "death" => person.death,
          "date" => death_date(person.death), "place" => place(person.residence), "reader_note" => person.note
        ).compact
      end

      # The open-start bound by the reader's death (class note), or nil.
      def death_date(death)
        bound = CorpusCoranicumVariantsParser.death_bound(death)
        bound && { "not_before" => nil, "not_after" => bound, "raw" => death, "class" => "composition" }
      end

      def place(residence) = residence.nil? || NO_PLACE.include?(residence) ? nil : residence

      def passage(doc_urn, reader, sura, verse, items, sequence)
        tokens = items.flat_map do |item|
          item.words.map { |word| { "id" => word.key, "form" => Normalize.nfc(word.form), "reading" => item.id } }
        end
        readings = items.map do |item|
          with = (ascribed.fetch(item.id) - [reader]).map { |other| "reader-#{other}" }
          with.empty? ? { "id" => item.id } : { "id" => item.id, "with" => with }
        end
        text = items.map { |item| item.words.map(&:form).join(" ") }.join("; ")
        Nabu::Passage.new(urn: "#{doc_urn}:#{sura}.#{verse}", language: LANGUAGE, text: Normalize.nfc(text),
                          annotations: { "tokens" => tokens, "readings" => readings }, sequence: sequence)
      end
    end
  end
end
