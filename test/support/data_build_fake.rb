# frozen_string_literal: true

# The nabu-data rail's test rig (P50-W1): ONE fake feature + builder pair so
# the `nabu data build` happy path is fully exercised while every REAL
# feature is still :planned. Fixture-scale and deterministic by design —
# two hand-written rows, no catalog reads, a pinned recipe string.
class FakeFormsBuilder
  COLUMNS = %w[ID Language_ID Form Headword].freeze
  ROWS = [
    { "ID" => "agnih", "Language_ID" => "san", "Form" => "agniḥ", "Headword" => "agni" },
    { "ID" => "agnina", "Language_ID" => "san", "Form" => "agninā", "Headword" => "agni" }
  ].freeze
  RECIPE = "fake-forms v1: two hand-written rows, no catalog reads"

  def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
    Nabu::DataBuild::CsvWriter.write(path: File.join(out_dir, "forms.csv"), columns: COLUMNS, rows: ROWS)
    Nabu::DataBuild::BuildResult.new(
      resources: [DataBuildFake.forms_resource],
      recipe: RECIPE,
      citations: [
        Nabu::DataBuild::Citation.new(
          key: "fake2026", type: "misc",
          fields: { "title" => "A fake upstream, for the rail's own tests", "year" => "2026" }
        )
      ]
    )
  end
end

module DataBuildFake
  def self.forms_resource
    Nabu::DataBuild::Resource.new(
      name: "forms", path: "forms.csv", rows: FakeFormsBuilder::ROWS.size,
      fields: FakeFormsBuilder::COLUMNS.map { |name| { name: name, type: "string" } },
      primary_key: ["ID"]
    )
  end

  # An :available feature wired to the fake builder — what tests splice into
  # the census (singleton-swap on Nabu::DataBuild.features) to drive `build`.
  def self.feature(slug: "san/fake-forms", inputs: [], canonical_cones: [], builder: FakeFormsBuilder,
                   license: Nabu::DataBuild::DEFAULT_LICENSE)
    Nabu::DataBuild::Feature.new(
      slug: slug, language: Nabu::DataBuild::LANGUAGES.fetch("san"),
      title: "Fake Sanskrit forms table (test rig)",
      status: :available, tier: "gold-derived", anchoring: "none", license: license,
      inputs: inputs, canonical_cones: canonical_cones,
      rationale: "Exists only to exercise the build rail end to end in the suite.",
      maintenance: "never — test rig only",
      builder: builder
    )
  end

  # The golden manifest's inputs, shared by the golden-file test and the
  # fixture generator so they can never drift: every value pinned, including
  # nabu_version (the fixture must not change when Nabu::VERSION bumps).
  def self.golden_manifest_args
    {
      feature: feature(inputs: ["dcs"], canonical_cones: ["dcs"]),
      resources: [
        forms_resource,
        Nabu::DataBuild::LanguagesTable.resource(count: 1),
        Nabu::DataBuild::SourcesBib.resource
      ],
      input_shas: { "dcs" => "1111222233334444555566667777888899990000" },
      recipe: FakeFormsBuilder::RECIPE,
      sources: [
        Nabu::DataBuild::Manifest::SourceRef.new(
          title: "Digital Corpus of Sanskrit (fake pin)",
          path: "https://example.invalid/dcs",
          version: "1111222233334444555566667777888899990000",
          licenses: [{ "name" => "CC-BY-4.0" }]
        )
      ],
      nabu_version: "0.0.0-golden"
    }
  end
end
