# frozen_string_literal: true

require "nokogiri"

require_relative "../timeline"
require_relative "../normalize"

module Nabu
  module Store
    # Populates the catalog's document_axes table from canonical (P15-2, design
    # doc §3). A post-load pass — like the Indexer, but writing the CATALOG
    # rather than the fulltext index — so `nabu rebuild` regenerates the timeline
    # after replaying the sources (wired into Rebuild#run). axes = f(canonical):
    # HGV reads the HGV_meta_EpiDoc XML and joins ddb-hybrid→urn→document_id;
    # goo300k/IMP read the CE year off the urn suffix (urn = f(canonical)); the
    # P16-3 part-2 extractors live in timeline_builder/: OraccDates (catalogue.json
    # period/regnal/absolute dates + provenience) and ChronicleAnnals (TOROT
    # anno-mundi annal divs, the first passage-grain rows). The Indexer is
    # unchanged and never re-parses canonical.
    #
    # == The date model lives in Nabu::Timeline (fable-reviewed)
    #
    # This builder only EXTRACTS and joins; every year decision (base-10 parse,
    # year-0 rejection, no astronomical shift) is Timeline's. The five reviewed
    # input fixes it must honour: open-ended intervals (notBefore-only /
    # notAfter-only → one NULL bound), multiple alternative origDates (ENVELOPE:
    # min of all lowers, max of all uppers), no octal year parse, no year 0
    # (a year-0 file is skipped, counted, never stored — robust bulk build over
    # a strict model), and honest ranges (never a midpoint).
    module TimelineBuilder
      HGV_SLUG = "papyri-ddbdp"
      HGV_SUBDIR = "HGV_meta_EpiDoc"
      DDBDP_PREFIX = "urn:nabu:ddbdp:"

      # One source's document-grain year suffix (goo300k/IMP share the family):
      # urn "…:sigil-1584" → 1584 CE.
      URN_YEAR = /-(\d{3,4})\z/

      # Per-source dated/placed DOCUMENT counts (+total+ sums them), plus the
      # honest residues: hgv_files/hgv_invalid (P15-2), oracc_undated (members
      # whose date didn't resolve — skipped, counted, never guessed),
      # torot_annals (the passage-grain annal rows behind the torot documents)
      # and coptic_invalid (P17-1 — year-0/unparseable TT headers, skipped)
      # and edh_undated/edh_invalid (P17-2: undated-but-joined records and the
      # year-0 tripwire), corph_undated (P25-0: held texts whose Date prose
      # resisted the honest parse ladder — the Annals of Ulster shape),
      # riig_undated/riig_invalid (P25-1) and aes_undated (P28-0: held texts
      # whose date AND findspot are both the corpus's unknown/"k" values),
      # ceipom_undated/ceipom_unplaced/ceipom_invalid (P29-1: the 3
      # undated texts, the 10 degenerate-Provenance texts, and the one
      # inverted-range typo — skipped, counted, never stored),
      # and lexlep/tir undated+invalid (P29-3: inscriptions whose Object
      # page is uncached or carries the wiki's sortdate=0 unknown filler)
      # and iip_undated/iip_invalid (P30-6: dateless-but-placed records —
      # period="Unknown" headers — and the year-0 tripwire),
      # and cdli_undated/cdli_invalid (P31-2: catalog rows whose period
      # string carries no year envelope — "uncertain", "fake (modern)" —
      # and the ascending-range/year-0 tripwire),
      # and rundata_undated (P40-6: inscriptions with neither a year bound
      # nor a find-spot — skipped, counted, never guessed).
      # The later-phase fields default so every prior construction stays
      # valid.
      Summary = Data.define(:hgv, :goo300k, :imp, :oracc, :torot, :coptic, :edh, :damaskini,
                            :corph, :riig, :tla_hf, :aes, :ceipom, :isicily, :open_etruscan,
                            :lexlep, :tir, :iip, :cdli, :rundata,
                            :hgv_files, :hgv_invalid, :oracc_undated, :torot_annals,
                            :coptic_invalid, :edh_undated, :edh_invalid, :corph_undated,
                            :riig_undated, :riig_invalid, :tla_hf_undated, :aes_undated,
                            :ceipom_undated, :ceipom_unplaced, :ceipom_invalid,
                            :isicily_undated, :isicily_invalid,
                            :open_etruscan_undated, :open_etruscan_invalid,
                            :lexlep_undated, :lexlep_invalid, :tir_undated, :tir_invalid,
                            :iip_undated, :iip_invalid, :cdli_undated, :cdli_invalid,
                            :rundata_undated) do
        def initialize(coptic: 0, coptic_invalid: 0, edh: 0, edh_undated: 0, edh_invalid: 0,
                       damaskini: 0, corph: 0, corph_undated: 0,
                       riig: 0, riig_undated: 0, riig_invalid: 0,
                       tla_hf: 0, tla_hf_undated: 0, aes: 0, aes_undated: 0,
                       ceipom: 0, ceipom_undated: 0, ceipom_unplaced: 0, ceipom_invalid: 0,
                       isicily: 0, isicily_undated: 0, isicily_invalid: 0,
                       open_etruscan: 0, open_etruscan_undated: 0, open_etruscan_invalid: 0,
                       lexlep: 0, lexlep_undated: 0, lexlep_invalid: 0,
                       tir: 0, tir_undated: 0, tir_invalid: 0,
                       iip: 0, iip_undated: 0, iip_invalid: 0,
                       cdli: 0, cdli_undated: 0, cdli_invalid: 0,
                       rundata: 0, rundata_undated: 0, **)
          super
        end

        def total
          hgv + goo300k + imp + oracc + torot + coptic + edh + damaskini + corph + riig +
            tla_hf + aes + ceipom + isicily + open_etruscan + lexlep + tir + iip + cdli +
            rundata
        end
      end

      module_function

      # Drop every timeline row and rebuild from canonical. Full-rebuild semantics
      # (the table is small — ≤ ~100k rows), matching the drop-and-rebuild
      # lifecycle of the derived indexes. Returns a Summary.
      def rebuild!(catalog:, canonical_dir:)
        catalog[:document_axes].delete
        hgv = build_hgv(catalog, canonical_dir)
        goo = build_year_from_urn(catalog, "urn:nabu:goo300k:", "goo300k")
        imp = build_year_from_urn(catalog, "urn:nabu:imp:", "imp")
        oracc = OraccDates.build(catalog: catalog, canonical_dir: canonical_dir)
        torot = ChronicleAnnals.build(catalog: catalog, canonical_dir: canonical_dir)
        coptic = CopticScriptoriumDates.build(catalog: catalog, canonical_dir: canonical_dir)
        edh = EdhDates.build(catalog: catalog, canonical_dir: canonical_dir)
        damaskini = DamaskiniDates.build(catalog: catalog, canonical_dir: canonical_dir)
        corph = CorphDates.build(catalog: catalog, canonical_dir: canonical_dir)
        riig = RiigDates.build(catalog: catalog, canonical_dir: canonical_dir)
        tla_hf = TlaHfDates.build(catalog: catalog, canonical_dir: canonical_dir)
        aes = AesDates.build(catalog: catalog, canonical_dir: canonical_dir)
        ceipom = CeipomDates.build(catalog: catalog, canonical_dir: canonical_dir)
        isicily = IsicilyDates.build(catalog: catalog, canonical_dir: canonical_dir)
        open_etruscan = OpenEtruscanDates.build(catalog: catalog, canonical_dir: canonical_dir)
        vienna = ViennaWikiDates.build(catalog: catalog, canonical_dir: canonical_dir)
        iip = IipDates.build(catalog: catalog, canonical_dir: canonical_dir)
        cdli = CdliDates.build(catalog: catalog, canonical_dir: canonical_dir)
        rundata = RundataDates.build(catalog: catalog, canonical_dir: canonical_dir)
        Summary.new(hgv: hgv[:rows], goo300k: goo, imp: imp,
                    oracc: oracc[:documents], torot: torot[:documents],
                    coptic: coptic[:documents], edh: edh[:documents],
                    damaskini: damaskini[:documents], corph: corph[:documents],
                    riig: riig[:documents], tla_hf: tla_hf[:documents], aes: aes[:documents],
                    ceipom: ceipom[:documents], isicily: isicily[:documents],
                    open_etruscan: open_etruscan[:documents],
                    lexlep: vienna[:lexlep][:documents], tir: vienna[:tir][:documents],
                    hgv_files: hgv[:files], hgv_invalid: hgv[:invalid],
                    oracc_undated: oracc[:undated], torot_annals: torot[:annals],
                    coptic_invalid: coptic[:invalid],
                    edh_undated: edh[:undated], edh_invalid: edh[:invalid],
                    corph_undated: corph[:undated],
                    riig_undated: riig[:undated], riig_invalid: riig[:invalid],
                    tla_hf_undated: tla_hf[:undated], aes_undated: aes[:undated],
                    ceipom_undated: ceipom[:undated], ceipom_unplaced: ceipom[:unplaced],
                    ceipom_invalid: ceipom[:invalid],
                    isicily_undated: isicily[:undated], isicily_invalid: isicily[:invalid],
                    open_etruscan_undated: open_etruscan[:undated],
                    open_etruscan_invalid: open_etruscan[:invalid],
                    lexlep_undated: vienna[:lexlep][:undated], lexlep_invalid: vienna[:lexlep][:invalid],
                    tir_undated: vienna[:tir][:undated], tir_invalid: vienna[:tir][:invalid],
                    iip: iip[:documents], iip_undated: iip[:undated], iip_invalid: iip[:invalid],
                    cdli: cdli[:documents], cdli_undated: cdli[:undated],
                    cdli_invalid: cdli[:invalid],
                    rundata: rundata[:documents], rundata_undated: rundata[:undated])
      end

      # -- HGV (papyri) --------------------------------------------------------

      def build_hgv(catalog, canonical_dir)
        hgv_dir = File.join(canonical_dir, HGV_SLUG, HGV_SUBDIR)
        return { rows: 0, files: 0, invalid: 0 } unless Dir.exist?(hgv_dir)

        # One urn→id map for the whole DDbDP shelf (the ddb-hybrid↔urn join,
        # design §3 — verified), so each HGV file is a hash hit, not a query.
        ddbdp = catalog[:documents].where(Sequel.like(:urn, "#{DDBDP_PREFIX}%")).select_hash(:urn, :id)
        rows = 0
        files = 0
        invalid = 0
        Dir.glob(File.join(hgv_dir, "**", "*.xml")).each do |path|
          files += 1
          timeline =
            begin
              extract_hgv(File.read(path))
            rescue Timeline::InvalidYear
              invalid += 1 # a year-0 (or otherwise invalid) file: skipped, counted, never stored
              next
            end
          next if timeline.nil?

          doc_id = ddbdp[timeline[:urn]] or next # HGV record for a DDbDP doc we don't hold
          insert_timeline(catalog, doc_id, timeline, "hgv")
          rows += 1
        end
        { rows: rows, files: files, invalid: invalid }
      end

      # Extract the timeline fields from one HGV EpiDoc file, or nil when it carries
      # neither a date nor a place. Namespaces stripped (tiny files); the
      # ENVELOPE across every origDate (alternatives included) is the fable-
      # reviewed policy for multi-date records.
      def extract_hgv(xml)
        doc = Nokogiri::XML(xml)
        doc.remove_namespaces!
        hybrid = doc.at_xpath("//idno[@type='ddb-hybrid']")&.text&.strip
        return nil if hybrid.nil? || hybrid.empty?

        dates = doc.xpath("//origDate")
        bounds = envelope(dates)
        place_name, place_ref = extract_place(doc)
        return nil if bounds[:not_before].nil? && bounds[:not_after].nil? && place_name.nil?

        {
          urn: "#{DDBDP_PREFIX}#{hybrid.tr(';', ':')}",
          not_before: bounds[:not_before], not_after: bounds[:not_after],
          precision: bounds[:precision], date_raw: bounds[:date_raw],
          place_name: place_name, place_ref: place_ref
        }
      end

      # Min of all lower candidates, max of all upper candidates across every
      # origDate: a `when` point contributes to BOTH bounds, a notBefore to the
      # lower only, a notAfter to the upper only. Either side empty → NULL =
      # open-ended (−∞ / +∞). precision = the first explicit HGV attribute, else
      # "range" when any bound came from notBefore/notAfter, else "exact".
      def envelope(dates)
        lowers = []
        uppers = []
        raw = nil
        precision = nil
        ranged = false
        dates.each do |node|
          when_y = Timeline.parse_year(node["when"])
          nb = Timeline.parse_year(node["notBefore"])
          na = Timeline.parse_year(node["notAfter"])
          next if when_y.nil? && nb.nil? && na.nil?

          if when_y
            lowers << when_y
            uppers << when_y
          end
          lowers << nb if nb
          uppers << na if na
          ranged ||= !(nb.nil? && na.nil?)
          precision ||= node["precision"]
          raw ||= normalize(node.text)
        end
        {
          not_before: lowers.min, not_after: uppers.max,
          precision: precision || (ranged ? "range" : "exact"), date_raw: raw
        }
      end

      # origPlace text as the place name; the first provenance placeName carrying
      # a ref (Trismegistos/Pleiades URLs) as the ref string. Both verbatim (no
      # gazetteer — the §1.4 stance), NFC-folded whitespace.
      def extract_place(doc)
        name = normalize(doc.at_xpath("//origPlace")&.text)
        name = normalize(doc.at_xpath("//provenance//placeName")&.text) if name.nil?
        ref = doc.at_xpath("//provenance//placeName[@ref]")&.attr("ref")
        ref = ref.to_s.strip.gsub(/\s+/, " ") unless ref.nil?
        ref = nil if ref && ref.empty?
        [name, ref]
      end

      # -- goo300k / IMP (year in the urn suffix) ------------------------------

      # The Slovene corpora carry only a CE year, in the urn ("…:sigil-1584");
      # urn = f(canonical), so reading it from the catalog is rebuild-safe.
      def build_year_from_urn(catalog, prefix, source)
        rows = 0
        catalog[:documents].where(Sequel.like(:urn, "#{prefix}%")).select_map(%i[id urn]).each do |id, urn|
          m = urn.match(URN_YEAR) or next

          year = m[1].to_i
          next if year.zero?

          catalog[:document_axes].insert(
            document_id: id, not_before: year, not_after: year,
            precision: "year", date_raw: year.to_s, axis_source: source
          )
          rows += 1
        end
        rows
      end

      # -- shared --------------------------------------------------------------

      def insert_timeline(catalog, document_id, timeline, source)
        catalog[:document_axes].insert(
          document_id: document_id,
          not_before: timeline[:not_before], not_after: timeline[:not_after],
          precision: timeline[:precision], date_raw: timeline[:date_raw],
          place_name: timeline[:place_name], place_ref: timeline[:place_ref],
          axis_source: source
        )
      end

      # NFC + collapse the indentation whitespace EpiDoc wraps inside elements,
      # or nil for blank text (conventions §1: NFC internally).
      def normalize(text)
        return nil if text.nil?

        folded = Nabu::Normalize.nfc(text.strip.gsub(/\s+/, " "))
        folded.empty? ? nil : folded
      end
    end
  end
end

require_relative "timeline_builder/oracc_dates"
require_relative "timeline_builder/chronicle_annals"
require_relative "timeline_builder/coptic_scriptorium_dates"
require_relative "timeline_builder/edh_dates"
require_relative "timeline_builder/damaskini_dates"
require_relative "timeline_builder/corph_dates"
require_relative "timeline_builder/riig_dates"
require_relative "timeline_builder/tla_hf_dates"
require_relative "timeline_builder/aes_dates"
require_relative "timeline_builder/ceipom_dates"
require_relative "timeline_builder/isicily_dates"
require_relative "timeline_builder/open_etruscan_dates"
require_relative "timeline_builder/vienna_wiki_dates"
require_relative "timeline_builder/iip_dates"
require_relative "timeline_builder/cdli_dates"
require_relative "timeline_builder/rundata_dates"
