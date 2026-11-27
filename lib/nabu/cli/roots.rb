# frozen_string_literal: true

# Nabu::CLI — the Arabic root readers: `define --root ROOT` (the entries a
# consonantal root reaches) and `show --roots` (each stored Quranic
# token's root, stepped to Lane). Both read Query::RootLink — the derived
# root-key entry facets, never a scan. Carved out of lib/nabu/cli.rb, the
# registry that loads it.
module Nabu
  class CLI < Thor
    ROOT_KEYS_UNBUILT = "the root keys are not built in this catalog yet — run " \
                        "`bundle exec rake builders:refresh` (or the next nabu rebuild) after a dictionary " \
                        "shelf with a keyed root rule (lane-lexicon) is synced"

    no_commands do
      # `define --root ROOT`: the header line (the root, its notation, its
      # Arabic form, the heading(s) and tier that answered), then the
      # reached entries in the define house format, capped at --limit.
      def define_by_root(root, catalog:, config:)
        scheme = options[:scheme]&.to_sym
        raise Thor::Error, ROOT_KEYS_UNBUILT unless Nabu::Query::RootLink.new(catalog: catalog).built?

        define = Nabu::Query::Define.new(catalog: catalog, lila: nil,
                                         scan_anchors: Nabu::Query::ScanAnchors.load_default(config: config))
        limit = options[:long] ? nil : options[:limit].to_i
        link, results = define.by_root(root, scheme: scheme, limit: limit)
        say root_link_header(link)
        return unless link.hit?

        say ""
        print_define_results(root, results, catalog: catalog)
        hidden = link.total - results.size
        return unless hidden.positive?

        say format("… %<n>d more %<verb>s under this root (--long shows all; --limit raises the cap)",
                   n: hidden, verb: hidden == 1 ? "entry" : "entries")
      end

      def root_link_header(link)
        lead = "root #{link.root} [#{link.scheme}]"
        if link.arabic.nil?
          tabled = Nabu::ArabicRoots::TABLES.key?(link.scheme)
          unmapped = tabled ? Nabu::ArabicRoots.unmapped(link.root, scheme: link.scheme) : []
          return "#{lead}: not a consonantal root in that notation " \
                 "(unmapped: #{unmapped.join(' ')}) — no dictionary lookup"
        end
        return "#{lead} → #{link.arabic}: no dictionary heading carries this root" unless link.hit?

        "#{lead} → #{link.arabic}: #{root_link_reach(link)}"
      end

      # "Lane heading رحم — 12 entries (strict key)".
      def root_link_reach(link)
        tier = link.tier == :strict ? "strict key" : "loose key — weak radicals/reduplication folded, may over-merge"
        noun = link.headings.size == 1 ? "heading" : "headings"
        "#{noun} #{link.headings.join(', ')} — #{link.total} #{link.total == 1 ? 'entry' : 'entries'} (#{tier})"
      end

      # -- show --roots ----------------------------------------------------

      def print_show_roots(result, catalog:)
        unless Nabu::Query::RootLink.scheme_for(result.source_slug)
          return say "no token root scheme is declared for #{result.source_slug} " \
                     "(Query::RootLink::TOKEN_SCHEMES — the Quranic sources)"
        end
        roots = Nabu::Query::RootLink.new(catalog: catalog)
        return say "roots: #{ROOT_KEYS_UNBUILT}" unless roots.built?

        case result
        when Nabu::Query::Show::PassageResult then print_passage_roots(result, roots)
        when Nabu::Query::Show::DocumentResult, Nabu::Query::Show::RangeResult then print_document_roots(result, roots)
        end
      end

      def print_passage_roots(result, roots)
        return say ANNOTATIONS_UNREADABLE_NOTE if annotations_unreadable?(result)

        pairs = roots.token_links(result.annotations, source: result.source_slug)
        return say "no token roots stored for this passage" if pairs.empty?

        say "roots (#{root_tally(pairs)}):"
        print_token_roots(pairs, roots, indent: "  ")
        say "  (a root's entries in full: nabu define --root ROOT)"
      end

      def print_document_roots(result, roots)
        listed = result.passages.filter_map do |line|
          pairs = roots.token_links(line.annotations, source: result.source_slug)
          [line, pairs] unless pairs.empty?
        end
        return say "no token roots stored for these passages" if listed.empty?

        say "roots (#{root_tally(listed.flat_map(&:last))} in #{sense_tally(listed.size, 'passage')}):"
        listed.each do |line, pairs|
          say "  #{passage_label(result, line)}"
          print_token_roots(pairs, roots, indent: "    ")
        end
        say "  (a root's entries in full: nabu define --root ROOT)"
      end

      def root_tally(pairs)
        joined = pairs.count { |_token, link| link.hit? }
        "#{sense_tally(pairs.size, 'token')}, #{joined} reaching a dictionary"
      end

      # One line per root-bearing token: form, root → Arabic, then the
      # reach (heading, count, tier) and the first entry's urn — or the
      # honest miss.
      def print_token_roots(pairs, roots, indent:)
        forms = pairs.map { |token, _link| token["form"].to_s }
        width = forms.map(&:length).max
        pairs.each_with_index do |(_token, link), index|
          lead = "#{indent}#{forms[index].ljust(width)}  #{link.root}"
          say "#{lead}  #{token_root_reach(link, roots)}"
        end
      end

      def token_root_reach(link, roots)
        return "(not a consonantal root)" if link.arabic.nil?
        return "→ #{link.arabic}  (no dictionary heading)" unless link.hit?

        first = roots.entries(link, limit: 1).first
        "→ #{link.arabic}  #{root_link_reach(link)}  #{first&.urn}".rstrip
      end
    end
  end
end
