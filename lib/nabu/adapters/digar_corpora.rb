# frozen_string_literal: true

require "fileutils"

require_relative "estnltk_tsv_parser"

module Nabu
  module Adapters
    # The DIGAR corpus of freely usable publications: the National
    # Library of Estonia's (Eesti Rahvusraamatukogu, RaRa) text-mining
    # corpus of the Estonian-language books its digital archive DIGAR
    # serves without restriction — 3,416 prints from the 1620s to the
    # 2010s, most of them 1900–1949, a long Fraktur-era tail (the 1535–1850
    # "red book" rarities, catechisms, hymn sheets, chapbooks, decrees)
    # and the interwar book mass (children's books, plays, statutes,
    # textbooks, address books). Corpus built by Peeter Tinits (Tallinn
    # University) in 2018: each DIGAR PDF exported with pdf2txt and run
    # through EstNLTK 1.4.1 (the estnltk-tsv family's class note).
    #
    # == What data.digar.ee actually serves (census 2026-11-23)
    #
    # The open-data page (data.digar.ee, the pre-2023 address; its
    # successor digilab.rara.ee carries the rights page) offers, as text:
    #
    # - processed_pdf_tsv.zip — "DIGARi korpus vabalt kasutataval ainesel"
    #   (972,354,373 B, Last-Modified 2018-10-09; 3,416 members, Deflate64,
    #   5.67 GB unpacked): one token table per book, named by the book's
    #   ESTER/ERB record id (b10342369.pdf.txt.tsv). THE TEXT GRAIN.
    # - processed_txt_tsv.zip — "Rahvusbibliograafia tekstikaeve korpus"
    #   (121,540,205 B, 2018-10-09; 5 members): despite its name, NO text —
    #   the Estonian National Bibliography (ERB) metadata: the raw MARC
    #   record of every Estonian-language book (ERB_eestikeelne_raamat_
    #   July_2018.tsv, 193,848 records as row-per-field TSV), Tinits's
    #   processed derivatives of it (ERB_works_v, ERB_works_processed,
    #   ERB_genres_processed) and the per-file OCR census
    #   fileinfo_stored_pub.tsv. Fetched as the metadata sidecar.
    #
    # Not here: the n-gram lists (modern fiction frequency tables — no
    # running text), the Kratt keyword-prototype files (meta.jsonl; the
    # full_texts.zip and morphological_data.zip links now serve a 178-byte
    # stub), the raw .txt export ("Küsi allikmaterjali .txt kujul (3416
    # faili kokku 196MB) data@nlib.ee" — email-gated), and the newspapers:
    # DEA (dea.digar.ee, 1821–) serves no bulk text — its article-text-XML
    # endpoint sits behind a Cloudflare challenge, bulk access is the
    # University of Tartu HPC OnDemand environment by request, and the
    # 2026 "Vaba juurdepääsuga keelekorpus" (526 million tokens, books +
    # newspapers + journals) carries no download link (2026-11-23).
    #
    # == License (read first-hand 2026-11-23, verbatim)
    #
    # data.digar.ee, page-wide: "Avaandmete kasutamisel nõustute Creative
    # Commons Public Domain (CC BY-SA 3.0 EE) litsentsitingimustega" —
    # the wording CONFLATES public domain with CC BY-SA 3.0 Estonia, and
    # neither text dataset carries its own statement (the corpus section
    # says only that its texts are those "DIGARis arhiveeritud ja
    # kasutajatele piiranguteta kättesaadavaks tehtud"; the ERB section
    # "Tugineb vabalt kättesaadaval ainesel ja on vabalt kasutamiseks
    # kõigile"). digilab.rara.ee's rights page (30.03.2023): items marked
    # "Vabakasutus" carry the Public Domain Mark 1.0 and ERB/DIGAR
    # metadata is CC0. The stricter reading wins (the syriac-htr-gt
    # precedent): the processed corpus — Tinits's derivation, served under
    # the page-wide statement — is CC BY-SA 3.0 EE → `attribution`, share-
    # alike. Each record's own rights field (MARC 542: "Vabakasutus" +
    # the PDM URL, on most fixture records) rides document metadata; it
    # mints no per-document override.
    #
    # == Grains and accounting
    #
    # Document = book (one token table), urn:nabu:digar-corpora:<ERB id>.
    # Rejected by rule, counted in discovery_skips: the header-only tables
    # (pdf2txt extracted nothing — 531 of 3,416 by the fileinfo census, 186
    # bytes each). Skipped by rule at parse (DocumentSkipped): a table
    # whose every token is the digitizer's stamp (an image-only PDF whose
    # sole text layer is the "Eesti Rahvusraamatukogu digitaalarhiiv DIGAR"
    # footer — the fixture's 1841 Jenowewa). The metadata sidecar's files
    # are never documents. Reconciliation: upstream advertises 3,416 files
    # (the page's "3416 faili", the zip's 3,416 members, the fileinfo's
    # 3,416 rows) = 2,885 non-empty tables (documents or stamp-only skips;
    # the stamp-only share is censused at the first real sync) + 531
    # header-only skips.
    #
    # == Metadata (the aggressive-mining pass, all from the raw MARC)
    #
    # Joined on the record id (MARC 001) — all 3,416 books carry a raw
    # MARC record (Tinits's processed ERB_works table misses 6, so it is
    # not the join). Mined: title (245 $a$n$p$b, ISBD tail punctuation
    # dropped) and statement of responsibility ($c); author (100) and
    # contributors with roles (700); edition (250); imprint (260: place,
    # publisher, printer and printing place; brackets dropped, "s.l."/"s.n."
    # mint nothing, a cataloguer's "?" conjecture flagged); the normalized
    # place (752 $d); the date — 008 date1 (u-digits widen to the
    # decade/century, a 008 range type takes date2), class edition (the
    # print's date, never the text's composition), 260 $c riding raw; the
    # languages (041 $a, $h originals of translations; 008's language when
    # 041 is absent); genre/form headings (655 → facet genre, folded in
    # config/kind_map.yml, open vocabulary); notes (500); the rights field
    # (542); the DIGAR link (856 $u); the OCR census (fileinfo's
    # prop_nopunct_unsolved — the share of non-punctuation tokens EstNLTK
    # could not analyse, upstream's own quality proxy).
    #
    # Deliberately coarse, declared: every document is `et` (008 reads
    # est for all 3,416); a bilingual book's 041 languages ride metadata,
    # never per-passage language. Upstream's OCR caveat, verbatim: "OCR-i
    # kvaliteet võib olla ebaühtlane".
    class DigarCorpora < Nabu::Adapter
      SLUG = "digar-corpora"

      TEXT_ZIP_URL = "https://data.digar.ee/processed_pdf_tsv.zip"
      META_ZIP_URL = "https://data.digar.ee/processed_txt_tsv.zip"

      TEXT_DIR = "processed_pdf_tsv"
      META_DIR = "processed_txt_tsv"
      MARC_FILE = "ERB_eestikeelne_raamat_July_2018.tsv"
      FILEINFO_FILE = "fileinfo_stored_pub.tsv"

      # The metadata zip's members: the two this adapter reads plus the
      # three processed derivatives it does not (same records, Tinits's
      # cleaning — the raw MARC is the complete join).
      META_FILES = [MARC_FILE, FILEINFO_FILE, "ERB_works_v_29.07.2018.tsv",
                    "ERB_works_processed_v_29.07.2018.tsv", "ERB_genres_processed_v_29.07.2018.tsv"].freeze

      TABLE = /\A(b\d{7}[\dx])\.pdf\.txt\.tsv\z/

      # Root-level names that are never upstream's: the attic, and the
      # test fixture's own README/manifest furniture.
      ROOT_FURNITURE = [ATTIC_DIRNAME, Nabu::ZipFetch::STATE_FILE, "README.md", "manifest.yml"].freeze

      URN_PREFIX = "urn:nabu:#{SLUG}:".freeze
      LANGUAGE = "et"

      OCR_NOTE = "OCR-i kvaliteet võib olla ebaühtlane (data.digar.ee: pdf2txt export of the DIGAR PDFs, " \
                 "uncorrected OCR for all but born-digital prints)"

      MARC_TAGS = %w[001 008 041 100 245 250 260 500 542 655 700 752 856].freeze

      # MARC 008/06 date types whose date2 closes a range.
      RANGE_TYPES = %w[i k m q].freeze

      NO_PLACE = /\As\.\s?l\.?\z/i
      NO_PUBLISHER = /\As\.\s?n\.?\z/i

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "DIGAR corpus of freely usable publications (National Library of Estonia)",
        license: "CC BY-SA 3.0 EE — data.digar.ee: \"Avaandmete kasutamisel nõustute Creative Commons Public " \
                 "Domain (CC BY-SA 3.0 EE) litsentsitingimustega\" (the wording conflates PD and BY-SA; the " \
                 "stricter reading is taken). The underlying prints are DIGAR \"Vabakasutus\" items (CC PDM " \
                 "1.0, digilab.rara.ee rights page); ERB metadata CC0",
        license_class: "attribution",
        upstream_url: "https://data.digar.ee/",
        parser_family: "estnltk-tsv",
        credit: "DIGAR corpus of freely usable publications, Eesti Rahvusraamatukogu (National Library of " \
                "Estonia); processed by Peeter Tinits (Tallinn University), 2018 — CC BY-SA 3.0 EE"
      )

      def self.manifest = MANIFEST

      # Parallel replay (audited): parse reads one token table plus the
      # memoized MARC/fileinfo indexes (pure functions of the workdir,
      # rebuilt per worker); no handle crosses refs.
      def self.parallel_parse? = true

      def self.materialized_paths = [TEXT_DIR, META_DIR].map { |dir| File.join(dir, Nabu::ZipFetch::STATE_FILE) }

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        { TEXT_DIR => TEXT_ZIP_URL, META_DIR => META_ZIP_URL }.map do |dir, url|
          Nabu::Adapter::HttpProbeTarget.new(label: File.basename(url), zip_url: url, metadata_url: nil,
                                             state_subdir: dir, state_file: Nabu::ZipFetch::STATE_FILE)
        end
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        tables(workdir).each do |id, path|
          next if EstnltkTsvParser.empty?(path)

          yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{id}", path: path,
                                      metadata: { "erb_id" => id })
        end
      end

      def discovery_skips(workdir)
        return Nabu::Adapter::DiscoverySkips.new unless Dir.exist?(workdir)

        empty = tables(workdir).count { |_, path| EstnltkTsvParser.empty?(path) }
        stray = stray_files(workdir)
        notes = []
        notes << "#{empty} header-only token table(s) — pdf2txt extracted no text" if empty.positive?
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: empty, unrecognized: stray.size,
                                          notes: notes + stray.map { |rel| "unrecognized file #{rel}" })
      end

      def parse(document_ref)
        id = document_ref.metadata.fetch("erb_id")
        book = EstnltkTsvParser.new.parse(document_ref.path)
        if book.windows.empty?
          raise Nabu::DocumentSkipped.new("#{document_ref.path}: only the digitizer's stamp",
                                          reason: "stamp-only table (image-only PDF)")
        end

        workdir = workdir_of(document_ref.path)
        record = marc_index(workdir)[id]
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: record && title_of(record),
          canonical_path: document_ref.path,
          metadata: metadata_for(id, record, fileinfo_index(workdir)[id], book)
        )
        book.windows.each_with_index do |window, index|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{index + 1}", language: LANGUAGE, text: window.text, sequence: index,
            annotations: { "rows" => [window.first_row, window.last_row] }
          )
        end
        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        fetches = { TEXT_DIR => TEXT_ZIP_URL, META_DIR => META_ZIP_URL }.map do |dir, url|
          [url, fetch_zip(workdir, dir, url, progress, force)]
        end
        notes = fetches.map do |url, fetch|
          state = fetch.not_modified? ? "not modified (304)" : "unpacked (sha256 #{fetch.sha})"
          ["#{File.basename(url)} #{state}", attic_notes(fetch.atticked)].compact.join(", ")
        end
        Nabu::FetchReport.new(sha: fetches.first.last.sha, fetched_at: Time.now, notes: notes.join("; "),
                              repos: fetches.to_h { |url, fetch| [url, fetch.sha] })
      rescue Nabu::ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def fetch_zip(workdir, dir, url, progress, force)
        target = File.join(workdir, dir)
        FileUtils.mkdir_p(target)
        fetch = Nabu::ZipFetch.new(url: url, dir: target, progress: progress, stream: true,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME, dir))
        begin
          fetch.prepare!
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        fetch
      end

      # [id, absolute path] for every token table under +workdir+, sorted.
      def tables(workdir)
        dir = File.join(workdir, TEXT_DIR)
        return [] unless Dir.exist?(dir)

        Dir.children(dir).sort.filter_map do |name|
          match = TABLE.match(name)
          [match[1], File.expand_path(File.join(dir, name))] if match
        end
      end

      def stray_files(workdir)
        known = { TEXT_DIR => ->(name) { TABLE.match?(name) }, META_DIR => ->(name) { META_FILES.include?(name) } }
        Dir.children(workdir).sort.flat_map do |entry|
          next [] if ROOT_FURNITURE.include?(entry)

          rule = known[entry]
          next [entry] if rule.nil?

          Dir.children(File.join(workdir, entry)).sort.filter_map do |name|
            "#{entry}/#{name}" unless name == Nabu::ZipFetch::STATE_FILE || rule.call(name)
          end
        end
      end

      # The source workdir behind a table path (live or attic).
      def workdir_of(path)
        dir = File.dirname(path, 2)
        File.basename(dir) == ATTIC_DIRNAME ? File.dirname(dir) : dir
      end

      def meta_path(workdir, file)
        [File.join(workdir, META_DIR, file), File.join(workdir, ATTIC_DIRNAME, META_DIR, file)]
          .find { |path| File.file?(path) }
      end

      # id → { tag → [content, …] } for the books the workdir holds, from
      # one streamed pass over the row-per-field MARC TSV (RecordNumber,
      # Tags, Indicators, Content; a blank row closes a record).
      def marc_index(workdir)
        @marc_index ||= {}
        @marc_index[workdir] ||= build_marc_index(workdir)
      end

      def build_marc_index(workdir)
        path = meta_path(workdir, MARC_FILE)
        return {} if path.nil?

        wanted = held_ids(workdir)
        index = {}
        record = nil
        number = nil
        SourceRead.utf8_lines(path, label: "ERB MARC dump") do |line|
          cells = line.chomp.split("\t", -1)
          next if cells.size < 4 || cells[0] == "RecordNumber"

          if cells[0] != number
            store_record(index, record, wanted)
            number = cells[0]
            record = {}
          end
          next unless MARC_TAGS.include?(cells[1])

          (record[cells[1]] ||= []) << Normalize.nfc(cells[3])
        end
        store_record(index, record, wanted)
        index
      end

      def store_record(index, record, wanted)
        id = record&.dig("001", 0)
        index[id] = record if id && wanted.include?(id)
      end

      def held_ids(workdir)
        ids = tables(workdir).map(&:first)
        ids.concat(tables(File.join(workdir, ATTIC_DIRNAME)).map(&:first))
        ids.to_set
      end

      # id → the fileinfo row (filesize, nrows, … prop_nopunct_unsolved).
      def fileinfo_index(workdir)
        @fileinfo_index ||= {}
        @fileinfo_index[workdir] ||= build_fileinfo_index(workdir)
      end

      def build_fileinfo_index(workdir)
        path = meta_path(workdir, FILEINFO_FILE)
        return {} if path.nil?

        lines = SourceRead.utf8_file(path, label: "fileinfo census").split("\n")
        header = lines.shift.to_s.split("\t", -1)
        lines.each_with_object({}) do |line, index|
          row = header.zip(line.split("\t", -1)).to_h
          match = TABLE.match(row["filename"].to_s)
          index[match[1]] = row if match
        end
      end

      # -- MARC field helpers -------------------------------------------

      # "$aPerno :$bF. W. Borm,$c1841" → [["a", "Perno :"], ["b", …], …]
      def subfields(content)
        content.to_s.scan(/\$(\w)([^$]*)/).map { |code, value| [code, value.strip] }
      end

      def first_sub(record, tag, code)
        Array(record[tag]).each do |content|
          subfields(content).each { |c, value| return value if c == code && !value.empty? }
        end
        nil
      end

      def all_subs(record, tag, code)
        Array(record[tag]).flat_map do |content|
          subfields(content).filter_map { |c, value| value if c == code && !value.empty? }
        end
      end

      # ISBD tail punctuation (" /", " :", ";", ",", ".") off a value.
      def clean(value)
        return nil if value.nil?

        out = value.sub(%r{[\s/:;,.=]+\z}, "").strip
        out.empty? ? nil : out
      end

      def title_of(record)
        parts = subfields(Array(record["245"]).first).filter_map { |code, value| value if %w[a n p b].include?(code) }
        balanced(clean(parts.join(" ").squeeze(" ")))
      end

      # A supplied-bracket pair the subfield split cut in two ("[värsid
      # lastele /$cJ. Oro]") loses its brackets; a whole pair stays.
      def balanced(value)
        return value if value.nil? || value.count("[") == value.count("]")

        clean(value.delete("[]"))
      end

      def metadata_for(id, record, info, book)
        meta = { "erb_id" => id, "text_nature" => "machine-ocr", "ocr_note" => OCR_NOTE,
                 "token_count" => book.token_count, "stamps_dropped" => book.stamps,
                 "ocr_unsolved_share" => unsolved_share(info) }
        meta.merge!(record_metadata(record)) if record
        meta.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      end

      def record_metadata(record)
        genres = all_subs(record, "655", "a").filter_map { |value| clean(value) }.uniq
        {
          "statement_of_responsibility" => balanced(clean(first_sub(record, "245", "c"))),
          "author" => clean(first_sub(record, "100", "a")),
          "author_dates" => clean(first_sub(record, "100", "d")),
          "contributors" => contributors(record),
          "edition" => clean(first_sub(record, "250", "a"))
        }.merge(imprint(record)).merge(
          "date" => date_of(record),
          "languages" => languages(record),
          "original_languages" => all_subs(record, "041", "h"),
          "genres" => genres,
          "facets" => genres.empty? ? nil : { "genre" => genres },
          "notes" => all_subs(record, "500", "a"),
          "rights" => clean(first_sub(record, "542", "l")),
          "rights_url" => first_sub(record, "542", "u"),
          "digar_url" => first_sub(record, "856", "u")
        )
      end

      def contributors(record)
        Array(record["700"]).filter_map do |content|
          subs = subfields(content).to_h { |code, value| [code, value] }
          name = clean(subs["a"])
          next if name.nil?

          { "name" => name, "dates" => clean(subs["d"]), "role" => clean(subs["e"]) }.compact
        end
      end

      def imprint(record)
        place = clean(bare(first_sub(record, "260", "a")))
        conjectural = place&.end_with?("?")
        place = clean(place&.delete_suffix("?"))
        place = nil if place&.match?(NO_PLACE)
        publisher = clean(bare(first_sub(record, "260", "b")))
        publisher = nil if publisher&.match?(NO_PUBLISHER)
        { "place" => place, "place_conjectural" => (conjectural && place ? true : nil),
          "place_normalized" => clean(first_sub(record, "752", "d")),
          "publisher" => publisher,
          "printer" => clean(bare(first_sub(record, "260", "f"))),
          "printing_place" => clean(bare(first_sub(record, "260", "e"))) }
      end

      # Supplied brackets dropped: "[Riia :" → "Riia :", "(Riia :" → "Riia :".
      def bare(value)
        value&.delete("[]()")&.strip
      end

      # 008/07-10 date1 (u-digits widen), a range type closing on date2.
      def date_of(record)
        fixed = record.dig("008", 0).to_s
        from = year_bounds(fixed[7, 4])
        return nil if from.nil?

        to = RANGE_TYPES.include?(fixed[6]) ? year_bounds(fixed[11, 4]) : nil
        not_after = to ? [to.last, from.last].max : from.last
        raw = ["ERB 008 #{fixed[6]}#{fixed[7, 4]}#{fixed[11, 4] if to}", bare(first_sub(record, "260", "c"))].compact
        { "not_before" => from.first, "not_after" => not_after, "raw" => raw.join("; "), "class" => "edition" }
      end

      def year_bounds(value)
        return nil unless value.to_s.match?(/\A\d[\du]{3}\z/) && !value.end_with?("uuu")

        [Integer(value.tr("u", "0"), 10), Integer(value.tr("u", "9"), 10)]
      end

      def languages(record)
        listed = all_subs(record, "041", "a")
        return listed unless listed.empty?

        code = record.dig("008", 0).to_s[35, 3].to_s.strip
        code.empty? ? [] : [code]
      end

      def unsolved_share(info)
        value = info&.fetch("prop_nopunct_unsolved", nil).to_s
        value.empty? ? nil : Float(value).round(3)
      rescue ArgumentError
        nil
      end
    end
  end
end
