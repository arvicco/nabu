# frozen_string_literal: true

require_relative "corpus_coranicum"
require_relative "corpus_coranicum_clone"
require_relative "corpus_coranicum_manuscript_parser"

module Nabu
  module Adapters
    # Corpus Coranicum — the manuscript transcriptions (the TEI export of
    # the Berlin-Brandenburg Academy's Qurʾān project, "Manuscripta
    # Coranica"; github.com/telota/corpus-coranicum-tei at 57cb2b7): the
    # project's word-by-word rasm transcriptions of early Qurʾān
    # manuscripts — the ḥiǧāzī and kūfī parchments of the first Islamic
    # centuries, later maġribī and new-style codices — each a WITNESS
    # beside the held Cairo text (corpus-coranicum), verse for verse.
    # Composes the corpus-coranicum-tei family
    # (CorpusCoranicumManuscriptParser).
    #
    # == Shape (the call, and why)
    #
    # A NEW SOURCE beside corpus-coranicum, reading the SAME pinned clone
    # (CorpusCoranicumClone; `requires: [corpus-coranicum]`, the bhsa →
    # bridging parse-time read) rather than a document family inside it:
    # the manuscripts' axes are their own — each is dated by its own copying
    # estimate and placed by its own provenance, where the Cairo suras band
    # through the work's 610–632 composition era and are unplaced; the
    # dating lane registers one shape per source (MetadataDates::SHAPES) and
    # the posture record one posture per layer, so one source would have to
    # lie about one of the two. The witness model is the house's
    # NT-manuscript model (cntr, ntvmr): ONE DOCUMENT PER TRANSCRIBED
    # MANUSCRIPT, ONE PASSAGE PER VERSE in the manuscript's own order, cited
    # sura.verse (urn:nabu:corpus-coranicum-manuscripts:manuscript-00012:7.42
    # beside urn:nabu:corpus-coranicum:sura-007:7.42), so a verse of any
    # manuscript lines up with the Cairo verse and with every other witness.
    #
    # == License (README, read first-hand 2026-11-27)
    #
    # The repository README: "© Berlin-Brandenburgische Akademie der
    # Wissenschaften 2024 / Creative Commons CC BY-SA 4.0" → attribution,
    # share-alike. The records carry no licence of their own; their
    # <availability status="restricted"> statements are IMAGE credits
    # ("Image credits: Staatsbibliothek zu Berlin - Preußischer
    # Kulturbesitz.", "… © The Trustees of the Chester Beatty Library,
    # Dublin.") — the facsimile <graphic> links point at images whose
    # rights stay with each holding library. The images are NOT fetched or
    # carried; their credits ride metadata (image_credits) verbatim.
    #
    # == Delivery grains (data/quran_manuscripts/, 2,323 files at the pin)
    #
    # - manuscript-NNNNN.xml WITH a transcription (a <w> in the body) — 193
    #   files — ACCEPTED: one document each.
    # - manuscript-NNNNN.xml WITHOUT one — 2,129 files (2,111 empty bodies,
    #   18 "(No content available)") — REJECTED, skipped by rule: a
    #   codicological record with no text (shelfmark, holding library,
    #   folio contents, date and script for most) is a catalogue entry, not
    #   a witness; one note with the count. Specimen: manuscript-02504.xml
    #   (Rotterdam 96D17).
    # - places.xml — the repository authority (110 holding libraries with
    #   city, country and a GeoNames id) — ACCEPTED as metadata: the
    #   repository fields of every document, never a document.
    # Anything else in the directory is unrecognized. The rest of the clone
    # belongs to its sibling sources (corpus-coranicum: the Cairo text and
    # concordance; corpus-coranicum-variants: quran_variants/) or to later
    # packets (commentary, intertexts) and is outside this census.
    # Reconciliation: 193 + 2,129 + 1 = 2,323, the directory.
    #
    # == Count reconciliation (dry parse of the pinned clone, 2026-11-27)
    #
    # The keys are the transcribers', kept verbatim — they cite the verse
    # and word the project assigned, which is not always the Cairo verse
    # the words read: manuscript-00017 keys the text of Cairo Q 97:3 as
    # 97:4 and Q 97:5 as the heading 98:0 (its own verse division), and a
    # heading band can carry the next verse's opening words (01362: 39:0).
    # Alignment by sura.verse is upstream's claim, never re-derived.
    #
    # 193 documents → 32,182 passages: 31,730 verse passages + 452 sura
    # heading passages (verse 0); 411,803 words (17,668 of them joined from
    # line-split fragments); 32,533 verse markers attached; 4 unkeyed and 3
    # empty <w> dropped (counted per document). 962 verse passages merge
    # more than one stretch (6,652 word keys recur across stretches). The
    # Cairo join, both ways: 31,676 verse passages cite a verse the Cairo
    # text has, 54 one it lacks (the transcribers' own keys, kept); 393,965
    # words carry the key of a Cairo word, 13,876 a key beyond the Cairo
    # verse's word count (the transcription's own word grid diverges in
    # 2,376 verses — keys are upstream's, never re-numbered); 76,999 of the
    # 77,432 Cairo words are witnessed by at least one manuscript.
    #
    # == Text (the house Leiden policy — CorpusCoranicumManuscriptParser)
    #
    # The verse = its words in manuscript order, single-space joined, in the
    # transcription's rasm as keyed: the undotted letter skeleton with its
    # archaic dotless forms (ٮ U+066E, ٯ U+066F, ڡ U+06A1, ں U+06BA,
    # ے U+06D2), U+200D/U+200C joiners and the occasional presentation
    # form (ﻩ U+FEE9) verbatim; supplied (from the Cairo rasm), unclear,
    # added and modified letters read through, deleted letters in ⟦…⟧. The
    # supplied letters are the Cairo rasm by construction, so the passage
    # also carries "extant" (what the page itself shows, each supplied
    # stretch "[…]") whenever the two differ. NFC MEASURED over all 411,803
    # words: it changes NOTHING (the rasm letters have no decompositions;
    # the archaic forms and U+FEE9 survive — NFC is not NFKC). Upstream
    # stray text stays verbatim (canonical means canonical): "&nbsp;"
    # typed as text in manuscript-00173, "nicht lesbar" in 00416/00505,
    # "⟦Bild⟧" in 00508.
    #
    # == Annotations (per verse passage; only non-empty keys)
    #
    #   tokens        one per word: id (upstream's key verbatim,
    #                 "002-282-088"), form, and the non-default marks —
    #                 extant (when it differs), supplied_chars,
    #                 unclear_chars, added_chars, modified_chars, cancelled,
    #                 unclear (the word flagged type="unclear"), parts (>1:
    #                 joined from line-split fragments)
    #   leiden        the verse's totals of the same counts + unclear_words
    #   extant        the verse as the page shows it (when it differs)
    #   markers       the verse-division / tenth markers following the verse
    #   lines         the folio.line locators its words sit on ("1r.3")
    #   line_notes    those lines' transcriber notes, verbatim
    #   stretches     >1 when the verse's words come in separate runs
    #   repeated_words  word keys more than one run carries
    #   heading       true on a sura heading passage (verse 0)
    #
    # == Axes (aggressive mining — every axis-shaped field)
    #
    # dating: origDate (CE years: "640-680", "-750" = before 750 — the
    # summary's "Estimated date of production: Before 750") → "date"
    # {not_before, not_after, raw}, the copying estimate (no class — an
    # artifact date, the dbbe stance); 172 of 193 dated, 21 empty (one
    # record's "0" is no date). places: upstream's provenance ("al-Fusṭāṭ",
    # "Damascus", "North Africa (Maghreb), al-Andalus") → "place" verbatim,
    # 98 of 193 — the place the fragment is recorded as coming from (the
    # Fusṭāṭ and Damascus mosque hoards, the Sanaa find); the holding
    # library is a PRESENT location and rides as repository /
    # repository_place / repository_country / repository_geonames, never as
    # the place. script: scriptNote verbatim ("ḥiǧāzī II", "kūfī B.Ia",
    # "maġribī", "new style III" — Déroche's typology) → "script" (facet);
    # the registry's scripts table is ISO-15924-grained (arab only), so the
    # styles have no node and are not claimed as one. material: the
    # supportDesc @material (parchment 177 · paper 9 · papyrus 7). Also mined:
    # shelfmark, title, folios, dimensions, lines per page, the folio
    # contents table, the summary prose, the project's record history
    # (transcribers) and the image credits.
    #
    # == fetch
    #
    # No network: CorpusCoranicumClone.fetch! verifies the clone at the
    # pin and records it (the only materialized file).
    class CorpusCoranicumManuscripts < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "corpus-coranicum-manuscripts",
        name: "Corpus Coranicum — Qurʾān manuscript transcriptions (BBAW TEI export)",
        license: "#{CorpusCoranicum::LICENSE.sub(/; share-alike\..*\z/, '; share-alike')}. The manuscript " \
                 "images are not carried (their rights are each holding library's; the records' " \
                 "availability statements are image credits only)",
        license_class: "attribution",
        upstream_url: CorpusCoranicum::REPO_URL,
        parser_family: "corpus-coranicum-tei",
        credit: "Corpus Coranicum Project, ed. Michael Marx. TEI Data. Berlin-Brandenburg Academy of Sciences " \
                "and Humanities. https://github.com/telota/corpus-coranicum-tei — the manuscript " \
                "transcriptions (Manuscripta Coranica) — CC BY-SA 4.0"
      )

      LANGUAGE = "ara"
      URN_PREFIX = "urn:nabu:corpus-coranicum-manuscripts:"
      WORK = "Qurʾān"
      DIR = File.join("data", "quran_manuscripts")
      RECORD = /\A(manuscript-\d{5})\.xml\z/
      AUTHORITY = "places.xml"
      CLOSED_DATE = /\A(\d{3,4})-(\d{3,4})\z/
      OPEN_DATE = /\A-(\d{3,4})\z/
      FOLIOS = /\AFolios:\s*(\d+)\z/

      def self.manifest = MANIFEST

      def self.materialized_paths = [CorpusCoranicumClone::PIN_FILE]

      # +clone_dir+/+pinned_sha+ exist for the tests; no-arg construction
      # reads canonical/corpus-coranicum beside the workdir.
      def initialize(clone_dir: nil, pinned_sha: CorpusCoranicum::PINNED_SHA)
        super()
        @clone_dir = clone_dir
        @pinned_sha = pinned_sha
      end

      # One ref per transcribed manuscript record, in file order.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        census(workdir)[:accepted].each do |path|
          yield Nabu::DocumentRef.new(source_id: manifest.id, id: "#{URN_PREFIX}#{File.basename(path, '.xml')}",
                                      path: path, metadata: { "record" => File.basename(path, ".xml") })
        end
      end

      def discovery_skips(workdir)
        found = census(workdir)
        rejected = found[:rejected]
        notes = []
        unless rejected.zero?
          notes << "data/quran_manuscripts/: #{rejected} manuscript record#{'s' unless rejected == 1} " \
                   "without a transcription skipped by rule (codicological metadata only)"
        end
        notes += found[:unknown].map { |rel| "#{rel}: not a manuscript record" }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: rejected, unrecognized: found[:unknown].size, notes: notes)
      end

      def parse(document_ref)
        record = parser.parse(document_ref.path)
        raise Nabu::ParseError, "#{document_ref.path}: the transcription keys no verse" if record.verses.empty?

        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, title: title(record.header),
                                      canonical_path: document_ref.path,
                                      metadata: metadata(record, document_ref, repositories(document_ref.path)))
        record.verses.each_with_index { |verse, sequence| document << passage(document_ref.id, verse, sequence) }
        document
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "corpus-coranicum-manuscripts #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        CorpusCoranicumClone.fetch!(source_id: manifest.id, workdir: workdir, clone: clone(workdir),
                                    pinned_sha: @pinned_sha)
      end

      private

      def parser = @parser ||= CorpusCoranicumManuscriptParser.new

      def clone(workdir) = @clone_dir ? File.expand_path(@clone_dir) : CorpusCoranicumClone.dir_for(workdir)

      # {accepted: [path …], rejected: n, unknown: [rel …]} over the
      # clone's manuscripts directory, memoized per directory.
      def census(workdir)
        dir = File.join(clone(workdir), DIR)
        (@census ||= {})[dir] ||= begin
          found = { accepted: [], rejected: 0, unknown: [] }
          names = File.directory?(dir) ? Dir.children(dir).reject { |name| name.start_with?(".") }.sort : []
          names.each do |name|
            path = File.join(dir, name)
            if RECORD.match?(name) && File.file?(path)
              xml = SourceRead.utf8_file(path, label: "corpus-coranicum manuscript")
              CorpusCoranicumManuscriptParser.transcribed?(xml) ? found[:accepted] << path : found[:rejected] += 1
            elsif name != AUTHORITY
              found[:unknown] << File.join(DIR, name)
            end
          end
          found
        end
      end

      def repositories(record_path)
        path = File.join(File.dirname(record_path), AUTHORITY)
        (@repositories ||= {})[path] ||= File.file?(path) ? parser.repositories(path) : {}
      end

      def title(header) = "#{WORK} — #{header['title'] || header['shelfmark']}"

      def metadata(record, ref, repositories)
        header = record.header
        repository = repositories.fetch(header["repository_key"].to_s, {})
        verses = record.verses.reject { |verse| verse.verse.zero? }
        {
          "work" => WORK, "record" => ref.metadata.fetch("record"), "record_id" => header["record_id"],
          "title" => header["title"], "shelfmark" => header["shelfmark"],
          "repository" => repository["name"] || header["repository_text"].to_s.split(" ,").first,
          "repository_place" => repository["settlement"], "repository_country" => repository["country"],
          "repository_geonames" => repository["geonames"],
          "material" => header["material"], "support" => header["support"], "folios" => folios(header),
          "dimensions" => dimensions(header), "lines_per_page" => positive(header["written_lines"]),
          "script" => header["script"], "date" => date(header["orig_date_text"]),
          "provenance" => header["provenance"], "place" => header["provenance"],
          "summary" => header["summary"].empty? ? nil : header["summary"].join("\n\n"),
          "contents" => header["contents"].empty? ? nil : header["contents"],
          "record_history" => header["record_history"].empty? ? nil : header["record_history"],
          "image_credits" => header["image_credits"].empty? ? nil : header["image_credits"],
          "transcription_file" => header["transcription_file"],
          "verses" => verses.size, "headings" => record.verses.size - verses.size,
          "words" => record.verses.sum { |verse| verse.words.size },
          "unkeyed_words" => positive(record.unkeyed), "empty_words" => positive(record.empty_words),
          "unplaced_markers" => positive(record.unplaced_markers)
        }.compact
      end

      def positive(value)
        number = value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
        number&.positive? ? number : nil
      end

      def folios(header) = header["extent"].to_s.match(FOLIOS)&.then { |match| match[1].to_i }

      def dimensions(header)
        width = positive(header["width"])
        height = positive(header["height"])
        return nil unless width && height

        { "width" => width, "height" => height, "unit" => header["dimensions_unit"] || "mm" }
      end

      # origDate (class note): "640-680" closed, "-750" before 750.
      def date(text)
        if (match = CLOSED_DATE.match(text.to_s))
          { "not_before" => match[1].to_i, "not_after" => match[2].to_i, "raw" => text }
        elsif (match = OPEN_DATE.match(text.to_s))
          { "not_before" => nil, "not_after" => match[1].to_i, "raw" => text }
        end
      end

      def passage(doc_urn, verse, sequence)
        Nabu::Passage.new(urn: "#{doc_urn}:#{verse.sura}.#{verse.verse}", language: LANGUAGE,
                          text: Normalize.nfc(verse.text), annotations: annotations(verse), sequence: sequence)
      end

      def annotations(verse)
        tokens = verse.words.map { |word| token(word) }
        extant = verse.extant
        {
          "tokens" => tokens, "leiden" => leiden(verse.words),
          "extant" => extant == verse.text ? nil : Normalize.nfc(extant),
          "markers" => verse.markers.empty? ? nil : verse.markers.map { |marker| Normalize.nfc(marker) },
          "lines" => verse.lines, "line_notes" => verse.line_notes.empty? ? nil : nfc_values(verse.line_notes),
          "stretches" => verse.stretches > 1 ? verse.stretches : nil,
          "repeated_words" => positive(verse.repeated_words), "heading" => verse.verse.zero? || nil
        }.compact
      end

      def nfc_values(hash) = hash.transform_values { |value| Normalize.nfc(value) }

      COUNTS = { "supplied_chars" => :supplied, "unclear_chars" => :unclear, "added_chars" => :added,
                 "modified_chars" => :modified }.freeze
      private_constant :COUNTS

      def token(word)
        token = { "id" => word.key, "form" => Normalize.nfc(word.form) }
        token["extant"] = Normalize.nfc(word.extant) unless word.extant == word.form
        COUNTS.each { |key, field| token[key] = word.public_send(field) if word.public_send(field).positive? }
        token["cancelled"] = true if word.cancelled
        token["unclear"] = true if word.unclear_word
        token["parts"] = word.parts if word.parts > 1
        token
      end

      def leiden(words)
        totals = COUNTS.to_h { |key, field| [key, words.sum { |word| word.public_send(field) }] }
        totals["unclear_words"] = words.count(&:unclear_word)
        totals = totals.select { |_key, count| count.positive? }
        totals["cancelled"] = true if words.any?(&:cancelled)
        totals.empty? ? nil : totals
      end
    end
  end
end
