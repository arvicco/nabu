# frozen_string_literal: true

module Nabu
  # Static metadata every adapter declares via Adapter.manifest (architecture
  # §3): identity, human name, license text and class, upstream location, and
  # which parser family does the heavy lifting.
  #
  # +license_class+ is a closed enum (architecture §5) — open, attribution,
  # nc, research_private, restricted — and drives query/export filters; a
  # Symbol is accepted and canonicalized to its String form.
  SourceManifest = Data.define(:id, :name, :license, :license_class, :upstream_url, :parser_family) do
    def initialize(id:, name:, license:, license_class:, upstream_url:, parser_family:)
      super(
        id: Model::Validation.slug!(id, field: "id"),
        name: Model::Validation.present_string!(name, field: "name"),
        license: Model::Validation.present_string!(license, field: "license"),
        license_class: Model::Validation.license_class!(license_class),
        upstream_url: Model::Validation.present_string!(upstream_url, field: "upstream_url"),
        parser_family: Model::Validation.slug!(parser_family, field: "parser_family")
      )
    end
  end

  # The license_class enum is part of the public contract; expose it here
  # (implementation lives with the shared validators).
  SourceManifest::LICENSE_CLASSES = Model::Validation::LICENSE_CLASSES
end
