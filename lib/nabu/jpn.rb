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
#   Unihan version:  17.0.0  (file date 2025-07-24)
#   generated on:    2026-07-21
#   reform pairs:    173 (new↔old), from 230 raw pointers
#   fold entries:    173 (7 composed onto the shinjitai via hani)
#   dropped:         57 NFC-identity (compat ideographs),
#                    0 many-to-one merges refused
#
# Changing this table changes text_normalized for jpn — the §9
# rebuild-storm caveat applies (aozora is enabled:false, so today it
# is vacuous; the owner schedules the re-derive once jpn is synced).
module Nabu
  module Jpn
    UNIHAN_VERSION = "17.0.0"
    UNIHAN_DATE = "2025-07-24"
    GENERATED_ON = "2026-07-21"

    # The reform pairs: shinjitai (new) => kyūjitai (old), key-sorted.
    # The SEMANTIC old/new relation (used by the char card's
    # cross-reference), independent of the hani-composed fold below.
    NEW = <<~CHARS.delete("\n").freeze
      万与乗争亙亜仏伝価倹偽児円凛剣剰勲単即厳収叙団国圏園堯塁増壊壮売奥奨嬢実富寛寝寿専将尽峡峰島巖巣巻帯庁広弥弾従徳徴応恒恵悪慎懐戦
      戯払抜拝捜掲揺摂撃斉昼晄晩暁暦曽条来杯栄桜検楽槇様横檜歩歴毎気浄涙涼渇渉渋温湿滝滞瀬灯為焼状狭獣畳痩盗県真砕礼祿禅禰禱秘稲穂穰竜
      粋緑緒縁縦繊翻聴臓芸荘萠蔵薫薬虚衛装覧謡譲転遙郎酔醸野鋳錬録鎮陥険雑静頼顕駆騒験髪鶏黄黒黙
    CHARS

    OLD = <<~CHARS.delete("\n").freeze
      萬與乘爭亘亞佛傳價儉僞兒圓凜劍剩勳單卽嚴收敍團國圈薗尭壘增壞壯賣奧奬孃實冨寬寢壽專將盡峽峯嶋巌巢卷帶廳廣彌彈從德徵應恆惠惡愼懷戰
      戲拂拔拜搜揭搖攝擊齊晝晃晚曉曆曾條來盃榮櫻檢樂槙樣橫桧步歷每氣淨淚凉渴涉澁溫濕瀧滯瀨燈爲燒狀狹獸疊瘦盜縣眞碎禮禄禪祢祷祕稻穗穣龍
      粹綠緖緣縱纖飜聽臟藝莊萌藏薰藥虛衞裝覽謠讓轉遥郞醉釀埜鑄鍊錄鎭陷險雜靜賴顯駈騷驗髮鷄黃黑默
    CHARS

    NEW_TO_OLD = NEW.each_char.zip(OLD.each_char).to_h.freeze
    OLD_TO_NEW = NEW_TO_OLD.invert.freeze

    # The search fold: each variant → Hani.fold(kyūjitai), the shared
    # traditional skeleton. Per-codepoint 1→1 (fold_with_map-safe).
    FROM = <<~CHARS.delete("\n").freeze
      万与乗争亙亜仏伝価倹偽児円凛剣剰勲単即厳収叙団国圏園堯塁増壊壮売奥奬嬢実富寛寝寿専将尽峡峰島巖巣巻帯庁広弥弾従徳徴応恒恵悪慎懐戦
      戯払抜拝捜掲搖摂撃斉昼晄晩暁暦曽条来杯栄桜桧検楽槇様横歩歴毎気浄涙涼渇渉渋温湿滝滞瀬灯為焼状狭獣畳痩盗県真砕礼禄禅禰禱秘稲穂穰竜
      粋緑緖縁縦繊翻聴臓芸荘萠蔵薫薬虚衛装覧謡譲転遥郞酔醸野鋳錬録鎮陥険雑静頼顕駆騒験髪鶏黄黒黙
    CHARS

    TO = <<~CHARS.delete("\n").freeze
      萬與乘爭亘亞佛傳價儉僞兒圓凜劍剩勳單卽嚴收敍團國圈薗尭壘增壞壯賣奧奨孃實冨寬寢壽專將盡峽峯嶋巌巢卷帶廳廣彌彈從德徵應恆惠惡愼懷戰
      戲拂拔拜搜揭揺攝擊齊晝晃晚曉曆曾條來盃榮櫻檜檢樂槙樣橫步歷每氣淨淚凉渴涉澁溫濕瀧滯瀨燈爲燒狀狹獸疊瘦盜縣眞碎禮祿禪祢祷祕稻穗穣龍
      粹綠緒緣縱纖飜聽臟藝莊萌藏薰藥虛衞裝覽謠讓轉遙郎醉釀埜鑄鍊錄鎭陷險雜靜賴顯駈騷驗髮鷄黃黑默
    CHARS

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
