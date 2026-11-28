# frozen_string_literal: true

require_relative "lexibank_cldf"

module Nabu
  module Adapters
    # The lexibank-cldf intake, the Altaic-area pair — two CC BY 4.0
    # lexibank CLDF Wordlists out of Martine Robbeets's Transeurasian
    # project, declarations over the shared family (LexibankCldf +
    # LexibankCldfParser) exactly like waves 1 and 2. Licenses read at
    # fixture time (2026-11-27) from each release's README ("This dataset
    # is licensed under a CC-BY-4.0 license"), LICENSE (the CC BY 4.0
    # legal code, "Attribution 4.0 International"), cldf-metadata.json
    # dc:license and the Zenodo record, all agreeing → attribution.
    #
    # Both bundles share a shape the earlier waves did not have:
    #
    # - WORD: the source Value, never Form (the peirosst/sagartst reading).
    #   Savelyev's Form is lexibank's IPA rewrite of the Turkological
    #   transcription (Clauson's Old Turkic tïrŋaḳ becomes tɯrŋaq);
    #   Robbeets's Form keeps the first variant only, spaces as "_", the
    #   bracketed alternants dropped (Old Japanese "na ~ nare" → na). The
    #   Value cell rides verbatim, variants, query marks and source tags
    #   included — canonical stays canonical; the folds strip the leading
    #   "?".
    # - ROOT: cognates.csv carries the authors' root label per judgment
    #   (Robbeets "*u-matu", Savelyev "*oglan" / "DIRNAK") — declared as a
    #   judgment note riding the set body; it is no variety's form row, so
    #   the concept still heads each set (no reconstruction is claimed).
    # - VARIETIES mapped only where upstream's OWN row names a registry
    #   code it does not spell (transcription, not judgment): the Codex
    #   Cumanicus row → qwm (Cuman — the ISO the robbeetstriangulation row
    #   for the same witness carries), the two Middle Mongolian rows → xng,
    #   "(Late) Middle Korean" (Glottolog late1258, upstream ISO kor — the
    #   modern language) → okm, the registry's Middle Korean anchor (the
    #   okm → okm:lmk row in config/lect_overrides.yml stages it on the
    #   variety's own "Late Middle Korean" name).
    #   Every other ISO rides verbatim, including both Old Turkic rows'
    #   oui (ISO's Old Uighur, which the registry carries as Old Uyghur
    #   under otk) although both bundles name the variety "Old Turkic" and
    #   Savelyev sources it from Clauson's pre-13th-century dictionary —
    #   the otk/oui refinement is a registry call, never guessed here.

    # Savelyev & Robbeets 2020 — 32 Turkic varieties × 254 concepts, 905
    # expert cognate sets (245 singletons), Old Turkic (Clauson 1972) and
    # Codex Cumanicus Cuman beside the modern languages, Chuvash included.
    # Zenodo record of the v2.1 GitHub release (= the default-branch head
    # 4a54059 at fixture time, last pushed 2024-08-02). Reconciliation
    # (full dry parse 2026-11-27): upstream advertises 8,360 lexemes,
    # "8,360 cognates in 905 cognate sets"; the parse mints 905 entries /
    # 8,360 reflex rows, 0 unjudged forms — accepted = upstream exactly.
    class Savelyevturkic < LexibankCldf
      DATASET = Dataset.new(
        slug: "savelyevturkic",
        name: "Savelyev & Robbeets 2020 Turkic basic-vocabulary cognate sets " \
              "(lexibank/savelyevturkic CLDF v2.1)",
        title: "Savelyev & Robbeets 2020 — Turkic basic-vocabulary cognate sets",
        label: "Savelyev & Robbeets 2020",
        language: "trk",
        license: "CC BY 4.0 (README verbatim: \"This dataset is licensed under a CC-BY-4.0 license\"; " \
                 "LICENSE (Attribution 4.0 International) + cldf-metadata.json dc:license agree; " \
                 "Zenodo 10.5281/zenodo.13163242 cc-by-4.0; cite Savelyev, Alexander and Robbeets, " \
                 "Martine (2020): Bayesian phylolinguistics infers the internal structure and the " \
                 "time-depth of the Turkic language family. Journal of Language Evolution 5.1. 39-53)",
        upstream_url: "https://doi.org/10.5281/zenodo.13163242",
        release: LexibankCldf::ZenodoRelease.new(
          tag: "v2.1", record: 13_163_242,
          url: "https://zenodo.org/api/records/13163242/files/lexibank/savelyevturkic-v2.1.zip/content",
          sha256: "2c40fe6d59db3acbd452756671b993569ac4090b2d380f209e10190cdaf6a440"
        ),
        word_from: :value,
        varieties: { "CodexCumanicus" => "qwm" },
        judgment_notes: { "Root" => "root" },
        rejected_grains: {
          "raw" => "upstream's pre-CLDF source alignment table and bibliography",
          "turkic.nex" => "the NEXUS cognate-character matrix derived for the phylogenetic study"
        }
      )
    end

    # Robbeets et al. 2021 (Nature 599) — 101 Turkic, Mongolic, Tungusic,
    # Koreanic and Japonic varieties × 253 concepts, 3,173 expert cognate
    # sets (812 singletons): Old Turkic, Codex Cumanicus, two Middle
    # Mongolian witnesses (the Secret History, the Muqaddimat al-adab),
    # Jurchen, Manchu, Late Middle Korean and Old Japanese beside the
    # modern varieties. The scout knew the repository as
    # lexibank/robbeetsaltaic; GitHub now answers that name with
    # lexibank/robbeetstriangulation (a rename — the package still calls
    # itself lexibank_robbeetsaltaic in setup.py, while metadata.json and
    # the CLDF bundle say robbeetstriangulation), so the current name is
    # the slug. Zenodo record of the v0.3 GitHub release (= the
    # default-branch head 5f59f15 at fixture time, last pushed
    # 2025-01-08). Reconciliation (full dry parse 2026-11-27): upstream
    # advertises 26,224 lexemes, "26,224 cognates in 3,173 cognate sets";
    # the parse mints 3,173 entries / 26,220 reflex rows, 0 unjudged
    # forms — accepted sets = upstream's 3,173 exactly; the four-row
    # residue is upstream's own "?" placeholder cells (Middle Mongolian
    # (Secret History) 'rope', Southern Evenki (Vershina-Tutury) 'rope'
    # and 'shade / shadow', Okinawa Yonamine 'in'), judged but carrying no form,
    # which mint no reflex by the family rule.
    class Robbeetstriangulation < LexibankCldf
      DATASET = Dataset.new(
        slug: "robbeetstriangulation",
        name: "Robbeets et al. 2021 Transeurasian basic-vocabulary cognate sets " \
              "(lexibank/robbeetstriangulation CLDF v0.3)",
        title: "Robbeets et al. 2021 — Transeurasian basic-vocabulary cognate sets",
        label: "Robbeets et al. 2021",
        language: "tut",
        license: "CC BY 4.0 (README verbatim: \"This dataset is licensed under a CC-BY-4.0 license\"; " \
                 "LICENSE (Attribution 4.0 International) + cldf-metadata.json dc:license agree; " \
                 "Zenodo 10.5281/zenodo.14614177 cc-by-4.0; cite Robbeets, M., Bouckaert, R., " \
                 "Conte, M. et al. Triangulation supports agricultural spread of the Transeurasian " \
                 "languages. Nature 599, 616–621 (2021). https://doi.org/10.1038/s41586-021-04108-8)",
        upstream_url: "https://doi.org/10.5281/zenodo.14614177",
        release: LexibankCldf::ZenodoRelease.new(
          tag: "v0.3", record: 14_614_177,
          url: "https://zenodo.org/api/records/14614177/files/lexibank/robbeetstriangulation-v0.3.zip/content",
          sha256: "647c4f52f32edd5c593030fc18cf00b1b4a32e80e361837ce8856a5388a47193"
        ),
        word_from: :value,
        varieties: {
          "LateMiddleKorean" => "okm",
          "MiddleMongolianSecretHistory" => "xng",
          "MiddleMongolianMuqaddimataladab" => "xng"
        },
        judgment_notes: { "Root" => "root" },
        rejected_grains: {
          "raw" => "upstream's source spreadsheet, BEAST model files and geodata",
          "plots" => "the cognate-detection evaluation plots (PDF)"
        }
      )
    end
  end
end
