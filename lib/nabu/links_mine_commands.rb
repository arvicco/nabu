# frozen_string_literal: true

module Nabu
  # The mined-layers verbs of `nabu links` (the cost law, architecture
  # §15): `nabu links mine SCOPE` — the ONLY trigger of a heavy layer's
  # (re-)mine — and `nabu links migrate-mined [--dry-run]`, the one-time
  # move of heavy runs out of db/links.sqlite3. Mixed into the CLI as
  # private helpers (never Thor commands of their own: `links URN` stays
  # the reader, these two words dispatch from it — the `place mine`
  # precedent). Every write goes through Nabu::MinedLayers →
  # Store::MinedLinks, the store's one gateway.
  module LinksMineCommands
    VERBS = %w[mine migrate-mined].freeze

    private

    def run_links_verb(verb, args)
      verb == "mine" ? run_links_mine(args) : run_links_migrate(args)
    end

    # Re-mine every recorded heavy scope named SCOPE (its link_scopes.yml
    # entry: producer + params) into local/mined-links.sqlite3 — the same
    # engine call the old rebuild replay made (LinkScopeReplay), so the
    # same profiles and params apply; the store's self-check compares the
    # fresh edges with the layer they replace.
    def run_links_mine(args)
      name = args.first.to_s
      raise Thor::Error, "usage: nabu links mine SCOPE (a recorded heavy scope)" if name.empty?

      config = Nabu::Config.load
      scopes = Nabu::MinedLayers.recorded(config.link_scopes_path, name)
      if scopes.empty?
        known = Nabu::MinedLayers.recorded(config.link_scopes_path).map { |scope| scope["scope"] }
        raise Thor::Error, "links mine: no recorded heavy scope #{name.inspect} " \
                           "(recorded: #{known.empty? ? 'none' : known.join(', ')}) — a new scope is " \
                           "recorded by its producer's batch command (nabu parallels --batch SCOPE)"
      end

      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

      registry = Nabu::SourceRegistry.load(config.sources_path)
      scopes.each do |scope|
        mine_layer(scope, config: config, catalog: catalog, fulltext: fulltext, registry: registry)
      end
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    def mine_layer(scope, config:, catalog:, fulltext:, registry:)
      label = "#{scope['producer']} #{scope['scope']}"
      say "links mine: #{label} → #{config.mined_links_path} (stamping inputs: member content identities)"
      on_chunk = ->(report) { warn "  #{Nabu::BatchParallels.chunk_line(report)}" }
      result = Nabu::MinedLayers.mine!(scope, config: config, catalog: catalog, registry: registry) do |store|
        Nabu::LinkScopeReplay.replay!(scope, db: catalog, fulltext: fulltext, journal: store, config: config,
                                             on_chunk: on_chunk)
      end
      say "links mine: #{label} — #{result.layer.edges} edges in " \
          "#{format_duration(result.layer.seconds.to_f)} · #{mine_verdict(result)}",
          result.verdict == :drift ? :red : nil
      warn "links mine SELF-CHECK DRIFT: #{label}" if result.verdict == :drift
    end

    def mine_verdict(result)
      before = result.before_edges
      case result.verdict
      when :first then "first mine of this layer"
      when :verified then "self-check: inputs unchanged, edges reproduced exactly"
      when :drift then "SELF-CHECK DRIFT: inputs unchanged, but #{before} edges stamped vs " \
                       "#{result.layer.edges} freshly mined — the stamp misses an input"
      when :reproduced then "code-change re-mine: reproduced exactly"
      when :changed then "code-change re-mine: content differs (#{before} → #{result.layer.edges} edges)"
      else "re-mined (moved: #{result.blame.join(', ')}; #{before} → #{result.layer.edges} edges)"
      end
    end

    # The one-time move. Opens the catalog (when present) only to vouch
    # each moved layer's catalog identity (MinedLayers.migrate!).
    def run_links_migrate(args)
      dry = Array(args).include?("--dry-run")
      config = Nabu::Config.load
      catalog = dry ? nil : open_catalog(config)
      registry = catalog ? Nabu::SourceRegistry.load(config.sources_path) : nil
      warn "links migrate-mined: vouching each moved layer against the live catalog (member identities) …" if catalog
      report = Nabu::MinedLayers.migrate!(config: config, dry_run: dry, catalog: catalog, registry: registry)
      say "links migrate-mined#{' (dry run — nothing written)' if dry}: #{report.runs} heavy run(s) in " \
          "#{config.links_path} (#{report.journal_edges_before} edges)"
      say "  #{dry ? 'would move' : 'moved'}: #{report.moved.empty? ? 'none' : report.moved.join(', ')}"
      say "  kept (store already current): #{report.kept.join(', ')}" unless report.kept.empty?
      say "  journal heavy edges #{report.journal_edges_before} → #{report.journal_edges_after} · " \
          "mined store edges #{report.mined_edges_before} → #{report.mined_edges_after}"
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end
  end
end
