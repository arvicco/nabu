# frozen_string_literal: true

require "digest"
require "json"

require_relative "../version"
require_relative "builder"
require_relative "feature"

module Nabu
  module DataBuild
    # datapackage.json — a Frictionless Data Package v2 manifest plus the
    # namespaced "nabu" extension block (producer, derivation shas + recipe +
    # fingerprint, anchoring, tier, counts). Pure: everything arrives as
    # data (the Runner resolves shas and assembles sources), the output is
    # pretty stdlib JSON in a committed key order, so identical inputs are
    # byte-identical — the golden-file test pins this.
    class Manifest
      SCHEMA_URL = "https://datapackage.org/profiles/2.0/datapackage.json"

      # The dataset-level defaults for the rail. Versioning of individual
      # dataset releases is a later (release-rail) concern; 1.0.0 marks the
      # manifest shape, not a curated release history.
      DATASET_VERSION = "1.0.0"
      CONTRIBUTORS = [{ "title" => "Ar Vicco", "role" => "author" }].freeze

      # The creativecommons.org URL per allowed dataset license (the closed
      # set DataBuild::LICENSES pins — owner ruling D51-a). The manifest's
      # licenses[] entry comes FROM the feature; each dataset's manifest is
      # authoritative over the repo-default CC BY.
      LICENSE_URLS = {
        "CC-BY-4.0" => "https://creativecommons.org/licenses/by/4.0/",
        "CC-BY-SA-4.0" => "https://creativecommons.org/licenses/by-sa/4.0/"
      }.freeze

      # The DerivationFingerprint token discipline: unit-separator-joined
      # tokens, one digest, changes iff any token changes.
      SEPARATOR = "\x1f"

      # One upstream input as the manifest's sources[] entry describes it:
      # title/path from the source's manifest, version = the canonical
      # cone's sha at derivation, licenses as [{ "name" => ... }].
      SourceRef = Data.define(:title, :path, :version, :licenses) do
        def initialize(title:, path: nil, version: nil, licenses: [])
          super
        end
      end

      class << self
        # The derivation fingerprint: sorted "cone:sha" tokens plus the
        # recipe string, digested. Changes iff an input's canonical bytes
        # or the derivation recipe change — the same iff DerivationFingerprint
        # promises for rebuild skipping, scoped to this dataset's inputs.
        def fingerprint(input_shas:, recipe:)
          tokens = input_shas.sort.map { |cone, sha| "#{cone}:#{sha}" }
          Digest::SHA256.hexdigest((tokens + [recipe.to_s]).join(SEPARATOR))
        end

        # Render the manifest for +feature+. +resources+ are Resource values
        # in manifest order, +input_shas+ is { cone => sha }, +sources+ is
        # SourceRef values (one per input source), +evaluation+ an optional
        # in-band eval hash (published as nabu.eval). Returns the JSON string
        # (pretty, trailing newline).
        def generate(feature:, resources:, input_shas:, recipe:, sources: [], evaluation: nil,
                     nabu_version: Nabu::VERSION)
          document = {
            "$schema" => SCHEMA_URL,
            "name" => feature.package_name,
            "title" => feature.title,
            "version" => DATASET_VERSION,
            "licenses" => [{ "name" => feature.license, "path" => LICENSE_URLS.fetch(feature.license) }],
            "contributors" => CONTRIBUTORS,
            "sources" => sources.map { |source| source_entry(source) },
            "resources" => resources.map { |resource| resource_entry(resource) },
            "nabu" => nabu_block(feature: feature, resources: resources, input_shas: input_shas,
                                 recipe: recipe, evaluation: evaluation, nabu_version: nabu_version)
          }
          "#{JSON.pretty_generate(document)}\n"
        end

        private

        def source_entry(source)
          entry = { "title" => source.title }
          entry["path"] = source.path if source.path
          entry["version"] = source.version if source.version
          entry["licenses"] = source.licenses unless source.licenses.empty?
          entry
        end

        # Tabular resources carry a schema (fields + primaryKey); non-tabular
        # ones are legal Frictionless resources with format/mediatype only.
        def resource_entry(resource)
          entry = { "name" => resource.name, "path" => resource.path }
          entry["format"] = resource.format if resource.format
          entry["mediatype"] = resource.mediatype if resource.mediatype
          if resource.tabular?
            schema = { "fields" => resource.fields.map { |field| { "name" => field[:name], "type" => field[:type] } } }
            schema["primaryKey"] = resource.primary_key if resource.primary_key
            entry["schema"] = schema
          end
          entry
        end

        def nabu_block(feature:, resources:, input_shas:, recipe:, nabu_version:, evaluation: nil)
          block = {
            "producer" => "nabu data build #{feature.slug}",
            "nabu_version" => nabu_version,
            "derivation" => {
              "inputs" => input_shas.sort.to_h { |cone, sha| [cone, { "canonical_sha" => sha, "cone" => cone }] },
              "recipe" => recipe,
              "fingerprint" => fingerprint(input_shas: input_shas, recipe: recipe)
            },
            "anchoring" => { "kind" => feature.anchoring },
            "tier" => feature.tier,
            "counts" => { "rows" => resources.sum { |resource| resource.rows.to_i } }
          }
          block["eval"] = evaluation if evaluation
          block
        end
      end
    end
  end
end
