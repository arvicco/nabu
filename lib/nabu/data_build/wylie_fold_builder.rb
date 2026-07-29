# frozen_string_literal: true

require_relative "builder"
require_relative "csv_writer"
require_relative "../ops/xct_fold_builder"

module Nabu
  module DataBuild
    # The xct/wylie-fold builder (P50-W3): publishes the authored Tibetan ↔
    # EWTS (THL Extended Wylie) transliteration rule table as a gold-tier
    # nabu-data dataset. OWN AUTHORSHIP — no canonical corpus inputs: the
    # table is curated from the Unicode Tibetan block (U+0F00–U+0FFF) and the
    # published THL EWTS correspondence, and it is the SAME table `rake
    # fold:xct` compiles into Nabu::Xct, Nabu's Tibetan-script → EWTS search
    # transcoder (one source of truth, two consumers;
    # Nabu::Ops::XctFoldBuilder is the shared reader/validator).
    #
    # Because the feature has no canonical cones, the derivation fingerprint
    # has exactly one moving part — the recipe — so the recipe embeds the
    # rule table's sha256: a rule correction re-fingerprints the dataset.
    class WylieFoldBuilder
      FILENAME = "rules.csv"

      NOTES = <<~NOTES.strip
        ## Scope and honest limits

        The table is the WORKING CORE for real canon text, not the whole
        Tibetan block: the 30 native consonants, the retroflex Sanskrit-loan
        letters (T/Th/D/N/Sh), the subjoined series (which, in NFC, also
        carries the decomposed aspirates: gha = U+0F42 U+0FB7), the vowel
        signs including a-chung A and the Old Tibetan reversed gi-gu (-i),
        anusvara/visarga/candrabindu, the head marks, tsheg/shad, and the
        digits. Deliberately NOT curated (pass-through in the transcoder):
        subjoined a-chung/a-chen (U+0FB0/U+0FB8), the fixed-form ra/wa/ya
        (U+0F6A, U+0FBA–0FBC), halanta (U+0F84), tsa-'phru (U+0F39), the
        rare marks U+0F82/U+0F86/U+0F87, and ornamental punctuation
        (U+0F06–0F0A, U+0F0F–0F1F) — honest smaller table over speculative
        completeness.

        The generated transcoder concatenates stack letters WITHOUT the EWTS
        "+" operator (query-form grain: bsgrubs, not b+s+g+r+u+b+s) and
        resolves the vowel-less three-letter syllables the classical grammar
        leaves genuinely ambiguous by preferring the prefix reading, with a
        curated override list for the attested common words (མངས = mangs,
        never mngas; བགས = bags). The precomposed NFC-excluded codepoints
        (U+0F43 etc.) never occur in NFC text and are intentionally absent.

        ## Language scope (the bod call)

        languages.csv lists xct (Classical Tibetan) — the slug's language and
        the holdings this fold serves first (Derge Kangyur/Tengyur, SOAS
        gold). The rules themselves are SCRIPT-level and apply unchanged to
        Old Tibetan (otb) and modern bod: inside Nabu the transcoder
        registers for xct, bod AND otb query folding. The dataset keeps the
        one-language-per-feature rail contract and states the wider
        applicability here instead of duplicating rows.
      NOTES

      def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
        rules = Ops::XctFoldBuilder.new
        count = CsvWriter.write(path: File.join(out_dir, FILENAME),
                                columns: Ops::XctFoldBuilder::COLUMNS, rows: rules.rows)
        BuildResult.new(
          resources: [resource(count)],
          recipe: "authored Tibetan↔EWTS rule table (config/ewts/rules.csv, sha256 " \
                  "#{rules.rules_sha256}); the generated Nabu::Xct transcoder derives " \
                  "from the same table via rake fold:xct",
          citations: citations,
          notes: NOTES
        )
      end

      private

      def resource(count)
        Resource.new(
          name: "rules", path: FILENAME, rows: count,
          fields: Ops::XctFoldBuilder::COLUMNS.map { |name| { name: name, type: "string" } },
          primary_key: ["ID"]
        )
      end

      def citations
        [
          Citation.new(
            key: "unicode-tibetan", type: "misc",
            fields: {
              "title" => "The Unicode Standard, Tibetan block (U+0F00–U+0FFF)",
              "author" => "{The Unicode Consortium}",
              "howpublished" => "https://www.unicode.org/charts/PDF/U0F00.pdf"
            }
          ),
          Citation.new(
            key: "thl-ewts", type: "misc",
            fields: {
              "title" => "THL Extended Wylie Transliteration Scheme (EWTS)",
              "author" => "{Tibetan and Himalayan Library}",
              "howpublished" => "https://www.thlib.org/reference/transliteration/#!essay=/thl/ewts/"
            }
          )
        ]
      end
    end
  end
end
