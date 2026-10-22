# frozen_string_literal: true

require "csv"
require "json"

require_relative "../normalize"
require_relative "../sign_list"

module Nabu
  module Store
    # The OSL sign concordances (migration 051): the concordance assets
    # riding in the held Oracc Sign List repo's 00etc — CC0 with the repo,
    # landed by `nabu sync osl`, never parsed before — joined onto the OSL
    # sign ids (@oid) and precompiled into sign_concordances, so the
    # cuneiform sign card reads ONE indexed lookup (the desk-commands law).
    #
    # == The assets (census against canonical/osl/00etc, 2026-10-22)
    #
    #   wikidata-script.csv      1,927 rows  Wikidata item (Characterqid) →
    #                                        23 printed-list columns (ABZ,
    #                                        AKS, ATU1, Labat, MesZL, KWU,
    #                                        LAK, ZATU, …); joins via the
    #                                        repo's own wikidata/Q-to-oid.tab
    #                                        (1,101 Q → oid rows), else the
    #                                        "(U+xxxxx)" codepoint in the
    #                                        Character label, else @uname
    #   wikidata.tsv             1,216 rows  Q → codepoint; same join lanes
    #   wikidata/oid-aks-lref-name.tsv 351   oid → AKS number (o0000000 =
    #                                        upstream's vacat/listref rows)
    #   aks-add.tsv                351 rows  AKS number → sign name
    #   mzl-kwu.tsv                960 rows  MZL ↔ KWU (bare "KWU" = KWU
    #                                        unnumbered) → sign name; '#'
    #                                        lines are upstream comments
    #   pgsl.tab                   361 rows  PGSL number → sign name; '='
    #                                        lines are section separators
    #   ebl-sign-names.json      2,490 names the eBL sign inventory (the
    #                                        same names as ebl-signs.lst)
    #   attinger.tab / add-attinger.tab      OSL value → Attinger spelling
    #                              194 / 30  (attinger.tab already appends
    #                                        add-attinger — duplicates fold)
    #   csf.tab                  1,680 rows  long → common short form, both
    #                                        values of one sign
    #   eng.tab                    260 rows  ŋ-value → its ŋ-less twin
    #
    # The wikidata/*.lst and m-*.lst files are per-column splits of the
    # same Script table as wikidata-script.csv (splitcol.sh), aks.Q /
    # aks-oid.tsv restate the AKS table by Q-id, ebl-signs.lst restates the
    # JSON — derivatives, not parsed. Everything else in 00etc (fonts, PUA
    # tables, image maps, sxw/ofs XML, signlists/) is not concordance data
    # for this table.
    #
    # == The join (every row joins or is censused with a reason)
    #
    # Name-keyed rows resolve through SignList#sign (name, then @aka, then
    # variant-form name — the lane is recorded in +via+). Value maps
    # resolve the left value through SignList#lookup; for the same-sign
    # maps (csf, eng) a right value that also resolves must share the sign
    # (else "split-signs"); a value on several signs is "ambiguous" — no
    # sign-level join, never a guess. A Q-to-oid row is upstream's own assertion: its oids win, and
    # when none is held the row is "oid-not-held" (no codepoint fallback
    # second-guessing it). Duplicate facts (the same oid/scheme/key/value
    # from two assets) keep the first asset and are counted.
    #
    # Derivable by construction: f(canonical/osl) — drop-and-reproject;
    # wired into both rebuild flavors, builders:refresh and the osl
    # post-sync refresh. A tree without the osl cone yields the honest
    # empty table, never an error.
    module SignConcordances
      TABLE = :sign_concordances
      SOURCE_SLUG = "osl"
      ETC = "00etc"

      # The asset roster in processing order (first asset wins a duplicate
      # fact): the oid-keyed Wikidata lists first, then the name-keyed
      # tables, then the value maps.
      ASSETS = %w[
        wikidata-script.csv wikidata.tsv wikidata/oid-aks-lref-name.tsv aks-add.tsv
        mzl-kwu.tsv pgsl.tab ebl-sign-names.json
        attinger.tab add-attinger.tab csf.tab eng.tab
      ].freeze
      Q_TO_OID = "wikidata/Q-to-oid.tab"
      VALUE_MAPS = {
        "attinger.tab" => "attinger", "add-attinger.tab" => "attinger",
        "csf.tab" => "csf", "eng.tab" => "eng"
      }.freeze
      SAME_SIGN_MAPS = %w[csf eng].freeze
      VACAT_OID = "o0000000"
      CODEPOINT = /\(U\+(\h{4,6})\)/
      LABEL_TAIL = /\s*\([^()]*\)\s*\z/
      # The Wikidata columns that are not printed-list concordances.
      NON_LIST_COLUMNS = ["Characterqid", "Character", "Char image"].freeze

      Row = Data.define(:oid, :scheme, :key, :value, :asset, :via)
      # Per asset: data rows read, rows that joined, skip reasons → count,
      # table rows written, and duplicate facts folded into earlier rows.
      AssetCensus = Data.define(:asset, :rows, :joined, :skipped, :emitted, :duplicates)
      Summary = Data.define(:rows, :assets)

      # The pure per-asset readers (the parse half, tested per asset).
      module Parse
        WikidataRow = Data.define(:qid, :character, :lists)

        module_function

        # Header-keyed; cells are stripped of (nb)space padding and empty
        # cells dropped, so +lists+ carries only real concordance numbers.
        def wikidata_script(path)
          CSV.read(path, headers: true, encoding: "UTF-8").map do |record|
            cells = record.to_h.to_h { |head, cell| [clean(head), clean(cell)] }
            lists = cells.reject { |head, cell| NON_LIST_COLUMNS.include?(head) || cell.empty? }
            WikidataRow.new(qid: cells["Characterqid"], character: cells["Character"], lists: lists)
          end
        end

        # Q → [oid, …] (the repo's own space-separated multi-oid cells).
        def q_to_oid(path)
          columns(path).to_h { |qid, oids| [qid, oids.to_s.split] }
        end

        # Tab-separated rows, each field stripped, NFC at the boundary;
        # trailing empty fields kept as "" up to the row's own width.
        def columns(path)
          File.readlines(path, chomp: true, encoding: "UTF-8").map do |line|
            Nabu::Normalize.nfc(line).split("\t", -1).map(&:strip)
          end
        end

        def ebl_names(path)
          JSON.parse(File.read(path, encoding: "UTF-8")).map { |entry| Nabu::Normalize.nfc(entry.fetch("_id")) }
        end

        def clean(text)
          Nabu::Normalize.nfc(text.to_s).gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
        end
      end

      module_function

      def rebuild!(catalog:, canonical_dir:, sign_list: nil)
        catalog[TABLE].delete if catalog.table_exists?(TABLE)
        root = canonical_dir && File.join(canonical_dir, SOURCE_SLUG)
        asl = root && File.join(root, Nabu::SignList::ASL_FILE)
        return Summary.new(rows: 0, assets: []) unless asl && File.file?(asl)

        list = sign_list || Nabu::SignList.load(asl)
        joiner = Joiner.new(list, q_to_oid: q_to_oid(root))
        assets = ASSETS.filter_map do |asset|
          path = File.join(root, ETC, asset)
          joiner.run(asset, path) if File.file?(path)
        end
        joiner.rows.each_slice(2_000) { |slice| catalog[TABLE].multi_insert(slice.map(&:to_h)) }
        Summary.new(rows: joiner.rows.size, assets: assets)
      end

      def q_to_oid(root)
        path = File.join(root, ETC, Q_TO_OID)
        File.file?(path) ? Parse.q_to_oid(path) : {}
      end

      # Sign name → [record, lane] through SignList#sign's own order (name,
      # @aka, variant-form name); nil when the OSL holds no such sign.
      def name_join(list, name)
        record = list.sign(name) or return nil
        via = if record.parent_name then "form"
              elsif record.name == name then "name"
              else "aka"
              end
        [record, via]
      end

      # The join + census engine: one instance per rebuild.
      class Joiner
        attr_reader :rows

        def initialize(list, q_to_oid:)
          @list = list
          @q_to_oid = q_to_oid
          @rows = []
          @seen = Set.new
          @by_oid = {}
          @by_uname = {}
          list.signs.each do |sign|
            [sign, *sign.forms].each do |record|
              @by_oid[record.oid] ||= record if record.oid
              @by_uname[record.uname] ||= record if record.uname
            end
          end
        end

        def run(asset, path)
          census = { rows: 0, joined: 0, skipped: Hash.new(0), emitted: 0, duplicates: 0 }
          outcomes(asset, path).each do |outcome|
            census[:rows] += 1
            if outcome.is_a?(String)
              census[:skipped][outcome] += 1
            else
              census[:joined] += 1
              outcome.each { |row| emit(row, census) }
            end
          end
          AssetCensus.new(asset: asset, rows: census[:rows], joined: census[:joined],
                          skipped: census[:skipped].sort.to_h, emitted: census[:emitted],
                          duplicates: census[:duplicates])
        end

        private

        def emit(row, census)
          if @seen.add?([row.oid, row.scheme, row.key, row.value])
            @rows << row
            census[:emitted] += 1
          else
            census[:duplicates] += 1
          end
        end

        # One outcome per source row: a skip-reason String, or the Rows
        # it contributes (an Array, possibly sharing facts already held).
        def outcomes(asset, path)
          case asset
          when "wikidata-script.csv" then wikidata_script(asset, path)
          when "wikidata.tsv" then wikidata_codepoints(asset, path)
          when "wikidata/oid-aks-lref-name.tsv" then aks_by_oid(asset, path)
          when "aks-add.tsv" then aks_by_name(asset, path)
          when "mzl-kwu.tsv" then mzl_kwu(asset, path)
          when "pgsl.tab" then pgsl(asset, path)
          when "ebl-sign-names.json" then ebl(asset, path)
          else value_map(asset, path, VALUE_MAPS.fetch(asset))
          end
        end

        def wikidata_script(asset, path)
          Parse.wikidata_script(path).map do |entry|
            targets = q_targets(entry.qid, glyph_of(entry.character), uname_of(entry.character))
            next targets if targets.is_a?(String)

            records, via = targets
            records.flat_map do |record|
              facts = entry.lists.map { |list, number| [list, nil, number] } + [["Wikidata", nil, entry.qid]]
              facts.map { |scheme, key, value| row(record, scheme, key, value, asset, via) }
            end
          end
        end

        def wikidata_codepoints(asset, path)
          Parse.columns(path).map do |qid, codepoint|
            glyph = codepoint.to_s[/\AU\+(\h+)\z/, 1]&.to_i(16)&.chr(Encoding::UTF_8)
            targets = q_targets(qid, glyph, nil)
            next targets if targets.is_a?(String)

            records, via = targets
            records.map { |record| row(record, "Wikidata", nil, qid, asset, via) }
          end
        end

        # Upstream's Q-to-oid row wins; only an unmapped item falls back to
        # its codepoint, then its Unicode name.
        def q_targets(qid, glyph, uname)
          if (oids = @q_to_oid[qid])
            held = oids.filter_map { |oid| @by_oid[oid] }
            return held.empty? ? "oid-not-held" : [held, "qid-oid"]
          end
          if glyph && (record = @list.sign_for_glyph(glyph)&.then { |hit| hit if hit.oid })
            return [[record], "codepoint"]
          end
          return [[@by_uname[uname]], "uname"] if uname && @by_uname[uname]

          "no-join"
        end

        def glyph_of(character)
          character.to_s[CODEPOINT, 1]&.to_i(16)&.chr(Encoding::UTF_8)
        end

        # "𒋀  CUNEIFORM SIGN SHESH (U+122C0)" → "CUNEIFORM SIGN SHESH".
        def uname_of(character)
          character.to_s.sub(LABEL_TAIL, "").sub(/\A[^A-Z]+/, "")
        end

        def aks_by_oid(asset, path)
          Parse.columns(path).map do |oid, number, *_rest|
            next "vacat" if oid == VACAT_OID

            record = @by_oid[oid] or next "oid-not-held"
            [row(record, "AKS", nil, number, asset, "oid")]
          end
        end

        def aks_by_name(asset, path)
          Parse.columns(path).map do |number, name|
            named(name) { |record, via| [row(record, "AKS", nil, number, asset, via)] }
          end
        end

        # "MZL535  KWU029,KWU032  ŠEŠ"; a bare "KWU" = KWU leaves the sign
        # unnumbered (value NULL); an empty MZL side keeps key NULL.
        def mzl_kwu(asset, path)
          Parse.columns(path).map do |fields|
            next "comment" if fields.first.to_s.start_with?("#")

            mzl, kwu, name = fields
            named(name) do |record, via|
              kwu_numbers = kwu.to_s.split(",").map { |token| token.strip.delete_prefix("KWU") }.reject(&:empty?)
              [row(record, "MZL-KWU", presence(mzl.to_s.delete_prefix("MZL")),
                   presence(kwu_numbers.join(",")), asset, via)]
            end
          end
        end

        def pgsl(asset, path)
          Parse.columns(path).map do |fields|
            next "separator" if fields == ["="]
            next "comment" if fields.first.to_s.start_with?("#")

            number, name = fields
            named(name) { |record, via| [row(record, "PGSL", nil, number.delete_prefix("PGSL"), asset, via)] }
          end
        end

        def ebl(asset, path)
          Parse.ebl_names(path).map do |name|
            named(name) { |record, via| [row(record, "eBL", nil, name, asset, via)] }
          end
        end

        def value_map(asset, path, scheme)
          Parse.columns(path).map do |from, to|
            from_records = @list.lookup(from.to_s).select(&:oid)
            next "value-not-held" if from_records.empty?

            picked = pick_value_sign(scheme, from_records, @list.lookup(to.to_s).select(&:oid))
            next "split-signs" if picked.empty?
            next "ambiguous" if picked.size > 1

            [row(picked.first, scheme, from, to, asset, "value")]
          end
        end

        # csf/eng pairs are minted INSIDE one sign (csf.plx/eng.plx walk a
        # sign's @v set), so both sides must share it — a pair whose sides
        # now sit on different signs is "split-signs". An Attinger spelling
        # is a foreign convention that may coincide with another sign's OSL
        # value (attinger.plx keys on the left @v alone): the left side
        # decides, the right only narrows an ambiguous left.
        def pick_value_sign(scheme, from_records, to_records)
          return from_records if to_records.empty?

          shared = from_records & to_records
          return shared if SAME_SIGN_MAPS.include?(scheme)

          from_records.size > 1 && shared.any? ? shared : from_records
        end

        # A name-keyed row: "no-sign-name" for an empty (or comment-only)
        # name cell, "name-not-held" when the OSL holds no such sign.
        def named(name)
          return "no-sign-name" if name.to_s.empty? || name.start_with?("#")

          joined = SignConcordances.name_join(@list, name) or return "name-not-held"
          # Every held OSL record carries an @oid (census 2026-10-22); a
          # future oid-less one is censused, never a NULL-keyed row.
          return "sign-without-oid" unless joined.first.oid

          yield(*joined)
        end

        def row(record, scheme, key, value, asset, via)
          Row.new(oid: record.oid, scheme: scheme, key: key, value: value, asset: asset, via: via)
        end

        def presence(text) = text.to_s.empty? ? nil : text
      end
    end
  end
end
