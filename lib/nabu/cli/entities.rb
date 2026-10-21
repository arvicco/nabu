# frozen_string_literal: true

# Nabu::CLI — the inline-entity readers: the `nabu entity` desk (the
# precompiled Store::EntityIndex) and the `show --entities` listing (the
# shown passages' own "entities" annotation). Carved out of lib/nabu/cli.rb,
# the registry that loads it.
module Nabu
  class CLI < Thor
    desc "entity [NAME]", "Passages by a name marked inside their text (persons, places … — the entity index)"
    long_desc <<~HELP, wrap: false
      Find passages by a name their edition MARKS inside the text: the
      persName/placeName/name spans of the Perseus EpiDoc editions, Coptic
      Scriptorium's entity spans (with their Wikification identities) and
      the DHARMA Deccan inscriptions' person/place tags. Each record is the
      upstream's verbatim — type (person, place, ethnic, abstract …), the
      surface as inscribed or inflected, and any identity, authority key
      (TGN ids, perseus gazetteer names, pers:/pl: keys) or ref.

      NAME matches as a SUBSTRING of a record's surface, identity, key or
      ref, with case and diacritics folded on both sides (Κροισ finds
      Κροῖσος and Κροίσου; macarius finds ⲁⲡⲁ ⲙⲁⲕⲁⲣⲓⲟⲥ through its
      identity). The fold is language-neutral: no Latin v/u or i/j merge.
      The desk prints the matched names (most-attested first) and the
      passages, in catalog order, each with the names it matched.

      With no NAME, the census: names and passages per source and type.

      Reads the precompiled index only — built by every rebuild, by
      `bundle exec rake builders:refresh` and per source after a sync;
      an unbuilt index is a hint, never a scan. The roster of indexed
      sources is config/entity_index.yml. To see one passage's (or
      document's) marked names, use `nabu show URN --entities`.

      Examples:
        nabu entity Κροῖσος                  # every passage naming Croesus
        nabu entity athens --type place       # places only
        nabu entity tgn,7002681               # by TGN key (Attica)
        nabu entity "macarius of egypt"       # a Coptic Wikification identity
        nabu entity puḷumāvi --source dharma-deccan
        nabu entity                           # the index census
    HELP
    option :type, type: :string, banner: "TYPE",
                  desc: "Only records of this upstream type (person, place, ethnic, …)"
    option :source, type: :string, banner: "SLUG", desc: "Only this source's records"
    option :limit, type: :numeric, default: Nabu::Query::Entities::DEFAULT_LIMIT,
                   desc: "Passages listed (the totals always count all)"
    display_option
    def entity(*name_parts)
      display_mode
      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      query = Nabu::Query::Entities.new(catalog: catalog)
      name = name_parts.join(" ").strip
      return print_entity_census(query.census) if name.empty?

      print_entity_result(query.run(name, type: options[:type], source: options[:source],
                                          limit: options[:limit].to_i))
      print_display_footer
    rescue Nabu::Query::Entities::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    ENTITY_SNIPPET = 100

    # One stored "entities" record as `show --entities` lists it.
    EntityRecord = Data.define(:type, :text, :identity, :key, :ref, :subtype) do
      def label = text || identity || key || ref
    end

    no_commands do
      def print_entity_result(result)
        scope = options[:type] ? " [#{options[:type]}]" : ""
        if result.name_total.zero?
          return say "entity #{result.query.inspect}#{scope}: no names match (folded substring of surface, " \
                     "identity, key or ref)"
        end

        say "entity #{result.query.inspect}#{scope}: #{entity_tally(result.name_total, 'name')} · " \
            "#{entity_tally(result.passage_total, 'passage')}"
        print_entity_names(result)
        say ""
        result.hits.each do |hit|
          say "#{hit.urn}  #{hit.names.map { |name| "#{name.type || 'untyped'} #{name.label}" }.uniq.join(' · ')}"
          say "  #{display_text(entity_snippet(hit.text), hit.language)}"
        end
        return unless result.hits.size < result.passage_total

        say "  (showing #{result.hits.size} of #{result.passage_total} passages — raise --limit)"
      end

      def print_entity_names(result)
        width = result.names.map { |name| (name.type || "untyped").length }.max
        result.names.each do |name|
          say "  #{(name.type || 'untyped').ljust(width)}  #{name.label}#{entity_details(name)}  " \
              "#{name.source}  #{entity_tally(name.passages, 'passage')}"
        end
        hidden = result.name_total - result.names.size
        say "  … #{entity_tally(hidden, 'more name')} (narrow with --type/--source)" if hidden.positive?
      end

      def print_entity_census(rows)
        return say "entity index: empty — no listed source carries inline entities" if rows.empty?

        sources = rows.map(&:source).uniq.size
        say "entity index: #{entity_tally(rows.sum(&:names), 'name')} across #{entity_tally(sources, 'source')}"
        source_width = rows.map { |row| row.source.length }.max
        type_width = rows.map { |row| (row.type || "untyped").length }.max
        rows.each do |row|
          say "  #{row.source.ljust(source_width)}  #{(row.type || 'untyped').ljust(type_width)}  " \
              "#{entity_tally(row.names, 'name')}  #{entity_tally(row.passages, 'passage')}"
        end
      end

      def entity_tally(count, noun) = "#{commas(count)} #{noun}#{'s' unless count == 1}"

      def entity_snippet(text)
        flat = text.to_s.gsub(/\s+/, " ").strip
        flat.length > ENTITY_SNIPPET ? "#{flat[0, ENTITY_SNIPPET]}…" : flat
      end

      # The record's fields beyond its label, verbatim: " [key … · identity …]".
      def entity_details(record)
        fields = { "key" => record.key, "identity" => record.identity, "ref" => record.ref,
                   "subtype" => record.subtype }
        label = record.label
        parts = fields.filter_map { |field, value| "#{field} #{value}" if value && value != label }
        parts.empty? ? "" : "  [#{parts.join(' · ')}]"
      end

      # -- show --entities ---------------------------------------------------

      # The shown passage's (or each listed passage's) stored "entities"
      # records, verbatim — read straight off the annotations the show
      # already loaded, so no index is needed.
      def print_show_entities(result)
        case result
        when Nabu::Query::Show::PassageResult then print_passage_entities(result)
        when Nabu::Query::Show::DocumentResult, Nabu::Query::Show::RangeResult
          print_document_entities(result)
        end
      end

      def print_passage_entities(result)
        return say ANNOTATIONS_UNREADABLE_NOTE if annotations_unreadable?(result)

        records = entity_records(result.annotations)
        return say "no inline entities stored for this passage" if records.empty?

        say "entities (#{records.size}):"
        print_entity_records(records, indent: "  ")
      end

      def print_document_entities(result)
        listed = result.passages.filter_map do |line|
          records = entity_records(line.annotations)
          [line, records] unless records.empty?
        end
        return say "no inline entities stored for these passages" if listed.empty?

        say "entities (#{listed.sum { |_line, records| records.size }} in #{entity_tally(listed.size, 'passage')}):"
        listed.each do |line, records|
          say "  #{passage_label(result, line)}"
          print_entity_records(records, indent: "    ")
        end
      end

      def print_entity_records(records, indent:)
        width = records.map { |record| record.type.length }.max
        records.each { |record| say "#{indent}#{record.type.ljust(width)}  #{record.label}#{entity_details(record)}" }
      end

      def entity_records(annotations)
        raw = annotations.is_a?(Hash) ? annotations[Nabu::Store::EntityIndex::ANNOTATION] : nil
        return [] unless raw.is_a?(Array)

        raw.filter_map do |element|
          next unless element.is_a?(Hash)

          fields = Nabu::Store::EntityIndex::FIELDS.to_h do |field|
            value = element[field]
            [field.to_sym, value.is_a?(String) && !value.strip.empty? ? value : nil]
          end
          fields[:type] ||= "untyped"
          record = EntityRecord.new(**fields)
          record if record.label
        end
      end
    end
  end
end
