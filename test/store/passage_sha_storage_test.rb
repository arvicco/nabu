# frozen_string_literal: true

require "test_helper"

module Store
  # The passage content hash's stored form (migration 056): the loader
  # writes 32 raw bytes into passages.content_sha_raw, and every reader
  # keeps reading the lower-case hex through the virtual content_sha256.
  # The oracles: what readers see is bit-identical to the hex the loader
  # always stored; reloads stay idempotent (a hex/blob comparison slip
  # would revise every passage in the library); a file still holding
  # hex-TEXT rows reloads without churn and revises into blob form only
  # where content actually changed.
  class PassageShaStorageTest < Minitest::Test
    include StoreTestDB

    # Real fixture corpora: plain text, annotation-bearing passages, CJK.
    CORPORA = {
      "suttacentral" => Nabu::Adapters::Suttacentral,
      "socinian-letters" => Nabu::Adapters::SocinianLetters,
      "cbeta" => Nabu::Adapters::Cbeta
    }.freeze

    def setup
      @ledger = ledger_test_db
      @db = store_test_db
    end

    def load_corpus(slug, klass)
      source = Nabu::Store::Source.first(slug: slug) ||
               Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: klass.name, license_class: "open")
      Nabu::Store::Loader.new(db: @db, source: source, ledger: @ledger)
                         .load_from(klass.new, workdir: Nabu::TestSupport.fixtures(slug), full: true)
    end

    def load_all = CORPORA.map { |slug, klass| load_corpus(slug, klass) }

    # urn => the hex the loader has always computed (and, before 056, stored).
    def expected_hexes
      CORPORA.each_with_object({}) do |(slug, klass), out|
        adapter = klass.new
        adapter.discover(Nabu::TestSupport.fixtures(slug)).each do |ref|
          adapter.parse(ref).passages.each do |passage|
            json = Nabu::Store::ContentHash.canonical_json(passage.annotations)
            out[passage.urn] = Nabu::Store::ContentHash.passage(passage, annotations_json: json)
          end
        end
      end
    end

    def served = @db[:passages].order(:id).select_map(%i[urn content_sha256])

    def stored_forms
      @db[:passages].distinct.select(Sequel.function(:typeof, :content_sha_raw).as(:type),
                                     Sequel.function(:length, :content_sha_raw).as(:bytes))
                    .map { |row| [row[:type], row[:bytes]] }
    end

    # The durable "revised" events whose urn is a PASSAGE urn.
    def passage_revisions
      @ledger[:revisions].where(event: "revised", urn: @db[:passages].select_map(:urn))
                         .select_map(%i[urn old_sha new_sha])
    end

    def revised_passage_events = passage_revisions.size

    # The journaled shas stay hex TEXT: old = what the row served before,
    # new = what it serves now.
    def assert_hex_revision(urn, before)
      _urn, old_sha, new_sha = passage_revisions.find { |row| row.first == urn }

      assert_equal before.to_h.fetch(urn), old_sha
      assert_equal @db[:passages].where(urn: urn).get(:content_sha256), new_sha
      assert_match(/\A[0-9a-f]{64}\z/, new_sha)
    end

    # Old-generation simulation: every row's raw column rewritten to the hex
    # TEXT the pre-056 loader stored (the virtual column reads it back).
    def downgrade_to_hex_text!
      @db[:passages].update(content_sha_raw: Sequel[:content_sha256])
    end

    # (a) + (e)
    def test_readers_see_the_exact_hex_the_loader_always_stored
      load_all
      expected = expected_hexes

      assert_operator expected.size, :>, 10, "a real multi-corpus sample"
      assert_equal expected.sort, served.sort, "every passage reads back its content hash bit-identically"
      assert(served.all? { |_urn, hex| hex.match?(/\A[0-9a-f]{64}\z/) }, "lower-case hex, never bytes")
      assert_equal [["blob", 32]], stored_forms, "new rows store 32 raw bytes"
    end

    # (b) the critical one — a document-level reload skip, AND a passage-level
    # comparison on a revised document, both stay churn-free.
    def test_reloading_is_idempotent_at_both_grains
      load_all
      before = served
      revisions_before = @ledger[:revisions].count

      again = load_all

      assert_equal 0, again.sum(&:updated), "nothing re-revised on an identical reload"
      assert_equal before, served
      assert_equal revisions_before, @ledger[:revisions].count, "no revision rows minted"

      changed = revise_one_passage_of_a_document
      assert_equal 1, revised_passage_events, "only the changed passage revises (blob rows compare equal)"
      assert_equal [changed], served.reject { |row| before.include?(row) }.map(&:first)
      assert_hex_revision(changed, before)
      assert_equal [["blob", 32]], stored_forms
    end

    # (c) a live file still carrying hex-TEXT rows
    def test_old_hex_text_rows_reload_without_churn_and_revise_into_blob_form
      load_all
      downgrade_to_hex_text!
      before = served
      text_rows = @db[:passages].count

      assert_equal [["text", 64]], stored_forms
      assert_equal 0, load_all.sum(&:updated), "an unchanged reload over text rows revises nothing"
      assert_equal before, served
      assert_equal [["text", 64]], stored_forms, "untouched rows are left as they are"

      changed = revise_one_passage_of_a_document

      assert_equal 1, revised_passage_events, "the unchanged siblings compare equal through the virtual column"
      assert_hex_revision(changed, before)
      assert_equal "blob", @db[:passages].where(urn: changed).get(Sequel.function(:typeof, :content_sha_raw))
      assert_equal [["blob", 32], ["text", 64]], stored_forms.sort
      assert_equal text_rows - 1, @db[:passages].where(Sequel.function(:typeof, :content_sha_raw) => "text").count
    end

    def test_the_stored_form_refuses_anything_but_lower_case_hex
      hex = "ab" * 32

      assert_equal [hex].pack("H*"), Nabu::Store::ContentHash.stored(hex)
      assert_kind_of Sequel::SQL::Blob, Nabu::Store::ContentHash.stored(hex)
      ["x", hex.upcase, "#{hex}0", nil].each do |bad|
        assert_raises(ArgumentError) { Nabu::Store::ContentHash.stored(bad) }
      end
    end

    def test_a_write_through_the_old_name_is_refused_on_the_model_path
      load_all
      passage = Nabu::Store::Passage.first

      assert_raises(Sequel::DatabaseError) { passage.update(content_sha256: "ab" * 32) }
    end

    private

    # Re-load the first multi-passage document with ONE passage's text
    # changed; returns that passage's urn.
    def revise_one_passage_of_a_document
      slug, klass = CORPORA.first
      adapter = klass.new
      documents = adapter.discover(Nabu::TestSupport.fixtures(slug)).lazy.map { |ref| adapter.parse(ref) }
      document = documents.find { |doc| doc.passages.size > 1 }
      target = document.passages.last
      revised = Nabu::Document.new(urn: document.urn, language: document.language, title: document.title,
                                   canonical_path: document.canonical_path, metadata: document.metadata,
                                   license_override: document.license_override)
      document.passages.each do |passage|
        text = passage.equal?(target) ? "#{passage.text} (revised)" : passage.text
        revised << Nabu::Passage.new(urn: passage.urn, language: passage.language, text: text,
                                     text_normalized: passage.equal?(target) ? text.downcase : passage.text_normalized,
                                     annotations: passage.annotations, sequence: passage.sequence)
      end
      source = Nabu::Store::Source.first(slug: slug)
      report = Nabu::Store::Loader.new(db: @db, source: source, ledger: @ledger).load([revised], full: false)
      assert_equal 1, report.updated
      target.urn
    end
  end
end
