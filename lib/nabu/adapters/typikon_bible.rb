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
    # The dump ships ten verse files under different terms; each edition
    # is admitted only on a marking verified first-hand in manifest.json,
    # re-read at every parse. ADMITTED (ruled order):
    #
    # - **ro-1688** — the 1688 Bucharest Bible in Romanian Cyrillic,
    #   typeset by the project from scans of the print, under the bible
    #   layer's CC BY 4.0 (layer rationale verbatim: "Румынскую кириллицу
    #   1688 и китайский Новый Завет 1910 набирали мы — они под лицензией
    #   слоя"; file note: "Оцифровка выполнена в проекте по сканам
    #   издания"). The file carries no license of its own.
    # - **cs-eliz** — the Elizabeth Bible (edition record: "Библия
    #   (церковнославянский, Елизаветинская)", year 1751; file attribution
    #   "Текст: Елизаветинская Библия (ред. 1751/1900), оцифровка
    #   bible.by/elzs"), in full Church Cyrillic print orthography (titla,
    #   accents, ѣ/і/ѵ/ѳ/ѡ). The UN-modernized second witness of the text
    #   the library holds modernized as elizabeth-bible, and the dump's own
    #   versification standard ("Эталон версификации всего собрания"):
    #   every canonRef is its own address. Exod 36:9–39:23 is absent from
    #   the file — the print leaves it unnumbered ("Исх. 36:9–39:23 книга
    #   печатает БЕЗ нумерации стихов и прямо о том говорит пометой на
    #   поле 36:8").
    # - **ka-mcxeta** — "ბიბლია ძველი ქართულით (грузинская: Мцхетская
    #   рукопись и перевод преподобных Евфимия и Георгия Святогорцев)":
    #   the Bible in Old Georgian from orthodoxy.ge's digital text — the
    #   Old Testament after the Mtskheta manuscript, the New Testament in
    #   the Athonite translation of Euthymius and George (file attribution
    #   "Ветхий Завет по Мцхетской рукописи, Новый преподобных Евфимия и
    #   Георгия Святогорцев"). Its edition record carries no year.
    #
    # The two PD editions — LICENSE (owner-ruled 2026-11-03). Both files
    # carry their own marking "PD" ("Общественное достояние (Public Domain
    # Mark 1.0)"), each with the redistributor's caveat that the digitizer
    # stated no terms — cs-eliz: "Условий оцифровщик не заявляет; отдаём по
    # тому же рассуждению, что и грузинскую, — верная передача текста,
    # свободного от притязаний, своего права не порождает, а издание 1751
    # года в общественном достоянии по возрасту бесспорно"; ka-mcxeta:
    # "Условий у этой оцифровки НЕ ЗАЯВЛЕНО, и это надо знать, беря файл.
    # Сами памятники в общественном достоянии по возрасту: Мцхетская
    # рукопись XVII–XVIII века, перевод Святогорцев — XI." The same
    # manifest's bible-layer rationale still says "Церковнославянский и
    # латинский остаются вне выгрузки: их оцифровки чужие и разрешения на
    # распространение не дают", and the ka-mcxeta note repeats
    # "Церковнославянская и латинская копии в выгрузку по-прежнему не
    # идут" — while the dump ships the Church Slavonic file marked PD: a
    # contradiction in the redistributor's own words, recorded here. The
    # owner ruled admission under the PD marking (2026-11-03): faithful
    # transcriptions of centuries-old editions, no originality of their own
    # to license. The source class stays `attribution` (the ro-1688
    # precedent): the book division, versification and canonical addresses
    # on every edition are the project's CC BY 4.0 work, and the PD text is
    # no stricter. Each PD document records the file marking and its
    # attribution verbatim (metadata text_license / text_attribution).
    #
    # Outside this source's scope: la-vulgata, en-brenton/kjv and grc-nt
    # (PD), grc-ot (GPL-3.0), ro-1914 (CC BY-SA, Wikisource) and zh-1910
    # (held elsewhere, or not Bible witnesses this shelf needs). A verse
    # file of any non-admitted edition in the workdir is SKIPPED BY RULE.
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
    # combining marks in non-canonical order on 33,484 of 36,312 verses,
    # cs-eliz on one, 1 Pet 1:10; neither ron nor chu is NFC-exempt).
    # Languages, per edition:
    # - ro-1688 → ron-Cyrl; config/lect_overrides.yml resolves it to
    #   ro:old~cyrl (the Old Romanian stage, band [1521, 1780]).
    # - cs-eliz → chu; the override resolves it to chu:ncs — the registry
    #   node names this Bible as fixing the post-Nikonian standard (the
    #   elizabeth-bible row's mold), the 1751 year inside its band.
    # - ka-mcxeta → oge, the Old Georgian anchor, by the edition's own
    #   title ("ძველი ქართულით", in Old Georgian; the dump's language field
    #   says ka). NOT ka:mid: the NT translation is 11th-c. Old Georgian,
    #   and the OT manuscript, though copied in the Middle Georgian band,
    #   carries the church literary language. Declared coarse: the
    #   Mtskheta OT is a compilation whose books' translation dates differ;
    #   the source does not say which, so no book is staged apart.
    # Date: the edition year the dump records, date_class edition (ro-1688
    # 1688; cs-eliz 1751). ka-mcxeta has no year: its OT books carry the
    # witness date the dump states for the Mtskheta manuscript (XVII–XVIII
    # c. → 1601–1800, class-less), its NT books the translation date it
    # states for the Athonite version (XI c. → 1001–1100, class
    # composition).
    #
    # == License drift guard
    #
    # Parse re-reads manifest.json: the bible layer must still be CC-BY-4.0
    # and each admitted file must carry exactly its ruled marking (ro-1688
    # none of its own; cs-eliz and ka-mcxeta "PD") — anything else is a
    # ParseError naming what changed, never a silent ingest.
    #
    # == Census (dump 2026-09-21; ro-1688 read 2026-11-02, the PD pair 2026-11-03)
    #
    # ro-1688: 36,312 verses / 79 books; 2,870 verses carry a canonical
    # address different from their own (the Psalter's Hebrew-style
    # numbering 1,213, Sirach 715, the Daniel additions as own books 181,
    # …). cs-eliz: 36,961 verses / 77 books (2–3 Esdras and 3 Maccabees
    # included), every canonRef its own address. ka-mcxeta: 32,425 verses /
    # 73 books (no Maccabees; Wisdom 119, Sirach 19, Ecclesiastes 86 verses
    # — the manuscript's own short books), canonRef identity. Manifest
    # `records` reconcile exactly (36,312 · 36,961 · 32,425). Expected
    # sync: 229 documents / 105,698 passages (79/36,312 + 77/36,961 +
    # 73/32,425), 0 errored.
    class TypikonBible < Nabu::Adapter
      DUMP_URL = "https://typikon.info/dump/2026-09-21/"

      # subdir => [url, landed filename] — fetch and probe read the same rows.
      FILES = {
        "manifest" => ["#{DUMP_URL}manifest.json", "manifest.json"].freeze,
        "bible-editions" => ["#{DUMP_URL}bible/bible-editions.jsonl.gz", "bible-editions.jsonl.gz"].freeze,
        "bible-books" => ["#{DUMP_URL}bible/bible-books.jsonl.gz", "bible-books.jsonl.gz"].freeze,
        "bible-verses-ro-1688" => ["#{DUMP_URL}bible/bible-verses-ro-1688.jsonl.gz",
                                   "bible-verses-ro-1688.jsonl.gz"].freeze,
        "bible-verses-cs-eliz" => ["#{DUMP_URL}bible/bible-verses-cs-eliz.jsonl.gz",
                                   "bible-verses-cs-eliz.jsonl.gz"].freeze,
        "bible-verses-ka-mcxeta" => ["#{DUMP_URL}bible/bible-verses-ka-mcxeta.jsonl.gz",
                                     "bible-verses-ka-mcxeta.jsonl.gz"].freeze
      }.freeze

      # One admitted edition: its document language, the license id its
      # verse file must carry of its own in manifest.json (nil = none, the
      # layer's), and the witness dates for an edition the dump gives no
      # year ({ testament => metadata date }).
      Edition = Data.define(:language, :file_license, :witness_dates)

      NT_BOOKS = %w[matfeya marka luki ioanna deyaniya iakova 1-petra 2-petra 1-ioanna-posl 2-ioanna-posl
                    3-ioanna-posl iudy rimlyanam 1-korinfyanam 2-korinfyanam galatam efesyanam filippiytsam
                    kolossyanam 1-fessaloniyitsam 2-fessaloniyitsam 1-timofeyu 2-timofeyu titu filimonu evreyam
                    otkrovenie].to_set.freeze

      # Edition code => Edition, in ruled order (cs-eliz and ka-mcxeta
      # owner-ruled 2026-11-03).
      ADMITTED = {
        "ro-1688" => Edition.new(language: "ron-Cyrl", file_license: nil, witness_dates: nil),
        "cs-eliz" => Edition.new(language: "chu", file_license: "PD", witness_dates: nil),
        "ka-mcxeta" => Edition.new(
          language: "oge", file_license: "PD",
          witness_dates: {
            ot: { "not_before" => 1601, "not_after" => 1800,
                  "raw" => "XVII–XVIII c. — the Mtskheta manuscript the dump names for the Old Testament " \
                           "(\"Мцхетская рукопись XVII–XVIII века\")" }.freeze,
            nt: { "not_before" => 1001, "not_after" => 1100, "class" => "composition",
                  "raw" => "XI c. — the Athonite translation of Euthymius and George the dump names for " \
                           "the New Testament (\"перевод Святогорцев — XI\")" }.freeze
          }.freeze
        )
      }.freeze

      LAYER_LICENSE = "CC-BY-4.0"

      MANIFEST = Nabu::SourceManifest.new(
        id: "typikon-bible",
        name: "typikon.info Bible layer — the 1688 Bucharest Bible, the Elizabeth Bible in Church Cyrillic " \
              "and the Old Georgian Bible (dump 2026-09-21)",
        license: "CC BY 4.0 (manifest.json bible layer license CC-BY-4.0; rationale verbatim: \"Румынскую " \
                 "кириллицу 1688 и китайский Новый Завет 1910 набирали мы — они под лицензией слоя\"; " \
                 "citation \"Корпус «Уставные чтения» (typikon.info), CC BY 4.0\", DOI 10.5281/zenodo.22883964); " \
                 "the cs-eliz and ka-mcxeta verse files carry their own marking PD (\"Общественное достояние " \
                 "(Public Domain Mark 1.0)\"), admitted under it owner-ruled 2026-11-03 although the layer " \
                 "rationale says the Church Slavonic digitization gives no redistribution permission",
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
        files = verse_files(workdir)
        ADMITTED.each_key do |code|
          path = files[code] or next
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
        admitted = ADMITTED.fetch(code)
        entry = check_license!(workdir, code, admitted)
        tables = tables(workdir)
        book = tables.books.fetch(document_ref.metadata.fetch("book_id"))
        edition = tables.editions.fetch(code)
        language = admitted.language
        document = Nabu::Document.new(urn: document_ref.id, language: language,
                                      title: Normalize.nfc(book.fetch("name")), canonical_path: document_ref.path,
                                      metadata: metadata_for(edition, book, entry, admitted))
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

      def metadata_for(edition, book, entry, admitted)
        {
          "edition" => edition.fetch("code"),
          "edition_title" => Normalize.nfc(edition.fetch("title")),
          "versification" => edition["versification"],
          "edition_source" => edition["sourceLink"],
          "book" => book.fetch("slug"),
          "canon_book" => book["canonId"],
          "date" => date_for(edition, book, admitted),
          "text_license" => entry.dig("license", "id"),
          "text_attribution" => entry["attribution"] && Normalize.nfc(entry["attribution"])
        }.compact
      end

      # The edition year when the dump records one (class edition); else
      # the edition's witness date for the book's testament; else nil.
      def date_for(edition, book, admitted)
        if (year = edition["year"])
          return { "not_before" => year, "not_after" => year, "class" => "edition",
                   "raw" => "#{year} — the edition year the dump records (bible-editions year)" }
        end

        admitted.witness_dates&.fetch(NT_BOOKS.include?(book["canonId"]) ? :nt : :ot)&.dup
      end

      # Re-reads the bible layer of manifest.json and returns the verse
      # file's entry; raises when the layer license or the file's own
      # marking is not the ruled one.
      def check_license!(workdir, code, admitted)
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
        return entry if entry && entry.dig("license", "id") == admitted.file_license

        ruled = admitted.file_license ? "its ruled marking #{admitted.file_license}" : "the layer license"
        raise Nabu::ParseError, "#{path}: bible-verses-#{code} is no longer listed under #{ruled} " \
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
