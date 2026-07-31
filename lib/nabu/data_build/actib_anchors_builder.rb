# frozen_string_literal: true

require "digest"
require "json"
require "sequel"

require_relative "../errors"
require_relative "../config"
require_relative "../adapters/esukhia_text_parser"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The xct/actib-anchors builder (P55-4) — nabu-data's FIRST
    # RE-PUBLICATION. ACTib v2.0 (Meelen, Hill & Faggionato; Zenodo record
    # 3951503) ships the word-segmented + POS-tagged eKangyur with NO stable
    # anchors into its source etexts — an upstream text update orphans the
    # whole layer (the known weakness the concept doc's prior-art verdict
    # pinned). This dataset publishes the anchor table that fixes it: one
    # row per derge-kangyur passage mapping URN + Passage_SHA256 (the Nabu
    # side) to (ACTib_Volume, ACTib_Page, ACTib_Line) (the ACTib side), with
    # the measured match census published in-band as nabu.eval.
    #
    # == What is NOT here (the load-bearing scope rule)
    #
    # The ~800 MB seg+POS token content is NEVER republished. Rows carry
    # only the join key; consumers take the DOI-cited Zenodo artifact
    # (SegPOS-eKangyur_July2020.zip) and join on the anchor key. The one
    # deliberate exception: near/partial rows republish BOTH text forms —
    # folded to the comparison form — in divergences.csv, because that
    # per-line divergence census is exactly the proofreading surface
    # scholars can act on.
    #
    # == The mapping (promoted from the P55 census scripts)
    #
    # Ported from the owner-run measurement pass (scratchpad actib_lib.rb /
    # census.rb / recensus_vol31.rb, 2026-07-31 — the scripts stay working
    # material; this class is the durable home):
    #
    # - Volume: Esukhia volume N reads ACTib file UT4CZ5369-I1KG(9126+N),
    #   with the tail permutation VOL_PERMUTATION (BDRC orders the last
    #   three volumes gzungs-'dus E/WaM/dri-med-'od differently).
    # - Page: walk each canonical derge volume's citation brackets in
    #   order; every NEW folio side increments the physical page counter —
    #   duplicated x-folios ([33xa]) are real physical pages, shifting
    #   everything after them (the naive p = 2F−(a?1:0) rule breaks there).
    #   {D/T} Tohoku markers keep the map PER DOCUMENT, because folio
    #   numbering can RESTART mid-volume (vol 31, where Toh 11 begins —
    #   the census's vol-31 correction, recensus_vol31.rb).
    # - Line: ACTib's own inline p<N>/ln<N> tokens (seg layer; <utt>
    #   utterance markers dropped).
    # - Comparison form: whitespace-free NFC letter streams on both sides.
    #
    # == Statuses (anchors.csv), the census vocabulary
    #
    # exact (letter streams equal) · near (neither equal nor containment —
    # Distance carries the exact Levenshtein distance) · partial (one
    # stream contains the other) · missing (no ACTib content at the mapped
    # line — including every volume's title folio 1a, which ACTib carries
    # without a line marker). A ref the citation grammar cannot parse is
    # censused as badref (eval + README), never faked as a row.
    class ActibAnchorsBuilder
      DERGE_SLUG = "derge-kangyur"
      ACTIB_SLUG = "actib"

      TEXT_DIRNAME = "text" # canonical/derge-kangyur/text
      SEG_DIRNAME = "seg"   # canonical/actib/seg

      ANCHORS_FILENAME = "anchors.csv"
      DIVERGENCES_FILENAME = "divergences.csv"
      ANCHORS_COLUMNS = %w[ID URN Passage_SHA256 ACTib_Volume ACTib_Page ACTib_Line
                           Status Distance].freeze
      DIVERGENCES_COLUMNS = %w[ID URN Passage_SHA256 ACTib_Volume ACTib_Page ACTib_Line
                               Status Distance Nabu_Text ACTib_Text].freeze
      INTEGER_COLUMNS = %w[ACTib_Page ACTib_Line Distance].freeze

      # Esukhia (Nabu) volume number → ACTib/BDRC volume position. Identity
      # except the tail: BDRC 100=dri-med-'od, 101=gzungs-'dus E,
      # 102=gzungs-'dus WaM; Esukhia 100=E, 101=WaM, 102=dri-med-'od.
      VOL_PERMUTATION = { 100 => 101, 101 => 102, 102 => 100 }.freeze
      BDRC_OFFSET = 9126
      SEG_FILENAME_FORMAT = "UT4CZ5369-I1KG%d-0000.txt"

      # The derge passage citation grammar (volume prefix on multi-volume
      # documents; the house :bN collision suffix would keep its colon and
      # honestly fail this — censused as badref, like the census did).
      REF = /\A(?:(\d+)\.)?(\d+x?[ab])(?:\.(\d+))?\z/

      STATUS_EXACT = "exact"
      STATUS_NEAR = "near"
      STATUS_PARTIAL = "partial"
      STATUS_MISSING = "missing"

      ACTIB_BIB_KEY = "actib"
      DERGE_BIB_KEY = "derge"

      # How many badref URNs the README names before truncating (announce
      # the truncation, never silently cap).
      BADREF_README_CAP = 10

      # Part of the derivation fingerprint: changing the mapping, the fold,
      # or the classification MUST change this string.
      RECIPE = "xct/actib-anchors v1: anchor every live derge-kangyur passage (page.line " \
               "citation grain) to its ACTib v2.0 SegPOS-eKangyur seg line (Zenodo 3951503): " \
               "Esukhia volume N reads BDRC volume I1KG(9126+N) after the tail permutation " \
               "{100→101, 101→102, 102→100}; folio→physical-page by walking each canonical " \
               "volume's citation brackets in order (every new folio side increments the page " \
               "counter, duplicated x-folio sides included, so [33xa]/[33xb] shift later folios; " \
               "{D/T} Tohoku markers keep per-document folio maps so a mid-volume folio restart " \
               "— the vol-31 Toh 11 seam, the census's vol-31 correction — resolves per " \
               "document); line from ACTib's inline p<N>/ln<N> tokens (<utt> dropped); compare " \
               "whitespace-free NFC letter streams — equal = exact, containment = partial, " \
               "otherwise near with the exact Levenshtein distance in the Distance column; an " \
               "absent ACTib line is missing, an unparseable ref is censused as badref, never " \
               "guessed. The seg+POS token content is NOT republished: rows carry only the " \
               "(ACTib_Volume, ACTib_Page, ACTib_Line) join key into the DOI-cited artifact plus " \
               "the URN + Passage_SHA256 anchor into Nabu; near/partial rows republish both " \
               "folded text forms in divergences.csv as the proofreading census."

      # Folio → physical page, per volume and per document — the promoted
      # census mapping (folio_page_map generalized by recensus_vol31.rb's
      # per-document walk). One pass over the canonical volume files in
      # basename order, the current Tohoku document carried ACROSS files
      # (vol 31 opens mid-Toh 10; its {D10} marker lives in vol 29): every
      # bracket line whose folio differs from the previous one starts a new
      # physical page; the folio registers in the volume-wide map (first
      # occurrence wins) and in the current document's map, and a {D/T}
      # marker also registers its boundary folio for the document it opens.
      # Lookup prefers the passage's own document map (the restart
      # disambiguation), then falls back to the volume-wide first
      # occurrence — correct everywhere folio numbering is unique, and the
      # honest answer for documents whose marker predates the walked files.
      class FolioPageWalk
        BRACKET = /\A\[(\d+x?[ab])(?:\.\d+)?\]/
        MARKER = Nabu::Adapters::EsukhiaTextParser::MARKER

        def initialize(paths)
          @volumes = {}
          parser = Nabu::Adapters::EsukhiaTextParser.new
          current = nil
          paths.sort_by { |path| File.basename(path) }.each do |path|
            volume = parser.volume_number(path)
            next if volume.nil?

            current = walk_volume(path, volume, current)
          end
        end

        def page_for(volume:, doc_slug:, folio:)
          maps = @volumes[volume]
          return nil if maps.nil?

          maps.fetch(:per_doc).fetch(doc_slug, {})[folio] || maps.fetch(:wide)[folio]
        end

        private

        def walk_volume(path, volume, current)
          wide = {}
          per_doc = {}
          page = 0
          last_folio = nil
          File.foreach(path, encoding: Encoding::UTF_8) do |line|
            match = BRACKET.match(line)
            next if match.nil?

            folio = match[1]
            if folio != last_folio
              page += 1
              last_folio = folio
            end
            wide[folio] ||= page
            (per_doc[current] ||= {})[folio] ||= page unless current.nil?
            line.scan(MARKER) do |(payload)|
              slug = "toh#{payload.downcase}"
              next if slug == current

              current = slug
              (per_doc[current] ||= {})[folio] ||= page # the boundary folio belongs to both
            end
          end
          @volumes[volume] = { wide: wide, per_doc: per_doc }
          current
        end
      end

      class << self
        # The BDRC volume id for Esukhia volume N ("I1KG9167" for 41).
        def bdrc_volume(volume)
          format("I1KG%d", BDRC_OFFSET + VOL_PERMUTATION.fetch(volume, volume))
        end

        def seg_filename(volume)
          format(SEG_FILENAME_FORMAT, BDRC_OFFSET + VOL_PERMUTATION.fetch(volume, volume))
        end
      end

      def initialize(canonical_dir: nil)
        @canonical_dir = canonical_dir
      end

      def build(catalog:, out_dir:)
        if catalog.nil?
          raise Error, "xct/actib-anchors reads the catalog and no catalog is open on this box — " \
                       "build where db/catalog.sqlite3 exists"
        end

        volume_paths = derge_volume_paths
        seg_dir = actib_seg_dir
        by_volume, badref_urns = passages_by_volume(catalog)
        walk = FolioPageWalk.new(volume_paths)

        anchors, divergences, census = resolve(by_volume, badref_urns, seg_dir, walk)
        anchor_count = CsvWriter.write(path: File.join(out_dir, ANCHORS_FILENAME),
                                       columns: ANCHORS_COLUMNS, rows: anchors)
        divergence_count = CsvWriter.write(path: File.join(out_dir, DIVERGENCES_FILENAME),
                                           columns: DIVERGENCES_COLUMNS, rows: divergences)

        BuildResult.new(resources: [anchors_resource(anchor_count), divergences_resource(divergence_count)],
                        recipe: RECIPE, citations: citations,
                        notes: notes(census, badref_urns), evaluation: census)
      end

      private

      # -- canonical reads ----------------------------------------------------

      def canonical_dir
        @canonical_dir ||= Nabu::Config.load.canonical_dir
      end

      def derge_volume_paths
        paths = Dir.glob(File.join(canonical_dir, DERGE_SLUG, TEXT_DIRNAME, "*.txt"))
        if paths.empty?
          raise Error, "canonical/#{DERGE_SLUG} has no text/ volume files — sync derge-kangyur " \
                       "(bin/nabu sync derge-kangyur) before building xct/actib-anchors"
        end
        paths
      end

      def actib_seg_dir
        dir = File.join(canonical_dir, ACTIB_SLUG, SEG_DIRNAME)
        unless Dir.exist?(dir)
          raise Error, "canonical/#{ACTIB_SLUG} has no seg/ layer (#{dir}) — sync actib " \
                       "(bin/nabu sync actib) before building xct/actib-anchors"
        end
        dir
      end

      # Parse one ACTib seg volume into { [page, line_or_nil] => letters }:
      # tokens concatenated with no separator, <utt> dropped, page/line
      # state from the inline p<N>/ln<N> tokens, values NFC-normalized
      # (ported from the census's parse_actib_volume). A volume file absent
      # upstream yields {} — its passages census as missing, never crash.
      def parse_seg_volume(seg_dir, volume)
        path = File.join(seg_dir, self.class.seg_filename(volume))
        return {} unless File.exist?(path)

        map = Hash.new { |hash, key| hash[key] = +"" }
        page = nil
        line = nil
        File.foreach(path, encoding: Encoding::UTF_8) do |raw|
          raw.split.each do |token|
            next if token == "<utt>"

            if (m = /\Ap(\d+)\z/.match(token))
              page = m[1].to_i
              line = nil
            elsif (m = /\Aln(\d+)\z/.match(token))
              line = m[1].to_i
            else
              map[[page, line]] << token
            end
          end
        end
        map.transform_values! { |value| value.unicode_normalize(:nfc) }
        map
      end

      # -- catalog reads ------------------------------------------------------

      def derge_rows(catalog)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:withdrawn] => false,
                 Sequel[:documents][:withdrawn] => false,
                 Sequel[:sources][:slug] => DERGE_SLUG)
          .order(Sequel[:documents][:urn], Sequel[:passages][:sequence])
          .select(Sequel[:passages][:urn], Sequel[:passages][:text],
                  Sequel[:passages][:content_sha256],
                  Sequel[:documents][:urn].as(:document_urn),
                  Sequel[:documents][:metadata_json])
          .all
      end

      # { volume => [row, ...] } in (document, sequence) order, each row
      # gaining :folio/:line/:doc_slug — plus the badref census (refs the
      # grammar cannot place; the census's badref bucket verbatim).
      def passages_by_volume(catalog)
        rows = derge_rows(catalog)
        if rows.empty?
          raise Error, "the catalog has no derge-kangyur passages — sync the canon " \
                       "(bin/nabu sync derge-kangyur) before building xct/actib-anchors"
        end

        volumes_by_doc = {}
        by_volume = Hash.new { |hash, key| hash[key] = [] }
        badref_urns = []
        rows.each do |row|
          volumes = volumes_by_doc[row[:document_urn]] ||= document_volumes(row[:metadata_json])
          volume = place(row, volumes)
          if volume.nil?
            badref_urns << row[:urn]
          else
            by_volume[volume] << row
          end
        end
        [by_volume, badref_urns]
      end

      def document_volumes(metadata_json)
        Array(JSON.parse(metadata_json.to_s)["volumes"]).map(&:to_i)
      rescue JSON::ParserError
        []
      end

      # The passage's volume: the ref's own prefix when present, else the
      # document's single volume; a multi-volume document's bare ref (or a
      # ref outside the grammar) has no honest placement → badref.
      def place(row, volumes)
        ref = row[:urn].delete_prefix("#{row[:document_urn]}:")
        match = REF.match(ref)
        return nil if match.nil?

        row[:folio] = match[2]
        row[:line] = match[3]&.to_i
        return match[1].to_i if match[1]

        volumes.size == 1 ? volumes.first : nil
      end

      # -- resolution ---------------------------------------------------------

      def resolve(by_volume, badref_urns, seg_dir, walk)
        anchors = []
        divergences = []
        counts = Hash.new(0)
        histogram = Hash.new(0)
        by_volume.keys.sort.each do |volume|
          seg = parse_seg_volume(seg_dir, volume)
          by_volume.fetch(volume).each do |row|
            anchor_row(row, volume, seg, walk, counts, histogram, anchors, divergences)
          end
        end
        counts[:badref] = badref_urns.size
        [anchors, divergences, census(counts, histogram)]
      end

      def anchor_row(row, volume, seg, walk, counts, histogram, anchors, divergences)
        page = walk.page_for(volume: volume, doc_slug: doc_slug(row), folio: row[:folio])
        theirs = page ? seg[[page, row[:line]]] : nil
        ours = letters(row[:text])
        status, distance = classify(ours, theirs)
        counts[:passages] += 1
        counts[:compared] += 1 unless status == STATUS_MISSING
        counts[status.to_sym] += 1
        histogram[distance] += 1 if distance

        cells = common_cells(row, volume, page, status, distance)
        anchors << cells.merge("ID" => mint_id("a", row))
        return unless [STATUS_NEAR, STATUS_PARTIAL].include?(status)

        divergences << cells.merge("ID" => mint_id("d", row),
                                   "Nabu_Text" => ours, "ACTib_Text" => theirs)
      end

      def common_cells(row, volume, page, status, distance)
        {
          "URN" => row[:urn],
          "Passage_SHA256" => row[:content_sha256],
          "ACTib_Volume" => self.class.bdrc_volume(volume),
          "ACTib_Page" => page,
          "ACTib_Line" => row[:line],
          "Status" => status,
          "Distance" => distance
        }
      end

      def doc_slug(row)
        row[:document_urn].split(":").last
      end

      def mint_id(prefix, row)
        CsvWriter.mint_id(prefix, doc_slug(row), row[:urn].delete_prefix("#{row[:document_urn]}:"))
      end

      # The comparison fold: the passage's letter stream, whitespace
      # stripped (catalog text is already NFC at the adapter boundary; the
      # ACTib side is NFC-normalized at parse — the census fold verbatim).
      def letters(text)
        text.gsub(/\s+/, "")
      end

      def classify(ours, theirs)
        return [STATUS_MISSING, nil] if theirs.nil? || theirs.empty?
        return [STATUS_EXACT, nil] if ours == theirs
        return [STATUS_PARTIAL, nil] if theirs.include?(ours) || ours.include?(theirs)

        [STATUS_NEAR, edit_distance(ours, theirs)]
      end

      # Exact Levenshtein distance (the census's edit_distance, cutoff
      # dropped: only near rows — a few thousand corpus-wide — ever reach
      # it, and the Distance column must not lie).
      def edit_distance(ours, theirs)
        ours, theirs = theirs, ours if ours.length > theirs.length
        return theirs.length if ours.empty?

        previous = (0..ours.length).to_a
        theirs.each_char.with_index do |their_char, i|
          current = [i + 1]
          ours.each_char.with_index do |our_char, j|
            cost = our_char == their_char ? 0 : 1
            current << [previous[j] + cost, previous[j + 1] + 1, current[j] + 1].min
          end
          previous = current
        end
        previous[-1]
      end

      # -- census -------------------------------------------------------------

      # The measured anchoring quality IS the eval (the packet rule): the
      # census totals verbatim plus the near-distance histogram.
      def census(counts, histogram)
        compared = counts[:compared]
        {
          "passages" => counts[:passages] + counts[:badref],
          "compared" => compared,
          "exact" => counts[:exact],
          "near" => counts[:near],
          "partial" => counts[:partial],
          "missing" => counts[:missing],
          "badref" => counts[:badref],
          "exact_rate" => compared.zero? ? 0.0 : (counts[:exact].to_f / compared).round(4),
          "distance_histogram" => histogram.sort.to_h { |distance, count| [distance.to_s, count] },
          "against" => "ACTib v2.0 SegPOS-eKangyur seg layer (Zenodo record 3951503), " \
                       "whitespace-free NFC letter streams, exact/containment/Levenshtein " \
                       "classification — a passage with no ACTib content at its mapped line " \
                       "is censused missing, never guessed"
        }
      end

      # -- furniture ----------------------------------------------------------

      def csv_fields(columns)
        columns.map { |name| { name: name, type: INTEGER_COLUMNS.include?(name) ? "integer" : "string" } }
      end

      def anchors_resource(count)
        Resource.new(name: "anchors", path: ANCHORS_FILENAME, rows: count,
                     fields: csv_fields(ANCHORS_COLUMNS), primary_key: ["ID"])
      end

      def divergences_resource(count)
        Resource.new(name: "divergences", path: DIVERGENCES_FILENAME, rows: count,
                     fields: csv_fields(DIVERGENCES_COLUMNS), primary_key: ["ID"])
      end

      def citations
        [
          Citation.new(
            key: ACTIB_BIB_KEY, type: "misc",
            fields: {
              "author" => "Meelen, Marieke and Hill, Nathan and Faggionato, Christian",
              "title" => "The Annotated Corpus of Classical Tibetan (ACTib)",
              "year" => "2020",
              "version" => "2.0",
              "doi" => "10.5281/zenodo.3951503",
              "note" => "CC BY 4.0 — the license basis is the Zenodo RECORD's declared license " \
                        "(API-verified 2026-07-31); the zip itself contains no license file " \
                        "(recorded honestly). File anchored: SegPOS-eKangyur_July2020.zip, the " \
                        "eKangyur seg + pos layers."
            }
          ),
          Citation.new(
            key: DERGE_BIB_KEY, type: "misc",
            fields: {
              "title" => "Digital Derge Kangyur (Esukhia/Barom proofreading of the UVA-SOAS 2013 eKangyur)",
              "howpublished" => "https://github.com/Esukhia/derge-kangyur",
              "note" => "Public Domain (upstream README declaration); " \
                        "ཆོས་ཀྱི་འབྱུང་" \
                        "གནས། [1721--31], Derge woodblock Kangyur"
            }
          )
        ]
      end

      def notes(census, badref_urns)
        <<~NOTES.strip
          ## What a row means — the two-way anchoring contract

          Each `anchors.csv` row ties one Derge Kangyur passage to one ACTib line.
          On the Nabu side, `URN` + `Passage_SHA256` name the exact catalog
          passage bytes (rows apply only where the sha matches). On the ACTib
          side, `(ACTib_Volume, ACTib_Page, ACTib_Line)` is the join key:
          `ACTib_Volume` is the BDRC volume id as it appears in the artifact's
          filenames (`UT4CZ5369-<ACTib_Volume>-0000.txt`), `ACTib_Page`/
          `ACTib_Line` are ACTib's own inline `p<N>`/`ln<N>` markers. An empty
          `ACTib_Line` means the page carries no line markers there (every
          volume's title page, for one).

          ## The join contract — the layer content is NOT republished

          This dataset deliberately contains none of ACTib's ~800 MB segmented/
          POS-tagged text. Consumers take the DOI-cited artifact —
          `SegPOS-eKangyur_July2020.zip` on Zenodo record 3951503
          (doi:10.5281/zenodo.3951503) — and join its `seg/` or `pos/` volume
          files on `(ACTib_Volume, ACTib_Page, ACTib_Line)`. License basis,
          stated honestly: the Zenodo record declares CC BY 4.0; the zip itself
          carries no license file — the record, not in-zip text, is the grant.

          ## The census — the measured anchoring quality

          Of #{census.fetch('passages')} passages: #{census.fetch('compared')} compared —
          #{census.fetch('exact')} exact (#{format('%.2f%%', census.fetch('exact_rate') * 100)} of compared),
          #{census.fetch('near')} near (letter edit distance in `Distance`; histogram
          #{census.fetch('distance_histogram').inspect}), #{census.fetch('partial')} partial
          (one letter stream contains the other) — plus #{census.fetch('missing')} missing
          (no ACTib content at the mapped line) and #{census.fetch('badref')} badref
          (refs outside the citation grammar#{badref_note(badref_urns)}). Missing and badref
          rows are censused here and in `nabu.eval`, never faked as anchor rows.
          Comparison is on whitespace-free NFC letter streams; the same numbers
          ride `datapackage.json` under `nabu.eval`.

          ## divergences.csv — the proofreading census

          The near + partial rows again, WITH both folded text forms in-band
          (`Nabu_Text` = the Derge passage's letters, `ACTib_Text` = ACTib's) —
          the per-line divergence list a proofreader can act on directly.

          ## Loading

              import pandas as pd
              anchors = pd.read_csv("anchors.csv", keep_default_na=False)

          How to cite: reference ACTib (Meelen, Hill & Faggionato — the `actib`
          key in `sources.bib`, DOI 10.5281/zenodo.3951503) alongside this
          dataset's `datapackage.json` provenance block.
        NOTES
      end

      def badref_note(badref_urns)
        return "" if badref_urns.empty?

        named = badref_urns.first(BADREF_README_CAP)
        listed = named.map { |urn| "`#{urn}`" }.join(", ")
        suffix = badref_urns.size > named.size ? ", … #{badref_urns.size - named.size} more truncated" : ""
        ": #{listed}#{suffix}"
      end
    end
  end
end
