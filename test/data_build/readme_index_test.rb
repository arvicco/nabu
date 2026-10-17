# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

# The repository README's dataset table is GENERATED between markers from
# the registry and the built manifests (it had been hand-maintained and
# went stale: eight datasets missing, counts from three releases back —
# owner correction 2026-10-17). The rail refreshes it on every build, so
# a new dataset can never again ship unannounced on the front page.
class DataBuildReadmeIndexTest < Minitest::Test
  INDEX = Nabu::DataBuild::ReadmeIndex

  FakeLanguage = Struct.new(:id, :name, keyword_init: true)
  FakeFeature = Struct.new(:slug, :title, :license, :status, :language, keyword_init: true) do
    def available? = status == :available
    def planned? = status == :planned
  end

  def features
    [
      FakeFeature.new(slug: "aaa/one", title: "The first table", license: "CC-BY-4.0", status: :available),
      FakeFeature.new(slug: "bbb/two", title: "The second table", license: "CC-BY-SA-4.0", status: :available),
      FakeFeature.new(slug: "ccc/planned", title: "Not yet", license: "CC-BY-4.0", status: :planned)
    ]
  end

  def seed(dir, slug, rows:)
    path = File.join(dir, slug)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "datapackage.json"),
               JSON.generate({ "name" => slug.tr("/", "-"), "nabu" => { "counts" => { "rows" => rows } } }))
  end

  def readme_with_markers(dir, body: "stale hand-written table\n")
    File.write(File.join(dir, "README.md"), <<~MD)
      # repo

      intro prose.

      ## Datasets

      <!-- datasets:generated:begin -->
      #{body.chomp}
      <!-- datasets:generated:end -->

      ## Licensing

      tail prose.
    MD
  end

  def test_refresh_splices_a_registry_and_manifest_derived_table_between_the_markers
    Dir.mktmpdir("nabu-readme") do |dir|
      seed(dir, "aaa/one", rows: 1234)
      seed(dir, "bbb/two", rows: 5)
      readme_with_markers(dir)
      summary = INDEX.refresh!(features: features, out_dir: dir,
                               published_dates: { "aaa/one" => "2026-08-01", "bbb/two" => "2026-10-17" })
      text = File.read(File.join(dir, "README.md"))
      refute_includes text, "stale hand-written table"
      assert_includes text, "| `aaa/one` | The first table — 1,234 rows | CC BY 4.0 | 2026-08-01 |"
      assert_includes text, "| `bbb/two` | The second table — 5 rows | CC BY-SA 4.0 | 2026-10-17 |"
      assert_includes text, "| Dataset | Content | License | Published |"
      refute_includes text, "ccc/planned", "a planned feature has nothing published to announce"
      assert_includes text, "intro prose."
      assert_includes text, "tail prose."
      assert_equal 2, summary.listed
      assert_empty summary.missing
    end
  end

  def test_refresh_is_idempotent_and_survives_its_own_output
    Dir.mktmpdir("nabu-readme") do |dir|
      seed(dir, "aaa/one", rows: 1)
      seed(dir, "bbb/two", rows: 2)
      readme_with_markers(dir)
      dates = { "aaa/one" => "2026-08-01", "bbb/two" => "2026-10-17" }
      INDEX.refresh!(features: features, out_dir: dir, published_dates: dates)
      first = File.read(File.join(dir, "README.md"))
      INDEX.refresh!(features: features, out_dir: dir, published_dates: dates)
      assert_equal first, File.read(File.join(dir, "README.md"))
    end
  end

  def test_a_feature_without_a_built_directory_is_censused_not_listed
    Dir.mktmpdir("nabu-readme") do |dir|
      seed(dir, "aaa/one", rows: 7)
      readme_with_markers(dir)
      summary = INDEX.refresh!(features: features, out_dir: dir,
                               published_dates: { "aaa/one" => "2026-08-01" })
      text = File.read(File.join(dir, "README.md"))
      assert_includes text, "`aaa/one`"
      refute_includes text, "`bbb/two`", "never list what is not on disk"
      assert_equal ["bbb/two"], summary.missing
    end
  end

  def test_missing_markers_raise_rather_than_guess_a_splice_point
    Dir.mktmpdir("nabu-readme") do |dir|
      seed(dir, "aaa/one", rows: 7)
      File.write(File.join(dir, "README.md"), "# repo\n\nno markers here\n")
      error = assert_raises(Nabu::Error) do
        INDEX.refresh!(features: features, out_dir: dir, published_dates: {})
      end
      assert_match(/datasets:generated/, error.message)
    end
  end

  def test_published_dates_fall_back_to_git_first_add_then_today
    Dir.mktmpdir("nabu-readme") do |dir|
      seed(dir, "aaa/one", rows: 7)
      seed(dir, "bbb/two", rows: 8)
      Dir.chdir(dir) do
        system("git init -q && git add aaa && git -c user.email=t@t -c user.name=t commit -qm seed " \
               "--date=2026-08-01T12:00:00", exception: true)
      end
      dates = INDEX.published_dates(out_dir: dir, slugs: ["aaa/one", "bbb/two"])
      assert_equal "2026-08-01", dates["aaa/one"], "the first-add commit date is the publication date"
      assert_equal Time.now.strftime("%Y-%m-%d"), dates["bbb/two"], "an uncommitted dataset publishes today"
    end
  end
end
