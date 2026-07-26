# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser for one Beta maṣāḥǝft Works TEI record (P46-2) — the
    # `betamasaheft-tei` family. A BM record is a WORK-level authority file
    # whose optional <div type="edition"> carries the transcription; this
    # parser reads exactly that div and mines the teiHeader for identity,
    # attribution and the D46-a in-file licence.
    #
    # == The citation scheme (upstream-first, positionally backstopped)
    #
    #   <div-path>.<unit-token>
    #
    # - div-path: each textpart <div> under the edition contributes ONE
    #   component — its @n verbatim when present (the chapter number:
    #   Mark's `subtype="chapter" n="1"` reads "1"), else its @xml:id (the
    #   editor's own anchor: "BiographyMark"), else "d<k>" positional among
    #   its sibling divs. The edition div itself contributes nothing.
    # - unit-token: a reading unit is a verse line <l>, or a prose block
    #   <ab>/<p> that contains no <l> descendants (Mark wraps a chapter's
    #   lines in one <ab> — that <ab> is a transparent container, not a
    #   unit). A numbered <l n="…"> takes its @n verbatim (the VERSE grain:
    #   urn:nabu:betamasaheft-works:LIT2711Mark:1.1); an unnumbered unit
    #   takes "<tag><k>", k a 1-based per-div per-kind ordinal consumed
    #   only by emitted units — Mark's unnumbered rubric lines read 1.l1,
    #   1.l2 and can never shadow a verse number.
    #   Residual duplicates disambiguate positionally (":b2", the house
    #   ddbdp/GRETIL precedent), never quarantine.
    #
    # == Text discipline (canonical means canonical)
    #
    # A unit's text is its subtree flattened with <note>, <label>, in-body
    # <title>, <listBibl>/<bibl> and <ref> subtrees dropped (apparatus and
    # empty verse pointers); <lb>/<pb>/<milestone>/<gap> leave one space.
    # Whitespace collapses, ends strip, output is NFC (a verified no-op on
    # Ethiopic — no precomposed forms exist). A unit is EMITTED only when
    # its flattened text carries Ethiopic script (>= 1 \p{Ethiopic}): the
    # Gǝʿǝz shelf's text-bearing rule, which also drops stray Latin cruft
    # without consuming ordinals. Zero emitted units → Nabu::DocumentSkipped
    # (a record whose edition holds only labels/foreign text — the quiet
    # skip lane, not a quarantine).
    #
    # == Language
    #
    # The edition div's @xml:lang, mapped {gez→gez, am→amh}; anything else —
    # including the records that mislabel Gǝʿǝz content "en" (LIT0017MMDZ,
    # fixture-pinned) and editions with no @xml:lang at all — falls back to
    # gez, the corpus default. Only Ethiopic-script units are emitted, so
    # the fallback can never label Latin-script text gez.
    #
    # == DOM, deliberately
    #
    # The largest text-bearing record upstream is ~1.1 MB (the Susǝnyos
    # chronicle) — under the house >5 MB SAX threshold — and the div/unit
    # decisions (an <ab> is a unit iff it has no <l> descendants) are
    # lookahead-shaped, so a DOM walk is the simple, honest fit.
    class BetamasaheftTeiParser
      DROPPED_ELEMENTS = %w[note label title listBibl bibl ref].freeze
      SEPARATOR_ELEMENTS = %w[lb pb milestone gap].freeze
      VERSE_UNIT = "l"
      PROSE_UNITS = %w[ab p].freeze
      private_constant :DROPPED_ELEMENTS, :SEPARATOR_ELEMENTS, :VERSE_UNIT, :PROSE_UNITS

      ETHIOPIC = /\p{Ethiopic}/
      LANGUAGE_BY_EDITION_LANG = { "gez" => "gez", "am" => "amh", "amh" => "amh" }.freeze
      DEFAULT_LANGUAGE = "gez"

      # One emitted unit: citation suffix, flattened text, annotations.
      Unit = Data.define(:citation, :text, :annotations)
      private_constant :Unit

      def parse(path, urn:)
        doc = read_xml(path)
        edition = find_edition(doc) or
          raise DocumentSkipped, "#{path}: no <div type=\"edition\"> — a catalog-only record"
        units = collect_units(edition)
        raise DocumentSkipped, "#{path}: edition carries no Ethiopic reading text" if units.empty?

        build_document(disambiguate_collisions(units), doc: doc, edition: edition,
                                                       urn: urn, path: path)
      end

      private

      def read_xml(path)
        Nokogiri::XML(File.read(path), &:strict)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def find_edition(doc)
        doc.at_xpath("//*[local-name()='text']//*[local-name()='div'][@type='edition']")
      end

      def language_for(edition)
        LANGUAGE_BY_EDITION_LANG.fetch(edition["xml:lang"], DEFAULT_LANGUAGE)
      end

      # -- the edition walk ---------------------------------------------------

      def collect_units(edition)
        units = []
        walk(edition, [new_frame(nil, nil)], units)
        units
      end

      def new_frame(component, subtype)
        { component: component, subtype: subtype, child_divs: 0, ordinals: Hash.new(0) }
      end

      def walk(element, frames, units)
        element.element_children.each do |child|
          name = child.name
          next if DROPPED_ELEMENTS.include?(name)

          case name
          when "div" then walk_div(child, frames, units)
          when VERSE_UNIT then emit_unit(child, frames, units)
          when *PROSE_UNITS then prose_or_container(child, frames, units)
          else walk(child, frames, units)
          end
        end
      end

      def walk_div(div, frames, units)
        parent = frames.last
        parent[:child_divs] += 1
        component = presence(div["n"]) || presence(div["xml:id"]) || "d#{parent[:child_divs]}"
        frames.push(new_frame(component, presence(div["subtype"])))
        walk(div, frames, units)
        frames.pop
      end

      # An <ab>/<p> holding <l> descendants is a transparent container (Mark
      # wraps each chapter's verse lines in one <ab>); otherwise it is a
      # prose unit of its own.
      def prose_or_container(element, frames, units)
        if element.xpath(".//*[local-name()='l']").empty?
          emit_unit(element, frames, units)
        else
          walk(element, frames, units)
        end
      end

      def emit_unit(element, frames, units)
        text = Normalize.nfc(flatten_text(element).gsub(/[[:space:]]+/, " ").strip)
        return unless text.match?(ETHIOPIC)

        frame = frames.last
        n = presence(element["n"])
        token = n || "#{element.name}#{frame[:ordinals][element.name] += 1}"
        path = frames.filter_map { |f| f[:component] }.join(".")
        units << Unit.new(
          citation: path.empty? ? token : "#{path}.#{token}",
          text: text,
          annotations: {
            "addressing" => "textpart",
            "unit" => element.name,
            "subtype" => frame[:subtype],
            "n" => n
          }.compact
        )
      end

      def flatten_text(element)
        buffer = +""
        element.children.each do |child|
          if child.text? || child.cdata?
            buffer << child.text
          elsif child.element? && !DROPPED_ELEMENTS.include?(child.name)
            buffer << " " if SEPARATOR_ELEMENTS.include?(child.name)
            buffer << flatten_text(child)
          end
        end
        buffer
      end

      # The house collision tolerance: duplicates disambiguate
      # deterministically in document order.
      def disambiguate_collisions(units)
        seen = Hash.new(0)
        units.map do |unit|
          seen[unit.citation] += 1
          count = seen[unit.citation]
          count == 1 ? unit : unit.with(citation: "#{unit.citation}:b#{count}")
        end
      end

      # -- header metadata ----------------------------------------------------

      def build_document(units, doc:, edition:, urn:, path:)
        language = language_for(edition)
        document = Document.new(urn: urn, language: language, title: header_title(doc),
                                canonical_path: path, metadata: header_metadata(doc))
        units.each_with_index do |unit, sequence|
          document << Passage.new(
            urn: "#{urn}:#{unit.citation}", language: language, text: unit.text,
            annotations: unit.annotations, sequence: sequence
          )
        end
        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      def title_stmt_titles(doc)
        doc.xpath("//*[local-name()='titleStmt']/*[local-name()='title']")
      end

      # The English main title when the record marks one, else the first
      # untyped title (the OT records), else the first title at all.
      def header_title(doc)
        titles = title_stmt_titles(doc)
        main = titles.find { |t| t["type"] == "main" } ||
               titles.find { |t| t["type"].nil? } || titles.first
        main && presence(flat(main.text))
      end

      def header_metadata(doc)
        licence = doc.at_xpath("//*[local-name()='availability']/*[local-name()='licence']")
        gez_title = title_stmt_titles(doc).find { |t| t["xml:lang"] == "gez" && t["type"].nil? }
        edition_stmt = doc.at_xpath("//*[local-name()='editionStmt']")
        {
          "title_gez" => gez_title && presence(flat(gez_title.text)),
          "attribution" => edition_stmt && presence(flat(edition_stmt.text)),
          "licence_target" => licence && presence(licence["target"]),
          "licence_statement" => licence && presence(flat(licence.text))
        }.compact
      end

      def flat(text)
        text.gsub(/[[:space:]]+/, " ").strip
      end

      def presence(value)
        value if value && !value.empty?
      end
    end
  end
end
