# frozen_string_literal: true

require "nokogiri"

require_relative "../../timeline"

module Nabu
  module Store
    module TimelineBuilder
      # TOROT chronicle annals (P16-3, part 2 of the timeline) — the
      # first PASSAGE-GRAIN timeline rows, the use the nullable passage_seq_*
      # columns were shipped for in migration 008.
      #
      # == Census (2026-07-13, live canonical/torot)
      #
      # The annal year IS structural: chronicle <div> titles carry the anno
      # mundi year ("6360: Mikhail and the beginning of the Land of the Rus",
      # bare "6361", the range "6369–6370: …", "6694 part 1"). Five of the 40
      # TOROT sources are annalistic: lav (89/91 divs AM-titled), pvl-hyp
      # (24/24), kiev-hyp (4/4), nov-sin (163/163), suz-lav (76/76) — 356
      # annal divs; no other source has a single AM-shaped div title, so the
      # shape+range gate below needs no per-source allowlist.
      #
      # == Extraction
      #
      # Streaming Reader (lav.xml is 12 MB — no DOM), tracking each div's
      # title and its sentence ids. A div whose title opens with a 4-digit
      # year in AM_PLAUSIBLE (optionally "–NNNN" for a year range) is an
      # annal; anything else (lav's "Introduction", "Vladimir Monomakh's
      # Instruction") is skipped and counted. AM → CE via Timeline.am_to_ce
      # (the −5509/−5508 September-style envelope; the March-year ambiguity is
      # documented there — precision "am" marks every row as era-converted).
      #
      # Each annal div becomes one passage-grain row: passage_seq_from/to are
      # the min/max catalog sequence of the div's sentences (sentence id →
      # passage urn "<doc-urn>:<sid>", the ProielParser mint — empty-text
      # sentences never reached the catalog and simply don't anchor). One
      # document-grain ENVELOPE row (min..max across the annals, passage_seq
      # NULL) is inserted first, so document-grain consumers (`vocab
      # --by-century`, `show`) see the chronicle once, honestly wide.
      module ChronicleAnnals
        TOROT_SLUG = "torot"
        URN_PREFIX = "urn:nabu:proiel:" # TOROT reuses the PROIEL urn scheme

        # "6360", "6360: title", "6369–6370: title", "6694 part 1".
        AM_TITLE = /\A\s*(\d{4})(?:\s*[–—-]\s*(\d{4}))?/
        # Plausibility gate: AM 5500–7300 = ca. 9 BCE – 1792 CE, generously
        # bracketing the chronicles (attested 6360–6780) while excluding
        # every other numeric div title on disk (folio/section numbers ≤ 3
        # digits, CE years like "1229" in prose titles).
        AM_PLAUSIBLE = (5500..7300)

        module_function

        # Walk canonical/torot/*.xml; for every source with annal divs that we
        # hold in the catalog, insert the envelope + annal rows. Returns
        # { documents:, annals:, skipped_divs: } — +skipped_divs+ counts
        # non-annal divs inside annalistic sources (honest residue, never
        # guessed into a year).
        def build(catalog:, canonical_dir:)
          dir = File.join(canonical_dir, TOROT_SLUG)
          return { documents: 0, annals: 0, skipped_divs: 0 } unless Dir.exist?(dir)

          documents = 0
          annals = 0
          skipped = 0
          Dir.glob(File.join(dir, "*.xml")).each do |path|
            outcome = build_source(catalog, path)
            next if outcome.nil?

            documents += 1
            annals += outcome[:annals]
            skipped += outcome[:skipped]
          end
          { documents: documents, annals: annals, skipped_divs: skipped }
        end

        # One TOROT source file → its timeline rows, or nil when it is not an
        # annalistic chronicle (no AM-titled divs) or not in the catalog.
        def build_source(catalog, path)
          divs = scan_divs(path)
          annal_divs = divs.filter_map do |title, sentence_ids|
            am = parse_am_title(title)
            [am, sentence_ids] if am
          end
          return nil if annal_divs.empty?

          urn = "#{URN_PREFIX}#{File.basename(path, '.xml')}"
          document_id = catalog[:documents].where(urn: urn).get(:id)
          return nil if document_id.nil?

          insert_rows(catalog, document_id, urn, annal_divs, skipped: divs.size - annal_divs.size)
        end

        def insert_rows(catalog, document_id, urn, annal_divs, skipped:)
          sequences = catalog[:passages].where(document_id: document_id).select_hash(:urn, :sequence)
          rows = annal_divs.filter_map do |am, sentence_ids|
            seqs = sentence_ids.filter_map { |sid| sequences["#{urn}:#{sid}"] }
            next if seqs.empty? # an annal none of whose sentences survived to the catalog

            am.merge(passage_seq_from: seqs.min, passage_seq_to: seqs.max)
          end
          return nil if rows.empty?

          insert_envelope(catalog, document_id, rows)
          rows.each do |row|
            catalog[:document_axes].insert(row.merge(document_id: document_id, axis_source: TOROT_SLUG))
          end
          { annals: rows.size, skipped: skipped }
        end

        # The document-grain row: the chronicle's full annal span, inserted
        # BEFORE the annal rows so document-grain readers meet it first.
        def insert_envelope(catalog, document_id, rows)
          catalog[:document_axes].insert(
            document_id: document_id,
            not_before: rows.map { |row| row[:not_before] }.min,
            not_after: rows.map { |row| row[:not_after] }.max,
            precision: "am", date_raw: "#{rows.first[:date_raw]} – #{rows.last[:date_raw]}",
            axis_source: TOROT_SLUG
          )
        end

        # An AM-titled div → the date fields, else nil. Both the shape and the
        # plausibility range must hold; a range must not descend.
        def parse_am_title(title)
          m = AM_TITLE.match(title.to_s) or return nil

          am_lo = m[1].to_i
          am_hi = (m[2] || m[1]).to_i
          return nil unless AM_PLAUSIBLE.cover?(am_lo) && AM_PLAUSIBLE.cover?(am_hi) && am_lo <= am_hi

          not_before, not_after = Timeline.am_to_ce(am_lo, am_hi)
          raw = am_hi == am_lo ? "AM #{am_lo}" : "AM #{am_lo}–#{am_hi}"
          { not_before: not_before, not_after: not_after, precision: "am", date_raw: raw }
        end

        # Stream one PROIEL file, returning [[div title, [sentence ids]], …].
        # Only <div>, its first <title>, and <sentence id> are touched — the
        # 12 MB token payload streams past (same Reader discipline as
        # ProielParser; a DOM here would be the CLAUDE.md anti-pattern).
        def scan_divs(path)
          divs = []
          current = nil
          File.open(path, "r") do |io|
            Nokogiri::XML::Reader(io, path).each do |node|
              current = process_node(node, divs, current)
            end
          end
          divs
        rescue Nokogiri::XML::SyntaxError
          [] # a malformed source is the loader's problem to report, not the timeline pass's
        end

        def process_node(node, divs, current)
          if node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            case node.name
            when "div" then current = { title: nil, sentence_ids: [] }
            when "title" then current[:title] ||= node.inner_xml if current
            when "sentence" then current[:sentence_ids] << node.attribute("id") if current
            end
          elsif node.node_type == Nokogiri::XML::Reader::TYPE_END_ELEMENT && node.name == "div" && current
            divs << [current[:title].to_s, current[:sentence_ids]]
            current = nil
          end
          current
        end
      end
    end
  end
end
