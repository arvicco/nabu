# frozen_string_literal: true

require "test_helper"

# The docs/manual convention guard (P84-6, owner ruling 2026-08-27): every
# manual-acquisition source carries a human-targeted, REPLAYABLE acquisition
# instructions document under docs/manual/, and the in-code ManualDrop
# instruction card must AGREE with its doc — same upstream URL, same steps
# verbatim, same expected files, the exact incoming/<slug>/ drop path. This
# test pins that agreement (and the README's index) so neither side can
# silently rot: a Spec edit without a doc update is red, a doc without a
# README index line is red.
class ManualAcquisitionDocsTest < Minitest::Test
  ROOT = Nabu::Config::PROJECT_ROOT
  MANUAL_DIR = File.join(ROOT, "docs", "manual")

  def registry
    @registry ||= Nabu::SourceRegistry.load(File.join(ROOT, "config", "sources.yml"))
  end

  # Every registered source whose adapter declares a ManualDrop Spec.
  def manual_drop_entries
    registry.each_source.select { |entry| entry.adapter_class.respond_to?(:manual_acquisition) }
  end

  # The docs are prose (wrapped lines); the cards are code strings. Agreement
  # is checked whitespace-squeezed on both sides, never layout-sensitive.
  def squeeze(text)
    text.gsub(/\s+/, " ")
  end

  def test_the_registry_still_carries_manual_drop_sources
    assert_includes manual_drop_entries.map(&:slug), "trismegistos-geo",
                    "trismegistos-geo (the first Manual Adapter, ruling Dp-a) must declare " \
                    "a ManualDrop Spec — if the pattern moved, move this guard with it"
  end

  def test_every_manual_drop_spec_has_an_agreeing_doc
    manual_drop_entries.each do |entry|
      spec = entry.adapter_class.manual_acquisition
      path = File.join(MANUAL_DIR, "#{entry.slug}.md")

      assert File.file?(path),
             "docs/manual/#{entry.slug}.md is missing — every ManualDrop source ships its " \
             "human acquisition doc WITH the adapter (P84-6 convention)"

      doc = squeeze(File.read(path))
      assert_includes doc, spec.upstream_url,
                      "#{entry.slug}: the doc must name the Spec's upstream URL (#{spec.upstream_url})"
      spec.steps.each do |step|
        assert_includes doc, squeeze(step),
                        "#{entry.slug}: the doc must carry the instruction card's step verbatim: #{step.inspect}"
      end
      spec.files.each do |file|
        assert_includes doc, file.name,
                        "#{entry.slug}: the doc must name the expected drop file #{file.name}"
      end
      assert_includes doc, "incoming/#{spec.slug}/",
                      "#{entry.slug}: the doc must state the incoming/#{spec.slug}/ drop path"
    end
  end

  def test_the_readme_states_the_convention_and_indexes_every_doc
    readme = File.join(MANUAL_DIR, "README.md")
    assert File.file?(readme), "docs/manual/README.md is missing — the convention statement lives there"

    text = File.read(readme)
    docs = Dir[File.join(MANUAL_DIR, "*.md")] - [readme]
    refute_empty docs, "docs/manual/ must carry at least one per-source acquisition doc"
    docs.each do |doc|
      assert_includes text, File.basename(doc),
                      "docs/manual/README.md must index #{File.basename(doc)} — every doc is findable " \
                      "from the README"
    end
  end
end
