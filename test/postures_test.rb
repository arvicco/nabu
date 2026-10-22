# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "yaml"

# The consolidated core-layer posture record (P61-0, the D59-f wave-1
# frame): config/postures.yml nests per-layer declarations under each
# source (lect: today's 60 rows migrated verbatim; dating:/places:/
# script: arm in the P61-1 sweep). The lect layer keeps the P59-4
# contract byte-for-byte: machine grains (rules/overrides files) stay the
# single source of truth, declarations hold judgment only, shadowing
# refused, pending names its candidate. The existence check per layer
# lives here; dating/places/script existence arms once the sweep
# declares them.
class PosturesTest < Minitest::Test
  POSTURES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "postures.yml")
  RULES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_facet_rules.yml")
  OVERRIDES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_overrides.yml")
  SOURCES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml")

  def postures
    @postures ||= Nabu::Postures.load(POSTURES_PATH)
  end

  # P71-0 (owner-ruled overlay-merge): a local/config/postures.yml merges
  # over the project file — per (slug, layer), the local declaration wins.
  def test_load_merges_an_overlay_pair_per_slug_and_layer
    Dir.mktmpdir do |dir|
      project = File.join(dir, "project.yml")
      local = File.join(dir, "local.yml")
      File.write(project, <<~YAML)
        sources:
          alpha:
            lect: {posture: identity}
            dating: {posture: undatable}
      YAML
      File.write(local, <<~YAML)
        sources:
          alpha:
            dating: {posture: dated, note: "local instrument dates it"}
          beta:
            lect: {posture: identity}
      YAML
      merged = Nabu::Postures.load([project, local])
      assert_equal "identity", merged.declared("alpha", layer: "lect").posture,
                   "project-only layers survive the merge"
      assert_equal "dated", merged.declared("alpha", layer: "dating").posture,
                   "the local declaration wins its (slug, layer)"
      assert_equal "identity", merged.declared("beta", layer: "lect").posture
    end
  end

  def rules
    @rules ||= Nabu::LectRules.load(RULES_PATH)
  end

  def overrides
    @overrides ||= YAML.safe_load_file(OVERRIDES_PATH)["sources"]
  end

  # Passage-serving sources: kind "source" entries whose adapter serves
  # passages (dictionary/notes/language shelves resolve at their own
  # grains) — plus the local library shelf, which mints documents.
  def passage_slugs
    @passage_slugs ||= begin
      registry = Nabu::SourceRegistry.load(SOURCES_PATH)
      slugs = []
      registry.each_source do |entry|
        kind = entry.kind || "source"
        next unless kind == "source" || entry.slug == "local-library"

        klass = begin
          Object.const_get(entry.adapter_class_name)
        rescue NameError
          nil
        end
        slugs << entry.slug if entry.slug == "local-library" ||
                               (klass && klass.content_kind == :passages)
      end
      slugs
    end
  end

  # --- the lect layer: the P59-4 contract, unchanged through the move ---

  def test_every_passage_serving_source_has_a_lect_posture
    refute_nil postures, "config/postures.yml must exist — it is the judgment record"
    coverage = postures.lect_coverage(rules: rules, overrides: overrides)
    missing = passage_slugs.reject { |slug| coverage.key?(slug) }
    assert_empty missing,
                 "sources with NO lect posture (machine or declared): #{missing.join(', ')} — " \
                 "run `nabu layer suggest <slug>`, then wire a rule/override or declare a row " \
                 "(identity is an honest answer) in config/postures.yml"
  end

  # --- the P61-1 sweep: every layer, every source — ARMED ----------------

  def test_every_passage_serving_source_declares_dating_places_and_script
    %w[dating places script].each do |layer|
      coverage = postures.layer_coverage(layer)
      missing = passage_slugs.reject { |slug| coverage.key?(slug) }
      assert_empty missing,
                   "sources with NO #{layer} posture: #{missing.join(', ')} — run " \
                   "`nabu layer suggest <slug>`, then declare (undatable/unplaced/implied " \
                   "are honest answers) in config/postures.yml"
    end
  end

  # P100-4: the kind axis joins the armed sweep — every
  # passage-serving source is either kind_map-ruled (machine
  # "classified") or declares its judgment (unclassified is an honest
  # answer; pending names its candidate).
  def test_every_passage_serving_source_has_a_kind_posture
    kinds = Nabu::Kinds.load(
      classes_path: File.expand_path("../config/kind_classes.yml", __dir__),
      map_path: File.expand_path("../config/kind_map.yml", __dir__)
    )
    coverage = postures.kind_coverage(ruled_slugs: kinds.sources)
    missing = passage_slugs.reject { |slug| coverage.key?(slug) }
    assert_empty missing,
                 "sources with NO kind posture (machine or declared): #{missing.join(', ')} — " \
                 "add a config/kind_map.yml rule or declare kind: {posture: unclassified} " \
                 "(honest) / pending (naming its candidate) in config/postures.yml"
  end

  def test_kind_declarations_never_shadow_kind_map_rules
    kinds = Nabu::Kinds.load(
      classes_path: File.expand_path("../config/kind_classes.yml", __dir__),
      map_path: File.expand_path("../config/kind_map.yml", __dir__)
    )
    assert_empty postures.kind_shadowing(ruled_slugs: kinds.sources),
                 "a declared kind row duplicates a kind_map rule — delete the declaration"
  end

  def test_lect_declarations_never_shadow_machine_postures
    assert_empty postures.shadowing(rules: rules, overrides: overrides),
                 "a declared lect row duplicates a rules/overrides posture — delete the " \
                 "declaration (machine files are the single source of truth)"
  end

  # --- every layer: vocabulary, real sources, pending discipline --------

  def test_declarations_use_each_layers_ruled_vocabulary_and_name_real_sources
    slugs = Nabu::SourceRegistry.load(SOURCES_PATH).then do |registry|
      list = []
      registry.each_source { |entry| list << entry.slug }
      list
    end
    postures.declarations.each do |declaration|
      vocabulary = Nabu::Postures::LAYERS.fetch(declaration.layer)
      assert_includes vocabulary, declaration.posture,
                      "#{declaration.slug}/#{declaration.layer}: unknown posture " \
                      "#{declaration.posture.inspect} (ruled set: #{vocabulary.join('/')})"
      assert_includes slugs, declaration.slug,
                      "#{declaration.slug}: declared but not in config/sources.yml (a ghost row)"
    end
  end

  def test_pending_rows_carry_the_candidate_as_a_note_on_every_layer
    postures.declarations.select { |d| d.posture == "pending" }.each do |declaration|
      refute_nil declaration.note,
                 "#{declaration.slug}/#{declaration.layer}: a pending posture must name its " \
                 "candidate — pending without a note is just a silence with paperwork"
    end
  end

  def test_unknown_layer_keys_are_refused_loudly
    Dir.mktmpdir do |dir|
      path = File.join(dir, "postures.yml")
      File.write(path, "sources:\n  gretil:\n    vibe: {posture: good}\n")
      error = assert_raises(Nabu::Error) { Nabu::Postures.load(path) }
      assert_match(/vibe/, error.message, "a typo'd layer key must never silently vanish")
    end
  end

  # --- the migration fact: the P59-4 record survived the move -----------

  def test_the_lect_migration_kept_the_p59_4_census
    lect = postures.declarations.select { |d| d.layer == "lect" }
    by_posture = lect.group_by(&:posture).transform_values(&:size)
    assert_equal 159, lect.size,
                 "the P59-4 declarations survive the move (61 at migration; itant retired P61-3," \
                 "oracc retired P62-2, etcsl/ccmh/freising/coptic-scriptorium retired P64-6, " \
                 "titus-avestan retired P66-1, osta+fornsvenska retired P77-r8, achemenet " \
                 "added-then-retired P77-r18→owner ruling 2026-08-18 — each when a machine grain took over: " \
                 "the shadowing rule, working; disco ADDED P77-4; P78 ADDED SEVEN — sillok+sjw+" \
                 "the goryeosa family three+viet-wikisource all codemap on the kanripo lzh " \
                 "precedent, ko-wikisource-mk identity okm; itkc ADDED P78-7 — codemap; " \
                 "corpus-corporum ADDED P80-1/2 — identity, the D57-f mixed-Latin class; ref " \
                 "ADDED P80-5 — pending on the de:early nabu-lects mint, the fornsvenska " \
                 "add-then-retire shape, RETIRED same phase — nabu-lects PR #5 merged and " \
                 "the ref-enhg rule machine-postures it; P80-6 ADDS the small-languages pack as identity — " \
                 "lo-congres/aranese bare oci, cv-sardinian bare srd, salom bare lad; " \
                 "bdcamoes ADDED P80-7 — identity por; ctilc ADDED P80-8 — identity cat; " \
                 "P81-r2 (owner-ruled 2026-08-21, nabu-lects PR #6) RETIRES lo-congres (oci-dialect rule) and " \
                 "aranese (oc/aranes override) — the add-then-retire shape again, 70→68; " \
                 "menota ADDED P82-1 — pending on the language-facet rule (nor/dan need " \
                 "registry decisions) — and cme ADDED P82-2 — identity enm (the aspr/iswoc " \
                 "germanic mold): 68→70; the 2026-08-24 ruling RETIRES menota (nabu-lects v1.1.0 minted " \
                 "no/da, the menota-dan rule + onw override machine-posture it): 70→69; " \
                 "eebo-tcp ADDED P83-1 — identity en, TRUE today; the en:early mint is " \
                 "APPROVED (nabu-lects PR #9, [1500, 1700]) and its date-band staging " \
                 "lands at the merge sweep, not here: 69→70; P84-7 ADDS " \
                 "corpus-oudnederlands (odt) + corpus-gysseling (dum) as identity: 70→72; " \
                 "dacon ADDED P88-A4 — pending on the nwc nabu-lects mint (P88-B3) — and " \
                 "classical-modern ADDED P88-A2 — codemap, the kanripo lzh precedent: 72→74; " \
                 "seal ADDED P89-3 — identity akk (a real anchor; the period-mixed OB/OA/MB " \
                 "refinement is a future date-band story): 74→75; titus-osco-umbrian ADDED " \
                 "P90-2 as pending on the xum mint, RETIRED TO IDENTITY at the same gate " \
                 "(the mint merged and reached canonical 2026-08-31 — the add-then-retire " \
                 "shape within ONE phase): 75→76; okhc ADDED P91-1 — codemap, the sillok " \
                 "lzh mold over the Korean label table: 76→77; dharma-khmer ADDED P92-1 as " \
                 "pending on the aggregated SEA nabu-lects mint (the titus-osco-umbrian " \
                 "xum shape — flips to identity when the mint reaches canonical): 77→78; " \
                 "P92-2 ADDS the three DHARMA siblings (campa/nusantara/pyu) on the same " \
                 "pending — the whole family flips together at the mint's merge: 78→81; " \
                 "P92-3 ADDS obi-burmese on the same mint (obr): 81→82; P92-4 ADDS " \
                 "dharma-javanese-texts (kaw/osn): 82→83; P92-5 ADDS ojw (kaw, the lexicon): " \
                 "83→84; the P92 GATE retires ALL SEVEN pendings to identity — v1.6.0 and the " \
                 "v1.6.1 first-sync census mint both merged and reached canonical 2026-09-02 " \
                 "(the xum add-then-retire shape at family scale, twice in one gate); " \
                 "dta ADDED P94-2 — identity de (the print corpus; date-band inference stages its pre-1650 " \
                 "tail via date-band INFERENCE, the document grain — no facet rule, so the " \
                 "declaration stays): 84→85; P95 ADDS FOUR — prilit (dates, the goo300k/imp " \
                 "sl-bands mold), diccas (identity ara), perseus-anglit (identity ang, the aspr " \
                 "mold), perseus-farsilit (identity fas, bare fa anchor): 85→89; " \
                 "scripta-bulgarica ADDED P107-8 — identity bul, declared whole-source " \
                 "coarse (the Old→Middle Bulgarian span; per-text chu-recension refinement " \
                 "a recorded future look): 89→90; iedc ADDED P107-2 — identity, eleven " \
                 "mapped ISO codes across the Islamicate-East belt: 90→91; P107-3 ADDS " \
                 "skjaervo-khotanese + shkz — identity: 91→93; P107-4/7 ADD atmo + " \
                 "altaica-shm — identity: 93→95; kouigenji ADDED P108-3 — pending on " \
                 "the jpn:emj mint (p108-japonic-stages), the titus-osco-umbrian " \
                 "shape: 95→96; kokubunken ADDED P108-4 — identity (jpn + ojp): 96→97; " \
                 "honkoku ADDED P108-5 — identity jpn honest-coarse: 97→98; " \
                 "westoldturkic ADDED P108-7 — identity trk collective: 98→99; " \
                 "P109 ADDS FOUR — hittite-glossed (identity hit), ndl-kotenseki (identity " \
                 "jpn, declared coarse), ja-wikisource (identity jpn+ojp; the era-band jpn " \
                 "staging is a NAMED candidate awaiting a ruling), zh-wikisource (codemap, " \
                 "the kanripo lzh precedent + bare zho for the Ming 總譯): 99→103; " \
                 "P110 completes the P108 add-then-retire — kouigenji (pending) and " \
                 "kokubunken (identity) RETIRED to the jpn → jpn:emj overrides " \
                 "(the p108-japonic-stages mint merged; the shadowing rule) and ADDS " \
                 "aclt (identity hlu, the hieroglyphic tradition): 103→102; " \
                 "titus-tocharian-a ADDED P114-1a — identity xto (a real anchor; " \
                 "the bilinguals' Sanskrit sub-lines ride bare san) and " \
                 "titus-pahlavi ADDED — identity pal, declared coarse (the titus " \
                 "family's grant-gated Middle Persian books): 102→104; " \
                 "titus-bactrian ADDED — identity xbc (a real anchor, declared coarse): 104→105; " \
                 "titus-manichaica ADDED — identity pal/xpr/sog/oui per lane (all real anchors): 105→106; " \
                 "titus-khotanese ADDED — identity kho (a real anchor, declared coarse): 106→107; " \
                 "titus-sogdian ADDED — identity sog per lane (script-coded lanes, declared coarse): 107→108; " \
                 "prague-bible-1488 ADDED P116-1 — pending on the cs:old mint (the aggregated " \
                 "Slavic nabu-lects package; no cs node exists yet): 108→109; korba ADDED " \
                 "P116-1 — pending on pl:mid date-band staging (same mint; no pl node): 109→110; " \
                 "the Slavic mint landing (2026-10-11) RETIRES prague-bible-1488 to the cs → cs:old " \
                 "override (the shadowing rule) and flips korba to identity (date-band inference " \
                 "stages it onto pl:mid, the dta shape — the declaration stays): 119→118; " \
                 "dharma-deccan ADDED P118-2 — pending on the tel/kan anchor mint (nothing " \
                 "Telugu or Kannada exists in nabu-lects; the dacon shape) and dharma-tamil " \
                 "ADDED P118-1 — pending on the same mint's tam node (the dharma-khmer " \
                 "shape): 127→129; " \
                 "P118-4 ADDS siddham (identity san, declared coarse) and dharma-mdt (PENDING " \
                 "on the tel/tam anchors of the aggregated Indic nabu-lects mint): 129→131; " \
                 "P118-3 ADDS kannada-texts + prakrit-texts as PENDING on the hub-side kan / " \
                 "pka mints (no node exists in nabu-lects): 131→133; " \
                 "the Indic registry package landing (merged 2026-10-11, canonical-synced " \
                 "2026-10-12) RETIRES all five P118 pendings to identity — te/kn/pka minted, " \
                 "ta re-parented, the tam/tel/kan codemap rows live (the add-then-retire " \
                 "shape, five at once); titus-tocharian-b ADDED — identity txb (a real " \
                 "anchor; the members-only B corpus on the titus-tocharian-a family) and " \
                 "ban-wikisource ADDED P120-2 — pending on the ban/sas nodes of the " \
                 "nabu-lects mint (kaw resolves on the held node): 133→135; " \
                 "P120-3 ADDS gu/ms/th-wikisource as PENDING on the hub-side gu/ms/th " \
                 "anchor mints (no Gujarati, Malay or Tai node exists): 135→138; " \
                 "the SEA/Gujarat package landing (merged + canonical-synced 2026-10-12) " \
                 "RETIRES all four P120 pendings to identity — the add-then-retire shape " \
                 "at family scale, count unchanged at 138; the same sitting's ruling lands " \
                 "the bg-charter-recension facet rule, so bg-wikisource's lect declaration " \
                 "retires under the shadowing rule: 138→137; " \
                 "tamilex ADDED P121-3 — identity ta (tam-Latn through the held codemap row; " \
                 "no Tamil stage exists, declared coarse): 137→138; " \
                 "sii-clean ADDED P122-3 — identity (tam/san/tel/kan -Latn on the held " \
                 "dharma-family codemap rows): 138→139; " \
                 "madurai ADDED P122-3 — identity ta (Tamil-script tam through the held " \
                 "codemap row, declared coarse — the tamilex shape): 139→140; " \
                 "shabados ADDED P122-3 — PENDING on the aggregated nabu-lects mint (no pa " \
                 "anchor, no guru script row, no bra-Guru/fas-Guru codemap rows exist): 140→141; " \
                 "bu-ajami ADDED P124-1 — PENDING on the aggregated nabu-lects Africa mint (no " \
                 "ha/mnk/fuf/wo node exists): 141→142; africa-pd ADDED P124-1 — PENDING on the " \
                 "same mint's sw anchor (Velten's reader; the other nine works claim real " \
                 "prose-language anchors): 142→143; old-nubian-ud ADDED P125 — PENDING on the " \
                 "nabu-lects Old Nubian package (the nub family + onw anchor; nothing Nubian " \
                 "exists in the canonical registry yet): 143→144; stgall-priscian ADDED P126 — " \
                 "dates (every page dated 850–851: lat pages stage to lat:med, the bare sga " \
                 "node stays sga — the corph shape): 144→145; ig-cyprus ADDED P130 — PENDING on " \
                 "the aggregated nabu-lects mint (an ecy anchor + a Cypriot-Greek grc stage): " \
                 "145→146; damos ADDED P130 — identity gmy: 146→147; ig-cyprus + ociana added " \
                 "and MACHINE-POSTURED the same day (the mint merged + canonical-synced, then " \
                 "the ociana-script facet rule and the ig-cyprus grc override shadow both " \
                 "declarations): 147→148→146; senie ADDED — PENDING on the aggregated " \
                 "Baltic–Finnic–Basque nabu-lects package (no lv anchor exists): 146→147; " \
                 "bim-sahcoba ADDED — PENDING on the same package's eu anchor + stages: 147→148; " \
                 "vks ADDED — PENDING on the same package's fi anchor + fi:old: 148→149; " \
                 "lasla ADDED — PENDING on a lat:cla approximation override (the perseus-latin " \
                 "shape — a corpus-level reading of Plautus-to-Juvenal Latin, not the corpus's " \
                 "own definition, so it waits on a ruling): 149→150; " \
                 "gretil-legacy ADDED — identity, per-file pka/pra/awa/bra/mar tags on held " \
                 "nodes (pra declared coarse; the Malayalam file quarantines pending the ml " \
                 "mint): 150→151; " \
                 "obimd ADDED — codemap och → zho:old (the oracle bones, Old Chinese's " \
                 "earliest stratum; no Shang stage minted): 151→152; lotsawa-house ADDED — " \
                 "identity xct (the Tibetan pages, declared coarse) + the translation " \
                 "languages: 152→153; " \
                 "vakk ADDED — dates (et:old by date band; the et anchor + stage already " \
                 "canonical): 153→154; " \
                 "P140 ADDS te/cy/jv/su/br-wikisource as PENDING on the phase's aggregated " \
                 "nabu-lects package (te:cls, cy:emod, the jv/su anchors, the jav/sun/bre aliases): 154→159"
    # The epigraphic-belt registry package (merged + canonical-synced
    # 2026-10-18, the add-then-retire shape within one phase) retires both
    # P130 pendings, and the ociana-script rule + the ig-cyprus override
    # machine-posture both sources the same day (the shadowing rule):
    # identity 118 (damos stays declared), pending 2→0. Zero pendings.
    # senie, bim-sahcoba and vks join as pending on the Baltic–Finnic–Basque
    # package's lv:old, eu:arch/eu:old and fi:old. lasla joins as the one
    # pending (its lat:cla approximation candidate awaits a ruling).
    # gretil-legacy joins as identity (119). obimd joins codemap
    # (och → zho:old): 13→14; lotsawa-house joins identity: 119→120;
    # vakk joins dates: 18→19; the five wave-3 cones join as pending on
    # the phase's aggregated package: 1→6.
    assert_equal({ "dates" => 19, "codemap" => 14, "identity" => 120, "pending" => 6 }, by_posture)
  end
end
