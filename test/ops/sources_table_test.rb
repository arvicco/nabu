# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Ops
  # The /sources/ corpus table generator: membership is the registry's
  # live-public rule (the one SiteData's sources.yml uses), the per-row
  # prose a hand-curated keyed map the generator reads and never writes.
  class SourcesTableTest < Minitest::Test
    Manifest = Data.define(:name, :license_class, :upstream_url)
    Entry = Struct.new(:slug, :kind, :wired, :blocked, :manifest) do
      def source? = kind == "source"
      def public? = !blocked
    end
    FakeRegistry = Struct.new(:rows) do
      def each_source(&) = rows.each(&)
    end

    def entry(slug, kind: "source", wired: true, blocked: false, name: nil, url: "https://example.org/#{slug}",
              license_class: "open")
      Entry.new(slug, kind, wired, blocked, Manifest.new(name || "#{slug.upcase} corpus", license_class, url))
    end

    def registry
      FakeRegistry.new([
                         entry("zeta"), entry("alpha"), entry("alpha-words"), entry("beta", license_class: "nc"),
                         entry("titus-x", blocked: true), entry("unwired", wired: false),
                         entry("local-notes", kind: "shelf"), entry("pleiades", kind: "module")
                       ])
    end

    def notes
      { "alpha" => { "with" => ["alpha-words"], "upstream" => "[Alpha](https://alpha.example)",
                     "contents" => "1,000 texts (synchronized 1 July 2026)", "license" => "CC BY 4.0" },
        "zeta" => { "upstream" => "[Zeta](https://zeta.example) (Z. Ed.)", "contents" => "Zeta things",
                    "license" => "CC0" } }
    end

    def table(notes: self.notes, registry: self.registry)
      Nabu::Ops::SourcesTable.new(registry: registry, notes: notes)
    end

    def test_noted_rows_render_their_prose_verbatim_with_live_holdings
      lines = table.render.lines
      assert_includes lines, '| <span id="src-zeta"></span>`zeta` | [Zeta](https://zeta.example) (Z. Ed.) | ' \
                             "Zeta things | {{ src[\"zeta\"].holdings }} | CC0 |\n"
    end

    def test_a_grouped_row_carries_every_member_anchor_and_holdings
      row = table.render.lines.grep(/src-alpha"/).first
      assert_equal '| <span id="src-alpha"></span><span id="src-alpha-words"></span>`alpha`, `alpha-words` | ' \
                   "[Alpha](https://alpha.example) | 1,000 texts (synchronized 1 July 2026) | " \
                   "{{ src[\"alpha\"].holdings }} · {{ src[\"alpha-words\"].holdings }} | CC BY 4.0 |\n", row
      assert_equal 1, table.render.scan('id="src-alpha-words"').size, "a grouped member never gets its own row"
    end

    def test_a_prose_less_live_source_renders_an_honest_pending_row
      row = table.render.lines.grep(/src-beta"/).first
      assert_equal '| <span id="src-beta"></span>`beta` | [BETA corpus](https://example.org/beta) | ' \
                   "*Description pending.* | {{ src[\"beta\"].holdings }} | `nc` |\n", row
      assert_equal ["beta"], table.pending, "folded group members are covered by their row's prose"
    end

    def test_membership_is_exactly_the_live_public_sources_in_slug_order
      anchors = table.render.scan(/id="src-([^"]+)"/).flatten
      assert_equal %w[alpha alpha-words beta zeta], anchors
      assert_equal %w[alpha alpha-words beta zeta], table.slugs
    end

    def test_blocked_unwired_shelves_and_modules_never_render
      out = table.render
      %w[titus-x unwired local-notes pleiades].each { |slug| refute_includes out, "src-#{slug}\"" }
    end

    def test_prose_for_a_blocked_source_is_never_published_and_is_reported_orphaned
      noted = notes.merge("titus-x" => { "upstream" => "[T](https://t.example)", "contents" => "secret",
                                         "license" => "grant" })
      refute_includes table(notes: noted).render, "secret"
      assert_equal ["titus-x"], table(notes: noted).orphans
      assert_empty table.orphans
    end

    def test_a_blocked_group_member_drops_out_of_its_row_and_is_orphaned
      noted = notes.merge("zeta" => notes["zeta"].merge("with" => ["titus-x"]))
      row = table(notes: noted).render.lines.grep(/src-zeta"/).first
      refute_includes row, "titus-x"
      assert_equal ["titus-x"], table(notes: noted).orphans
    end

    def test_a_slug_noted_twice_is_an_error
      noted = notes.merge("alpha-words" => { "upstream" => "u", "contents" => "c", "license" => "l" })
      error = assert_raises(Nabu::Error) { table(notes: noted).render }
      assert_includes error.message, "alpha-words"
    end

    def test_a_note_missing_a_cell_is_an_error
      noted = notes.merge("beta" => { "upstream" => "[B](https://b.example)", "license" => "CC0" })
      error = assert_raises(Nabu::Error) { table(notes: noted).render }
      assert_includes error.message, "beta"
      assert_includes error.message, "contents"
    end

    def test_pending_cells_escape_markdown_table_and_link_syntax
      odd = FakeRegistry.new([entry("odd", name: "A | B [draft]")])
      row = table(notes: {}, registry: odd).render.lines.grep(/src-odd"/).first
      assert_includes row, '[A \| B \[draft\]](https://example.org/odd)'
    end

    def test_a_pending_source_without_an_upstream_url_names_itself_unlinked
      bare = FakeRegistry.new([entry("bare", url: nil, name: "Bare corpus")])
      row = table(notes: {}, registry: bare).render.lines.grep(/src-bare"/).first
      assert_includes row, "| Bare corpus | *Description pending.* |"
    end

    def test_the_rendered_include_is_marked_generated_and_binds_the_sources_data
      out = table.render
      assert_match(/\A\{% comment %\}GENERATED by `rake site:sources`/, out)
      assert_includes out, "{% assign src = site.data.sources.sources -%}"
      assert_includes out, "#{Nabu::Ops::SourcesTable::HEADER}\n|---|---|---|---|---|\n"
    end

    def test_write_reads_the_notes_file_and_writes_the_include
      Dir.mktmpdir do |dir|
        notes_path = File.join(dir, "_data", "source_notes.yml")
        FileUtils.mkdir_p(File.dirname(notes_path))
        File.write(notes_path, "# hand-curated\n#{notes.to_yaml}")
        path = Nabu::Ops::SourcesTable.load(registry: registry, site_dir: dir).write!
        assert_equal File.join(dir, "_includes", "sources_table.md"), path
        assert_equal table.render, File.read(path)
      end
    end
  end
end
