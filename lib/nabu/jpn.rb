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
#   Unihan version:  17.0.0  (file date 2025-07-24)
#   KANJIDIC2:       2026-202  (file date 2026-07-21)
#   generated on:    2026-07-21
#   fold entries:    744
#     lane 1 jinmeiyō 1:1 pairs:     173
#     lane 2 kanjidic 1:1 pairs:     341
#     lane 2 kanjidic merges:        79 (185 old forms admitted)
#   refused: 2 one-to-many ambiguous, 0 jinmeiyō-lane conflicts
#   dropped: 57 NFC-identity (compat ideographs)
#   jis212 variants refused (JIS X 0212 ≠ JIS X 0213; verified misread)
#
# NEW/OLD below is the SEMANTIC kyūjitai relation — the 173
# authoritative jinmeiyō pairs ONLY (the char card's cross-reference);
# the kanjidic lane (1:1 + merges) feeds the FOLD only, since its
# <variant> links are not all genuine "old forms". Admitted-merge
# census (new ← olds), flagship distinct-word collapses commented:
#   世 ← 丗卋
#   両 ← 两兩
#   並 ← 傡竝
#   事 ← 亊叓
#   伐 ← 傠牫
#   体 ← 躰軆骵體
#   光 ← 灮炗
#   写 ← 冩寫
#   参 ← 參叅
#   台 ← 坮臺
#   哲 ← 喆嚞
#   夢 ← 夣梦
#   始 ← 乨兘
#   婿 ← 壻聟
#   学 ← 學斅斈
#   宜 ← 冝宐
#   宝 ← 寚寳寶
#   帰 ← 歸皈
#   弁 ← 瓣辧辨辮辯   (辨 (discriminate) / 瓣 (petal, valve) / 辯 (speech, argue) — three words, one shinjitai)
#   弄 ← 挊挵
#   弐 ← 貮貳
#   径 ← 徑逕
#   拡 ← 挄擴
#   挙 ← 擧舉
#   携 ← 擕攜
#   松 ← 枩柗梥
#   棋 ← 棊檱
#   欠 ← 缺缼   (缺 (lack, vacancy) vs the native 欠 (ken: to yawn, deficient))
#   殻 ← 壳殼
#   法 ← 佱灋
#   泰 ← 夳𣳾
#   浜 ← 濱濵
#   渓 ← 嵠溪磎谿
#   潜 ← 潛濳
#   災 ← 灾烖
#   照 ← 曌瞾
#   琴 ← 珡琹
#   留 ← 畄畱
#   畝 ← 畆畒畞
#   秋 ← 穐龝
#   称 ← 稱穪
#   稚 ← 稺穉
#   稿 ← 稾藳
#   窓 ← 囱牎牕窗窻
#   窯 ← 窑窰
#   続 ← 續賡
#   総 ← 摠緫總
#   繭 ← 絸蠒
#   缶 ← 缻罐   (罐 (kan: boiler, can) vs the native 缶 (fou: earthenware vessel))
#   職 ← 聀軄
#   胆 ← 膻膽
#   脳 ← 匘腦
#   艶 ← 艷豓豔
#   蓋 ← 盖葢
#   虎 ← 乕虝
#   蚕 ← 蝅蠶蠺
#   褒 ← 裒襃
#   覇 ← 灞霸
#   覚 ← 覐覺
#   質 ← 劕貭
#   辞 ← 辝辤辭
#   辺 ← 邉邊
#   道 ← 噵衜衟
#   酬 ← 酧醻
#   鉄 ← 銕鋨鐡鐵
#   鉱 ← 砿磺礦鑛
#   鑑 ← 鍳鑒
#   長 ← 兏镸
#   闘 ← 鬦鬪鬭
#   陰 ← 侌阥隂
#   陽 ← 阦阳
#   隠 ← 乚隱
#   隣 ← 厸鄰
#   霊 ← 灵霛靈
#   霧 ← 雺霚
#   風 ← 凮飌
#   髄 ← 膸髓
#   鶴 ← 靎靏鸖
#   麺 ← 麪麵
#
# Changing this table changes text_normalized for jpn — the §9
# rebuild-storm caveat applies (aozora is enabled:false, so today it
# is vacuous; the owner schedules the re-derive once jpn is synced).
module Nabu
  module Jpn
    UNIHAN_VERSION = "17.0.0"
    UNIHAN_DATE = "2025-07-24"
    KANJIDIC_VERSION = "2026-202"
    KANJIDIC_DATE = "2026-07-21"
    GENERATED_ON = "2026-07-21"

    # The authoritative jinmeiyō 1:1 reform pairs: shinjitai (new) =>
    # kyūjitai (old), key-sorted. The SEMANTIC old/new relation (the
    # char card's cross-reference), independent of the fold below. The
    # kanjidic lane (extra 1:1 + merges) is fold-only, NOT here.
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

    # The search fold: each variant → its shared skeleton (per §9's
    # composition rule). Per-codepoint 1→1 (fold_with_map-safe).
    FROM = <<~CHARS.delete("\n").freeze
      一丄丅万三与丗丘两乕乗乚乨乱乹亀予争亊二亖亗亙亜亝亡享京仂仏仐仮仾会伝似余佱侌価侯信俢倂倹健偽備傠傡兏児兘党兩冃円冊冐写冝冣冩冲
      决况凄减凖凛凡凥処凮凷刀刃剣剤剥剰剱創劒劔劕努励労効勅勇勛勧勲匘匞匨区医卆卋卓単即却厓厚原厯厳厸去參叅双収叓叙叞叠号吴呉呪和咏咽
      唀唇唱啓善喆喫営嗅嗎嘱嘽噵嚞囘囙団囱囲図囶国圀圏園圧坮垂垩埞堕堯場塁塑塔塩填増壄壊壌壐壮声壱売壳壻夅変夏多夣夳奇奈奥奬妊妒妙姉姻
      嬢学守宐実宷富寍寚寛寝寳寶対寿専将尽届屚属岳峡峰島嵠嶌嶴嶹巖巣巻帋帒帯帳幣年幹庁広廃廰弃弥弾当往征径従徳徴忄忙応忢怖思怪恋恒恥恱
      恵悦悩悪悳惨慎憇懐戦戯戻払抜択担拝拠挄挊挙挟挵捜掃接掲插搖摂摠摩撃撡擕擧擴攜敗敘数敺斅斈斉斊斎断旉旧旹旺旾昇明星是昼晄晩普晴暁暦
      暸曌曺曽期本杉条杤来杯构枢枩柗柳柿栄桑桘桜桟桧桼梥梦棊椉検楼楽概槇槗様権横檱欝欧欵歓歩歮歯歴歸残殴殺殼毌毎比気氷汚沈沗没沢泥泪洯
      浄浅涌涙涯涼淫渇済渉渋温湾湿満源溪滝滞漫潜澀濱濳濵瀬灋灞火灮灯灵灾炁炉炗点為烖烟焼煅牎牕牫犠状独狭猟猨猫献獍獎獣率珍珡琹瑠瓣瓶男
      町画畄畆畒畞略畱畳畾疂疉疎痩痴瘉発登皃皈皍盖盗監県真眾瞾砕砿硏確磁磎磺礆礦礼禄禅禰禱秇秘稱稲稺稾穂穉穏穐穪穰窃窑窗窮窰窻竜竝笔笧
      篭粋粛粮糸糺経統絵絸継綫緑緖緫縁縄縦總繊續纎缺缻缼缽罐罰群羪翻聀聟聴肎股育脅脉脚腦腸膳膸膻膽臓臺舉舎舗舩艷花芸英茎荘華萠葢葬蔵薫
      薬藳蘍虗虚虝虫虵蚊蛍蛮蜂蝅蠒蠶蠺衛衜衟装裒褱襃覐覧観覺觔解触訳証誉読謡譲谿豊豓豔豚貝財貭貮貳賛賡賢走践踊躰軄軆転軰軽轄辝辤辧辨辭
      辮辯迁逃逓逕遅達遡遥邉邊郒郞部鄰酔酢酧醸醻釈野釜釼鈆銕銭鋨鋳錬録鍳鎌鎖鎮鐡鐵鑒鑛镸閉関阥阦阳陥険隂階随隙隱隸雑雞雷雺霚霛霸靈靎靏
      静靣靴頬頼顔顕飌飲飾餅館駅駆騐騒験驅骵髓體髪鬦鬪鬭鶏鸖麦麪麵麻黄黒黙鼓齢龒龝𠮟𣳾
    CHARS

    TO = <<~CHARS.delete("\n").freeze
      弌上下萬弎與世坵両虎乘隠始亂乾龜豫爭事弍四歳亘亞齊兦亯亰働佛傘假低會傳佀餘法陰價矦訫修併儉徤僞僃伐並長兒始黨両帽圓册冒寫宜最寫沖
      決況淒減準凜凢居處風塊釖刄劍劑剝剩劍戧劍劍質伮勵勞效敕勈勳勸勳脳匠藏區醫卒世桌單卽卻崖垕厡曆嚴隣厺参参雙收事敍尉疊號吳吳咒龢詠胭
      誘脣誯諬譱哲噄營齅罵囑單道哲回因團窓圍圖國國國圈薗壓台埀聖堤墮尭塲壘塐墖鹽塡增埜壞壤璽壯聲壹賣殻婿降變夓夛夢泰竒柰奧奨姙妬玅姊婣
      孃學垨宜實審冨寧宝寬寢宝宝對壽專將盡屆漏屬嶽峽峯嶋渓嶋奧嶋巌巢卷紙袋帶賬幤秊榦廳廣廢廳棄彌彈當徃徰徑從德徵心恾應悟悑恖恠戀恆耻悅
      惠悅惱惡德慘愼憩懷戰戲戾拂拔擇擔拜據拡弄𢸁挾弄搜埽擑揭挿揺攝総擵擊操携𢸁拡携贁敍數駈學學齊齊齋斷敷舊時暀春曻朙皨昰晝晃晚暜暒曉曆
      瞭照曹曾朞夲檆條栃來盃構樞松松桺柹榮桒椎櫻棧檜漆松夢棋乘檢樓樂槪槙橋樣權橫棋鬱歐款歡步澁齒歷帰殘毆煞殻貫每夶氣冰汙沉添沒澤坭淚潔
      淨淺湧淚漄凉婬渴濟涉澁溫灣濕滿厵渓瀧滯熳潛澁浜潛浜瀨法覇伙光燈霊災氣爐光點爲災煙燒鍛窓窓伐犧狀獨狹獵猿貓獻鏡奨獸卛珎琴琴璢弁甁侽
      甼畫留畝畝畝畧留疊壘疊疊踈瘦癡癒發僜貌帰卽蓋盜譼縣眞衆照碎鉱研碻礠渓鉱險鉱禮祿禪祢祷藝祕称稻稚稿穗稚穩秋称穣竊窯窓竆窯窓龍並筆策
      籠粹肅糧絲糾經綂繪繭繼線綠緒総緣繩縱総纖続纖欠缶欠鉢缶罸羣養飜職婿聽肯脵毓脋脈踋脳膓饍髄胆胆臟台𢸁舍舖船艶芲藝偀莖莊蕐萌蓋塟藏薰
      藥稿薰虛虛虎蟲蛇蟁螢蠻蠭蚕繭蚕蚕衞道道裝褒懷褒覚覽觀覚筋觧觸譯證譽讀謠讓渓豐艶艶豘蛽戝質弐弐贊続贒赱踐踴体職体轉輩輕鎋辞辞弁弁辞
      弁弁遷迯遞徑遲逹溯遙辺辺郎郎郶隣醉醋酬釀酬釋埜釡劍鉛鉄錢鉄鑄鍊錄鑑鐮鏁鎭鉄鉄鑑鉱長閇關陰陽陽陷險陰堦隨隟隠隷雜鷄靁霧霧霊覇霊鶴鶴
      靜面鞾頰賴顏顯風飮餝餠舘驛駈驗騷驗駈体髄体髮闘闘闘鷄鶴麥麺麺蔴黃黑默皷齡龍秋叱泰
    CHARS

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
