# frozen_string_literal: true

require_relative "sro_tei_parser"

module Nabu
  module Adapters
    # stationers-register — Stationers' Register Online (SRO; Giles Bergel
    # and Ian Gadd, CREATe, University of Glasgow; stationersregister.online):
    # the copy entries of the Stationers' Company of London's Registers A–D,
    # 1557–1640 — every licence to print a "copy" the Company's Clerk
    # entered, with the enterer, the copy-title, the licensers, the fee, and
    # the Master and Wardens in office. Transcribed from Arber's Transcript
    # (1875–94), corrected against the Registers' images and enriched
    # (Phase Two, CREATe / the Bibliographical Society / Bath Spa), published
    # as TEI on GitHub: github.com/gbergel/SRO_data (no LICENSE file; last
    # push 2019-08-27; the SRO_Arber_data name redirects to the same repo).
    #
    # == Shape (censused 2026-11-05 at 562db001…, the master head)
    #
    # The repo's 64 files. TAKEN: "Register /CURRENT Register/reg_{A,B,C,D}-
    # updated.xml" (note the space in "Register "), 29.0 MB, 10,453 <div
    # type="entry"> = A 1,391 · B 2,356 · C 3,530 · D 3,176 — SRO1…SRO10453,
    # every id unique, contiguous across the four files. Document = the
    # entry (urn = its permanent SRO id, the site's own /entry/SRO<n>);
    # passage = each block of its register text (head / p / desc / list /
    # the register's own note). Rejected by rule (discovery_skips): Arber/
    # (19 files — Arber's Transcript rendered entry-by-entry, the older
    # encoding of the same entries; they REUSE the SRO ids, 1,264 entries in
    # volume 1 alone, so discovering them would collide), "Register /OLD
    # Register/" (27 files — superseded working versions of the same
    # registers), the schema/stylesheet pairs (4: sro-transcription.rng,
    # sro-proofing-view.xsl), README.md and the editors' change-list PDF
    # (2), and macOS .DS_Store litter (8). Reconciliation: 4 accepted + 60
    # skipped by rule = 64; 10,453 entries = SRO's own numbering, SRO1 to
    # SRO10453 without a gap.
    #
    # == License — two upstream statements CONFLICT (both read 2026-11-05)
    #
    # In every TEI header (all four CURRENT files): <licence
    # target="http://creativecommons.org/licenses/by/4.0/">Creative Commons
    # Attribution</licence>. The project site's Project page
    # (stationersregister.online/project, served by /api/staticPage?page=
    # project): "TEI data is available on Github under a CC-BY-SA licence,
    # and may accordingly be reused under those terms." The stricter reading
    # (BY-SA) is taken; either way the class is attribution. Cite as the
    # site asks: "Giles Bergel and Ian Gadd, Stationers' Register Online,
    # CREATe, University of Glasgow". The in-file licence is checked per
    # file: any other target quarantines the file's entries.
    #
    # == Axes
    #
    # Dates (TYPED): every entry's metadata block carries a SortDate (one
    # ISO day) and a Register date — either the Clerk's own dated day
    # (when, 9,111 entries) or, for the years before c. 1571 when entries
    # were grouped only by the Company's year, the SRO editors' span
    # between dated neighbours (notBefore/notAfter, 1,342; SortDate = the
    # span's start). Years are new-style (SRO normalizes the 25 March
    # year start). → "date" {not_before, not_after} years, the Register
    # date's wording as raw, the ISO bounds as start/end — the entry's own
    # date of record (artifact basis, no class); 1557–1640 by SortDate.
    # Persons: SRO's name markup — the enterer(s) (role "stationer
    # enterer"), every other named stationer/non-stationer with SRO's own
    # name key (n) — and the Master and Wardens in office ("officers").
    # Places: <placeName> mentions only (1,157, mostly London) — places the
    # entries NAME, never where they were made (deliberately no origin
    # claim: every entry was made at Stationers' Hall, London, but no entry
    # says so). Kind: the whole source is a register (kind_map.yml).
    # Fees: the entry's total in pence (totalEntryPence). Status: SRO's
    # entry flags verbatim (entered / shared / reassigned / cancelled /
    # annotated / stock / notPrinted / other; "incomplete" — the editors'
    # workflow flag — is on all 10,453).
    #
    # Language: English (the Clerk's), declared coarse — Latin formulae
    # ("solutum magistro …") and the occasional foreign copy-title (3
    # <foreign>, unlabelled upstream) ride inside it.
    class StationersRegister < Nabu::Adapter
      SLUG = "stationers-register"
      URN_PREFIX = "urn:nabu:stationers-register:"
      LANGUAGE = "en"
      REPO_URL = "https://github.com/gbergel/SRO_data.git"
      SITE_URL = "https://stationersregister.online"
      LICENCE = "http://creativecommons.org/licenses/by/4.0/"

      # The space in "Register " is upstream's own.
      CURRENT_DIR = File.join("Register ", "CURRENT Register")
      REGISTER_FILE = /\Areg_([A-D])-updated\.xml\z/

      # The rejected grains (class note), checked in order; first match wins.
      SKIP_RULES = [
        ["Arber/", ->(rel) { rel.start_with?("Arber/") },
         "Arber's Transcript rendered entry by entry — the older encoding of the same entries (reusing the SRO ids)"],
        ["Register /OLD Register/", ->(rel) { rel.start_with?("Register /OLD Register/") },
         "superseded working versions of the same registers"],
        ["macOS .DS_Store", ->(rel) { File.basename(rel) == ".DS_Store" }, "Finder metadata, not upstream content"],
        ["schema/stylesheet", ->(rel) { %w[.rng .xsl].include?(File.extname(rel)) },
         "the transcription schema and the proofing-view stylesheet"],
        ["project documents", ->(rel) { ["README.md", "JC-changes-actually-made.pdf"].include?(rel) },
         "the repo README and the editors' change list"]
      ].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Stationers' Register Online — the copy entries of Registers A–D, 1557–1640",
        license: "CC BY-SA (the stricter of two conflicting upstream statements, both read 2026-11-05: every " \
                 "TEI header's <licence target=\"http://creativecommons.org/licenses/by/4.0/\">Creative " \
                 "Commons Attribution</licence>; the project site: \"TEI data is available on Github under a " \
                 "CC-BY-SA licence, and may accordingly be reused under those terms\")",
        license_class: "attribution",
        upstream_url: "https://github.com/gbergel/SRO_data",
        parser_family: "sro-tei",
        credit: "Giles Bergel and Ian Gadd, Stationers' Register Online, CREATe, University of Glasgow, " \
                "stationersregister.online (TEI: github.com/gbergel/SRO_data)"
      )

      def self.manifest = MANIFEST

      def self.upstream_repo_urls = [REPO_URL]

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        register_files(workdir).each do |path, liber|
          parser.entry_ids(path).each do |sro_id|
            yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{sro_id}", path: path,
                                        metadata: { "sro_id" => sro_id, "liber" => liber })
          end
        end
      end

      # Every file beside the four registers, classed by SKIP_RULES and
      # counted per class; anything no rule names is unrecognized (loud).
      def discovery_skips(workdir)
        return Nabu::Adapter::DiscoverySkips.new unless Dir.exist?(workdir)

        counts = Hash.new(0)
        strays = []
        upstream_files(workdir).each do |rel|
          next if accepted?(rel)

          rule = SKIP_RULES.find { |_label, matches, _why| matches.call(rel) }
          rule ? counts[rule] += 1 : strays << rel
        end
        notes = counts.map do |(label, _matches, why), n|
          "#{label}: #{n} file#{'s' unless n == 1} — #{why} (skipped by rule)"
        end
        notes.concat(strays.map { |rel| "#{rel}: unrecognized file in the SRO_data tree" })
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: counts.values.sum, unrecognized: strays.size,
                                          notes: notes)
      end

      def parse(document_ref)
        result = parsed(document_ref.path)
        sro_id = document_ref.metadata["sro_id"]
        entry = result[:entries][sro_id] or
          raise Nabu::ParseError, "#{document_ref.path}: entry #{sro_id} vanished"
        raise Nabu::DocumentSkipped.new(reason: "entry without register text") if entry.blocks.empty?

        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: nfc(entry.titles.first) || "Stationers' Register entry #{sro_id}",
                                      metadata: document_metadata(entry, result[:header]))
        entry.blocks.each_with_index do |block, index|
          document << Nabu::Passage.new(urn: "#{document.urn}:#{index + 1}", language: LANGUAGE,
                                        text: Normalize.nfc(block.text), sequence: index + 1,
                                        annotations: annotations(block))
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: REPO_URL, workdir: workdir, progress: progress, force: force)
      end

      private

      def parser
        @parser ||= SroTeiParser.new
      end

      # [path, liber] for the four CURRENT registers, A → D.
      def register_files(workdir)
        dir = File.join(workdir, CURRENT_DIR)
        return [] unless Dir.exist?(dir)

        Dir.children(dir).sort.filter_map do |name|
          match = REGISTER_FILE.match(name) or next
          [File.expand_path(File.join(dir, name)), match[1]]
        end
      end

      def accepted?(rel)
        File.dirname(rel) == CURRENT_DIR && REGISTER_FILE.match?(File.basename(rel))
      end

      # Workdir-relative files, dotfiles included, never the clone's .git or
      # the attic.
      def upstream_files(workdir)
        Dir.glob("**/*", File::FNM_DOTMATCH, base: workdir).sort.select do |rel|
          top = rel.split("/").first
          next false if [".git", ATTIC_DIRNAME].include?(top)

          File.file?(File.join(workdir, rel))
        end
      end

      # One register file parsed per call, memoized single-slot on (path,
      # size, mtime): discover and the per-entry parses walk file by file,
      # so each file is read once per pass. The licence is verified here,
      # once per file.
      def parsed(path)
        expanded = File.expand_path(path)
        stat = File.stat(expanded)
        key = [expanded, stat.size, stat.mtime]
        return @parsed if @parsed_key == key

        result = parser.parse_file(expanded)
        verify_licence!(expanded, result.header)
        @parsed_key = key
        @parsed = { header: result.header, entries: result.entries.to_h { |entry| [entry.id, entry] } }
      end

      def verify_licence!(path, header)
        return if header.licence == LICENCE

        raise Nabu::ParseError, "#{path}: licence target #{header.licence.inspect} is not #{LICENCE} — " \
                                "the in-file grant this source is held under"
      end

      def document_metadata(entry, header)
        deep_nfc({
          "sro_id" => entry.id, "sro_number" => entry.sro_number, "liber" => entry.liber,
          "register" => entry.liber && "Register #{entry.liber}", "register_title" => header.title,
          "sort_date" => entry.sort_date, "date" => date(entry),
          "fee_pence" => entry.fee_pence, "works" => entry.works,
          "register_ref" => entry.register_ref, "arber_ref" => entry.arber_ref,
          "register_image_id" => entry.register_id,
          "status" => presence(entry.statuses), "titles" => presence(entry.titles),
          "enterers" => presence(enterers(entry)),
          "persons_mentioned" => presence(entry.persons.map { |p| p["name"] }.uniq),
          "persons" => presence(entry.persons), "officers" => presence(entry.officers),
          "places_mentioned" => presence(entry.places), "notes" => presence(entry.notes),
          "url" => "#{SITE_URL}/entry/#{entry.id}", "licence" => header.licence
        }.compact)
      end

      def enterers(entry)
        entry.persons.select { |p| p["role"].to_s.split.include?("enterer") }.map { |p| p["name"] }.uniq
      end

      # The Register date (the Clerk's day, or the editors' company-year
      # span) → year bounds; SortDate stands in only if the Register date
      # is absent (none at the 2026-11-05 census).
      def date(entry)
        reg = entry.register_date || {}
        start = reg["when"] || reg["not_before"] || entry.sort_date
        finish = reg["when"] || reg["not_after"] || entry.sort_date
        not_before = year(start)
        not_after = year(finish)
        return nil if not_before.nil? && not_after.nil?

        { "not_before" => not_before, "not_after" => not_after, "raw" => reg["text"] || entry.sort_date,
          "start" => start, "end" => finish,
          "precision" => reg["when"] ? "day" : "span" }.compact
      end

      def year(iso) = iso && iso[/\A(\d{4})/, 1]&.then { |y| Integer(y, 10) }

      def annotations(block)
        deep_nfc({
          "block" => block.kind, "rend" => block.rend, "notes" => presence(block.notes),
          "deletions" => presence(block.deletions), "foreign" => presence(block.foreign),
          "corrections" => presence(block.corrections)
        }.compact)
      end

      def presence(list) = list.nil? || list.empty? ? nil : list

      def nfc(value) = value && Normalize.nfc(value)

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
