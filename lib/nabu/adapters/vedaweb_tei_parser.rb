# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming reader for one VedaWeb Rigveda book file — the `vedaweb-tei`
    # parser family (github.com/VedaWebProject/vedaweb-data,
    # rigveda/TEI/rv_book_NN.tei; 10–44 MB each, read through the encoding
    # belt, then a Nokogiri::XML::Reader pass, never a DOM over the book;
    # the whole Rigveda parses in ~15 s). Each hymn is yielded as a value
    # object once its last stanza has been read; a stanza's subtree (~10 KB)
    # is materialized alone through the reader's outer_xml.
    #
    # == The shape (censused over all ten books, 2026-10-21)
    #
    #   <div xml:id="b01" type="book">
    #     <div xml:id="b01_h001" ana="1" type="hymn">       ana = Grassmann's hymn number
    #       <div type="dedication">                          addressee + group, deu/eng <p>s
    #       <div xml:id="b01_h001_01" type="stanza">
    #         <fs type="stanza_properties">                  some stanzas (late-addition flags)
    #         <lg type="strata"> <l …_strata_a> <fs> label + strata </fs> …
    #         <lg source="zurich" xml:lang="san-Latn-x-ISO-15919">
    #           <l …_zur_a>agním īḷe puróhitaṃ</l>          the pada
    #           <l …_zur_a_tokens> <fs type="zurich_info"> surface / gra_lemma /
    #                                gra_gramm / morphosyntax (Leipzig labels) …
    #         <lg source="lubotsky|vnh|aufrecht|padapatha|eichler|geldner|…">
    #
    # 1,028 hymns, 10,552 stanzas, 39,832 zurich padas (a–h; 10,552 a,
    # 10,545 b, 10,394 c, 7,585 d, 437 e, 204 f, 112 g, 3 h), 164,758 zurich
    # tokens. Every stanza carries the zurich and strata layers.
    #
    # == License scope (the per-layer grants of vedaweb_corpus.tei)
    #
    # ONLY the CC BY 4.0 layers are read: zurich (text + annotation), strata,
    # stanza_properties and the dedication (addressees). The text versions
    # (lubotsky, vnh, aufrecht, padapatha, eichler) and the translations are
    # each CC BY-NC-SA 4.0 and are skipped here by construction — the
    # adapter's class note records the scope decision.
    #
    # == Morphology
    #
    # morphosyntax keeps upstream's own Leipzig category names and labels
    # verbatim ({"case" => ["ACC"], …}); a <vAlt> (the annotators'
    # undecided alternatives, e.g. ACC/GEN) keeps every reading in order.
    class VedawebTeiParser
      Hymn = Data.define(:id, :book, :number, :grassmann, :addressee, :group, :stanzas)
      Stanza = Data.define(:id, :number, :padas, :tokens, :strata, :properties)
      Token = Data.define(:id, :pada, :surface, :lemma, :lemma_ref, :gramm, :morphosyntax)

      HYMN_ID = /\Ab(\d+)_h(\d+)\z/
      PADA_ID = /_zur_([a-z])\z/
      TOKENS_ID = /_zur_([a-z])_tokens\z/
      TOKEN_ID = /_zur_([a-z]_\d+)\z/
      STRATA_ID = /_strata_([a-z])\z/
      private_constant :HYMN_ID, :PADA_ID, :TOKENS_ID, :TOKEN_ID, :STRATA_ID

      # Yields each Hymn of the book at +path+ in document order.
      def each_hymn(path)
        return enum_for(:each_hymn, path) unless block_given?

        hymn = nil
        SourceRead.utf8_file(path, label: "vedaweb").then do |xml|
          Nokogiri::XML::Reader(xml).each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.local_name == "div"

            case node.attribute("type")
            when "hymn"
              yield finish(hymn) if hymn
              hymn = start(node, path: path)
            when "dedication"
              hymn&.merge!(dedication(fragment(node)))
            when "stanza"
              raise Nabu::ParseError, "#{path}: stanza outside any hymn" unless hymn

              hymn[:stanzas] << stanza(fragment(node))
            end
          end
        end
        yield finish(hymn) if hymn
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: #{e.message}"
      end

      private

      def start(node, path:)
        id = node.attribute("xml:id").to_s
        match = HYMN_ID.match(id) or raise Nabu::ParseError, "#{path}: unexpected hymn id #{id.inspect}"
        { id: id, book: match[1].to_i, number: match[2].to_i, grassmann: Integer(node.attribute("ana"), 10),
          addressee: {}, group: {}, stanzas: [] }
      end

      def finish(hymn) = Hymn.new(**hymn)

      def fragment(node)
        Nokogiri::XML(node.outer_xml).tap(&:remove_namespaces!).root
      end

      def dedication(root)
        addressee = langs(root.at_xpath("./div[@type='addressee']"))
        group_div = root.at_xpath("./div[@type='group']")
        group = langs(group_div)
        group = { "n" => group_div["n"] }.merge(group) if group_div && group_div["n"]
        { addressee: addressee, group: group }
      end

      def langs(div)
        return {} unless div

        div.xpath("./p").to_h { |p| [p["lang"], text(p)] }.reject { |lang, value| lang.nil? || value.empty? }
      end

      def stanza(root)
        id = root["id"].to_s
        zurich = root.at_xpath("./lg[@source='zurich']")
        padas = {}
        tokens = []
        zurich&.xpath("./l")&.each do |line|
          line_id = line["id"].to_s
          if (m = TOKENS_ID.match(line_id))
            tokens.concat(line.xpath("./fs[@type='zurich_info']").map { |fs| token(fs, pada: m[1]) })
          elsif (m = PADA_ID.match(line_id))
            padas[m[1]] = text(line)
          end
        end
        Stanza.new(id: id, number: id.split("_").last.to_i, padas: padas, tokens: tokens,
                   strata: strata(root), properties: properties(root))
      end

      def strata(root)
        root.xpath("./lg[@type='strata']/l").each_with_object({}) do |line, out|
          letter = STRATA_ID.match(line["id"].to_s)&.[](1)
          next unless letter

          fields = line.xpath("./fs/f").to_h { |f| [f["name"], text(f)] }.reject { |_k, v| v.empty? }
          out[letter] = fields unless fields.empty?
        end
      end

      def properties(root)
        root.xpath("./fs[@type='stanza_properties']/f").to_h do |f|
          [f["name"], f.xpath(".//symbol").map { |s| s["value"] }.join("/")]
        end
      end

      def token(feature_set, pada:)
        lemma = feature_set.at_xpath("./f[@name='gra_lemma']/string")
        Token.new(
          id: TOKEN_ID.match(feature_set["id"].to_s)&.[](1),
          pada: pada,
          surface: text(feature_set.at_xpath("./f[@name='surface']/string")),
          lemma: lemma ? text(lemma) : nil,
          lemma_ref: lemma&.[]("correction")&.delete_prefix("#"),
          gramm: feature_set.at_xpath("./f[@name='gra_gramm']/symbol")&.[]("value"),
          morphosyntax: feature_set.xpath("./f[@name='morphosyntax']/fs/f").to_h do |f|
            [f["name"], f.xpath(".//symbol").map { |s| s["value"].to_s.strip }]
          end
        )
      end

      def text(node) = node ? Nabu::Normalize.nfc(node.text.gsub(/\s+/, " ").strip) : ""
    end
  end
end
