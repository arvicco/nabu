# frozen_string_literal: true

require "test_helper"

# THE DERIVABILITY LAW's writer guards (P71-5; the lects_test callsite
# pattern): persistent state may enter the tree only through the
# sanctioned gateways, and SQLite handles open only through Store's
# gate. A new writer cannot appear without deliberately touching an
# allowlist here — which is the moment its law classification gets
# asked.
class DerivabilityWritersTest < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)

  # (a) Sequel connections: store.rb is the ONE opener (WAL, timeouts,
  # readonly discipline live there). Everything else asks Store.
  def test_sequel_opens_only_through_store
    offenders = grep_files(/Sequel\.(connect|sqlite)\b/).reject { |f| f == "nabu/store.rb" }
    assert_empty offenders,
                 "Sequel opened outside Store's gate: #{offenders.join(', ')} — use " \
                 "Store.connect(..., readonly: true/false)"
  end

  # (b) Journal rows carry config write-throughs: only these callsites
  # may mint lect assignments (cli writes through LectRulings first;
  # the appliers replay config; the test-support rig is suite-only).
  ASSIGN_ALLOWLIST = %w[nabu/cli.rb nabu/lect_rules.rb nabu/lect_dates.rb nabu/lect_rulings.rb].freeze

  def test_lect_journal_assign_callsites_are_allowlisted
    offenders = grep_files(/LectJournal\.assign!/) - ASSIGN_ALLOWLIST - ["nabu/store/lect_journal.rb"]
    assert_empty offenders,
                 "LectJournal.assign! called from #{offenders.join(', ')} — new journal writers " \
                 "must keep the local/config write-through in view (P70-2)"
  end

  # (c) Persistent-file writers: the sanctioned gateway census. Fetch
  # arms and adapters write canonical/ inside #fetch; the four shelves +
  # ingest write local/shelves/; the write-through modules write
  # local/config/; ops/ and data_build/ write generated repo/site or
  # caller-named output (places_lpf_builder writes its GeoJSON/TSV into
  # the runner's caller-named dataset dir — P73-5; readme_index rewrites
  # the generated dataset table between markers in the caller-named
  # clone's README.md — the runner/caller-named-output law kind, owner
  # correction 2026-10-17 after the hand table went a release stale);
  # fixture_sentinel
  # writes test fixtures; local_migration executes the P71 layout move;
  # ops/drill writes its evidence files (report.txt, verify-issues.tsv)
  # into its OWN tmp workspace, and its workspace sweep (P77-r14)
  # salvages those same small files into the caller-named drill-log
  # home (~/Library/Logs/nabu via the rake harness) before removing a
  # superseded workspace — disposable ops evidence, never a permanent
  # folder (P77-r10/r14). The two P78 wikisource adapters
  # (ko_wikisource_mk, viet_wikisource) write their fetched page
  # envelopes into canonical/ inside Adapter#fetch — the sanctioned
  # canonical gateway, the burman/wiki_fetch law kind. The P116-2
  # South Slavic family writes through its one shared base
  # (slavic_wikisource) inside Adapter#fetch — the same law kind.
  # corpus_corporum_fetch (P80-2) writes canonical/<slug>/texts/ +
  # attic + its state checkpoint inside Adapter#fetch — the
  # elephantine_fetch law kind. menota_fetch (P82-1) writes
  # canonical/<slug>/texts/ + the MUFI entity table + attic + its
  # catalogue checkpoint inside Adapter#fetch — the same
  # elephantine/corpus-corporum law kind. cme_fetch (P82-2) writes
  # canonical/cme/texts/ (tmp+rename) + attic copies + its state
  # ledger inside Adapter#fetch — the derom_fetch law kind, its
  # fifth crawl sibling. eebo_tcp_fetch (P83-1) writes
  # canonical/eebo-tcp/texts/<phase>/<stem>/ (per-zip ZipFetch staging
  # + tmp discipline), the ID-list/DTD sidecars (tmp+rename), attic
  # copies and its state ledger inside Adapter#fetch — the
  # zip_fetch/corpus_corporum law kind at zip grain. lemma_shelf (P84-1)
  # is the FIFTH local-shelf gateway: it writes the silver-lemma
  # enricher's non-derivable model output as JSONL shards
  # (tmp+validate+rename) plus its campaign checkpoint under
  # local/shelves/local-lemmas/ — the shelf-gateway law kind at machine
  # grain, the corpus-corporum checkpoint kind for state. date_shelf
  # (P122-1) is the SIXTH local-shelf gateway: it writes model/tool date
  # estimates as JSONL shards (tmp+validate+rename) plus the owner's
  # projection arm marker under local/shelves/local-dates/ — the
  # shelf-gateway law kind at document grain. The P80-8 ctilc
  # adapter writes its crawled works (tmp+rename) and their replacement
  # attic copies into canonical/ inside Adapter#fetch — the riig crawl
  # law kind. seal_fetch (P89-3) writes canonical/seal/texts/
  # (tmp+rename) + the search-index sidecars + attic copies + its state
  # ledger inside Adapter#fetch — the cantigas_fetch law kind, its
  # fourth crawl sibling. The P96-4 cbdb adapter writes
  # canonical/cbdb/ inside Adapter#fetch — the downloaded zip
  # (removed after unpack), the unpacked sqlite artifact, and the
  # .cbdb-fetch.json sha pin — the zip_fetch/file_fetch law kind
  # with a latest.json self-pinning channel. The P107 five:
  # scripta_bulgarica_fetch writes canonical/scripta-bulgarica/
  # (pager index sidecars + sources/<slug>.html mirrors) inside
  # Adapter#fetch — the cantigas_fetch law kind, its fifth crawl
  # sibling; the iedc / shkz / altaica-shm adapters move ONE
  # UrlDownload-fetched file each to its house name inside
  # Adapter#fetch (FileUtils.mv, the burman_concordance law kind);
  # atmo does the same for its index + the 18 transcripts it lists;
  # the P108 trio (kouigenji's 54 maki, kokubunken's three TEIs,
  # nrct's one CSV) move UrlDownload fetches to house names the
  # same way — the burman_concordance law kind.
  # canonical_identity_cache (P116) writes ONE derived file,
  # db/canonical_identities.json (tmp+rename): the census-keyed memo of
  # plain-tree canonical identities — the DERIVED law kind (a pure
  # function of canonical/ + code; deletable at any time, a miss re-hashes).
  # Its sibling git_identity_cache writes ONE derived file,
  # db/git_identities.json (tmp+rename): the census-keyed memo of embedded
  # git repos' identity tokens — the same DERIVED law kind (a miss pays the
  # full git call).
  # same way — the burman_concordance law kind. The P116-3 Slavic
  # wikisource family base (slavic_wikisource) writes page envelopes
  # (tmp+rename) + its .<slug>-fetch.json pin into canonical/<slug>/
  # inside Adapter#fetch, and the pl Brückner lane writes its stub index
  # + scan envelopes under canonical/pl-wikisource/bruckner/ from that
  # same fetch — the ja/zh-wikisource law kind. P120-2's ban_wikisource
  # (that base's ProofreadPage sibling) writes one Index envelope per
  # manuscript (tmp+rename) + the same pin, likewise inside its fetch. P117's litopys_fetch
  # writes the censused Izbornyk pages (verbatim windows-1251, tmp+rename,
  # site paths) + its .litopys-fetch.json pin into canonical/litopys/
  # inside Adapter#fetch — the titus_fetch law kind.
  # same fetch — the ja/zh-wikisource law kind. mdz-protestant
  # writes IIIF manifests + per-page hOCR (tmp+rename) and its
  # .mdz-crawl.json ledger into canonical/mdz-protestant/ inside
  # Adapter#fetch — the ndl-kotenseki crawl law kind.
  # same fetch — the ja/zh-wikisource law kind. The P117-2
  # elektire_fetch writes canonical/elektire/ (the WP-JSON listing
  # pages under index/ + epub/<slug>.epub books, tmp+rename, and its
  # .elektire-fetch.json pin) inside Adapter#fetch — the cantigas_fetch
  # law kind, its sixth crawl sibling.
  # same fetch — the ja/zh-wikisource law kind. The archive.org
  # scan-shelf base (ia_scan_shelf) writes each census item's hOCR
  # derivative pair (.part + rename, whole item or nothing) under
  # canonical/<slug>/<identifier>/ inside Adapter#fetch — the same
  # canonical-gateway law kind. The P124-1 bu_ajami_fetch writes
  # canonical/bu-ajami/ (the NEH Ajami item pages under items/ + their
  # transcription PDFs under files/, .part + rename, and its
  # .bu-ajami-fetch.json pin) inside Adapter#fetch — the elektire_fetch
  # WP-JSON crawl law kind. The damos adapter writes canonical/damos/
  # (the POSTed listing under map/ + items/<id>.json, tmp+rename, and
  # its .damos-crawl.json ledger) inside Adapter#fetch — the
  # ndl-kotenseki crawl law kind. The itkc-catalog module writes
  # canonical/itkc-catalog/ (the OpenAPI 서지 response pages under
  # <section>/<start>.xml, tmp+rename, stale pages renamed into .attic/)
  # inside Adapter#fetch — the same crawl law kind.
  # credentials (the credentials seam) writes ONE instance file,
  # local/config/credentials.yml (tmp born mode 600 + chmod + rename),
  # driven only by the `nabu creds set` gateway — the local/config
  # write-through law kind (grant_gate's grants.yml sibling); never db/.
  # The ig-cyprus adapter writes its crawled IG XV 1,1 records
  # (canonical/ig-cyprus/documents/, tmp+rename) inside Adapter#fetch —
  # the riig crawl law kind.
  # ANY new file here is a deliberate allowlist decision, not a
  # drive-by.
  WRITER_ALLOWLIST = %w[
    nabu/adapters/bfm.rb nabu/adapters/ctilc.rb nabu/adapters/ig_cyprus.rb
    nabu/adapters/kitab.rb nabu/adapters/oracc.rb
    nabu/adapters/riig.rb nabu/adapters/rundata.rb
    nabu/adapters/sabellic_loans.rb nabu/adapters/trismegistos.rb
    nabu/cantigas_fetch.rb nabu/cme_fetch.rb
    nabu/corpus_corporum_fetch.rb nabu/eebo_tcp_fetch.rb
    nabu/derom_fetch.rb nabu/elephantine_fetch.rb
    nabu/file_fetch.rb nabu/git_fetch.rb nabu/iness_fetch.rb
    nabu/kanripo_fetch.rb nabu/lfs_fetch.rb nabu/local_fetch.rb
    nabu/menota_fetch.rb
    nabu/manual_drop.rb nabu/ochre_fetch.rb nabu/otdo_fetch.rb
    nabu/poma_fetch.rb nabu/bu_ajami_fetch.rb
    nabu/seal_fetch.rb
    nabu/sefaria_fetch.rb nabu/titus_fetch.rb nabu/url_download.rb
    nabu/litopys_fetch.rb
    nabu/wiki_fetch.rb nabu/zip_fetch.rb
    nabu/adapters/altaica_shm.rb nabu/adapters/atmo.rb
    nabu/adapters/iedc.rb nabu/adapters/shkz.rb
    nabu/scripta_bulgarica_fetch.rb nabu/elektire_fetch.rb
    nabu/adapters/kouigenji.rb nabu/adapters/kokubunken.rb
    nabu/adapters/nrct.rb
    nabu/adapters/burman_concordance.rb nabu/adapters/cbdb.rb
    nabu/adapters/ko_wikisource_mk.rb nabu/adapters/viet_wikisource.rb
    nabu/adapters/ja_wikisource.rb nabu/adapters/zh_wikisource.rb
    nabu/adapters/slavic_wikisource.rb nabu/adapters/ban_wikisource.rb
    nabu/adapters/slavic_wikisource_html.rb nabu/adapters/pl_wikisource_bruckner_lane.rb
    nabu/adapters/hittite_glossed.rb nabu/adapters/ndl_kotenseki.rb
    nabu/adapters/aclt.rb
    nabu/adapters/mdz_protestant.rb
    nabu/adapters/damos.rb nabu/adapters/itkc_catalog.rb
    nabu/adapters/aclt.rb nabu/adapters/ia_scan_shelf.rb
    nabu/language_shelf.rb nabu/lemma_shelf.rb nabu/date_shelf.rb
    nabu/library_shelf.rb nabu/note_shelf.rb
    nabu/source_shelf.rb nabu/ingest.rb
    nabu/lect_rulings.rb nabu/link_scopes.rb nabu/grant_gate.rb nabu/credentials.rb
    nabu/health/quarantine_baseline.rb nabu/profile.rb
    nabu/health/shed_acceptance.rb
    nabu/ops/axis_pages.rb nabu/ops/site_data.rb
    nabu/ops/drill.rb
    nabu/data_build/runner.rb nabu/data_build/sources_bib.rb
    nabu/data_build/places_lpf_builder.rb nabu/data_build/readme_index.rb
    nabu/fixture_sentinel.rb nabu/local_migration.rb
    nabu/canonical_identity_cache.rb nabu/git_identity_cache.rb
  ].freeze

  def test_file_writers_are_allowlisted
    offenders = grep_files(/File\.(write|binwrite)|IO\.write|FileUtils\.(mv|cp)\b/) - WRITER_ALLOWLIST
    assert_empty offenders,
                 "persistent-file writer outside the gateway census: #{offenders.join(', ')} — " \
                 "declare it here deliberately and name what it writes and its law kind"
  end

  private

  def grep_files(pattern)
    Dir.glob(File.join(LIB, "**", "*.rb")).select { |path| File.read(path).match?(pattern) }
                                          .map { |path| path.delete_prefix("#{LIB}/") }.sort
  end
end
