# frozen_string_literal: true

require_relative "source_read"
require_relative "titus_old_prussian_parser"

module Nabu
  module Adapters
    # TITUS Old Prussian Corpus — the complete written record of Old
    # Prussian as served by TITUS (J. W. Goethe-Universität Frankfurt,
    # Prof. Jost Gippert): the three Lutheran catechisms (Königsberg 1545,
    # 1545, and Abel Will's Enchiridion of 1561), the Elbing Vocabulary and
    # Simon Grunau's vocabulary, and the minor fragments (the Basel
    # epigram among them). A diplomatic edition after V. Mažiulis, Prūsų
    # kalbos paminklai (Vilnius 1966/1981), data entry W. Euler (München
    # 1997-1998), TITUS version J. Gippert.
    #
    # == The grant (by email, 2026-11-12) and the credit duty
    #
    # Fetched under the owner's PERSONAL grant on the terms of the TITUS
    # family: one retrieval, local personal research use, no
    # redistribution, TITUS and the editors credited wherever displayed.
    # Same two mechanisms as titus-avestan: `grant_required: true` guards
    # the fetch right; license_class `nc` + the manifest +credit+ line
    # carry the display duty.
    #
    # == Shape (see Nabu::Adapters::TitusOldPrussianParser)
    #
    # One PAGE is one document (the family grain); the printed Old Prussian
    # LINES are the passages (an Elbing/Grunau vocabulary line is one
    # German-Prussian entry), the German lane riding as the `german`
    # annotation. Upstream's delivery grains (the frameset index, census
    # 2026-11-12): 40 text pages apreu001…apreu040 — Kat.I 1-7, Kat.II
    # 8-14, Kat.III 15-27, Gloss. 28-32 (E = Elbing on one page; Grunau's
    # GrG/GrA/GrF/GrColl.), Fragm. 33-40; the frameset (apreu.htm) and its
    # index frames (apreux*.htm) are navigation, never fetched as text.
    # Pages carrying NO Old Prussian lane skip by rule: each text's
    # editorial notes page (the "N."/"Anm." part, footnote lanes only) and
    # German-only front matter (Catechism I's and II's German title pages
    # and prefaces) — expected ~6 of 40, to be reconciled at the first
    # sync. German-only and translation lines inside a text page are not
    # passages either (declared, the parser's lane rule).
    #
    # == Dating and place: what the title pages state
    #
    # Every page's anchors name its text (Kat.I …), so the document carries
    # its text's own title-page imprint: Catechisms I and II print "1.5.45",
    # the Enchiridion "Gedruckt zu Kőnigsperg in Preuſſen durch Johann
    # Daubman. M.D. LXI." — the print year as a :structured date of class
    # edition (the korpus16 precedent for Reformation prints), Königsberg as
    # the place where stated. Deliberately coarse: Catechisms I/II name no
    # print place on their title pages (no claim), and the vocabularies and
    # fragments carry no date in the edition's headers (the Elbing
    # manuscript's c. 1400 is scholarship, not a header — no claim).
    class TitusOldPrussian < Nabu::Adapter
      SLUG = "titus-old-prussian"
      LANGUAGE = "prg" # Old Prussian
      PARSER_FAMILY = "titus_old_prussian"

      ENTRY_URL = "https://titus.uni-frankfurt.de/texte/etcs/balt/apreuss/apreuss/apreu.htm"

      LICENSE = "personal grant, Gippert (by email, 2026-11-12, on the TITUS family terms): " \
                "one retrieval, local personal research use, no redistribution; TITUS and " \
                "the editors clearly indicated wherever displayed"

      CREDIT = "TITUS (J. Gippert, Frankfurt) — Old Prussian Corpus after V. Mažiulis, " \
               "Prūsų kalbos paminklai, data entry W. Euler."

      PAGE_GLOB = "apreu*.htm"
      PAGE_RE = /\Aapreu\d+\.htm\z/

      # A page carrying text has at least one Old Prussian content span
      # (the parser's PRUSSIAN_LANE) — the cheap byte needle.
      PRUSSIAN_NEEDLE = /<span id=baapx?(?:12|16|22)>/i

      # Text sigla → display names (the edition's index; display only).
      TEXT_NAMES = {
        "Kat.I" => "Catechism I (1545)", "Kat.II" => "Catechism II (1545)",
        "Kat.III" => "Enchiridion (Catechism III, 1561)", "Gloss." => "Vocabularies",
        "Fragm." => "Fragments"
      }.freeze

      # The vocabularies' parts (Gloss. page subtitle: "Das Elbinger
      # Vokabular und das Glossar Simon Grünaus").
      GLOSS_PARTS = { "E" => "Elbing Vocabulary" }.freeze
      GRUNAU_PART = /\AGr/

      # Each catechism's title-page imprint, verbatim (raw) + the year
      # (apreu001 / apreu008 / apreu015, read 2026-11-12).
      IMPRINTS = {
        "Kat.I" => { year: 1545, raw: "1.5.45" },
        "Kat.II" => { year: 1545, raw: "1.5.45" },
        "Kat.III" => { year: 1561, raw: "M.D. LXI.", place: "Königsberg" }
      }.freeze

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "TITUS Old Prussian Corpus",
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
          label: "apreu.htm entry", zip_url: ENTRY_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::TitusFetch::STATE_FILE
        )]
      end

      # One DocumentRef per fetched page carrying Old Prussian text (ref.id
      # IS the document urn); pages without a Prussian lane skip by rule.
      def discover(workdir)
        text_pages(workdir).filter_map do |path|
          next unless prussian?(path)

          stem = File.basename(path).delete_suffix(".htm")
          Nabu::DocumentRef.new(source_id: SLUG, id: document_urn(stem), path: path,
                                metadata: { "page" => stem })
        end
      end

      # The discovery census: the Prussian-less pages, counted and named.
      def discovery_skips(workdir)
        skipped = text_pages(workdir).count { |path| !prussian?(path) }
        notes = if skipped.positive?
                  ["#{skipped} pages carry no Old Prussian text lane — editorial notes " \
                   "pages and German-only front matter"]
                else
                  []
                end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: 0, notes: notes)
      end

      # Parse one page into a Document of Old Prussian line Passages. A page
      # whose Prussian lanes key no line is a structural failure
      # (ParseError) — quarantined whole, never served with a hole.
      def parse(document_ref)
        html = Nabu::Adapters::SourceRead.utf8_file(document_ref.path, label: SLUG, repair: :severed_tags)
        lines = TitusOldPrussianParser.parse(html)
        raise Nabu::ParseError, "titus-old-prussian: no Old Prussian lines in #{document_ref.path}" if lines.empty?

        stem = document_ref.metadata["page"]
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(stem, lines), metadata: document_metadata(stem, lines)
        )
        seen = Hash.new(0)
        lines.each_with_index do |line, sequence|
          occurrence = (seen[line.anchor] += 1)
          document << Nabu::Passage.new(
            urn: passage_urn(document_ref.id, line.anchor, occurrence),
            language: LANGUAGE, text: line.text, sequence: sequence,
            annotations: line_annotations(line, occurrence)
          )
        end
        document
      end

      # Polite sequential page walk from the frameset (owner-run; never in
      # tests) — the TitusFetch machinery, steered by this corpus's pattern.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::TitusFetch.sync!(
          entry_url: ENTRY_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          page_re: PAGE_RE, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue Nabu::TitusFetch::Error => e
        raise Nabu::FetchError, "titus-old-prussian fetch failed into #{workdir}: #{e.message}"
      end

      private

      def text_pages(workdir)
        Dir.glob(File.join(workdir, PAGE_GLOB)).select { |path| File.basename(path).match?(PAGE_RE) }
      end

      # The byte needle; an unreadable page counts as text so parse
      # quarantines it loudly instead of discovery hiding it.
      def prussian?(path)
        Nabu::Adapters::SourceRead.utf8_file(path, label: SLUG, repair: :severed_tags).match?(PRUSSIAN_NEEDLE)
      rescue Nabu::ParseError
        true
      end

      def document_urn(stem)
        "urn:nabu:#{SLUG}:#{stem}"
      end

      def passage_urn(document_urn, anchor, occurrence)
        tail = occurrence > 1 ? "#{anchor}##{occurrence}" : anchor
        "#{document_urn}:#{tail}"
      end

      # The header levels as raw tokens; empty levels and the fragments'
      # "_" page placeholder are absent, not blank.
      def line_annotations(line, occurrence)
        annotations = { "text" => line.siglum }
        { "part" => line.part, "paragraph" => line.paragraph, "page" => line.page,
          "line" => line.line }.each do |key, value|
          annotations[key] = value unless value.empty? || value == "_"
        end
        annotations["german"] = line.german if line.german
        annotations["repetition"] = occurrence if occurrence > 1
        annotations
      end

      # The page's text siglum (unanimous — a page never straddles two texts
      # in the census; a straddling page claims no text, so no date/kind),
      # its parts, and its text's title-page imprint.
      def document_metadata(stem, lines)
        metadata = { "page" => stem, "parts" => lines.map(&:part).uniq.reject(&:empty?) }
        sigla = lines.map(&:siglum).uniq
        return metadata unless sigla.size == 1

        metadata["text"] = sigla.first
        imprint = IMPRINTS[sigla.first]
        return metadata unless imprint

        metadata["date"] = { "not_before" => imprint[:year], "not_after" => imprint[:year],
                             "raw" => imprint[:raw], "class" => "edition" }
        metadata["place"] = imprint[:place] if imprint[:place]
        metadata
      end

      def title_for(stem, lines)
        siglum = lines.first.siglum
        parts = lines.map(&:part).uniq.reject(&:empty?)
        label = if siglum == "Gloss." && parts.size == 1
                  gloss_part_name(parts.first)
                else
                  [TEXT_NAMES.fetch(siglum, siglum), parts.join(", ")].reject(&:empty?).join(", ")
                end
        "Old Prussian Corpus — #{label} (#{stem})"
      end

      def gloss_part_name(part)
        return GLOSS_PARTS[part] if GLOSS_PARTS.key?(part)
        return "Simon Grunau's vocabulary, #{part}" if part.match?(GRUNAU_PART)

        "Vocabularies, #{part}"
      end
    end
  end
end
