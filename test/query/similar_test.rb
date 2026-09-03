# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Similar (P93-5, №R-36) — the URN-anchored semantic page
  # over hand-planted int8 vectors, scanned by the REAL sqlite-vec
  # extension. The extension is an owner-installed tool
  # (docs/manual/embed-venv.md): when absent on a box, the scan tests
  # skip honestly (the restricted-fixtures precedent) — the refusal
  # tests still run everywhere.
  class SimilarTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @vectors = Sequel.sqlite
      Nabu::Embed.ensure_schema!(@vectors)
      @source = Nabu::Store::Source.create(
        slug: "lit", name: "Lit", adapter_class: "TestAdapter", license_class: "open"
      )
      @doc = Nabu::Store::Document.create(
        source_id: @source.id, urn: "urn:d:1", title: "Iliad", language: "grc",
        content_sha256: "x", revision: 1, withdrawn: false
      )
    end

    def teardown
      @vectors.disconnect
    end

    def extension_present? = File.exist?(Nabu::Query::Similar.extension_path)

    def make_passage(urn:, text:, sequence:, language: "grc")
      Nabu::Store::Passage.create(
        document_id: @doc.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: text, content_sha256: "x", revision: 1, withdrawn: false
      )
    end

    def plant_vector(urn:, values:, language: "grc", model: Nabu::Embed::MODEL)
      @vectors[Nabu::Embed::VECTORS_TABLE].insert(
        model: model, urn: urn, language: language,
        text_sha: "sha-#{urn}", vec: Sequel.blob(values.pack("c*"))
      )
    end

    def plant_meta(model: Nabu::Embed::MODEL)
      @vectors[Nabu::Embed::META_TABLE].insert(
        model: model, dim: 4, encoding: "i8", worker_version: "test",
        updated_at: Time.now.utc.iso8601
      )
    end

    def similar = Nabu::Query::Similar.new(catalog: @catalog, vectors: @vectors)

    # -- the scan (needs the extension) --------------------------------------

    def test_neighbors_rank_by_cosine_distance_with_bands
      skip "sqlite-vec extension not installed on this box" unless extension_present?

      plant_meta
      %w[anchor close far].each_with_index do |name, index|
        make_passage(urn: "urn:d:1:#{name}", text: "text #{name}", sequence: index)
      end
      plant_vector(urn: "urn:d:1:anchor", values: [127, 0, 0, 0])
      plant_vector(urn: "urn:d:1:close", values: [126, 9, 0, 0])
      plant_vector(urn: "urn:d:1:far", values: [0, 127, 0, 0])

      page = similar.run("urn:d:1:anchor", limit: 5)

      assert_equal "urn:d:1:anchor", page.anchor_urn
      assert_equal Nabu::Embed::MODEL, page.model
      assert_equal %w[urn:d:1:close urn:d:1:far], page.results.map(&:urn),
                   "ascending cosine distance, anchor excluded"
      assert_equal "close", page.results.first.band
      assert_equal "loose", page.results.last.band, "orthogonal = distance 1.0 = loose"
      assert_includes page.results.first.snippet, "text close",
                      "the stored-text window rides every hit"
      assert_equal "Iliad", page.results.first.document_title
    end

    def test_subpool_is_same_language_only
      skip "sqlite-vec extension not installed on this box" unless extension_present?

      plant_meta
      make_passage(urn: "urn:d:1:a", text: "grc a", sequence: 0)
      make_passage(urn: "urn:d:1:b", text: "lat b", sequence: 1, language: "lat")
      plant_vector(urn: "urn:d:1:a", values: [127, 0, 0, 0])
      plant_vector(urn: "urn:d:1:b", values: [127, 0, 0, 0], language: "lat")

      page = similar.run("urn:d:1:a", limit: 5)
      assert_empty page.results,
                   "an identical Latin vector never serves a Greek anchor — the trial's NO is pinned"
    end

    # -- the honest refusals (run everywhere) --------------------------------

    def test_absent_store_names_the_build_command
      bare = Sequel.sqlite
      begin
        finder = Nabu::Query::Similar.new(catalog: @catalog, vectors: bare)
        error = assert_raises(Nabu::Error) { finder.run("urn:d:1:1") }
        assert_match(/nabu embed/, error.message)
      ensure
        bare.disconnect
      end
    end

    def test_unembedded_passage_distinguished_from_unknown_urn
      plant_meta
      make_passage(urn: "urn:d:1:held", text: "held", sequence: 0)

      error = assert_raises(Nabu::Error) { similar.run("urn:d:1:held") }
      assert_match(/no vector.*embed scope|embed_index/m, error.message,
                   "a held passage outside the scope names the flag, never a bare miss")
      error = assert_raises(Nabu::Error) { similar.run("urn:d:1:nope") }
      assert_match(/no passage/, error.message)
    end

    def test_missing_extension_names_the_install_step
      plant_meta
      make_passage(urn: "urn:d:1:a", text: "a", sequence: 0)
      plant_vector(urn: "urn:d:1:a", values: [127, 0, 0, 0])
      finder = Nabu::Query::Similar.new(catalog: @catalog, vectors: @vectors,
                                        extension: "/nonexistent/vec0.dylib")

      error = assert_raises(Nabu::Error) { finder.run("urn:d:1:a") }
      assert_match(/sqlite-vec.*embed-venv\.md|NABU_SQLITE_VEC/m, error.message)
    end
  end
end
