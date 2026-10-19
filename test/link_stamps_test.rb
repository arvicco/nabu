# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::LinkStamps: the links stage's per-scope derivation stamps. A
# recorded batch scope is carried (its edges kept, no re-mine) only when
# its stamp — producer code digest + resolved params + member sources'
# content identities + producer-specific extras — is unchanged AND the
# journal still holds exactly the runs that stamp vouches for. Every
# perturbation of an input must move the stamp; the periodic self-check
# re-derives everything and compares.
class LinkStampsTest < Minitest::Test
  include StoreTestDB

  Place = Data.define(:id, :title, :lat, :lon, :place_types, :time_periods, :name_keys)

  FORMULAS = { "producer" => "formulas", "scope" => "aspr",
               "params" => { "gram_size" => 4, "min_count" => 2 } }.freeze
  PLACE_MINE = { "producer" => "place-mine", "scope" => "kanripo", "params" => { "gazetteer" => "chgis" } }.freeze
  PLACE_LINK = { "producer" => "place-link", "scope" => "kanripo", "params" => { "gazetteer" => "chgis" } }.freeze
  PARALLELS = { "producer" => "parallels", "scope" => "kanripo",
                "params" => { "profile" => "chinese", "min_score" => 0.5 } }.freeze
  COGNATES = { "producer" => "cognates", "scope" => "nt", "params" => { "langs" => %w[got chu] } }.freeze

  def setup
    @root = Dir.mktmpdir("nabu-link-stamps")
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    @aspr = Nabu::Store::Source.create(slug: "aspr", name: "A", adapter_class: "X", license_class: "open")
    @kanripo = Nabu::Store::Source.create(slug: "kanripo", name: "K", adapter_class: "X",
                                          license_class: "attribution")
    passage(@aspr, "urn:nabu:aspr:riddle", "urn:nabu:aspr:riddle:1", "saga hwaet ic hatte foo", "ang")
    passage(@aspr, "urn:nabu:aspr:riddle", "urn:nabu:aspr:riddle:2", "saga hwaet ic hatte bar", "ang")
    passage(@kanripo, "urn:nabu:kanripo:d1", "urn:nabu:kanripo:d1:1", "田何徙杜陵號杜田生", "lzh")
    Nabu::Store::PlaceIndex.derive!(
      @catalog, gazetteer: "chgis",
                places: [Place.new(id: "hvd_1", title: "杜陵", lat: 34.2, lon: 109.1, place_types: ["xian"],
                                   time_periods: ["1820"], name_keys: ["杜陵"])],
                names_for: :name_keys.to_proc
    )
    @places_tree = File.join(@root, "canonical", Nabu::Places::DIRNAME)
    FileUtils.mkdir_p(@places_tree)
    File.write(File.join(@places_tree, "kanripo.yml"), "a: 1\n")
  end

  def teardown
    @journal.disconnect
    FileUtils.remove_entry(@root)
  end

  def passage(source, doc_urn, urn, text, language)
    document = Nabu::Store::Document.find(urn: doc_urn) ||
               Nabu::Store::Document.create(source_id: source.id, urn: doc_urn, title: "t", language: language,
                                            content_sha256: Digest::SHA256.hexdigest(doc_urn))
    Nabu::Store::Passage.create(document_id: document.id, urn: urn, language: language, text: text,
                                text_normalized: Nabu::Normalize.search_form(text, language: language),
                                content_sha256: Digest::SHA256.hexdigest(text),
                                sequence: @catalog[:passages].where(document_id: document.id).count,
                                revision: 1)
  end

  def config
    Struct.new(:canonical_dir).new(File.join(@root, "canonical"))
  end

  def stamps = Nabu::LinkStamps.new(catalog: @catalog, config: config, registry: nil)

  def unit(scope) = stamps.unit(scope)

  # -- the stamp: every input moves it ------------------------------------------

  def test_the_same_inputs_mint_the_same_stamp
    assert_equal unit(FORMULAS).stamp, unit(FORMULAS).stamp
    assert_match(/\A\h{64}\z/, unit(FORMULAS).stamp)
  end

  def test_a_params_change_moves_the_stamp
    changed = FORMULAS.merge("params" => { "gram_size" => 3, "min_count" => 2 })
    refute_equal unit(FORMULAS).stamp, unit(changed).stamp
    assert_equal %w[params], unit(changed).blame(unit(FORMULAS).inputs)
  end

  def test_a_parallels_profile_retune_moves_the_stamp_even_under_the_same_name
    before = unit(PARALLELS)
    retuned = Nabu::ReuseProfiles::Profile.new(**Nabu::ReuseProfiles.default.fetch("chinese").to_h, min_score: 9.9)
    replacing(Nabu::ReuseProfiles, :default, -> { Struct.new(:profile) { def fetch(_name) = profile }.new(retuned) }) do
      refute_equal before.stamp, unit(PARALLELS).stamp
    end
  end

  def test_a_member_content_change_moves_the_stamp
    before = unit(FORMULAS)
    Nabu::Store::Document.find(urn: "urn:nabu:aspr:riddle").update(content_sha256: "f" * 64)
    after = unit(FORMULAS)
    refute_equal before.stamp, after.stamp
    assert_equal %w[members], after.blame(before.inputs)
  end

  def test_a_scope_local_producer_ignores_other_sources_but_a_global_one_does_not
    formulas = unit(FORMULAS).stamp
    parallels = unit(PARALLELS.merge("scope" => "aspr")).stamp
    Nabu::Store::Document.find(urn: "urn:nabu:kanripo:d1").update(content_sha256: "f" * 64)
    assert_equal formulas, unit(FORMULAS).stamp, "formulas reads only its slice"
    refute_equal parallels, unit(PARALLELS.merge("scope" => "aspr")).stamp,
                 "parallels scores by GLOBAL document frequency — every source is a member"
  end

  def test_a_producer_code_change_moves_its_own_stamp_only
    before = unit(FORMULAS)
    place_mine = unit(PLACE_MINE).stamp
    with_changed_code("batch_formulas.rb") do
      after = unit(FORMULAS)
      refute_equal before.stamp, after.stamp
      assert_equal %w[producer_code], after.blame(before.inputs)
      assert_equal place_mine, unit(PLACE_MINE).stamp, "another producer's closure is untouched"
    end
  end

  def test_shared_replay_code_moves_every_stamped_producer
    formulas = unit(FORMULAS).stamp
    place_mine = unit(PLACE_MINE).stamp
    with_changed_code("store/links_journal.rb") do
      refute_equal formulas, unit(FORMULAS).stamp
      refute_equal place_mine, unit(PLACE_MINE).stamp
    end
  end

  def test_the_gazetteer_names_are_a_place_mine_input
    before = unit(PLACE_MINE)
    @catalog[:place_index_names].insert(gazetteer: "chgis", place_id: "hvd_2", name_key: "長安")
    after = unit(PLACE_MINE)
    refute_equal before.stamp, after.stamp
    assert_equal %w[gazetteer], after.blame(before.inputs)
  end

  def test_the_places_registry_tree_is_a_place_link_input
    before = unit(PLACE_LINK)
    File.write(File.join(@places_tree, "kanripo.yml"), "a: 2\n")
    after = unit(PLACE_LINK)
    refute_equal before.stamp, after.stamp
    assert_equal %w[places_registry], after.blame(before.inputs)
  end

  def test_place_link_without_a_registry_tree_is_volatile
    FileUtils.remove_entry(@places_tree)
    assert_nil unit(PLACE_LINK).stamp
    assert_match(/nabu-places/, unit(PLACE_LINK).volatile)
  end

  def test_an_urn_prefix_scope_resolves_to_the_owning_source
    prefix = FORMULAS.merge("scope" => "urn:nabu:aspr:riddle")
    assert_equal %w[aspr], unit(prefix).inputs.fetch("members").keys
  end

  def test_the_cognates_producer_is_volatile_and_never_stamped
    cognates = unit(COGNATES)
    assert_nil cognates.stamp
    assert_match(/lect/, cognates.volatile)
  end

  def test_an_unknown_producer_is_volatile_so_the_replay_names_it_loudly
    assert_nil unit({ "producer" => "nope", "scope" => "x" }).stamp
  end

  # -- the producer code closure is test-pinned -------------------------------
  #
  # The stamp's code digest covers the producer's require_relative closure
  # plus declared extras. A file the producer EXECUTES but the closure
  # misses would let a code change hide behind a carried scope (the stamp
  # lying) — so every lib file a real replay runs code from must be in
  # the closure. TracePoint, not a grep: it sees what actually runs.

  def test_every_lib_file_a_replay_executes_is_in_its_producers_closure
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fulltext, cjk_slugs: ["kanripo"])
    registry = Struct.new(:rows) { def decisions_for(_source) = rows }.new({})
    [FORMULAS, PLACE_MINE, PLACE_LINK, PARALLELS].each do |scope|
      executed = executed_lib_files do
        Nabu::LinkScopeReplay.replay!(scope, db: @catalog, fulltext: fulltext, journal: @journal, config: config,
                                             places: registry)
      end
      closure = Nabu::LinkStamps.code_files(scope["producer"])
      missing = executed - closure
      assert_empty missing.map { |file| file.delete_prefix("#{Nabu::LinkStamps::LIB_DIR}/") },
                   "#{scope['producer']} executes code outside its stamped closure"
    end
  ensure
    fulltext&.disconnect
  end

  def test_the_closures_stay_out_of_the_catalog_loaders
    # The economics guard: a loader edit is content-neutral or moves the
    # member identities — either way the code digest must not see it.
    Nabu::LinkStamps::PRODUCERS.each_key do |producer|
      rel = Nabu::LinkStamps.code_files(producer).map { |file| file.delete_prefix("#{Nabu::LinkStamps::LIB_DIR}/") }
      refute_includes rel, "store/loader.rb", producer
      refute_includes rel, "rebuild.rb", producer
    end
  end

  # The reference lane re-runs every stage on top of carried batch edges:
  # that is sound only while no other journal writer mints a batch kind
  # (write_edge! would refresh — and so take over — a carried edge). A
  # producer adopting one must join the component model first.
  def test_no_other_journal_writer_mints_a_batch_producer_kind
    batch_files = Nabu::LinkStamps::PRODUCERS.each_key.flat_map do |producer|
      Nabu::LinkStamps::PRODUCERS.fetch(producer).roots.map { |rel| File.join(Nabu::LinkStamps::LIB_DIR, rel) }
    end + [File.join(Nabu::LinkStamps::LIB_DIR, "batch_cognates.rb")]
    batch_kinds = Nabu::LinkStamps::PRODUCERS.values.flat_map(&:kinds).uniq
    offenders = Dir[File.join(Nabu::LinkStamps::LIB_DIR, "**", "*.rb")].filter_map do |file|
      next if batch_files.include?(file)

      code = File.read(file)
      next unless code.include?("write_edge!")

      kinds = code.scan(/KIND\s*=\s*"([^"]+)"/).flatten
      clash = kinds & batch_kinds
      "#{file.delete_prefix("#{Nabu::LinkStamps::LIB_DIR}/")} (#{clash.join(', ')})" unless clash.empty?
    end
    assert_empty offenders
  end

  # -- the plan: components, carrying, cadence ----------------------------------

  def mine(scope)
    before = Nabu::Store::LinksJournal.max_run_id(@journal)
    Nabu::LinkScopeReplay.replay!(scope, db: @catalog, fulltext: nil, journal: @journal, config: config,
                                         places: Struct.new(:rows) { def decisions_for(_source) = rows }.new({}))
    Nabu::Store::LinksJournal.run_ids_for(@journal, producers: [scope["producer"]]).select { |id| id > before }
  end

  def stamp_after_mine(scope)
    current = unit(scope)
    Nabu::Store::LinksJournal.write_scope_stamp!(@journal, producer: scope["producer"], scope: scope["scope"],
                                                           stamp: current.stamp, inputs: current.inputs,
                                                           run_ids: mine(scope))
  end

  def test_a_stamped_scope_is_carried_with_its_runs
    stamp_after_mine(FORMULAS)
    plan = stamps.plan([FORMULAS], journal: @journal)
    assert_equal [%w[formulas aspr]], plan.carried_keys
    assert_equal Nabu::Store::LinksJournal.run_ids_for(@journal, producers: ["formulas"]), plan.carried_run_ids
    refute plan.self_check
  end

  def test_an_unexpected_run_of_the_producer_dirties_the_scope
    stamp_after_mine(FORMULAS)
    Nabu::Store::LinksJournal.record_run!(@journal, producer: "formulas", scope: "stray", params: {},
                                                    code_version: "t")
    assert_empty stamps.plan([FORMULAS], journal: @journal).carried_keys,
                 "the journal no longer holds exactly the stamped runs — carrying would keep a stranger"
  end

  def test_place_mine_and_place_link_carry_or_re_mine_together
    stamp_after_mine(PLACE_MINE)
    stamp_after_mine(PLACE_LINK)
    assert_equal [%w[place-mine kanripo], %w[place-link kanripo]],
                 stamps.plan([PLACE_MINE, PLACE_LINK], journal: @journal).carried_keys
    @catalog[:place_index_names].insert(gazetteer: "chgis", place_id: "hvd_2", name_key: "長安")
    assert_empty stamps.plan([PLACE_MINE, PLACE_LINK], journal: @journal).carried_keys,
                 "place-link promotes place-mine's candidates: a dirty mine re-runs the link too"
  end

  def test_a_dirty_scope_does_not_drag_an_unrelated_component
    stamp_after_mine(FORMULAS)
    stamp_after_mine(PLACE_MINE)
    @catalog[:place_index_names].insert(gazetteer: "chgis", place_id: "hvd_2", name_key: "長安")
    assert_equal [%w[formulas aspr]], stamps.plan([FORMULAS, PLACE_MINE], journal: @journal).carried_keys
  end

  def test_a_volatile_scope_never_carries
    assert_empty stamps.plan([COGNATES], journal: @journal).carried_keys
  end

  def test_every_nth_stage_is_a_self_check_that_carries_nothing
    stamp_after_mine(FORMULAS)
    (Nabu::LinkStamps::SELF_CHECK_EVERY - 1).times do
      Nabu::Store::LinksJournal.record_stage_run!(@journal, mode: "stamped", carried: 1)
    end
    plan = stamps.plan([FORMULAS], journal: @journal)
    assert plan.self_check
    assert_empty plan.carried_keys
    assert_equal [%w[formulas aspr]], plan.verify_keys, "the would-be-carried scope is what gets verified"
  end

  def test_force_full_is_a_self_check_now
    stamp_after_mine(FORMULAS)
    plan = stamps.plan([FORMULAS], journal: @journal, force_full: true)
    assert plan.self_check
    assert_equal [%w[formulas aspr]], plan.verify_keys
  end

  private

  def executed_lib_files(&)
    files = Set.new
    trace = TracePoint.new(:call, :b_call) do |tp|
      files << tp.path if tp.path.start_with?(Nabu::LinkStamps::LIB_DIR)
    end
    trace.enable(&)
    files.to_a.sort
  end

  def with_changed_code(rel, &)
    target = File.join(Nabu::LinkStamps::LIB_DIR, rel)
    original = Nabu::LinkStamps.method(:code_file_digest)
    replacing(Nabu::LinkStamps, :code_file_digest, ->(path) { path == target ? "changed" : original.call(path) }, &)
  end

  # Swap a singleton method for the block's duration (the
  # derivation_fingerprint_test seam pattern — no mock library).
  def replacing(owner, name, body)
    original = owner.method(name)
    owner.singleton_class.define_method(name, &body)
    yield
  ensure
    owner.singleton_class.define_method(name, original)
  end
end
