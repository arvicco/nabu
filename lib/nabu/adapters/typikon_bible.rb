# frozen_string_literal: true

require "json"

module Nabu
  module Adapters
    # typikon-bible — the Bible layer of the "Уставные чтения" (Typikon
    # Readings) corpus dump of typikon.info (dump 2026-09-21, Zenodo
    # 10.5281/zenodo.22883965): verse texts of Bible editions aligned to
    # the Church Slavonic (Elizabethan) versification, with a 342,568-row
    # numbering concordance across eleven editions. The family is
    # `typikon-jsonl` (one JSON object per line, gzipped).
    #
    # == The edition gate (what is admitted, and why)
    #
    # The dump ships seven verse files under different terms; each edition
    # is admitted only on a license verified first-hand in manifest.json.
    # ADMITTED today: **ro-1688** — the 1688 Bucharest Bible in Romanian
    # Cyrillic, typeset by the project from scans of the print, under the
    # bible layer's CC BY 4.0 (layer rationale verbatim: "Румынскую
    # кириллицу 1688 и китайский Новый Завет 1910 набирали мы — они под
    # лицензией слоя"; file note: "Оцифровка выполнена в проекте по
    # сканам издания"). NOT admitted, held for a ruling: cs-eliz (the
    # Elizabeth Bible, 1751) and ka-mcxeta (the Mtskheta Old Georgian
    # Bible) — both marked "PD" by the dump, each with the caveat that the
    # digitizer states no terms ("Условий оцифровщик не заявляет";
    # "Условий у этой оцифровки НЕ ЗАЯВЛЕНО"), and the same manifest's
    # layer rationale still says "Церковнославянский и латинский остаются
    # вне выгрузки: их оцифровки чужие и разрешения на распространение не
    # дают" — the redistributor's own statements disagree. la-vulgata,
    # en-brenton/kjv and grc-nt (PD), grc-ot (GPL-3.0), ro-1914 (CC BY-SA,
    # Wikisource) and zh-1910 are outside this source's scope (held
    # elsewhere, or not Bible witnesses this shelf needs). A verse file of
    # any non-admitted edition in the workdir is SKIPPED BY RULE.
    #
    # The concordance (bible-concordance.jsonl.gz, CC BY 4.0, the project's
    # own work) is an instrument — "Стих без текста" — not a text grain: the
    # admitted editions' own verse records already carry their canonical
    # address, so it is not fetched; a copy in the workdir is skipped by
    # rule. Its home (an alignment-remap feed) is a separate decision.
    #
    # == Identity: document = edition × book, passage = verse
    #
    # urn:nabu:typikon-bible:<edition>:<book slug> (the dump's own book
    # slug: avdiya, ioilya, pesn-trekh-otrokov); passages <chapter>.<verse>
    # in the EDITION's own numbering (the 1688 print numbers Joel in four
    # chapters; the Song of the Three Youths is its own book), sorted by
    # (chapter, verse). The Slavonic canonical address (canonRef, the
    # dump's reduction to the Elizabeth Bible) rides annotations
    # "canon_ref" on every verse — the alignment hand-off.
    #
    # == Text, language, dating
    #
    # Text = the record's content, NFC at the boundary (the 1688 text ships
    # combining marks in non-canonical order on 33,484 of 36,312 verses;
    # ron is not NFC-exempt). Language ron-Cyrl (Romanian, Cyrillic
    # script); the registry carries no Romanian node yet (lect pending).
    # Date: the edition year the dump records (1688), date_class edition.
    #
    # == License drift guard
    #
    # Parse re-reads manifest.json: the bible layer must still be CC-BY-4.0
    # and the admitted file must carry no license of its own — anything
    # else is a ParseError naming what changed, never a silent ingest.
    #
    # == Census (dump 2026-09-21, read 2026-11-02)
    #
    # ro-1688: 36,312 verses / 79 books; 2,870 verses carry a canonical
    # address different from their own (the Psalter's Hebrew-style
    # numbering 1,213, Sirach 715, the Daniel additions as own books 181,
    # …). Expected first sync: 79 documents / 36,312 passages, 0 errored.
    class TypikonBible < Nabu::Adapter
      DUMP_URL = "https://typikon.info/dump/2026-09-21/"

      # subdir => [url, landed filename] — fetch and probe read the same rows.
      FILES = {
        "manifest" => ["#{DUMP_URL}manifest.json", "manifest.json"].freeze,
        "bible-editions" => ["#{DUMP_URL}bible/bible-editions.jsonl.gz", "bible-editions.jsonl.gz"].freeze,
        "bible-books" => ["#{DUMP_URL}bible/bible-books.jsonl.gz", "bible-books.jsonl.gz"].freeze,
        "bible-verses-ro-1688" => ["#{DUMP_URL}bible/bible-verses-ro-1688.jsonl.gz",
                                   "bible-verses-ro-1688.jsonl.gz"].freeze
      }.freeze

      # edition code => document language.
      ADMITTED = { "ro-1688" => "ron-Cyrl" }.freeze

      LAYER_LICENSE = "CC-BY-4.0"

      MANIFEST = Nabu::SourceManifest.new(
        id: "typikon-bible",
        name: "typikon.info Bible layer — the 1688 Bucharest Bible in Romanian Cyrillic (dump 2026-09-21)",
        license: "CC BY 4.0 (manifest.json bible layer license CC-BY-4.0; rationale verbatim: \"Румынскую " \
                 "кириллицу 1688 и китайский Новый Завет 1910 набирали мы — они под лицензией слоя\"; " \
                 "citation \"Корпус «Уставные чтения» (typikon.info), CC BY 4.0\", DOI 10.5281/zenodo.22883964)",
        license_class: "attribution",
        upstream_url: DUMP_URL,
        parser_family: "typikon-jsonl",
        credit: "Корпус «Уставные чтения» (typikon.info)"
      )

      URN_PREFIX = "urn:nabu:typikon-bible:"

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        FILES.map do |subdir, (url, filename)|
          Nabu::Adapter::HttpProbeTarget.new(label: filename, zip_url: url, metadata_url: nil,
                                             state_subdir: subdir, state_file: Nabu::FileFetch::STATE_FILE)
        end
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        tables = tables(workdir) or return
        verse_files(workdir).each do |code, path|
          next unless ADMITTED.key?(code)

          books = records(path).keys.map { |book_id| tables.books.fetch(book_id) { unknown_book!(path, book_id) } }
          books.sort_by { |book| book["order"] }.each do |book|
            yield Nabu::DocumentRef.new(
              source_id: MANIFEST.id, id: "#{URN_PREFIX}#{code}:#{book.fetch('slug')}", path: File.expand_path(path),
              metadata: { "edition" => code, "book_id" => book.fetch("_id") }
            )
          end
        end
      end

      def discovery_skips(workdir)
        notes = verse_files(workdir).filter_map do |code, path|
          "#{File.basename(path)}: edition #{code} is outside the ruled set" unless ADMITTED.key?(code)
        end
        notes += Dir.glob(File.join(workdir, "**", "bible-concordance.jsonl.gz")).map do |path|
          "#{File.basename(path)}: the numbering concordance is an instrument, not a text grain"
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: 0, notes: notes)
      end

      def parse(document_ref)
        workdir = File.dirname(document_ref.path, 2) # <workdir>/<subdir>/<file>
        code = document_ref.metadata.fetch("edition")
        check_license!(workdir, code)
        tables = tables(workdir)
        book = tables.books.fetch(document_ref.metadata.fetch("book_id"))
        edition = tables.editions.fetch(code)
        language = ADMITTED.fetch(code)
        document = Nabu::Document.new(urn: document_ref.id, language: language,
                                      title: Normalize.nfc(book.fetch("name")),
                                      canonical_path: document_ref.path, metadata: metadata_for(edition, book))
        verses = records(document_ref.path).fetch(book.fetch("_id"))
        verses.sort_by { |r| [r.fetch("chapter"), r.fetch("verse")] }.each_with_index do |record, sequence|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{record.fetch('chapter')}.#{record.fetch('verse')}",
            language: language, text: Normalize.nfc(record.fetch("content").strip),
            annotations: { "canon_ref" => record.fetch("canonRef") }, sequence: sequence
          )
        end
        raise Nabu::ParseError, "#{document_ref.id}: no verses" if document.empty?

        document
      rescue Nabu::ValidationError, KeyError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      # Each file into its own subdir with its own state + attic (the
      # cldf-spine shape). No network in tests (WebMock).
      def fetch(workdir, progress: nil, force: false)
        results = FILES.to_h do |subdir, (url, filename)|
          dir = File.join(workdir, subdir)
          [subdir, Nabu::FileFetch.sync!(
            url: url, dir: dir, filename: filename, attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir),
            progress: progress, guard: ->(doomed) { guard_mass_deletion!(dir, doomed, force: force) }
          )]
        end
        notes = results.filter_map { |subdir, result| "#{subdir} unchanged (304)" if result.not_modified }
        FetchReport.new(sha: results.fetch("bible-verses-ro-1688").sha, fetched_at: Time.now,
                        notes: notes.empty? ? nil : notes.join("; "),
                        repos: FILES.to_h { |subdir, (url, _)| [url, results.fetch(subdir).sha] })
      rescue Nabu::FileFetch::Error => e
        raise Nabu::FetchError, "typikon-bible fetch failed into #{workdir}: #{e.message}"
      end

      Tables = Data.define(:editions, :books)

      private

      def metadata_for(edition, book)
        year = edition["year"]
        {
          "edition" => edition.fetch("code"),
          "edition_title" => Normalize.nfc(edition.fetch("title")),
          "versification" => edition["versification"],
          "edition_source" => edition["sourceLink"],
          "book" => book.fetch("slug"),
          "canon_book" => book["canonId"],
          "date" => year && { "not_before" => year, "not_after" => year, "class" => "edition",
                              "raw" => "#{year} — the edition year the dump records (bible-editions year)" }
        }.compact
      end

      def check_license!(workdir, code)
        path = Dir.glob(File.join(workdir, "**", "manifest.json")).min or
          raise Nabu::ParseError, "#{workdir}: manifest.json missing — the license cannot be re-read"
        layer = parse_json(SourceRead.utf8_file(path, label: "typikon-bible"), path)
                .fetch("layers").find { |l| l["id"] == "bible" } or
          raise Nabu::ParseError, "#{path}: no bible layer"
        license = layer.dig("license", "id")
        unless license == LAYER_LICENSE
          raise Nabu::ParseError, "#{path}: the bible layer license is now #{license.inspect}, not #{LAYER_LICENSE}"
        end

        entry = layer.fetch("files").find { |f| f["path"] == "bible/bible-verses-#{code}.jsonl.gz" }
        return if entry && !entry.key?("license")

        raise Nabu::ParseError, "#{path}: bible-verses-#{code} is no longer listed under the layer license " \
                                "(#{entry ? entry['license'].inspect : 'absent'})"
      end

      # { edition code => path } for every verse file in the workdir.
      def verse_files(workdir)
        Dir.glob(File.join(workdir, "**", "bible-verses-*.jsonl.gz")).to_h do |path|
          [File.basename(path).delete_prefix("bible-verses-").delete_suffix(".jsonl.gz"), path]
        end
      end

      def tables(workdir)
        editions = Dir.glob(File.join(workdir, "**", "bible-editions.jsonl.gz")).min
        books = Dir.glob(File.join(workdir, "**", "bible-books.jsonl.gz")).min
        return nil unless editions && books

        Tables.new(editions: each_record(editions).to_h { |r| [r.fetch("code"), r] },
                   books: each_record(books).to_h { |r| [r.fetch("_id"), r] })
      end

      # { bookId => [records] } for one verse file, cached by path + mtime.
      def records(path)
        key = [path, File.mtime(path), File.size(path)]
        @records ||= {}
        @records[key] ||= each_record(path).group_by { |r| r.fetch("bookId") }
      end

      # One JSON object per line of a gzipped file — decompressed through
      # gzip (Nabu::Shell, the corpus-oudfries unzip -p shape) and read
      # through the encoding belt.
      def each_record(path)
        text = SourceRead.utf8(Nabu::Shell.run("gzip", "-dc", path), label: "typikon-bible #{path}")
        text.each_line.map { |line| parse_json(line, path) }
      rescue Nabu::Shell::Error => e
        raise Nabu::ParseError, "#{path}: #{e.message}"
      end

      def parse_json(text, path)
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "#{path}: #{e.message}"
      end

      def unknown_book!(path, book_id)
        raise Nabu::ParseError, "#{path}: bookId #{book_id} is not in bible-books.jsonl.gz"
      end
    end
  end
end
