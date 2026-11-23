# frozen_string_literal: true

require_relative "lexibank_cldf"

module Nabu
  module Adapters
    # The lexibank-cldf intake, wave 2 — three CC BY-NC 4.0 lexibank CLDF
    # Wordlists with cognate tables, declarations over the shared family
    # (LexibankCldf + LexibankCldfParser) exactly like wave 1
    # (lexibank_datasets.rb), license class nc. Licenses read at fixture
    # time (2026-11-23) from each repository's README, LICENSE (the CC BY-NC
    # 4.0 legal code, "Attribution-NonCommercial 4.0 International") and
    # cldf-metadata.json dc:license, all agreeing; no ND clause anywhere.
    #
    # One census nc-basket name is NOT here: mixezoqueanvoices (Kondić's
    # Mixe-Zoquean Voices, CC BY-NC 4.0) ships no CognateTable — no
    # cognates.csv in any release (v1.0 … v2.0.1), the forms.csv Cognacy
    # column empty for all 4,888 forms — so the family's one-entry-per-set
    # seam has nothing to mint. It is a wordlist-with-recordings, not a
    # cognate dataset.

    # Kitchen, Ehret, Assefa & Mulligan 2009 — 25 Semitic varieties × 97
    # concepts (Akkadian, Ugaritic, Hebrew, Aramaic, Ge'ez, the modern
    # Ethiosemitic, Modern South Arabian and Arabic lists), 665 expert
    # cognate sets. No reconstructions: the concept heads each set.
    # Upstream tags its Hebrew heb and its Aramaic oar (Old Aramaic) though
    # the paper names its sources "ancient Hebrew" and "Biblical Aramaic"
    # (Rabin 1975) — the ISO codes ride verbatim; the stage refinement is a
    # judgment call left to the registry, never guessed here.
    class Kitchensemitic < LexibankCldf
      DATASET = Dataset.new(
        slug: "kitchensemitic",
        name: "Kitchen et al. 2009 Bayesian phylogenetic analysis of Semitic languages " \
              "(lexibank/kitchensemitic CLDF v2.1)",
        title: "Kitchen et al. 2009 — Semitic basic-vocabulary cognate sets",
        label: "Kitchen et al. 2009",
        language: "sem",
        license: "CC BY-NC 4.0 (README verbatim: \"This dataset is licensed under a " \
                 "https://creativecommons.org/licenses/by-nc/4.0/ license\"; LICENSE (Attribution-" \
                 "NonCommercial 4.0 International) + cldf-metadata.json dc:license agree; Zenodo " \
                 "10.5281/zenodo.17510140 cc-by-nc-4.0; cite Kitchen, Ehret, Assefa & Mulligan 2009, " \
                 "Bayesian phylogenetic analysis of Semitic languages identifies an Early Bronze Age " \
                 "origin of Semitic in the Near East, Proc. R. Soc. B, doi:10.1098/rspb.2009.0408)",
        license_class: "nc",
        upstream_url: "https://doi.org/10.5281/zenodo.17510140",
        release: LexibankCldf::ZenodoRelease.new(
          tag: "v2.1", record: 17_510_140,
          url: "https://zenodo.org/api/records/17510140/files/lexibank/kitchensemitic-v2.1.zip/content",
          sha256: "4bde45028d2d45c7079ab2e30094dd426969a7630e29316f36a5ad9528e3be2a"
        ),
        rejected_grains: { "raw" => "upstream's pre-CLDF source wordlists and coding sheets" }
      )
    end

    # Zhang, Jacques & Lai 2019 — 122 cognate sets between Old Chinese
    # (Baxter-Sagart), Middle Chinese and the Gyalrongic languages
    # (Cogtse and Brag-bar Situ, Japhug, Zbu) with Classical Tibetan. Value
    # is the published spelling (the asterisked Old Chinese, the Gyalrong
    # prefix hyphen); Form rewrites the hyphen as "+" — so :value. The
    # concept's Gloss_in_Source is the Chinese character the Old/Middle
    # Chinese rows read, carried on the body. Never released (no tag, no
    # Zenodo record) — git arm.
    class Zhangrgyalrong < LexibankCldf
      DATASET = Dataset.new(
        slug: "zhangrgyalrong",
        name: "Zhang, Jacques & Lai 2019 A study of cognates between Gyalrong and Old Chinese " \
              "(lexibank/zhangrgyalrong CLDF)",
        title: "Zhang et al. 2019 — Gyalrong–Old Chinese cognate sets",
        label: "Zhang et al. 2019",
        language: "sit",
        license: "CC BY-NC 4.0 (README verbatim: \"This dataset is licensed under a " \
                 "https://creativecommons.org/licenses/by-nc/4.0/ license\"; LICENSE (Attribution-" \
                 "NonCommercial 4.0 International) + cldf-metadata.json dc:license agree; cite Zhang, " \
                 "Jacques & Lai 2019, A study of cognates between Gyalrong and Old Chinese, Journal of " \
                 "Language Relationship 17(1), 73-92)",
        license_class: "nc",
        upstream_url: "https://github.com/lexibank/zhangrgyalrong",
        release: LexibankCldf::GitRepository.new(
          repo_url: "https://github.com/lexibank/zhangrgyalrong",
          commit: "51cdc51964a9a3c0d194f01b6d1ab89c56db2613"
        ),
        word_from: :value,
        concept_notes: { "Gloss_in_Source" => "Chinese character" }
      )
    end

    # Peiros 2004 — Comparative Sino-Tibetan Wordlists: 128 varieties ×
    # 110 concepts (the Starostin-1991 list), 1,806 cognate classes
    # numbered per concept. Value is Peiros's database cell (Old Chinese
    # with its character, "bhaj 皮"; tone digits; loan tags TIB/NEP);
    # Form is the lexibank cleaning (first variant only, spaces as "_", the
    # character dropped) — so :value. Upstream's non-positive class numbers
    # (-1, 0, -666 …; 94 sets, 211 forms) are carried verbatim as the CognateTable
    # states them; the "-1" classes gather mostly loan-tagged forms, but
    # upstream documents no meaning, so no loan flag is inferred. Never
    # released (no tag, no Zenodo record) — git arm.
    class Peirosst < LexibankCldf
      DATASET = Dataset.new(
        slug: "peirosst",
        name: "Peiros 2004 Comparative Sino-Tibetan Wordlists (lexibank/peirosst CLDF)",
        title: "Peiros 2004 — Sino-Tibetan comparative wordlists, cognate classes",
        label: "Peiros 2004",
        language: "sit",
        license: "CC BY-NC 4.0 (README verbatim: \"This dataset is licensed under a CC-BY-NC-4.0 " \
                 "license\"; LICENSE (Attribution-NonCommercial 4.0 International) + cldf-metadata.json " \
                 "dc:license agree; cite Peiros, Ilia (2004): Comparative Sino-Tibetan Wordlists)",
        license_class: "nc",
        upstream_url: "https://github.com/lexibank/peirosst",
        release: LexibankCldf::GitRepository.new(
          repo_url: "https://github.com/lexibank/peirosst",
          commit: "4619b46ac0b9cdba83f19debc1108faebccab229"
        ),
        word_from: :value
      )
    end
  end
end
