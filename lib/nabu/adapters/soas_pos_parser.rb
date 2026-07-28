# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Adapters
    # Streaming parser for the SOAS "Tibetan in Digital Communication" gold
    # POS corpus's own format (the `soas-pos` family, P48-3) — censused from
    # all 8 real files in the Zenodo Texts.zip (2026-07-28):
    #
    #   one line  = one editorial chunk of running text (the corpus's only
    #               stable address — 991 lines across the four texts);
    #   one token = `form|tag`, space-separated — EVERY token carries exactly
    #               one `|`; tags are Garrett et al. 2014/2015 POS labels
    #               (`n.count`, `case.gen`, `v.past`, `punc`, `skt`, plus
    #               `~`-joined variants like `cl.quot~quote.E`).
    #
    # No existing family fits (no tabs, no sent_id, no XML), hence this
    # small bespoke class — same call shape as ConlluParser#parse.
    #
    # == Passage minting
    #
    # - urn = "<document-urn>:<line-number>" — the 1-based PHYSICAL line
    #   number, so citations stay stable even if a future revision of the
    #   deposit inserted a blank line (none exists today; blanks are skipped
    #   without minting).
    # - text = the forms joined with NOTHING: the forms are Unicode Tibetan
    #   syllables carrying their own tsheg/shad, so any separator would
    #   corrupt the text. NFC at the boundary (upstream is NFC-stable).
    # - annotations = { "tokens" => [{"form","pos"}, …] }. There is NO lemma
    #   column anywhere in the corpus: tokens deliberately mint no "lemma"
    #   key, so the lemma index gains zero rows from this source — honest
    #   absence, never a faked lane.
    #
    # A token without `|` is a ParseError naming line and token (quarantine,
    # never paper over) — the census says it cannot happen, so if it does the
    # upstream file changed shape.
    class SoasPosParser
      # Same signature family as ConlluParser#parse; +source+ is a path
      # (String) or an IO-like (StringIO in tests).
      def parse(source, urn:, language:, title: nil, canonical_path: nil, metadata: {})
        document = Nabu::Document.new(
          urn: urn, language: language, title: title, metadata: metadata,
          canonical_path: canonical_path || source.to_s
        )

        sequence = 0
        each_line(source) do |line, line_no|
          tokens = split_tokens(line, source: source, line_no: line_no)
          next if tokens.empty?

          document << build_passage(tokens, document_urn: urn, language: language,
                                            line_no: line_no, sequence: sequence)
          sequence += 1
        end

        raise Nabu::ParseError, "#{source}: no form|tag lines found" if document.empty?

        document
      end

      private

      def each_line(source)
        line_no = 0
        read_lines(source) do |raw|
          line_no += 1
          yield raw.chomp, line_no
        end
      end

      # A String is always a path (ConlluParser's rule) — String#each_line
      # would iterate the path text itself.
      def read_lines(source, &block)
        if source.is_a?(String)
          File.open(source, "r:UTF-8") { |io| io.each_line(&block) }
        else
          source.each_line(&block)
        end
      end

      # The `form|tag` pairs of one line. rsplit on the LAST pipe: forms are
      # Tibetan syllables (no pipes censused), but the tag charset is the
      # narrow side, so anchoring on the last separator is the robust cut.
      def split_tokens(line, source:, line_no:)
        line.split.filter_map do |pair|
          next if pair.empty?

          form, _, tag = pair.rpartition("|")
          if form.empty? || tag.empty?
            raise Nabu::ParseError,
                  "#{source}: line #{line_no}: expected form|tag, got #{pair.inspect}"
          end
          { "form" => form, "pos" => tag }
        end
      end

      def build_passage(tokens, document_urn:, language:, line_no:, sequence:)
        text = Nabu::Normalize.nfc(tokens.map { |token| token["form"] }.join)
        Nabu::Passage.new(
          urn: "#{document_urn}:#{line_no}",
          language: language,
          text: text,
          annotations: { "tokens" => tokens },
          sequence: sequence
        )
      end
    end
  end
end
