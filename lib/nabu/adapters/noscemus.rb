# frozen_string_literal: true

require "nokogiri"
require_relative "../zip_fetch"
require_relative "../file_fetch"
require_relative "source_read"

module Nabu
  module Adapters
    # noscemus — the NOSCEMUS Digital Sourcebook (Stefan Zathammer, Universität
    # Innsbruck; Zenodo record 15040256, 2025-03-17, concept 15040255): the
    # plain text of the 1,050 digital copies collected by the Noscemus Wiki —
    # early-modern scientific Latin, the ERC NOSCEMUS project's ("Nova
    # Scientia: Early Modern Scientific Literature and Latin", grant 741374)
    # survey of how Latin literature engaged with the sciences 1500–1800:
    # medicine, astronomy/astrology/cosmography, biology, mathematics, the
    # earth sciences, physics, geography, alchemy — monographs, encyclopedic
    # works, dissertations, didactic and panegyric poems, letters, orations,
    # tables, dictionaries, journal volumes (Acta eruditorum, academy
    # Commentarii). Prints from 1479 (Cermisonus, Venice) to the 19th
    # century, a few modern editions among them (Huygens' Oeuvres complètes
    # vol. 17, 1932; The Works of John Caius, 1912).
    #
    # == The text is UNCORRECTED machine HTR — declared on every document
    #
    # The record, verbatim: "The automatic transcriptions were produced in
    # Transkribus using text recognition models specifically trained for the
    # recognition of early modern (Latin) prints as part of the NOSCEMUS
    # project. They have not undergone manual editing or correction." Every
    # document carries text_nature "machine-htr" and that sentence as
    # text_note (the mdz-protestant posture). Quality varies by copy: most
    # prints read well (long s resolved, line-end hyphens kept as upstream's
    # ¬), some pages are noise — Palingenio's Zodiacus vitae (5314216) opens
    # with mirror-read pages ("VTOLSIdA" for EPISTOLA), and Google Books
    # copies carry "Digitized by Google" stamps. Canonical means canonical:
    # nothing is corrected here.
    #
    # == License (read first-hand 2026-11-05)
    #
    # Both records' license field: cc-by-4.0 (Creative Commons Attribution
    # 4.0 International) → attribution. The sourcebook credits Stefan
    # Zathammer; the wiki backup (2023-03-31) its nine editors (Akopyan,
    # Barton, Baumgartner, Berrens, Kirchler, Korenjak, Luggin, Tautschnig,
    # Zathammer). The underlying prints are public domain by age (the
    # 1912/1932 editions aside — CC BY is the deposit's grant over the
    # transcription either way).
    #
    # == Delivery grains (census of the full zip, 2026-11-05)
    #
    # - Noscemus_Digital_Sourcebook.zip (301,102,275 bytes, md5 = the
    #   record's ccd475d9…7b285; 2,101 members, 791,925,300 bytes unpacked)
    #   — the archive, unpacked (single top dir stripped), never a document.
    #   183 member names are CP437 bytes (no UTF-8 flag) with the real UTF-8
    #   name in the Info-ZIP Unicode Path extra field (0x7075): `unzip`
    #   dies on them on APFS and the salvage reader would drop them, so the
    #   fetch unpacks with bsdtar (ZipFetch archive: :zip_bsdtar).
    # - <transkribus-id>/<Author_-_Title__Place_Year[_pdf]>.txt — TAKEN: the
    #   DOCUMENT, one Transkribus document = one digital copy (1,050 dirs,
    #   exactly one .txt each; 1,031 *_pdf.txt + 19 plain .txt names). The
    #   file is Transkribus's plain-text export: a "Metadata section" header
    #   (Title — "Author - Title. Place Year.pdf", the copy's own label;
    #   Author; Number of Pages; Created From/To; Sripttype; Language, null
    #   on 1,039) taken as metadata, then the body.
    # - the text region — TAKEN: the PASSAGE. The export carries no page
    #   break and no paragraph mark (lines end in a single newline; a blank
    #   line inside text occurs 1,052 times corpus-wide); Transkribus text
    #   regions are separated by two or more blank lines (659,796 + longer
    #   runs). A region is in practice a page's main text block, or a
    #   running head / page number / catchword region beside it (675,095
    #   non-blank regions over the 1,038 documents — 555,797 passages +
    #   119,298 marks; median ~700 bytes, max ~21 KB — no oversized
    #   passage). So passage = region, cited by its 1-based ordinal among
    #   the work's non-blank regions (urn:nabu:noscemus:1031760:6), lines
    #   joined by newline, text verbatim (NFC). A region with no letter at
    #   all (a page number "6", a signature "2\n9", "1620.") mints no
    #   passage: it rides the NEXT passage's annotations as "marks" (in
    #   order), or the last passage's "trailing_marks" at the end of the
    #   work — nothing is dropped, and the citation ordinals keep their gaps.
    # - empty-text works — SKIPPED BY RULE (Nabu::DocumentSkipped, "no
    #   transcribed text"): 12 copies whose body is blank or letterless
    #   (census: Crüger's Uranodormus cometicus 736346 — pinned —, Camerarius,
    #   de Laet, Mercator's Atlas, Großinger vol. 3, Franck, Nieremberg,
    #   Inghirami, the two Ploucquet volumes, Reuss, Rheticus).
    # - wiki/works, wiki/authors — the Noscemus Wiki backup (Zenodo 7855322,
    #   2023-03-31, MediaWiki XML of {{Works}} / {{Authors}} pages), TAKEN
    #   as the metadata join. Works: 989 pages; 948 link at least one
    #   Transkribus document (a work may list several copies or volumes —
    #   several links on one line among them; a host volume may hold several
    #   works, each "in: …" at a /pages/<n> start page; one link carries a
    #   stray %20 before the id). The join covers 1,012 of the 1,050 copies;
    #   38 copies (later additions — the Principia editions, Spinoza's
    #   Ethica, the Göttingen Commentationes volumes …) have no wiki page
    #   and keep the header's own metadata. Wiki works with no copy here —
    #   41 whose Transkribus-ID reads "not available" or is empty, 3 whose
    #   ids name no directory in the zip — are metadata about nothing held:
    #   counted (.wiki_census), never documents. Authors: 850 pages (Year of birth / death, GND).
    # - wiki/literature (2023-03-31_noscemus_literature.xml, 1,853
    #   secondary-literature records) — REJECTED: bibliography of modern
    #   scholarship, not text metadata; never fetched (a specimen page is
    #   pinned in the fixture).
    # Reconciliation: 1,050 directories = 1,050 text files = the record's
    # 1,050 works; 1,038 documents + 12 skipped by rule.
    #
    # == Metadata, dating, places (the aggressive-mining law)
    #
    # The copy's own Title label is the document title and its imprint
    # source: the LAST year (or range, "1675-79" → 1675–1679, "[1723–1725]")
    # is the print date (MetadataDates :structured, raw = the imprint
    # segment, date_basis "imprint" — the print IS the document); the
    # segment before it is the imprint place ("London", "Leipzig &
    # Copenhagen" → place = the first town, places = all; "s. l." and a
    # label without a separating stop name none — declared coarse: a
    # printer's name sometimes stands where the town should, e.g. "Coulon &
    # Willem"; upstream's typos — "Pairs", "Viena" — ride verbatim). A
    # label naming no town ("… remediis. 1699") places by the whole-copy
    # wiki work's Place (place_basis "wiki_place"). No year in the label
    # (2 copies) → the Transkribus Created From/To year (date_basis
    # "transkribus_created" — typed, but on 5 of 1,047 it disagrees with the
    # label: the work's or a misread year), then the joined wiki work's Year
    # (date_basis "wiki_year"). The wiki's work-level fields ride per
    # joined work (title, author, full title, year, place, printer, era,
    # In, the copy note and start page; the descriptive prose stays in
    # wiki/works); its Form/Genre and Discipline/Content become the genre
    # and discipline facets (the union over the joined works; genre folds
    # through config/kind_map.yml). Authors: the joined wiki work's Author
    # list (else the header's, split on " & "), each with the Authors
    # page's life years (raw: "c. 460 BC") and GND id.
    #
    # == Overlap (recorded, not deduplicated — witnesses)
    #
    # Some London prints are also keyed in eebo-tcp (Bacon's Instauratio
    # magna, London 1620 — 1031760 here): there a TCP keyed transcription of
    # an EEBO copy, here the HTR of another scan — a different witness,
    # ingested with its own provenance. corpus-corporum's "noscemus"
    # subcorpus (3 texts) is a separately edited selection.
    class Noscemus < Nabu::Adapter
      SLUG = "noscemus"
      LANGUAGE = "lat"
      URN_PREFIX = "urn:nabu:noscemus:"
      RECORD_URL = "https://zenodo.org/records/15040256"
      WIKI_RECORD_URL = "https://zenodo.org/records/7855322"
      ZIP_URL = "https://zenodo.org/api/records/15040256/files/Noscemus_Digital_Sourcebook.zip/content"
      WIKI_DIRNAME = "wiki"
      WIKI_FILES = {
        works: { filename: "2023-03-31_noscemus_works.xml",
                 url: "https://zenodo.org/api/records/7855322/files/2023-03-31_noscemus_works.xml/content" },
        authors: { filename: "2023-03-31_noscemus_authors.xml",
                   url: "https://zenodo.org/api/records/7855322/files/2023-03-31_noscemus_authors.xml/content" }
      }.freeze
      # The records' own md5 checksums (Zenodo publishes md5); downloaded and
      # matched 2026-11-05 (zip sha256 410cbd39…0fcc).
      PINS = { zip: "ccd475d900ee5123d41d281b7234b285", works: "983b5bfdd22d7c3a9f064dd81b8e0e0a",
               authors: "c68af30807dda50d86367eb2a1c1f3da" }.freeze

      TEXT_NOTE = "Uncorrected Transkribus HTR. The record (Zenodo 15040256): \"The automatic transcriptions " \
                  "were produced in Transkribus using text recognition models specifically trained for the " \
                  "recognition of early modern (Latin) prints as part of the NOSCEMUS project. They have not " \
                  "undergone manual editing or correction.\""
      HEADER_END = /^-+\nEnd of metadata section\n-+\n/
      REGION_BREAK = /\n[ \t]*\n(?:[ \t]*\n)+/
      ID_DIR = /\A\d+\z/
      # A print year 1400–1999, optionally a range (2- or 4-digit tail).
      YEAR = %r{(?<!\d)(1[4-9]\d\d)(?:\s*[-–/]\s*(\d{4}|\d{2})(?!\d))?(?!\d)}
      # Upstream's own no-place statements (imprint "s. l."; the wiki's
      # Place field "s.l." ×3, "not indicated").
      NO_PLACE = /\A(?:s\.\s*l\.?|sine loco|not indicated)\z/i
      VOLUME_LEAD = /\A(?:Vol|Bd|Tom|Pars)\.?\s*[\dIVXLC]+[.,]?\s+/i
      # "Vol. 3", "Bd. 4." inside the imprint run — removed before the split
      # so "Vol. 3 Uppsala" reads Uppsala.
      VOLUME_MARK = /\b(?:Vol|Bd|Tom)\.?\s*[\dIVXLC]+(?:\.,\d+)?(?:,\s*pars\s+[\dIVXLC]+)?[.,]?(?=\s|\z)/i
      # One Transkribus link in a wiki Transkribus-ID field: the id (a stray
      # %20 before it once), the /pages/<n> start page of a contained work,
      # and the note after the link up to the next link or line end.
      LINK = %r{\[https?://transkribus\.eu/r/noscemus/[^\]\s]*?documents/(?:%20)?(\d+)(?:/pages/(\d+))?[^\]]*\]
                ((?:(?!\[https?:)[^\n])*)}x

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "NOSCEMUS Digital Sourcebook — early modern scientific Latin (Transkribus HTR)",
        license: "CC BY 4.0 — Noscemus Digital Sourcebook, Stefan Zathammer, Universität Innsbruck (Zenodo " \
                 "15040256, license field cc-by-4.0, read 2026-11-05); metadata from the Noscemus Wiki " \
                 "backup, Akopyan, Barton, Baumgartner, Berrens, Kirchler, Korenjak, Luggin, Tautschnig, " \
                 "Zathammer (Zenodo 7855322, cc-by-4.0). Attribution required",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "transkribus-txt",
        credit: "Noscemus Digital Sourcebook (Zathammer 2025, doi:10.5281/zenodo.15040256) and the Noscemus " \
                "Wiki (2023, doi:10.5281/zenodo.7855322), ERC project NOSCEMUS (grant 741374), Universität " \
                "Innsbruck."
      )

      def self.manifest = MANIFEST

      # #parse reads one text file and its ref's joined metadata; no state.
      def self.parallel_parse? = true

      # The wiki tables FileFetch lands beside the unpacked works.
      def self.materialized_paths = [WIKI_DIRNAME]

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(label: "Noscemus_Digital_Sourcebook.zip", zip_url: ZIP_URL,
                                            metadata_url: nil, state_subdir: "",
                                            state_file: Nabu::ZipFetch::STATE_FILE)]
      end

      # The copy's imprint from its Title label: {place:, places:, not_before:,
      # not_after:, raw:}, or nil when the label names no print year.
      def self.imprint(title)
        label = title.to_s.strip.sub(/\.pdf\z/i, "").strip
        last = nil
        label.scan(YEAR) { last = Regexp.last_match }
        return nil if last.nil?

        from = Integer(last[1], 10)
        to = last[2] ? expand_year(from, last[2]) : from
        place = imprint_place(label[0...last.begin(0)], label[last.end(0)..])
        raw = [place, label[last.begin(0)...last.end(0)]].compact.join(" ")
        { place: place, places: places(place), not_before: [from, to].min, not_after: [from, to].max, raw: raw }
      end

      def self.expand_year(from, tail)
        return Integer(tail, 10) if tail.size == 4

        Integer("#{from.to_s[0, 2]}#{tail}", 10)
      end

      # The segment after the last stop/comma/dash before the year, read
      # past the "Author - " lead; a year-first label ("1767 Munich") reads
      # the words after the year instead. A label whose title runs straight
      # into the year ("… remediis. 1699", "… edita Amsterdam 1659") names
      # no separable place.
      def self.imprint_place(head, tail)
        head = head.gsub(/\bet al\.?/, "").gsub(VOLUME_MARK, "").strip.delete_suffix("[").strip
        return nil if head.match?(/(?:\A|[.,]\s)s\.\s*l\.?\z/i) # "s. l." — sine loco, upstream's own no-place

        head = head.split(/\s+[-–]\s+/, 2).last
        segments = head.split(/[.,]\s+|\.(?=\p{Lu})|,(?=\p{Lu})|\s+[-–]\s+/).reject { |s| s.strip.empty? }
        candidate = segments.size > 1 ? segments.last : nil
        if candidate.to_s.strip.empty? || candidate.match?(/\A\d/)
          candidate = tail.delete("[]").strip.delete_suffix(".")
        end
        candidate = candidate.to_s.sub(VOLUME_LEAD, "").delete("[]").strip.delete_suffix(".").strip
        candidate = candidate.sub(/\A\d+(?:st|nd|rd|th) ed\.?\s*/i, "").strip
        return nil if candidate.empty? || candidate.match?(NO_PLACE) || !candidate.match?(/\p{L}/)

        candidate
      end

      def self.places(place)
        return [] if place.nil?

        place.split(/\s*(?:&|;)\s*/).map(&:strip).reject { |town| town.empty? || town.match?(NO_PLACE) }
      end

      # The wiki tables' coverage: works, works with no Transkribus-ID, works
      # whose every id names no directory in +workdir+.
      def self.wiki_census(workdir)
        held = Dir.children(workdir).grep(ID_DIR).sort.to_set
        pages = WikiTables.read(workdir).work_pages
        linked = pages.reject { |page| page[:links].empty? }
        { works: pages.size, without_transkribus_id: pages.size - linked.size,
          without_a_copy: linked.count { |page| page[:links].none? { |link| held.include?(link[:id]) } } }
      end

      def initialize(pins: PINS)
        super()
        @pins = pins
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?
        return unless Dir.exist?(workdir)

        tables = WikiTables.read(workdir)
        work_dirs(workdir).each do |id, path|
          yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{id}", path: path,
                                      metadata: { "transkribus_id" => id }.merge(tables.join(id)))
        end
      end

      def discovery_skips(workdir)
        return Nabu::Adapter::DiscoverySkips.new unless Dir.exist?(workdir)

        visible = Dir.children(workdir).sort.reject { |name| name.start_with?(".") }
        dirs = visible.select { |name| File.directory?(File.join(workdir, name)) } - [WIKI_DIRNAME]
        strays = dirs.grep_v(ID_DIR)
        textless = dirs.select { |name| name.match?(ID_DIR) && texts_in(File.join(workdir, name)).size != 1 }
        notes = []
        notes << "top-level directories that are not Transkribus ids: #{strays.sort.join(', ')}" unless strays.empty?
        notes << "Transkribus directories without exactly one .txt: #{textless.sort.join(', ')}" unless textless.empty?
        Nabu::Adapter::DiscoverySkips.new(unrecognized: strays.size + textless.size, notes: notes)
      end

      def parse(document_ref)
        raw = Normalize.nfc(SourceRead.utf8_file(document_ref.path, label: SLUG))
        header_text, body = split_header(raw, document_ref.path)
        header = parse_header(header_text)
        passages = passages_for(document_ref.id, body)
        raise Nabu::DocumentSkipped.new(reason: "no transcribed text (blank or letterless body)") if passages.empty?

        title = header.fetch("Title", "").strip.sub(/\.pdf\z/i, "").strip
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: title.empty? ? document_ref.id : title,
                                      metadata: document_metadata(document_ref.metadata, header))
        passages.each { |passage| document << passage }
        document
      rescue KeyError, Nabu::ValidationError => e
        raise Nabu::ParseError, "#{SLUG}: #{document_ref.path}: #{e.class}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        attic = File.join(workdir, ATTIC_DIRNAME)
        zip = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir, stream: true, archive: :zip_bsdtar,
                                 keep: ["#{WIKI_DIRNAME}/"], attic_dir: attic, progress: progress)
        wiki = WIKI_FILES.to_h do |key, file|
          [key, Nabu::FileFetch.new(url: file[:url], dir: File.join(workdir, WIKI_DIRNAME, key.to_s),
                                    filename: file[:filename], progress: progress,
                                    attic_dir: File.join(attic, WIKI_DIRNAME, key.to_s))]
        end
        begin
          zip.prepare!
          verify_pin!("Noscemus_Digital_Sourcebook.zip", zip, @pins[:zip])
          wiki.each do |key, fetch|
            fetch.prepare!
            verify_pin!("wiki #{key} table", fetch, @pins[key])
          end
          guard_mass_deletion!(workdir, zip.doomed_paths + wiki.values.flat_map(&:doomed_paths), force: force)
          zip.complete!
          wiki.each_value(&:complete!)
        ensure
          zip.cleanup!
        end
        Nabu::FetchReport.new(sha: zip.sha, fetched_at: Time.now, notes: fetch_notes(zip, wiki))
      rescue Nabu::ZipFetch::Error, Nabu::FileFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def work_dirs(workdir)
        ids = Dir.children(workdir).grep(ID_DIR).sort_by { |name| Integer(name, 10) }
        ids.filter_map do |id|
          texts = texts_in(File.join(workdir, id))
          [id, File.expand_path(texts.first)] if texts.size == 1
        end
      end

      def texts_in(dir) = Dir.glob(File.join(dir, "*.txt"))

      def split_header(raw, path)
        match = HEADER_END.match(raw)
        unless raw.start_with?("----------------------------\nMetadata section of document") && match
          raise Nabu::ParseError, "#{SLUG}: #{path}: no Transkribus metadata section"
        end

        [raw[0...match.begin(0)], raw[match.end(0)..]]
      end

      def parse_header(text)
        text.lines.each_with_object({}) do |line, fields|
          key, value = line.chomp.split(": ", 2)
          next if value.nil? || key.start_with?("-")

          fields[key] = value.strip
        end
      end

      # Region = a run of text between two-or-more blank lines; letterless
      # regions become marks on the next passage (or trailing on the last).
      def passages_for(urn, body)
        built = []
        marks = []
        body.split(REGION_BREAK).map(&:strip).reject(&:empty?).each_with_index do |region, index|
          next marks << region unless region.match?(/\p{L}/)

          built << { citation: index + 1, text: region, marks: marks }
          marks = []
        end
        built.last[:trailing] = marks if built.any? && !marks.empty?
        built.each_with_index.map do |entry, sequence|
          annotations = { "marks" => (entry[:marks] unless entry[:marks].empty?),
                          "trailing_marks" => entry[:trailing] }.compact
          Nabu::Passage.new(urn: "#{urn}:#{entry[:citation]}", language: LANGUAGE, text: entry[:text],
                            sequence: sequence, annotations: annotations)
        end
      end

      def document_metadata(ref_meta, header)
        works = ref_meta["wiki_works"]
        meta = {
          "text_nature" => "machine-htr", "text_note" => TEXT_NOTE,
          "transkribus_id" => ref_meta["transkribus_id"],
          "transkribus_title" => header["Title"],
          "page_count" => header["Number of Pages in whole Document"]&.then { |v| Integer(v, 10) },
          "transkribus_created_from" => header["Created From"], "transkribus_created_to" => header["Created To"],
          "transkribus_script_type" => blank_to_nil(header["Sripttype"]),
          "transkribus_language" => null_to_nil(header["Language"]),
          "transkribus_genre" => null_to_nil(header["Genre"]),
          "header_author" => null_to_nil(header["Author"]),
          "wiki_works" => works,
          "authors" => ref_meta["authors"] || header_authors(header["Author"]),
          "facets" => ref_meta["facets"],
          "attribution" => "Noscemus Digital Sourcebook (Zathammer 2025); Noscemus Wiki (2023)"
        }
        meta.merge!(dating(header, works))
        meta.compact
      end

      def dating(header, works)
        imprint = self.class.imprint(header["Title"])
        out = {}
        if imprint
          out["imprint"] = imprint[:raw]
          out["date"] = { "not_before" => imprint[:not_before], "not_after" => imprint[:not_after],
                          "raw" => imprint[:raw] }
          out["date_basis"] = "imprint"
          return out.merge(place_claim(imprint[:places], primary_work(works)))
        end
        fallback_dating(header, Array(works).first, out)
      end

      # The imprint's towns; a label naming none falls back to the whole-copy
      # wiki work's Place (place_basis says which).
      def place_claim(places, work)
        if places.empty? && work && work["place"]
          places = self.class.places(work["place"])
          basis = "wiki_place"
        end
        return {} if places.empty?

        { "place" => places.first, "places" => (places if places.size > 1),
          "place_basis" => basis || "imprint" }.compact
      end

      def primary_work(works) = Array(works).find { |work| work["primary"] }

      def fallback_dating(header, work, out)
        created = [header["Created From"], header["Created To"]].compact.filter_map { |v| v[/\b(1[4-9]\d\d)\z/, 1] }
        if created.any?
          years = created.map { |y| Integer(y, 10) }
          out["date"] = { "not_before" => years.min, "not_after" => years.max, "raw" => created.uniq.join("–") }
          out["date_basis"] = "transkribus_created"
        elsif work && (years = work["year"].to_s.scan(/(?<!\d)1[4-9]\d\d(?!\d)/).map { |y| Integer(y, 10) }).any?
          out["date"] = { "not_before" => years.min, "not_after" => years.max, "raw" => work["year"] }
          out["date_basis"] = "wiki_year"
        end
        out.merge(place_claim([], work))
      end

      def header_authors(value)
        value = null_to_nil(value) or return nil
        value.split(/\s+&\s+/).map { |name| { "name" => name.strip } }
      end

      def null_to_nil(value) = value.nil? || value.strip.empty? || value.strip == "null" ? nil : value.strip

      def blank_to_nil(value) = value.nil? || value.strip.empty? ? nil : value.strip

      def verify_pin!(label, fetch, pin)
        return if fetch.not_modified? || fetch.md5 == pin

        raise Nabu::FetchError,
              "#{SLUG}: downloaded #{label} md5 #{fetch.md5} misses the pin #{pin} — Zenodo records are " \
              "versioned-immutable; read #{RECORD_URL} / #{WIKI_RECORD_URL} and re-pin only after reading them"
      end

      def fetch_notes(zip, wiki)
        [zip.not_modified? ? "sourcebook zip not modified (304)" : "zenodo 15040256 md5 pin verified",
         *wiki.map { |key, f| f.not_modified? ? "wiki #{key} not modified (304)" : "wiki #{key} md5 pin verified" }]
          .join("; ")
      end

      # The Noscemus Wiki backup tables, read once per discover: works keyed
      # by the Transkribus ids their pages link, and the authors' life data.
      class WikiTables
        def self.read(workdir)
          new(file(workdir, :works), file(workdir, :authors))
        end

        def self.file(workdir, key)
          path = File.join(workdir, WIKI_DIRNAME, key.to_s, WIKI_FILES.fetch(key)[:filename])
          File.file?(path) ? path : nil
        end

        attr_reader :work_pages

        def initialize(works_path, authors_path)
          @work_pages = works_path ? pages(works_path, "Works").map { |page| work_page(page) } : []
          @authors = authors_path ? pages(authors_path, "Authors").to_h { |page| [page[:title], page[:fields]] } : {}
          @by_id = Hash.new { |hash, key| hash[key] = [] }
          @work_pages.each do |page|
            page[:links].each { |link| @by_id[link[:id]] << [page, link] }
          end
        end

        # The ref metadata for one Transkribus id: wiki_works (the whole-copy
        # work first), the genre/discipline facets, the authors.
        def join(id)
          hits = @by_id.fetch(id, []).uniq { |page, _link| page[:title] }
          return {} if hits.empty?

          hits = hits.sort_by.with_index { |(_page, link), index| [link[:page] ? 1 : 0, index] }
          works = hits.map { |page, link| work_record(page, link) }
          { "wiki_works" => works, "facets" => facets(hits.map(&:first)),
            "authors" => authors(hits.first.first) }.compact
        end

        private

        def pages(path, template)
          xml = Nokogiri::XML(SourceRead.utf8_file(path, label: "#{SLUG} wiki"))
          xml.remove_namespaces!
          xml.xpath("//page[ns='0']").filter_map do |page|
            text = page.at("revision/text")&.text.to_s
            next unless text.match?(/\A\s*\{\{#{template}\b/)

            { id: page.at("id").text, title: Normalize.nfc(page.at("title").text), fields: fields(text) }
          end
        end

        def fields(text)
          out = {}
          text.scan(/^\|([^=\n]*)=(.*?)(?=^\||^\}\}|\z)/m) { |key, value| out[key.strip] = Normalize.nfc(value.strip) }
          out
        end

        def work_page(page)
          links = page[:fields].fetch("Transkribus-ID", "").scan(LINK).map do |id, start, note|
            { id: id, page: start && Integer(start, 10), note: plain(note) }
          end
          page.merge(links: links)
        end

        def work_record(page, link)
          f = page[:fields]
          {
            "title" => page[:title], "wiki_page_id" => page[:id], "primary" => link[:page].nil?,
            "start_page" => link[:page], "note" => blank(link[:note]),
            "author" => blank(plain(f["Author"])), "full_title" => blank(plain(f["Full title"])),
            "in" => blank(plain(f["In"])), "year" => blank(plain(f["Year"])), "place" => blank(plain(f["Place"])),
            "printer" => blank(plain(f["Publisher/Printer"])), "era" => blank(f["Era"]),
            "form_genre" => list(f["Form/Genre"]), "discipline" => list(f["Discipline/Content"])
          }.compact
        end

        def facets(pages)
          out = {}
          { "genre" => "Form/Genre", "discipline" => "Discipline/Content" }.each do |facet, field|
            raws = pages.filter_map { |page| blank(page[:fields][field]) }
            values = raws.flat_map { |raw| list(raw) || [] }.uniq
            out[facet] = { "values" => values, "raw" => raws.uniq.join(" | ") } unless values.empty?
          end
          out.empty? ? nil : out
        end

        def authors(page)
          names = plain(page[:fields]["Author"]).to_s.split(";").map(&:strip).reject(&:empty?)
          return nil if names.empty?

          names.map do |name|
            data = @authors.fetch(name, {})
            { "name" => name, "born" => blank(data["Year of birth"]), "died" => blank(data["Year of death"]),
              "gnd" => data["Link to GND"].to_s[%r{/gnd/([0-9X-]+)}, 1] }.compact
          end
        end

        def list(value)
          items = value.to_s.split(",").map(&:strip).reject(&:empty?)
          items.empty? ? nil : items
        end

        def blank(value) = value.nil? || value.strip.empty? ? nil : value.strip

        # Wiki markup → plain text: links keep their label, tags and '' go.
        def plain(value)
          return nil if value.nil?

          value.gsub(/\[\[(?:[^\]|]*\|)?([^\]]*)\]\]/, '\1')
               .gsub(%r{\[https?://\S+\s+([^\]]*)\]}, '\1')
               .gsub(%r{</?(?:i|b|em|strong|br|sup|sub)\s*/?>}i, "")
               .gsub("''", "").gsub(/\s+/, " ").strip
        end
      end
    end
  end
end
