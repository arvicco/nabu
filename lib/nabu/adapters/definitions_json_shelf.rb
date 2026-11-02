# frozen_string_literal: true

require_relative "definitions_json_parser"

module Nabu
  module Adapters
    # The shared base for a definitions-json dictionary repo (the
    # stscoundrel editions: one git repo, one JSON array file as the shelf).
    # A subclass declares only the facts that differ:
    #
    #   MANIFEST         - the Nabu::SourceManifest
    #   JSON_PATH        - the accepted file, relative to the repo root
    #   REJECTED_PATHS   - the other data files upstream serves, skipped by
    #                      rule with a note each (the no-markup twin)
    #   DICTIONARY_SLUG  - the shelf slug (= manifest id, by convention)
    #   LANGUAGE         - the stored language tag
    #   TITLE            - the DictionaryDocument display title
    #
    # Fetch is the house GitFetch (attic + mass-deletion breaker); nothing
    # is materialized beside upstream's tree.
    class DefinitionsJsonShelf < Nabu::Adapter
      class << self
        def manifest
          self::MANIFEST
        end

        # Entries, not passages — SyncRunner/Rebuild load through
        # Store::DictionaryLoader (architecture §11).
        def content_kind = :dictionary
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, self.class::JSON_PATH)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(
          source_id: manifest.id,
          id: "#{self.class::DICTIONARY_SLUG}:#{File.basename(path)}",
          path: File.expand_path(path),
          metadata: { "dictionary" => self.class::DICTIONARY_SLUG }
        )
      end

      # The rejected grains present in the tree, each counted with its note.
      def discovery_skips(workdir)
        present = self.class::REJECTED_PATHS.select { |rel, _| File.file?(File.join(workdir, rel)) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: present.size,
          notes: present.map { |rel, why| "#{rel}: skipped by rule — #{why}" }
        )
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: self.class::DICTIONARY_SLUG, language: self.class::LANGUAGE,
          title: self.class::TITLE, canonical_path: document_ref.path
        )
        DefinitionsJsonParser.new(language: self.class::LANGUAGE)
                             .entries(document_ref.path).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{manifest.id}: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Split out so fetch tests can point a singleton at a local git tmpdir
      # (the house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end
    end
  end
end
