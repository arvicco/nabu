# frozen_string_literal: true

require "digest"

require_relative "../errors"
require_relative "../config"
require_relative "../source_registry"
require_relative "builder"
require_relative "csv_writer"
require_relative "rollup_slice"

module Nabu
  module DataBuild
    # The mul/dictionary-crossrefs builder — the catalog's
    # dictionary_crossrefs published as the cross-dictionary reference
    # graph. One row per edge: the FROM entry, the pointer's kind and its
    # verbatim label, the target as stored (target, target_folded,
    # target_id), and — where the loader resolved it — the TO entry.
    #
    # == Entry references
    #
    # Entries are referenced by their catalog URN
    # (urn:nabu:dict:<dictionary>:<upstream entry id>, migration 006) —
    # minted from the dictionary slug and the upstream entry id, so it is
    # stable across rebuilds where the integer row id is not. The headword
    # rides beside it for readability.
    #
    # == Resolution
    #
    # A resolved edge carries Target_Entry_URN + Target_Headword and names
    # the target entry's own dictionary. An unresolved edge (an ambiguous
    # homograph pointer, or a dictionary the catalog does not hold) is
    # still an edge: it publishes with the target-entry fields empty and
    # Target_Dictionary as the pointer names it (to_dictionary, or the
    # pointer's own dictionary when NULL — the migration-041 default).
    # Both states are censused.
    #
    # == License screening — both endpoints
    #
    # An edge publishes only when its OWN dictionary's source is open or
    # attribution class AND, when resolved, the TARGET entry's dictionary's
    # source is too — a resolved edge exposes the target's URN and
    # headword, so an nc endpoint on either side drops the edge. Drops are
    # censused per endpoint role ("source" first: a doubly-screened edge
    # counts once, under its source role) and per class. An unresolved
    # edge exposes only its own dictionary's pointer text, so only its
    # source endpoint screens. Edges of withdrawn entries never publish
    # (censused).
    #
    # == Provenance
    #
    # Own catalog projection; the recipe embeds the published-slice sha256,
    # so an unchanged slice is a fingerprint no-op and a screened edge can
    # never move it.
    class DictionaryCrossrefsBuilder
      FILENAME = "dictionary-crossrefs.csv"
      COLUMNS = %w[ID Language_ID Dictionary Entry_URN Headword Seq Kind Label Target Target_Folded
                   Target_ID Target_Dictionary Target_Entry_URN Target_Headword Source].freeze
      INTEGER_COLUMNS = %w[Seq].freeze

      SOURCE_ROLE = "source"
      TARGET_ROLE = "target"

      OVERVIEW =
        "Which dictionary entries point at which? Historical dictionaries are dense with cross-" \
        "references — LSJ's \"v. μῦθος\", JMdict's antonyms, the Hebrew lexical index's pointers " \
        "into BDB, the AED's root links, Wiktionary's reconstructed-etymon synonyms — but the " \
        "pointers have only ever been readable inside each dictionary's own markup. This dataset " \
        "publishes Nabu's cross-reference estate as one queryable graph: every machine-marked " \
        "pointer of the open dictionaries, its kind and verbatim label, and where the target " \
        "headword resolves unambiguously, the target entry by stable URN — across Greek, Latin, " \
        "Japanese, Chinese, Hebrew, Egyptian and the reconstructed proto-languages."

      def initialize(registry: nil)
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "mul/dictionary-crossrefs needs the catalog open — dictionary_crossrefs lives there" if
          catalog.nil?

        state = new_state
        stream = RollupSlice::Stream.new { |&emit| each_published(catalog, state, &emit) }
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: stream)
        BuildResult.new(
          resources: [resource(count)],
          recipe: recipe(state[:sha].hexdigest),
          citations: RollupSlice.citations(registry, state[:slugs].keys.sort),
          evaluation: census(catalog, state, count),
          overview: OVERVIEW
        )
      end

      private

      def registry
        @registry || Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
      end

      def new_state
        { excluded: Hash.new { |hash, role| hash[role] = Hash.new(0) }, excluded_by_dictionary: Hash.new(0),
          excluded_by_resolution: Hash.new(0), by_dictionary: Hash.new(0), by_resolution: Hash.new(0),
          withdrawn: 0, slugs: {}, minter: IdMinter.new, sha: Digest::SHA256.new }
      end

      def each_published(catalog, state)
        edges(catalog).each do |row|
          if row[:withdrawn]
            state[:withdrawn] += 1
            next
          end

          role, license_class = screened_endpoint(row)
          if role
            exclude(state, row, role, license_class)
            next
          end

          yield publish(state, row)
        end
      end

      # [role, class] of the first non-publishable endpoint, or nil.
      def screened_endpoint(row)
        return [SOURCE_ROLE, row[:license_class]] unless RollupSlice.publishable?(row[:license_class])
        return nil if row[:to_entry_id].nil?
        return [TARGET_ROLE, row[:to_license_class]] unless RollupSlice.publishable?(row[:to_license_class])

        nil
      end

      def exclude(state, row, role, license_class)
        state[:excluded][role][license_class] += 1
        state[:excluded_by_dictionary][row[:dictionary]] += 1
        state[:excluded_by_resolution][resolution(row)] += 1
      end

      def resolution(row) = row[:to_entry_id].nil? ? "unresolved" : "resolved"

      # Every crossref with both endpoints joined (the target side LEFT
      # joined — an unresolved edge has none); ordered (dictionary slug,
      # entry URN, seq), never by row id, so the order survives a rebuild.
      def edges(catalog)
        catalog[Sequel[:dictionary_crossrefs].as(:x)]
          .join(Sequel[:dictionary_entries].as(:e), id: Sequel[:x][:dictionary_entry_id])
          .join(Sequel[:dictionaries].as(:d), id: Sequel[:e][:dictionary_id])
          .join(Sequel[:sources].as(:s), id: Sequel[:d][:source_id])
          .left_join(Sequel[:dictionary_entries].as(:te), id: Sequel[:x][:to_entry_id])
          .left_join(Sequel[:dictionaries].as(:td), id: Sequel[:te][:dictionary_id])
          .left_join(Sequel[:sources].as(:ts), id: Sequel[:td][:source_id])
          .select(Sequel[:d][:slug].as(:dictionary), Sequel[:d][:language], Sequel[:e][:urn],
                  Sequel[:e][:entry_id], Sequel[:e][:headword], Sequel[:e][:withdrawn],
                  Sequel[:s][:slug].as(:source), Sequel[:s][:license_class], Sequel[:x][:seq],
                  Sequel[:x][:kind], Sequel[:x][:label], Sequel[:x][:target], Sequel[:x][:target_folded],
                  Sequel[:x][:target_id], Sequel[:x][:to_dictionary], Sequel[:x][:to_entry_id],
                  Sequel[:te][:urn].as(:to_urn), Sequel[:te][:headword].as(:to_headword),
                  Sequel[:td][:slug].as(:to_dictionary_slug), Sequel[:ts][:slug].as(:to_source),
                  Sequel[:ts][:license_class].as(:to_license_class))
          .order(Sequel[:d][:slug], Sequel[:e][:urn], Sequel[:x][:seq], Sequel[:x][:id])
      end

      # The ID keys on an entry-id DIGEST (upstream entry ids carry kana,
      # Greek, dots — illegal or colliding under the CLDF identifier class)
      # plus the in-entry seq; the IdMinter catches any residual collision.
      def publish(state, row)
        record(state, row)
        target_dictionary = row[:to_dictionary_slug] || row[:to_dictionary] || row[:dictionary]
        id = state[:minter].mint(row[:dictionary], "E#{Digest::SHA256.hexdigest(row[:entry_id])[0, 12]}",
                                 row[:seq].to_s)
        values = [id, row[:language], row[:dictionary], row[:urn], row[:headword], row[:seq], row[:kind],
                  row[:label], row[:target], row[:target_folded], row[:target_id], target_dictionary,
                  row[:to_urn], row[:to_headword], row[:source]]
        state[:sha] << values.drop(1).join("\x1f") << "\n"
        COLUMNS.zip(values).to_h
      end

      def record(state, row)
        state[:slugs][row[:source]] = true
        state[:slugs][row[:to_source]] = true if row[:to_source]
        state[:by_dictionary][row[:dictionary]] += 1
        state[:by_resolution][resolution(row)] += 1
      end

      def census(catalog, state, count)
        { "crossref_rows" => catalog[:dictionary_crossrefs].count,
          "withdrawn_entry_edges_skipped" => state[:withdrawn],
          "published_edges" => count,
          "published_by_resolution" => RollupSlice.sorted_census(state[:by_resolution]),
          "published_by_dictionary" => RollupSlice.sorted_census(state[:by_dictionary]),
          "excluded_edges" => RollupSlice.sorted_census(state[:excluded].transform_values do |classes|
            RollupSlice.sorted_census(classes)
          end),
          "excluded_by_dictionary" => RollupSlice.sorted_census(state[:excluded_by_dictionary]),
          "excluded_by_resolution" => RollupSlice.sorted_census(state[:excluded_by_resolution]) }
      end

      def resource(count)
        fields = COLUMNS.map { |name| { name: name, type: INTEGER_COLUMNS.include?(name) ? "integer" : "string" } }
        Resource.new(name: "dictionary_crossrefs", path: FILENAME, rows: count,
                     fields: fields, primary_key: ["ID"])
      end

      def recipe(digest)
        "dictionary-crossrefs v1: project dictionary_crossrefs one row per edge of a live entry, " \
          "entries referenced by catalog URN, resolved targets joined by to_entry_id, license " \
          "classes #{RollupSlice::PUBLISHABLE_LICENSE_CLASSES.join('+')} only on BOTH endpoints " \
          "(source dictionary always, target dictionary when resolved), ordered (dictionary, " \
          "entry URN, seq); published-slice sha256=#{digest}"
      end
    end
  end
end
