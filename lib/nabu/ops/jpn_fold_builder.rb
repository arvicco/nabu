# frozen_string_literal: true

require_relative "../hani"

module Nabu
  module Ops
    # P38-4: generator for lib/nabu/jpn.rb — the Japanese kyūjitai↔shinjitai
    # (old-form ↔ new-form) search fold, derived from the HELD Unihan data
    # (canonical/unihan/Unihan_OtherMappings.txt, field kJinmeiyoKanji).
    # Dev-time ops code (fingerprint-excluded like hani_fold_builder): the
    # GENERATED lib/nabu/jpn.rb rides the shared-core digest (P36-1), so a
    # regeneration dirties every source (over-rebuild-safe).
    #
    # == Field discipline — the one clean held source
    #
    # kJinmeiyoKanji is Unicode's purpose-built list of the 2010 jinmeiyō
    # (name-use) kanji. When a jinmeiyō character is the KYŪJITAI (traditional
    # variant) of a jōyō character, the entry carries a pointer to that jōyō
    # (shinjitai) codepoint: `U+OLD  kJinmeiyoKanji  2010:U+NEW`. Those pointer
    # lines ARE the reform pairs — one authoritative, 1:1, Unicode-declared
    # old→new mapping. No other field is read.
    #
    # Deliberately NOT synthesised from KANJIDIC2's <variant jis208/212/213>
    # cross-references: those are kuten-coded and one-to-MANY (學 lists both 学
    # and the itaiji 斈; 体 lists 體 and 軆) with no clean signal for THE
    # kyūjitai — resolving them would require inventing a disambiguation policy,
    # which the hani mold forbids. The price is coverage: pairs whose old form
    # is NOT a registered name-kanji (學/学, 體/体, 醫/医, 觀/観) are OUT of
    # scope. The fold covers the ~173 name-kanji reform pairs, honestly bounded.
    #
    # == The merge policy (many-to-one reform merges)
    #
    # The famous reform merges — 辨/瓣/辯 → 弁, 豫/預 collisions — are NOT in
    # kJinmeiyoKanji (the merged-away old forms are not name-kanji), so the
    # source is merge-free by construction. The builder STILL enforces the
    # refusal structurally: if two distinct old forms ever pointed at one new
    # form (or one old at two new), BOTH are dropped and censused. We fold
    # toward the old form and REFUSE to invent a merge — never picking one of
    # 辨/瓣/辯 to be "the" traditional of 弁.
    #
    # == The composition rule with the hani fold (compose, not fight)
    #
    # lzh/och already fold through Nabu::Hani to a traditional skeleton, and a
    # kyūjitai like 國 is that skeleton. So the jpn canonical for each pair is
    # NOT the raw kyūjitai but Hani.fold(kyūjitai) — the exact traditional
    # fixed point hani assigns. For most pairs that IS the kyūjitai (國, 廣,
    # 圓…), so shinjitai folds to kyūjitai; for the few where Unihan makes the
    # shinjitai the traditional (the 奨↔奬 cycle family: 奬 桧 禄 緖 搖 遥 郞),
    # hani.fold(old) is the shinjitai, so the OLD form folds instead. Either
    # way every jpn fold value equals what hani produces, so Japanese old/new
    # forms land on the SAME index skeleton as Chinese trad/simp — the two
    # folds agree by construction rather than competing. jpn passages apply
    # ONLY this fold (never hani wholesale, which carries Chinese-specific
    # semantic merges wrong for Japanese); the query union still ORs both
    # lanes' variants, so cross-corpus findability holds regardless.
    #
    # All codepoints pass through NFC at build time — CJK compatibility
    # ideographs (the FA/F9 blocks: 渚 U+FA46, 類 U+F9D0…) decompose to their
    # unified forms, collapsing many of the raw pointer pairs to identity;
    # those are dropped (the runtime fold only ever sees post-NFC text).
    class JpnFoldBuilder
      FIELD = "kJinmeiyoKanji"

      # The census: provenance + every count the generated header and the
      # conventions §9 entry report.
      Census = Struct.new(:unihan_version, :unihan_date,
                          :raw_pointers, :nfc_identity_dropped, :reform_pairs,
                          :fold_entries, :hani_composed, :merges_refused,
                          keyword_init: true)

      attr_reader :census, :reform_pairs, :fold_table

      def initialize(mappings_path:, generated_on: Time.now.strftime("%Y-%m-%d"))
        @mappings_path = mappings_path
        @generated_on = generated_on
        @census = Census.new(raw_pointers: 0, nfc_identity_dropped: 0, reform_pairs: 0,
                             fold_entries: 0, hani_composed: 0, merges_refused: [])
        parse
        resolve
      end

      # The lib/nabu/jpn.rb source text.
      def render
        <<~RUBY
          # frozen_string_literal: true

          # GENERATED FILE — do not edit by hand. Regenerate with:
          #   rake fold:jpn            (reads canonical/unihan/Unihan_OtherMappings.txt)
          #
          # Nabu::Jpn (P38-4): the Japanese kyūjitai↔shinjitai (old↔new form)
          # search fold. Derived from the HELD Unihan kJinmeiyoKanji pointers —
          # the 2010 jinmeiyō old-forms of jōyō characters, the one clean 1:1
          # reform source Unicode ships. Reform MERGES (辨/瓣/辯 → 弁) are
          # refused, not invented. The fold canonical composes THROUGH the hani
          # fold (canonical = Hani.fold(kyūjitai)) so Japanese old/new forms
          # land on the same skeleton as Chinese trad/simp. Full rule, coverage
          # bound and provenance: Nabu::Ops::JpnFoldBuilder and conventions §9.
          #
          # Provenance:
          #   Unihan version:  #{@census.unihan_version}  (file date #{@census.unihan_date})
          #   generated on:    #{@generated_on}
          #   reform pairs:    #{@census.reform_pairs} (new↔old), from #{@census.raw_pointers} raw pointers
          #   fold entries:    #{@census.fold_entries} (#{@census.hani_composed} composed onto the shinjitai via hani)
          #   dropped:         #{@census.nfc_identity_dropped} NFC-identity (compat ideographs),
          #                    #{@census.merges_refused.size} many-to-one merges refused
          #
          # Changing this table changes text_normalized for jpn — the §9
          # rebuild-storm caveat applies (aozora is enabled:false, so today it
          # is vacuous; the owner schedules the re-derive once jpn is synced).
          module Nabu
            module Jpn
              UNIHAN_VERSION = "#{@census.unihan_version}"
              UNIHAN_DATE = "#{@census.unihan_date}"
              GENERATED_ON = "#{@generated_on}"

              # The reform pairs: shinjitai (new) => kyūjitai (old), key-sorted.
              # The SEMANTIC old/new relation (used by the char card's
              # cross-reference), independent of the hani-composed fold below.
              NEW = #{heredoc_chunks(@reform_pairs.keys.join)}

              OLD = #{heredoc_chunks(@reform_pairs.values.join)}

              NEW_TO_OLD = NEW.each_char.zip(OLD.each_char).to_h.freeze
              OLD_TO_NEW = NEW_TO_OLD.invert.freeze

              # The search fold: each variant → Hani.fold(kyūjitai), the shared
              # traditional skeleton. Per-codepoint 1→1 (fold_with_map-safe).
              FROM = #{heredoc_chunks(@fold_table.keys.join)}

              TO = #{heredoc_chunks(@fold_table.values.join)}

              TABLE = FROM.each_char.zip(TO.each_char).to_h.freeze

              # Fold a string to the shared kyūjitai/traditional skeleton.
              def self.fold(str)
                str.tr(FROM, TO)
              end

              # The kyūjitai (old form) of a shinjitai, or nil.
              def self.old_form(new) = NEW_TO_OLD[new]

              # The shinjitai (new form) of a kyūjitai, or nil.
              def self.new_form(old) = OLD_TO_NEW[old]
            end
          end
        RUBY
      end

      private

      def parse
        @raw = []
        File.foreach(@mappings_path, encoding: Encoding::UTF_8) do |line|
          if line.start_with?("#")
            parse_header(line)
            next
          end
          code, field, value = line.chomp.split("\t", 3)
          next unless field == FIELD && value&.include?(":U+")

          new_hex = value[/:(U\+\h+)/, 1]
          @raw << [nfc_char(code), nfc_char(new_hex)]
          @census.raw_pointers += 1
        end
        @census.unihan_version ||= "unknown"
        @census.unihan_date ||= "unknown"
      end

      def parse_header(line)
        case line
        when /^# Date: (\d{4}-\d{2}-\d{2})/ then @census.unihan_date = Regexp.last_match(1)
        when /^# Unicode Version (\S+)/ then @census.unihan_version = Regexp.last_match(1)
        end
      end

      def resolve
        # Drop NFC-identity pairs (compat ideographs collapse post-NFC).
        pairs = @raw.reject do |old, new|
          identity = old == new
          @census.nfc_identity_dropped += 1 if identity
          identity
        end

        # Reform relation new=>old; refuse any many-to-one / one-to-many.
        by_new = pairs.group_by(&:last)
        by_old = pairs.group_by(&:first)
        clean = pairs.reject do |old, new|
          merge = by_new[new].map(&:first).uniq.size > 1 || by_old[old].map(&:last).uniq.size > 1
          @census.merges_refused << [old, new] if merge
          merge
        end
        @census.merges_refused.uniq!

        reform = clean.to_h { |old, new| [new, old] } # new => old
        @reform_pairs = reform.sort_by { |new, _old| new.ord }.to_h
        @census.reform_pairs = @reform_pairs.size

        build_fold(clean)
      end

      # Compose each pair's canonical through the hani fold, drop self-maps,
      # assert every value is a fixed point (never itself a key).
      def build_fold(clean)
        table = {}
        clean.each do |old, new|
          canonical = Nabu::Hani.fold(old)
          @census.hani_composed += 1 if canonical != old
          [new, old].each { |form| table[form] = canonical unless form == canonical }
        end
        table.each do |from, to|
          raise Nabu::Error, "jpn-fold: #{to.inspect} is a value but also a key" if table.key?(to)
          if from.length != 1 || to.length != 1
            raise Nabu::Error, "jpn-fold: multi-char key/value #{from.inspect}=>#{to.inspect}"
          end
        end
        @fold_table = table.sort_by { |from, _to| from.ord }.to_h
        @census.fold_entries = @fold_table.size
      end

      def nfc_char(code)
        hex = code[/\AU\+(\h{4,6})\z/, 1] or
          raise Nabu::Error, "jpn-fold: malformed codepoint #{code.inspect}"
        [hex.to_i(16)].pack("U").unicode_normalize(:nfc)
      end

      # A `<<~CHARS…` heredoc: the string chunked into 64-char lines.
      def heredoc_chunks(str)
        lines = str.scan(/.{1,64}/m).map { |chunk| "      #{chunk}" }
        ["<<~CHARS.delete(\"\\n\").freeze", *lines, "    CHARS"].join("\n")
      end
    end
  end
end
