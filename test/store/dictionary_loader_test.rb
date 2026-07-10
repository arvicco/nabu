# frozen_string_literal: true

require "test_helper"

# Store::DictionaryLoader (P11-4): persists dictionary adapter output with the
# same idempotency / revision / withdrawal semantics as the passage Loader —
# upsert on (dictionary, entry_id), skip on identical sha, revise + bump on
# change, withdraw on full-load absence, journal transitions (provenance +
# durable ledger revisions). Runs against the real lexica fixtures.
class DictionaryLoaderTest < Minitest::Test
  include StoreTestDB

  def setup
    @db = store_test_db
    @ledger = ledger_test_db
    @adapter = Nabu::Adapters::Lexica.new
    @workdir = Nabu::TestSupport.fixtures("lexica")
    @source = Nabu::Store::Source.create(
      slug: "lexica", name: "Perseus Lexica", adapter_class: "Nabu::Adapters::Lexica",
      license: "CC BY-SA 4.0", license_class: "attribution",
      upstream_url: "https://github.com/PerseusDL/lexica", enabled: false
    )
  end

  def loader
    Nabu::Store::DictionaryLoader.new(db: @db, source: @source, ledger: @ledger)
  end

  def load!
    loader.load_from(@adapter, workdir: @workdir)
  end

  def test_first_load_creates_dictionaries_and_entries
    report = load!
    assert_equal 8, report.added # 4 LSJ entries (2 files) + 4 L&S entries
    assert_equal 0, report.errored
    assert_equal %w[lewis-short lsj], @db[:dictionaries].select_map(:slug).sort
    assert_equal 8, @db[:dictionary_entries].count
    menis = @db[:dictionary_entries].where(entry_id: "n67485").first
    assert_equal "μῆνις", menis[:headword]
    assert_equal "μηνισ", menis[:headword_folded]
    assert_equal "urn:nabu:dict:lsj:n67485", menis[:urn]
    assert_equal 1, menis[:revision]
  end

  def test_citations_are_persisted_in_entry_order
    load!
    menis_id = @db[:dictionary_entries].where(entry_id: "n67485").get(:id)
    citations = @db[:dictionary_citations].where(dictionary_entry_id: menis_id).order(:seq).all
    refute_empty citations
    iliad = citations.find { |row| row[:label] == "Il. 1.1" }
    assert_equal "urn:cts:greekLit:tlg0012.tlg001", iliad[:cts_work]
    assert_equal "1.1", iliad[:citation]
  end

  def test_loading_twice_is_idempotent
    load!
    before = snapshot
    report = load!
    assert_equal 0, report.added
    assert_equal 8, report.skipped
    assert_equal 0, report.updated
    assert_equal before, snapshot
  end

  def test_changed_entry_content_revises_and_journals
    load!
    # Same urn, different body: revision must bump and the transition must be
    # journaled (provenance + durable ledger).
    report = loader.load([modified_document], full: false)
    assert_equal 1, report.updated
    row = @db[:dictionary_entries].where(entry_id: "n67485").first
    assert_equal 2, row[:revision]
    assert_equal "changed body", row[:body]
    events = @db[:provenance].where(dictionary_entry_id: row[:id]).select_map(:event)
    assert_includes events, "revised"
    assert_includes @ledger[:revisions].where(urn: "urn:nabu:dict:lsj:n67485").select_map(:event), "revised"
  end

  def test_full_load_withdraws_entries_absent_from_the_batch_and_restores_them
    load!
    # A full load of ONE modified document (mhnis only) withdraws every other
    # entry; a fresh full fixture load then restores them.
    report = loader.load([modified_document], full: true)
    assert_equal 7, report.withdrawn
    assert_equal 7, @db[:dictionary_entries].where(withdrawn: true).count
    report = load!
    assert_equal 0, @db[:dictionary_entries].where(withdrawn: true).count
    assert_operator report.updated, :>=, 7 # the restores count as updates
  end

  def test_revision_replaces_citations_wholesale
    load!
    loader.load([modified_document], full: false)
    entry_row_id = @db[:dictionary_entries].where(entry_id: "n67485").get(:id)
    assert_equal 0, @db[:dictionary_citations].where(dictionary_entry_id: entry_row_id).count
  end

  def test_quarantined_file_counts_errored_and_batch_continues
    broken = Nabu::DocumentRef.new(source_id: "lexica", id: "lexica:lsj:broken.xml",
                                   path: File.join(@workdir, "README.md"), # not XML → ParseError
                                   metadata: { "dictionary" => "lsj" })
    real = @adapter
    wrapper = Nabu::Adapters::Lexica.new
    wrapper.define_singleton_method(:discover) do |workdir, &block|
      return enum_for(:discover, workdir) unless block

      block.call(broken)
      real.discover(workdir, &block)
    end
    report = Nabu::Store::DictionaryLoader.new(db: @db, source: @source, ledger: @ledger)
                                          .load_from(wrapper, workdir: @workdir)
    assert_equal 1, report.errored
    assert_equal 8, report.added, "the healthy files must still load"
  end

  private

  # The fixture μῆνις entry with its body replaced — a real model object, the
  # store-level testing seam (no fake TEI involved).
  def modified_document
    parsed = @adapter.discover(@workdir)
                     .map { |ref| @adapter.parse(ref) }
                     .find { |doc| doc.entries.any? { |e| e.entry_id == "n67485" } }
    entry = parsed.entries.find { |e| e.entry_id == "n67485" }
    document = Nabu::DictionaryDocument.new(slug: parsed.slug, language: parsed.language,
                                            title: parsed.title, canonical_path: parsed.canonical_path)
    document << Nabu::DictionaryEntry.new(
      entry_id: entry.entry_id, key_raw: entry.key_raw, language: entry.language,
      headword: entry.headword, headword_folded: entry.headword_folded,
      gloss: entry.gloss, body: "changed body", citations: []
    )
    document
  end

  def snapshot
    [@db[:dictionary_entries].order(:id).select_map(%i[entry_id content_sha256 revision withdrawn]),
     @db[:dictionary_citations].count]
  end
end
