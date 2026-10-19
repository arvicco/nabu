# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::ArchiveAxes: the ruled archive-grain axes table
# (config/archive_axes.yml) — per source, each upstream archive label's
# findspot (with the held gazetteer refs) and its dating ladder: a
# designation naming a reign volume → the HELD regnal table's whole-reign
# span; a volume's own stated span; else the source's corpus period band.
class ArchiveAxesTest < Minitest::Test
  def teardown
    Nabu::ArchiveAxes.reset!
    Nabu::RegnalYears.reset!
  end

  def table = Nabu::ArchiveAxes.default

  def test_archive_findspots_carry_the_held_refs
    assert_equal ["Nippur", "cigs:NIP pleiades:912910"], table.place("achemenet", "Murashu")
    assert_equal ["Uruk", "cigs:URU pleiades:912986"], table.place("achemenet", "YOS7")
    assert_equal ["Sippar", "cigs:SAP pleiades:894089"], table.place("achemenet", "CT55")
    assert_equal ["Sippar", "cigs:SAP pleiades:894089"], table.place("achemenet", "Jursa_Bel-remanni")
    assert_nil table.place("achemenet", "Strassmaier"), "reign volumes gather many findspots"
    assert_nil table.place("achemenet", "Nowhere")
  end

  def test_a_reign_volume_designation_bands_through_the_regnal_table
    dating = table.dating("achemenet", "Strassmaier", "Strassmaier, Cyrus 45")
    assert_equal [-538, -530], dating.band
    assert_equal "regnal-reign", dating.precision
    assert_match(/Cyrus2/, dating.raw)
    assert_equal [-555, -539], table.dating("achemenet", "Strassmaier", "Strassmaier, Nebonidus 3").band
    assert_equal [-604, -562], table.dating("achemenet", "Strassmaier", "Strassmaier, Nebukadnezzar 7").band
  end

  def test_a_volume_stated_span_and_the_corpus_band_fall_back_in_order
    yos = table.dating("achemenet", "YOS7", "YOS 7 12")
    assert_equal [-538, -521], yos.band
    corpus = table.dating("achemenet", "CT55", "CT 55, 001")
    assert_equal [-547, -331], corpus.band, "period_bands' Achaemenid row"
    assert_equal "period", corpus.precision
    unknown_volume = table.dating("achemenet", "Strassmaier", "Strassmaier, Xerxes 1")
    assert_equal [-547, -331], unknown_volume.band, "an unmapped reign word falls to the corpus band"
  end

  def test_a_source_without_a_table_answers_nil
    assert_nil table.dating("cdli", "CT55", "x")
    assert_nil table.place("cdli", "CT55")
  end

  def test_an_unruled_regnal_key_is_a_config_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "archive_axes.yml")
      File.write(path, <<~YAML)
        sources:
          demo:
            corpus_period: Achaemenid
            archives:
              A:
                reigns: {pattern: "^A, (\\\\w+) ", rulers: {Foo: NoSuchKing}}
                note: x
      YAML
      assert_raises(Nabu::ArchiveAxes::ConfigError) { Nabu::ArchiveAxes.load(path) }
    end
  end
end
