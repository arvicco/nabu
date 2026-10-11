# frozen_string_literal: true

require_relative "ollett_texts_base"

module Nabu
  module Adapters
    # The Kannada Digital Texts Project (P118-3; Andrew Ollett, text entry
    # Krishnaprasada G. / Adishila Publications; github.com/aso2101/
    # kannada_texts): 16 TEI editions in ISO-15919 romanization — the Old
    # Kannada campū classics (Pampa's Ādipurāṇaṁ and Vikramārjunavijayaṁ of
    # 941, Ponna's Śāntipurāṇaṁ of 953, Ranna's Sāhasabhīmavijayaṁ and his
    # nighaṇṭu, Nāgavarma II's Vardhamānapurāṇaṁ / Kāvyāvalōkanaṁ /
    # Karṇāṭakabhāṣābhūṣaṇaṁ, Janna's Anantanāthapurāṇaṁ) and the later
    # śataka / ṣaṭpadi / sāṅgatya poets (Harihara, Rāghavāṅka, Kanakadāsa,
    # Ratnākaravarṇi, Saṁciya Honnamma). Composes the `ollett-tei` family
    # (OllettTextsBase holds identity/discovery/fetch).
    #
    # == License (the in-file grant governs)
    #
    # README verbatim: "Unless specified otherwise, the data provided in
    # this repository is made available under a CC-BY 4.0 license." Every
    # one of the 16 TEI files DOES specify otherwise — "Kannada Digital
    # Texts Project. Distributed under a Creative Commons
    # Attribution-ShareAlike 4.0 license." (census 2026-10-11) — and the
    # in-file grant governs (the Freising/DHARMA doctrine), recorded
    # verbatim per document. Both are class attribution.
    #
    # == Language
    #
    # kan-Latn (ISO-15919 romanized Kannada; 15 files) and san-Latn (the
    # Karṇāṭakabhāṣābhūṣaṇaṁ is a Sanskrit sūtra grammar with Kannada
    # example lists — README: "this text is in *Sanskrit* with Kannada
    # examples"; Sanskrit stanzas elsewhere). Upstream defect, repaired by
    # declaration: Honnamma's Hadibadeya Dharma declares
    # <text xml:lang="san-Latn"> though the sāṅgatya is Kannada → kan-Latn
    # (keyed by its siglum HaDha, noted in metadata language_repair); its
    # explicitly tagged Sanskrit stanzas stay san-Latn.
    #
    # == Dating (declared coarse)
    #
    # The TEI headers carry only edition years. The repo README dates six
    # files' works ("941", "953", "ca. 1042") — those ride as the attributed
    # COMPOSITION class on the :structured lane (keyed by the work's siglum,
    # a "ca." year as a one-year envelope with the "ca." kept in raw). The
    # other ten works carry no date anywhere in the asset: undated, never
    # guessed. Seven files (Harihara ×2, Honnamma, Kanakadāsa ×2,
    # Rāghavāṅka, Ratnākaravarṇi) carry their sourceDesc only inside an XML
    # comment (Ponna's edition, a template left commented out) — no edition
    # claim is mined from them.
    class KannadaTexts < OllettTextsBase
      SLUG = "kannada-texts"
      REPO_URL = "https://github.com/aso2101/kannada_texts"
      NAME = "Kannada Digital Texts Project — Old and Middle Kannada classics in TEI (A. Ollett)"
      LICENSE = "CC BY-SA 4.0 in every file (\"Kannada Digital Texts Project. Distributed under a Creative " \
                "Commons Attribution-ShareAlike 4.0 license.\" — the in-file grant governs; README: \"Unless " \
                "specified otherwise, the data provided in this repository is made available under a CC-BY 4.0 " \
                "license.\"), census 2026-10-11; class attribution"
      CREDIT = "Kannada Digital Texts Project — Andrew Ollett (TEI), Krishnaprasada G. and Adishila " \
               "Publications (text entry and correction); github.com/aso2101/kannada_texts"
      DEFAULT_LANGUAGE = "kan-Latn"
      ALLOWED_LANGUAGES = %w[kan-Latn san-Latn].freeze

      LANGUAGE_REPAIRS = { "HaDha" => "kan-Latn" }.freeze # Honnamma, Hadibadeya Dharma

      # README "Texts included so far" (retrieved 2026-10-11), keyed by the
      # work's TEI siglum → [not_before, not_after, upstream wording].
      README_DATES = {
        "Ādi" => [941, 941, "941"],
        "ViVi" => [941, 941, "941"],
        "ŚāPu" => [953, 953, "953"],
        "VaPu" => [1042, 1042, "ca. 1042"],
        "Kāvyāva" => [1042, 1042, "ca. 1042"],
        "KaBhāBhū" => [1042, 1042, "ca. 1042"]
      }.freeze

      private

      def refine_metadata(metadata)
        refined = metadata.dup
        if (low, high, wording = README_DATES[metadata["siglum"]])
          refined["date"] = { "not_before" => low, "not_after" => high,
                              "raw" => "#{wording} (the repository README's date for the work)" }
        end
        if (repaired = LANGUAGE_REPAIRS[metadata["siglum"]])
          refined["language_repair"] = "upstream <text xml:lang> reads san-Latn; the work is Kannada → #{repaired}"
        end
        refined
      end
    end
  end
end
