# frozen_string_literal: true

require "json"
require_relative "grand_tour_tei_parser"
require_relative "source_read"
require_relative "../zip_range_fetch"

module Nabu
  module Adapters
    # grand-tour — "Grand Tour digital": the Herzog August Bibliothek
    # Wolfenbüttel's edition of early-modern travel journals (DFG project
    # 2022–2026, ed. Angela Göbel and Maximilian Görmar; the edition at
    # selbstzeugnisse.hab.de/edition_grand_tour). Four journals in HAB
    # manuscripts, edited line by line from the facsimiles:
    #
    #   Cod. Guelf. 267.1 Extrav.  [Johannes Wagener], the travel diary of a
    #                              journeyman apothecary, 1652–1659
    #   Cod. Guelf. 221 Extrav.    Christian August of Schleswig-Holstein-
    #                              Norburg's travel diary and chronicle,
    #                              1664–1670 ("in Bearbeitung")
    #   Cod. Guelf. 89 Blank.      Duke Ludwig Rudolf of Brunswick-
    #                              Wolfenbüttel's Danish and Swedish journey,
    #                              1689
    #   Cod. Guelf. 149.14 Extrav. the Italian and French journal of the
    #                              Brunswick-Bevern dukes Heinrich Ferdinand
    #                              and Ernst Ferdinand, 1701–1702 ("in
    #                              Bearbeitung"; variants against three
    #                              later copies)
    #
    # == The text's nature (the deposit's own declarations)
    #
    # README: Transkribus for the full text and Python NER scripts for the
    # named entities, "Der jeweilige Output der eingesetzten Programme
    # wurde händisch nachkontrolliert und korrigiert" — hand-checked and
    # corrected HTR, entities linked to the registers and authority files
    # (GND, GeoNames, VIAF, Wikidata). 221's header further states its TEI
    # conversion and entity annotation were done with a large language
    # model's and spaCy's help, then linked by the editors. Transcription
    # rules (introduction_editionRules.xml): character-faithful, long s
    # normalized to round s, abbreviations kept, line-end hyphens unified
    # to "-". Every document carries text_nature "htr-corrected" + the note.
    #
    # == Delivery grains (census of the Zenodo zip, 2026-11-03: 199 members)
    #
    # - Reiseberichte/<shelfmark>.xml — TAKEN: the four journals, document =
    #   journal, passage = page. 540 <pb/> in all (23 + 124 + 177 + 216 — a
    #   line count reads 536 because four 267.1 lines carry two breaks
    #   each); one sits inside a later copy's variant reading (149.14), not
    #   the base text → 539 pages: 515 passages + 24 without text
    #   (bindings, blank leaves — skipped by rule, counted per document as
    #   blank_pages).
    # - register/listPlace|listPerson|listOrg_grand_tour.xml — READ as the
    #   entity registers every <rs> resolves through (323 places: 254
    #   GeoNames, 45 GND, 8 Wikidata, 16 unlinked; 397 persons; 37 orgs);
    #   never documents (skipped by rule).
    # - register/itinerar_wagener.json — READ as 267.1's dated itinerary
    #   (149 stops, 141 with GeoNames id + coordinates) into that
    #   document's metadata; never a document.
    # - introduction/*.xml — 20 files, SKIPPED BY RULE: the editors' modern
    #   German introductions (4 Einleitungen to the edited journals, 14
    #   Kurzbeschreibungen of further digitised codices that are NOT
    #   transcribed, the project description and the edition rules) —
    #   2023–2026 scholarly apparatus about the journals, not early-modern
    #   text; the edition rules are cited here instead.
    # - Reiseberichte/index_grand_tour.xml — the edition's XInclude
    #   assembly, SKIPPED BY RULE; READ for each journal's group label
    #   ("… (in Bearbeitung)" marks the two works in progress).
    # - Schema/grand_tour_digital.rng, README.md, LICENSE — skipped by rule.
    # - .git/ (the zip ships the project's git directory, 94 files) —
    #   outside the Range cone, never fetched (a .git in canonical/ would
    #   make the tree read as an embedded repository).
    #
    # Reconciliation: 4 documents + 28 rule-skipped files = the 32 files
    # outside .git/ (the zip's 199 entries = 126 files — 32 + 94 under
    # .git/ — and 73 directory entries); the edition rules speak of five
    # edited texts, the deposit carries four journals.
    #
    # == Language
    #
    # No file carries xml:lang; the journals are German (the 1652–1702
    # stage: de stays bare — de:early's band closes 1650, the dta
    # precedent), with French and Latin quotations, inscriptions and one
    # French copy's variant readings unmarked by upstream — deliberately
    # coarse, the whole document rides de.
    #
    # == Axes
    #
    # Dates: every <date when> in the reading text (the diary's own day
    # entries; never the editors' notes) → the document's envelope, first
    # to last year, class composition (a diary is written along its
    # journey); each page carries its own dates. Places: the journals are
    # ITINERARIES — no single origin place is claimed (the diccas
    # place_mentioned precedent); every <rs type="place"> rides its page as
    # {value, ref} (the register's name + its GeoNames/GND/Wikidata URL —
    # the passage facet place), the distinct resolved names as the
    # document's places_mentioned. Upstream's NER is uneven and said so:
    # 149.14 carries none, 221 links 34 of its places (962 bare "#" refs,
    # 633 ids its register does not yet hold — kept as unresolved surface
    # mentions, counted in entity_mentions). Persons and orgs ride the same
    # way. Kind: the whole source is travel diaries (kind_map.yml).
    #
    # == License
    #
    # LICENSE = Creative Commons Attribution-ShareAlike 4.0 International;
    # the Zenodo record's license field cc-by-sa-4.0 and the index header's
    # <licence target=".../by-sa/4.0/"> agree (read 2026-11-03) →
    # attribution.
    class GrandTour < Nabu::Adapter
      SLUG = "grand-tour"
      URN_PREFIX = "urn:nabu:grand-tour:"
      LANGUAGE = "de"
      RECORD_URL = "https://zenodo.org/records/23055358"
      ZIP_URL = "https://zenodo.org/api/records/23055358/files/grand-tour-tei.zip/content"
      # sha256 of the zip's central directory (zip md5
      # 6013b6805464fa1ec4e15e5b32cd3dea = the record's checksum, 1,616,592
      # bytes, downloaded 2026-11-03).
      DIRECTORY_SHA256 = "e9b8baf3019f7952caa783c412ce920538669cd79fb0168a9910463b4a97a122"

      JOURNALS_DIR = "Reiseberichte"
      INDEX = "index_grand_tour.xml"
      REGISTERS = { places: ["listPlace_grand_tour.xml", "place"], persons: ["listPerson_grand_tour.xml", "person"],
                    orgs: ["listOrg_grand_tour.xml", "org"] }.freeze
      # The itinerary sidecar → the journal it belongs to (its stops are
      # Wagener's: Meldorf 1652 … Lyon 1658/59).
      ITINERARIES = { "cod_guelf_267_1_extrav" => "itinerar_wagener.json" }.freeze

      TEXT_NOTE = "Transkribus HTR, hand-checked and corrected by the editors (README); entities linked to the " \
                  "registers and authority files. Character-faithful transcription: abbreviations kept, long s " \
                  "normalized, line-end hyphens unified."

      SKIP_RULES = [
        [%r{\AReiseberichte/index_grand_tour\.xml\z}, "the edition's XInclude assembly (read for group labels)"],
        [%r{\Aintroduction/[^/]+\.xml\z}, "the editors' modern introduction / codex description / edition rules"],
        [%r{\Aregister/list(?:Place|Person|Org)_grand_tour\.xml\z}, "an entity register (read as the lookup)"],
        [%r{\Aregister/itinerar_[^/]+\.json\z}, "an itinerary sidecar (read as its journal's metadata)"],
        [%r{\ASchema/[^/]+\.rng\z}, "the project's RELAX NG schema"],
        [/\A(?:README\.md|LICENSE)\z/, "the deposit's README / LICENSE"],
        [/\A#{Regexp.escape(Nabu::ZipRangeFetch::STATE_FILE)}\z/, "the fetcher's own state pin — not upstream content"]
      ].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Grand Tour digital — early-modern travel journals (Herzog August Bibliothek Wolfenbüttel)",
        license: "CC BY-SA 4.0 — the deposit's LICENSE (Creative Commons Attribution-ShareAlike 4.0 " \
                 "International); Zenodo record 23055358 license cc-by-sa-4.0 and the edition index's licence " \
                 "agree (read 2026-11-03)",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "grand-tour-tei",
        credit: "Grand Tour digital, ed. Angela Göbel and Maximilian Görmar, Herzog August Bibliothek " \
                "Wolfenbüttel — Zenodo 10.5281/zenodo.23055358."
      )

      def self.manifest = MANIFEST

      def self.parallel_parse? = true

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(label: "zenodo 23055358", zip_url: ZIP_URL, metadata_url: nil,
                                            state_subdir: "", state_file: Nabu::ZipRangeFetch::STATE_FILE,
                                            liveness_only: true)]
      end

      # Everything outside the zip's .git/ (class note).
      def self.keep?(rel) = !rel.start_with?(".git/") && rel != ".git"

      # "90r" → "90r"; else the facsimile id's ordinal ("#mss_221-extrav_00107" → "f107").
      def self.citation(label:, facs:)
        folio = label.to_s.strip
        return folio.gsub(/[^\p{Alnum}]/, "") unless folio.empty?

        digits = facs.to_s[/(\d+)\z/, 1]
        digits ? "f#{Integer(digits, 10)}" : nil
      end

      def initialize(range_fetch: ->(**kwargs) { Nabu::ZipRangeFetch.new(**kwargs) })
        super()
        @range_fetch = range_fetch
        @registers = {}
        @indexes = {}
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        journal_files(workdir).each do |path|
          stem = File.basename(path, ".xml")
          yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{stem}", path: path,
                                      metadata: { "stem" => stem })
        end
      end

      def discovery_skips(workdir)
        return Nabu::Adapter::DiscoverySkips.new unless Dir.exist?(workdir)

        journals = journal_files(workdir).to_set { |path| path.delete_prefix("#{File.expand_path(workdir)}/") }
        notes = []
        unrecognized = []
        Dir.glob("**/*", File::FNM_DOTMATCH, base: workdir).sort.each do |rel|
          next if rel.start_with?("#{ATTIC_DIRNAME}/") || !File.file?(File.join(workdir, rel)) ||
                  journals.include?(rel)

          rule = SKIP_RULES.find { |pattern, _| pattern.match?(rel) }
          rule ? notes << "#{rel}: #{rule.last}" : unrecognized << rel
        end
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: notes.size, unrecognized: unrecognized.size,
          notes: notes + unrecognized.map { |rel| "#{rel}: unrecognized member of the Grand Tour deposit" }
        )
      end

      def parse(document_ref)
        stem = document_ref.metadata.fetch("stem") { File.basename(document_ref.path, ".xml") }
        root = deposit_root(document_ref.path)
        result = GrandTourTeiParser.new(register: register(root)).parse(document_ref.path)
        raise Nabu::ParseError, "#{document_ref.path}: no transcribed page" if result.pages.empty?

        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: Normalize.nfc(result.header.title || stem),
                                      metadata: document_metadata(stem, root, result))
        add_passages(document, result.pages)
        document
      rescue Nabu::ValidationError, JSON::ParserError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.class}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        fetch = @range_fetch.call(url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
                                  select: ->(rel) { self.class.keep?(rel) }, progress: progress)
        fetch.prepare!
        result = fetch.result
        unless fetch.not_modified?
          verify_pin!(result.sha)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        end
        fetch.complete!
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now,
                              notes: [fetch_note(fetch, result), attic_notes(fetch.result.atticked)].compact.join("; "))
      rescue Nabu::ZipRangeFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def journal_files(workdir)
        Dir.glob(File.join(workdir, JOURNALS_DIR, "*.xml")).reject { |path| File.basename(path) == INDEX }
                                                           .map { |path| File.expand_path(path) }.sort
      end

      # The deposit root holding register/ — the journal's parent's parent,
      # walking up for an attic copy (the attic mirrors the relative shape
      # but holds only what upstream deleted).
      def deposit_root(path)
        dir = File.dirname(path, 2)
        4.times do
          return dir if File.file?(File.join(dir, "register", REGISTERS[:places].first))

          dir = File.dirname(dir)
        end
        File.dirname(path, 2)
      end

      def register(root)
        @registers[root] ||= GrandTourTeiParser::Register.new(
          **REGISTERS.to_h do |kind, (file, entry)|
            [kind, GrandTourTeiParser.load_register(File.join(root, "register", file), entry: entry)]
          end
        )
      end

      # stem → the index's group head ("Wagener, 1652-1659").
      def group_labels(root)
        @indexes[root] ||= begin
          path = File.join(root, JOURNALS_DIR, INDEX)
          if File.file?(path)
            doc = Nokogiri::XML(SourceRead.utf8_file(path, label: SLUG))
            doc.remove_namespaces!
            doc.xpath("//group").each_with_object({}) do |group, labels|
              head = group.at_xpath("head")&.text.to_s.gsub(/\s+/, " ").strip
              group.xpath("include").each do |inc|
                labels[File.basename(inc["href"].to_s, ".xml")] = head unless inc["href"].to_s.include?("introduction")
              end
            end
          else
            {}
          end
        end
      end

      def document_metadata(stem, root, result)
        header = result.header
        pages = result.pages
        label = group_labels(root)[stem]
        mentions = pages.flat_map { |page| page.places + page.persons + page.orgs }
        {
          "shelfmark" => header.shelfmark, "author" => author(header.title), "bibl" => header.bibl,
          "publication_note" => header.publication_note, "responsibility" => presence(header.statements),
          "edition_group" => label, "work_in_progress" => label&.include?("in Bearbeitung") || nil,
          "date" => date(pages), "places_mentioned" => names(pages.flat_map(&:places)),
          "persons_mentioned" => names(pages.flat_map(&:persons)), "orgs_mentioned" => names(pages.flat_map(&:orgs)),
          "entity_mentions" => { "resolved" => mentions.count { |m| !m["unresolved"] },
                                 "unresolved" => mentions.count { |m| m["unresolved"] } },
          "itinerary" => itinerary(root, stem), "blank_pages" => result.blank_pages,
          "text_nature" => "htr-corrected", "text_note" => TEXT_NOTE
        }.compact.then { |meta| deep_nfc(meta) }
      end

      # The title's "Author: Title" head, upstream's own pattern.
      def author(title)
        head, rest = title.to_s.split(": ", 2)
        rest && !head.strip.empty? ? head.strip : nil
      end

      def date(pages)
        years = pages.flat_map(&:dates).map { |w| Integer(w[0, 4], 10) }
        return nil if years.empty?

        all = pages.flat_map(&:dates).sort
        { "not_before" => years.min, "not_after" => years.max,
          "raw" => "dated entries #{all.first} … #{all.last}", "class" => "composition" }
      end

      def names(mentions)
        values = mentions.reject { |m| m["unresolved"] }.map { |m| m["value"] }.uniq
        values.empty? ? nil : values
      end

      def itinerary(root, stem)
        file = ITINERARIES[stem] or return nil
        path = File.join(root, "register", file)
        return nil unless File.file?(path)

        JSON.parse(SourceRead.utf8_file(path, label: SLUG)).fetch("rows", []).map do |row|
          { "date" => row["Datum"], "place" => row["Ort"], "geonames" => blank_nil(row["GeoNames ID"]),
            "lat" => blank_nil(row["latitude"]), "lon" => blank_nil(row["longitude"]),
            "journey" => row["Reise"] }.compact
        end
      end

      def add_passages(document, pages)
        seen = Hash.new(0)
        pages.each_with_index do |page, index|
          citation = self.class.citation(label: page.n, facs: page.facs) || "s#{index + 1}"
          seen[citation] += 1
          citation = "#{citation}-#{seen[citation]}" if seen[citation] > 1
          document << Nabu::Passage.new(urn: "#{document.urn}:#{citation}", language: LANGUAGE,
                                        text: Normalize.nfc(page.text), sequence: index + 1,
                                        annotations: annotations(page))
        end
      end

      def annotations(page)
        regularized = Normalize.nfc(page.regularized)
        deep_nfc({
          "page" => page.n, "facs" => page.facs&.delete_prefix("#"),
          "regularized" => (regularized unless regularized == Normalize.nfc(page.text.tr("\n", " "))),
          "places" => presence(page.places), "persons" => presence(page.persons), "orgs" => presence(page.orgs),
          "dates" => presence(page.dates), "deletions" => presence(page.deletions),
          "variants" => presence(page.variants), "marginalia" => presence(page.marginalia),
          "editorial_notes" => presence(page.editorial_notes)
        }.compact)
      end

      def fetch_note(fetch, result)
        return "not modified (directory pin, every kept member on disk)" if fetch.not_modified?

        "zenodo 23055358 directory pin verified; #{result.kept} members kept by Range, #{result.skipped} never read"
      end

      def verify_pin!(sha)
        return if sha == DIRECTORY_SHA256

        raise Nabu::FetchError,
              "#{SLUG}: the zip directory misses the 2026-09-30 pin (expected #{DIRECTORY_SHA256}, got #{sha}) — " \
              "Zenodo files are immutable, so this is corruption or a new version; read #{RECORD_URL} and re-pin"
      end

      def presence(list) = list.empty? ? nil : list

      def blank_nil(value) = value.to_s.strip.empty? ? nil : value

      def deep_nfc(value)
        case value
        when String then Normalize.nfc(value)
        when Hash then value.transform_values { |v| deep_nfc(v) }
        when Array then value.map { |v| deep_nfc(v) }
        else value
        end
      end
    end
  end
end
