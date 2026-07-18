# frozen_string_literal: true

require "nokogiri"

require_relative "../date_axis"
require_relative "../normalize"

module Nabu
  module Store
    # Populates the catalog's document_axes table from canonical (P15-2, design
    # doc §3). A post-load pass — like the Indexer, but writing the CATALOG
    # rather than the fulltext index — so `nabu rebuild` regenerates the axis
    # after replaying the sources (wired into Rebuild#run). axes = f(canonical):
    # HGV reads the HGV_meta_EpiDoc XML and joins ddb-hybrid→urn→document_id;
    # goo300k/IMP read the CE year off the urn suffix (urn = f(canonical)); the
    # P16-3 part-2 extractors live in axis_builder/: OraccDates (catalogue.json
    # period/regnal/absolute dates + provenience) and ChronicleAnnals (TOROT
    # anno-mundi annal divs, the first passage-grain rows). The Indexer is
    # unchanged and never re-parses canonical.
    #
    # == The date model lives in Nabu::DateAxis (fable-reviewed)
    #
    # This builder only EXTRACTS and joins; every year decision (base-10 parse,
    # year-0 rejection, no astronomical shift) is DateAxis's. The five reviewed
    # input fixes it must honour: open-ended intervals (notBefore-only /
    # notAfter-only → one NULL bound), multiple alternative origDates (ENVELOPE:
    # min of all lowers, max of all uppers), no octal year parse, no year 0
    # (a year-0 file is skipped, counted, never stored — robust bulk build over
    # a strict model), and honest ranges (never a midpoint).
    module AxisBuilder
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
      # resisted the honest parse ladder — the Annals of Ulster shape) and
      # riig_undated/riig_invalid (P25-1). The later-phase fields default so
      # every prior construction stays valid.
      Summary = Data.define(:hgv, :goo300k, :imp, :oracc, :torot, :coptic, :edh, :damaskini,
                            :corph, :riig, :tla_hf,
                            :hgv_files, :hgv_invalid, :oracc_undated, :torot_annals,
                            :coptic_invalid, :edh_undated, :edh_invalid, :corph_undated,
                            :riig_undated, :riig_invalid, :tla_hf_undated) do
        def initialize(coptic: 0, coptic_invalid: 0, edh: 0, edh_undated: 0, edh_invalid: 0,
                       damaskini: 0, corph: 0, corph_undated: 0,
                       riig: 0, riig_undated: 0, riig_invalid: 0,
                       tla_hf: 0, tla_hf_undated: 0, **)
          super
        end

        def total
          hgv + goo300k + imp + oracc + torot + coptic + edh + damaskini + corph + riig + tla_hf
        end
      end

      module_function

      # Drop every axis row and rebuild from canonical. Full-rebuild semantics
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
        Summary.new(hgv: hgv[:rows], goo300k: goo, imp: imp,
                    oracc: oracc[:documents], torot: torot[:documents],
                    coptic: coptic[:documents], edh: edh[:documents],
                    damaskini: damaskini[:documents], corph: corph[:documents],
                    riig: riig[:documents], tla_hf: tla_hf[:documents],
                    hgv_files: hgv[:files], hgv_invalid: hgv[:invalid],
                    oracc_undated: oracc[:undated], torot_annals: torot[:annals],
                    coptic_invalid: coptic[:invalid],
                    edh_undated: edh[:undated], edh_invalid: edh[:invalid],
                    corph_undated: corph[:undated],
                    riig_undated: riig[:undated], riig_invalid: riig[:invalid],
                    tla_hf_undated: tla_hf[:undated])
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
          axis =
            begin
              extract_hgv(File.read(path))
            rescue DateAxis::InvalidYear
              invalid += 1 # a year-0 (or otherwise invalid) file: skipped, counted, never stored
              next
            end
          next if axis.nil?

          doc_id = ddbdp[axis[:urn]] or next # HGV record for a DDbDP doc we don't hold
          insert_axis(catalog, doc_id, axis, "hgv")
          rows += 1
        end
        { rows: rows, files: files, invalid: invalid }
      end

      # Extract the axis fields from one HGV EpiDoc file, or nil when it carries
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
          when_y = DateAxis.parse_year(node["when"])
          nb = DateAxis.parse_year(node["notBefore"])
          na = DateAxis.parse_year(node["notAfter"])
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

      def insert_axis(catalog, document_id, axis, source)
        catalog[:document_axes].insert(
          document_id: document_id,
          not_before: axis[:not_before], not_after: axis[:not_after],
          precision: axis[:precision], date_raw: axis[:date_raw],
          place_name: axis[:place_name], place_ref: axis[:place_ref],
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

require_relative "axis_builder/oracc_dates"
require_relative "axis_builder/chronicle_annals"
require_relative "axis_builder/coptic_scriptorium_dates"
require_relative "axis_builder/edh_dates"
require_relative "axis_builder/damaskini_dates"
require_relative "axis_builder/corph_dates"
require_relative "axis_builder/riig_dates"
require_relative "axis_builder/tla_hf_dates"
