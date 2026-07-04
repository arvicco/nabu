# frozen_string_literal: true

require_relative "nabu/version"
require_relative "nabu/errors"
require_relative "nabu/shell"
require_relative "nabu/normalize"
require_relative "nabu/model/validation"
require_relative "nabu/model/passage"
require_relative "nabu/model/document_ref"
require_relative "nabu/model/source_manifest"
require_relative "nabu/model/document"
require_relative "nabu/model/fetch_report"
require_relative "nabu/progress_reporter"
require_relative "nabu/adapter"
require_relative "nabu/adapters/epidoc_parser"
require_relative "nabu/adapters/perseus"
require_relative "nabu/adapters/first1k_greek"
require_relative "nabu/adapters/conllu_parser"
require_relative "nabu/adapters/universal_dependencies"
require_relative "nabu/adapters/proiel_parser"
require_relative "nabu/adapters/proiel"
require_relative "nabu/adapters/torot"
require_relative "nabu/adapters/ddbdp_parser"
require_relative "nabu/adapters/papyri"
require_relative "nabu/store"
require_relative "nabu/query/search"
require_relative "nabu/config"
require_relative "nabu/source_registry"
require_relative "nabu/status_report"
require_relative "nabu/rebuild"
require_relative "nabu/sync_runner"
require_relative "nabu/cli"

# Nabu: personal research infrastructure for ingesting ancient-text corpora
# into a local SQLite-backed store. See docs/architecture.md.
module Nabu
end
