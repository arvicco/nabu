# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The `tamilex-tei` parser family (P121-3): TAMILEX's critical TEI
    # editions of the classical Tamil corpus (Universität Hamburg; the
    # UHH-Tamilex repos). One file is one edited unit — a poem, a sūtra, a
    # couplet, a canto — in ISO 15919 romanized Tamil, with a parallel
    # English translation and, on most files, a per-word WORDSPLIT standOff
    # that exists nowhere else for Old Tamil. Shapes read from real files
    # (census 2026-10-12, recorded in test/fixtures/tamilex/README.md):
    #
    # == Passages
    #
    # Every `<text>` of the file is walked in order. The FIRST is the root
    # edition; every later one is a commentary (`<body><head>` names the
    # commentator — Parimēlaḻakar, Iḷampūraṇar …). Within a text, the
    # outermost `lg`/`p` blocks are the units:
    #
    #   - a Tamil block is a passage, cited by its xml:id when upstream
    #     minted one (`KT1`, `KT1-kilavi`, `TK1-Pari1`) and positionally
    #     otherwise as <text n>.<Tamil block ordinal> (`2.4` — the
    #     commentaries' id-less prose);
    #   - an English block (xml:lang="en") is never a passage: it is the
    #     `translation` of the preceding Tamil sibling (the `div
    #     rend="parallel"` pairing) or, with none before it, the commentary's
    #     edition statement (metadata "commentaries", "edition").
    #
    # Verse lines join by "\n"; whitespace collapses inside a line or a
    # prose block. In-text editorial markup: `note` is never text; `app`
    # reads its `lem` (a bare apparatus note reads nothing); `choice` reads
    # its `corr` (the editors' reading) or else its first child (the first
    # of several renderings in a translation); `gap` reads upstream's own
    # index sigil "‡"; everything else reads its text. The `-kilavi`/`-intro`
    # blocks are the poems' situation colophons (speaker, tiṇai/tuṟai) —
    # flagged `colophon`, their prose kept verbatim and NOT mined into
    # facets (an unruled prose parse).
    #
    # == The wordsplit standOff → gold tokens
    #
    # `standOff[@type=wordsplit][@corresp=#id]` segments its target unit
    # word by word. Each `entry` becomes one token in the P7-5 "tokens"
    # contract, following upstream's own indexer (lib/_indexer/todb.mjs)
    # exactly:
    #
    #   form        the split segment as upstream writes it (the first
    #               untyped `form`'s text, `pc[@type=ignored]` dropped)
    #   lemma       form[@type=simple] if present, else the form cleaned of
    #               inserted/glide/geminated `c` (elided vowels restored)
    #   gloss       the `def`
    #   sandhi      form[@type=sandhi] cleaned of uncertain/geminated/
    #               elided/glide `c` (only when present)
    #   roles       the gram[@type=role] values, verbatim, in order
    #   enclitic /  the gramGrp[@type=particle] `m` (proclitic only for
    #   proclitic   upstream's four proclitics when the form opens with it)
    #
    # A `superEntry` (always @type=ambiguous in the census) yields its FIRST
    # reading as tokens; every other reading rides that reading's first
    # token as `alternatives` — a list of token lists, since a reading may
    # split into several words. The lemma tier is gold (scholar-made
    # segmentation, never automatic). `standOff[@type=apparatus]` rides the
    # same passage as `apparatus` (loc, lemma + witnesses, readings);
    # `notes*` standOffs and the alignment `interp` are not carried.
    #
    # == Header mining
    #
    # titleStmt/title → document title (whitespace-collapsed) and its
    # parts: `work` (the inner title), `number` (`num`, else the bare
    # trailing number), `poet` (the attributed persName), `section` (the
    # chapter `term` or a second inner title); `editor` elements →
    # editors [{name, role}]; sourceDesc/listWit's top-level witnesses →
    # witnesses [{id, siglum, description}] verbatim (their years are
    # witness years — manuscripts and printed editions — never the work's
    # date). The work rides the `work` facet. No header carries a
    # composition date or place (census 2026-10-12).
    class TamilexTeiParser
      LANGUAGE = "tam-Latn"
      TAMIL_CODES = [nil, "", "ta", "ta-Latn", "tam", "tam-Latn"].freeze
      ENGLISH_CODES = %w[en eng].freeze
      BLOCKS = %w[lg p].freeze

      COLOPHON_ID = /-(?:kilavi|intro)\z/
      PROCLITICS = %w[amma koṉ maṟṟu yāḻa].freeze
      LEMMA_DROP = %w[inserted glide geminated].freeze
      SANDHI_DROP = %w[uncertain geminated elided glide].freeze
      GAP_SIGIL = "‡"
      TRAILING_NUMBER = /\A\s*([\d.–-]*\d)\.?/

      # One Tamil block on its way to a passage (node: the block, for the
      # English pairing).
      Unit = Data.define(:id, :text, :annotations, :node)

      # Parse +path+ into a Nabu::Document under +urn+.
      def parse(path, urn:, metadata: {})
        doc = read(path)
        header = header_metadata(doc)
        texts = doc.xpath("/TEI/text")
        tokens = wordsplits(doc)
        apparatus = apparatus_by_target(doc)
        commentaries = []
        units = texts.each_with_index.flat_map do |text, index|
          text_units(text, index, commentaries)
        end
        raise ParseError, "#{File.basename(path)}: no edition text (every block is empty)" if units.empty?

        header["commentaries"] = commentaries unless commentaries.empty?
        build(units, urn: urn, path: path, metadata: metadata.merge(header),
                     tokens: tokens, apparatus: apparatus)
      end

      private

      def read(path)
        doc = Nokogiri::XML(File.read(path, encoding: "UTF-8"), &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def build(units, urn:, path:, metadata:, tokens:, apparatus:)
        document = Document.new(urn: urn, language: LANGUAGE, title: metadata["title"],
                                canonical_path: path, metadata: metadata.except("title").compact)
        units.each_with_index do |unit, sequence|
          annotations = unit.annotations.dup
          annotations["tokens"] = tokens[unit.id] if tokens.key?(unit.id)
          annotations["apparatus"] = apparatus[unit.id] if apparatus.key?(unit.id)
          document << Passage.new(urn: "#{urn}:#{Normalize.nfc(unit.id)}", language: LANGUAGE,
                                  text: Normalize.nfc(unit.text), annotations: annotations,
                                  sequence: sequence)
        end
        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # -- the text walk --------------------------------------------------------

      def text_units(text, index, commentaries)
        commentator = index.zero? ? nil : squish(text.at_xpath("./body/head"))
        entry = commentator ? { "commentator" => commentator } : nil
        units = []
        ordinal = 0
        blocks(text).each do |block|
          language = block["lang"]
          if ENGLISH_CODES.include?(language)
            attach_english(block, units, entry)
          elsif TAMIL_CODES.include?(language)
            ordinal += 1
            unit = tamil_unit(block, index, ordinal, commentator)
            units << unit if unit
          else
            raise ParseError, "unknown block language #{language.inspect} on <#{block.name}>"
          end
        end
        commentaries << entry if entry
        units
      end

      # The outermost lg/p blocks of a text's body, in document order.
      def blocks(text)
        text.xpath(".//body//*[self::lg or self::p][not(ancestor::lg or ancestor::p)]" \
                   "[not(ancestor::note)]")
      end

      def tamil_unit(block, text_index, ordinal, commentator)
        content = block_text(block)
        return nil if content.empty?

        id = block["id"].to_s.strip
        id = "#{text_index + 1}.#{ordinal}" if id.empty?
        annotations = {}
        annotations["commentator"] = commentator if commentator
        annotations["colophon"] = true if id.match?(COLOPHON_ID)
        Unit.new(id: id, text: content, annotations: annotations, node: block)
      end

      # An English block translates the Tamil block it directly follows
      # (same parent); unpaired, it is the commentary's edition statement.
      def attach_english(block, units, entry)
        content = block_text(block)
        return if content.empty?

        previous = block.previous_element
        paired = units.reverse.find { |unit| unit.node == previous }
        if previous && paired
          paired.annotations["translation"] = Normalize.nfc(content)
        elsif entry
          entry["edition"] = [entry["edition"], Normalize.nfc(content)].compact.join(" ")
        end
      end

      def block_text(block)
        lines = block.name == "lg" ? block.xpath("./l") : []
        return lines.map { |line| squish_text(inline(line)) }.reject(&:empty?).join("\n") unless lines.empty?

        squish_text(inline(block))
      end

      def inline(node)
        node.children.map do |child|
          if child.text? || child.cdata? then child.text
          elsif child.element? then inline_element(child)
          else ""
          end
        end.join
      end

      def inline_element(node)
        case node.name
        when "note", "rdg", "interp" then ""
        when "app"
          lem = node.at_xpath("./lem")
          lem ? inline(lem) : ""
        when "choice"
          pick = node.at_xpath("./corr") || node.element_children.first
          pick ? inline(pick) : ""
        when "gap" then GAP_SIGIL * gap_quantity(node)
        when "lb", "pb" then " "
        else inline(node)
        end
      end

      def gap_quantity(node)
        quantity = node["quantity"].to_i
        quantity.positive? ? quantity : 1
      end

      # -- standOffs --------------------------------------------------------------

      # { unit id => [token, …] } from every wordsplit standOff.
      def wordsplits(doc)
        doc.xpath("//standOff[@type='wordsplit']").each_with_object({}) do |stand_off, map|
          target = target_id(stand_off) or next
          tokens = stand_off.element_children.flat_map { |child| split_tokens(child) }
          (map[target] ||= []).concat(tokens) unless tokens.empty?
        end
      end

      def split_tokens(node)
        case node.name
        when "entry" then [token(node)].compact
        when "superEntry" then ambiguous_tokens(node)
        else []
        end
      end

      # A superEntry's readings are wrapper entries holding the words.
      def ambiguous_tokens(node)
        readings = node.xpath("./entry").map do |wrapper|
          inner = wrapper.xpath("./entry")
          (inner.empty? ? [wrapper] : inner.to_a).filter_map { |entry| token(entry) }
        end.reject(&:empty?)
        return [] if readings.empty?

        first, *others = readings
        first.first["alternatives"] = others unless others.empty?
        first
      end

      def token(entry)
        form = entry.xpath("./form[not(@type)]").first or return nil
        result = { "form" => split_form(form) }
        simple = squish(entry.at_xpath("./form[@type='simple']"))
        result["lemma"] = simple || clean_form(form, LEMMA_DROP)
        gloss = squish(entry.at_xpath("./def"))
        result["gloss"] = Normalize.nfc(gloss) if gloss
        sandhi = entry.at_xpath("./form[@type='sandhi']")
        result["sandhi"] = clean_form(sandhi, SANDHI_DROP) if sandhi
        roles = entry.xpath("./gramGrp[not(@type)]/gram[@type='role']").filter_map { |gram| squish(gram) }
        result["roles"] = roles.map { |role| Normalize.nfc(role) } unless roles.empty?
        particle(entry, result)
        result.transform_values { |value| value.is_a?(String) ? Normalize.nfc(value) : value }
      end

      def particle(entry, result)
        clitic = squish(entry.at_xpath("./gramGrp[@type='particle']/m"))
        return unless clitic

        proclitic = PROCLITICS.include?(clitic) && result["lemma"].start_with?("#{clitic}-")
        result[proclitic ? "proclitic" : "enclitic"] = clitic
      end

      # upstream's cleanOne: the segment text, ignored punctuation dropped.
      def split_form(form)
        copy = form.dup
        copy.xpath(".//pc[@type='ignored']").each(&:remove)
        copy.text.strip
      end

      # upstream's cleanForm: gaps → ‡, the listed c types removed,
      # uncertain c parenthesized, then (u)/(i) → u and +/~ dropped.
      def clean_form(form, drop)
        copy = form.dup
        copy.xpath(".//gap").each { |gap| gap.replace(GAP_SIGIL * gap_quantity(gap)) }
        copy.xpath(".//c").each do |c|
          if drop.include?(c["type"]) then c.remove
          elsif c["type"] == "uncertain" then c.replace("(#{c.text})")
          end
        end
        copy.text.strip.gsub(/\([ui]\)/, "u").delete("+~")
      end

      # { unit id => [app, …] } from every apparatus standOff.
      def apparatus_by_target(doc)
        doc.xpath("//standOff[@type='apparatus']").each_with_object({}) do |stand_off, map|
          target = target_id(stand_off) or next
          apps = stand_off.xpath(".//listApp/app").map { |app| app_entry(app) }
          (map[target] ||= []).concat(apps) unless apps.empty?
        end
      end

      def app_entry(app)
        lem = app.at_xpath("./lem")
        entry = { "loc" => app["loc"] }
        entry["lemma"] = Normalize.nfc(squish_text(inline(lem))) if lem
        entry["witnesses"] = sigla(lem["wit"]) if lem && lem["wit"]
        entry["readings"] = app.xpath("./rdg").map do |rdg|
          { "text" => Normalize.nfc(squish_text(inline(rdg))), "witnesses" => sigla(rdg["wit"]) }
        end
        entry.compact
      end

      def sigla(value)
        value.to_s.split.map { |siglum| Normalize.nfc(siglum.delete_prefix("#")) }
      end

      def target_id(stand_off)
        id = stand_off["corresp"].to_s.strip.delete_prefix("#")
        id.empty? ? nil : id
      end

      # -- header -------------------------------------------------------------------

      def header_metadata(doc)
        title = doc.at_xpath("/TEI/teiHeader/fileDesc/titleStmt/title")
        metadata = title_parts(title)
        editors = doc.xpath("/TEI/teiHeader/fileDesc/titleStmt/editor").filter_map { |editor| editor_entry(editor) }
        metadata["editors"] = editors unless editors.empty?
        witnesses = doc.xpath("/TEI/teiHeader/fileDesc/sourceDesc/listWit/witness").map { |w| witness(w) }
        metadata["witnesses"] = witnesses unless witnesses.empty?
        metadata["facets"] = { "work" => { "value" => metadata["work"] } } if metadata["work"]
        metadata
      end

      def title_parts(title)
        return {} unless title

        work = title.at_xpath("./title")
        parts = { "title" => nfc_or_nil(squish(title)), "work" => nfc_or_nil(squish(work)) }
        parts["number"] = squish(title.at_xpath("./num")) || trailing_number(work)
        parts["poet"] = nfc_or_nil(squish(title.at_xpath("./persName")))
        section = title.at_xpath("./term") || title.xpath("./title")[1]
        parts["section"] = nfc_or_nil(squish(section))
        parts.compact
      end

      def trailing_number(work)
        following = work&.next_sibling
        return nil unless following&.text?

        following.text[TRAILING_NUMBER, 1]
      end

      def editor_entry(editor)
        name = squish(editor.at_xpath("./persName")) || squish(editor)
        return nil unless name

        { "name" => Normalize.nfc(name), "role" => editor["role"] }.compact
      end

      def witness(node)
        {
          "id" => node["id"],
          "siglum" => nfc_or_nil(squish(node.at_xpath("./abbr"))),
          "description" => nfc_or_nil(squish(node.at_xpath("./expan")))
        }.compact
      end

      def nfc_or_nil(value)
        value && Normalize.nfc(value)
      end

      def squish(node)
        return nil if node.nil?

        value = squish_text(node.text)
        value.empty? ? nil : value
      end

      # Collapse whitespace; strip edge format characters (a stray ZWJ
      # after a block's last word, PN2-intro) with it.
      def squish_text(value)
        value.gsub(/[[:space:]]+/, " ").gsub(/\A[\s\p{Cf}]+|[\s\p{Cf}]+\z/, "")
      end
    end
  end
end
