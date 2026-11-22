# frozen_string_literal: true

require "yaml"
require "date"
require_relative "../../paced_crawl"
require_relative "../../grant_gate"
require_relative "../../source_registry"

module Nabu
  module Ops
    module Reconstruction
      # The reconstruction class of every registered source: "how would
      # this source's canonical asset come back if canonical/ were lost,
      # with no backup?" One primary class per source:
      #
      #   :granted       — local/config/grants.yml names the slug: re-fetch
      #                    rides a recorded grant (absent file → never).
      #   :manual        — docs/manual/<slug>.md carries a human recipe
      #                    (only registered slugs match; the directory's
      #                    tool docs — embed-venv.md, git-hooks.md — never do).
      #   :rail_paced    — the adapter declares a PacedCrawl::Schedule (a
      #                    bare constant or a Spec's): a polite months-long
      #                    crawl (the Ops::RailPlan roster rule).
      #   :restricted    — the manifest's license_class is non-redistributable
      #                    (research_private / restricted, the MCP-excluded
      #                    pair): no public mirror to fall back on.
      #   :public_stable — everything else: the adapter re-fetches from stable
      #                    public URLs (the default).
      #
      # PRECEDENCE is the CLASSES order, first match wins: granted > manual
      # (a grant is the gating fact, whatever the recipe) > rail_paced >
      # restricted > public_stable. The access route outranks the license
      # posture: a restricted source that rides a recipe or the rail comes
      # back by that route.
      #
      # Orthogonal flag — attic: canonical/<slug>/.attic exists and is
      # non-empty (upstream-deleted files GitFetch preserved: backup-only
      # bytes no re-fetch restores). Absent canonical/ → false.
      #
      # OVERRIDE — an optional `reconstruct: <class>` key on a sources.yml
      # row replaces the computed class. It must name a known class AND
      # differ from the computed one (an override with no effect is a stale
      # escape hatch) — either failure raises ValidationError.
      class SourceClass
        CLASSES = %i[granted manual rail_paced restricted public_stable].freeze
        RESTRICTED_LICENSE_CLASSES = %w[research_private restricted].freeze

        Verdict = Data.define(:slug, :klass, :computed, :attic)

        # local/'s top-level entries and their roles (the census's inventory).
        LOCAL_INVENTORY = [
          ["config/", "owner rulings + grants (instance config)"],
          ["shelves/", "enrichment products (the owner shelves)"],
          ["fixtures/", "restricted test samples"],
          ["history.sqlite3", "operational ledger"],
          ["mined-links.sqlite3", "time-heavy mined link layer"]
        ].freeze

        def self.from_config(config)
          new(sources_path: config.sources_path, manual_dir: File.join(Config::PROJECT_ROOT, "docs", "manual"),
              grants_path: config.grants_path, canonical_dir: config.canonical_dir)
        end

        def initialize(sources_path:, manual_dir:, grants_path:, canonical_dir:)
          @sources_path = sources_path
          @manual_dir = manual_dir
          @grants_path = grants_path
          @canonical_dir = canonical_dir
        end

        def verdicts
          registry.slugs.map { |slug| classify(slug) }
        end

        def classify(slug)
          entry = registry[slug] or raise ValidationError, "unknown source: #{slug}"
          computed = compute(entry)
          Verdict.new(slug: slug, klass: override(slug, computed) || computed, computed: computed,
                      attic: attic?(slug))
        end

        # { counts: { class => n } (every class, zeros included),
        #   attic: [slug, ...] }.
        def census
          all = verdicts
          { counts: CLASSES.to_h { |klass| [klass, all.count { |verdict| verdict.klass == klass }] },
            attic: all.select(&:attic).map(&:slug).sort }
        end

        def self.render(census, local_dir:)
          lines = ["reconstruction census — #{census[:counts].values.sum} sources"]
          census[:counts].each { |klass, count| lines << format("  %-14<k>s %5<n>d", k: klass, n: count) }
          lines << "attic (backup-only upstream deletions) — #{census[:attic].size}"
          census[:attic].each { |slug| lines << "  #{slug}" }
          lines << "local/ inventory (#{local_dir})"
          LOCAL_INVENTORY.each do |name, role|
            state = File.exist?(File.join(local_dir, name)) ? "present" : "absent"
            lines << format("  %-20<n>s %-8<s>s %<r>s", n: name, s: state, r: role)
          end
          "#{lines.join("\n")}\n"
        end

        private

        def compute(entry)
          return :granted if granted.include?(entry.slug)
          return :manual if File.file?(File.join(@manual_dir, "#{entry.slug}.md"))
          return :rail_paced if rail_paced?(entry.adapter_class)
          return :restricted if RESTRICTED_LICENSE_CLASSES.include?(entry.manifest.license_class)

          :public_stable
        end

        def override(slug, computed)
          value = raw_rows.dig(slug, "reconstruct")
          return nil if value.nil?

          klass = value.to_s.to_sym
          unless CLASSES.include?(klass)
            raise ValidationError, "source #{slug}: reconstruct: #{value.inspect} is not one of #{CLASSES.join(', ')}"
          end
          if klass == computed
            raise ValidationError, "source #{slug}: reconstruct: #{value} has no effect (already the computed class)"
          end

          klass
        end

        # The Ops::RailPlan roster rule: a Schedule constant, bare or a Spec's.
        def rail_paced?(klass)
          klass.constants(false).any? do |name|
            case klass.const_get(name, false)
            in PacedCrawl::Schedule then true
            in PacedCrawl::Spec => spec then !spec.schedule.nil?
            else false
            end
          end
        end

        def attic?(slug)
          attic = File.join(@canonical_dir.to_s, slug, ".attic")
          File.directory?(attic) && !Dir.empty?(attic)
        end

        def granted
          @granted ||= GrantGate.new(ledger: nil, grants_path: @grants_path).config_grants.map { |g| g["source"] }
        end

        def registry
          @registry ||= SourceRegistry.load(@sources_path)
        end

        def raw_rows
          @raw_rows ||= RegistryTree.load(@sources_path)
        end
      end
    end
  end
end
