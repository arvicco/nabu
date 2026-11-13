# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "support/paced_crawl_conformance"
require "digest"
require "fileutils"
require "json"
require "tmpdir"

# PleiasFrenchBooks adapter tests: PleIAs/French-PD-Books (Gallica OCR),
# pre-1700 cone. The fixture workdir (README in the fixture dir) is what
# the adapter's OWN fetch materializes from two trimmed real shards
# (fetch/: upstream rows re-written by upstream's writer, fastparquet
# 2023.10.1): three cone books (1563, 1626, 1652), one post-1699 row and
# one range straddling 1700 (the rejected grains, catalogue lines only).
# No network: fetch runs against WebMock stubs of the real HF URLs with the
# tree listing's pins swapped for the trimmed shards'.
class PleiasFrenchBooksTest < Minitest::Test
  include AdapterConformance
  include PacedCrawlConformance

  FIXTURES = Nabu::TestSupport.fixtures("pleias-french-books")
  FETCH = File.join(FIXTURES, "fetch")
  ADAPTER = Nabu::Adapters::PleiasFrenchBooks
  LETTRES = "urn:nabu:pleias-french-books:bpt6k9671998b"
  TRIOLETS = "urn:nabu:pleias-french-books:bpt6k54293789"
  EDICT = "urn:nabu:pleias-french-books:bpt6k96930955"
  SHARD_URL = %r{\Ahttps://huggingface\.co/datasets/PleIAs/French-PD-Books/resolve/#{ADAPTER::REVISION}/gallica_mono_(\d+)\.parquet\z}

  def conformance_adapter = ADAPTER.new(jit: false)
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "pleias-french-books"

  def adapter(**) = ADAPTER.new(delay: 0, timeout_backoff: 0, jit: false, **)

  def documents
    @documents ||= adapter.then { |a| a.discover(FIXTURES).to_h { |ref| [ref.id, a.parse(ref)] } }
  end

  def shard_bytes(name) = File.binread(File.join(FETCH, name))

  def stub_upstream(api_sha: ADAPTER::REVISION)
    api = JSON.parse(File.read(File.join(FETCH, "api-dataset.json"))).merge("sha" => api_sha)
    stub_request(:get, ADAPTER::API_URL).to_return(status: 200, body: JSON.generate(api))
    stub_request(:get, ADAPTER::TREE_URL).to_return(status: 200, body: File.read(File.join(FETCH, "tree.json")))
    stub_request(:get, format(ADAPTER::RESOLVE_URL, "README.md"))
      .to_return(status: 200, body: shard_bytes("README.md"))
    %w[gallica_mono_1.parquet gallica_mono_100.parquet].each do |name|
      stub_request(:get, format(ADAPTER::RESOLVE_URL, name)).to_return(status: 200, body: shard_bytes(name))
    end
  end

  def materialized_files(dir)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).reject do |rel|
      File.directory?(File.join(dir, rel)) || rel.start_with?("fetch/", "README.md", "manifest.yml") || rel == ADAPTER::LEDGER_FILE
    end.sort
  end

  # --- manifest -----------------------------------------------------------------

  def test_manifest_is_open_with_the_cards_own_words_and_both_credits
    manifest = ADAPTER.manifest
    assert_equal "pleias-french-books", manifest.id
    assert_equal "open", manifest.license_class
    assert_match(/The entire collection is in the public domain everywhere/, manifest.license)
    assert_match(/no license field/, manifest.license)
    assert_match(/Gallica/, manifest.credit)
    assert_match(/PleIAs/, manifest.credit)
    assert_equal "pleias-parquet", manifest.parser_family
  end

  def test_the_cone_and_the_materialized_tree_are_declared
    assert_equal 1699, ADAPTER::CONE.ceiling
    assert_equal %w[tree.json dataset-card.md shards books], ADAPTER.materialized_paths
    assert_equal "21abfb3f646a0f1846175c63709913a51abc9bcb", ADAPTER::REVISION
  end

  # --- fetch --------------------------------------------------------------------

  def test_fetch_materializes_exactly_the_fixture_tree
    stub_upstream
    Dir.mktmpdir do |dir|
      report = adapter.fetch(dir)
      assert_equal materialized_files(FIXTURES), materialized_files(dir)
      materialized_files(FIXTURES).each do |rel|
        assert_equal File.binread(File.join(FIXTURES, rel)), File.binread(File.join(dir, rel)), rel
      end
      refute File.exist?(File.join(dir, ADAPTER::STAGING_DIR)), "the staged shards go with the slice"
      assert_match(/census 2 = held 2 \(\+2\)/, report.notes)
      refute_match(/upstream main is now/, report.notes)
    end
  end

  def test_a_held_shard_is_never_downloaded_again
    stub_upstream
    Dir.mktmpdir do |dir|
      adapter.fetch(dir)
      adapter.fetch(dir)
      assert_requested :get, format(ADAPTER::RESOLVE_URL, "gallica_mono_1.parquet"), times: 1
    end
  end

  def test_upstream_moving_past_the_pin_is_noted_not_followed
    stub_upstream(api_sha: "0" * 40)
    Dir.mktmpdir do |dir|
      notes = adapter.fetch(dir).notes
      assert_match(/upstream main is now 0{40}; this era stays pinned to #{ADAPTER::REVISION}/, notes)
    end
  end

  def test_a_shard_missing_its_sha_pin_raises_and_keeps_nothing
    stub_upstream
    stub_request(:get, format(ADAPTER::RESOLVE_URL, "gallica_mono_1.parquet"))
      .to_return(status: 200, body: shard_bytes("gallica_mono_100.parquet"))
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(dir) }
      assert_match(/gallica_mono_1\.parquet misses its sha256 pin/, error.message)
      refute File.exist?(File.join(dir, "shards", "1.json"))
      assert_empty Dir.glob(File.join(dir, "books", "*"))
    end
  end

  def test_a_new_cone_requeues_every_shard
    stub_upstream
    Dir.mktmpdir do |dir|
      adapter.fetch(dir)
      wider = ADAPTER::Cone.new(id: "imprint-envelope<=1799", ceiling: 1799)
      adapter(cone: wider).fetch(dir)
      assert_requested :get, format(ADAPTER::RESOLVE_URL, "gallica_mono_1.parquet"), times: 2
      assert_equal "imprint-envelope<=1799", JSON.parse(File.read(File.join(dir, "shards", "1.json")))["cone"]
      assert_equal 5, adapter(cone: wider).discover(dir).count, "the 1783 row and the 1633–1742 range join a ≤1799 cone"
    end
  end

  # The paced-crawl conformance through the real wiring: the pinned
  # listing is the universe (every id pinned to the trimmed shard 1), the
  # stamp the held rule; the stub answers each shard GET per the script.
  def paced_crawl_engine(dir:, ids:, slice:, script:)
    shard = shard_bytes("gallica_mono_1.parquet")
    shards = ids.to_h do |id|
      [id, { "path" => "gallica_mono_#{id}.parquet", "size" => shard.bytesize,
             "sha256" => Digest::SHA256.hexdigest(shard) }]
    end
    File.write(File.join(dir, ADAPTER::TREE_FILE), JSON.generate("revision" => ADAPTER::REVISION, "shards" => shards))
    empty = File.binread(File.join(Nabu::TestSupport.fixtures("parquet"), "empty.parquet"))
    stub_request(:get, SHARD_URL).to_return do |request|
      case script.call(request.uri.path[/gallica_mono_(\d+)\.parquet/, 1])
      when :ok then { status: 200, body: shard }
      when :denied then { status: 403, body: PacedCrawlConformance::PC_REFUSAL_BODY }
      when :empty then { status: 200, body: empty }
      when :timeout then raise Net::ReadTimeout
      when :fatal then { status: 500, body: "internal error" }
      end
    end
    adapter(slice: slice).shard_crawl(dir)
  end

  def paced_crawl_hold!(dir, id)
    FileUtils.mkdir_p(File.join(dir, "shards"))
    File.write(File.join(dir, "shards", "#{id}.json"),
               JSON.generate("revision" => ADAPTER::REVISION, "cone" => ADAPTER::CONE.id))
    FileUtils.cp(File.join(FIXTURES, "shards", "1.jsonl"), File.join(dir, "shards", "#{id}.jsonl"))
  end

  def test_the_lane_keeps_the_committed_etiquette
    lane = ADAPTER::SHARD_CRAWL
    assert_equal ["shards", ".pleias-crawl.json", 1.0, 25, 3, 5.0],
                 [lane.name, lane.ledger_file, lane.delay, lane.slice, lane.timeout_attempts, lane.timeout_backoff]
    assert_equal %w[denied empty timeout-stuck], lane.class_names
    assert_equal [:per_phase, 6], [lane.schedule.cadence, lane.schedule.slices_per_phase]
  end

  def test_paced_crawls_is_the_chain_seam
    Dir.mktmpdir do |dir|
      lanes = adapter.paced_crawls(dir)
      assert_equal ["shards"], lanes.keys
      assert_kind_of Nabu::PacedCrawl::Engine, lanes["shards"]
    end
  end

  # --- discovery ----------------------------------------------------------------

  def test_discovers_the_cone_books_in_shard_then_row_order
    assert_equal [LETTRES, TRIOLETS, EDICT], documents.keys
  end

  def test_out_of_cone_rows_skip_by_rule_with_their_reasons
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 2, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_includes skips.notes, "1 row(s): printed after 1699 (outside the cone)"
    assert_includes skips.notes,
                    "1 row(s): date range opens before 1700 and closes after it (serials, multi-volume sets)"
  end

  def test_a_missing_cone_book_and_a_stray_book_are_unrecognized
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "{tree.json,shards,books}")), dir)
      FileUtils.mv(File.join(dir, "books", "bpt6k9671998b.json.gz"), File.join(dir, "books", "bpt6k0000000x.json.gz"))
      skips = adapter.discovery_skips(dir)
      assert_equal 2, skips.unrecognized
      assert_includes skips.notes, "shards/1: cone row bpt6k9671998b has no book file"
      assert_includes skips.notes, "books/bpt6k0000000x.json.gz: no held catalogue names it"
      assert_equal [TRIOLETS, EDICT], adapter.discover(dir).map(&:id)
    end
  end

  def test_a_shard_stamped_for_another_cone_is_not_held
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "{tree.json,shards,books}")), dir)
      stamp = File.join(dir, "shards", "1.json")
      File.write(stamp, JSON.generate(JSON.parse(File.read(stamp)).merge("cone" => "imprint-envelope<=1599")))
      assert_empty adapter.discover(dir).to_a
    end
  end

  def test_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  # --- dates --------------------------------------------------------------------

  def test_upstream_date_shapes_read_as_envelopes
    {
      "1626" => [1626, 1626], "1633-1742" => [1633, 1742], "1607-16" => [1607, 1616],
      "1932-11" => [1932, nil], "1843-18.." => [1843, 1899], "1863-????" => [1863, nil],
      "1847-." => [1847, nil], "1890-1889" => [1890, 1889]
    }.each { |raw, envelope| assert_equal envelope, ADAPTER.date_envelope(raw), raw }
    assert_nil ADAPTER.date_envelope("")
  end

  # --- passages -----------------------------------------------------------------

  def test_one_passage_per_page_segment_cited_by_its_ordinal
    lettres = documents.fetch(LETTRES)
    assert_equal 7, lettres.size
    assert_equal "#{LETTRES}:1", lettres.first.urn
    assert lettres.first.text.start_with?("LETTRES\nPATENTES DV ROY, PORTANT continuation"), lettres.first.text[0, 40]
    assert_equal({ "segment" => 1 }, lettres.first.annotations)
  end

  def test_blank_segments_mint_nothing_and_keep_their_ordinals
    triolets = documents.fetch(TRIOLETS)
    assert_equal "#{TRIOLETS}:3", triolets.first.urn, "the two leading blank pages mint no passage"
    assert_match(/IE m'en vais Chanter hautement, Les louanges de son Altesse/, triolets.first.text)
    assert triolets.to_a[2].text.start_with?("ri\n5 Son Altesse"), "the next page opens with its number"
  end

  def test_upstreams_escaped_entities_decode_and_lines_are_trimmed
    text = documents.values.flat_map { |doc| doc.map(&:text) }.join("\n")
    refute_match(/&amp;|&lt;|&gt;/, text)
    assert_includes documents.fetch(LETTRES).to_a[1].text, "Benefices qui ont esté cy deuant 'Uendus & alienez"
    refute_match(/ \n|\n\z/, text, "no trailing spaces, no edge blank lines")
    assert_includes documents.fetch(EDICT).to_a[1].text, "[texte_manquant]", "Gallica's gap marker kept"
  end

  def test_an_overlong_page_splits_at_line_boundaries
    line = "#{documents.fetch(LETTRES).to_a[2].text.lines.first.chomp}\n"
    page = line * ((ADAPTER::MAX_PASSAGE_CHARS / line.length) + 5)
    chunks = adapter.send(:split_page, page)
    assert_equal 2, chunks.size
    assert(chunks.all? { |chunk| chunk.length <= ADAPTER::MAX_PASSAGE_CHARS })
    assert_equal page.strip, chunks.join("\n")
  end

  # --- axes ---------------------------------------------------------------------

  def test_the_catalogue_row_mines_the_axes
    meta = documents.fetch(EDICT).metadata
    assert_equal "machine-ocr", meta["text_nature"]
    assert_equal "ark:/12148/bpt6k96930955", meta["gallica_ark"]
    assert_equal "https://gallica.bnf.fr/ark:/12148/bpt6k96930955", meta["source_url"]
    assert_equal({ "not_before" => 1563, "not_after" => 1563, "raw" => "1563", "class" => "edition" }, meta["date"])
    assert_equal "Charles IX (1550-1574 ; roi de France)", meta["author"]
    assert_equal({ "values" => ["Charles IX (1550-1574 ; roi de France)"] }, meta.dig("facets", "author"))
    assert_equal [82, 12, 890, 6423], meta.values_at("ocr_quality", "gallica_views", "word_count", "character_count")
    assert_equal ["gallica_mono_1.parquet", 3], meta.values_at("hf_shard", "hf_row")
    assert_equal "Édit", meta.dig("facets", "genre", "value")
  end

  def test_upstreams_none_author_reads_as_absent
    meta = documents.fetch(TRIOLETS).metadata
    assert_nil meta["author"]
    assert_nil meta.dig("facets", "author")
    assert_equal "Triolet", meta.dig("facets", "genre", "value")
  end

  def test_titles_decode_entities
    assert_match(/vendus & aliénez/, documents.fetch(LETTRES).title)
    assert_equal "Lettres patentes", documents.fetch(LETTRES).metadata.dig("facets", "genre", "value")
  end

  def test_every_book_is_french
    assert(documents.values.all? { |doc| doc.language == "fra" && doc.all? { |p| p.language == "fra" } })
  end
end
