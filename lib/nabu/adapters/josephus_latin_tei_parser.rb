# frozen_string_literal: true

require "nokogiri"

require_relative "celtic_leiden"

module Nabu
  module Adapters
    # The `josephus-latin-tei` parser family: the Latin Josephus Project's
    # production TEI (latinjosephus.org v3.0, the Zenodo core deposit) — one
    # file per book of the Latin Antiquitates, Bellum, Contra Apionem and
    # De excidio. A bespoke family: the project's own encoding (the
    # FairCopy spec it names) shares no reading-TEI family's citation
    # ladder, and its two annotation layers (inline witness <note>s and the
    # standOff <listApp> keyed to paragraph ids) are its own. Files are
    # ≤ 300 KB, so DOM, not the >5 MB Reader rule.
    #
    # == Reading units
    #
    # A unit is every <p>, <head> and <trailer> under the text's body that
    # is not itself inside another unit, in document order — including the
    # ones nested in <argument>/<floatingText> (Antiquities XI and XIV wrap
    # their whole running text that way) and the id-less capitula and
    # incipit rubrics of the Bamberg books. The body-level <note> (the
    # witness label: "Bamberg Msc. Class. 78", "Boysen, CSEL 37 …") is not
    # a unit; it rides as the file's witness.
    #
    # Unit ref: a <p>'s xml:id minus the redundant file prefix
    # (latin-book01-num27 → num27, latin-deh2-num1 → num1); an id-less unit
    # is positional per element name (p1, head1, trailer1). Units whose
    # reading text is empty (an empty <p/>) are not emitted.
    #
    # == Reading text (canonical means canonical)
    #
    # Text nodes concatenate verbatim, whitespace runs squeezed — upstream's
    # own editorial brackets ("[add]", "[si]") stay in the text. Page,
    # column and line breaks (<pb>/<cb>/<lb>) contribute nothing (they sit
    # word-internally: "Ro<pb n="4"/>manos"); <del> is kept inside the house
    # erasure brackets ⟦…⟧, <gap> renders the house lacuna marker […]
    # (both CelticLeiden's vocabulary); <add>, <corr>, <expan>, <supplied>,
    # <unclear>, <foreign> read through. Out of the text, into annotations:
    #
    #   "citation"        <num> — the reader's label ("I.i.27", "II.1.1")
    #   "niese"           every <milestone unit="niese" n> inside the unit
    #   "pb"              every page/folio break inside the unit
    #   "ms_annotations"  the early-medieval manuscript annotations: inline
    #                     <note> (witness @source, @type) plus the standOff
    #                     <app> readings whose first <rdg> points at the
    #                     unit's xml:id ({"witness", "type", "text"}; a
    #                     standOff copy of an inline note is folded once)
    #   "upstream_id"     the unit's xml:id, verbatim
    class JosephusLatinTeiParser
      TEI_NS = "http://www.tei-c.org/ns/1.0"
      XML_NS = "http://www.w3.org/XML/1998/namespace"

      UNIT_NAMES = %w[p head trailer].freeze

      # The file-scoped xml:id prefix a <p> id carries (latin-book01-,
      # latin-bellum7-, latin-apion2-, latin-deh2-, latin-preface-).
      ID_PREFIX = /\Alatin-[a-z]+\d*-/

      # Inline elements whose content is OUT of the reading text.
      SILENT = %w[pb cb lb milestone anchor note num].freeze

      Unit = Data.define(:ref, :name, :text, :annotations)
      Result = Data.define(:title, :witness, :witnesses, :units)

      def parse(path)
        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "josephus-latin TEI"), &:strict)
        body = doc.at_xpath("/t:TEI/t:text/t:body", "t" => TEI_NS) or
          raise ParseError, "#{path}: no TEI text body"

        Result.new(
          title: squeeze(doc.at_xpath("//t:titleStmt/t:title", "t" => TEI_NS)&.text),
          witness: squeeze(body.at_xpath("t:note", "t" => TEI_NS)&.text),
          witnesses: witnesses(doc),
          units: units(body, apparatus(doc))
        )
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML — #{e.message}"
      end

      private

      # The header's listWit: witness xml:id → label (the sigla the
      # annotations name).
      def witnesses(doc)
        doc.xpath("//t:listWit/t:witness", "t" => TEI_NS).to_h do |w|
          [xml_id(w), squeeze(w.text)]
        end
      end

      # standOff <app>s: the first <rdg>'s @source names the unit
      # ("#latin-book02-num1", its text a cue); every further <rdg> is one
      # witness's annotation of that unit.
      def apparatus(doc)
        doc.xpath("//t:standOff//t:app", "t" => TEI_NS).each_with_object(Hash.new { |h, k| h[k] = [] }) do |app, map|
          target, *readings = app.xpath("t:rdg", "t" => TEI_NS).to_a
          next if target.nil?

          key = target["source"].to_s.delete_prefix("#")
          readings.each do |rdg|
            map[key] << { "witness" => rdg["source"].to_s.delete_prefix("#"), "text" => squeeze(rdg.text) }
          end
        end
      end

      def units(body, apparatus)
        ordinals = Hash.new(0)
        seen = Hash.new(0)
        body.xpath(".//t:p|.//t:head|.//t:trailer", "t" => TEI_NS).filter_map do |elem|
          next if elem.ancestors.any? { |a| a.is_a?(Nokogiri::XML::Element) && UNIT_NAMES.include?(a.name) }

          unit(elem, apparatus, ordinals, seen)
        end
      end

      def unit(elem, apparatus, ordinals, seen)
        id = xml_id(elem)
        ref = base_ref(elem, id, ordinals)
        count = (seen[ref] += 1)
        ref = "#{ref}:b#{count}" if count > 1
        layers = { "niese" => [], "pb" => [], "ms_annotations" => [] }
        text = squeeze(render(elem, layers))
        return nil if text.empty?

        merge_apparatus(layers["ms_annotations"], apparatus.fetch(id, [])) if id
        Unit.new(ref: ref, name: elem.name, text: text, annotations: annotations(layers, id))
      end

      # The standOff often repeats an inline <note> verbatim (same witness,
      # same text): one record per (witness, text), the inline one (which
      # carries @type) kept.
      def merge_apparatus(notes, readings)
        seen = notes.to_set { |n| [n["witness"], n["text"]] }
        readings.each { |r| notes << r if seen.add?([r["witness"], r["text"]]) }
      end

      def base_ref(elem, id, ordinals)
        return id.sub(ID_PREFIX, "") if elem.name == "p" && id

        "#{elem.name}#{ordinals[elem.name] += 1}"
      end

      def annotations(layers, id)
        {
          "citation" => layers["citation"],
          "niese" => (layers["niese"] unless layers["niese"].empty?),
          "pb" => (layers["pb"] unless layers["pb"].empty?),
          "ms_annotations" => (layers["ms_annotations"] unless layers["ms_annotations"].empty?),
          "upstream_id" => id
        }.compact
      end

      # The reading text of +node+'s children, side layers collected.
      def render(node, layers)
        node.children.map do |child|
          case child
          when Nokogiri::XML::Text then child.text
          when Nokogiri::XML::Element then element(child, layers)
          else ""
          end
        end.join
      end

      def element(elem, layers)
        case elem.name
        when "del"
          "#{CelticLeiden::CANCELLATION_OPEN}#{render(elem, layers)}#{CelticLeiden::CANCELLATION_CLOSE}"
        when "gap" then CelticLeiden::GAP_MARKER
        when *SILENT
          side_layer(elem, layers)
          ""
        else render(elem, layers)
        end
      end

      def side_layer(elem, layers)
        case elem.name
        when "num" then layers["citation"] ||= squeeze(elem.text).delete_prefix("[").delete_suffix("]")
        when "milestone" then layers["niese"] << elem["n"] if elem["unit"] == "niese" && elem["n"]
        when "pb" then layers["pb"] << elem["n"] if elem["n"]
        when "note" then layers["ms_annotations"] << note(elem)
        end
      end

      def note(elem)
        { "witness" => elem["source"]&.delete_prefix("#"), "type" => elem["type"],
          "text" => squeeze(elem.text) }.compact
      end

      def xml_id(elem)
        elem.attribute_with_ns("id", XML_NS)&.value
      end

      def squeeze(text)
        return "" if text.nil?

        Normalize.nfc(text).gsub(/[[:space:]]+/, " ").strip
      end
    end
  end
end
