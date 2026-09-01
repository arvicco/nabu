# frozen_string_literal: true

require "test_helper"

# The three P92-2 DHARMA siblings (campa, nusantara, pyu) — same
# dharma-epidoc family as dharma-khmer (P92-1), three registrations.
# Each gets the conformance suite plus the pins its fixtures earn:
# campa carries the BROUILLON worklist skip and Old Cham; nusantara the
# bilingual san-inside-omy edition, the face-milestone line wrap and the
# languageb-Latn upstream bug; pyu the flat repo layout.
#
# Fixtures: whole real files retrieved 2026-09-01 (per-fixture READMEs).

class DharmaCampaTest < Minitest::Test
  include AdapterConformance

  CIC1 = "urn:nabu:dharma-campa:INSCIC00001"

  def conformance_adapter = Nabu::Adapters::DharmaCampa.new

  def conformance_workdir = Nabu::TestSupport.fixtures("dharma-campa")

  def conformance_expected_source_id = "dharma-campa"

  def test_manifest
    manifest = Nabu::Adapters::DharmaCampa.manifest
    assert_equal "dharma-campa", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "dharma-epidoc", manifest.parser_family
  end

  def test_c1_is_old_cham_and_the_worklist_is_censused
    adapter = conformance_adapter
    refs = adapter.discover(conformance_workdir).to_a
    assert_equal [CIC1], refs.map(&:id), "BROUILLON-LISTE.xml is not an edition"
    document = adapter.parse(refs.first)
    assert_equal "ocm-Latn", document.language,
                 "the edition's own measured code — the oldest attested Austronesian language"
    skips = adapter.discovery_skips(conformance_workdir)
    assert_equal 1, skips.skipped_by_rule
    assert_match(/BROUILLON/, skips.notes.join(" "))
  end
end

class DharmaNusantaraTest < Minitest::Test
  include AdapterConformance

  N7 = "urn:nabu:dharma-nusantara:INSIDENK00007"
  N24 = "urn:nabu:dharma-nusantara:INSIDENK00024"
  N50 = "urn:nabu:dharma-nusantara:INSIDENK00050"

  # The languageb-Latn file quarantines by design, so the conformance
  # sweep runs over the two clean fixtures; the bug file is asserted
  # separately below.
  def conformance_adapter
    adapter = Nabu::Adapters::DharmaNusantara.new
    conformance_scope(adapter)
    adapter
  end

  def conformance_workdir = Nabu::TestSupport.fixtures("dharma-nusantara")

  def conformance_expected_source_id = "dharma-nusantara"

  def test_manifest
    assert_equal "dharma-nusantara", Nabu::Adapters::DharmaNusantara.manifest.id
  end

  def test_n7_prose_lines_wrap_the_stone_faces
    adapter = Nabu::Adapters::DharmaNusantara.new
    ref = adapter.discover(conformance_workdir).find { |r| r.id == N7 }
    document = adapter.parse(ref)
    assert_equal "omy-Latn", document.language
    line1 = document.passages.find { |p| p.urn == "#{N7}:1" }
    assert_match(/svasti śaka-varṣātīta/, line1.text)
    assert_match(/tithi pratipada/, line1.text,
                 "the face milestone (a→B) wraps mid-word: ti|thi joins with no space")
    line2 = document.passages.find { |p| p.urn == "#{N7}:2" }
    assert_match(/Inan· tatkāla/, line2.text,
                 "a new <p> without a leading <lb> continues the current physical line")
  end

  def test_n24_is_old_malay
    adapter = Nabu::Adapters::DharmaNusantara.new
    ref = adapter.discover(conformance_workdir).find { |r| r.id == N24 }
    assert_equal "omy-Latn", adapter.parse(ref).language
  end

  def test_the_upstream_languageb_bug_quarantines
    adapter = Nabu::Adapters::DharmaNusantara.new
    ref = adapter.discover(conformance_workdir).find { |r| r.id == N50 }
    refute_nil ref
    error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    assert_match(/languageb-Latn/, error.message,
                 "upstream's template-placeholder div is censused reality, quarantined loudly")
  end

  private

  # Scope discover to the two clean fixtures for the conformance sweep.
  def conformance_scope(adapter)
    clean = [N7, N24]
    original = adapter.method(:discover)
    adapter.define_singleton_method(:discover) do |workdir, &block|
      return enum_for(:discover, workdir) unless block

      original.call(workdir) { |ref| block.call(ref) if clean.include?(ref.id) }
    end
  end
end

class DharmaPyuTest < Minitest::Test
  include AdapterConformance

  PYU20 = "urn:nabu:dharma-pyu:INSPYU00020"

  def conformance_adapter = Nabu::Adapters::DharmaPyu.new

  def conformance_workdir = Nabu::TestSupport.fixtures("dharma-pyu")

  def conformance_expected_source_id = "dharma-pyu"

  def test_manifest
    assert_equal "dharma-pyu", Nabu::Adapters::DharmaPyu.manifest.id
  end

  def test_pyu20_parses_from_the_flat_repo_root
    adapter = conformance_adapter
    refs = adapter.discover(conformance_workdir).to_a
    assert_equal [PYU20], refs.map(&:id), "flat layout: editions at the repo root"
    document = adapter.parse(refs.first)
    assert_equal "pyx-Latn", document.language
    refute_empty document.passages
  end
end
