# frozen_string_literal: true

require "digest"
require "fileutils"
require "nokogiri"
require_relative "../url_download"

module Nabu
  module Adapters
    # kokubunken — NIJL's own TEI lane on GitHub (P108-4, Q89.3): the
    # 嘉禄二年本『古今和歌集』 transcription (kokubunken/kokinwakashu)
    # and the Man'yōshū TEI project (kokubunken/nijl-manyoshuTEI: the
    # 廣瀬本 — the only complete NON-Sengaku-line witness — plus the
    # 元暦校本 opening). Both READMEs grant CC BY 4.0 verbatim
    # (「クリエイティブコモンズライセンス 表示 4.0 国際 (CC BY 4.0)の
    # もとで公開しております」, read 2026-09-29). The 廣瀬本 is a
    # DIFFERENT manuscript line from held ONCOJ's base text — the
    # two-editions doctrine: complementary witnesses, never a dupe.
    #
    # == Two shapes, one adapter (fixture-verified 2026-09-29)
    #
    # kokin: div[@type=序] prose in phr units (xml:id kana1-1 → :kana1-1)
    # and 1,031 div[@type=和歌/墨滅歌] poems — passage per poem `l`
    # (xml:id n1 → :n1, the five ku segs joined), the 詞書 headnote and
    # 作者名 poet riding annotations. The critical apparatus reads the
    # LEM (the repo's own 国 base text); rdg variants ride the "rdg"
    # annotation; ruby reads its rb base.
    #
    # manyo: poems under div[@type=旧国歌大観番号 @n] — chōka as
    # ab[@type=長歌], tanka as lg[@type=短歌] (xml:id manyoNNNN →
    # :m<N>). The passage text is the MAN'YŌGANA base layer (the l
    # without @corresp; 長歌1行 segs minus their 傍訓 gloss segs); the
    # kun/傍訓 reading layer rides the "kun" annotation with marginal
    # notes and ミセケチ-struck deletions removed (corrections applied
    # — declared, the reading layer is an editorial surface).
    class Kokubunken < Nabu::Adapter
      FILES = {
        "kokin" => { repo: "kokinwakashu",
                     name: "Kokinwakashu_200003050_20240922.xml" },
        "manyo-hirose" => { repo: "nijl-manyoshuTEI",
                            name: "manyo_hirose_v06_0001-0234,3348-3577_202603.xml" },
        "manyo-genryaku" => { repo: "nijl-manyoshuTEI",
                              name: "manyo_genryakukohon_v01_0001-0006_amane202503.xml" }
      }.freeze
      RAW_BASE = "https://raw.githubusercontent.com/kokubunken"
      URN_PREFIX = "urn:nabu:kokubunken:"
      TEI_NS = { "tei" => "http://www.tei-c.org/ns/1.0" }.freeze

      TITLES = {
        "kokin" => "嘉禄二年本 古今和歌集 (NIJL TEI)",
        "manyo-hirose" => "廣瀬本 万葉集 巻一 (NIJL/関西大学 TEI)",
        "manyo-genryaku" => "元暦校本 万葉集 冒頭 (NIJL TEI)"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "kokubunken",
        name: "NIJL kokubunken TEI — 嘉禄二年本古今和歌集 + 廣瀬本/元暦校本万葉集",
        license: "CC BY 4.0, both repository READMEs verbatim (github.com/kokubunken, read " \
                 "2026-09-29): \"クリエイティブコモンズライセンス 表示 4.0 国際 (CC BY 4.0)の" \
                 "もとで公開しております\". Credit 国文学研究資料館 (NIJL) and, for the 廣瀬本, " \
                 "関西大学",
        license_class: "attribution",
        upstream_url: "https://github.com/kokubunken",
        parser_family: "kokubunken-tei"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "kokin tei", metadata_url: nil, state_subdir: "", liveness_only: true,
          zip_url: "#{RAW_BASE}/kokinwakashu/main/#{FILES['kokin'][:name]}"
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        FILES.each do |slug, spec|
          path = File.join(workdir, spec[:name])
          next unless File.file?(path)

          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{slug}",
                                      path: path, metadata: { "work" => slug })
        end
      end

      def parse(document_ref)
        xml = Nokogiri::XML(File.read(document_ref.path, encoding: "UTF-8"))
        raise Nabu::ParseError, "#{document_ref.path}: #{xml.errors.first}" if xml.errors.any?

        work = document_ref.metadata["work"]
        document = Nabu::Document.new(
          urn: document_ref.id, language: work == "kokin" ? "jpn" : "ojp",
          canonical_path: document_ref.path,
          title: TITLES.fetch(work), metadata: { "work" => work }
        )
        work == "kokin" ? parse_kokin(document, xml) : parse_manyo(document, xml)
        raise Nabu::ParseError, "#{document_ref.path}: no passages parsed — reshaped TEI?" if
          document.passages.empty?

        document
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        FILES.each_value do |spec|
          progress&.call("kokubunken #{spec[:name]}…\n")
          url = "#{RAW_BASE}/#{spec[:repo]}/main/#{spec[:name]}"
          downloaded = Nabu::UrlDownload.new.fetch(url, dir: workdir)
          wanted = File.join(workdir, spec[:name])
          FileUtils.mv(downloaded, wanted) unless downloaded == wanted
        end
        sha = Digest::SHA256.hexdigest(
          FILES.values.map { |s| Digest::SHA256.file(File.join(workdir, s[:name])).hexdigest }.join("\n")
        )
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now, notes: ["#{FILES.size} TEI files"])
      end

      private

      # -- kokin ------------------------------------------------------------

      def parse_kokin(document, xml)
        xml.xpath("//tei:body//tei:phr[@xml:id] | //tei:body//tei:l[@xml:id]", TEI_NS).each do |node|
          next if node.ancestors.any? { |a| a.name == "note" } # 古注 phrases ride their target

          node.name == "phr" ? add_kokin_phrase(document, node) : add_kokin_poem(document, node)
        end
      end

      def add_kokin_phrase(document, phr)
        working = phr.dup
        rdg = strip_apparatus!(working)
        text = squish(working.text)
        return if text.empty?

        annotations = {}
        annotations["rdg"] = rdg.join("；") unless rdg.empty?
        add_passage(document, ref: phr["xml:id"], text: text, annotations: annotations)
      end

      def add_kokin_poem(document, line)
        working = line.dup
        rdg = strip_apparatus!(working)
        text = working.xpath("./tei:seg", TEI_NS).map { |s| squish(s.text) }.reject(&:empty?)
        text = [squish(working.text)] if text.empty?
        annotations = {}
        annotations["rdg"] = rdg.join("；") unless rdg.empty?
        waka_div = line.ancestors.find { |a| a.name == "div" }
        if waka_div
          poet = waka_div.at_xpath(".//tei:note[@type='作者名']", TEI_NS)&.text
          kotobagaki = waka_div.at_xpath(".//tei:note[@type='詞書']", TEI_NS)
          annotations["poet"] = squish(poet.to_s) unless poet.to_s.strip.empty?
          if kotobagaki
            k = kotobagaki.dup
            strip_apparatus!(k)
            annotations["kotobagaki"] = squish(k.text)
          end
        end
        add_passage(document, ref: line["xml:id"], text: text.join("／"), annotations: annotations)
      end

      # app → keep lem, collect rdg readings; ruby → keep rb. Mutates
      # +node+ (always a dup), returns the removed variant readings.
      def strip_apparatus!(node)
        rdg = node.xpath(".//tei:rdg", TEI_NS).map { |r| squish(r.text) }
        node.xpath(".//tei:app", TEI_NS).each do |app|
          lem = app.at_xpath("./tei:lem", TEI_NS)
          app.replace(lem ? lem.children : Nokogiri::XML::NodeSet.new(node.document))
        end
        node.xpath(".//tei:ruby", TEI_NS).each do |ruby|
          rb = ruby.at_xpath("./tei:rb", TEI_NS)
          ruby.replace(rb ? rb.children : Nokogiri::XML::NodeSet.new(node.document))
        end
        rdg.reject(&:empty?)
      end

      # -- manyo ------------------------------------------------------------

      def parse_manyo(document, xml)
        xml.xpath("//tei:body//tei:lg[starts-with(@xml:id,'manyo')] | " \
                  "//tei:body//tei:ab[starts-with(@xml:id,'manyo')]", TEI_NS).each do |poem|
          add_manyo_poem(document, poem)
        end
      end

      def add_manyo_poem(document, poem)
        base, kun = manyo_layers(poem)
        return if base.empty?

        annotations = {}
        annotations["kun"] = kun unless kun.empty?
        annotations["form"] = poem["type"] if poem["type"]
        number = poem.ancestors.find { |a| a.name == "div" && a["type"] == "旧国歌大観番号" }&.[]("n")
        annotations["kokka_taikan"] = number if number
        ref = "m#{poem['xml:id'].sub(/\Amanyo0*/, '')}"
        add_passage(document, ref: ref, text: base, annotations: annotations)
      end

      # The man'yōgana base vs the kun reading layer. lg: base = the l
      # without @corresp, kun = the corresp-bearing l. ab (長歌): base =
      # the 長歌1行 segs minus their 傍訓 gloss segs; kun = those segs.
      # The kun surface applies corrections: marginal notes and
      # ミセケチ-struck del drop, add stays (declared editorial layer).
      def manyo_layers(poem)
        if poem.name == "lg"
          base = poem.xpath("./tei:l[not(@corresp)]", TEI_NS).map { |l| clean_layer(l) }
          kun = poem.xpath("./tei:l[@corresp]", TEI_NS).map { |l| clean_layer(l) }
          [base.join("／"), kun.join("／")]
        else
          glosses = poem.xpath(".//tei:seg[@type='傍訓']", TEI_NS).map { |s| clean_layer(s) }
          working = poem.dup
          working.xpath(".//tei:seg[@type='傍訓']", TEI_NS).each(&:remove)
          [clean_layer(working), glosses.join("／")]
        end
      end

      def clean_layer(node)
        working = node.dup
        working.xpath(".//tei:note | .//tei:del", TEI_NS).each(&:remove)
        squish(working.text)
      end

      # -- shared -----------------------------------------------------------

      def add_passage(document, ref:, text:, annotations:)
        document << Nabu::Passage.new(
          urn: "#{document.urn}:#{ref}", language: document.language,
          text: Normalize.nfc(text), sequence: document.passages.size + 1,
          annotations: annotations
        )
      end

      def squish(text)
        text.gsub(/\s+/, "").strip
      end
    end
  end
end
