# frozen_string_literal: true

require "strscan"
require_relative "jis0213"

module Nabu
  module Adapters
    # The aozora-ruby parser family (P38-3): Aozora Bunko's ruby-annotated
    # plain-text format, one work per single-.txt zip (canonical = the zip,
    # unzipped on read — upstream stores the text zipped and the inner
    # filename is unpredictable). Every rule below is from the P38-0 survey
    # (.docs/surveys/aozora-survey.md §4, quoted from fetched real files) or
    # from the two PD fixture works — never invented.
    #
    # == Encoding
    #
    # Shift_JIS in practice CP932/Windows-31J (the index's nominal charset
    # "JIS X 0208" undersells the real files' JIS X 0213 gaiji rows), decoded
    # to UTF-8 and NFC-normalized at this boundary (jpn is not NFC-exempt).
    # Files ship CRLF line ends.
    #
    # == File structure (survey §4e)
    #
    # Header block (line 1 = title, then author/translator lines), a
    # 55-hyphen delimiter, the 【テキスト中に現れる記号について】 legend, a
    # second delimiter, the body, then the 底本 colophon. The legend is
    # Aozora's per-file markup explainer — input-convention boilerplate whose
    # examples quote the file's own notation (56078's legend repeats one of
    # its gaiji), so it is structurally skipped, never text. The colophon
    # (from the first body line starting 底本：, to EOF) is structured
    # provenance — document metadata, never passage text. A file without the
    # delimiter pair quarantines loudly (every surveyed file has it).
    # A pure hyphen-run line inside the body is layout, not text — skipped
    # (some works reuse the delimiter as a section rule).
    #
    # == Passage granularity: one passage per non-blank body LINE
    #
    # Aozora files hard-wrap nothing: a prose paragraph is ONE physical line
    # (fixture paragraphs run to 850+ chars) and verse/quotations put each
    # verse line on its own physical line. The physical line is therefore
    # the corpus's own paragraph/verse grain — anything coarser would glue
    # paragraphs, anything finer would invent structure. Lines whose content
    # is only formatting commands mint no passage; their commands annotate
    # the NEXT passage (block commands like ここから２字下げ scope forward).
    # Urns are ordinals over emitted passages (<doc>:1, <doc>:2, …) — stable
    # for a fixed upstream file, revised naturally with it.
    #
    # == Ruby (furigana), survey §4b
    #
    # `｜base《reading》` and auto-boundary `base《reading》`. The STORED text
    # is the base text with all ruby markup stripped; readings ride the
    # annotation layer (annotations "ruby": [{"base","reading"}, …] in line
    # order — the kanripo gaiji-annotation precedent). The auto-boundary
    # rule: the reading attaches to the maximal preceding run of the same
    # character class (kanji run, katakana run, …); ｜ (U+FF5C) scopes the
    # base explicitly and is itself removed. A 《…》 with NO determinable
    # base (nothing before it, or a non-runnable character) is kept verbatim
    # in the text and counted (annotations "ruby_orphans" + document count)
    # — loud, never dropped.
    #
    # == Gaiji ※［＃…］, survey §4c — resolve mechanically where certain,
    #    stay loud where not
    #
    # (a) JIS X 0213 kuten `第N水準X-Y-Z` → resolved through the shipped
    #     JIS X 0213:2004 table (Jis0213) into the real character — this is
    #     upstream's own identity claim, not a guess. The resolved char goes
    #     INTO the text (so a following ruby scopes onto it); the notation
    #     rides annotations "gaiji" ({"class"=>"kuten", "kuten", "char",
    #     "desc", "loc"?}).
    # (b) explicit `U+XXXX` → resolved directly ({"class"=>"unicode", …}).
    # (c) component-description only (no kuten, no U+) → NOT mechanically
    #     resolvable: the verbatim notation STAYS in the text as a loud
    #     sentinel (the kanripo &KR…; precedent) + annotation
    #     ({"class"=>"unresolved", "notation", "desc"}), counted in document
    #     metadata "gaiji_unresolved". A kuten/U+ the table cannot map falls
    #     to the same sentinel — never a silent guess. No IDS derivation at
    #     parse time (the display ladder is the sibling packet's surface).
    #
    # == Formatting commands ［＃…］ without ※, survey §4d
    #
    # Never emitted as passage text. KNOWN commands (the survey's censused
    # vocabulary: indents, headings, emphasis dots/lines, small-print,
    # warichu, page breaks, right/left small print) ride annotations
    # "commands" verbatim; heading references additionally map to structure
    # (annotations "heading" {"text","kind"} — the quoted heading text
    # remains the passage). UNKNOWN commands ride annotations
    # "unknown_commands" + the document-level "unknown_commands" census —
    # LOUD, but never a quarantine: a 17.5k-work corpus with a long-tail
    # command vocabulary would quarantine absurdly, so the honest mechanism
    # is the count + journal, not refusal (deliberate, P38-3).
    class AozoraRubyParser
      LANGUAGE = "jpn"

      DELIMITER = /\A-{10,}\z/
      COLOPHON_START = /\A底本：/

      GAIJI = /※［＃(?<body>[^］]*)］/
      COMMAND = /［＃(?<body>[^］]*)］/
      RUBY = /《(?<reading>[^》]*)》/
      PIPE = "｜" # U+FF5C FULLWIDTH VERTICAL LINE — the explicit base scope

      # Gaiji notation grammars (survey §4c, greedy desc so the LAST
      # resolver token anchors): kuten `…、第N水準men-ku-ten[、loc]` and
      # unicode `…、U+XXXX[、loc]`.
      KUTEN_GAIJI = /\A(?<desc>.+)、第\d水準(?<men>\d+)-(?<ku>\d+)-(?<ten>\d+)(?:、(?<loc>.*))?\z/
      UNICODE_GAIJI = /\A(?<desc>.+)、[Uu]\+(?<hex>\h{4,6})(?:、(?<loc>.*))?\z/

      # The KNOWN formatting-command vocabulary (survey §4d census + the two
      # fixture works). N admits ASCII, fullwidth and kanji numerals.
      N = /[0-9０-９一二三四五六七八九十]+/
      HEADING_REF = /\A「(?<text>.+)」は(?<kind>(?:同行|窓)?[大中小]見出し)\z/
      KNOWN_COMMANDS = [
        /\Aここから#{N}字下げ\z/, /\A#{N}字下げ\z/, /\A(?:ここで)?字下げ終わり\z/,
        /\A地から#{N}字上げ\z/, /\A地付き\z/,
        /\A(?:ここから)?#{N}段階(?:小さな|大きな)文字\z/, /\A(?:ここで)?(?:小さな|大きな)文字終わり\z/,
        HEADING_REF, /\A[大中小]見出し\z/, /\A[大中小]見出し終わり\z/,
        /\A「.+」に(?:白ゴマ|丸|白丸|黒三角|白三角|二重丸|蛇の目)?傍点\z/,
        /\A「.+」に(?:二重)?傍線\z/, /\A「.+」に(?:鎖|破|波)線\z/,
        /\A「.+」は行(?:右|左)小書き\z/,
        /\A割り注\z/, /\A割り注終わり\z/,
        /\A改ページ\z/, /\A改丁\z/, /\A改段\z/, /\A改行\z/,
        /\Aページの左右中央\z/
      ].freeze

      # Annotation keys that accumulate as arrays across a passage.
      LIST_KEYS = %w[ruby gaiji commands unknown_commands ruby_orphans].freeze

      # Parse the single-.txt work zip at +zip_path+ into one Document.
      # +urn+ is the document urn the adapter minted; +metadata+ (the
      # adapter's index-derived fields) merges under the parse-derived keys.
      def parse(zip_path, urn:, metadata: {})
        lines = decode(read_zip_member(zip_path)).split(/\r?\n/)
        sections = split_sections(zip_path, lines)
        state = { passages: [], pending: {}, unresolved: 0, unknown: [], orphans: 0, urn: urn }
        sections[:body].each { |line| consume_body_line(state, line) }

        document = Nabu::Document.new(
          urn: urn, language: LANGUAGE, canonical_path: File.expand_path(zip_path),
          title: sections[:title],
          metadata: document_metadata(metadata, sections, state)
        )
        state[:passages].each { |passage| document << passage }
        document
      end

      private

      # -- zip + encoding boundary ---------------------------------------------

      # The zip holds exactly one .txt (name unpredictable); anything else is
      # upstream damage this parser must not guess around.
      def read_zip_member(zip_path)
        members = Shell.run("unzip", "-Z1", zip_path).split("\n")
        texts = members.grep(/\.txt\z/i)
        raise ParseError, "#{zip_path}: expected exactly one .txt member, found #{texts.inspect}" if texts.size != 1

        Shell.run("unzip", "-p", zip_path, texts.first)
      rescue Shell::Error => e
        raise ParseError, "#{zip_path}: unreadable zip (#{e.message})"
      end

      def decode(bytes)
        Nabu::Normalize.nfc(bytes.dup.force_encoding(Encoding::Windows_31J).encode(Encoding::UTF_8))
      rescue EncodingError => e
        raise ParseError, "CP932 decode failed: #{e.message}"
      end

      # -- file structure -------------------------------------------------------

      # Header / legend / body / colophon on the delimiter pair + 底本：.
      def split_sections(zip_path, lines)
        header, legend_and_rest = split_on_delimiter(lines)
        raise ParseError, "#{zip_path}: no legend delimiter (not an Aozora ruby text?)" if legend_and_rest.nil?

        _legend, rest = split_on_delimiter(legend_and_rest)
        raise ParseError, "#{zip_path}: unterminated legend block" if rest.nil?

        body, colophon = split_colophon(rest)
        header_lines = header.reject { |line| blank?(line) }
        raise ParseError, "#{zip_path}: empty header block" if header_lines.empty?

        { title: header_lines.first, header: header_lines.drop(1), body: body, colophon: colophon }
      end

      def split_on_delimiter(lines)
        index = lines.index { |line| DELIMITER.match?(line) }
        return nil if index.nil?

        [lines.take(index), lines.drop(index + 1)]
      end

      def split_colophon(lines)
        index = lines.index { |line| COLOPHON_START.match?(line) }
        return [lines, []] if index.nil?

        [lines.take(index), lines.drop(index)]
      end

      # Blank includes ideographic-space-only lines (U+3000 layout padding).
      def blank?(line)
        line.tr("　", " ").strip.empty?
      end

      # -- body lines -----------------------------------------------------------

      def consume_body_line(state, line)
        return if blank?(line) || DELIMITER.match?(line) # section rules are layout, not text

        text, annotations = process_line(state, line)
        if text.empty?
          merge_annotations!(state[:pending], annotations)
        else
          emit_passage(state, text, annotations)
        end
      end

      def emit_passage(state, text, annotations)
        merged = state[:pending]
        state[:pending] = {}
        merge_annotations!(merged, annotations)
        state[:passages] << Nabu::Passage.new(
          urn: "#{state[:urn]}:#{state[:passages].size + 1}",
          language: LANGUAGE,
          text: Nabu::Normalize.nfc(text),
          sequence: state[:passages].size + 1,
          annotations: merged
        )
      end

      def merge_annotations!(into, from)
        LIST_KEYS.each do |key|
          next unless from.key?(key)

          (into[key] ||= []).concat(from[key])
        end
        into["heading"] = from["heading"] if from.key?("heading")
        into
      end

      # One left-to-right pass over the physical line: gaiji first at each
      # position (※［＃ before ［＃ — the ※ is the class marker), then
      # formatting commands, then ruby markers. Output text accumulates in
      # +out+; ruby boundary state is an index into it.
      def process_line(state, line)
        out = +""
        annotations = {}
        mark = nil
        scanner = StringScanner.new(line)
        until scanner.eos?
          if scanner.scan(GAIJI)
            out << consume_gaiji(state, annotations, scanner[:body])
          elsif scanner.scan(COMMAND)
            consume_command(state, annotations, scanner[:body])
          elsif scanner.scan(RUBY)
            mark = consume_ruby(state, annotations, out, mark, scanner[:reading])
          elsif scanner.skip(/｜/)
            out.insert(mark, PIPE) if mark # an unconsumed earlier ｜ was literal text
            mark = out.length
          else
            out << scanner.scan(/[^※［｜《]+|./)
          end
        end
        out.insert(mark, PIPE) if mark # trailing unconsumed ｜: restore verbatim
        [out, annotations]
      end

      # -- gaiji ----------------------------------------------------------------

      # Returns the text fragment the notation contributes: the resolved
      # character for classes (a)/(b), the verbatim notation sentinel
      # otherwise (never a guess, never a silent drop).
      def consume_gaiji(state, annotations, body)
        if (match = KUTEN_GAIJI.match(body))
          char = Jis0213.resolve(plane: match[:men].to_i, row: match[:ku].to_i, cell: match[:ten].to_i)
          if char
            return resolved_gaiji(annotations, match, char,
                                  "kuten" => "#{match[:men]}-#{match[:ku]}-#{match[:ten]}")
          end
        elsif (match = UNICODE_GAIJI.match(body))
          char = [match[:hex].to_i(16)].pack("U*")
          return resolved_gaiji(annotations, match, char, "codepoint" => "U+#{match[:hex].upcase}")
        end
        unresolved_gaiji(state, annotations, body)
      end

      def resolved_gaiji(annotations, match, char, identity)
        entry = { "class" => identity.key?("kuten") ? "kuten" : "unicode", "desc" => bare_desc(match[:desc]) }
        entry.merge!(identity)
        entry["char"] = char
        entry["loc"] = match[:loc] if match.names.include?("loc") && match[:loc]
        (annotations["gaiji"] ||= []) << entry
        char
      end

      def unresolved_gaiji(state, annotations, body)
        notation = "※［＃#{body}］"
        state[:unresolved] += 1
        desc = body[/\A「(?<d>[^」]*)」/, :d] || body
        (annotations["gaiji"] ||= []) << { "class" => "unresolved", "desc" => desc, "notation" => notation }
        notation
      end

      # `「執／糸」` → `執／糸`; a desc only PARTLY wrapped (「插」でつくりの…)
      # stays whole — the wrapper strips only when it spans the entire desc.
      def bare_desc(desc)
        desc[/\A「(?<d>[^「」]*)」\z/, :d] || desc
      end

      # -- formatting commands --------------------------------------------------

      def consume_command(state, annotations, body)
        if KNOWN_COMMANDS.any? { |pattern| pattern.match?(body) }
          (annotations["commands"] ||= []) << body
          if (match = HEADING_REF.match(body))
            annotations["heading"] = { "text" => match[:text], "kind" => match[:kind] }
          end
        else
          state[:unknown] << body
          (annotations["unknown_commands"] ||= []) << body
        end
      end

      # -- ruby -----------------------------------------------------------------

      # Consume one 《reading》 against the current output. Returns the new
      # mark state (always nil — a reading consumes any pending ｜ scope).
      def consume_ruby(state, annotations, out, mark, reading)
        base = mark ? out[mark..] : auto_boundary_base(out)
        if base.nil? || base.empty?
          state[:orphans] += 1
          (annotations["ruby_orphans"] ||= []) << reading
          out << "《#{reading}》" # kept verbatim — loud, nothing dropped
        else
          (annotations["ruby"] ||= []) << { "base" => base, "reading" => reading }
        end
        nil
      end

      # The maximal preceding run of the same character class (survey §4b:
      # kanji run, katakana run, …). ー extends either kana run.
      def auto_boundary_base(out)
        klass = char_class(out[-1])
        return nil if klass == :other

        length = 0
        length += 1 while length < out.length && run_member?(out[-1 - length], klass)
        out[-length..]
      end

      def run_member?(char, klass)
        char_class(char) == klass || (char == "ー" && %i[katakana hiragana].include?(klass))
      end

      def char_class(char)
        case char
        when /\p{Han}/, "々", "〆", "〇", "仝" then :han
        # ー (the prolonged-sound mark) classes katakana here but extends
        # either kana run (run_member?).
        when "ー", /\p{Katakana}/, "ヽ", "ヾ" then :katakana
        when /\p{Hiragana}/, "ゝ", "ゞ" then :hiragana
        when /[A-Za-zＡ-Ｚａ-ｚ]/ then :latin
        when /[0-9０-９]/ then :digit
        else :other # nil included — regexps never match nil
        end
      end

      # -- document metadata ----------------------------------------------------

      def document_metadata(index_metadata, sections, state)
        metadata = index_metadata.merge(
          "header" => sections[:header].reject { |line| blank?(line) },
          "colophon" => sections[:colophon].join("\n")
        )
        extract_colophon_fields(metadata, sections[:colophon])
        metadata["gaiji_unresolved"] = state[:unresolved] if state[:unresolved].positive?
        metadata["ruby_orphans"] = state[:orphans] if state[:orphans].positive?
        metadata["unknown_commands"] = state[:unknown].uniq.sort unless state[:unknown].empty?
        metadata
      end

      def extract_colophon_fields(metadata, colophon)
        colophon.each do |line|
          case line
          when /\A底本：(.+)\z/ then metadata["teihon"] ||= Regexp.last_match(1).strip
          when /\A入力：(.+)\z/ then metadata["inputter"] ||= Regexp.last_match(1).strip
          when /\A校正：(.+)\z/ then metadata["proofer"] ||= Regexp.last_match(1).strip
          end
        end
      end
    end
  end
end
