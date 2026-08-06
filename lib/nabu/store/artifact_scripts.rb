# frozen_string_literal: true

require "yaml"

module Nabu
  module Store
    # The artifact-script compiler (P61-3, D60-b): config/artifact_scripts.yml
    # rows (source → stored code → registry script tag [+ note]) derived into
    # document_axes rows under the dedicated axis_source "artifact-script" —
    # one row per live matching document, minted ONLY where the artifact's
    # script differs from the held surface (which is what earns a code its
    # config row in the first place). Wholesale supersede on every run: the
    # lane is a pure function of stored codes + config, so rebuild and
    # re-derive are the same operation. Other lanes' rows are never touched
    # (date/place readers filter on their own columns; this lane carries
    # only the artifact columns).
    module ArtifactScripts
      AXIS_SOURCE = "artifact-script"

      Row = Data.define(:source, :code, :script, :note)
      Report = Data.define(:minted, :sources)

      # nil-safe on an absent config file (feature posture: no file, no
      # lane). +registry+ (Nabu::Lects), when present, validates every
      # script tag against the global scripts table — an unregistered tag
      # is refused loudly, never written.
      def self.derive!(catalog, config_path:, registry: nil)
        rows = load_rows(config_path)
        validate!(rows, registry) if registry
        catalog[:document_axes].where(axis_source: AXIS_SOURCE).delete
        minted = 0
        rows.each do |row|
          doc_ids = catalog[:documents]
                    .join(:sources, id: :source_id)
                    .where(Sequel[:sources][:slug] => row.source,
                           Sequel[:documents][:language] => row.code,
                           Sequel[:documents][:withdrawn] => false)
                    .select_map(Sequel[:documents][:id])
          doc_ids.each_slice(1_000) do |slice|
            catalog[:document_axes].multi_insert(slice.map do |doc_id|
              { document_id: doc_id, axis_source: AXIS_SOURCE,
                artifact_script: row.script, artifact_script_note: row.note }
            end)
          end
          minted += doc_ids.size
        end
        Report.new(minted: minted, sources: rows.map(&:source).uniq)
      end

      # The artifact row for one document, or nil (the common case — the
      # lane is minted on difference only).
      def self.for_document(catalog, document_id)
        catalog[:document_axes]
          .where(document_id: document_id, axis_source: AXIS_SOURCE)
          .select(:artifact_script, :artifact_script_note).first
      end

      def self.load_rows(config_path)
        return [] unless config_path && File.file?(config_path)

        raw = YAML.safe_load_file(config_path) || {}
        (raw["sources"] || {}).flat_map do |source, codes|
          (codes || {}).map do |code, entry|
            Row.new(source: source, code: code,
                    script: entry.fetch("script"), note: entry["note"])
          end
        end
      end
      private_class_method :load_rows

      def self.validate!(rows, registry)
        rows.each do |row|
          next if registry.script?(row.script)

          raise Nabu::Error, "artifact_scripts.yml: #{row.source}/#{row.code}: script " \
                             "#{row.script.inspect} is not in the registry's scripts table"
        end
      end
      private_class_method :validate!
    end
  end
end
