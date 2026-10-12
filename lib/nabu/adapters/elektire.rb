# frozen_string_literal: true

require "cgi"
require "json"

require_relative "elektire_epub_parser"
require_relative "../elektire_fetch"

module Nabu
  module Adapters
    # elektire — eLektire (lektire.skole.hr), CARNET's school reading
    # portal of the Croatian literary canon, its books produced by Bulaja
    # naklada (P117-2): the Croatian canon from Marulić's Judita
    # (written 1501) and the Dubrovnik Renaissance (Držić, Vetranović,
    # Nalješković, Hektorović, Zoranić) through Gundulić and the Baroque,
    # Kačić, Relković and the Illyrians, to Šenoa, Kovačić, Matoš, Kamov
    # and the moderns — all Croatian, Čakavian, Štokavian and Kajkavian.
    #
    # == The cone and the admission rule (in-copyright works excluded by rule)
    #
    # The portal lists 378 works (WP-JSON /wp/v2/djela, censused
    # 2026-10-11): 284 in the Croatian-literature term, the rest
    # translations of foreign literature. The fetch takes the Croatian
    # term only (ElektireFetch); 231 of those carry an EPUB (all downloaded
    # for the census). Each book's impressum states its rights per work; a
    # book is ADMITTED only when all four hold:
    #
    # 1. its impressum carries a public-domain statement for the work
    #    ("Autorska prava na djela Marka Marulića su istekla, i ona su sada
    #    javno dobro koje se nesmetano može kopirati." / "Držićeva djela su
    #    u javnoj domeni." / "…ne postoje…") — 24 Croatian books state
    #    none (living or recent authors: "© Silvija Šesto", …);
    # 2. it reserves no translation ("Autorska prava za prijevod …";
    #    "…autorska prava na redakturu prijevoda…");
    # 3. its author died at or before AUTHOR_DEATH_CUTOFF (1955 — life + 70
    #    as of 1 January 2026, the Croatian term; advanced each January as
    #    a code change), the death year read from the author note's own
    #    life line ("Split, 18. kolovoza 1450. - Split, 5. siječnja 1524.")
    #    — the publisher's statement alone is not trusted: Viktor Car Emin
    #    (d. 1963) is called public domain and is excluded here;
    # 4. or, for 3, the work is anonymous (folk prose, folk drama, folk
    #    verse; Ljubovnici — creators "anonimni autor(i)" / "nepoznati
    #    autor").
    #
    # A book whose author note yields no life line (Prokletstvo, by two
    # authors) fails 3 and is excluded — conservative, censused as a
    # discovery skip. Census: 231 Croatian books → 205 admitted / 375,300
    # passages, 26 skipped by rule (24 no statement, Car Emin, Prokletstvo).
    #
    # == Text and the edition layer
    #
    # The elektire-epub family reads only the work: the impressum itself
    # says "sva autorska prava na opremu knjige (rječnik, napomene,
    # bilješka o piscu...) su pridržana", so glossary, notes, author note,
    # didactic pages and the e-book title page are apparatus, never text.
    # The NAMED EDITION is the e-book itself, recorded per document as
    # metadata "edition": publisher (Bulaja naklada), ISBN, editor, the OPF
    # publication date and the generation (v2 2011–2017 / v3 2018+ CARNET).
    # The printed edition the text was keyed from is NOT stated in the
    # asset (censused: no impressum names one — e.g. Judita's text follows
    # a modern critical edition, with its bracketed restorations "(j)",
    # "(n)" kept verbatim, but the book does not say which); recorded as
    # "base_edition": "not stated in the asset", never guessed.
    #
    # == Identity
    #
    # Document = one book: urn:nabu:elektire:<the portal's work slug>
    # (judita, dundo-maroje). Passages = lines, citation <spine
    # position>.<line> (`…:judita:9.2` — the first verse of Libro parvo).
    #
    # == Axes
    #
    # Date: the portal's "stoljece_nastanka" (century of origin) terms as a
    # century envelope (16-stoljece → 1501–1600; several terms → their
    # span) — an attributed composition-era date, MetadataDates
    # :structured in the COMPOSITION class. Places: none — no place field
    # exists for the works (the author note's birthplaces are not the
    # work's). Facets: genre (knjizevna_vrsta: ep, komedija, roman,
    # zbirka pjesama …), mode (knjizevni_zanr: epika/lirika/drama), epoch
    # (epohe: renesansa, barok, …) — values the term slugs, raw the names.
    # The school grade (lektira) rides as metadata.
    #
    # == License
    #
    # Per work, the impressum's own statement (quoted verbatim per
    # document as "rights_statement"): the work's copyright has expired and
    # it is public domain; the book's apparatus is reserved and not
    # ingested → open. The portal's reader asks for a login; the REST API
    # and the uploaded book files are public, unauthenticated URLs.
    class Elektire < Nabu::Adapter
      BASE_URL = "https://lektire.skole.hr"
      LANGUAGE = "hrv"
      URN_PREFIX = "urn:nabu:elektire:"
      BASE_EDITION = "not stated in the asset"

      # const: the life+70 boundary as of 1 January 2026 — advance each January, not a corpus claim
      AUTHOR_DEATH_CUTOFF = 1955

      MANIFEST = Nabu::SourceManifest.new(
        id: "elektire",
        name: "eLektire — the Croatian school canon (CARNET / Bulaja naklada)",
        license: "Public domain per work — each book's impressum, e.g. \"Autorska prava na djela Marka " \
                 "Marulića su istekla, i ona su sada javno dobro koje se nesmetano može kopirati. Međutim, " \
                 "sva autorska prava na opremu knjige (rječnik, napomene, bilješka o piscu...) su " \
                 "pridržana.\" Only the works are ingested, never the reserved apparatus; works without " \
                 "such a statement, with a reserved translation, or whose author died after " \
                 "#{AUTHOR_DEATH_CUTOFF} are excluded by rule. Books: Bulaja naklada for CARNET " \
                 "(lektire.skole.hr).",
        license_class: "open",
        upstream_url: "https://lektire.skole.hr/",
        parser_family: "elektire-epub"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "works listing", zip_url: "#{BASE_URL}#{ElektireFetch::API}/djela?per_page=1",
          metadata_url: nil, state_subdir: "", liveness_only: true
        )]
      end

      def fetch(workdir, progress: nil, force: false)
        result = ElektireFetch.sync!(
          base_url: BASE_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now,
                              notes: "#{result.manifest_count} Croatian works listed · #{result.works} with " \
                                     "an EPUB · #{result.fetched} fetched · #{result.cached} cached")
      rescue ElektireFetch::Error => e
        raise Nabu::FetchError, "elektire fetch failed into #{workdir}: #{e.message}"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        judged(workdir).each do |entry|
          next unless entry[:reason].nil?

          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{entry[:slug]}",
                                      path: File.expand_path(entry[:path]), metadata: entry[:work])
        end
      end

      def discovery_skips(workdir)
        entries = judged(workdir)
        strays = entries.select { |e| e[:reason] == :stray }
        excluded = entries.reject { |e| e[:reason].nil? || e[:reason] == :stray }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: excluded.size, unrecognized: strays.size,
          notes: excluded.map { |e| "#{e[:slug]}: #{e[:reason]}" } +
                 strays.map { |e| "#{e[:slug]}: EPUB with no works-listing row" }
        )
      end

      def parse(document_ref)
        book = parser.parse(document_ref.path)
        work = document_ref.metadata
        title = book.opf.title || work["wp_title"] || work["slug"]
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: title, metadata: metadata_for(book, work))
        book.lines.each_with_index do |line, index|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{line.citation}", language: LANGUAGE,
                                        text: line.text, sequence: index + 1,
                                        annotations: line.kind == "head" ? { "kind" => "head" } : {})
        end
        raise Nabu::ParseError, "#{document_ref.id}: no text lines outside the apparatus" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      def parser = @parser ||= ElektireEpubParser.new

      # Every EPUB on disk with its listing row and, when not admitted, the
      # reason (a Symbol :stray for a book the listing does not know).
      # Memoized per tree STATE (paths + sizes + mtimes), so discover and
      # discovery_skips share one judgment while a fetch that changes the
      # tree is never answered from a stale one.
      def judged(workdir)
        paths = Dir.glob(File.join(workdir, ElektireFetch::EPUB_DIR, "*.epub"))
        listing = Dir.glob(File.join(workdir, ElektireFetch::INDEX_DIR, "*.json"))
        key = (paths + listing).map { |p| "#{p}\0#{File.size(p)}\0#{File.mtime(p).to_f}" }.join("\n")
        return @judged.last if @judged && @judged.first == key

        @judged = [key, judge(workdir, paths)]
        @judged.last
      end

      def judge(workdir, paths)
        index = WorksIndex.load(workdir)
        paths.map do |path|
          slug = File.basename(path, ".epub")
          work = index&.work(slug)
          reason = if index && work.nil? then :stray
                   elsif index && !work["croatian"] then "outside the Croatian-literature term"
                   else exclusion(parser.rights(path).last)
                   end
          { slug: slug, path: path, work: work || { "slug" => slug }, reason: reason }
        end
      end

      def exclusion(rights)
        return "no public-domain statement in the impressum" unless rights.statement
        return "translation rights reserved (#{rights.reserved[0, 80]})" if rights.reserved
        return nil if rights.anonymous
        return "author's life years not stated in the author note" unless rights.author_death

        return nil if rights.author_death <= AUTHOR_DEATH_CUTOFF

        "author d. #{rights.author_death} — in copyright (life + 70; cutoff #{AUTHOR_DEATH_CUTOFF})"
      end

      def metadata_for(book, work)
        rights = book.rights
        opf = book.opf
        {
          "work_id" => work["id"], "url" => work["link"],
          "author" => opf.creators.join(", "), "authors" => opf.creators,
          "author_birth" => rights.author_birth, "author_death" => rights.author_death,
          "anonymous" => rights.anonymous || nil,
          "rights_statement" => rights.statement,
          "date" => century_date(work["centuries"]),
          "facets" => facets_for(work),
          "school_grade" => work["grades"],
          "edition" => {
            "publisher" => opf.publisher, "isbn" => rights.isbn, "editor" => rights.editor,
            "published" => opf.dates["publication"] || opf.dates["date"],
            "base_edition" => BASE_EDITION
          }.compact,
          "subjects" => opf.subjects
        }.reject { |_k, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
      end

      # "16-stoljece" → 1501–1600; several centuries → their span.
      def century_date(centuries)
        terms = Array(centuries)
        numbers = terms.filter_map { |t| t["slug"].to_s[/\A(\d{1,2})-stoljece\z/, 1]&.to_i }
        return nil if numbers.empty?

        { "not_before" => ((numbers.min - 1) * 100) + 1, "not_after" => numbers.max * 100,
          "raw" => "#{terms.map { |t| t['name'] }.join(', ')} (the portal's century of origin)" }
      end

      def facets_for(work)
        { "genre" => work["genres"], "mode" => work["modes"], "epoch" => work["epochs"] }
          .each_with_object({}) do |(facet, terms), out|
            terms = Array(terms)
            next if terms.empty?

            slugs = terms.map { |t| t["slug"] }
            raw = terms.map { |t| t["name"] }.join(", ")
            out[facet] =
              slugs.size == 1 ? { "value" => slugs.first, "raw" => raw } : { "values" => slugs, "raw" => raw }
          end
      end

      # The works listing + taxonomy pages the fetch landed under index/,
      # resolved to one compact record per work slug.
      class WorksIndex
        TERM_KEYS = { "centuries" => "stoljece_nastanka", "genres" => "knjizevna_vrsta",
                      "modes" => "knjizevni_zanr", "epochs" => "epohe", "grades" => "lektira" }.freeze

        def self.load(workdir)
          dir = File.join(workdir, ElektireFetch::INDEX_DIR)
          return nil unless Dir.exist?(dir)

          new(dir)
        end

        def initialize(dir)
          @terms = ElektireFetch::TAXONOMIES.to_h do |tax|
            [tax, pages(dir, tax).to_h { |t| [t["id"], { "slug" => t["slug"], "name" => text(t["name"]) }] }]
          end
          canon = @terms.fetch(ElektireFetch::CANON_TAXONOMY).find { |_id, t| t["slug"] == ElektireFetch::CANON_TERM }
          @canon_id = canon&.first
          @works = pages(dir, "djela").to_h { |w| [w["slug"], w] }
        end

        def work(slug)
          raw = @works[slug] or return nil

          record = { "id" => raw["id"], "slug" => slug, "link" => raw["link"],
                     "wp_title" => text(raw.dig("title", "rendered")),
                     "croatian" => Array(raw[ElektireFetch::CANON_TAXONOMY]).include?(@canon_id) }
          TERM_KEYS.each do |key, tax|
            terms = Array(raw[tax]).filter_map { |id| @terms.fetch(tax, {})[id] }
            record[key] = terms unless terms.empty?
          end
          record.compact
        end

        private

        def pages(dir, name)
          Dir.glob(File.join(dir, "#{name}-*.json")).sort_by { |p| p[/-(\d+)\.json\z/, 1].to_i }
                                                    .flat_map { |path| JSON.parse(File.read(path)) }
        rescue JSON::ParserError => e
          raise Nabu::ParseError, "#{dir}/#{name}: unparseable listing (#{e.message})"
        end

        def text(value) = value && CGI.unescapeHTML(value.to_s)
      end
    end
  end
end
