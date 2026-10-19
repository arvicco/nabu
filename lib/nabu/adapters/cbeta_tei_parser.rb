# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one CBETA xml-p5 edition — the `cbeta-tei` family
    # (P33-2): TEI P5 plus CBETA's own cb: extension namespace
    # (http://www.cbeta.org/ns/1.0), probed on real T (Taishō) and X
    # (Xuzangjing) files before design, never invented.
    #
    # == Passage grain: the encoded print line (censused 2026-07-20)
    #
    # Every file carries its canon's own print coordinates as empty <lb>
    # milestones: @n = "PPPPrLL" (four-digit page, register a/b/c…,
    # two-digit line — e.g. "1390a24" = p.1390, register a, line 24), @ed =
    # the canon siglum ("T", "X"). The Taishō/Xuzangjing citation therefore
    # rides FREE: passage urn = <document urn>:<lb @n> verbatim
    # (urn:nabu:cbeta:T85n2884:1390a24 IS "T85, No. 2884, p.1390a24" — the
    # standard scholarly citation), volume in the document id, never
    # invented. A file may ALSO carry a parallel lb stream for a WITNESS
    # edition (X files interleave ed="R150"-style 卍續藏經 lines); only the
    # file's own canon siglum mints — the witness stream is layout of a
    # different print run. Attribute order varies upstream
    # (<lb n=… ed=…> and <lb ed=… n=…> both real; censused) — attributes,
    # never regexes. Lines whose accumulated text is empty (blank layout
    # lines around headers) emit nothing; a duplicate @n (none censused)
    # would disambiguate ":b2" (house ddbdp rule), never quarantine.
    #
    # == Text discipline (all shapes censused on real files)
    #
    # Reading text is captured between <text><body> and </body> only. CBETA
    # encodes the witness apparatus STAND-OFF in <back> (see "The stand-off
    # apparatus" below), so the body already carries the edition's reading
    # text and <back> never contributes a byte of it. Inside the body:
    #
    # - <note place="inline"> — CBETA's interlinear small-print notes — are
    #   dropped from the reading text but carried VERBATIM per line as a
    #   "notes" annotation; every other <note> subtree is dropped.
    # - <g ref="#CB…"/> gaiji: the element's text content (CBETA's Unicode
    #   approximation) stays in the reading text; the ref rides the line's
    #   "gaiji" annotation verbatim, NOT resolved against <charDecl> (the
    #   P33-0 Kanripo rule; composition/PUA mappings stay in canonical XML).
    # - Inline <app>/<lem> (defensive; censused apparatus is stand-off) keep
    #   the <lem> reading, <rdg> subtrees drop.
    # - <cb:t place="foot"> (the back-matter multilingual term glosses —
    #   Dīrgha-āgama beside 長阿含經) drops; plain <cb:t> text flows.
    # - <cb:mulu> (table-of-contents entries duplicating the adjacent
    #   <head>; censused on X55n0899) drops.
    # - <space quantity="0"/> contributes nothing; any other <space/> one
    #   space. <caesura/> (verse half-line) contributes nothing — CJK verse
    #   carries its own punctuation. <anchor/>, foreign-ed <lb>/<pb> are
    #   empty and ignored. Everything else (p, lg, l, head, byline,
    #   cb:div, cb:jhead, cb:docNumber…) is transparent: line grain means
    #   text flows to the open print line.
    # - <milestone unit="juan" n="…"/> tracks the current fascicle; each
    #   passage carries it as the "juan" annotation.
    # - <ref cRef="PTS.Khp.1"/> (N canon only — censused absent from every
    #   T/X/K file, 2026-10-14): the Pali Text Society page anchor of the
    #   Pāli original, empty, carried verbatim per line as the "cref"
    #   annotation (folded into the preceding line from a layout-only one).
    #   N's <label type="translation-mark"> (a, a'…) is printed text and
    #   flows.
    #
    # == The stand-off apparatus (census: 924,766 top-level <app> in 3,905
    #    of 4,075 scope files, every FROM anchor resolved onto a passage —
    #    0 unresolved, 11,233 spans closing on a later line, 2026-10-20,
    #    this parser run in memory over T/X/K/J/N at 2026.R2)
    #
    # <back>'s <cb:div type="apparatus"> holds one
    # <app from="#beg…" to="#end…"> per variant — <lem wit="#wit.orig">
    # (the edition's reading) beside <rdg wit="#wit1 #wit2" resp="#resp2">
    # (witness readings; an empty <rdg><space quantity="0"/></rdg> is an
    # omission) — anchored on empty body <anchor xml:id> milestones. Each
    # entry resolves to the print line holding its FROM anchor (an anchor on
    # a layout-only line folds to the preceding text line, one before any
    # text line to the next — the inline-note fold) and rides that passage's
    # "apparatus" annotation in the house stand-off shape (tamilex):
    # {"lemma", "witnesses", "resp"?, "readings" => [{"text", "witnesses",
    # "resp"?, "type"?}], "type"?, "corresp"?, "cf"?, "to"?}. Witness ids
    # resolve to the header's own sigla (wit1 → 【宋】), resp ids to the
    # respStmt names (resp2 → Taisho); an undeclared id rides verbatim.
    # "type"/"corresp" are the star-app markers (CBETA's re-anchoring of a
    # Taishō note number onto a later occurrence); "cf" carries the
    # <note type="cf…"> cross-canon page references verbatim; "to" names
    # the closing print line when the TO anchor sits on another line.
    # Apparatus text flattens like reading text (gaiji text kept, lb/anchor
    # empty) except that an interlinear <note place="inline"> IS printed
    # lemma text there; the Taishō orig/mod note restatements drop, and a
    # nested <app> (a variant restated inside a longer lemma — it also
    # stands as its own top-level entry) contributes its lemma only.
    # cb:word-count is derivable from the lemma and not carried. An entry
    # whose FROM anchor is absent from the body is never guessed onto a
    # line: it is counted in metadata["apparatus_unresolved"]. The tt
    # (multilingual term) and note divisions are not variant apparatus and
    # stay unread.
    #
    # == The license gate (canon-level, re-verified per file)
    #
    # Every T and X header carries the SAME <availability> grant verbatim:
    # "Available for non-commercial use when distributed with this header
    # intact." (censused across all sampled T/X files at 2026.R1). The
    # parser refuses (ParseError) any file whose availability does not
    # carry that sentence — a drifted grant must quarantine loudly, never
    # ride the source's nc class on faith. The grant is carried in
    # Document#metadata["license"]; the witness list (tagsDecl <witness>:
    # 【CB】【大】【宋】【元】【明】…) in metadata["witnesses"].
    #
    # == Streaming
    #
    # Nokogiri::XML::Reader only: T ships 27 files over the house 5 MB DOM
    # limit (max 17.2 MB, T25n1509), X ships 7 (max 9.0 MB). One pass.
    class CbetaTeiParser
      # CBETA's T/X/K/J text is Literary Chinese (headers tag zh-Hant, the
      # script; the language is lzh — the SuttaCentral Āgama precedent).
      LANGUAGE = "lzh"

      # Canons whose text is NOT Literary Chinese (P126). N — 漢譯南傳大藏經
      # (Yuan Heng Temple edition, 1990–98, 70 vols) — is a 20th-century
      # Chinese translation of the Pāli Tipiṭaka, made from the Japanese
      # Nanden daizōkyō (1935–41): modern written Chinese in a classicizing
      # Buddhist register, tagged cmn (the classical-modern translation-
      # sibling precedent), never the lzh claim. Its headers tag zh-Hant
      # exactly like T, so the canon — not the header — decides.
      CANON_LANGUAGES = { "N" => "cmn" }.freeze

      # What a translated canon was translated FROM, recorded per document
      # (the Pāli source the N text renders; the Japanese intermediary named
      # in the basis). Canons absent here are native Chinese composition or
      # carry their own translation bylines.
      CANON_TRANSLATIONS = {
        "N" => {
          "translated_from" => "pli",
          "translation_basis" => "漢譯南傳大藏經（元亨寺版）— Chinese translation of the Pāli " \
                                 "Tipiṭaka via the Japanese 南傳大藏經 (Nanden daizōkyō, 1935–41)"
        }.freeze
      }.freeze

      def self.language_for(canon)
        CANON_LANGUAGES.fetch(canon, LANGUAGE)
      end

      # The in-file grant, byte-verbatim (see class note). Field-gated at
      # <body>; quoted in docs and the 02-sources row.
      AVAILABILITY_GRANT =
        "Available for non-commercial use when distributed with this header intact."

      # One print line: citation = lb @n verbatim; juan/gaiji/notes/cref
      # ride annotations.
      Unit = Data.define(:citation, :text, :juan, :gaiji, :notes, :crefs)
      private_constant :Unit

      # A role-suffixed byline token: 譯 translated, 造/撰/述/說 authored,
      # 集/輯/編/錄/記 compiled, 註/疏 commented. census: 3,163 spaced
      # bylines over 3,707 headers, 2026-09-26.
      ROLE_SUFFIX = /[譯造撰述說集輯編錄著記註疏]\z/
      # "奉詔譯"/"奉制譯" — translated by imperial decree; the decree tail
      # is ceremony, not name.
      DECREE_TAIL = /(?:奉[[:space:]]*[詔制])?譯\z/
      # 失譯 "translator lost" / 闕譯 "translation attribution missing" —
      # upstream's own no-attribution markers (census: 135 + 7 lone
      # headers, 2026-09-26): a claim of absence, never a name.
      NO_ATTRIBUTION = %w[失譯 闕譯].freeze

      # The structural attribution split (P104-1). Tokens are whitespace-
      # separated (CBETA's own header convention); the final role-suffixed
      # token is the acting person(s), the dynasty seat is the short bare
      # token before it (an Indian master's "…菩薩造" is itself
      # role-suffixed and never mistaken for a seat; title strings like
      # 天竺三藏 run longer than any censused seat). Returns
      # {dynasty:, translator:}, either absent — no seat, no claim.
      def self.byline_attribution(author)
        tokens = author.split(/[[:space:]]+/).reject(&:empty?)
        role_index = tokens.rindex { |token| token.match?(ROLE_SUFFIX) }
        return {} if role_index.nil?

        seats = tokens[0...role_index].grep_v(ROLE_SUFFIX)
        dynasty = seats.find { |token| token.length <= 3 }
        translator = nil
        role = tokens[role_index]
        if role.end_with?("譯") && !NO_ATTRIBUTION.include?(role)
          name = role.sub(DECREE_TAIL, "")
          translator = name unless name.empty?
        end
        { dynasty: dynasty, translator: translator }.compact
      end

      def parse(source, urn:, canon:, title: nil, canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        extraction = extract(source, path: path, canon: canon)
        units = disambiguate_collisions(extraction.units)
        build_document(extraction, units, urn: urn, title: title, path: path)
      end

      private

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      def extract(source, path:, canon:)
        with_io(source) do |io|
          Extraction.new(reader: Nokogiri::XML::Reader(io, path), path: path, canon: canon).call
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def with_io(source, &)
        source.is_a?(String) ? File.open(source, "r", &) : yield(source)
      end

      # The house collision tolerance: duplicates disambiguate
      # deterministically in document order, never quarantine.
      def disambiguate_collisions(units)
        seen = Hash.new(0)
        units.map do |unit|
          count = seen[unit.citation] += 1
          count == 1 ? unit : unit.with(citation: "#{unit.citation}:b#{count}")
        end
      end

      def build_document(extraction, units, urn:, title:, path:)
        language = self.class.language_for(extraction.canon_siglum)
        apparatus, unresolved = resolve_apparatus(extraction, units)
        metadata = document_metadata(extraction)
        metadata["apparatus_unresolved"] = unresolved if unresolved.positive?
        document = Document.new(
          urn: urn, language: language, title: extraction.title || title,
          canonical_path: path, metadata: metadata
        )
        units.each_with_index do |unit, sequence|
          text = Normalize.nfc(unit.text.gsub(/[[:space:]]+/, " ").strip)
          annotations = unit_annotations(unit)
          annotations["apparatus"] = apparatus[sequence] if apparatus.key?(sequence)
          document << Passage.new(
            urn: "#{urn}:#{unit.citation}", language: language, text: text,
            annotations: annotations, sequence: sequence
          )
        end
        raise ParseError, "#{path}: no citable print lines found in <text><body>" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      def document_metadata(extraction)
        metadata = { "license" => AVAILABILITY_GRANT }
        metadata["witnesses"] = extraction.witnesses unless extraction.witnesses.empty?
        metadata["canon"] = extraction.canon if extraction.canon
        metadata["vol"] = extraction.vol if extraction.vol
        metadata["no"] = extraction.no if extraction.no
        metadata.merge!(CANON_TRANSLATIONS.fetch(extraction.canon_siglum, {}))
        merge_byline(metadata, extraction.author)
        merge_body_bylines(metadata, extraction.bylines)
        metadata
      end

      # The body <byline> harvest: every byline as a document-level person
      # with role — {"name" => …, "role" => …} — deduped per (name, role)
      # (the per-fascicle repeats collapse). Names ride verbatim (the
      # byline's reading text, anchors transparent, inline notes dropped);
      # cb:type rides as the role with ASCII case folded (upstream writes
      # both "Translator" and "translator"); an untyped byline carries no
      # role. These name preface and sub-work authors the header never
      # does; where the header <author> is silent, the author-role names
      # also ride "byline_authors" (the author facet via
      # config/facet_map.yml). No dynasty/name split here — the body
      # byline is freer than the header's (era phrases such as 後秦弘始年
      # run into the name), so the whole string stays the claim.
      def merge_body_bylines(metadata, bylines)
        persons = bylines.uniq
        return if persons.empty?

        metadata["persons"] = persons
        return if metadata["author"]

        authors = persons.filter_map { |person| person["name"] if person["role"] == "author" }
        metadata["byline_authors"] = authors unless authors.empty?
      end

      # The header byline harvest (P104-1; attributed-era dating, its own labeled class): the teiHeader
      # <author> carries CBETA's own attribution ("後秦 佛陀耶舍共竺佛念譯")
      # — verbatim in "author", the structural split in "dynasty"/
      # "translator" plus matching facets (raw = the whole byline). The
      # dynasty seat feeds the MetadataDates :dynasty_band era lane; an
      # unruled seat there mints no date, so the split can stay purely
      # structural here.
      def merge_byline(metadata, author)
        return if author.nil? || author.empty?

        metadata["author"] = author
        attribution = self.class.byline_attribution(author)
        facets = {}
        %i[dynasty translator].each do |part|
          value = attribution[part] or next

          metadata[part.to_s] = value
          facets[part.to_s] = { "value" => value, "raw" => author }
        end
        metadata["facets"] = facets unless facets.empty?
      end

      # Stand-off entries onto unit indexes (see the class note): FROM anchor
      # → the hosting unit; a TO anchor on a later unit names its citation.
      # Returns [{unit index => [entry, …]}, unresolved count].
      def resolve_apparatus(extraction, units)
        anchors = extraction.anchors
        unresolved = 0
        by_unit = {}
        extraction.apparatus.each do |from, to, entry|
          index = anchors[from]
          next unresolved += 1 if index.nil?

          to_index = anchors[to]
          entry = entry.merge("to" => units[to_index].citation) if to_index && to_index != index
          (by_unit[index] ||= []) << entry
        end
        [by_unit, unresolved]
      end

      def unit_annotations(unit)
        annotations = {}
        annotations["juan"] = unit.juan if unit.juan
        annotations["gaiji"] = unit.gaiji unless unit.gaiji.empty?
        annotations["notes"] = unit.notes unless unit.notes.empty?
        annotations["cref"] = unit.crefs unless unit.crefs.empty?
        annotations
      end

      # The single-pass Reader state machine: header phase (title, idno,
      # availability gate, witness list), body phase (print-line units),
      # done at </body> — <back> never read.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        # Body subtrees whose text never reaches the reading line. <note> is
        # special-cased (inline notes ride annotations); <mulu> is cb:mulu.
        DROPPED_ELEMENTS = %w[note rdg mulu].freeze
        private_constant :READER, :TEXT_NODE_TYPES, :DROPPED_ELEMENTS

        Result = Data.define(:units, :title, :author, :witnesses, :canon, :vol, :no, :canon_siglum,
                             :bylines, :anchors, :apparatus)

        attr_reader :title, :author, :witnesses, :canon, :vol, :no

        def initialize(reader:, path:, canon:)
          @reader = reader
          @path = path
          @expected_canon = canon
          @title = nil
          @author = nil
          @capture = nil            # header text sink (:title, :author, :idno, :witness, :availability)
          @availability_text = +""
          @in_availability = false
          @witnesses = []
          @idno = {}
          @idno_type = nil
          @seen_body = false
          @in_body = false
          @drop_depth = nil
          @note_buffer = nil        # open inline-note text, riding annotations
          @juan = nil
          @line = nil               # open print line {citation:, text:, gaiji:, notes:, crefs:}
          @units = []
          @byline = nil             # open body <byline> {role:, text:}
          @bylines = []
          @witness_id = nil         # header <witness xml:id> being captured
          @witness_sigla = {}       # wit1 => 【宋】
          @resp_id = nil            # header <respStmt xml:id> being captured
          @resp_names = {}          # resp2 => Taisho
          @anchors = {}             # body <anchor xml:id> => unit index
          @pending_anchors = []     # anchors seen before any text line
          @back_done = false        # the apparatus division (or </back>) closed
          @apparatus_depth = nil    # depth of the open cb:div type="apparatus"
          @app_depth = nil          # depth of the top-level <app> being skipped
          @apparatus = []           # [from, to, entry] in back order
        end

        def call
          @reader.each do |node|
            process(node)
            break if @back_done # nothing after the apparatus division is read
          end
          raise ParseError, "#{@path}: no <text><body> found" unless @seen_body

          Result.new(units: @units, title: @title, author: @author, witnesses: @witnesses,
                     canon: @idno["canon"], vol: @idno["vol"], no: @idno["no"],
                     canon_siglum: @expected_canon, bylines: @bylines, anchors: @anchors,
                     apparatus: @apparatus)
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          when *TEXT_NODE_TYPES then text_node(node)
          end
        end

        def start_element(node)
          name = local_name(node)
          return enter_body(node) if name == "body" && !@seen_body
          return back_element(node, name) if @seen_body && !@in_body
          return header_element(node, name) unless @in_body
          # An anchor marks a position even inside a dropped subtree (an
          # inline note's span still sits on its print line).
          return record_anchor(node.attribute("xml:id")) if name == "anchor"
          return if dropping?

          case name
          when "lb" then line_break(node)
          when "note" then open_note(node)
          when "g" then @line[:gaiji] << node.attribute("ref") if @line && node.attribute("ref")
          when "ref" then @line[:crefs] << node.attribute("cRef") if @line && node.attribute("cRef")
          when "milestone" then @juan = node.attribute("n") if node.attribute("unit") == "juan"
          when "byline" then open_byline(node)
          when "space" then append(" ") unless node.attribute("quantity") == "0"
          when "t" then drop_subtree(node) if node.attribute("place") == "foot"
          when *DROPPED_ELEMENTS then drop_subtree(node)
          end
        end

        def end_element(node)
          if @in_body
            return close_body if local_name(node) == "body"
            return close_byline if local_name(node) == "byline" && !dropping?
            return unless dropping?

            if node.depth == @drop_depth
              @drop_depth = nil
              close_note
            end
          elsif @seen_body
            back_end_element(node)
          else
            header_end_element(local_name(node))
          end
        end

        def text_node(node)
          value = node.value.to_s
          if @in_body
            return @note_buffer << value if dropping? && @note_buffer
            return if dropping?

            append(value)
          elsif !@seen_body
            header_text(value)
          end
        end

        # -- header ----------------------------------------------------------

        def header_element(node, name)
          case name
          when "title"
            @capture = :title if @title.nil? && node.attribute("level") == "m" &&
                                 node.attribute("xml:lang") == "zh-Hant"
          when "author"
            # The titleStmt byline (first only — the header's own
            # attribution seat; P104-1).
            @capture = :author if @author.nil? && !node.empty_element?
          when "idno" then @idno_type = node.attribute("type")
          when "witness"
            @capture = :witness
            @witness_id = node.attribute("xml:id")
          when "availability" then @in_availability = true unless node.empty_element?
          when "respStmt" then @resp_id = node.attribute("xml:id")
          when "name" then @capture = :resp_name if @resp_id
          end
        end

        def header_end_element(name)
          @capture = nil
          @in_availability = false if name == "availability"
          @idno_type = nil if name == "idno"
          @resp_id = nil if name == "respStmt"
        end

        def header_text(value)
          @availability_text << value if @in_availability
          case @capture
          when :title
            @title = value.strip
            @capture = nil
          when :author
            author = Nabu::Normalize.nfc(value.strip)
            @author = author unless author.empty?
            @capture = nil
          when :witness
            @witnesses << value.strip
            @witness_sigla[@witness_id] = value.strip if @witness_id
            @capture = nil
          when :resp_name
            @resp_names[@resp_id] = value.strip
            @capture = nil
          end
          @idno[@idno_type] = value.strip if @idno_type
        end

        # The canon-level license gate, re-verified per file, plus the
        # canon identity check — both loud, both before any body text.
        def enter_body(node)
          unless @availability_text.include?(CbetaTeiParser::AVAILABILITY_GRANT)
            raise ParseError, "#{@path}: license gate: <availability> does not carry the CBETA " \
                              "grant verbatim (#{CbetaTeiParser::AVAILABILITY_GRANT.inspect}) — " \
                              "refusing to ride the nc class on faith"
          end
          declared = @idno["canon"]
          if declared && declared != @expected_canon
            raise ParseError, "#{@path}: canon mismatch: caller says #{@expected_canon.inspect}, " \
                              "the header declares #{declared.inspect}"
          end
          @seen_body = true
          @in_body = !node.empty_element?
        end

        # -- body ------------------------------------------------------------

        # Only the file's own canon siglum mints print lines; witness-edition
        # lb streams (ed="R150"…) are another print run's layout.
        def line_break(node)
          return unless node.attribute("ed") == @expected_canon

          flush_line
          @line = { citation: node.attribute("n"), text: +"", gaiji: [], notes: [], crefs: [], anchors: [] }
        end

        def open_note(node)
          return if node.empty_element?

          @note_buffer = +"" if @line && node.attribute("place") == "inline"
          drop_subtree(node)
        end

        def close_note
          return if @note_buffer.nil?

          note = @note_buffer.strip
          @line[:notes] << note unless note.empty?
          @note_buffer = nil
        end

        def close_body
          flush_line
          @in_body = false
        end

        # -- back: the stand-off apparatus (never reading text) -------------

        # Only top-level <app> inside cb:div type="apparatus" is read, each
        # as one small DOM (the Reader's outer_xml carries its namespace
        # declarations) — bounded memory; its descendants are skipped.
        def back_element(node, name)
          return if @app_depth

          if name == "div" && node.attribute("type") == "apparatus" && !node.empty_element?
            @apparatus_depth = node.depth
          elsif name == "app" && @apparatus_depth
            read_app(node)
            @app_depth = node.depth unless node.empty_element?
          end
        end

        def back_end_element(node)
          name = local_name(node)
          if @app_depth
            @app_depth = nil if name == "app" && node.depth == @app_depth
          elsif name == "div" && node.depth == @apparatus_depth
            # census: in all 3,905 apparatus-bearing files the apparatus is
            # the FIRST back division, 2026-10-20 — the notes/tt divisions
            # after it are never needed, so the read ends here.
            @apparatus_depth = nil
            @back_done = true
          elsif name == "back"
            @back_done = true
          end
        end

        def read_app(node)
          app = Nokogiri::XML(node.outer_xml).root
          entry = ApparatusEntry.new(witnesses: @witness_sigla, resps: @resp_names).build(app)
          @apparatus << [target(app["from"]), target(app["to"]), entry]
        end

        def target(ref)
          ref.to_s.strip.delete_prefix("#")
        end

        def flush_line
          line = @line
          @line = nil
          return if line.nil?
          return fold_anchors(line[:anchors]) if line[:citation].nil?

          # Blankness must be judged with the same Unicode collapse the
          # passage build applies: a line of ideographic layout space
          # (U+3000) slips past an ASCII strip and then empties into a
          # ValidationError that quarantines the whole file (the Sep-29
          # 35-file class, T10n0285:0458a18). A layout-only line mints no
          # passage; its interlinear notes fold into the preceding text
          # line so the apparatus survives (a title gloss hangs under its
          # title line in print); a Pāli cRef milestone on such a line folds
          # the same way. Gaiji cannot occur on a blank line (a gaiji ref IS
          # text).
          if line[:text].gsub(/[[:space:]]+/, "").empty?
            fold_into_previous(line)
            fold_anchors(line[:anchors])
            return
          end

          index = @units.size
          @pending_anchors.each { |id| @anchors[id] = index }
          @pending_anchors.clear
          line[:anchors].each { |id| @anchors[id] = index }
          @units << Unit.new(citation: line[:citation], text: line[:text], juan: @juan,
                             gaiji: line[:gaiji], notes: line[:notes], crefs: line[:crefs])
        end

        # Body anchors (the apparatus targets) map to the unit they sit on;
        # an anchor on a layout-only line folds like its notes (to the
        # preceding text line), one before any text line waits for the next.
        def record_anchor(id)
          return if id.nil?
          return @line[:anchors] << id if @line

          @pending_anchors << id
        end

        def fold_anchors(ids)
          return @pending_anchors.concat(ids) if @units.empty?

          ids.each { |id| @anchors[id] = @units.size - 1 }
        end

        def fold_into_previous(line)
          return if @units.empty? || (line[:notes].empty? && line[:crefs].empty?)

          last = @units.last
          @units[-1] = last.with(notes: last.notes + line[:notes], crefs: last.crefs + line[:crefs])
        end

        def append(value)
          @line[:text] << value if @line
          @byline[:text] << value if @byline
        end

        # A body byline's text still flows to the print line (it IS printed
        # text); it is ALSO captured for the persons harvest.
        def open_byline(node)
          return if node.empty_element?

          @byline = { role: node.attribute("cb:type"), text: +"" }
        end

        def close_byline
          byline = @byline
          @byline = nil
          return if byline.nil?

          name = Nabu::Normalize.nfc(byline[:text].gsub(/[[:space:]]+/, ""))
          return if name.empty?

          person = { "name" => name }
          role = byline[:role].to_s.strip
          person["role"] = role.ascii_only? ? role.downcase : role unless role.empty?
          @bylines << person
        end

        def drop_subtree(node)
          @drop_depth = node.depth unless node.empty_element?
        end

        def dropping?
          !@drop_depth.nil?
        end

        def local_name(node)
          node.name.split(":").last
        end
      end
      private_constant :Extraction

      # One top-level stand-off <app> → its annotation entry (the class
      # note's shape). Witness/resp ids resolve through the header maps; an
      # undeclared id rides verbatim.
      class ApparatusEntry
        def initialize(witnesses:, resps:)
          @witnesses = witnesses
          @resps = resps
        end

        def build(app)
          entry = {}
          entry["type"] = app["type"] if app["type"]
          entry["corresp"] = app["corresp"].delete_prefix("#") if app["corresp"]
          lem = child(app, "lem")
          entry["lemma"] = lem ? flatten(lem) : ""
          ids(entry, "witnesses", lem&.[]("wit"), @witnesses)
          ids(entry, "resp", lem&.[]("resp"), @resps)
          entry["readings"] = app.element_children.select { |el| el.name == "rdg" }.map { |rdg| reading(rdg) }
          cf = cross_references(app)
          entry["cf"] = cf unless cf.empty?
          entry
        end

        private

        def reading(rdg)
          reading = { "text" => flatten(rdg) }
          ids(reading, "witnesses", rdg["wit"], @witnesses)
          ids(reading, "resp", rdg["resp"], @resps)
          reading["type"] = rdg["type"] if rdg["type"]
          reading
        end

        def ids(hash, key, value, names)
          list = value.to_s.split.map do |ref|
            id = ref.delete_prefix("#")
            names.fetch(id, id)
          end
          hash[key] = list unless list.empty?
        end

        def child(node, name)
          node.element_children.find { |el| el.name == name }
        end

        # <note type="cf1">K17n0647_p0840b23</note> — upstream's own
        # cross-canon page references, verbatim, deduped (a nested restated
        # app may repeat its twin's).
        def cross_references(app)
          app.xpath(".//*[local-name()='note'][starts-with(@type, 'cf')]")
             .map { |note| note.text.strip }.reject(&:empty?).uniq
        end

        def flatten(node)
          Normalize.nfc(collect(node, +"").gsub(/[[:space:]]+/, " ").strip)
        end

        def collect(node, buffer)
          node.children.each do |part|
            if part.text? || part.cdata?
              buffer << part.content
            elsif part.element?
              collect_element(part, buffer)
            end
          end
          buffer
        end

        def collect_element(element, buffer)
          case element.name
          when "note" then collect(element, buffer) if element["place"] == "inline"
          when "app"
            lem = child(element, "lem")
            collect(lem, buffer) if lem
          when "rdg", "mulu" then nil
          when "space" then buffer << " " unless element["quantity"] == "0"
          when "t" then collect(element, buffer) unless element["place"] == "foot"
          else collect(element, buffer)
          end
        end
      end
      private_constant :ApparatusEntry
    end
  end
end
