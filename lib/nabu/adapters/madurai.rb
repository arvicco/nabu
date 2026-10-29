# frozen_string_literal: true

require_relative "../litopys_fetch"
require_relative "../redirect_follow"
require_relative "../zip_fetch"
require_relative "madurai_fetch"
require_relative "madurai_html_parser"

module Nabu
  module Adapters
    # Project Madurai — the classical-Tamil cone (P122-3). Project Madurai
    # (www.projectmadurai.org; K. Kalyanasundaram and volunteers, since
    # 1998) is the open, voluntary e-text library of Tamil literature: 1,090
    # works in 1,367 Unicode HTML files (works list census 2026-10-12),
    # from the Caṅkam anthologies to twentieth-century novels.
    #
    # == License (verified on the files themselves, 2026-10-12)
    #
    # Every e-text carries the project's header page: "© Project Madurai
    # … You are welcome to freely distribute this file, provided this
    # header page is kept intact." — an attribution-conditioned permission
    # (class attribution). The header rides every document's metadata
    # verbatim (pm_header), so the condition travels with the text. The
    # project's FAQ: all works are public domain or published with their
    # authors' consent.
    #
    # == The classical filter (the cone)
    #
    # Modern authors are interleaved with the classics, so the cone is a
    # GENRE rule over the works list's own Genre column (CLASSICAL /
    # NON_CLASSICAL below): a Unicode file is in scope when EVERY catalog
    # row naming it carries a pre-modern genre — the Caṅkam anthologies
    # (சங்ககாலம்: எட்டுத்தொகை, பத்துப்பாட்டு), the didactic canon
    # (நீதிநெறி, பதினெண்கீழ்க்கணக்கு), the Śaiva / Vaiṣṇava / Islamic
    # devotional and doctrinal corpora (சமயம், சைவ சித்தாந்தம், பண்டார
    # சாத்திரம், தேவாரம், சித்தர்), the epics and purāṇas (காப்பியம்,
    # காவியம், இதிகாசம், புராணம், தலபுராணம்), the prabandha genres
    # (பிரபந்தம் — the ciṟṟilakkiyam forms), grammar, poetics and lexicons
    # (இலக்கணம், பாட்டியல், நிகண்டு), palm-leaf texts and verse-form
    # labels (ஓலைச்சுவடி, இலக்கியம் - வெண்பா/கலிவெண்பா) — and no row
    # names a modern apparatus (மொழிபெயர்ப்பு translation, ஆங்கில English,
    # ஆராய்ச்சி research, கட்டுரை essays). Out: novels, short stories,
    # essays, history, biography, drama, modern poetry and songs, speeches,
    # Christian mission literature (சமயம் – கிருத்துவம்), translations.
    # Census 2026-10-12: 760 of the 1,366 linked Unicode files in scope;
    # files whose rows mix a classical and a modern genre stay out (the
    # all-rows rule — upstream links work 662, a modern poem, to work
    # 660 pmuni0660.html), and so do classical works whose TITLE names a
    # translation (G. U. Pope's English Tiruvācakam, Kausalya Hart's
    # bilingual prabandhas).
    #
    # DECLARED COARSENESS: the rule reads the genre, not the date — a
    # 19th/20th-c. poet writing in a prabandha form (a modern piḷḷaittamiḻ)
    # rides in, and a classical text the catalog files under a modern
    # label stays out; the catalog row (titles/authors/genres) rides every
    # document so a later date-aware refinement can re-cut the cone.
    #
    # == Fetch
    #
    # The works list is GET-ted first and the cone computed from it; then
    # MaduraiFetch (Nabu::LitopysFetch's census-listed retention contract)
    # GETs the list + every in-cone file from the one host, polite (1 s
    # apart, a nabu User-Agent), bytes verbatim, sha-pinned in its state
    # file (.litopys-fetch.json), delisted *.html pages atticked. The works
    # list links 5 files the server does not have (404) — skipped and named
    # in the fetch notes, censused as missing at discovery. ~760 GETs: the
    # census download ran ~40 min at the server's pace (1–5 s a file).
    #
    # == Identity and grain
    #
    #   urn:nabu:madurai:<file stem>        (…:pmuni0001, …:pmuni0003_01)
    #   passage: <urn>:<line ordinal>       (the madurai-html physical line)
    #
    # Language: Tamil in Tamil script — the bare code "tam" (→ ta through
    # the held codemap row). Lines without Tamil script are dropped and
    # counted (madurai-html). Dating: the asset carries none (the works
    # list has no date column; the footers date the e-text, never the
    # work). Places: none.
    #
    # == The OCR label (metadata text_nature, per file)
    #
    # Most e-texts are hand-keyed ("Etext Preparation (input,
    # proof-reading)"); the later ones say in their header's
    # acknowledgements that they were made by OCR AND then corrected
    # ("generated using Google OCR online tool and subsequent
    # proof-reading", "subsequently corrected for any OCR errors",
    # "subsequently edited by …"). A header naming OCR together with a
    # correction is stamped text_nature "corrected-ocr" — the
    # non-excluding label (`export passages --exclude-ocr` keeps it). An
    # OCR mention WITHOUT a stated correction is "ocr-origin" (the origin
    # is declared, the correction status is not — never upgraded by
    # guess, never downgraded to "uncorrected" either; also non-excluding).
    # Hand-keyed files carry no label. Census 2026-10-29 over canonical:
    # 181 of 755 held files name OCR — 180 with their correction claim,
    # one (pmuni0752: "generated using Google OCR online tool.") without.
    class Madurai < Nabu::Adapter
      SLUG = "madurai"
      HOST = "https://www.projectmadurai.org/"
      CATALOG = "pmworks.html"
      ETEXT_DIR = "pm_etexts/utf8"
      LANGUAGE = "tam"
      URN_PREFIX = "urn:nabu:#{SLUG}:".freeze

      CLASSICAL = Regexp.union(
        /\A(?:சங்ககாலம்|சங்க|எட்டுத்தொகை|பத்துப்பாட்டு|பதினெண்)/,
        /\A(?:நீதிநெறி|நீதி நூல்)/,
        /\A(?:சமயம் [-–] (?:சைவம்|வைணவம்|இஸ்லாமியம்)|சமயம்\z)/,
        /\A(?:சைவ சித்தாந்தம்|பண்டார சாத்திரம்|சித்தர்|தேவாரம்)/,
        /\A(?:பிரபந்த|சிற்‌?றிலக்கியம்)/,
        /\A(?:புராணம்|தலபுராணம்|காப்பியம்|காப்பியங்கள்|காவியம்|இதிகாசம்)/,
        /\A(?:இலக்கண|பாட்டியல்|நிகண்டு|செய்யுள்)/,
        /\A(?:ஓலைச்சுவடி|ஒளைச் சுவடி|இலக்கியம் - (?:கலி)?வெண்பா)/
      )
      # A modern apparatus named in a genre OR a title (Pope's English
      # Tiruvācakam files under a plain "சமயம் - சைவம்" genre, its title
      # saying "(ஆங்கில மொழிபெயர்ப்பு)"); மொழியர்ப்பு is upstream's typo.
      NON_CLASSICAL = /மொழிபெயர்ப்பு|மொழியாக்கம்|மொழியர்ப்பு|ஆங்கில|ஆராய்ச்சி|கட்டுரை|English|Translation/i

      CREDIT = "Project Madurai (www.projectmadurai.org) — Tamil e-texts prepared by the project's " \
               "volunteers (K. Kalyanasundaram et al.); freely distributable provided the header " \
               "page is kept intact (each document carries it verbatim as pm_header)."

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Project Madurai — classical Tamil e-texts",
        license: "Project Madurai header page: \"You are welcome to freely distribute this file, " \
                 "provided this header page is kept intact.\" — attribution-conditioned; the header " \
                 "rides every document verbatim (class attribution)",
        license_class: "attribution",
        upstream_url: HOST,
        parser_family: "madurai-html",
        credit: CREDIT
      )

      def self.manifest = MANIFEST

      OCR_CLAIM = /\bOCR\b/
      CORRECTION_CLAIM = /proof-?reading|correct|edited/i

      # The header's own OCR statement → text_nature (class note).
      def self.text_nature(header)
        header = header.to_s
        return nil unless header.match?(OCR_CLAIM)

        header.match?(CORRECTION_CLAIM) ? "corrected-ocr" : "ocr-origin"
      end

      def self.classical_genre?(genre)
        genre = genre.to_s.strip
        genre.match?(CLASSICAL) && !genre.match?(NON_CLASSICAL)
      end

      # The cone: catalog entries whose every genre is classical and whose
      # titles name no modern apparatus (a translation, an English version).
      def self.in_scope(entries)
        entries.select do |entry|
          !entry.genres.empty? && entry.genres.all? { |g| classical_genre?(g) } &&
            entry.titles.none? { |title| title.match?(NON_CLASSICAL) }
        end
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "projectmadurai.org works list", zip_url: "#{HOST}#{CATALOG}", metadata_url: nil,
          state_subdir: "", state_file: Nabu::LitopysFetch::STATE_FILE, liveness_only: true
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        scope(workdir).each do |entry|
          path = File.join(workdir, ETEXT_DIR, entry.file)
          next unless File.file?(path)

          yield Nabu::DocumentRef.new(
            source_id: SLUG, id: "#{URN_PREFIX}#{File.basename(entry.file, '.html')}",
            path: File.expand_path(path), metadata: catalog_metadata(entry)
          )
        end
      end

      def discovery_skips(workdir)
        on_disk = Dir.glob(File.join(workdir, ETEXT_DIR, "*.html")).map { |path| File.basename(path) }
        in_scope = scope(workdir).map(&:file)
        outside = on_disk - in_scope
        missing = in_scope - on_disk
        notes = []
        notes << "#{outside.size} e-text file(s) outside the classical cone (genre rule)" unless outside.empty?
        notes += missing.map { |file| "#{file}: in the classical cone but not on disk" }
        notes << "#{CATALOG} missing — no cone without the works list" unless File.file?(catalog_path(workdir))
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: outside.size, unrecognized: missing.size, notes: notes)
      end

      def parse(document_ref)
        etext = MaduraiHtmlParser.etext(File.binread(document_ref.path), path: document_ref.path)
        name = File.basename(document_ref.path)
        raise Nabu::ParseError, "#{SLUG}: #{name}: no Tamil text in the body" if etext.lines.empty?

        meta = document_ref.metadata
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: Array(meta["titles"]).join(" / ").then { |t| t.empty? ? etext.html_title || name : t },
          metadata: meta.merge(
            "html_title" => etext.html_title, "pm_header" => etext.header, "pm_footer" => etext.footer,
            "non_tamil_lines" => etext.non_tamil_lines, "text_nature" => self.class.text_nature(etext.header)
          ).reject { |_, value| value.nil? || value == "" }
        )
        etext.lines.each_with_index do |line, index|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{index + 1}", language: LANGUAGE, text: line.text, sequence: index,
            annotations: line.heading ? { "heading" => true } : {}
          )
        end
        document
      end

      def fetch(workdir, progress: nil, force: false)
        entries = MaduraiHtmlParser.catalog(get_catalog(progress))
        pages = [CATALOG] + self.class.in_scope(entries).map { |entry| "#{ETEXT_DIR}/#{entry.file}" }.sort
        pull = MaduraiFetch.new(pages: pages, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
                                http: fetch_http, hosts: [HOST], delay: fetch_delay, progress: progress)
        pull.prepare!
        guard_mass_deletion!(workdir, pull.doomed_paths, force: force)
        pull.complete!
        notes = ["#{pull.page_count} pages (#{pull.changed} changed)",
                 ("404 on the works list's own links: #{pull.missing.join(', ')}" unless pull.missing.empty?),
                 attic_notes(pull.atticked)].compact
        FetchReport.new(sha: pull.sha, fetched_at: Time.now, notes: notes.join("; "))
      rescue Nabu::LitopysFetch::Error, Nabu::ParseError => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      # Seams for tests (the politeness pause; the HTTP client).
      def fetch_delay = Nabu::LitopysFetch::DELAY

      def fetch_http = Nabu::ZipFetch.default_http

      private

      def catalog_path(workdir) = File.join(workdir, CATALOG)

      def scope(workdir)
        path = catalog_path(workdir)
        return [] unless File.file?(path)

        self.class.in_scope(MaduraiHtmlParser.catalog(File.binread(path))).sort_by(&:file)
      end

      def catalog_metadata(entry)
        { "file" => entry.file, "work_numbers" => entry.work_numbers, "titles" => entry.titles,
          "authors" => entry.authors, "genres" => entry.genres }
      end

      def get_catalog(progress)
        progress&.call("Fetching #{HOST}#{CATALOG} (the works list → the classical cone)…\n")
        response, = Nabu::RedirectFollow.get(
          "#{HOST}#{CATALOG}", http: fetch_http, error: Nabu::LitopysFetch::Error,
                               headers: { "User-Agent" => Nabu::LitopysFetch::USER_AGENT }
        )
        response.body.to_s.b
      end
    end
  end
end
