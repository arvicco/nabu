# frozen_string_literal: true

module Nabu
  module Adapters
    # The quranic-corpus-tsv family: the Quranic Arabic Corpus morphology
    # file (version 0.4), one tab-separated row per SEGMENT —
    #
    #   LOCATION     FORM        TAG  FEATURES
    #   (1:1:3:2)    r~aHoma`ni  ADJ  STEM|POS:ADJ|LEM:r~aHoma`n|ROOT:rHm|MS|GEN
    #
    # LOCATION = (sura:verse:word:segment); FORM = the segment's surface in
    # (extended) Buckwalter transliteration, possibly empty (208 elided 1S
    # suffix pronouns) and once carrying a space (37:130 <ilo yaAsiyna);
    # TAG = the segment's part-of-speech tag; FEATURES = the pipe-joined
    # feature string, opening with PREFIX / STEM / SUFFIX, with LEM: and
    # ROOT: among its members on stems. The file is ASCII with CRLF line
    # ends and opens with a 57-line preamble: two "#" copyright blocks (the
    # corpus's and the Tanzil text's), blank lines, and the column header.
    #
    # Nothing is rewritten: FORM, TAG and FEATURES ride the token verbatim,
    # LEM and ROOT are their substrings verbatim, and the verse text is the
    # segments' FORMs concatenated per word, words single-space joined in
    # upstream's order.
    class QuranicCorpusParser
      HEADER = "LOCATION\tFORM\tTAG\tFEATURES"
      NOTICE = "Quranic Arabic Corpus (morphology, version 0.4)"
      LOCATION = /\A\((\d+):(\d+):(\d+):(\d+)\)\z/

      # One segment row, decoded. +token+ is its annotation hash.
      Segment = Data.define(:sura, :verse, :word, :segment, :form, :tag, :features) do
        def location = "#{sura}:#{verse}:#{word}:#{segment}"

        def token
          members = features.split("|")
          lemma = members.find { |m| m.start_with?("LEM:") }
          root = members.find { |m| m.start_with?("ROOT:") }
          token = { "id" => location, "form" => form, "tag" => tag, "features" => features }
          token["lemma"] = lemma.delete_prefix("LEM:") if lemma
          token["root"] = root.delete_prefix("ROOT:") if root
          token
        end
      end

      # A data row opens with its "(" location; everything before the
      # first row is the preamble.
      def row?(line) = line.start_with?("(")

      # The preamble must be comment and blank lines carrying the corpus
      # notice, closed by the pinned column header — anything else is a
      # different file.
      def check_preamble!(lines, label:)
        *body, header = lines.map { |line| chomp(line) }
        raise Nabu::ParseError, "#{label}: column header drift (#{header.inspect})" unless header == HEADER

        stray = body.find { |line| !line.empty? && !line.start_with?("#") }
        raise Nabu::ParseError, "#{label}: unexpected preamble line #{stray.inspect}" if stray
        raise Nabu::ParseError, "#{label}: the corpus notice is missing" unless body.any? { |l| l.include?(NOTICE) }

        nil
      end

      # The sura number of a data row (discovery's cheap read).
      def sura_of(line, label:)
        location(chomp(line).split("\t", 2).first, label: label).first
      end

      def segment(line, label:)
        fields = chomp(line).split("\t", -1)
        unless fields.size == 4
          raise Nabu::ParseError, "#{label}: row has #{fields.size} fields, not 4: #{line.inspect}"
        end

        sura, verse, word, seg = location(fields[0], label: label)
        Segment.new(sura: sura, verse: verse, word: word, segment: seg,
                    form: fields[1], tag: fields[2], features: fields[3])
      end

      # Segments → word strings (FORMs concatenated per word) → the verse,
      # words single-space joined.
      def verse_text(segments)
        segments.chunk_while { |a, b| a.word == b.word }.map { |word| word.map(&:form).join }.join(" ")
      end

      private

      def chomp(line) = line.chomp

      def location(field, label:)
        numbers = LOCATION.match(field)&.captures&.map(&:to_i)
        raise Nabu::ParseError, "#{label}: malformed location #{field.inspect}" if numbers.nil? || numbers.include?(0)

        numbers
      end
    end
  end
end
