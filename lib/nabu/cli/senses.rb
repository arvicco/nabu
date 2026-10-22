# frozen_string_literal: true

# Nabu::CLI — the token-sense readers: the `nabu sense` desk (the sense
# facet pairs Store::PassageFacetBuilder projects from the DCS gold
# tokens' WordSem ids) and the `show --senses` listing (the shown
# passages' own stored tokens, resolved against the dcs-senses shelf).
# Carved out of lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    desc "sense [TERM]", "Passages and tokens by the word sense their gold tokens cite (DCS WordSem)"
    long_desc <<~HELP, wrap: false
      Find passages by the WORD SENSE their tokens are annotated with: the
      Digital Corpus of Sanskrit's gold tokens cite WordNet-shaped sense ids
      (CoNLL-U MISC WordSem=…), the ids of the dcs-senses shelf. A token
      citing several senses keeps them all — each finds it.

      TERM is a sense id (59344, or a comma-joined list), else a sense NAME
      matched case-insensitively against the shelf (finger, Dhanvantari;
      LIKE wildcards work: circum%). --gloss also matches a substring of the
      sense's gloss ("linear measure"). The desk prints the matched senses
      (most-attested first) and the passages in catalog order, each with
      its citing tokens — form (lemma) ×count [ids].

      With no TERM, the census: senses, passages and pairs per source.

      Reads the precompiled passage facet pairs only (facet name "sense",
      so `nabu search --facet sense=59344` filters by it too) — built by
      every rebuild, by `bundle exec rake builders:refresh` and per source
      after a sync; an unbuilt index is a hint, never a scan. To see one
      passage's (or document's) token senses, use `nabu show URN --senses`.

      Examples:
        nabu sense finger                     # the sense named finger
        nabu sense 25248,25258                # by sense id(s)
        nabu sense "linear measure" --gloss   # inside the gloss
        nabu sense                            # the index census
    HELP
    option :gloss, type: :boolean, default: false, desc: "Also match TERM inside the sense's gloss"
    option :source, type: :string, banner: "SLUG", desc: "Only this source's passages"
    option :limit, type: :numeric, default: Nabu::Query::Senses::DEFAULT_LIMIT,
                   desc: "Passages listed (the totals always count all)"
    display_option
    def sense(*term_parts)
      display_mode
      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      query = Nabu::Query::Senses.new(catalog: catalog, facet_map: Nabu::FacetMap.load_default(config: config))
      term = term_parts.join(" ").strip
      return print_sense_census(query.census) if term.empty?

      print_sense_result(query.run(term, gloss: options[:gloss], source: options[:source],
                                         limit: options[:limit].to_i))
      print_display_footer
    rescue Nabu::Query::Senses::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    SENSE_SNIPPET = 100
    SENSE_GLOSS = 80
    # Token groups printed per hit (form + lemma + ids, most frequent
    # first); the tail is counted, never silently cut.
    SENSE_TOKEN_GROUPS = 6

    no_commands do
      def print_sense_result(result)
        if result.sense_total.zero?
          return say "sense #{result.query.inspect}: no indexed sense matches (an id, or a sense name" \
                     "#{' or gloss' if options[:gloss]})"
        end

        say "sense #{result.query.inspect}: #{sense_tally(result.sense_total, 'sense')} · " \
            "#{sense_tally(result.passage_total, 'passage')}"
        print_sense_list(result)
        say ""
        result.hits.each do |hit|
          say "#{hit.urn}  #{sense_token_groups(hit.tokens)}"
          say "  #{display_text(sense_clip(hit.text, SENSE_SNIPPET), hit.language)}"
        end
        return unless result.hits.size < result.passage_total

        say "  (showing #{result.hits.size} of #{result.passage_total} passages — raise --limit)"
      end

      def print_sense_list(result)
        width = result.senses.map { |sense| sense.id.length }.max
        result.senses.each do |sense|
          say "  #{sense.id.ljust(width)}  #{sense_label(sense)}  #{sense_tally(sense.passages, 'passage')}"
        end
        hidden = result.sense_total - result.senses.size
        say "  … #{sense_tally(hidden, 'more sense')} (narrow the term or --source)" if hidden.positive?
      end

      # "finger — the length of …", or the honest unresolved label.
      def sense_label(sense)
        return "(not in #{sense.shelf || 'a loaded shelf'})" if sense.headword.nil?

        sense_name_gloss(sense.headword, sense.gloss)
      end

      def sense_name_gloss(headword, gloss)
        [headword, gloss && sense_clip(gloss, SENSE_GLOSS)].compact.join(" — ")
      end

      # "aṅgula ×11 [59344] · aṅgulam (aṅgula) ×4 [59344] · …"
      def sense_token_groups(tokens)
        groups = tokens.group_by { |token| [token.form, token.lemma, token.ids] }
                       .sort_by.with_index { |(_key, members), index| [-members.size, index] }
        shown = groups.first(SENSE_TOKEN_GROUPS).map do |(form, lemma, ids), members|
          count = members.size > 1 ? " ×#{members.size}" : ""
          "#{sense_token_name(form, lemma)}#{count} [#{ids.join(',')}]"
        end
        hidden = groups.size - shown.size
        shown << "… #{hidden} more" if hidden.positive?
        shown.join(" · ")
      end

      def sense_token_name(form, lemma)
        lemma.nil? || lemma == form ? form.to_s : "#{form} (#{lemma})"
      end

      def print_sense_census(rows)
        return say "sense index: empty — no ruled source's tokens carry senses" if rows.empty?

        say "sense index: #{sense_tally(rows.sum(&:senses), 'sense')} across #{sense_tally(rows.size, 'source')}"
        width = rows.map { |row| row.source.length }.max
        rows.each do |row|
          say "  #{row.source.ljust(width)}  #{sense_tally(row.senses, 'sense')}  " \
              "#{sense_tally(row.passages, 'passage')}  #{sense_tally(row.pairs, 'pair')}"
        end
      end

      def sense_tally(count, noun) = "#{commas(count)} #{noun}#{'s' unless count == 1}"

      def sense_clip(text, width)
        flat = text.to_s.gsub(/\s+/, " ").strip
        flat.length > width ? "#{flat[0, width]}…" : flat
      end

      # -- show --senses -----------------------------------------------------

      # The shown passage's (or each listed passage's) citing tokens, every
      # sense id resolved against the shelf — read straight off the stored
      # tokens the show already loaded, so no index is needed.
      def print_show_senses(result, catalog:, config:)
        senses = Nabu::Query::Senses.new(catalog: catalog, facet_map: Nabu::FacetMap.load_default(config: config))
        if senses.misc_keys(result.source_slug).empty?
          return say "no token senses are ruled for #{result.source_slug} (config/facet_map.yml token_fields)"
        end

        case result
        when Nabu::Query::Show::PassageResult then print_passage_senses(result, senses)
        when Nabu::Query::Show::DocumentResult, Nabu::Query::Show::RangeResult
          print_document_senses(result, senses)
        end
      end

      def print_passage_senses(result, senses)
        return say ANNOTATIONS_UNREADABLE_NOTE if annotations_unreadable?(result)

        cited = senses.token_senses(result.annotations, source: result.source_slug)
        return say "no token senses stored for this passage" if cited.empty?

        say "senses (#{sense_tally(cited.size, 'token')}):"
        print_token_senses(cited, senses, indent: "  ")
      end

      def print_document_senses(result, senses)
        listed = result.passages.filter_map do |line|
          cited = senses.token_senses(line.annotations, source: result.source_slug)
          [line, cited] unless cited.empty?
        end
        return say "no token senses stored for these passages" if listed.empty?

        say "senses (#{sense_tally(listed.sum { |_line, cited| cited.size }, 'token')} in " \
            "#{sense_tally(listed.size, 'passage')}):"
        listed.each do |line, cited|
          say "  #{passage_label(result, line)}"
          print_token_senses(cited, senses, indent: "    ")
        end
      end

      # One line per citing token: "form (lemma)  id name — gloss", a
      # multi-id token's further ids on continuation lines beneath.
      def print_token_senses(cited, senses, indent:)
        entries = senses.entries_for(cited.flat_map(&:last))
        unresolved = "(not in #{senses.shelves.empty? ? 'a loaded shelf' : senses.shelves.join(', ')})"
        names = cited.map { |token, _ids| sense_token_name(token["form"], token["lemma"]) }
        width = names.map(&:length).max
        cited.each_with_index do |(_token, ids), index|
          ids.each_with_index do |id, position|
            entry = entries[id]
            label = entry ? sense_name_gloss(entry.headword, entry.gloss) : unresolved
            lead = position.zero? ? names[index].ljust(width) : " " * width
            say "#{indent}#{lead}  #{id} #{label}"
          end
        end
      end
    end
  end
end
