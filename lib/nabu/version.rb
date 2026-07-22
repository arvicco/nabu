# frozen_string_literal: true

module Nabu
  # Bumped by the release rail (ops §12) together with CITATION.cff —
  # surfaced in provenance code_version stamps and fetch User-Agents, so
  # it must match the tagged release. (It sat at 0.1.0 through v1.0.0 and
  # v1.1.0 — caught at the v1.2.0 cut; the stamps those releases minted
  # keep their recorded strings, provenance is append-only.)
  VERSION = "1.2.0"
end
