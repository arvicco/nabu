# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The scansion campaign (P152): Scansion over the live lat/grc passages,
# verdicts onto the local-meter shelf — the document verse gate keeps
# prose off the shelf, and a re-fire is delta-only (resumable).
class MeterScanTest < Minitest::Test
  VERSE = [
    "Arma virumque cano, Troiae qui primus ab oris",
    "litora, multum ille et terris iactatus et alto",
    "Arma gravi numero violentaque bella parabam",
    "edere, materia conveniente modis."
  ].freeze
  PROSE = [
    "Gallia est omnis divisa in partes tres, quarum unam incolunt Belgae, aliam Aquitani.",
    "Hi omnes lingua, institutis, legibus inter se differunt."
  ].freeze

  def with_world
    catalog = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(catalog)
    src = catalog[:sources].insert(slug: "perseus", name: "P", adapter_class: "X", license_class: "open")
    { "urn:t:verse" => VERSE, "urn:t:prose" => PROSE }.each do |urn, lines|
      doc = catalog[:documents].insert(source_id: src, urn: urn, language: "lat", content_sha256: "x")
      lines.each_with_index do |text, i|
        catalog[:passages].insert(document_id: doc, urn: "#{urn}:#{i + 1}", sequence: i, language: "lat", text: text,
                                  text_normalized: text, content_sha256: "sha-#{urn}-#{i}")
      end
    end
    Dir.mktmpdir("nabu-meter-scan") do |root|
      yield catalog, Nabu::MeterShelf.new(dir: File.join(root, "local-meter"))
    end
  ensure
    catalog&.disconnect
  end

  def test_verse_documents_shelve_their_lines_and_prose_shelves_one_gate_record
    with_world do |catalog, shelf|
      report = Nabu::MeterScan.new(catalog: catalog, shelf: shelf).run
      assert_equal [2, 1, 1], [report.documents, report.verse_documents, report.gated_documents]
      latest = shelf.latest_by_urn
      assert_equal(%w[hexameter hexameter hexameter pentameter],
                   (1..4).map { |i| latest["urn:t:verse:#{i}"].meter })
      assert_equal "DDSSD", latest["urn:t:verse:1"].feet
      gate = latest["urn:t:prose"]
      assert_equal ["document", 2, 0], [gate.kind, gate.passages, gate.scanned]
      refute latest.key?("urn:t:prose:1"), "prose lines never reach the shelf"
    end
  end

  def test_a_refire_is_delta_only
    with_world do |catalog, shelf|
      Nabu::MeterScan.new(catalog: catalog, shelf: shelf).run
      again = Nabu::MeterScan.new(catalog: catalog, shelf: shelf).run
      assert_equal 0, again.records, "everything current: nothing re-shelved"
      assert_equal 1, again.current_documents
      catalog[:passages].where(urn: "urn:t:verse:2").update(content_sha256: "re-parsed")
      moved = Nabu::MeterScan.new(catalog: catalog, shelf: shelf).run
      assert_equal 1, moved.records
      assert_equal "re-parsed", shelf.latest_by_urn["urn:t:verse:2"].content_sha256
    end
  end

  def test_a_long_prose_document_ends_at_the_probe
    with_world do |catalog, shelf|
      src = catalog[:sources].get(:id)
      doc = catalog[:documents].insert(source_id: src, urn: "urn:t:long", language: "lat", content_sha256: "x")
      (Nabu::MeterScan::PROBE + 10).times do |i|
        catalog[:passages].insert(document_id: doc, urn: "urn:t:long:#{i}", sequence: i, language: "lat",
                                  text: PROSE[i % 2], text_normalized: "p", content_sha256: "p#{i}")
      end
      report = Nabu::MeterScan.new(catalog: catalog, shelf: shelf).run(urn_prefix: "urn:t:long")
      assert_equal Nabu::MeterScan::PROBE, report.passages, "only the probe was read and scanned"
      gate = shelf.latest_by_urn["urn:t:long"]
      assert_equal [Nabu::MeterScan::PROBE + 10, 0], [gate.passages, gate.scanned]
    end
  end

  def test_scope_by_source_and_urn_prefix_and_the_census
    with_world do |catalog, shelf|
      scan = Nabu::MeterScan.new(catalog: catalog, shelf: shelf)
      assert_equal 6, scan.candidate_passages
      assert_equal 4, scan.candidate_passages(urn_prefix: "urn:t:verse")
      assert_equal 0, scan.candidate_passages(source: "nowhere")
      assert_equal 0, scan.candidate_passages(language: "grc")
      report = scan.run(urn_prefix: "urn:t:verse")
      assert_equal 1, report.documents
    end
  end
end
