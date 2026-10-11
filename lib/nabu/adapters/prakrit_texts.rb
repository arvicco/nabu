# frozen_string_literal: true

require_relative "ollett_texts_base"

module Nabu
  module Adapters
    # The Prakrit Digital Texts Project (P118-3; Andrew Ollett;
    # github.com/aso2101/prakrit_texts): TEI editions of Prakrit literature
    # in ISO-15919 romanization — Hāla's Sattasaī, Vākpatirāja's Gaüḍavaho
    # (with its Sanskrit chāyā), Kautūhala's Līlāvaī, Jayavallabha's
    # Vajjālagga, Vimala's Paümacariya, Haribhadra's Samarāiccakahā and
    # Dhuttakkhāṇa, Dhanēśvara's Surasundarīcariya, the lexica
    # (Dēśīnāmamālā, Pāiyalacchī), the grammars (Vararuci's Prākṛtaprakāśa,
    # with Bhāmaha), the Prākṛtapaiṅgala, the gāhā anthologies (Jinēśvara,
    # Tārāyaṇa, Chappaṇṇaya), the Jyōtiṣkaraṇḍaka, the Vyavahārabhāṣya, and
    # the Āgamas Nandī + Aṇuōgaddārāiṁ. Composes the `ollett-tei` family
    # (OllettTextsBase holds identity/discovery/fetch).
    #
    # == Scope (the per-file grant, census 2026-10-11 over 33 files)
    #
    # INGESTED: the 23 files whose <availability> carries the statement
    # "Prakrit Digital Texts Project. Distributed under a Creative Commons
    # Attribution-ShareAlike 4.0 license." — recorded verbatim per document
    # (license_statement), class attribution. One of them,
    # Niryukti-Bhāṣya/Ācāra/ācāraniryukti.xml, is not well-formed upstream
    # (a work in progress: an unclosed start tag, bare "<|75.|>" markers)
    # and quarantines loudly at parse — 22 load.
    #
    # EXCLUDED at discovery, censused with notes (discovery_skips):
    # - the 9 Śvētāmbara Āgama files (Āyāraṅga, Sūyagaḍa, Ṭhāṇa,
    #   Nāyādhammakahāō, Nisīha, Bṛhatkalpa, Piṇḍanijjutti, Dasavēyāliya,
    #   Uttarajjhayaṇa) whose availability holds only the upstream template
    #   comment "<!-- add whatever license you like: -->" — no grant, no
    #   ingest (the parser's license gate refuses them too);
    # - Pravarasēna/Sētu.xml — the Sētubandha is the SARIT edition (its
    #   authority is SARIT, CC BY-SA 3.0), ALREADY HELD as
    #   urn:nabu:sarit:pravarasena-setubandha: a declared overlap, not a
    #   second copy.
    #
    # == Language
    #
    # Census of the 22 loading files: document language pra-Latn ×18
    # (Prakrit, the collective code), pka-Latn ×2 (Ardhamāgadhī — the two
    # Āgamas' own tag), san-Latn ×2 (Vararuci's Prākṛtaprakāśa, with and
    # without Bhāmaha — Sanskrit sūtras on Prakrit); passages pra-Latn
    # 24,809 / san-Latn 1,551 (the two Vararuci files, Tārāyaṇa's ṭīkā,
    # Sanskrit stanzas in Dhuttakkhāṇa and the gāhā anthologies) / pka-Latn
    # 764 — 27,124 in all, <back> included. Gaüḍavaho's Sanskrit chāyā
    # rides annotations, not passages. Four files declare no language at
    # all (Chappaṇṇaya, Sattasaī, Vajjālagga, Prākṛtapaiṅgala) → pra-Latn,
    # the corpus default; the Jyōtiṣkaraṇḍaka declares it on <body>.
    # Declared coarse: the Dēśīnāmamālā and the Bhāmaha commentary's
    # Sanskrit prose blocks carry no own tag upstream and inherit the
    # file's (pra-Latn / san-Latn) — upstream's claim, recorded as is.
    #
    # == Dating (declared): the headers carry only modern edition years
    # (source_edition.date — Weber 1881, Bühler 1879, …), never the
    # works'; no composition date is minted.
    class PrakritTexts < OllettTextsBase
      SLUG = "prakrit-texts"
      REPO_URL = "https://github.com/aso2101/prakrit_texts"
      NAME = "Prakrit Digital Texts Project — Prakrit literature in TEI (A. Ollett)"
      LICENSE = "CC BY-SA 4.0 per file (\"Prakrit Digital Texts Project. Distributed under a Creative Commons " \
                "Attribution-ShareAlike 4.0 license.\"), census 2026-10-11 — only the 23 files carrying it are " \
                "ingested; class attribution"
      CREDIT = "Prakrit Digital Texts Project — Andrew Ollett; funded by NEH HG-5004113 (SARIT) and the " \
               "Milton Fund, Harvard University; github.com/aso2101/prakrit_texts"
      DEFAULT_LANGUAGE = "pra-Latn"
      ALLOWED_LANGUAGES = %w[pra-Latn pka-Latn san-Latn].freeze

      EXCLUDED = {
        "tei/Pravarasēna/Sētu.xml" =>
          "the SARIT Sētubandha (authority SARIT, CC BY-SA 3.0) — already held as " \
          "urn:nabu:sarit:pravarasena-setubandha; declared overlap, not ingested twice"
      }.freeze
    end
  end
end
