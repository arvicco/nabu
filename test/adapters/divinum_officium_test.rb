# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# DivinumOfficium adapter tests: the Tridentine Latin Office and Mass from
# github.com/DivinumOfficium/divinum-officium on the divinum-officium-txt
# family. Fixture: real upstream files laid out in upstream's own tree —
# nine accepted Latin files (Office and Mass propers, a Monastic overlay
# with conditionals, a Passau and a Brazilian proper, a common inheriting
# a whole file, a psalm, a necrology month and the Mass ordinary — the
# last two trimmed), two inclusion stubs and the empty extensionless
# stray (skipped by rule), and one specimen of every rejected tree
# (English translation, gabc chant, the Bea psalter, the hour templates,
# the credits page, a top-level site file) plus the repo LICENSE.
class DivinumOfficiumTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("divinum-officium")
  PREFIX = "urn:nabu:divinum-officium:"
  AGNES = "#{PREFIX}horas/Sancti/01-21".freeze
  MASS_AGNES = "#{PREFIX}missa/Sancti/01-21".freeze
  FLORIAN = "#{PREFIX}horas/Sancti/Bavaria/Passaviensis/05-04-Florianus".freeze
  PSALM1 = "#{PREFIX}horas/Psalterium/Psalmorum/Psalm1".freeze

  def conformance_adapter = Nabu::Adapters::DivinumOfficium.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "divinum-officium"

  def adapter = Nabu::Adapters::DivinumOfficium.new

  def document(urn)
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn } || flunk("discover must yield #{urn}")
    adapter.parse(ref)
  end

  # --- manifest + identity ------------------------------------------------------

  def test_manifest_records_the_public_domain_statement_verbatim
    manifest = adapter.manifest
    assert_equal "open", manifest.license_class
    assert_includes manifest.license, "All liturgical texts within this site are, to the best of our " \
                                      "knowledge, from the public domain."
    assert_includes manifest.license, "MIT License"
    assert_equal "divinum-officium-txt", manifest.parser_family
    assert_equal "https://github.com/DivinumOfficium/divinum-officium", manifest.upstream_url
  end

  def test_the_fixture_carries_the_license_evidence_first_hand
    credits = File.read(File.join(FIXTURES, "web/www/horas/Help/credits.html"))
    assert_includes credits, "All liturgical texts within this site are, to the best of our knowledge, " \
                             "from the public domain."
    assert_includes credits, "apparently copyrighted", "the vernacular credits' own caveat (the LATIN ONLY rule)"
    assert File.read(File.join(FIXTURES, "LICENSE")).start_with?("MIT License")
  end

  def test_discover_yields_one_document_per_latin_file_with_own_text
    expected = %W[
      #{PREFIX}horas/Commune/C10a #{PREFIX}horas/Necrologium/Januarius #{PSALM1} #{AGNES}
      #{FLORIAN} #{PREFIX}horas/Sancti/Brasilia/06-13 #{PREFIX}horas/SanctiM/09-17M
      #{PREFIX}missa/Ordo/Ordo #{MASS_AGNES}
    ]
    assert_equal expected, adapter.discover(FIXTURES).map(&:id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a, "the pre-fetch state yields nothing" }
  end

  def test_passage_censuses
    counts = adapter.discover(FIXTURES).to_h { |ref| [ref.id.delete_prefix(PREFIX), adapter.parse(ref).size] }
    assert_equal({ "horas/Commune/C10a" => 6, "horas/Necrologium/Januarius" => 2,
                   "horas/Psalterium/Psalmorum/Psalm1" => 7, "horas/Sancti/01-21" => 21,
                   "horas/Sancti/Bavaria/Passaviensis/05-04-Florianus" => 5, "horas/Sancti/Brasilia/06-13" => 2,
                   "horas/SanctiM/09-17M" => 3, "missa/Ordo/Ordo" => 2, "missa/Sancti/01-21" => 4 }, counts)
  end

  def test_passage_urns_and_a_known_text
    agnes = document(AGNES)
    assert_equal "#{AGNES}:Officium", agnes.first.urn
    oratio = agnes.find { |p| p.urn == "#{AGNES}:Oratio" }
    assert oratio.text.start_with?("Omnípotens sempitérne Deus, qui infírma mundi éligis, ut fórtia quæque confúndas")
    assert_equal "#{PSALM1}:1.1", document(PSALM1).first.urn
    assert_equal "Beátus vir, qui non ábiit in consílio impiórum, † et in via peccatórum non stetit, * et in " \
                 "cáthedra pestiléntiæ non sedit:", document(PSALM1).first.text
    assert_equal "horas/Psalterium/Psalmorum/Psalm1", document(PSALM1).title, "a title-less file names itself"
  end

  def test_the_office_and_the_mass_of_one_feast_are_two_documents
    mass = document(MASS_AGNES)
    assert_equal "S. Agnetis Virginis et Martyris", mass.title
    assert_equal "missa", mass.metadata["book"]
    graduale = mass.find { |p| p.urn == "#{MASS_AGNES}:Graduale" }
    assert_equal ["Ps 44:3", "Ps 44:5", "Matt 25:4 25:6"], graduale.annotations["rubrics"]
    assert_equal "@Commune/C6-1", mass.metadata["reference_sections"]["Introitus"].first,
                 "the Introit is a reference to the common — preserved, never resolved"
  end

  # --- the mined axes --------------------------------------------------------------

  def test_path_metadata_mines_book_part_use_and_the_local_calendar_place
    florian = document(FLORIAN).metadata
    assert_equal({ "book" => "horas", "book_part" => "Sancti", "use" => "Roman",
                   "subcollection" => "Bavaria/Passaviensis", "local_calendar" => "Bavaria/Passaviensis",
                   "place" => "Passau", "day" => "05-04-Florianus",
                   "file" => "web/www/horas/Latin/Sancti/Bavaria/Passaviensis/05-04-Florianus.txt" },
                 florian.slice("book", "book_part", "use", "subcollection", "local_calendar", "place", "day", "file"))
    assert_equal "Brazil", document("#{PREFIX}horas/Sancti/Brasilia/06-13").metadata["place"]
    hildegard = document("#{PREFIX}horas/SanctiM/09-17M").metadata
    assert_equal "Monastic", hildegard["use"]
    assert_equal "Sancti", hildegard["book_part"], "the use suffix strips off the book part"
    refute hildegard.key?("place")
  end

  def test_path_metadata_rules
    meta = Nabu::Adapters::DivinumOfficium.method(:path_metadata)
    assert_equal "Cistercian", meta.call("horas", "TemporaCist/Adv1-0.txt")["use"]
    assert_equal "Dominican", meta.call("horas", "CommuneOP/C1.txt")["use"]
    assert_equal "Roman", meta.call("missa", "Tempora/Adv1-0.txt")["use"]
    assert_nil meta.call("horas", "Martyrologium/01-02.txt")["use"], "no use claim outside the propers"
    assert_nil meta.call("missa", "Ordo/OrdoOP.txt")["use"], "the ordinaries' uses are not guessed from names"
    assert_equal "Psalmorum", meta.call("horas", "Psalterium/Psalmorum/Psalm1.txt")["book_part"]
    assert_equal "Psalterium", meta.call("horas", "Psalterium/Invitatorium.txt")["book_part"]
    assert_equal "Rome", meta.call("horas", "Sancti/Urbis/01-10.txt")["place"]
    assert_equal "Utrecht", meta.call("horas", "Sancti/Neerlandia/Ultrajectum/11-07.txt")["place"],
                 "the deepest named jurisdiction wins"
    locis = meta.call("horas", "Sancti/aliquibus locis/09-04-RosaV.txt")
    assert_equal "aliquibus locis", locis["local_calendar"]
    assert_nil locis["place"], "'in some places' names no place"
    votive = meta.call("horas", "Commune/Votiva/C1.txt")
    assert_equal "Votiva", votive["subcollection"]
    assert_nil votive["local_calendar"], "the votive offices are not a calendar"
    assert_nil meta.call("horas", "Psalterium/Special/Prima Special.txt")["local_calendar"]
  end

  def test_layouts_follow_the_tree
    layout = Nabu::Adapters::DivinumOfficium.method(:layout_for)
    assert_equal :verses, layout.call("Psalterium/Psalmorum/Psalm1.txt")
    assert_equal :necrology, layout.call("Necrologium/Januarius.txt")
    assert_equal :sections, layout.call("Psalterium/Invitatorium.txt")
    assert_equal [1531, 1746, 1760, 1764, 1789, 1793, 1808, 1816, 1887, 1947, 1948],
                 document("#{PREFIX}horas/Necrologium/Januarius").first.annotations["entry_years"]
  end

  def test_the_book_part_folds_onto_the_kind_axis
    root = File.expand_path("../../config", __dir__)
    kinds = Nabu::Kinds.load(classes_path: File.join(root, "kind_classes.yml"),
                             map_path: File.join(root, "kind_map.yml"))
    assert_equal ["book_part"], kinds.metadata_for("divinum-officium")
    assert_equal ["ritual/liturgy"], kinds.normalize("divinum-officium", "Sancti")
    assert_equal %w[hagiography ritual/liturgy], kinds.normalize("divinum-officium", "Martyrologium").sort,
                 "a liturgical book whose content is saints' notices (both claims since 2026-11-07)"
    assert_equal ["scripture"], kinds.normalize("divinum-officium", "Psalmorum")
    assert_equal ["legal/law"], kinds.normalize("divinum-officium", "Regula")
    assert_equal ["administrative/list"], kinds.normalize("divinum-officium", "Necrologium"),
                 "the necrology is in form a dated obituary register — the content " \
                 "classifies, not the chapter use (folded 2026-11-04)"
    assert_equal "Sancti", document(AGNES).metadata["book_part"]
  end

  def test_the_place_rides_the_place_only_timeline_lane
    assert_equal :place_only, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["divinum-officium"]
  end

  # --- discovery census: stubs, the stray, and every rejected tree ----------------

  def test_rejected_trees_stubs_and_the_stray_skip_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 9, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    notes = skips.notes.join("\n")
    assert_match(%r{horas/English/Sancti/01-21\.txt: a vernacular translation tree — LATIN ONLY}, notes)
    assert_match(%r{horas/Latin-gabc/Sancti/01-21\.txt: the Gregorian chant scores}, notes)
    assert_match(%r{horas/Latin-Bea/Psalterium/Psalmorum/Psalm123\.txt: the Pius XII \(Bea, 1945\) psalter}, notes)
    assert_match(%r{horas/Ordinarium/Prima\.txt: the hour-assembly templates}, notes)
    assert_match(%r{horas/Help/credits\.html: the site's help and credits pages}, notes)
    assert_match(%r{missa/Linguae\.txt: a top-level site file}, notes)
    assert_match(%r{horas/Latin/CommuneCist/C10c\.txt: an inclusion stub}, notes)
    assert_match(%r{horas/Latin/SanctiM/08-18bmv\.txt: an inclusion stub}, notes)
    assert_match(%r{aliquibus locis/09-04-BMVDivPastMatr: not a \.txt data file}, notes)
  end

  def test_an_unnamed_tree_is_unrecognized_never_silently_dropped
    Dir.mktmpdir do |work|
      FileUtils.cp_r(File.join(FIXTURES, "web"), work)
      FileUtils.mkdir_p(File.join(work, "web/www/horas/Latin-Newer/Sancti"))
      FileUtils.cp(File.join(FIXTURES, "web/www/horas/Latin/Sancti/01-21.txt"),
                   File.join(work, "web/www/horas/Latin-Newer/Sancti/01-21.txt"))
      skips = adapter.discovery_skips(work)
      assert_equal 1, skips.unrecognized
      assert_match(%r{Latin-Newer/Sancti/01-21\.txt: a tree no rule names}, skips.notes.join("\n"))
      assert_equal 9, adapter.discover(work).count, "the unnamed tree is never discovered"
    end
  end

  # --- store: idempotent double-load ------------------------------------------------

  def test_loads_idempotently_into_the_store
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: "divinum-officium", name: "Divinum Officium",
                                        adapter_class: "Nabu::Adapters::DivinumOfficium", license_class: "open")
    first = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 9, first.added
    assert_equal 0, first.errored
    assert_equal 52, catalog[:passages].count
    second = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 0, second.errored
    assert_equal 9, second.skipped, "a byte-identical reload skips every document"
    assert_equal 52, catalog[:passages].count
    assert_equal [1], catalog[:passages].distinct.select_map(:revision)
  end

  # --- registry + fetch --------------------------------------------------------

  def test_registry_resolves_divinum_officium
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["divinum-officium"]
    refute_nil entry, "divinum-officium must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::DivinumOfficium, entry.adapter_class
    assert_equal Nabu::Adapters::DivinumOfficium.manifest, entry.manifest
    assert_equal "manual", entry.sync_policy
  end

  def test_fetch_clones_the_latin_cone_and_the_tree_is_discoverable
    Dir.mktmpdir("nabu-divinum-officium-fetch") do |root|
      upstream = File.join(root, "upstream")
      FileUtils.mkdir_p(upstream)
      %w[web LICENSE].each { |entry| FileUtils.cp_r(File.join(FIXTURES, entry), upstream) }
      Nabu::Shell.run("git", "init", "-q", upstream)
      git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
      git.call("add", ".")
      git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")

      officium = adapter
      officium.define_singleton_method(:repo_url) { upstream }
      workdir = File.join(root, "canonical")
      report = officium.fetch(workdir)
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert_equal 9, officium.discover(workdir).count
      %w[English Latin-gabc Latin-Bea Ordinarium].each do |tree|
        refute File.exist?(File.join(workdir, "web/www/horas", tree)), "#{tree} stays outside the Latin cone"
      end
      refute File.exist?(File.join(workdir, "web/www/missa/Linguae.txt"))
      assert File.file?(File.join(workdir, "web/www/horas/Help/credits.html")), "the license evidence rides the cone"
      assert File.file?(File.join(workdir, "LICENSE"))
      skips = officium.discovery_skips(workdir)
      assert_equal 4, skips.skipped_by_rule, "live: the stubs + the stray + credits.html"
    end
  end
end
