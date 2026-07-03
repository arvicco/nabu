# frozen_string_literal: true

# Initial catalog schema (architecture §5). Forward-only; never edit once
# applied — add a new numbered migration instead.
#
# Migrations must NOT depend on application code, so the license-class enum
# and run-status enum are hardcoded here. They mirror
# Nabu::Model::Validation::LICENSE_CLASSES; keep the two in sync by hand if
# the enum ever grows (a schema change is a migration either way).
Sequel.migration do
  change do
    license_classes = %w[open attribution nc research_private restricted].freeze
    run_statuses = %w[running succeeded failed aborted].freeze

    create_table(:sources) do
      primary_key :id
      String :slug, null: false # registry id, e.g. "perseus-greek"
      String :name, null: false
      String :adapter_class, null: false
      String :license
      String :license_class, null: false
      String :upstream_url
      TrueClass :enabled, null: false, default: false
      DateTime :last_sync_at
      String :last_sync_sha

      constraint(:sources_license_class_valid, license_class: license_classes)
      index :slug, unique: true
    end

    create_table(:documents) do
      primary_key :id
      foreign_key :source_id, :sources, null: false
      String :urn, null: false
      String :title
      String :language
      String :edition
      String :license_override # nullable; same enum as license_class
      String :canonical_path
      String :content_sha256, null: false
      Integer :revision, null: false, default: 1
      TrueClass :withdrawn, null: false, default: false

      constraint(:documents_license_override_valid) do
        (license_override =~ nil) | (license_override =~ license_classes)
      end
      index :source_id
      index :urn, unique: true
    end

    create_table(:passages) do
      primary_key :id
      foreign_key :document_id, :documents, null: false
      String :urn, null: false
      Integer :sequence, null: false
      String :language
      String :text, text: true, null: false
      String :text_normalized, text: true, null: false
      String :annotations_json, text: true, default: "{}"
      String :content_sha256, null: false
      Integer :revision, null: false, default: 1
      TrueClass :withdrawn, null: false, default: false

      index :document_id
      index :urn, unique: true
      index %i[document_id sequence], unique: true
    end

    create_table(:provenance) do
      primary_key :id
      foreign_key :passage_id, :passages          # nullable: document-level events use document_id
      foreign_key :document_id, :documents        # nullable
      String :event, null: false                  # e.g. "loaded", "revised", "withdrawn"
      String :tool
      String :tool_version
      String :model
      String :params_json, text: true
      DateTime :at, null: false

      index :passage_id
      index :document_id
    end

    create_table(:enrichments) do
      primary_key :id
      foreign_key :passage_id, :passages, null: false
      String :kind, null: false
      String :model
      String :model_version
      String :payload_json, text: true
      DateTime :at, null: false

      index :passage_id
      index %i[passage_id kind]
    end

    create_table(:runs) do
      primary_key :id
      foreign_key :source_id, :sources, null: false
      DateTime :started_at, null: false
      DateTime :finished_at
      Integer :added, null: false, default: 0
      Integer :updated, null: false, default: 0
      Integer :withdrawn_count, null: false, default: 0
      Integer :errored, null: false, default: 0
      String :status, null: false, default: "running"
      String :notes, text: true

      constraint(:runs_status_valid, status: run_statuses)
      index :source_id
    end
  end
end
