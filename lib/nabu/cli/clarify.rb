# frozen_string_literal: true

# Nabu::CLI — the reference normalizer (`nabu clarify`), the CLI face of
# Query::Clarify (served on MCP as nabu_clarify). Carved out of
# lib/nabu/cli.rb, the registry that loads it.
require_relative "../query/clarify"

module Nabu
  class CLI < Thor
    desc "clarify QUERY", "Normalize a partial or misspelled title/reference into urns and candidates"
    long_desc <<~HELP, wrap: false
      Turn a half-remembered reference into an honest reading of it: is the
      input a REFERENCE at all, which urn it names when it parses UNIQUELY,
      what a deeper citation looks like there, and typed CANDIDATES
      (document · source · place · lemma) for everything else. Never a
      silent guess: an ambiguous reference (two editions sharing a title, a
      citation two of them hold) resolves to nothing and lists every
      reading; a misspelling-lane (fuzzy) match is only ever a candidate.

      QUERY is a urn (or its prefix — the catalog's unique urn indexes
      answer it, no index needed), a title or its prefix/misspelling, or a
      title plus a citation ("Iliad 1.2"). Each candidate prints its title,
      [type · how it matched], the key to open it with (a document urn, a
      source slug, a place id, a lemma), its source and [language · license
      class], and — when a citation was given — the passage urn it names
      there.

      Reads precompiled data only: names resolve through the fulltext
      index's clarify lane (built by every sync/rebuild); an absent lane is
      a hint, never a scan. The same reading MCP clients get from
      nabu_clarify (which additionally withholds research_private/restricted
      material by default — this local desk shows everything).

      Examples:
        nabu clarify Ilaid                    # the misspelling → Iliad candidates
        nabu clarify "Iliad 1.2"              # a title plus a citation
        nabu clarify urn:cts:greekLit:tlg0012.tlg001   # a urn prefix → its documents
    HELP
    option :limit, type: :numeric, default: Nabu::Query::Clarify::DEFAULT_LIMIT,
                   desc: "Candidates listed (default #{Nabu::Query::Clarify::DEFAULT_LIMIT})"
    def clarify(*query_parts)
      query = query_parts.join(" ").strip
      raise Thor::Error, "clarify: give a title, a title plus citation, or a urn" if query.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      fulltext = open_fulltext(config)
      result = Nabu::Query::Clarify.new(catalog: catalog, fulltext: fulltext)
                                   .run(query, limit: options[:limit].to_i, include_restricted: true)
      print_clarify(result)
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    no_commands do
      def print_clarify(result)
        say "clarify #{result.query.inspect}#{' — a reference' if result.is_ref}"
        print_clarify_ref(result.ref) if result.ref
        print_clarify_structure(result.structure) if result.structure
        print_clarify_candidates(result.completions)
        say "note: #{result.note}" if result.note
        say "(the clarify lane is not built — names cannot resolve until the next sync/rebuild)" \
          unless result.index_present || result.query.start_with?("urn:")
      end

      def print_clarify_ref(ref)
        say "  resolves to #{ref.urn} (#{ref.kind})#{" — #{ref.title}" if ref.title}  " \
            "#{ref.source} [#{[ref.language, ref.license_class].compact.join(' · ')}]"
      end

      def print_clarify_structure(structure)
        span = [structure.first_citation, structure.last_citation].compact.uniq.join(" … ")
        line = "  citation shape: #{plural(structure.passages, 'passage')}"
        line += ", #{span}" unless span.empty?
        line += " (depth #{structure.depth})" if structure.depth
        say line
        examples = [structure.example, structure.range_example].compact
        say "    e.g. #{examples.join('  ·  ')}" unless examples.empty?
      end

      def print_clarify_candidates(candidates)
        return say "  no candidates" if candidates.empty?

        say "candidates (#{candidates.size}):"
        candidates.each do |candidate|
          tags = [candidate.language, candidate.license_class].compact.join(" · ")
          primary = candidate.is_primary ? "" : " (alias)"
          say "  #{candidate.title}#{primary}  [#{candidate.type} · #{candidate.match}]  #{candidate.key}" \
              "#{"  #{candidate.source}" if candidate.source}#{" [#{tags}]" unless tags.empty?}"
          say "    #{candidate.detail}" if candidate.detail
          say "    → #{candidate.ref_urn}" if candidate.ref_urn
        end
      end
    end
  end
end
