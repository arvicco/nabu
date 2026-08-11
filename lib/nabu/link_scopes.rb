# frozen_string_literal: true

require "yaml"
require "fileutils"

module Nabu
  # config/link_scopes.yml — the durable record of BATCH-MINED link scopes
  # (P70-3b, the derivability contract). The three parameterized miners
  # (parallels · cognates · formulas) take owner-chosen scopes and params
  # that used to live ONLY in the losable links file's link_runs rows; the
  # batch CLIs now write the scope HERE (write-through, deduped by
  # producer+scope) and `nabu rebuild`'s links stage replays every entry —
  # so db/links.sqlite3 is a pure function of canonical + config + the
  # catalog. Slug-scoped producers (references, etymologies, reuse,
  # translations) need no entry: the registry is their scope record.
  module LinkScopes
    HEADER = <<~YAML
      # config/link_scopes.yml — batch-mined link scopes (P70 derivability
      # contract). Each entry re-runs at `nabu rebuild`'s links stage; the
      # batch CLI commands append here automatically. Slug-scoped producers
      # (kind: reference etc.) derive from the registry and are not listed.
      scopes: []
    YAML

    module_function

    def load(path)
      return [] unless File.file?(path)

      (YAML.safe_load_file(path) || {}).fetch("scopes", nil) || []
    end

    # Record a batch run's scope (replacing a previous entry for the same
    # producer+scope — the latest params govern the replay).
    def record!(path, producer:, scope:, params: {})
      scopes = load(path).reject { |s| s["producer"] == producer && s["scope"] == scope }
      scopes << { "producer" => producer, "scope" => scope, "params" => params }
      FileUtils.mkdir_p(File.dirname(path))
      body = HEADER.sub("scopes: []", YAML.dump("scopes" => scopes).sub(/\A---\n/, ""))
      File.write(path, body)
    end
  end
end
