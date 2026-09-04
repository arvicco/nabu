# frozen_string_literal: true

require_relative "perseus"

module Nabu
  module Adapters
    # PerseusDL canonical-farsiLit (P95-4, the long-tail sweep): classical
    # Persian — Hafez's Divan (495 ghazals in 32 alphabet chapters, plus
    # the ghazal-appendix letters) with aligned English and German
    # translations. License read 2026-09-04: the standard PerseusDL repo
    # grant (CC BY-SA 3.0 US). Proper CTS throughout (__cts__.xml,
    # 4-deep cRefPattern: chapter.poem.line.seg).
    #
    # The one delta beyond the namespace: upstream's original-language
    # edition slug is perseus-far<n> while the house language code is
    # "fas" (the openiti/kitab convention) — so LANGUAGES maps the
    # namespace to "fas" and the slug pattern is overridden on the
    # documented First1K seam. The ger1 translation stays out
    # (TRANSLATION_LANGUAGE is eng-only, the house-wide rule).
    class PerseusFarsilit < Perseus
      NAMESPACE = "farsiLit"

      private

      def edition_slug_pattern
        /\Aperseus-far(?<version>\d+)\z/
      end
    end
  end
end
