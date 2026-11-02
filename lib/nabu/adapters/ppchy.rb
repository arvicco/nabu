# frozen_string_literal: true

require "nokogiri"
require_relative "penn_psd_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # PPCHY — the Penn Parsed Corpus of Historical Yiddish (Beatrice
    # Santorini, v1.0 2021; github.com/beatrice57/penn-parsed-corpus-of-
    # historical-yiddish, actively corrected upstream). About 200,000 words
    # of Yiddish from the oldest dated letter (Regensburg 1478) through
    # Old Yiddish verse (the Bovo-bukh), Cracow and Prague prints, Glikl's
    # memoirs and the Hasidic and Haskalah prose, to twentieth-century
    # drama, folk humour and grammar books — every sentence hand-parsed in
    # the Penn historical-corpora annotation scheme (constituency trees with
    # traces, function tags and Hebrew-component glosses).
    #
    # == Upstream's delivery grains (census 2026-11-02, main @404082bf)
    #
    # - data/*.psd — 63 parsed-text files (one text or text excerpt each,
    #   19,560 top-level forms = 17,861 sentence trees + 1,699 page/file
    #   marker blocks) → THE DOCUMENT GRAIN, urn:nabu:ppchy:<file stem>.
    # - doc/sources/yiddish-sources-contents.html — the per-text source
    #   record (Filename / Date / Dialect / Genre / Source / Notes / Catalog
    #   entries / Number of words, a PDF page-image flag): MINED, never a
    #   document — 63 file names over 61 records (two record pairs share
    #   one entry: 1600e-magid(-preface), 1620e-lev-tov-1(-preface)).
    # - doc/pdf-images/*.pdf — page images of the source prints (~400 MB):
    #   REJECTED (a scan grain; the text is the psd). Outside the cone.
    # - doc/annotation-yiddish/*.html — the annotation manual: REJECTED.
    # - other/ — Santorini's 1989/1995 studies, the Olsvanger glossary,
    #   Zaretski's transliterated grammar excerpts: REJECTED (scholarship
    #   about the corpus, not corpus text). Outside the cone.
    # - data/.DS_Store — upstream's own Finder litter: skipped by rule.
    # Reconciliation: 63 accepted + 1 skipped = the 64 entries under data/;
    # the sources page lists exactly the same 63 file names (no residue).
    # The README advertises "roughly 200,000 words" (the page's per-text
    # counts sum to 206,392).
    #
    # NB: README — "some of them still reflect their origin, containing
    # only subordinate clauses": several Old Yiddish files are sentence
    # SAMPLES, not running text. Declared on the dossier.
    #
    # == Script and text
    #
    # The texts are Yiddish in Hebrew script upstream but the corpus is
    # ROMANIZED — "more or less according to the YIVO system", Hebrew
    # words without diacritics (doc/annotation-yiddish/transliteration).
    # So passages are Latin-script yi; NFC as everywhere (no exemption).
    # The surface text is the penn-psd :ppche rendering (split "@" words
    # rejoined, ^glosses on the tokens, empty categories silent); the tree
    # rides verbatim.
    #
    # == Mined axes
    #
    # Dating: the record's Date — a year, "Approx. YYYY" (the year, the
    # qualifier kept raw — the memis precedent), "Between A and B", "19xx"
    # (the century), the court testimony's "ranging from c1413 to 1686" →
    # the MetadataDates :structured shape; a file without a record falls
    # back to its own name's year (1478w-…). The court testimony's items
    # carry their own date and dialect inside the ID (Rubashov's item
    # numbers "1_c1413_w"): per-passage item / item_date / item_year /
    # item_dialect annotations. Dialect: "<East|West> Yiddish[, place]" →
    # dialect (the classification, a facet) + dialect_localization; a town
    # or region localization (Regensburg, Cracow, Prague, Lublin, Lvov,
    # Vilna, Volina, Holland, Northern Germany) is the place claim —
    # adjectival areas (Moravian, Bohemian, Polish, Lithuanian) and the
    # quoted "halb-deytshish" are not. Kind: the record's Genre (Letter /
    # Prose / Verse / Vernacular; "Prose (preface), verse (main text)"
    # resolves per file), folded in config/kind_map.yml.
    #
    # == License
    #
    # In-repo LICENSE.rst (verbatim, verified 2026-11-02): "The files in
    # this repository are distributed under Creative Commons License
    # Attribution-NonCommercial-ShareAlike 4.0 International CC BY-NC-SA
    # 4.0" → class nc. Cite: Santorini, Beatrice. 2021. Penn Parsed Corpus
    # of Historical Yiddish, v1.0.
    #
    # == fetch / sync policy
    #
    # Sparse GitFetch over [data, doc/sources, LICENSE.rst, README.rst]
    # (the ~400 MB of page images and studies stay upstream). Upstream
    # corrects annotation continually (commits weekly in Oct 2026) — git
    # tracks it; sync_policy manual.
    class Ppchy < Nabu::Adapter
      REPO_URL = "https://github.com/beatrice57/penn-parsed-corpus-of-historical-yiddish"
      SPARSE_PATHS = ["data", "doc/sources", "LICENSE.rst", "README.rst"].freeze
      DATA_DIR = "data"
      SOURCES_PAGE = "doc/sources/yiddish-sources-contents.html"
      LANGUAGE = "yi"
      URN_PREFIX = "urn:nabu:ppchy:"

      # Rejected grains (class note), counted when present in a workdir.
      REJECTED = {
        "doc/pdf-images" => "page images of the source prints — a scan grain, the text is the psd",
        "doc/annotation-yiddish" => "the annotation manual — documentation, not corpus text",
        "other" => "studies and glossaries about the corpus — not corpus text"
      }.freeze

      # The record's Filename/Date/… fields (upstream's labels verbatim).
      FIELDS = { "Date" => "date", "Dialect" => "dialect", "Genre" => "genre", "Source" => "source",
                 "Notes" => "notes", "Catalog entries" => "catalog_entries",
                 "Number of words" => "words" }.freeze
      DIALECT_LETTERS = { "e" => "East Yiddish", "w" => "West Yiddish" }.freeze
      COURT_ITEM = /,(\d+)_(c?(\d{4}))_([ewx]\??)\./
      SPLIT_GENRE = /\A(\w+) \(preface\), (\w+) \(main text\)\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "ppchy",
        name: "PPCHY — Penn Parsed Corpus of Historical Yiddish (Santorini)",
        license: "CC BY-NC-SA 4.0 (in-repo LICENSE.rst, verbatim: \"The files in this repository are " \
                 "distributed under Creative Commons License Attribution-NonCommercial-ShareAlike 4.0 " \
                 "International CC BY-NC-SA 4.0\"; verified 2026-11-02). Cite: Santorini, Beatrice. 2021. " \
                 "Penn Parsed Corpus of Historical Yiddish, v1.0",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "penn-psd",
        credit: "Beatrice Santorini, Penn Parsed Corpus of Historical Yiddish (2021)"
      )

      def self.manifest = MANIFEST

      # -- the mined-axis readers (class methods so tests pin each rule) --

      # The record's Date → the :structured hash (bounds only when the
      # shape is one of the censused ones; the raw always rides).
      def self.date_for(raw)
        bounds = case raw
                 when /\A(?:Approx\. )?(\d{4})\z/ then [Regexp.last_match(1).to_i] * 2
                 when /\ABetween (\d{4}) and (\d{4})\z/, /ranging from c?(\d{4}) to c?(\d{4})\z/
                   [Regexp.last_match(1).to_i, Regexp.last_match(2).to_i]
                 when /\A(\d\d)xx\z/ then [Regexp.last_match(1).to_i * 100, (Regexp.last_match(1).to_i * 100) + 99]
                 end
        return { "raw" => raw } if bounds.nil?

        { "not_before" => bounds[0], "not_after" => bounds[1], "raw" => raw }
      end

      # "West Yiddish, Regensburg" → [classification, localization]; the
      # split is the first comma OUTSIDE parentheses.
      def self.dialect_parts(raw)
        depth = 0
        raw.each_char.with_index do |char, index|
          depth += 1 if char == "("
          depth -= 1 if char == ")"
          return [raw[0...index].strip, raw[(index + 1)..].strip] if char == "," && depth.zero?
        end
        [raw.strip, nil]
      end

      # A localization that names a place: not adjectival (-ian/-ish), not
      # a quoted register label.
      def self.place_for(localization)
        return nil if localization.nil? || localization.start_with?('"') || localization.match?(/(?:ian|ish)\z/)

        localization
      end

      # -- discovery ------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        records = sources_records(workdir)
        psd_files(workdir).each do |name|
          stem = File.basename(name, ".psd")
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{URN_PREFIX}#{stem}",
            path: File.expand_path(File.join(DATA_DIR, name), workdir),
            metadata: { "stem" => stem, "record" => records[stem] }.compact
          )
        end
      end

      def discovery_skips(workdir)
        notes = data_entries(workdir).reject { |name| name.end_with?(".psd") }
                                     .map { |name| "#{DATA_DIR}/#{name}: not a parsed-text file" }
        REJECTED.each do |dir, why|
          Dir.glob("**/*", base: File.join(workdir, dir)).sort.each do |rel|
            notes << "#{dir}/#{rel}: #{why}" if File.file?(File.join(workdir, dir, rel))
          end
        end
        DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: 0, notes: notes)
      end

      def parse(document_ref)
        stem = document_ref.metadata.fetch("stem")
        PennPsdParser.new.parse(
          document_ref.path, urn: document_ref.id, language: LANGUAGE, title: stem,
                             conventions: :ppche, metadata: document_metadata(stem, document_ref.metadata["record"]),
                             annotate: method(:item_annotations)
        )
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url = REPO_URL

      def data_entries(workdir)
        dir = File.join(workdir, DATA_DIR)
        return [] unless File.directory?(dir)

        Dir.children(dir).select { |name| File.file?(File.join(dir, name)) }.sort
      end

      def psd_files(workdir) = data_entries(workdir).select { |name| name.end_with?(".psd") }

      # stem => { upstream label => verbatim text } from the sources page;
      # one record may name two files ("1600e-magid-preface, 1600e-magid").
      def sources_records(workdir)
        path = File.join(workdir, SOURCES_PAGE)
        return {} unless File.file?(path)

        page = SourceRead.utf8_file(path, label: "ppchy")
        page.split(/^(?=<a name=")/).each_with_object({}) do |chunk, records|
          record = record_fields(chunk)
          next unless record["Filename"]

          record["PDF"] = chunk[/<!--PDF: ([^>]*?)-->/, 1]
          record["Filename"].split(",").map(&:strip).each { |stem| records[stem] = record.compact }
        end
      end

      def record_fields(chunk)
        chunk.scan(%r{<font color="darkred">([^<]*):</font>(.*?)(?=<font color="darkred">|\z)}m)
             .to_h { |label, body| [label, clean(body)] }
      end

      # Tags out, entities decoded (the page writes &uuml; etc.), whitespace
      # collapsed, NFC.
      def clean(html)
        text = Nokogiri::HTML.fragment(html.gsub(/<br\s*>/i, " ")).text.gsub(/\s+/, " ").strip
        Nabu::Normalize.nfc(text)
      end

      def document_metadata(stem, record)
        record ||= {}
        metadata = { "file" => "#{DATA_DIR}/#{stem}.psd" }
        FIELDS.each { |label, key| metadata[key] = record[label] if record[label] }
        metadata["page_images"] = record["PDF"] if record["PDF"]
        metadata["date"] = record["Date"] ? self.class.date_for(record["Date"]) : filename_date(stem)
        metadata.merge!(dialect_metadata(record["Dialect"] || filename_dialect(stem)))
        metadata.merge!(genre_metadata(stem, record["Genre"])) if record["Genre"]
        metadata.compact
      end

      def dialect_metadata(raw)
        return {} if raw.nil?

        dialect, localization = self.class.dialect_parts(raw)
        { "dialect" => dialect, "dialect_localization" => localization,
          "place" => self.class.place_for(localization) }
      end

      # "Prose (preface), verse (main text)" names both files of a pair.
      def genre_metadata(stem, raw)
        match = SPLIT_GENRE.match(raw)
        return { "genre" => raw } unless match

        genre = stem.end_with?("-preface") ? match[1] : match[2]
        { "genre" => genre.capitalize, "genre_raw" => raw }
      end

      def filename_date(stem)
        year = stem[/\A(\d{4})[ewx]-/, 1]
        year && { "not_before" => year.to_i, "not_after" => year.to_i, "raw" => "#{stem[0, 5]} (file name)" }
      end

      def filename_dialect(stem) = DIALECT_LETTERS[stem[/\A\d{4}([ew])-/, 1]]

      # Rubashov's court-testimony items: "…,1_c1413_w.3".
      def item_annotations(id)
        match = COURT_ITEM.match(id)
        return {} unless match

        { "item" => match[1], "item_date" => match[2], "item_year" => match[3].to_i, "item_dialect" => match[4] }
      end
    end
  end
end
