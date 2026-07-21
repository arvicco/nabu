# frozen_string_literal: true

require "zlib"
require_relative "../hani"
require_relative "../adapters/jis0213"

module Nabu
  module Ops
    # P38-4 / P38-r1: generator for lib/nabu/jpn.rb — the Japanese
    # kyūjitai↔shinjitai (old-form ↔ new-form) search fold. TWO lanes,
    # both from HELD data, both read-only:
    #
    #   LANE 1 (jinmeiyō, P38-4): Unihan kJinmeiyoKanji pointers
    #   (canonical/unihan/Unihan_OtherMappings.txt) — Unicode's purpose-built
    #   list of the 2010 jinmeiyō (name-use) kanji. When a jinmeiyō character
    #   is the KYŪJITAI of a jōyō character it carries a pointer to that jōyō
    #   codepoint (`U+OLD kJinmeiyoKanji 2010:U+NEW`). Those lines ARE the
    #   clean 1:1 reform pairs. 173 of them at Unihan 17.0.0.
    #
    #   LANE 2 (kanjidic2-jōyō, P38-r1): KANJIDIC2's `<variant>` cross-
    #   references (canonical/edrdg/kanjidic2/kanjidic2.xml.gz), mined under
    #   the owner's ruled policy — fold only pairs whose TARGET (new form) is
    #   jōyō-listed. This lands the high-frequency reform pairs the jinmeiyō
    #   lane cannot reach (學/学, 體/体, 醫/医, 觀/観), whose old forms are not
    #   name-kanji.
    #
    # == Lane 2, the ruled policy (D38-b, owner 2026-07-21, amended)
    #
    # jōyō signal: a character is jōyō iff BOTH held authorities agree — its
    # KANJIDIC2 <grade> is 1–6 or 8 (grade 9/10 = jinmeiyō) AND it is present
    # in Unihan kJoyoKanji. The INTERSECTION is deliberate: "jōyō-listed" means
    # listed by both, the strictest, most conservative reading of the filter.
    #
    # Candidate old↔new links: KANJIDIC2 <variant var_type="jis208|jis213">
    # men-ku-ten codes, decoded to Unicode through the held JIS X 0213 table
    # (Nabu::Adapters::Jis0213). Links are read in EITHER direction (the XML's
    # pointers are near-reciprocal; the union captures both). A candidate pair
    # is (A non-jōyō, B jōyō): A is the old form, B the new form.
    #
    #   jis212 is REFUSED (verified, not guessed): the <variant var_type="jis212">
    #   codes are JIS X 0212 kuten — a DIFFERENT standard the 0213 table does
    #   not cover. Decoding e.g. 學's jis212 1-33-55 through the 0213 plane-1
    #   table misreads it as 宋 (U+5B8B), a spurious edge. So jis212 variants
    #   are dropped at the decode boundary.
    #
    # Refusals (censused, never silent):
    #   * ONE-TO-MANY ambiguity — an old form variant-linked to 2+ DISTINCT
    #     jōyō forms (碕 → 崎 AND 埼). We never pick arbitrarily; the old is
    #     dropped. (Distinct from a MERGE, which is many olds → ONE new.)
    #   * NFC-identity — a compat ideograph that collapses onto its target
    #     post-NFC (the runtime fold only ever sees NFC text).
    #   * JINMEIYŌ-LANE CONFLICT — a kanjidic edge that would map a codepoint
    #     the jinmeiyō lane already folds to a DIFFERENT canonical. Lane 1 is
    #     authoritative; the conflicting lane-2 edge is dropped.
    #
    # == Merges are ADMITTED (owner ruling 2026-07-21, supersedes the refuse mold)
    #
    # "Admit the merges, match modern reading habits by default — as long as
    # there is an option to look for EXACT match along with it." The famous
    # polygraphic reform merges are FOLDED, not refused: 辨/瓣/辯 → 弁, 罐 → 缶,
    # 缺 → 欠, 藝 → 芸. When a jōyō new form B has 2+ old claimants, they all
    # fold onto B's shared skeleton. A NAMED census of the flagship distinct-
    # word merges (below, MERGE_NOTES) documents the lexical collapse each one
    # makes, so the owner can reverse any single entry trivially. The exact-
    # match escape hatch is `nabu search --exact` (glyph-literal, unfolded).
    #
    # == The composition rule with the hani fold (compose, not fight)
    #
    # lzh/och already fold through Nabu::Hani to a traditional skeleton, and a
    # kyūjitai like 國 IS that skeleton. The fold canonical composes THROUGH
    # hani so Japanese old/new forms land on the SAME index skeleton as Chinese
    # trad/simp — the two folds agree by construction. The canonical depends on
    # the group:
    #
    #   * jinmeiyō-absorbed B (B is already a lane-1 new form): canonical =
    #     the lane-1 canonical. Any extra kanjidic olds fold to the SAME place
    #     — never a reverse edge (that would cycle 気→氣 against 氣→気).
    #   * 1:1 pair (single old A): canonical = Hani.fold(A) — the traditional
    #     skeleton the lzh lane assigns, so 国 aligns with kanripo's 國.
    #   * MERGE (2+ olds): canonical = Hani.fold(B). The olds are distinct
    #     Chinese words (Hani.fold(辨) ≠ Hani.fold(瓣) — the lzh lane keeps them
    #     apart), so they cannot share a traditional; they collapse onto the
    #     shinjitai's skeleton instead. jpn passages apply ONLY this fold, never
    #     the whole Han table.
    #
    # Every value is asserted a fixed point (never itself a key) and every
    # key/value a single codepoint (String#tr-safe, fold_with_map-safe).
    class JpnFoldBuilder
      KJINMEIYO = "kJinmeiyoKanji"
      KJOYO = "kJoyoKanji"
      # KANJIDIC2 <grade>: 1–6 kyōiku, 8 the rest of jōyō; 9/10 jinmeiyō.
      GRADE_JOYO = [1, 2, 3, 4, 5, 6, 8].freeze
      # jis213 men-ku-ten → Jis0213 plane (men 1 → table plane 1, men 2 → 2).
      KUTEN = /\A(\d+)-(\d+)-(\d+)\z/

      # The flagship distinct-word merges — a NAMED, trivially-editable census
      # (owner may reverse any entry). Each comment names the distinct classical
      # words the shinjitai collapses. This list DOCUMENTS what the data-driven
      # merge detection produces; it does not drive it (remove an entry here and
      # the fold is unchanged — edit the policy in +resolve+ to actually refuse).
      MERGE_NOTES = {
        "弁" => "辨 (discriminate) / 瓣 (petal, valve) / 辯 (speech, argue) — three words, one shinjitai",
        "缶" => "罐 (kan: boiler, can) vs the native 缶 (fou: earthenware vessel)",
        "欠" => "缺 (lack, vacancy) vs the native 欠 (ken: to yawn, deficient)",
        "芸" => "藝 (art, craft) vs the classical 芸 (un: rue, a fragrant herb) — jinmeiyō-absorbed",
        "糸" => "絲 (thread) vs the native 糸 (beki: a fine silk unit)",
        "虫" => "蟲 (insects, creatures at large) vs the native 虫 (ki: a small creature)"
      }.freeze

      # The census: provenance + every count the header and conventions §9 report.
      Census = Struct.new(:unihan_version, :unihan_date, :kanjidic_version, :kanjidic_date,
                          :jinmeiyo_pairs, :kanjidic_singles, :merges, :ambiguous_refused,
                          :jinmeiyo_conflicts, :nfc_identity_dropped, :reform_pairs, :fold_entries,
                          keyword_init: true)

      attr_reader :census, :reform_pairs, :fold_table, :merges

      def initialize(mappings_path:, kanjidic_path:, generated_on: Time.now.strftime("%Y-%m-%d"))
        @mappings_path = mappings_path
        @kanjidic_path = kanjidic_path
        @generated_on = generated_on
        @census = Census.new(jinmeiyo_pairs: 0, kanjidic_singles: 0, merges: {}, ambiguous_refused: [],
                             jinmeiyo_conflicts: [], nfc_identity_dropped: 0, reform_pairs: 0, fold_entries: 0)
        parse_unihan
        parse_kanjidic
        resolve
      end

      # The lib/nabu/jpn.rb source text.
      def render
        <<~RUBY
          # frozen_string_literal: true

          # GENERATED FILE — do not edit by hand. Regenerate with:
          #   rake fold:jpn   (reads canonical/unihan/Unihan_OtherMappings.txt +
          #                    canonical/edrdg/kanjidic2/kanjidic2.xml.gz)
          #
          # Nabu::Jpn: the Japanese kyūjitai↔shinjitai (old↔new form) search fold,
          # in TWO lanes (full rule + policy on Nabu::Ops::JpnFoldBuilder, §9):
          #   LANE 1 (jinmeiyō): Unihan kJinmeiyoKanji — the clean 1:1 name-kanji
          #     reform pairs Unicode ships.
          #   LANE 2 (kanjidic2-jōyō): KANJIDIC2 <variant> links whose target is
          #     jōyō (grade 1–6/8 ∩ Unihan kJoyoKanji), landing the reform pairs
          #     whose old form is not a name-kanji (學/学, 體/体, 醫/医, 觀/観).
          # The fold matches MODERN READING HABITS: reform MERGES are admitted
          # (學/斈→学, 辨/瓣/辯→弁), so a search for 学 finds 學 and 弁 finds
          # 辨/瓣/辯. The glyph-literal escape hatch is `nabu search --exact`.
          # The canonical composes THROUGH the hani fold, so Japanese and Chinese
          # trad/simp land on one skeleton.
          #
          # Provenance:
          #   Unihan version:  #{@census.unihan_version}  (file date #{@census.unihan_date})
          #   KANJIDIC2:       #{@census.kanjidic_version}  (file date #{@census.kanjidic_date})
          #   generated on:    #{@generated_on}
          #   fold entries:    #{@census.fold_entries}
          #     lane 1 jinmeiyō 1:1 pairs:     #{@census.jinmeiyo_pairs}
          #     lane 2 kanjidic 1:1 pairs:     #{@census.kanjidic_singles}
          #     lane 2 kanjidic merges:        #{@census.merges.size} (#{merge_old_count} old forms admitted)
          #   refused: #{@census.ambiguous_refused.size} one-to-many ambiguous, #{@census.jinmeiyo_conflicts.size} jinmeiyō-lane conflicts
          #   dropped: #{@census.nfc_identity_dropped} NFC-identity (compat ideographs)
          #   jis212 variants refused (JIS X 0212 ≠ JIS X 0213; verified misread)
          #
          # NEW/OLD below is the SEMANTIC kyūjitai relation — the #{@census.reform_pairs}
          # authoritative jinmeiyō pairs ONLY (the char card's cross-reference);
          # the kanjidic lane (1:1 + merges) feeds the FOLD only, since its
          # <variant> links are not all genuine "old forms". Admitted-merge
          # census (new ← olds), flagship distinct-word collapses commented:
          #{merge_census_comment}
          #
          # Changing this table changes text_normalized for jpn — the §9
          # rebuild-storm caveat applies (aozora is enabled:false, so today it
          # is vacuous; the owner schedules the re-derive once jpn is synced).
          module Nabu
            module Jpn
              UNIHAN_VERSION = "#{@census.unihan_version}"
              UNIHAN_DATE = "#{@census.unihan_date}"
              KANJIDIC_VERSION = "#{@census.kanjidic_version}"
              KANJIDIC_DATE = "#{@census.kanjidic_date}"
              GENERATED_ON = "#{@generated_on}"

              # The authoritative jinmeiyō 1:1 reform pairs: shinjitai (new) =>
              # kyūjitai (old), key-sorted. The SEMANTIC old/new relation (the
              # char card's cross-reference), independent of the fold below. The
              # kanjidic lane (extra 1:1 + merges) is fold-only, NOT here.
              NEW = #{heredoc_chunks(@reform_pairs.keys.join)}

              OLD = #{heredoc_chunks(@reform_pairs.values.join)}

              NEW_TO_OLD = NEW.each_char.zip(OLD.each_char).to_h.freeze
              OLD_TO_NEW = NEW_TO_OLD.invert.freeze

              # The search fold: each variant → its shared skeleton (per §9's
              # composition rule). Per-codepoint 1→1 (fold_with_map-safe).
              FROM = #{heredoc_chunks(@fold_table.keys.join)}

              TO = #{heredoc_chunks(@fold_table.values.join)}

              TABLE = FROM.each_char.zip(TO.each_char).to_h.freeze

              # Fold a string to the shared kyūjitai/traditional skeleton.
              def self.fold(str)
                str.tr(FROM, TO)
              end

              # The kyūjitai (old form) of a shinjitai reform pair, or nil.
              # Merged shinjitai (辨/瓣/辯→弁) have no single old — nil for them.
              def self.old_form(new) = NEW_TO_OLD[new]

              # The shinjitai (new form) of a kyūjitai reform pair, or nil.
              def self.new_form(old) = OLD_TO_NEW[old]
            end
          end
        RUBY
      end

      private

      # --- lane 1 + jōyō signal (Unihan) ---------------------------------

      def parse_unihan
        @jinmeiyo_raw = []
        @joyo_unihan = {}
        File.foreach(@mappings_path, encoding: Encoding::UTF_8) do |line|
          if line.start_with?("#")
            parse_unihan_header(line)
            next
          end
          code, field, value = line.chomp.split("\t", 3)
          case field
          when KJINMEIYO
            next unless value&.include?(":U+")

            @jinmeiyo_raw << [nfc_codepoint(code), nfc_codepoint(value[/:(U\+\h+)/, 1])]
          when KJOYO
            @joyo_unihan[nfc_codepoint(code)] = true
          end
        end
        @census.unihan_version ||= "unknown"
        @census.unihan_date ||= "unknown"
      end

      def parse_unihan_header(line)
        case line
        when /^# Date: (\d{4}-\d{2}-\d{2})/ then @census.unihan_date = Regexp.last_match(1)
        when /^# Unicode Version (\S+)/ then @census.unihan_version = Regexp.last_match(1)
        end
      end

      # --- lane 2 source (KANJIDIC2) -------------------------------------

      # Stream the (optionally gzipped) XML, accumulating one <character> block
      # at a time (kanjidic2 is ~13 MB unzipped — never DOM the whole file).
      # Per block: literal, grade, and jis208/jis213 variant chars (jis212
      # refused at the decode boundary).
      def parse_kanjidic
        @grade = {}
        @strokes = {}
        @literals = {}
        @variants = Hash.new { |h, k| h[k] = [] }
        block = nil
        each_kanjidic_line do |line|
          case line
          when /<database_version>(.*?)</ then @census.kanjidic_version = Regexp.last_match(1)
          when /<date_of_creation>(.*?)</ then @census.kanjidic_date = Regexp.last_match(1)
          when /<character>/ then block = +""
          when %r{</character>} then absorb_character(block)
                                     block = nil
          else block << line if block
          end
        end
        @census.kanjidic_version ||= "unknown"
        @census.kanjidic_date ||= "unknown"
      end

      def each_kanjidic_line(&)
        if @kanjidic_path.end_with?(".gz")
          # GzipReader yields ASCII-8BIT; lines split on \n (safe for UTF-8) so
          # force the encoding back per line before the CJK literals are read.
          Zlib::GzipReader.open(@kanjidic_path) do |io|
            io.each_line { |line| yield line.force_encoding(Encoding::UTF_8) }
          end
        else
          File.foreach(@kanjidic_path, encoding: Encoding::UTF_8, &)
        end
      end

      def absorb_character(block)
        lit = block[%r{<literal>(.*?)</literal>}, 1] or return
        lit = nfc(lit)
        @literals[lit] = true
        @grade[lit] = Regexp.last_match(1).to_i if block =~ %r{<grade>(\d+)</grade>}
        # The FIRST stroke_count is the accepted one (later ones are common
        # miscounts, per the DTD) — the kyūjitai/simplification discriminator.
        @strokes[lit] = Regexp.last_match(1).to_i if block =~ %r{<stroke_count>(\d+)</stroke_count>}
        block.scan(%r{<variant var_type="(jis208|jis213)">([0-9-]+)</variant>}) do |var_type, kuten|
          decoded = decode_kuten(var_type, kuten) or next
          decoded = nfc(decoded)
          @variants[lit] << decoded unless decoded == lit
        end
      end

      # men-ku-ten → the character via the held JIS X 0213 table. jis212 never
      # reaches here (refused in absorb_character): it is a different standard.
      def decode_kuten(_var_type, kuten)
        m = KUTEN.match(kuten) or return nil
        Nabu::Adapters::Jis0213.resolve(plane: m[1].to_i, row: m[2].to_i, cell: m[3].to_i)
      end

      # --- resolution ----------------------------------------------------

      def resolve
        jinmeiyo = resolve_jinmeiyo          # [new, old] clean 1:1, canonical map
        jin_canon = jinmeiyo[:canonical]     # new => canonical skeleton
        @fold_table = jinmeiyo[:fold].dup    # from => to (lane 1)
        one_to_one = jinmeiyo[:pairs].dup    # new => old (lane 1 reform pairs)
        @census.jinmeiyo_pairs = one_to_one.size

        groups = kanjidic_groups             # jōyō new => [old claimants]
        groups.each do |new, olds|
          canonical, is_merge = group_canonical(new, olds, jin_canon)
          record_group(new, olds, canonical, is_merge: is_merge, jin_absorbed: jin_canon.key?(new))
        end

        # NEW/OLD (the SEMANTIC kyūjitai relation, the char card's cross-ref)
        # stays the AUTHORITATIVE jinmeiyō pairs only — KANJIDIC2 <variant>
        # links are not all genuine kyūjitai (弃 is 棄's ancient/simplified
        # form, not its "old form"), so labelling them kyūjitai would lie. The
        # kanjidic lane feeds the FOLD (findability), never the semantic table.
        @reform_pairs = one_to_one.sort_by { |new, _old| new.ord }.to_h
        @census.reform_pairs = @reform_pairs.size
        @fold_table = @fold_table.sort_by { |from, _to| from.ord }.to_h
        finalize
      end

      # Lane 1: kJinmeiyoKanji pointers → 1:1 pairs (drop NFC-identity; refuse
      # any many-to-one within the lane, though 17.0.0 has none). canonical =
      # Hani.fold(old) — the traditional skeleton, aligning with the lzh lane.
      def resolve_jinmeiyo
        pairs = @jinmeiyo_raw.reject do |old, new|
          identity = old == new
          @census.nfc_identity_dropped += 1 if identity
          identity
        end
        by_new = pairs.group_by(&:last)
        by_old = pairs.group_by(&:first)
        clean = pairs.reject do |old, new|
          by_new[new].map(&:first).uniq.size > 1 || by_old[old].map(&:last).uniq.size > 1
        end
        canonical = {}
        fold = {}
        reform = {}
        clean.each do |old, new|
          skeleton = nfc(Nabu::Hani.fold(old))
          canonical[new] = skeleton
          reform[new] = old
          [new, old].each { |form| fold[form] = skeleton unless form == skeleton }
        end
        { pairs: reform, canonical: canonical, fold: fold }
      end

      # jōyō new => sorted unique non-jōyō old claimants, after refusing any old
      # variant-linked to 2+ distinct jōyō forms (one-to-many ambiguity).
      def kanjidic_groups
        adjacency = build_adjacency
        joyo_neighbors = {}
        adjacency.each do |char, neighbors|
          next if joyo?(char) || !@literals.key?(char) # A must be a kanjidic non-jōyō

          js = neighbors.select { |n| joyo?(n) }.uniq
          joyo_neighbors[char] = js unless js.empty?
        end
        groups = Hash.new { |h, k| h[k] = [] }
        joyo_neighbors.each do |old, news|
          if news.size >= 2
            @census.ambiguous_refused << [old, news.sort]
          else
            groups[news.first] << old
          end
        end
        @census.ambiguous_refused.sort_by! { |old, _| old.ord }
        groups.transform_values { |olds| olds.uniq.sort_by(&:ord) }
      end

      # Undirected variant graph (either direction of the XML's pointers).
      def build_adjacency
        adjacency = Hash.new { |h, k| h[k] = [] }
        @variants.each do |char, decoded|
          decoded.each do |other|
            adjacency[char] << other
            adjacency[other] << char
          end
        end
        adjacency.each_value(&:uniq!)
        adjacency
      end

      def joyo?(char)
        grade = @grade[char]
        grade && GRADE_JOYO.include?(grade) && @joyo_unihan[char]
      end

      # The skeleton a group folds onto, and whether it is a merge.
      def group_canonical(new, olds, jin_canon)
        return [jin_canon[new], false] if jin_canon.key?(new) # lane 1 is authoritative
        return [single_canonical(new, olds.first), false] if olds.size == 1

        [nfc(Nabu::Hani.fold(new)), true] # merge → the shinjitai skeleton
      end

      # A 1:1 pair folds onto the TRADITIONAL member's Han skeleton — the one
      # the lzh/och lane also stores, so jpn and Chinese meet. The kyūjitai has
      # MORE strokes than its shinjitai, so the more-complex form is the
      # traditional (觀→観 folds to 觀, aligning with kanripo, even though Unihan
      # ships 観 no kTraditionalVariant). When the kanjidic "old" is actually
      # SIMPLER (弃 for 棄, 笔 for 筆 — a Chinese simplification, not a Japanese
      # kyūjitai), the standard new form is the traditional and wins, so the
      # common glyph is never folded onto a rare simplification.
      def single_canonical(new, old)
        traditional = (@strokes[old].to_i >= @strokes[new].to_i ? old : new)
        nfc(Nabu::Hani.fold(traditional))
      end

      def record_group(new, olds, canonical, is_merge:, jin_absorbed:)
        ([new] + olds).each { |form| add_fold(form, canonical) }
        if is_merge
          @census.merges[new] = olds
        elsif !jin_absorbed
          @census.kanjidic_singles += 1
        end
      end

      # Add from→to, dropping identity; a codepoint the fold already sends
      # ELSEWHERE is a jinmeiyō-lane conflict (lane 1 wins, lane 2 dropped).
      def add_fold(from, to)
        from = nfc(from)
        to = nfc(to)
        return if from == to

        if @fold_table.key?(from) && @fold_table[from] != to
          @census.jinmeiyo_conflicts << [from, @fold_table[from], to]
          return
        end
        @fold_table[from] = to
      end

      def finalize
        @census.jinmeiyo_conflicts.uniq!
        @census.fold_entries = @fold_table.size
        @fold_table.each do |from, to|
          raise Nabu::Error, "jpn-fold: #{to.inspect} is a value but also a key" if @fold_table.key?(to)
          if from.length != 1 || to.length != 1
            raise Nabu::Error, "jpn-fold: multi-char key/value #{from.inspect}=>#{to.inspect}"
          end
        end
        assert_reform_bijection
      end

      # NEW/OLD must be a bijection (each new one old, each old one new).
      def assert_reform_bijection
        olds = @reform_pairs.values
        return if olds.uniq.size == olds.size

        dup = olds.group_by(&:itself).select { |_o, v| v.size > 1 }.keys
        raise Nabu::Error, "jpn-fold: reform old form(s) claimed by 2+ new forms: #{dup.inspect}"
      end

      # --- rendering helpers ---------------------------------------------

      def merge_old_count = @census.merges.values.sum(&:size)

      def merge_census_comment
        @census.merges.sort_by { |new, _| new.ord }.map do |new, olds|
          note = MERGE_NOTES[new]
          "#   #{new} ← #{olds.join}#{"   (#{note})" if note}"
        end.join("\n")
      end

      def nfc(str) = str.unicode_normalize(:nfc)

      def nfc_codepoint(code)
        hex = code[/\AU\+(\h{4,6})\z/, 1] or
          raise Nabu::Error, "jpn-fold: malformed codepoint #{code.inspect}"
        nfc([hex.to_i(16)].pack("U"))
      end

      # A `<<~CHARS…` heredoc: the string chunked into 64-char lines.
      def heredoc_chunks(str)
        lines = str.scan(/.{1,64}/m).map { |chunk| "      #{chunk}" }
        ["<<~CHARS.delete(\"\\n\").freeze", *lines, "    CHARS"].join("\n")
      end
    end
  end
end
