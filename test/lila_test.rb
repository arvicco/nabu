# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Lila (P44-8) — the pure read seam over the LiLa Lemma Bank Turtle
# dump: a folded Latin lemma → its canonical lemma record(s) {IRI, canonical
# form, POS, variant forms}. Exercised against the real trimmed
# rdf/lemmaBank.ttl fixture (test/fixtures/lila/README.md).
class LilaTest < Minitest::Test
  DUMP = File.join(Nabu::TestSupport.fixtures("lila"), "rdf", "lemmaBank.ttl")

  def resolver
    @resolver ||= Nabu::Lila.load(DUMP)
  end

  def one(form)
    records = resolver.lookup(form)
    assert_equal 1, records.size, "expected exactly one LiLa record for #{form.inspect}"
    records.first
  end

  # --- the record shape, off real bytes -------------------------------------

  def test_resolves_a_plain_lemma_to_its_canonical_record
    rec = one("subsides")
    assert_equal "http://lila-erc.eu/data/id/lemma/83005", rec.lila_id
    assert_equal "subsides", rec.form
    assert_equal "noun", rec.pos
    assert_equal ["subsides"], rec.variants
    refute rec.hypolemma
  end

  def test_carries_the_part_of_speech_verbatim
    assert_equal "verb", one("percrebreo").pos
    assert_equal "adverb", one("tantipliciter").pos
    assert_equal "adjective", one("proeliaris").pos
  end

  # --- variants: every writtenRep reaches the one canonical record ----------

  def test_a_written_rep_variant_reaches_the_canonical_form
    # "eclypsans" is a variant; the canonical (rdfs:label) is "eclipsans".
    via_variant = one("eclypsans")
    via_canonical = one("eclipsans")
    assert_equal "eclipsans", via_variant.form
    assert_equal via_variant.lila_id, via_canonical.lila_id, "both spellings resolve to one record"
    assert_equal %w[eclypsans eclipsans], via_variant.variants
  end

  def test_hypolemma_is_flagged_and_iri_uses_the_hypolemma_space
    rec = one("eclipsans")
    assert rec.hypolemma, "lilaIpoLemma:97523 is a lila:Hypolemma"
    assert_equal "http://lila-erc.eu/data/id/hypolemma/97523", rec.lila_id
  end

  def test_h_drop_variant_maps_to_its_canonical
    rec = one("amiger")
    assert_equal "hamiger", rec.form
    assert_includes rec.variants, "amiger"
  end

  # --- the house Latin fold is the lookup key -------------------------------

  def test_lookup_folds_v_to_u_like_the_house_latin_fold
    # "virgastrum" folds (v→u) onto the stored "uirgastrum" writtenRep.
    rec = one("virgastrum")
    assert_equal "uirgastrum", rec.form
  end

  def test_lookup_is_case_insensitive
    assert_equal one("proeliaris").lila_id, one("PROELIARIS").lila_id
  end

  # --- honest misses --------------------------------------------------------

  def test_an_unknown_form_is_an_empty_lookup
    assert_empty resolver.lookup("thisisnotalatinlemma")
  end

  def test_size_counts_the_indexed_forms
    assert_operator resolver.size, :>, 8, "eight blocks, several with extra variant keys"
  end

  # --- feature detection: absent tree → nil (byte-identical define) ---------

  def test_load_default_is_nil_without_a_canonical_tree
    Dir.mktmpdir do |root|
      config = Nabu::Config.load(root: root)
      assert_nil Nabu::Lila.load_default(config: config),
                 "no canonical/lila → nil resolver → define fallback is a no-op"
    end
  end

  def test_load_default_finds_the_sparse_cone_layout
    Dir.mktmpdir do |root|
      dir = File.join(root, "canonical", "lila", "rdf")
      FileUtils.mkdir_p(dir)
      FileUtils.cp(DUMP, File.join(dir, "lemmaBank.ttl"))
      config = Nabu::Config.load(root: root)
      resolver = Nabu::Lila.load_default(config: config)
      refute_nil resolver
      assert_equal "subsides", resolver.lookup("subsides").first.form
    end
  end
end
