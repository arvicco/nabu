# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

# Nabu::Adapters::CgpgCarvePlan — the open-greek-corpus carve plan that
# splits CGPG's Migne volumes into works (data/cgpg_carve_plan.json at tag
# corpus-2026-10-28.2). The fixture is the real plan trimmed to seven
# volumes' entries, every kept entry and work verbatim (see the README).
class CgpgCarvePlanTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("cgpg"), "carve", "cgpg_carve_plan.json")

  def plan = Nabu::Adapters::CgpgCarvePlan.load(FIXTURE)

  def test_plan_volume_keys_follow_the_adapters_dotted_numbers
    assert_equal "5", Nabu::Adapters::CgpgCarvePlan.volume_key("PG005")
    assert_equal "87.1", Nabu::Adapters::CgpgCarvePlan.volume_key("PG087_1")
    assert_equal "16.3", Nabu::Adapters::CgpgCarvePlan.volume_key("PG016_3")
    assert_equal "101", Nabu::Adapters::CgpgCarvePlan.volume_key("PG101")
  end

  def test_pass_entries_of_one_volume_fold_into_one_volume
    assert_equal %w[134 101 123 124 146 3 139], plan.volumes.keys, "first-appearance order"
    volume = plan.volumes.fetch("139")
    assert_equal 3, volume.passes
    assert_equal %w[nicetas-choniates.historia-xronikh-dih-ghsis joel.chronographia-compendiaria
                    isidorus-thessalonicensis.sermones-in-deiparam], volume.works.map(&:slug)
  end

  def test_the_last_pass_states_the_residual
    volume = plan.volumes.fetch("139")
    assert_equal :apparatus, volume.role_of(554).first, "pass 3's residual 554-558"
    assert_equal :work, volume.role_of(13).first, "pass 1 called 13-89 residual; pass 3 carved it"
    assert_equal :uncarved, volume.role_of(90).first, "in no work and no final residual range"
  end

  def test_residual_loci_cut_a_row_out_of_a_work_range
    volume = plan.volumes.fetch("101")
    assert_equal :apparatus, volume.role_of(293).first, "the explicit locus-293 exclusion"
    assert_equal :apparatus, volume.role_of(14).first
    work = volume.works.first
    refute_includes work.loci, 293
    assert_equal (44..611).to_a - [293], work.loci
  end

  def test_dropped_duplicates_leave_the_work_and_name_their_original
    volume = plan.volumes.fetch("134")
    assert_equal [:duplicate, 561], volume.role_of(563)
    assert_equal [:duplicate, 562], volume.role_of(564)
    lib = volume.works.first
    refute_includes lib.loci, 563
    assert_equal :work, volume.role_of(561).first
  end

  def test_rank_defaults_to_primary_and_carries_the_secondary_reason
    zonaras, clausula = plan.volumes.fetch("134").works
    assert_equal "secondary", zonaras.rank
    assert_match(/served from/, zonaras.secondary_reason)
    assert_equal "primary", clausula.rank, "no rank field: the plan's precedence rule demoted nothing"
    assert_nil clausula.secondary_reason
    assert_equal "tlg3135.tlg003", clausula.tlg
    assert_equal "Joannes Zonaras", clausula.author
  end

  def test_a_deferred_volume_carries_its_reason_and_no_works
    volume = plan.volumes.fetch("3")
    assert volume.deferred?
    assert_match(/interleaves/, volume.defer_reason)
    assert_empty volume.works
  end

  def test_an_append_work_joins_its_earlier_volume_into_one_document
    joannis = plan.documents.find { |doc| doc.key == "theophylactus-achridensis.enarratio-in-evangelium-joannis" }
    assert_equal %w[123 124], joannis.parts.map(&:volume)
    assert_equal [569, 679], joannis.parts.first.loci.minmax
    assert_equal [10, 164], joannis.parts.last.loci.minmax
  end

  def test_documents_mint_one_key_per_work_in_plan_order
    assert_equal %w[joannes-zonaras.epitome-historiarum-lib-1-12
                    joannes-zonaras.epitome-historiarum-lib-12-clausula-varia-dub
                    photius.amphilochia
                    theophylactus-achridensis.enarratio-in-evangelium-joannis
                    theophylactus-achridensis.expositio-in-epistolam-ad-romanos
                    nicephorus-callistus-xanthopulus.historia-ecclesiastica-lib-8-14
                    nicetas-choniates.historia-xronikh-dih-ghsis
                    joel.chronographia-compendiaria
                    isidorus-thessalonicensis.sermones-in-deiparam], plan.documents.map(&:key)
  end

  # The real plan carries one such slug (pseudo-codinus.patria-
  # constantinopoleos: PG 157's primary and PG 122's secondary witness):
  # with no append flag the two are separate witnesses, and BOTH keys take
  # their volume so neither silently owns the bare slug.
  def test_a_slug_repeated_without_append_keys_each_copy_by_volume
    with_plan(lambda do |raw|
      zonaras = raw["volumes"].find { |v| v["volume"] == "PG134" }["works"].first
      raw["volumes"].find { |v| v["volume"] == "PG101" }["works"] << zonaras.merge("ranges" => [[612, 620]])
    end) do |path|
      keys = Nabu::Adapters::CgpgCarvePlan.load(path).documents.map(&:key)
      assert_includes keys, "joannes-zonaras.epitome-historiarum-lib-1-12-pg134"
      assert_includes keys, "joannes-zonaras.epitome-historiarum-lib-1-12-pg101"
      refute_includes keys, "joannes-zonaras.epitome-historiarum-lib-1-12"
    end
  end

  def test_a_locus_claimed_by_two_works_is_a_plan_error
    with_plan(lambda do |raw|
      raw["volumes"].find { |v| v["volume"] == "PG134" }["works"].last["ranges"] = [[560, 569]]
    end) do |path|
      error = assert_raises(Nabu::ParseError) { Nabu::Adapters::CgpgCarvePlan.load(path) }
      assert_match(/560.*two works/, error.message)
    end
  end

  def test_row_order_sequences_a_work_out_of_page_order
    with_plan(lambda do |raw|
      raw["volumes"].find { |v| v["volume"] == "PG139" }["works"].first["row_order"] = [[300, 536], [167, 299]]
    end) do |path|
      choniates = Nabu::Adapters::CgpgCarvePlan.load(path).volumes.fetch("139").works.first
      assert_equal [300, 536, 167, 299], choniates.loci.values_at(0, 236, 237, -1)
    end
  end

  # Incipit soft verification: OCR divergence (the plan quotes its own
  # cleaned text) must pass; a different page must not.
  def test_incipit_scores_tolerate_ocr_noise_and_reject_another_page
    check = "Ἡ δὲ πρὸς Ῥωμαίους ἐπιστολὴ περιέχει τὴν πρὸς τὸν Χριστὸν παρασκευὴν"
    ours = "Ἡ δὲ πρὸς Ἑωμαίους ἐπιστολὴ περιέχει τὴν πρὸς τὸν Χριστὸν παρασκευὴν, μάλιστα"
    assert_operator Nabu::Adapters::CgpgCarvePlan.incipit_score(check, ours), :>=,
                    Nabu::Adapters::CgpgCarvePlan::INCIPIT_THRESHOLD
    other = "σχών στρατιώτας, καὶ φοβηθεὶς μὴ πρόσθοιντο τῷ ἐχθρῷ, ἀπάστη τῆς μάχηε"
    assert_operator Nabu::Adapters::CgpgCarvePlan.incipit_score(check, other), :<,
                    Nabu::Adapters::CgpgCarvePlan::INCIPIT_THRESHOLD
  end

  # The OCR's own brackets are page text, never annotations: PG 126 locus
  # 118 opens a stray "[" before the incipit and closes one after it
  # ("εἰσμεθέξουσιν[συμμεθ. … σφάλματα [σι]") — stripping the page like
  # the check would delete the incipit itself.
  def test_brackets_on_the_page_are_not_stripped
    page = "Ὧν καὶ εἰσμεθέξουσιν[συμμεθ. Ἀμήν. Εἰσῆλθε τὸ ἀξίωμά σου ἐνώπιόν μου, εὐλαβέστατέ " \
           "μοι ἐν Κυρίῳ υἱὲ, καὶ κατενόησα μὲν αὐτὸ καλὸν, σφάλματα [σι], πολλοῖς"
    check = "Εἰσῆλθε τὸ ἀξίωμά σου ἐνώπιόν μου, εὐλαβέστατέ μοι ἐν Κυρίῳ υἱὲ, καὶ κατενόησα μὲν αὐτὸ καλὸν"
    assert_in_delta 1.0, Nabu::Adapters::CgpgCarvePlan.incipit_score(check, page)
  end

  def test_the_plans_bracketed_annotations_are_not_incipit_words
    check = "Ἀριθμοὶ ἐτῶν ἀπὸ τοῦκρώτου ἀνθρώπου ἔως τῆς [OCR noise from the Latin column] ἡμετέρας"
    assert_equal %w[αριθμοι ετων τουκρωτου ανθρωπου ημετερασ],
                 Nabu::Adapters::CgpgCarvePlan.incipit_words(check)
  end

  private

  def with_plan(mutate)
    Dir.mktmpdir do |dir|
      raw = JSON.parse(File.read(FIXTURE))
      mutate.call(raw)
      path = File.join(dir, "plan.json")
      File.write(path, JSON.generate(raw))
      yield path
    end
  end
end
