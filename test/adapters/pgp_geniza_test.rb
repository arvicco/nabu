# frozen_string_literal: true

require "test_helper"
require "csv"
require "tmpdir"
require "support/adapter_conformance"

module Adapters
  # pgp-geniza — the Princeton Geniza Project's own data export
  # (princetongenizalab/pgp-metadata, CC BY-NC 4.0): documents.csv joined to
  # the digital editions and translations footnotes.csv carries as plain
  # text. Fixture: nine real documents.csv rows and every footnote of them
  # (plus three rejected-grain specimens), with the fragments / sources /
  # places rows they join to — see test/fixtures/pgp-geniza/README.md for
  # the grain enumeration.
  class PgpGenizaTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("pgp-geniza")
    KLASS = Nabu::Adapters::PgpGeniza
    URN = "urn:nabu:pgp-geniza"

    INDIA_BOOK = "goitein-s-d-friedman-mordechai-akiva-india-book-3-abraham-ben-2010"
    INDIA_TRADERS = "goitein-s-d-friedman-mordechai-akiva-india-traders-of-the-middle-2008-3"

    def conformance_adapter = KLASS.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "pgp-geniza"

    def adapter = @adapter ||= KLASS.new

    def refs = @refs ||= adapter.discover(FIXTURES).to_a

    def document(id)
      ref = refs.find { |r| r.id == "#{URN}:#{id}" } or flunk("no ref for #{id}")
      adapter.parse(ref)
    end

    def raw_content(pgpid, slug)
      CSV.foreach(File.join(FIXTURES, "data", "footnotes.csv"), headers: true, encoding: "bom|utf-8")
         .find { |row| row["document_id"] == pgpid && row["source_slug"] == slug && row["content"] }
         .fetch("content")
    end

    # --- manifest ------------------------------------------------------------------

    def test_manifest_records_the_noncommercial_grant_and_the_credit
      manifest = KLASS.manifest
      assert_equal "pgp-geniza", manifest.id
      assert_equal "nc", manifest.license_class
      assert_match(/CC BY-NC 4\.0/, manifest.license)
      assert_match(%r{10\.5281/zenodo\.15839055}, manifest.license)
      assert_match(/Princeton Geniza Project/, manifest.credit)
      assert_equal "https://github.com/princetongenizalab/pgp-metadata", manifest.upstream_url
    end

    # --- discover + the grain census -------------------------------------------------

    def test_discover_yields_edition_documents_and_translation_siblings_in_pgpid_order
      expected = %w[723 1071 1071-heb 4737 4737-en 8339 8742 16766 16766-en 28363 36492-en].map { |id| "#{URN}:#{id}" }
      assert_equal expected, refs.map(&:id)
      assert(refs.all? { |ref| ref.path == File.expand_path(File.join(FIXTURES, "data", "footnotes.csv")) })
      translations = refs.select { |ref| ref.metadata["kind"] == "translation" }.map(&:id)
      assert_equal %w[1071-heb 4737-en 16766-en 36492-en].map { |id| "#{URN}:#{id}" }, translations
    end

    def test_discover_yields_nothing_before_a_first_fetch
      Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
    end

    def test_rejected_grains_are_skipped_by_rule_and_counted
      skips = adapter.discovery_skips(FIXTURES)
      assert_equal 5, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
      notes = skips.notes.join("\n")
      assert_match(/1 metadata-only document/, notes) # PGPID 30423: no text at all
      assert_match(/2 text footnotes .*no digital layer/, notes) # PGPID 723's two relation-less rows
      assert_match(/1 text footnote .*absent from documents\.csv/, notes) # PGPID 3513
      assert_match(/1 text footnote .*no document_id/, notes) # the orphaned Goitein edition
    end

    def test_a_metadata_only_document_mints_no_ref
      refute(refs.any? { |ref| ref.id.include?("30423") })
    end

    # --- the edition document ------------------------------------------------------------

    def test_a_judaeo_arabic_letter_parses_line_passages_keyed_by_its_edition
      doc = document("4737")
      assert_equal "jrb", doc.language
      assert_equal "T-S Ar.7.18 (PGPID 4737)", doc.title
      assert_equal 9, doc.size
      first = doc.passages.first
      assert_equal "#{URN}:4737:#{INDIA_BOOK}.1", first.urn
      assert_equal "סיידי אלשיך אלאגֹל אטאל אללה בקאה אלדי אעלמךֹ", first.text
      assert_equal INDIA_BOOK, first.annotations["source_slug"]
      refute first.annotations.key?("side")
    end

    def test_side_labels_become_annotations_never_passages
      doc = document("4737")
      address = doc.passages[6]
      assert_equal "אלי אלשיך אלחזן", address.text
      assert_equal "Verso, address:", address.annotations["side"]
      refute(doc.passages.any? { |passage| passage.text.start_with?("Verso") })
    end

    def test_a_label_run_without_text_between_rides_whole
      doc = document("8742")
      assert_equal 20, doc.size
      assert_equal "Recto, right · Recto, left · Verso, right (fol. 2b) · Verso, left (fol. 1a)",
                   doc.passages.first.annotations["side"]
    end

    def test_a_line_folding_to_nothing_rides_a_passage_as_a_mark
      doc = document("8339")
      assert_equal "ara", doc.language, "Arabic is the first primary tag; the numeral system names no language"
      assert_equal 125, doc.size
      sides = doc.passages.map { |passage| passage.annotations["side"] }.compact.uniq
      assert_equal ["First column", "Second column", "Third column", "Fourth column"], sides
      assert_equal "ابو] سعيد الحابر", doc.passages[11].text
      # a bare tatweel run folds to nothing: kept as the next line's mark, never a passage, never dropped
      last = doc.passages.last
      assert_equal "𐋬𐋤", last.text, "the Coptic epact numerals themselves stay searchable lines"
      assert_equal ["ـــ"], last.annotations["marks"]
      assert_equal [1235, 1236], doc.metadata["date"].values_at("not_before", "not_after")
    end

    def test_two_editions_ride_one_document_in_slug_order
      doc = document("16766")
      assert_equal "ara", doc.language
      assert_equal 26, doc.size
      editions = doc.passages.map { |passage| passage.annotations["source_slug"] }.uniq
      assert_equal %w[bondioli-lorenzo-luescher-stephanie-rustow-marina-vanthieghem-naim-unpublished
                      khan-geoffrey-arabic-legal-and-administrative-documents-1993], editions
      assert_equal "Verso", doc.passages.first.annotations["side"]
      assert_equal "ذو القعدة", doc.passages.first.text
    end

    def test_aramaic_text_is_stored_byte_verbatim_under_the_nfc_exemption
      doc = document("28363")
      assert_equal "arc", doc.language
      assert_equal 25, doc.size
      # the closing line is a lone no-break space — blank, never a passage
      raw = raw_content("28363", "dudley-matthew-digital-editions-2024")
      lines = raw.split("\n").map { |line| line.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "") }
      assert_equal lines.reject(&:empty?), doc.passages.map(&:text)
    end

    def test_the_document_metadata_mines_every_axis_field
      meta = document("4737").metadata
      assert_equal "4737", meta["pgpid"]
      assert_equal "T-S Ar.7.18", meta["shelfmark"]
      assert_equal "https://geniza.princeton.edu/documents/4737/", meta["url"]
      assert_equal "Letter", meta["document_type"]
      assert_equal ["IB3", "trade", "Ibn Yiju", "India Book"], meta["tags"]
      assert_equal ["jrb"], meta["languages"]
      assert_equal ["Judaeo-Arabic"], meta["languages_primary"]
      assert_equal({ "ancient" => "Messina", "geo" => "38.19361, 15.55417" }, meta["place"])
      assert_equal "Mazara", meta["destination"]
      assert_equal ["CUL"], meta["library"]
      assert_equal ["CUL, T-S"], meta["collection"]
      assert_equal ["Geniza"], meta["provenance"]
      assert_match(/\ANote from a certain Ḥajjāj|IB III, 44/, meta["description"])
      refute_includes meta["description"], "\r"
      assert_equal([INDIA_BOOK], meta["editions"].map { |e| e["slug"] })
    end

    def test_an_inferred_date_is_its_own_labeled_envelope
      date = document("4737").metadata["date"]
      assert_equal 1154, date["not_before"]
      assert_equal 1154, date["not_after"]
      assert_equal "inferred", date["basis"]
      assert_equal "1154-10/1154-11", date["standard"]
      assert_match(/October-November 1154/, date["raw"])
      span = document("28363").metadata["date"]
      assert_equal [1790, 1840], [span["not_before"], span["not_after"]]
    end

    def test_a_document_date_carries_its_original_calendar_reading
      meta = document("8742").metadata
      date = meta["date"]
      assert_equal [1190, 1190], [date["not_before"], date["not_after"]]
      assert_equal "document", date["basis"]
      assert_equal "13 Kislev 1502", date["original"]
      assert_equal "Seleucid", date["calendar"]
      assert_equal "13 Kislev 1502 (Seleucid) = 1190-11-13", date["raw"]
      assert_equal ["Paper"], meta["material"]
    end

    def test_mentioned_places_ride_verbatim
      assert_equal ["Madīnat al-Fayyūm"], document("16766").metadata["mentioned"]
      assert_equal ["al-Maḥalla"], document("1071").metadata["location"]
    end

    # --- translation siblings ---------------------------------------------------------------

    def test_an_english_translation_is_its_own_sibling_document
      doc = document("4737-en")
      assert_equal "en", doc.language
      assert_equal "T-S Ar.7.18 (PGPID 4737) — English translation", doc.title
      assert_equal "translation", doc.metadata["kind"]
      assert_equal "#{URN}:4737", doc.metadata["translation_of"]
      assert_equal 10, doc.size
      first = doc.passages.first
      assert_equal "#{URN}:4737-en:#{INDIA_TRADERS}.t1", first.urn
      assert_equal "recto", first.annotations["side"]
      assert_match(/\AMy lord, the most illustrious Sheikh/, first.text)
      refute doc.metadata.key?("date"), "the edition document carries the axes"
      refute doc.metadata.key?("place")
    end

    def test_a_hebrew_script_translation_mints_the_heb_sibling
      doc = document("1071-heb")
      assert_equal "heb", doc.language
      assert_match(/Hebrew translation\z/, doc.title)
      assert_equal "התקנה אשר כתבו אנשי אלמחלה, חלק מהם, במה שנוגע בר' פרחיה בן", doc.passages.first.text
    end

    def test_a_translation_only_document_carries_the_axes_itself
      doc = document("36492-en")
      meta = doc.metadata
      assert_equal "translation", meta["kind"]
      assert_equal [1098, 1098], [meta["date"]["not_before"], meta["date"]["not_after"]]
      assert_equal({ "ancient" => "Fustat", "geo" => "30.00472, 31.2375" }, meta["place"])
      assert_equal "Legal document", meta["document_type"]
      assert_equal 2, doc.size
    end

    def test_a_stale_ref_is_a_parse_error
      stale = Nabu::DocumentRef.new(source_id: "pgp-geniza", id: "#{URN}:30423",
                                    path: File.expand_path(File.join(FIXTURES, "data", "footnotes.csv")),
                                    metadata: { "pgpid" => "30423" })
      assert_raises(Nabu::ParseError) { adapter.parse(stale) }
    end

    # --- load + fetch + registry ------------------------------------------------------------

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "pgp-geniza", name: "PGP", adapter_class: KLASS.name,
                                          license_class: "nc")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(KLASS.new, workdir: FIXTURES)
      assert_equal 11, first.added
      passages = db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(KLASS.new, workdir: FIXTURES)
      assert_equal 11, second.skipped
      assert_equal passages, db[:passages].count
    ensure
      db&.disconnect
    end

    def test_fetch_is_the_sanctioned_git_fetch_of_the_repository
      captured = nil
      subject = KLASS.new
      subject.define_singleton_method(:git_fetch!) { |**kw| captured = kw }
      subject.fetch("/tmp/nowhere")
      assert_equal "https://github.com/princetongenizalab/pgp-metadata", captured[:repo_url]
    end

    def test_registry_row_is_unwired_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["pgp-geniza"]
      refute_nil entry, "pgp-geniza must be registered in config/sources.yml"
      assert_equal KLASS, entry.adapter_class
      refute entry.wired, "wired flips at the verified first sync"
      assert_equal "manual", entry.sync_policy
    end
  end
end
