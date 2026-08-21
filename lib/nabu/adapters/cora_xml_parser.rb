# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for the cora-xml family (P80-5): the RAW CorA-XML
    # export of the CorA annotation tool (Bollmann et al.) used by the
    # Bochum/Halle reference-corpus projects. First registrant: ReF (Early
    # New High German, ref-mlu + ref-rub subcorpora); the ReM/ReN CorA-XML
    # sibling zips (ReM's pos/msd gap, ReN's dating gap — both documented
    # at their adapters) are natural future registrants. Censused from the
    # WHOLE ReF v1.0.2 deposit (190 files, 3,107,196 tokens — never
    # invented); fixtures are four structural trims of real texts.
    #
    #   <text id="F011">
    #     <cora-header sigle="F011" name="Die Geometria. Deutsch"/>
    #     <header>corpus: ReF.MLU
    #   language-area: nordbairisch
    #   date: 1487/88 …</header>
    #     <layoutinfo>
    #       <page id="p1" no="001" range="c1" side="r"/>
    #       <column id="c1" range="l1..l13"/>
    #       <line id="l1" name="01" range="t1_d1..t8_d1"/> …
    #     </layoutinfo>
    #     <shifttags><title range="t2..t4"/> …</shifttags>
    #     <token id="t8" trans="her(=)nach">
    #       <tok_dipl id="t8_d1" trans="her(=)" utf="her"/>
    #       <tok_dipl id="t8_d2" trans="nach" utf="nach"/>
    #       <tok_anno id="t8_m1" trans="her(=)nach" utf="hernach" ascii="hernach">
    #         <lemma tag="hernach"/><pos tag="AVD"/><morph tag="*"/> …
    #
    # == The two token layers (canonical means canonical)
    #
    # tok_dipl carries the DIPLOMATIC layer (@utf: long ſ, combining marks,
    # superscripts); tok_anno carries the annotated layer (@utf/@ascii +
    # lemma/pos/morph…). The diplomatic layer is the witness — line text is
    # the line's dipl @utf forms space-joined (each dipl is a separately
    # written unit; censused 33,739 same-line multi-dipl tokens). The anno
    # records ride Line#tokens. A token whose dipls straddle a line break
    # (the her(=)nach hyphenation) contributes each dipl to its own line;
    # its anno records ride the line the token STARTS on.
    #
    # == Lines (the layout grain)
    #
    # layoutinfo gives the physical hierarchy: page (@no + @side, side
    # sometimes absent) → column (@name only in multi-column layouts) →
    # line (@name = upstream's zero-padded label, kept verbatim; @range =
    # the dipl-id window). Censused: every line's start dipl id exists and
    # the first dipl of every file starts its first line, so the body walk
    # switches lines on start ids. Duplicate (page, side, column, name)
    # citations exist upstream (5,729 across 40 files, adjacent duplicate
    # labels included) — passing them through verbatim is deliberate;
    # disambiguation is the ADAPTER's citation policy, not the parser's.
    #
    # == Token records (the honest selection)
    #
    # Per tok_anno: id, form (the anno unit's @utf — the "form" key is the
    # house tokens contract, what the lemma index shows as the attesting
    # surface), ascii (only when it differs from form), lemma,
    # pos, morph, lemma_id (the DWB id, [GA07685] → GA07685), punc /
    # boundary (the modern-punctuation and sentence-boundary suggestion
    # lanes, verbatim), token_type, comment (the annotator's @tag note —
    # "Mehl?", "neues Lemma"), anno_type ONLY when "manual" (censused
    # 2,874,451 auto / 544,520 manual — absence reads auto), flags (the
    # cora-flag names minus the punc/boundary presence mirrors). Documented
    # drops: @trans (transcription-internal encoding), posLemma (the pos
    # value's class prefix), lemmaURL (a template over lemma_id/lemma),
    # @checked (mirrors anno_type manual). TOP-LEVEL <comment type=…>
    # elements between tokens (transcriber apparatus with free text) are
    # COUNTED (Body#comments) and their text swallowed — content
    # extraction is a documented follow-up, and the count keeps the drop
    # honest. A token with NO tok_anno (transcription-only material)
    # records id + form so the token census stays whole.
    #
    # == Loudness (the aozora precedent)
    #
    # Unrecognized elements are counted (Body#unrecognized, name → count)
    # and parsing continues; non-whitespace text outside <header> counts
    # under "#text". Shifttag spans (rub/title/lat/fm ranges) are censused
    # by kind (Body#shifttags) — span application is a documented
    # follow-up. ParseError is reserved for structural breakage: malformed
    # XML, a dipl before any line start, a line whose column/page mapping
    # is missing, a malformed layout range.
    class CoraXmlParser
      # The cora-header identity plus the free-text key/value header
      # fields (upstream keys verbatim; "-"/"--" null placeholders
      # dropped; multi-line values kept whole, newlines preserved).
      Header = Data.define(:sigle, :name, :fields)

      # One physical line: +page+ the page @no, +side+ its r/v side (nil
      # when the page carries none), +column+ the column @name (nil in
      # single-column layouts), +n+ the line @name label verbatim, +text+
      # the diplomatic surface (caller normalizes), +tokens+ the anno
      # records (string-keyed Hashes).
      Line = Data.define(:page, :side, :column, :n, :text, :tokens)

      # One file's body: lines in document order, the shifttag census
      # (kind → count), the count of top-level editorial comments
      # (swallowed apparatus — see class note) and the unrecognized-
      # element census (name → count).
      Body = Data.define(:lines, :shifttags, :comments, :unrecognized)

      # The closed header key set (censused: all 190 ReF files carry
      # exactly these 28). A header line starting with anything else is a
      # continuation of the previous value.
      HEADER_KEYS = %w[
        corpus language-area language-region language-type genre medium
        time reference corpus-sigle text text-author text-type
        assignment_quality hoffmann_wetter_nr library library-shelfmark
        date place text-place printer edition size language literature
        notes-transcription abbr_ddd extent extent-size
      ].freeze

      # Upstream's null placeholder in header fields.
      NULL_PLACEHOLDER = /\A-+\z/

      # tok_anno children captured as token-record fields (element name →
      # record key; @tag carries the value).
      ANNO_CAPTURES = {
        "lemma" => "lemma", "pos" => "pos", "morph" => "morph",
        "punc" => "punc", "boundary" => "boundary", "token_type" => "token_type",
        "comment" => "comment"
      }.freeze

      # tok_anno children recognized and deliberately dropped (class note).
      ANNO_DROPS = %w[posLemma lemmaURL].freeze

      # cora-flag names that merely mirror the punc/boundary elements.
      MIRROR_FLAGS = %w[punc boundary].freeze

      TEXT_NODE_TYPES = [Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_CDATA,
                         Nokogiri::XML::Reader::TYPE_SIGNIFICANT_WHITESPACE].freeze

      # Peek one file's identity + header fields; stops at </header>.
      def header(path)
        walk = { sigle: nil, name: nil, in_header: false, buffer: +"" }
        each_node(path) do |node|
          case node.node_type
          when Nokogiri::XML::Reader::TYPE_ELEMENT
            case node.name
            when "cora-header"
              walk[:sigle] = node.attribute("sigle")
              walk[:name] = node.attribute("name")
            when "header" then walk[:in_header] = true
            end
          when Nokogiri::XML::Reader::TYPE_END_ELEMENT
            break if node.name == "header"
          when *TEXT_NODE_TYPES
            walk[:buffer] << node.value if walk[:in_header]
          end
        end
        Header.new(sigle: walk[:sigle], name: walk[:name], fields: header_fields(walk[:buffer]))
      end

      # Read one file's body into lines + the censuses.
      def body(path)
        walk = fresh_walk(path)
        each_node(path) do |node|
          case node.node_type
          when Nokogiri::XML::Reader::TYPE_ELEMENT then open_element(node, walk)
          when Nokogiri::XML::Reader::TYPE_END_ELEMENT then close_element(node, walk)
          when *TEXT_NODE_TYPES then capture_text(node, walk)
          end
        end
        Body.new(lines: finished_lines(walk), shifttags: walk[:shifttags].sort.to_h,
                 comments: walk[:comments], unrecognized: walk[:unrecognized].sort.to_h)
      end

      private

      # The free-text header block: one "key: value" field per line keyed
      # by the closed HEADER_KEYS set (a line starting with anything else
      # — value text with a colon, a wrapped line — continues the current
      # field). Null placeholders drop; values stay verbatim otherwise
      # (inner colons, literal \n escapes).
      def header_fields(text)
        fields = {}
        current = nil
        text.each_line(chomp: true) do |line|
          key, _, rest = line.partition(":")
          if HEADER_KEYS.include?(key)
            current = key
            fields[current] = rest.strip
          elsif current && !line.strip.empty?
            fields[current] = "#{fields[current]}\n#{line}".strip
          end
        end
        fields.reject { |_, v| v.empty? || NULL_PLACEHOLDER.match?(v) }
      end

      def each_node(path, &)
        reader = Nokogiri::XML::Reader(File.open(path, "r:UTF-8"))
        reader.each(&)
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed CorA-XML: #{e.message}"
      end

      def fresh_walk(path)
        { path: path, in_header: false, in_comment: false, section: nil,
          layout: { pages: [], columns: [], lines: [] },
          starts: nil, current: nil, token: nil, anno: nil, comments: 0,
          shifttags: Hash.new(0), unrecognized: Hash.new(0), builders: [] }
      end

      # -- element dispatch --------------------------------------------------

      def open_element(node, walk)
        case node.name
        when "text", "cora-header" then nil # the identity envelope (header() reads it)
        when "header" then walk[:in_header] = true
        when "layoutinfo" then walk[:section] = :layout unless node.self_closing?
        when "shifttags" then walk[:section] = :shifttags unless node.self_closing?
        when "page", "column", "line" then collect_layout(node, walk)
        when "token" then open_token(node, walk)
        when "tok_dipl" then open_dipl(node, walk)
        when "tok_anno" then open_anno(node, walk)
        else open_leaf(node, walk)
        end
      end

      def close_element(node, walk)
        case node.name
        when "header" then walk[:in_header] = false
        when "layoutinfo", "shifttags" then walk[:section] = nil
        when "token" then close_token(walk)
        when "tok_anno" then close_anno(walk)
        when "comment" then walk[:in_comment] = false
        end
      end

      def open_leaf(node, walk)
        if node.name == "comment" && walk[:anno].nil?
          # A top-level editorial comment (<comment type="K">…</comment>
          # between tokens — transcriber apparatus): counted, its free
          # text swallowed (never loose "#text" noise).
          walk[:comments] += 1
          walk[:in_comment] = true unless node.self_closing?
        elsif walk[:section] == :shifttags
          walk[:shifttags][node.name] += 1
        elsif walk[:anno] && (key = ANNO_CAPTURES[node.name])
          walk[:anno][key] = node.attribute("tag")
        elsif walk[:anno] && node.name == "lemmaId"
          walk[:anno]["lemma_id"] = node.attribute("tag")&.delete("[]")
        elsif walk[:anno] && node.name == "annoType"
          # Rides only as the manual mark: absence reads auto (censused
          # 2,874,451 auto / 544,520 manual — the minority is the signal).
          walk[:anno]["anno_type"] = "manual" if node.attribute("tag") == "manual"
        elsif walk[:anno] && node.name == "cora-flag"
          flag = node.attribute("name")
          (walk[:anno]["flags"] ||= []) << flag unless MIRROR_FLAGS.include?(flag)
        elsif walk[:anno] && ANNO_DROPS.include?(node.name)
          nil # recognized, deliberately dropped (class note)
        else
          walk[:unrecognized][node.name] += 1
        end
      end

      def capture_text(node, walk)
        return if walk[:in_header] || walk[:in_comment] || node.value.strip.empty?

        walk[:unrecognized]["#text"] += 1
      end

      # -- layout ------------------------------------------------------------

      def collect_layout(node, walk)
        unless walk[:section] == :layout
          walk[:unrecognized][node.name] += 1
          return
        end
        walk[:layout][:"#{node.name}s"] << %w[id no side name range].to_h { |a| [a, node.attribute(a)] }
      end

      # Resolve the layout hierarchy into start-dipl-id → line builder.
      # Ranges expand numerically (p1/c3/l70 ids — censused); a range whose
      # endpoints disagree with its prefix is structural breakage.
      def resolve_layout!(walk)
        page_of_col = {}
        col_of_line = {}
        cols = {}
        walk[:layout][:pages].each do |p|
          expand_range(p["range"], "c", walk).each { |c| page_of_col[c] = p }
        end
        walk[:layout][:columns].each do |c|
          cols[c["id"]] = c
          expand_range(c["range"], "l", walk).each { |l| col_of_line[l] = c["id"] }
        end
        walk[:starts] = {}
        walk[:layout][:lines].each do |line|
          cid = col_of_line[line["id"]] or
            raise Nabu::ParseError, "#{walk[:path]}: line #{line['id']} belongs to no column range"
          page = page_of_col[cid] or
            raise Nabu::ParseError, "#{walk[:path]}: column #{cid} belongs to no page range"
          builder = { page: page["no"], side: page["side"], column: cols[cid]["name"],
                      n: line["name"], dipl_utfs: [], tokens: [] }
          walk[:builders] << builder
          walk[:starts][line["range"].to_s.split("..").first] = builder
        end
      end

      def expand_range(range, prefix, walk)
        parts = range.to_s.split("..")
        unless parts.size.between?(1, 2) && parts.all? { |p| p.match?(/\A#{prefix}\d+\z/) }
          raise Nabu::ParseError, "#{walk[:path]}: malformed layout range #{range.inspect}"
        end
        return parts if parts.size == 1

        (parts.first.delete_prefix(prefix).to_i..parts.last.delete_prefix(prefix).to_i)
          .map { |i| "#{prefix}#{i}" }
      end

      # -- tokens ------------------------------------------------------------

      def open_token(node, walk)
        resolve_layout!(walk) if walk[:starts].nil?
        walk[:token] = { id: node.attribute("id"), home: nil, dipl_utfs: [], annos: [] }
      end

      def open_dipl(node, walk)
        token = walk[:token] or
          raise Nabu::ParseError, "#{walk[:path]}: tok_dipl outside a token"
        if (builder = walk[:starts][node.attribute("id")])
          walk[:current] = builder
        end
        walk[:current] or
          raise Nabu::ParseError,
                "#{walk[:path]}: dipl #{node.attribute('id')} before any layout line start"
        walk[:current][:dipl_utfs] << node.attribute("utf").to_s
        token[:home] ||= walk[:current]
        token[:dipl_utfs] << node.attribute("utf").to_s
      end

      def open_anno(node, walk)
        token = walk[:token] or
          raise Nabu::ParseError, "#{walk[:path]}: tok_anno outside a token"
        anno = { "id" => node.attribute("id"), "form" => node.attribute("utf") }
        ascii = node.attribute("ascii")
        anno["ascii"] = ascii if ascii && ascii != anno["form"]
        walk[:anno] = anno
        token[:annos] << anno
        close_anno(walk) if node.self_closing?
      end

      def close_anno(walk)
        walk[:anno] = nil
      end

      def close_token(walk)
        token = walk[:token]
        walk[:token] = nil
        return unless token && token[:home]

        records = token[:annos]
        records = [{ "id" => token[:id], "form" => token[:dipl_utfs].join(" ") }] if records.empty?
        token[:home][:tokens].concat(records)
      end

      def finished_lines(walk)
        walk[:builders].map do |b|
          Line.new(page: b[:page], side: b[:side], column: b[:column], n: b[:n],
                   text: b[:dipl_utfs].join(" "), tokens: b[:tokens])
        end
      end
    end
  end
end
