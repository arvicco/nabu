# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "store_test_db"

# The fresh-birth harness: the derived dbs at the first instant after
# `nabu rebuild` drops them — every catalog migration applied and not one
# row; a migrated ledger (in production the ledger SURVIVES the drop, so a
# test seeds whatever history it needs); a fulltext index either ABSENT
# (nil) or BORN EMPTY (the indexer's tables created, no row — the shape a
# run killed in its index stage leaves on disk, since the indexer creates
# its tables before it fills them); and a scratch canonical/ dir for the
# permanent-folder side.
#
# Status surfaces and desk fallback chains are pinned against this state:
# a fallback that reads a missing or unbuilt structure must say so — "—",
# :unbuilt, nil, a not-indexed hint, a loud finding — never print a zero
# (or a silence) that reads as "the library holds nothing", and never
# forget a durable fact that lives outside db/ (the ledger, canonical/).
#
#   include FreshBirth
#   catalog = fresh_catalog          # migrated, empty, models bound
#   ledger  = fresh_ledger           # migrated, empty, models bound
#   fulltext = born_empty_fulltext   # tables present, rows absent
#   dir = fresh_canonical_dir        # removed in teardown
module FreshBirth
  include StoreTestDB

  def fresh_catalog = store_test_db

  def fresh_ledger = ledger_test_db

  # The indexer's corpus tables, created bare: what an index stage that
  # died before its first commit leaves behind.
  def born_empty_fulltext
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    fulltext.run(Nabu::Store::Indexer::CREATE_TABLE)
    Nabu::Store::Indexer.create_lemma_table(fulltext)
    Nabu::Store::Indexer.create_char_postings_table(fulltext)
    fulltext
  end

  # A scratch canonical/ root, removed after the test.
  def fresh_canonical_dir
    dir = Dir.mktmpdir("nabu-fresh-birth")
    (@fresh_birth_dirs ||= []) << dir
    dir
  end

  def teardown
    (@fresh_birth_dirs || []).each { |dir| FileUtils.rm_rf(dir) }
    super
  end
end
