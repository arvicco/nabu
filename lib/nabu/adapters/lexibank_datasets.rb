# frozen_string_literal: true

require_relative "lexibank_cldf"

module Nabu
  module Adapters
    # The lexibank-cldf intake, wave 1 — eight CC BY 4.0 lexibank CLDF
    # Wordlists with cognate tables, each a declaration over the shared
    # family (LexibankCldf + LexibankCldfParser; seam and pinning argued
    # there). Ranked HIGH by the 2026-11-13 lexibank census; licenses read
    # at fixture time from each release's own README ("This dataset is
    # licensed under a CC-BY-4.0 license"), LICENSE (the CC BY 4.0 legal
    # code) and cldf-metadata.json dc:license, all agreeing → attribution.
    # Two census wave-1 names are NOT here: meloniromance is already held
    # (its own adapter, live since 2026-10-22) and ielexfinal ships no word
    # forms at all (every one of its 21,483 forms is the "---" placeholder
    # — cognate classes with nothing to land as a reflex).
    #
    # Reconstructed varieties map onto registry codes ONLY where the
    # nabu-lects codemap already resolves them (poz-oce-pro, poz-mic-pro,
    # poz-pol-pro, …); every other proto variety stays display-only with a
    # namespaced lang_code until the registry carries its node.

    # Dyen, Kruskal & Black 1992 — 95 modern Indo-European Swadesh-200
    # lists in Dyen's ASCII transcription, 2,388 cognate classes. No
    # reconstructions: the concept heads each class. The repository has
    # never cut a release (no tag, no Zenodo record) — git arm.
    class Dyenindoeuropean < LexibankCldf
      DATASET = Dataset.new(
        slug: "dyenindoeuropean",
        name: "Dyen, Kruskal & Black 1992 Indo-European cognate classes (lexibank/dyenindoeuropean CLDF)",
        title: "Dyen et al. 1992 — Indo-European Swadesh-200 cognate classes",
        label: "Dyen et al. 1992",
        language: "ine",
        license: "CC BY 4.0 (README verbatim: \"This dataset is licensed under a CC-BY-4.0 license\"; " \
                 "LICENSE + cldf-metadata.json dc:license agree; cite Dyen, Kruskal & Black 1992, " \
                 "An Indoeuropean Classification: A lexicostatistical experiment, TAPS 82(5))",
        upstream_url: "https://github.com/lexibank/dyenindoeuropean",
        release: LexibankCldf::GitRepository.new(
          repo_url: "https://github.com/lexibank/dyenindoeuropean",
          commit: "cd1ad5f8b20e2bf2acd4823cbb93a411809036e9"
        )
      )
    end

    # Saenko 2015 (Global Lexicostatistical Database) — 43 Romance
    # varieties × 110 concepts, 465 cognate sets; Value carries the
    # transcription with the orthography in braces (the :value_braces
    # strategy). Loan-flagged forms sit in their own singleton sets.
    class Saenkoromance < LexibankCldf
      DATASET = Dataset.new(
        slug: "saenkoromance",
        name: "Saenko 2015 annotated Swadesh wordlists for the Romance group (lexibank/saenkoromance CLDF v1.1)",
        title: "Saenko 2015 — Romance Swadesh-110 cognate sets",
        label: "Saenko 2015",
        language: "roa",
        license: "CC BY 4.0 (README verbatim: \"This dataset is licensed under a CC-BY-4.0 license\"; " \
                 "LICENSE + cldf-metadata.json dc:license agree; Zenodo 10.5281/zenodo.13163492 " \
                 "cc-by-4.0; cite Saenko 2015, Annotated Swadesh wordlists for the Romance group, " \
                 "The Global Lexicostatistical Database)",
        upstream_url: "https://doi.org/10.5281/zenodo.13163492",
        release: LexibankCldf::ZenodoRelease.new(
          tag: "v1.1", record: 13_163_492,
          url: "https://zenodo.org/api/records/13163492/files/lexibank/saenkoromance-v1.1.zip/content",
          sha256: "f02dbdde7540775d00a3696b477488c7241c8d9b5dec541b357a116ae2448a63"
        ),
        word_from: :value_braces,
        rejected_grains: { "raw" => "upstream's pre-CLDF source tables" }
      )
    end

    # The lexicon of Proto Oceanic (Ross, Pawley & Osmond, vols 1–6) —
    # 2,821 reconstruction-headed sets (POc and its daughters, with PAn/
    # PMP antecedents), 755 varieties. The release zip also ships the raw
    # OCR'd volumes and the rendered book (out/): both rejected grains —
    # the archive is 318 MB for ~10 MB of CLDF.
    class Tlopo < LexibankCldf
      DATASET = Dataset.new(
        slug: "tlopo",
        name: "The lexicon of Proto Oceanic (Ross, Pawley & Osmond; lexibank/tlopo CLDF v0.1.1)",
        title: "TLoPO — The lexicon of Proto Oceanic (Ross, Pawley & Osmond)",
        label: "TLoPO",
        language: "poz-oce",
        license: "CC BY 4.0 (README verbatim: \"This dataset is licensed under a CC-BY-4.0 license\"; " \
                 "LICENSE + cldf-metadata.json dc:license agree; Zenodo 10.5281/zenodo.23688418 " \
                 "cc-by-4.0; cite Ross, Pawley & Osmond, The lexicon of Proto Oceanic, vols 1–6)",
        upstream_url: "https://doi.org/10.5281/zenodo.23688418",
        release: LexibankCldf::ZenodoRelease.new(
          tag: "v0.1.1", record: 23_688_418,
          url: "https://zenodo.org/api/records/23688418/files/tlopo-v0.1.1.zip/content",
          sha256: "fac45c143c93cd957f64e75f9f3f6ef86c9cdde708c22ceebc1d772b79578704"
        ),
        varieties: {
          "poc" => "poz-oce-pro", "pemp" => "pqe-pro", "pmic" => "poz-mic-pro",
          "pcp" => "poz-pcc-pro", "ppn" => "poz-pol-pro", "pnpn" => "poz-pnp-pro",
          "pepn" => "poz-pep-pro"
        },
        rejected_grains: {
          "raw" => "upstream's OCR'd source volumes",
          "out" => "the rendered book chapters (HTML/Markdown)"
        }
      )
    end

    # The Austronesian Comparative Dictionary (Blust, Trussel & Smith) —
    # 10,857 reconstruction-headed sets (PAn down to low-level protos)
    # over 1,063 varieties, with acd's etymon records and loan events.
    class Acd < LexibankCldf
      DATASET = Dataset.new(
        slug: "acd",
        name: "Austronesian Comparative Dictionary (Blust, Trussel & Smith; lexibank/acd CLDF v2.0)",
        title: "ACD — Austronesian Comparative Dictionary (Blust, Trussel & Smith)",
        label: "ACD",
        language: "map",
        license: "CC BY 4.0 (README verbatim: \"This dataset is licensed under a CC-BY-4.0 license\"; " \
                 "LICENSE + cldf-metadata.json dc:license agree; Zenodo 10.5281/zenodo.14608975 " \
                 "cc-by-4.0; cite Blust, Trussel & Smith, Austronesian Comparative Dictionary)",
        upstream_url: "https://doi.org/10.5281/zenodo.14608975",
        release: LexibankCldf::ZenodoRelease.new(
          tag: "v2.0", record: 14_608_975,
          url: "https://zenodo.org/api/records/14608975/files/lexibank/acd-v2.0.zip/content",
          sha256: "6141f908af0b7e9733176e838b59e586c092e78f405c874b8dff0baaf3447d01"
        ),
        varieties: {
          "20001" => "pqe-pro", "19082" => "poz-oce-pro", "19079" => "poz-mic-pro",
          "19084" => "poz-pol-pro"
        },
        rejected_grains: { "raw" => "upstream's pre-CLDF source dumps and update logs" }
      )
    end

    # The Micronesian Comparative Dictionary (Bender et al. 2003,
    # Proto-Micronesian Reconstructions 1–2) — 1,707 sets headed by PMc
    # and sub-group reconstructions, 60 varieties.
    class Mcd < LexibankCldf
      DATASET = Dataset.new(
        slug: "mcd",
        name: "Micronesian Comparative Dictionary (Bender et al. 2003; lexibank/mcd CLDF v2.0)",
        title: "MCD — Micronesian Comparative Dictionary (Bender et al. 2003)",
        label: "MCD",
        language: "poz-mic",
        license: "CC BY 4.0 (README verbatim: \"This dataset is licensed under a CC-BY-4.0 license\"; " \
                 "LICENSE + cldf-metadata.json dc:license agree; Zenodo 10.5281/zenodo.14608119 " \
                 "cc-by-4.0; cite Bender, Goodenough, Jackson, Marck, Rehg, Sohn, Trussel & Wang " \
                 "2003, Proto-Micronesian Reconstructions 1–2, Oceanic Linguistics 42)",
        upstream_url: "https://doi.org/10.5281/zenodo.14608119",
        release: LexibankCldf::ZenodoRelease.new(
          tag: "v2.0", record: 14_608_119,
          url: "https://zenodo.org/api/records/14608119/files/lexibank/mcd-v2.0.zip/content",
          sha256: "d3a50f4dafa321f95e202e1cc566cdb4f5408acc27e0204b584b54ddb028083a"
        ),
        varieties: {
          "protooceanic" => "poz-oce-pro", "protomicronesian" => "poz-mic-pro",
          "protopolynesian" => "poz-pol-pro"
        },
        rejected_grains: { "raw" => "upstream's pre-CLDF source pages and tables" }
      )
    end

    # The Comparative Siouan Dictionary (Rankin et al. 2015) — 1,204 sets
    # headed by Proto-Siouan and sub-group reconstructions over 36
    # varieties. Upstream's languages.csv carries NO ISO or Glottocode for
    # any variety, so every member is display-only (namespaced codes).
    # Never released (no tag, no Zenodo record) — git arm.
    class Csd < LexibankCldf
      DATASET = Dataset.new(
        slug: "csd",
        name: "Comparative Siouan Dictionary (Rankin et al. 2015; lexibank/csd CLDF)",
        title: "CSD — Comparative Siouan Dictionary (Rankin et al. 2015)",
        label: "CSD",
        language: "sio",
        license: "CC BY 4.0 (README verbatim: \"This dataset is licensed under a " \
                 "http://creativecommons.org/licenses/by/4.0/ license\"; LICENSE + cldf-metadata.json " \
                 "dc:license agree; cite Rankin, Carter, Jones, Koontz, Rood & Hartmann (eds.) 2015, " \
                 "Comparative Siouan Dictionary, csd.clld.org)",
        upstream_url: "https://github.com/lexibank/csd",
        release: LexibankCldf::GitRepository.new(
          repo_url: "https://github.com/lexibank/csd",
          commit: "91756e90cee764dcfe96966e5a82a6092eb35f00"
        )
      )
    end

    # UraLex 2.0 — 27 Uralic varieties × 313 basic-vocabulary meanings,
    # 3,792 cognate sets (Proto-Uralic reconstructions as asterisked
    # members), with curated loan records (borrowings.csv).
    class Uralex < LexibankCldf
      DATASET = Dataset.new(
        slug: "uralex",
        name: "UraLex — Uralic basic vocabulary with cognate and loanword information (lexibank/uralex CLDF v2.0)",
        title: "UraLex 2.0 — Uralic basic-vocabulary cognate sets",
        label: "UraLex",
        language: "urj",
        license: "CC BY 4.0 (README verbatim: \"This dataset is licensed under a CC-BY-4.0 license\"; " \
                 "LICENSE + cldf-metadata.json dc:license agree; Zenodo 10.5281/zenodo.4777568 " \
                 "cc-by-4.0; cite Syrjänen et al. and de Heer et al., the UraLex 2.0 papers)",
        upstream_url: "https://doi.org/10.5281/zenodo.4777568",
        release: LexibankCldf::ZenodoRelease.new(
          tag: "v2.0", record: 4_777_568,
          url: "https://zenodo.org/api/records/4777568/files/lexibank/uralex-v2.0.zip/content",
          sha256: "5e2f2e4e385dbf5308c2f2c264b0fb89d844c8ffe5aef06567957c3357b1afb3"
        ),
        # "Proto-Uralic*" (Subgroup "(reconstr.)") — upstream has no
        # Is_Proto column; its sets head with the reconstruction.
        proto_varieties: ["0"],
        rejected_grains: { "raw" => "upstream's pre-CLDF source tables" }
      )
    end

    # Sagart, Jacques, Lai & List 2019 — 50 Sino-Tibetan varieties × 250
    # concepts, 5,120 cognate sets, incl. Old Chinese, Old Tibetan, Old
    # Burmese and Tangut. Form is a segmentation artifact ("s.t.e.ŋ"), so
    # the source Value is the word (the :value strategy).
    class Sagartst < LexibankCldf
      DATASET = Dataset.new(
        slug: "sagartst",
        name: "Sagart et al. 2019 Sino-Tibetan Database of Lexical Cognates (lexibank/sagartst CLDF v2.1)",
        title: "Sagart et al. 2019 — Sino-Tibetan lexical cognate sets",
        label: "Sagart et al. 2019",
        language: "sit",
        license: "CC BY 4.0 (README verbatim: \"This dataset is licensed under a CC-BY-4.0 license\"; " \
                 "LICENSE + cldf-metadata.json dc:license agree; Zenodo 10.5281/zenodo.13162889 " \
                 "cc-by-4.0; cite Sagart, Jacques, Lai & List 2019, Sino-Tibetan Database of Lexical " \
                 "Cognates)",
        upstream_url: "https://doi.org/10.5281/zenodo.13162889",
        release: LexibankCldf::ZenodoRelease.new(
          tag: "v2.1", record: 13_162_889,
          url: "https://zenodo.org/api/records/13162889/files/lexibank/sagartst-v2.1.zip/content",
          sha256: "7175b7c512897a16d217a013205196ebc8d5023b2777c091e43463205801bfc7"
        ),
        word_from: :value,
        rejected_grains: { "raw" => "upstream's pre-CLDF source data" }
      )
    end
  end
end
