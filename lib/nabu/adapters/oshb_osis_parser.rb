# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The OSHB OSIS book parser (P26-3, parser family "oshb-osis"): one
    # openscriptures/morphhb wlc/<Book>.xml file → one Document, one passage
    # per container verse, urn <doc-urn>:<chapter>.<verse> from the native
    # Masoretic osisIDs ("Gen.1.1" → "1.1").
    #
    # == Byte-verbatim text (the owner's P26-3 NFC ruling, 2026-07-18)
    #
    # WLC text is stored EXACTLY as upstream ships it — never NFC-normalized:
    # NFC reorders Hebrew combining marks by canonical combining class
    # (dagesh ccc 21 vs vowel points ccc 10–19), rewriting the Masoretic mark
    # order, and upstream's own README warns against NFC. The verse text is
    # assembled from the file's own bytes: each <w>'s character data with the
    # OSHB morpheme divider "/" removed (markup, not WLC text — it segments
    # the word against the composite lemma/morph values), each top-level
    # <seg> (maqqef, sof pasuq, paseq, the samekh/pe parashah marks) verbatim,
    # joined by a single space exactly where the source file itself puts
    # whitespace between elements — so maqqef and sof pasuq attach directly,
    # word gaps stay word gaps, and nothing is invented. <note> apparatus is
    # never running text. Nabu::Passage admits the un-normalized bytes via the
    # per-language NFC exemption (Normalize::NFC_EXEMPT_LANGUAGES).
    #
    # == Tokens: the Strong's lemma lane and the OSHM morphology
    #
    # Every <w> becomes a token in the P7-5 "tokens" contract: "form" (the
    # slash-stripped word bytes), "lemma" = @lemma VERBATIM — an AUGMENTED
    # STRONG'S id ("b/7225", "1254 a", "c/3212"), the only lemma identity the
    # data provides; no display headword is invented — "morph" = the OSHM
    # code verbatim ("HC/Vqw3ms"), "id" = the immutable OSHB word id, "n" =
    # the cantillation-hierarchy attribute when present, and "lang" from the
    # OSHM language prefix (H → hbo, A → arc; any other prefix is a
    # ParseError, never a guess).
    #
    # == Language honesty (the corph majority mechanics)
    #
    # OSHM marks Hebrew vs Aramaic per word. Each passage takes the majority
    # over its tokens' "lang" votes (Jer 10:11 votes arc inside a Hebrew
    # book; Gen 31:47's two Aramaic words stay token-grain); the document
    # takes the majority over all tokens; a verse with no voting tokens falls
    # back to the document majority.
    #
    # == Apparatus notes
    #
    # <note type="variant"> is the ketiv/qere apparatus: the running text
    # keeps the ketiv <w> (marked type="x-ketiv"); the qere reading(s) inside
    # <rdg type="x-qere"> attach to that token as "qere" word hashes.
    # <note type="alternative"> (BHS/BHQ accent variants, <rdg
    # type="x-accent">) attaches to the preceding token as "alternative".
    # Bare and exegesis notes ride the passage's "notes" annotation verbatim.
    class OshbOsisParser
      LANGUAGE_BY_MORPH_PREFIX = { "H" => "hbo", "A" => "arc" }.freeze

      # Fallback when a whole book yields no morph-tagged words at all —
      # cannot happen upstream (morphology is complete), but never guess.
      DEFAULT_LANGUAGE = "hbo"

      def parse(path, urn:)
        xml = parse_xml(path)
        verses = xml.xpath("//verse")
        raise Nabu::ParseError, "#{path}: no <verse> elements" if verses.empty?

        built = verses.map { |verse| build_verse(verse, path: path) }
        language = majority_language(built.flat_map { |v| v[:tokens] }) || DEFAULT_LANGUAGE
        document = Nabu::Document.new(
          urn: urn, language: language, title: book_code(xml, path),
          canonical_path: File.expand_path(path)
        )
        built.each_with_index do |verse, sequence|
          document << passage(verse, urn: urn, sequence: sequence, fallback: language)
        end
        document
      end

      private

      def parse_xml(path)
        xml = Nokogiri::XML(File.read(path), &:strict)
        xml.remove_namespaces!
        xml
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed OSIS XML (#{e.message})"
      end

      def book_code(xml, path)
        code = xml.at_xpath("//div[@type='book']/@osisID")&.value.to_s
        raise Nabu::ParseError, "#{path}: no <div type=\"book\"> osisID" if code.empty?

        code
      end

      # One <verse> → { tail:, text:, tokens:, notes: }. Text assembly walks
      # every child node in document order; a whitespace text node between two
      # kept elements becomes exactly one space (class note).
      def build_verse(verse, path:)
        osis_id = verse["osisID"].to_s
        tail = osis_id.split(".", 2).last.to_s
        unless tail.match?(/\A\d+\.\d+\z/)
          raise Nabu::ParseError, "#{path}: verse osisID #{osis_id.inspect} is not Book.Chapter.Verse"
        end

        state = { text: +"", pending: false, tokens: [], notes: [] }
        verse.children.each { |node| consume(node, state, path: path) }
        raise Nabu::ParseError, "#{path}: verse #{osis_id} has no text" if state[:text].empty?

        { tail: tail, text: state[:text].freeze, tokens: state[:tokens], notes: state[:notes] }
      end

      def consume(node, state, path:)
        case node.name
        when "text"
          unless node.text.strip.empty?
            raise Nabu::ParseError, "#{path}: stray character data #{node.text.strip.inspect} inside a verse"
          end

          state[:pending] = true
        when "w"
          append(state, word_form(node))
          state[:tokens] << token(node, path: path)
        when "seg" then append(state, node.text)
        when "note" then consume_note(node, state, path: path)
        when "comment" then nil
        else
          raise Nabu::ParseError, "#{path}: unexpected <#{node.name}> inside a verse"
        end
      end

      def append(state, text)
        state[:text] << " " if state[:pending] && !state[:text].empty?
        state[:text] << text
        state[:pending] = false
      end

      # The OSHB morpheme divider "/" segments the word against its composite
      # lemma/morph values; it is markup, never WLC text. Everything else —
      # including <seg> letter-size/suspended marks inside the word — is the
      # word's own character data, kept byte-verbatim.
      def word_form(word)
        word.text.delete("/")
      end

      def token(word, path:)
        token = { "form" => word_form(word) }
        %w[lemma morph id n type].each do |attribute|
          value = word[attribute].to_s
          token[attribute] = value unless value.empty?
        end
        token["lang"] = morph_language(token["morph"], path: path) if token.key?("morph")
        token
      end

      def morph_language(morph, path:)
        LANGUAGE_BY_MORPH_PREFIX.fetch(morph[0]) do
          raise Nabu::ParseError, "#{path}: OSHM morph #{morph.inspect} has no H/A language prefix"
        end
      end

      # Apparatus, never running text. variant → the qere reading(s) attach
      # to the preceding (ketiv) token; alternative → the accent reading
      # attaches as "alternative"; anything else rides the passage notes.
      def consume_note(note, state, path:)
        case note["type"]
        when "variant" then attach_readings(note, state, key: "qere", path: path)
        when "alternative" then attach_alternative(note, state)
        else
          text = note.text.strip
          state[:notes] << text unless text.empty?
        end
      end

      def attach_readings(note, state, key:, path:)
        words = note.xpath("./rdg/w")
        return if words.empty?

        target = state[:tokens].last
        raise Nabu::ParseError, "#{path}: a variant note precedes any word" if target.nil?

        target[key] = words.map { |word| token(word, path: path) }
      end

      def attach_alternative(note, state)
        reading = note.at_xpath("./rdg")&.text.to_s.strip
        target = state[:tokens].last
        return if reading.empty? || target.nil?

        target["alternative"] = reading
      end

      def passage(verse, urn:, sequence:, fallback:)
        annotations = { "tokens" => verse[:tokens] }
        annotations["notes"] = verse[:notes] unless verse[:notes].empty?
        Nabu::Passage.new(
          urn: "#{urn}:#{verse[:tail]}",
          language: majority_language(verse[:tokens]) || fallback,
          text: verse[:text],
          annotations: annotations,
          sequence: sequence
        )
      end

      # Majority "lang" vote over tokens (insertion order breaks ties —
      # deterministic; the corph precedent), or nil when nothing votes.
      def majority_language(tokens)
        votes = tokens.filter_map { |token| token["lang"] }
        return nil if votes.empty?

        votes.tally.max_by { |_code, count| count }.first
      end
    end
  end
end
