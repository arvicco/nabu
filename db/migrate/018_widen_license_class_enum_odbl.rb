# frozen_string_literal: true

# P40-6 (D40-c ruled): mint the `odbl` license class — the Open Database
# License 1.0 (+ DbCL 1.0 for contents), first occupant Rundata/SRDB. ODbL
# is an attribution+share-alike OPEN DATA licence, but its obligations
# attach to the DATABASE (naming + link + share-alike on derived databases),
# not to a per-work credit line like the CC attribution class — a distinct
# compliance posture, so it is its own class rather than an `attribution`
# alias.
#
# Migrations must NOT depend on application code (the 001 rule), so the
# widened enum is hardcoded here, mirroring
# Nabu::Model::Validation::LICENSE_CLASSES. SQLite cannot ALTER a CHECK in
# place; Sequel's alter_table emulation recreates the table (columns,
# indexes and FKs preserved — verified) around the swapped constraint.
Sequel.migration do
  narrow = %w[open attribution nc research_private restricted].freeze
  wide = %w[open attribution nc odbl research_private restricted].freeze

  up do
    alter_table(:sources) do
      drop_constraint :sources_license_class_valid
      add_constraint(:sources_license_class_valid, license_class: wide)
    end
    alter_table(:documents) do
      drop_constraint :documents_license_override_valid
      add_constraint(:documents_license_override_valid) do
        (Sequel[:license_override] =~ nil) | (Sequel[:license_override] =~ wide)
      end
    end
  end

  down do
    alter_table(:sources) do
      drop_constraint :sources_license_class_valid
      add_constraint(:sources_license_class_valid, license_class: narrow)
    end
    alter_table(:documents) do
      drop_constraint :documents_license_override_valid
      add_constraint(:documents_license_override_valid) do
        (Sequel[:license_override] =~ nil) | (Sequel[:license_override] =~ narrow)
      end
    end
  end
end
