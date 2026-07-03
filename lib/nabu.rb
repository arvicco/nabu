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
require_relative "nabu/adapter"
require_relative "nabu/store"
require_relative "nabu/config"
require_relative "nabu/cli"

# Nabu: personal research infrastructure for ingesting ancient-text corpora
# into a local SQLite-backed store. See docs/architecture.md.
module Nabu
end
