# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser family `ollett-tei` (P118-3): the hand-structured TEI P5
    # editions Andrew Ollett publishes for the Kannada Digital Texts Project
    # (github.com/aso2101/kannada_texts) and the Prakrit Digital Texts
    # Project (github.com/aso2101/prakrit_texts) — one encoder, one
    # convention set, two corpora. A SIBLING of the SARIT family (same
    # editorial world, same cRefPattern idiom: //div[@n]/lg[@n]), not a
    # reuse of it: these files carry what SaritParser never had to — the
    # meter on every stanza (`lg/@met`, or a preceding `label
    # type="metrical"`), per-element language switches (Sanskrit chāyā,
    # commentary, Kannada example lists inside Sanskrit sūtras), witness
    # apparatus (`app/lem/rdg`) and the abbreviation `choice`s of the
    # Jaina commentaries. Same call shape as the other families:
    # #parse(path, urn:, default_language:, language_overrides:, refine:).
    #
    # == Unit grain (whole-corpus census 2026-10-11, 16 + 33 files)
    #
    # A passage is a VERSE GROUP (`lg` whose children are lines — its
    # `l`s joined by a NEWLINE — the line is the encoding's own boundary:
    # the Kannada prāsa lines break mid-word, so a joining space would
    # invent word breaks), a standalone `l`,
    # a PROSE block (`p`, `ab` — the sūtra blocks of the grammars — or a
    # block-level `list`, items joined by "; "), or a `trailer` (the
    # chapter colophons: text of the work, kept). An `lg` that wraps
    # further `lg`s (Sētubandha's kulakas) is a transparent container.
    # `<back>` is text too (appendix gāthās) and cites under a "back."
    # prefix. Inside an open unit everything nested is reading text: inline
    # quotes, nested stanzas in commentary sentences, `s`/`seg`/`foreign`.
    #
    # == Citation (FROZEN minting)
    #
    # The dotted `div/@n` path + the unit's own `@n` — upstream's
    # cRefPattern exactly (`Ādi.1.25` → `1.25`, `GāSa.12` → `12`,
    # `DēNāMā.1.1` base-text stanza → `1.1.1`), addressing "attribute".
    # An unnumbered unit takes a div-scoped ordinal (`v<k>` verse, `p<k>`
    # prose/list, `tr<k>` trailer — addressing "ordinal", non-canonical,
    # the GRETIL/SARIT precedent); n-less divs are transparent and do NOT
    # reset the counters (Tārāgaṇa's twenty n-less sections would
    # otherwise collide). A residual duplicate disambiguates positionally
    # (":b2", ":b3" — the ddbdp/GRETIL/SARIT house rule), never quarantines.
    #
    # == Annotations
    #
    # addressing; `met` (the unit's @met, else the nearest ancestor's, else
    # a preceding `label type="metrical"` — Janna/Ranna encode meter that
    # way); `label` (labels inside or just before the unit, verbatim —
    # "va." marks Kannada prose, Prakrit `bb` labels give the commentary
    # source); `chaya` (a `note type="chāyā"` inside the unit — the
    # Sanskrit shadow translation of Gaüḍavaho, kept OUT of the reading
    # text); `page` (the running `pb/@n` without @ed at the unit's start;
    # `pages` carries the edition-keyed breaks, Tārāgaṇa's `ed="bh"`);
    # `head` (the enclosing div's head); `base_text` (inside a
    # `quote type="base-text"` — the mūla of a commented work); `type`
    # (the unit's @type: sūtra, example, stanza); `lines`.
    #
    # == Text discipline
    #
    # Dropped: `note` subtrees (footnotes, apparatus; the chāyā moves to
    # annotations), `head`/`label` inside units (moved to annotations),
    # `rdg` (the lemma reading is the text — `app` keeps its `lem`),
    # `fw`/`figure`. `choice` keeps `expan`/`corr`/`reg`; `lb break="no"`
    # and `pb break="no"` join, other `lb`/`pb`/`caesura`/`milestone` are a
    # space. Source whitespace collapses to one space within a line; the
    # only newlines are `l` boundaries. NFC at the boundary.
    #
    # == Language (the unknown-code net)
    #
    # Document: the caller's override keyed by the work's siglum (a
    # censused upstream defect) →
    # `text/@xml:lang` → `body/@xml:lang` → the caller's default. Passage:
    # the nearest ancestor-or-self `xml:lang` inside the body, else the
    # document's. Every code passes the caller's ALLOWED set (after its
    # censused aliases) or the document refuses to load — the DHARMA net.
    #
    # == License gate
    #
    # The in-file `<availability>` grant is re-verified per document against
    # the caller's recognized grants (URL target or prose) and recorded
    # verbatim (`license_statement` = authority + availability prose). An
    # absent grant — the Śvētāmbara Āgama template comment "add whatever
    # license you like" — or an unrecognized one is a ParseError.
    #
    # == DOM
    #
    # The largest file in either corpus is 1.36 MB (Paümacariya, census
    # 2026-10-11) — far under the house 5 MB streaming threshold, and the
    # walk needs ancestor context (language, meter), so this family reads
    # the DOM.
    class OllettTeiParser
      TEI_NS = "http://www.tei-c.org/ns/1.0"
      XML_NS = "http://www.w3.org/XML/1998/namespace"
      NS = { "t" => TEI_NS }.freeze

      VERSE = :verse
      PROSE = :prose
      TRAILER = :trailer
      ORDINAL_PREFIX = { VERSE => "v", PROSE => "p", TRAILER => "tr" }.freeze

      # Dropped wholesale wherever met (inside or outside units).
      DROPPED = %w[note fw figure rdg].freeze

      # A `break="no"` lb/pb: a sentinel that swallows the source
      # indentation around it at collapse time (the word continues).
      JOIN = "\u0001"

      # The preferred member of a <choice>.
      CHOICE_PREFERENCE = %w[expan corr reg].freeze

      Unit = Data.define(:citation, :text, :language, :annotations)
      private_constant :Unit

      # +allowed+: the censused language codes; +aliases+: censused upstream
      # tag dirt → held code; +grants+: { pattern => label } matched against
      # the availability's ref targets and prose.
      def initialize(allowed:, grants:, aliases: {})
        @allowed = allowed
        @aliases = aliases
        @grants = grants
      end

      # Resolve a raw xml:lang through the aliases and the allowed set; raise
      # the unknown-code net otherwise.
      def resolve_language(code, path:)
        resolved = @aliases.fetch(code, code)
        return resolved if @allowed.include?(resolved)

        raise ParseError, "#{File.basename(path)}: unknown language code #{code.inspect} — " \
                          "classify it before ingesting"
      end

      # +refine+ receives the mined metadata hash and returns the one the
      # Document carries (the adapter's censused corrections and attributed
      # dates); nil values drop their key.
      def parse(path, urn:, default_language:, language_overrides: {}, refine: nil)
        xml = read(path)
        header = Header.new(xml, path: path, grants: @grants)
        license = header.license!
        declared = language_overrides[header.siglum] || header.text_language || default_language
        language = resolve_language(declared, path: path)
        units = Walk.new(xml, path: path, language: language, resolver: ->(code) { resolve_language(code, path: path) })
                    .call
        metadata = header.metadata.merge(license).merge("text_languages" => census(units))
        metadata = refine.call(metadata) if refine
        build(units, urn: urn, language: language, path: path, metadata: metadata)
      end

      # Whitespace-collapsed text of a node (header fields).
      def self.squish(node)
        node.nil? ? nil : presence(node.text.gsub(/[[:space:]]+/, " ").strip)
      end

      def self.presence(value)
        value.nil? || value.empty? ? nil : value
      end

      def self.lang_of(node)
        node.attribute_with_ns("lang", XML_NS)&.value
      end

      private

      # Strict: a not-well-formed file quarantines loudly. No markup repair
      # is attempted — the one census case (ācāraniryukti, 2026-10-11: an
      # unclosed start tag, bare "<|75.|>" markers, lines without <l>) is a
      # work in progress whose repair would be guesswork.
      def read(path)
        Nokogiri::XML(File.read(path, encoding: "UTF-8"), &:strict)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def census(units)
        units.map(&:language).tally.sort.to_h
      end

      def build(units, urn:, language:, path:, metadata:)
        document = Document.new(urn: urn, language: language, title: metadata["title"], canonical_path: path,
                                metadata: metadata.compact)
        seen = Hash.new(0)
        units.each_with_index do |unit, sequence|
          seen[unit.citation] += 1
          citation = seen[unit.citation] == 1 ? unit.citation : "#{unit.citation}:b#{seen[unit.citation]}"
          document << Passage.new(urn: "#{urn}:#{citation}", language: unit.language,
                                  text: Normalize.nfc(unit.text), annotations: unit.annotations,
                                  sequence: sequence)
        end
        raise ParseError, "#{path}: no citable passages found in <text><body>" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The teiHeader reading: identity, the grant, the source edition.
      class Header
        def initialize(xml, path:, grants:)
          @xml = xml
          @path = path
          @grants = grants
        end

        # The TEI root's @n is the work's citation siglum (Ādi, GāSa, Āyār).
        def siglum
          OllettTeiParser.presence(at("/t:TEI")&.[]("n").to_s.strip)
        end

        def text_language
          text = at("/t:TEI/t:text")
          text && (OllettTeiParser.lang_of(text) || body_language(text))
        end

        # The per-file grant gate: { "license", "license_statement",
        # "license_url" } or a ParseError.
        def license!
          availability = at("//t:teiHeader//t:publicationStmt/t:availability")
          prose = OllettTeiParser.squish(availability)
          targets = availability ? availability.xpath(".//t:ref/@target | .//t:licence/@target", NS).map(&:value) : []
          label = match_grant(targets, prose.to_s)
          unless label
            detail = prose ? "unrecognized grant #{prose.inspect}" : "no grant in <availability> (template comment)"
            raise ParseError, "#{File.basename(@path)}: license gate: #{detail}"
          end
          authority = OllettTeiParser.squish(at("//t:teiHeader//t:publicationStmt/t:authority"))
          { "license" => label,
            "license_statement" => [authority&.sub(/\.?\z/, "."), prose].compact.join(" "),
            "license_url" => targets.first }
        end

        def metadata
          titles = titles_in("//t:teiHeader/t:fileDesc/t:titleStmt/t:title")
          {
            "title" => main_title(titles),
            "titles" => titles.empty? ? nil : titles,
            "author" => authors.first,
            "authors" => authors.size > 1 ? authors : nil,
            "siglum" => siglum,
            "digital_edition_date" => OllettTeiParser.squish(at("//t:teiHeader//t:publicationStmt/t:date")),
            "source_edition" => source_edition,
            "source_note" => source_note,
            "languages_declared" => languages_declared,
            "refs_pattern" => at("//t:teiHeader//t:refsDecl/t:cRefPattern")&.[]("matchPattern")
          }.compact
        end

        private

        def at(xpath)
          @xml.at_xpath(xpath, NS)
        end

        def body_language(text)
          body = text.at_xpath("t:body", NS)
          body && OllettTeiParser.lang_of(body)
        end

        def match_grant(targets, prose)
          targets.each do |target|
            @grants.each { |pattern, label| return label if pattern.match?(target) }
          end
          @grants.each { |pattern, label| return label if pattern.match?(prose) }
          nil
        end

        def titles_in(xpath)
          @xml.xpath(xpath, NS).filter_map do |node|
            text = OllettTeiParser.squish(node)
            next unless text

            { "text" => text, "lang" => OllettTeiParser.lang_of(node), "type" => node["type"] }.compact
          end
        end

        def main_title(titles)
          (titles.find { |t| t["type"] == "main" } || titles.first)&.fetch("text")
        end

        def authors
          @authors ||= @xml.xpath("//t:teiHeader/t:fileDesc/t:titleStmt/t:author", NS)
                           .filter_map { |node| OllettTeiParser.squish(node) }
        end

        def languages_declared
          idents = @xml.xpath("//t:teiHeader//t:langUsage/t:language/@ident", NS).map(&:value)
          idents.empty? ? nil : idents
        end

        # The printed edition the digital text is based on, from the first
        # monogr/bibl in sourceDesc — title(s), editors, imprint.
        def source_edition
          source = at("//t:teiHeader//t:sourceDesc")
          return nil unless source

          monogr = source.at_xpath(".//t:monogr", NS) || source.at_xpath(".//t:bibl", NS)
          return nil unless monogr

          {
            "title" => OllettTeiParser.squish(monogr.at_xpath("t:title", NS) || monogr.at_xpath(".//t:title", NS)),
            "editors" => names(monogr.xpath(".//t:editor", NS)),
            "authors" => names(monogr.xpath("./t:author", NS)),
            "publisher" => OllettTeiParser.squish(monogr.at_xpath(".//t:publisher", NS)),
            "pub_place" => OllettTeiParser.squish(monogr.at_xpath(".//t:pubPlace", NS)),
            "date" => OllettTeiParser.squish(monogr.at_xpath(".//t:date", NS)),
            "series" => OllettTeiParser.squish(source.at_xpath(".//t:series/t:title | .//t:title[@level='s']", NS)),
            "idnos" => idnos(source)
          }.compact.then { |hash| hash.key?("title") ? hash : nil }
        end

        def names(nodes)
          list = nodes.filter_map do |node|
            # Forenames first whatever the encoding order (Pischel's record
            # puts <surname> before <forename>).
            parts = %w[forename surname].flat_map do |name|
              node.xpath(".//t:#{name}", NS).map { |part| part.text.strip }
            end
            OllettTeiParser.presence(parts.empty? ? node.text.gsub(/[[:space:]]+/, " ").strip : parts.join(" "))
          end
          list.empty? ? nil : list
        end

        def idnos(source)
          pairs = source.xpath(".//t:idno", NS).filter_map do |node|
            value = node.text.strip
            [node["type"] || "id", value] unless value.empty?
          end
          pairs.empty? ? nil : pairs.to_h
        end

        # Prose source statements (the Āgama DOCX provenance, GRETIL
        # lineage, the MCLI reduction note).
        def source_note
          paras = @xml.xpath("//t:teiHeader//t:sourceDesc/t:p | //t:teiHeader//t:sourceDesc/t:head", NS)
                      .filter_map { |node| OllettTeiParser.squish(node) }
          paras.empty? ? nil : paras.join(" ")
        end
      end
      private_constant :Header

      # The body walk: containers recurse, units extract.
      class Walk
        def initialize(xml, path:, language:, resolver:)
          @xml = xml
          @path = path
          @language = language
          @resolver = resolver
          @frames = [frame(nil, nil)]
          @page = nil
          @pages = {}
          @pending_labels = []
          @units = []
        end

        def call
          body = @xml.at_xpath("/t:TEI/t:text/t:body", NS)
          raise ParseError, "#{File.basename(@path)}: no <text><body> found" unless body

          walk(body, base_text: false)
          walk_back
          @units
        end

        # <back> carries text of the edition too (Vajjālagga's additional
        # gāthās of MS. C, the Nandī's anuṇṇā appendices): walked under a
        # "back" path component so its numbering never meets the body's.
        def walk_back
          back = @xml.at_xpath("/t:TEI/t:text/t:back", NS)
          return unless back

          @frames << frame("back", nil)
          @pending_labels = []
          walk(back, base_text: false)
          @frames.pop
        end

        private

        def frame(component, head)
          { component: component, head: head, counters: Hash.new(0) }
        end

        def walk(container, base_text:)
          container.element_children.each do |child|
            case child.name
            when "div" then walk_div(child, base_text: base_text)
            when "head", "lb", "cb", "milestone", "caesura", *DROPPED then nil
            when "pb" then page_break(child)
            when "label" then @pending_labels << child
            when "lg" then container_lg?(child) ? walk(child, base_text: base_text) : unit(child, VERSE, base_text)
            when "l" then unit(child, VERSE, base_text)
            when "p", "ab", "list" then unit(child, PROSE, base_text)
            when "trailer" then unit(child, TRAILER, base_text)
            when "quote" then walk(child, base_text: base_text || child["type"] == "base-text")
            else walk(child, base_text: base_text)
            end
          end
        end

        def walk_div(div, base_text:)
          head = OllettTeiParser.squish(div.at_xpath("t:head", NS))
          @frames << frame(OllettTeiParser.presence(div["n"].to_s.strip), head)
          @pending_labels = []
          walk(div, base_text: base_text)
          @frames.pop
        end

        # An lg wrapping further lgs (outside notes) is a container.
        def container_lg?(node)
          node.element_children.any? { |child| child.name == "lg" }
        end

        def page_break(node)
          return unless node["n"]

          if node["ed"]
            @pages[node["ed"]] = node["n"]
          else
            @page = node["n"]
          end
        end

        # -- units -------------------------------------------------------------

        def unit(node, kind, base_text)
          start_page = @page
          start_pages = @pages.dup
          collector = { chaya: [], labels: @pending_labels.map { |label| squish_text(label) }.compact }
          metrical = @pending_labels.select { |label| label["type"] == "metrical" }
          @pending_labels = []
          text = collapse(extract(node, collector))
          return if text.empty?

          citation, addressing = citation_for(node, kind)
          annotations = {
            "addressing" => addressing,
            "met" => meter_for(node, kind, metrical),
            "label" => join_or_nil(collector[:labels]),
            "chaya" => join_or_nil(collector[:chaya]),
            "page" => start_page,
            "pages" => start_pages.empty? ? nil : start_pages,
            "head" => innermost_head,
            "base_text" => base_text || nil,
            "type" => node["type"],
            "lines" => kind == VERSE ? line_count(node) : nil
          }.compact
          @units << Unit.new(citation: citation, text: text, language: language_of(node), annotations: annotations)
        end

        def citation_for(node, kind)
          n = OllettTeiParser.presence(node["n"].to_s.strip)
          return [join_path(n), "attribute"] if n

          frame = @frames.reverse.find { |f| f[:component] } || @frames.first
          token = "#{ORDINAL_PREFIX.fetch(kind)}#{frame[:counters][kind] += 1}"
          [join_path(token, upto: frame), "ordinal"]
        end

        def join_path(leaf, upto: nil)
          frames = upto ? @frames[0..(@frames.index { |f| f.equal?(upto) })] : @frames
          (frames.filter_map { |f| f[:component] } + [leaf]).join(".")
        end

        def innermost_head
          @frames.reverse.find { |f| f[:head] }&.fetch(:head)
        end

        # @met on the unit, else the nearest ancestor lg/div's, else a
        # preceding metrical label (verse only — "va." on prose is a label).
        def meter_for(node, kind, metrical)
          met = node.ancestors.each_with_object([node]) { |a, acc| acc << a if a.element? }
                              .find { |n| n["met"] && %w[lg div l].include?(n.name) }&.[]("met")
          met ||= squish_text(metrical.last) if kind == VERSE && metrical.any?
          met
        end

        def language_of(node)
          current = node
          while current.element? && current.name != "text"
            code = OllettTeiParser.lang_of(current)
            # The body's own tag is the document's language claim (already
            # resolved, possibly overridden) — only tags BELOW it switch.
            return @language if current.name == "body"
            return @resolver.call(code) if code

            current = current.parent
          end
          @language
        end

        def line_count(node)
          lines = node.xpath(".//t:l[not(ancestor::t:note)]", NS).size
          lines.zero? ? nil : lines
        end

        # -- text --------------------------------------------------------------

        def extract(node, collector)
          return node.text.gsub(/[[:space:]]+/, " ") if node.text? || node.cdata?
          return "" unless node.element?

          case node.name
          when "note"
            collector[:chaya] << collapse(extract_children(node, scratch)) if node["type"] == "chāyā"
            ""
          when "label"
            collector[:labels] << squish_text(node)
            ""
          when "head", *DROPPED then ""
          when "app" then (lem = node.at_xpath("t:lem", NS)) ? extract_children(lem, collector) : ""
          when "choice" then extract_choice(node, collector)
          when "lb" then node["break"] == "no" ? JOIN : " "
          when "pb"
            page_break(node)
            node["break"] == "no" ? JOIN : " "
          when "caesura", "milestone", "cb" then " "
          when "l" then "\n#{extract_children(node, collector)}\n"
          when "list" then " #{extract_list(node, collector)} "
          else extract_children(node, collector)
          end
        end

        def extract_children(node, collector)
          node.children.map { |child| extract(child, collector) }.join
        end

        def extract_choice(node, collector)
          preferred = CHOICE_PREFERENCE.lazy.filter_map { |name| node.at_xpath("t:#{name}", NS) }.first
          preferred ||= node.element_children.first
          preferred ? extract_children(preferred, collector) : ""
        end

        def extract_list(node, collector)
          items = node.xpath("t:item", NS).map { |item| collapse(extract_children(item, collector)) }
          items.reject(&:empty?).join("; ")
        end

        def scratch
          { chaya: [], labels: [] }
        end

        def collapse(text)
          text.gsub(/ *#{JOIN}[ #{JOIN}]*/o, "").split("\n").map { |line| line.gsub(/[[:space:]]+/, " ").strip }
                                                            .reject(&:empty?).join("\n")
        end

        def squish_text(node)
          OllettTeiParser.squish(node)
        end

        def join_or_nil(values)
          values = values.compact.reject(&:empty?)
          values.empty? ? nil : values.join(" | ")
        end
      end
      private_constant :Walk
    end
  end
end
