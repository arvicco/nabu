# frozen_string_literal: true

require_relative "titus_tocharian_parser"

module Nabu
  module Adapters
    # TITUS Tocharian A Corpus (P114-1a) — the East Tocharian manuscripts of
    # the Berlin Turfan collection as served by TITUS (J. W. Goethe-
    # Universität Frankfurt, Prof. Jost Gippert): on the basis of E. Sieg &
    # W. Siegling, Tocharische Sprachreste I (Berlin/Leipzig 1921), entered
    # by P. Olivier and T. Tamai (1996–98), collated with the manuscripts by
    # T. Tamai (1998–2001), corrections K. Kupfer; TITUS version with the
    # THT catalogue data by J. Gippert, K. Kupfer, T. Tamai.
    #
    # == The grant (by email, 2026-10-06) and the credit duty
    #
    # Fetched under the owner's PERSONAL grant — the third extension on the
    # 2026-07-23 Avestan terms: ONE retrieval per corpus, local personal
    # research use only, no redistribution, TITUS and the editors credited
    # wherever displayed. The titus-avestan mechanisms verbatim:
    # `grant_required: true` guards the fetch right; license_class `nc` +
    # the manifest +credit+ line carry the display duty.
    #
    # == Shape (see Nabu::Adapters::TitusTocharianParser)
    #
    # One PAGE is one document — and one page is one Sieg & Siegling number
    # (tochaNNN = "A NNN", the page header's own "Part No. NNN"; 467 pages
    # censused by HEAD probe 2026-10-07), carrying one THT manuscript. The
    # manuscript LINES are the passages (the bilingual pages' 1a/1b
    # sub-lines are their own passages, each with its lane's language).
    #
    # == Mined metadata (the №R-70 aggressive-mining law)
    #
    # The THT catalogue block rides document metadata: the edition number,
    # the Berlin find signature verbatim ("T_III_Š_72.1"), the THT
    # number(s), the German catalogue note. The signature's SITE siglum
    # mines the findspot through SITE_SIGLA — DELIBERATELY coarse and
    # declared: only the sigla censused on the live pages resolve (Š, D);
    # any other siglum mints no place (the raw signature still rides), and
    # the first-sync census extends the table. The expedition numeral is
    # not mined (the catalogue prose and the numeral disagree on page 467 —
    # never guessed). The pages carry no dating — undatable is honest.
    class TitusTocharianA < Nabu::Adapter
      SLUG = "titus-tocharian-a"
      PARSER_FAMILY = "titus_tocharian"
      LANGUAGE = "xto"

      ENTRY_URL = "https://titus.uni-frankfurt.de/texte/etcs/toch/tocha/tocha.htm"

      LICENSE = "personal grant, Gippert (by email, 2026-10-06, extending the 2026-07-23 " \
                "Avestan terms): one retrieval, local personal research use only, no " \
                "redistribution; TITUS and the editors clearly indicated wherever displayed"

      CREDIT = "TITUS (J. Gippert, Frankfurt) — Tocharian A corpus (Berlin Turfan collection) " \
               "on the basis of E. Sieg & W. Siegling, Tocharische Sprachreste I (1921); data " \
               "entry P. Olivier & T. Tamai, collation T. Tamai, corrections K. Kupfer; TITUS " \
               "version J. Gippert, K. Kupfer, T. Tamai."

      # Numbered text pages (tocha001.htm …); the frameset tocha.htm and the
      # index frames (tochax.htm, tochaxx.htm, tochax1.htm, tochalex.htm)
      # are not.
      PAGE_GLOB = "tocha*.htm"
      PAGE_RE = /\Atocha\d+\.htm\z/

      # Berlin Turfan find-signature SITE sigla → findspot. Census-complete
      # for the 13 live pages sampled 2026-10-07 (Š on the Šorčuq pages, D
      # on the Qočo pages — the catalogue's own prose names "Chotscho" for
      # a T I D fragment, tocha467). Unknown sigla mint nothing.
      SITE_SIGLA = { "Š" => "Šorčuq", "D" => "Qočo" }.freeze

      # "No._1 = T_III_Š_72.1" — the edition number and the find signature.
      NUMBER_LINE = /\ANo\._(\d+)\s*=\s*(\S+)\z/

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "TITUS Tocharian A Corpus",
          license: LICENSE,
          license_class: "nc",
          upstream_url: ENTRY_URL,
          parser_family: PARSER_FAMILY,
          credit: CREDIT
        )
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "tocha.htm entry", zip_url: ENTRY_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::TitusFetch::STATE_FILE
        )]
      end

      # The findspot a find signature's site siglum names, or nil.
      # "T_III_Š_72.1" → "Šorčuq"; an unknown siglum → nil.
      def self.findspot_for(signature)
        siglum = signature.to_s.split("_")[2]
        SITE_SIGLA[siglum]
      end

      # A manuscript anchor with no part/line anchor below it: the page is
      # the catalogue entry alone (tocha227 = A 227, THT 860: the find
      # signature and the THT number, no text — 1 of 467 at the first-sync
      # census, 2026-10-10).
      MANUSCRIPT_ANCHOR = /NAME="TochA_THT_[^_"]+"/
      DEEPER_ANCHOR = /NAME="TochA_THT_[^_"]+_[^"]+"/

      # One DocumentRef per fetched text page (ref.id IS the document urn).
      # Catalogue-only pages skip by rule, censused by discovery_skips.
      def discover(workdir)
        text_pages(workdir).reject { |path| catalogue_only?(path) }.map do |path|
          stem = File.basename(path).delete_suffix(".htm")
          Nabu::DocumentRef.new(source_id: SLUG, id: document_urn(stem), path: path,
                                metadata: { "page" => stem })
        end
      end

      def discovery_skips(workdir)
        skipped = text_pages(workdir).count { |path| catalogue_only?(path) }
        notes = skipped.positive? ? ["#{skipped} catalogue-only page(s) skipped — THT catalogue entry, no text"] : []
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: 0, notes: notes)
      end

      # Parse one page into a Document of line Passages. A page with no
      # keyable lines quarantines whole (ParseError) — never served empty.
      def parse(document_ref)
        html = TitusTocharianParser.read_page(document_ref.path)
        page = TitusTocharianParser.parse(html)
        raise Nabu::ParseError, "#{SLUG}: no text lines in #{document_ref.path}" if page.lines.empty?

        stem = document_ref.metadata["page"]
        metadata = page_metadata(page)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(stem, page, metadata), metadata: metadata
        )
        seen = Hash.new(0)
        page.lines.each_with_index do |line, sequence|
          citation = line.components.join(".")
          occurrence = (seen[citation] += 1)
          document << Nabu::Passage.new(
            urn: passage_urn(document_ref.id, citation, occurrence),
            language: line.language, text: line.text, sequence: sequence,
            annotations: line_annotations(line, occurrence)
          )
        end
        document
      end

      # Polite sequential page walk from the frameset (owner-run; never in
      # tests) — the same TitusFetch machinery as the Avestan and
      # Osco-Umbrian corpora, steered by this corpus's page pattern.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::TitusFetch.sync!(
          entry_url: ENTRY_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          page_re: PAGE_RE, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue Nabu::TitusFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def text_pages(workdir)
        Dir.glob(File.join(workdir, PAGE_GLOB)).select { |path| File.basename(path).match?(PAGE_RE) }
      end

      def catalogue_only?(path)
        html = File.binread(path)
        html.match?(MANUSCRIPT_ANCHOR) && !html.match?(DEEPER_ANCHOR)
      end

      def document_urn(stem)
        "urn:nabu:#{SLUG}:#{stem}"
      end

      def passage_urn(document_urn, citation, occurrence)
        tail = occurrence > 1 ? "#{citation}##{occurrence}" : citation
        "#{document_urn}:#{tail}"
      end

      # The catalogue block, mined: the first manuscript's "No._N = <sig>"
      # line yields the edition number + signature; the remaining notes
      # (minus the bare "THT NNNN" restatement) are the catalogue prose.
      def page_metadata(page)
        catalogue = page.manuscripts.flat_map(&:catalogue)
        number_line = catalogue.find { |note| note.match?(NUMBER_LINE) }
        metadata = { "manuscripts" => page.manuscripts.map(&:number) }
        if number_line
          number, signature = NUMBER_LINE.match(number_line).captures
          metadata["edition_number"] = number
          metadata["signature"] = signature
          findspot = self.class.findspot_for(signature)
          metadata["findspot"] = findspot if findspot
        end
        prose = catalogue.reject { |note| note == number_line || note.match?(/\ATHT \d+\z/) }
        metadata["catalogue"] = prose unless prose.empty?
        preservation = page.notes.map { |line| { "line" => line.components.join("."), "note" => line.note } }
        metadata["preservation"] = preservation unless preservation.empty?
        metadata
      end

      def line_annotations(line, occurrence)
        manuscript, part, number = line.components
        annotations = { "manuscript" => manuscript, "part" => part, "line" => number }
        annotations["syllabic"] = line.syllabic if line.syllabic
        annotations["side"] = line.side if line.side
        annotations["footnotes"] = line.footnotes unless line.footnotes.empty?
        annotations["note"] = line.note if line.note
        annotations["inline"] = line.inline unless line.inline.empty?
        annotations["inline_syllabic"] = line.inline_syllabic unless line.inline_syllabic.empty?
        annotations["repetition"] = occurrence if occurrence > 1
        annotations
      end

      def title_for(stem, page, metadata)
        manuscripts = page.manuscripts.map { |m| "THT #{m.number}" }.join(", ")
        label = [metadata["edition_number"]&.then { |n| "A #{n}" }, manuscripts].compact.reject(&:empty?)
        "Tocharian A Corpus — #{label.join(', ')} (#{stem})"
      end
    end
  end
end
