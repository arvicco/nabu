# frozen_string_literal: true

require_relative "errors"

module Nabu
  # The nabu-data production rail (P50-W1, architecture §17): everything the
  # `nabu data` command family needs to document and build the publishable
  # derived datasets that live — as pure data, CSV + Frictionless Data
  # Package manifests — in the public nabu-data repository. ALL production
  # code stays here in Nabu; the rail writes files into the owner's
  # nabu-data working clone and NEVER runs git operations there.
  #
  # The parts (explicit requires, no autoloading magic):
  #   Feature / REGISTRY   the self-documenting feature census (registry.rb)
  #   CsvWriter            CLDF-nomenclature CSV emission + the ID discipline
  #   Resource/BuildResult the builder contract values (builder.rb)
  #   LanguagesTable       the languages.csv every dataset ships
  #   SourcesBib           sources.bib from structured citations
  #   Manifest             datapackage.json (+ the namespaced nabu block)
  #   Runner               one build: builder → files → manifest → summary
  #
  # The producer-side contract is docs/nabu-data.md (drift-guarded).
  module DataBuild
    # A dataset build cannot proceed honestly (planned feature, missing or
    # dirty canonical input, unregistered input source). The CLI converts
    # this to a clean Thor::Error; nothing partial is ever announced as done.
    class Error < Nabu::Error; end
  end
end

require_relative "data_build/feature"
require_relative "data_build/registry"
require_relative "data_build/csv_writer"
require_relative "data_build/builder"
require_relative "data_build/languages_table"
require_relative "data_build/sources_bib"
require_relative "data_build/manifest"
require_relative "data_build/runner"
