# frozen_string_literal: true

require "nokogiri"

require_relative "celtic_leiden"
require_relative "../timeline"
require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family "elephantine-tei" (P47-1): one record of the Berlin ERC
    # Elephantine database (elephantine.smb.museum) — TEI P5 against the
    # project's own DTD (tei_erc_elephantine.dtd), deliberately NOT EpiDoc:
    # no textparts, milestone-based text (<pb>/<lb> inside <ab>), a project
    # taxonomy in every file's encodingDesc (~25 KB of identical
    # boilerplate — resolved for catRef labels, never stored). DOM-based:
    # files are 25–55 KB (census 2026-07-26), far under the >5 MB Reader
    # rule.
    #
    # == Content shape (census + fixture evidence)
    #
    #   div[@type="edition"] > ab[@xml:lang="<Script> <lang>"] >
    #     pb[@n="R|V|concave|convex|…"], lb[@n] (@n may be EMPTY, carry
    #     spaces — "vso 1" — or algebraic forms "x+1", "1-5", "12+y"),
    #     damage[@degree]/supplied/unclear (often SELF-CLOSED = illegible
    #     traces)/gap/del/add/mod[@type="subst"]/choice(sic|corr, reg|orig)/
    #     expan/abbr/ex/persName/surname/rs[@type="title"]/orgName/
    #     placeName/date/note/space/handShift
    #   div[@type="translation" @xml:lang="en"] — same milestone shape,
    #     English prose (typographic ⸢…⸣ [///] marks kept verbatim: they are
    #     part of the translation as published).
    #
    # Either div may be EMPTY (self-closed on catalog-only records).
    #
    # == Passage = the LINE, page-scoped
    #
    #   urn = <document-urn>:<pb-n>.<lb-n>   (urn:nabu:elephantine:307762:R.4)
    #
    # Spaces in upstream @n fold to dots ("vso 1" → "vso.1", the oracc label
    # rule); an EMPTY lb @n (upstream's editorial label lines — "new text" /
    # "old text") mints a positional l<k> per page; a repeated (page, n)
    # suffix takes the house :b2 disambiguator (the ReM/EDR precedent —
    # upstream repeats <pb n="V"/> with restarting numbers across sibling
    # abs). Lines never span abs or page breaks.
    #
    # == The readable predicate (census: NEVER trust the site's text flag)
    #
    # A line is citable only when, gap markers removed, it still carries a
    # letter or digit (Imperial Aramaic numeral signs U+10858ff and
    # Egyptological transliteration both pass; "///" damage notation and
    # "-- --" lost-line dashes do not). ZERO citable edition lines — the
    # all-lacunae flagged editions and the catalog-only self-closed divs —
    # is a METADATA-ONLY document ("text_layer" => "none", the EDR
    # symbol-only precedent): catalogued, zero passages, never a quarantine.
    #
    # == Text policy (CelticLeiden + the Elephantine dialect)
    #
    # - choice keeps corr > reg (CelticLeiden.choice_branch); expan reads
    #   abbr+ex expanded; supplied/unclear/damage read through with grapheme
    #   counts riding annotations ("supplied_chars"/"unclear_chars"/
    #   "damaged_chars" — damage is this dialect's unclear-sibling); a
    #   SELF-CLOSED unclear/damage contributes nothing (illegible traces).
    # - gap → the house […] marker + reason/extent annotations; del →
    #   ⟦…⟧ + cancelled (mod[@type="subst"] falls out naturally: its del
    #   wraps, its add reads); surplus → {…}.
    # - DROP: note (inline editorial prose, English/German).
    # - Whitespace folds to single spaces; NFC at the boundary EXCEPT arc
    #   (Imperial Aramaic is on Normalize::NFC_EXEMPT_LANGUAGES — byte-
    #   verbatim, the standing owner ruling; census: the Aramaic sample is
    #   NFC-stable anyway, and 6/82 Greek editions need the NFC pass).
    #
    # == Language (the registry's Egyptian-family convention)
    #
    # msContents textLang/@mainLang carries combined tags (arc-Armi,
    # grc-Grek, egy-x-demr-Egyd-x-Egydlt — one taxonomy id with a TRAILING
    # SPACE, stripped defensively). Mapping: primary subtag, except the
    # Egyptian family, where a Demotic script marker (Egyd) mints egy-Egyd
    # (the papyri-ddbdp precedent; hieratic/other Egyptian stays egy, the
    # aes precedent). <ab xml:lang> is a SPACE-SEPARATED script+lang pair
    # ("Armi arc", "Grek grc", " en" with a leading space) — parsed
    # defensively (last token is the language), falling back to the
    # document language. No mainLang at all (62 records censused) → und.
    #
    # == Identity + licence pin
    #
    # Root <TEI xml:id="elephantine_erc_db_<ID6>"> IS the canonical id
    # (zero-padded even for short object ids — verified on 002881); the
    # caller-minted urn must agree or parse quarantines. Every record's
    # publicationStmt <licence target="…/by-sa/3.0/"> is the per-document
    # grant (zero deviations across the census's 76 sampled files) — pinned
    # HERE per document, so a drifted re-release stops loudly instead of
    # being silently ingested (D46-a: the per-file grant governs; the site
    # notice's CC BY-NC-SA claim is recorded in the adapter manifest, D47-d).
    #
    # == Header → Document#metadata (the EDH/EDR shape)
    #
    #   title = msItem title[@type="modern"] (fallback titleStmt/title);
    #   {"inventory", "repository", "summary", "title_original",
    #    "facets" => {"genre" (catRef labels resolved against the in-file
    #                 taxonomy, joined " | ")/"object_type"/"material"},
    #    "place" => {"ancient" (origin origPlace settlement)},
    #    "date" => {"not_before"/"not_after"/"raw"} — signed years via
    #      Timeline.parse_year from the supportDesc origDate's
    #      notBefore-custom/notAfter-custom (the precise editorial claim)
    #      when present, else the history origin origDate's nested
    #      date/@notBefore/@notAfter (the typological range),
    #    "tm_nr" (the trismegistos.org quick= id, ~15/51 censused)}
    #   — only non-empty keys (honest sparsity).
    #
    # == The -en translation lane
    #
    # parse_translation mints the parallel English sibling document
    # (<urn>-en, language eng, metadata "kind" => "translation" — the aes
    # -de / oracc -en mold) at the same line grain. A record whose
    # translation div has no citable line raises DocumentSkipped (skip by
    # rule, the honest absence).
    class ElephantineTeiParser
      URN_PREFIX = "urn:nabu:elephantine:"

      # The per-document grant every censused record carries (class note).
      LICENCE_TARGET = "http://creativecommons.org/licenses/by-sa/3.0/"

      DROPPED_ELEMENTS = %w[note].freeze

      # ISO 639-1 primaries → 639-3 (the ab pairs say "en"; mainLang is
      # already 639-3-shaped elsewhere).
      LANGUAGE_MAP = { "en" => "eng", "la" => "lat", "de" => "deu", "ar" => "ara" }.freeze

      TRANSLATION_LANGUAGE = "eng"

      # One extracted line: citation suffix, folded text, per-ab language,
      # page, leiden counters.
      Line = Data.define(:suffix_base, :text, :language, :page,
                         :gaps, :supplied, :unclear, :damaged, :cancelled)
      private_constant :Line

      # Parse one record file into the ORIGINAL Nabu::Document (+urn+ is
      # the adapter-minted urn:nabu:elephantine:<ID6>).
      def parse(path, urn:)
        doc = read_and_validate(path, record_urn: urn)
        language = document_language(doc)
        edition = doc.at_xpath("//body/div[@type='edition']")
        lines = edition ? citable_lines(edition, fallback_language: language) : []
        document = Nabu::Document.new(
          urn: urn, language: language, title: title_of(doc),
          canonical_path: path, metadata: metadata(doc, text_layer: !lines.empty?)
        )
        append_lines(document, urn, lines)
      end

      # Parse the -en translation sibling (+urn+ ends in -en; the record's
      # ID6 is minted from it). DocumentSkipped when the translation div
      # carries no citable line.
      def parse_translation(path, urn:)
        doc = read_and_validate(path, record_urn: urn.delete_suffix("-en"))
        translation = doc.at_xpath("//body/div[@type='translation']")
        lines = translation ? citable_lines(translation, fallback_language: TRANSLATION_LANGUAGE) : []
        if lines.empty?
          raise DocumentSkipped.new("#{path}: no readable translation div",
                                    reason: "no readable translation")
        end

        document = Nabu::Document.new(
          urn: urn, language: TRANSLATION_LANGUAGE, title: title_of(doc),
          canonical_path: path, metadata: { "kind" => "translation" }
        )
        append_lines(document, urn, lines)
      end

      # House folding minus the NFC for the exempt languages (arc rides
      # byte-verbatim per the standing owner ruling; whitespace runs still
      # collapse — they are markup pretty-printing, not text). Public: the
      # Extraction helper calls back into the family policy.
      def fold(text, language)
        collapsed = text.gsub(/[[:space:]]+/, " ").strip
        Normalize.nfc_exempt?(language) ? collapsed : Normalize.nfc(collapsed)
      end

      # The space-separated script+lang pair on an <ab> ("Armi arc",
      # " en" — leading/double spaces censused): the LAST token is the
      # language; the whole value decides the Demotic script marker.
      # Public for the Extraction helper.
      def ab_language(node, fallback)
        value = node["lang"].to_s
        tokens = value.split
        return fallback if tokens.empty?

        primary = tokens.last.split("-").first.downcase
        return value.match?(/Egyd/) ? "egy-Egyd" : "egy" if primary == "egy"

        map_language(tokens.last) || fallback
      end

      private

      def read_and_validate(path, record_urn:)
        doc = read_xml(path)
        validate_identity!(doc, path: path, urn: record_urn)
        verify_licence!(doc, path: path)
        doc
      end

      def read_xml(path)
        doc = Nokogiri::XML(File.read(path), &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # -- identity + licence ---------------------------------------------------

      # The root xml:id IS the canonical id; the caller's urn must mint it.
      def validate_identity!(doc, path:, urn:)
        xml_id = doc.root&.[]("id").to_s
        expected = "elephantine_erc_db_#{urn.delete_prefix(URN_PREFIX)}"
        return if xml_id == expected

        raise ParseError, "#{path}: root xml:id #{xml_id.inspect} does not mint the caller urn " \
                          "#{urn.inspect} (expected xml:id #{expected.inspect})"
      end

      def verify_licence!(doc, path:)
        licence = doc.at_xpath("//publicationStmt//licence")
        target = licence&.[]("target").to_s
        return if target == LICENCE_TARGET

        raise ParseError, "#{path}: <licence> drifted from the per-document CC BY-SA 3.0 pin " \
                          "(#{LICENCE_TARGET}), got #{target.inspect} — re-verify upstream terms " \
                          "(and the D47-d ruling) before ingesting"
      end

      # -- language -------------------------------------------------------------

      def document_language(doc)
        tag = doc.at_xpath("//msContents//textLang")&.[]("mainLang")
        map_language(tag) || "und"
      end

      # A combined upstream tag → the registry code (class note). nil for
      # empty input.
      def map_language(tag)
        value = tag.to_s.strip
        return nil if value.empty?

        # P47-i3 (owner live incident): the real corpus carries a literal
        # mainLang="-" (language undeclared) and script-only "-Egyd"/"-Egyp"
        # (script declared, language subtag missing) — a hyphen-led value
        # splits to NO primary subtag. Script-only Egyptian still maps
        # home; a bare hyphen is an honest und (the caller's fallback).
        primary = value.split("-").first.to_s.downcase
        if primary.empty?
          return "egy-Egyd" if value.match?(/Egyd/)
          return "egy" if value.match?(/Egy[ph]/)

          return nil
        end
        return value.match?(/Egyd/) ? "egy-Egyd" : "egy" if primary == "egy"
        return LANGUAGE_MAP.fetch(primary) if LANGUAGE_MAP.key?(primary)

        primary.match?(/\A[a-z]{2,3}\z/) ? primary : "und"
      end

      # -- lines ----------------------------------------------------------------

      # Citable lines of one edition/translation div, suffixes
      # disambiguated with the house :b2 counter.
      def citable_lines(div, fallback_language:)
        extraction = Extraction.new(self, fallback_language: fallback_language)
        extraction.div(div)
        seen = Hash.new(0)
        extraction.lines.filter_map do |line|
          next unless citable?(line.text)

          count = (seen[line.suffix_base] += 1)
          suffix = count == 1 ? line.suffix_base : "#{line.suffix_base}:b#{count}"
          [suffix, line]
        end
      end

      # Gap markers removed, a letter or digit must remain — "///" damage
      # notation, "-- --" lost-line dashes and marker-only lines are not
      # citable text (class note).
      def citable?(text)
        text.gsub(CelticLeiden::GAP_MARKER, "").match?(/[\p{L}\p{N}]/)
      end

      def append_lines(document, urn, lines)
        lines.each_with_index do |(suffix, line), sequence|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{suffix}", language: line.language, text: line.text,
            annotations: annotations_for(line), sequence: sequence
          )
        end
        document
      end

      def annotations_for(line)
        leiden = CelticLeiden.leiden_annotations(
          gaps: line.gaps, supplied: line.supplied,
          unclear: line.unclear, cancelled: line.cancelled
        )
        leiden["damaged_chars"] = line.damaged if line.damaged.positive?
        result = {}
        result["page"] = line.page if line.page
        result["leiden"] = leiden unless leiden.empty?
        result
      end

      # -- header → metadata ----------------------------------------------------

      def title_of(doc)
        presence(doc.at_xpath("//msContents//msItem/title[@type='modern']")&.text) ||
          presence(doc.at_xpath("//titleStmt/title")&.text)
      end

      def metadata(doc, text_layer:)
        result = {}
        result["text_layer"] = "none" unless text_layer
        { "inventory" => "//msIdentifier/idno",
          "repository" => "//msIdentifier/repository",
          "summary" => "//msContents/summary",
          "title_original" => "//msContents//msItem/title[@type='original']" }.each do |key, xpath|
          value = presence(doc.at_xpath(xpath)&.text)
          result[key] = value if value
        end
        facets = build_facets(doc)
        result["facets"] = facets unless facets.empty?
        ancient = presence(doc.at_xpath("//history/origin/origPlace/settlement")&.text)
        result["place"] = { "ancient" => ancient } if ancient
        date = extract_date(doc)
        result["date"] = date unless date.empty?
        tm_nr = trismegistos_id(doc)
        result["tm_nr"] = tm_nr if tm_nr
        result
      end

      def build_facets(doc)
        facets = {}
        genre = genre_labels(doc)
        facets["genre"] = { "value" => genre.join(" | ") } unless genre.empty?
        { "object_type" => "//physDesc//objectType",
          "material" => "//physDesc//material" }.each do |facet, xpath|
          value = presence(doc.at_xpath(xpath)&.text)
          facets[facet] = { "value" => value } if value
        end
        facets
      end

      # catRef targets resolved against the record's OWN taxonomy (the one
      # use the 25 KB boilerplate has; the labels land in metadata, the
      # taxonomy never does).
      def genre_labels(doc)
        doc.xpath("//textClass/catRef[@scheme='TAX_Text_Type']").filter_map do |ref|
          id = ref["target"].to_s.delete_prefix("#")
          next if id.empty?

          presence(doc.at_xpath("//category[@id='#{id}']/catDesc")&.text)
        end
      end

      # Signed-year bounds for the timeline lane (class note): the
      # supportDesc origDate's -custom attrs when present (the precise
      # editorial claim, raw text alongside), else the history origin
      # origDate's nested date range. A literal year 0 drops the bounds
      # and keeps raw (the Timeline tripwire, EDR mold).
      def extract_date(doc)
        custom = doc.at_xpath("//origDate[@notBefore-custom or @notAfter-custom]")
        node, before, after =
          if custom
            [custom, custom["notBefore-custom"], custom["notAfter-custom"]]
          else
            range = doc.at_xpath("//history/origin/origDate/date[@notBefore or @notAfter]")
            [range, range&.[]("notBefore"), range&.[]("notAfter")]
          end
        return {} if node.nil?

        result = {}
        begin
          not_before = Timeline.parse_year(before)
          not_after = Timeline.parse_year(after)
          result["not_before"] = not_before if not_before
          result["not_after"] = not_after if not_after
        rescue Timeline::InvalidYear
          result = {}
        end
        raw = presence(node.text)
        result["raw"] = raw if raw
        result
      end

      # The Trismegistos id from additional/listBibl ref[@type="url"]
      # (…trismegistos.org/tm/detail.php?quick=<TM>).
      def trismegistos_id(doc)
        doc.xpath("//listBibl//ref[@type='url']").each do |ref|
          match = ref.text.match(%r{trismegistos\.org/.*quick=(\d+)})
          return match[1] if match
        end
        nil
      end

      def presence(value)
        return nil if value.nil?

        folded = fold(value, "und")
        folded.empty? ? nil : folded
      end

      # Recursive-descent extraction over ONE edition/translation div:
      # <ab> blocks carry the language, <pb> the page scope, <lb> the
      # upstream line numbers (possibly empty → positional l<k> per page);
      # the CelticLeiden counters ride each line. ALL lines are kept here —
      # citability is the caller's cut.
      class Extraction
        attr_reader :lines

        def initialize(parser, fallback_language:)
          @parser = parser
          @fallback_language = fallback_language
          @raw_lines = []
          @current = nil
          @page = nil
          @unnumbered = 0
          @language = fallback_language
          @supplied_depth = 0
          @unclear_depth = 0
          @damage_depth = 0
          @del_depth = 0
          @lines = nil
        end

        def div(node)
          node.xpath("ab").each { |ab| walk_ab(ab) }
          close_line
          @lines = @raw_lines.map do |line|
            Line.new(
              suffix_base: line[:suffix_base], language: line[:language], page: line[:page],
              text: @parser.fold(line[:buffer], line[:language]),
              gaps: line[:gaps], supplied: line[:supplied], unclear: line[:unclear],
              damaged: line[:damaged], cancelled: line[:cancelled]
            )
          end
        end

        private

        def walk_ab(node)
          @language = @parser.ab_language(node, @fallback_language)
          node.children.each { |child| walk(child) }
          close_line # lines never span abs
        end

        def walk(node)
          return emit(node.text) if node.text?
          return unless node.element?

          name = node.name
          return if ElephantineTeiParser::DROPPED_ELEMENTS.include?(name)

          case name
          when "pb" then page_break(node)
          when "lb" then start_line(node)
          when "gap" then gap(node)
          when "choice" then choice(node)
          when "supplied" then counted(node, :@supplied_depth)
          when "unclear" then counted(node, :@unclear_depth)
          when "damage" then counted(node, :@damage_depth)
          when "del" then wrapped(node, CelticLeiden::CANCELLATION_OPEN, CelticLeiden::CANCELLATION_CLOSE)
          when "surplus" then wrapped(node, CelticLeiden::SURPLUS_OPEN, CelticLeiden::SURPLUS_CLOSE)
          else recurse(node)
          end
        end

        def recurse(node)
          node.children.each { |child| walk(child) }
        end

        # -- pages + lines --------------------------------------------------------

        # A page break scopes the following lines' suffixes and resets the
        # positional counter for unnumbered label lines. An EMPTY pb @n
        # (the translation divs' <pb n=""/>) scopes nothing.
        def page_break(node)
          close_line # a line never spans a page break
          n = fold_n(node["n"])
          @page = n.empty? ? nil : n
          @unnumbered = 0
        end

        def start_line(node)
          close_line
          n = fold_n(node["n"])
          n = "l#{@unnumbered += 1}" if n.empty?
          @current = {
            suffix_base: [@page, n].compact.join("."), page: @page, language: @language,
            buffer: +"", gaps: [], supplied: 0, unclear: 0, damaged: 0,
            cancelled: @del_depth.positive?
          }
          @raw_lines << @current
        end

        def close_line
          @current = nil
        end

        # Upstream @n folded for citation: spaces → dots ("vso 1" →
        # "vso.1", the oracc label rule), NFC.
        def fold_n(value)
          Normalize.nfc(value.to_s.strip).gsub(/\s+/, ".")
        end

        # Text before the first <lb> of an ab/page is template whitespace
        # (every text run opens with a milestone — censused); it lands
        # nowhere.
        def emit(text)
          return if @current.nil? || text.empty?

          @current[:buffer] << text
          count_certainty(text)
        end

        def emit_marker(marker)
          @current[:buffer] << marker unless @current.nil?
        end

        def count_certainty(text)
          return if @supplied_depth.zero? && @unclear_depth.zero? && @damage_depth.zero?

          count = CelticLeiden.grapheme_count(text)
          @current[:supplied] += count if @supplied_depth.positive?
          @current[:unclear] += count if @unclear_depth.positive?
          @current[:damaged] += count if @damage_depth.positive?
        end

        # -- markers + counted spans ----------------------------------------------

        def gap(node)
          return if @current.nil? # a gap before any line has nowhere to land

          emit_marker(CelticLeiden::GAP_MARKER)
          @current[:gaps] << CelticLeiden.gap_annotation(node)
        end

        def counted(node, variable)
          instance_variable_set(variable, instance_variable_get(variable) + 1)
          recurse(node)
          instance_variable_set(variable, instance_variable_get(variable) - 1)
        end

        def wrapped(node, open, close)
          cancelling = open == CelticLeiden::CANCELLATION_OPEN
          @del_depth += 1 if cancelling
          emit_marker(open)
          @current[:cancelled] = true if cancelling && @current
          recurse(node)
          emit_marker(close)
          @del_depth -= 1 if cancelling
        end

        def choice(node)
          branch = CelticLeiden.choice_branch(node)
          walk(branch) if branch
        end
      end
      private_constant :Extraction
    end
  end
end
