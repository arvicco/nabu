# frozen_string_literal: true

require "io/console"
require "thor"
require_relative "version"
require_relative "display"
require_relative "duration_format"
require_relative "cli/data"
require_relative "cli/lect"
require_relative "cli/layer"
require_relative "cli/index"
require_relative "cli/creds"
require_relative "cli/export"

# CLI flag conventions (P90-3 standing rules, applied whenever a command is
# next touched — never as a sweep):
#   ① `--lang` is the ONE language-filter spelling, accepting a comma list
#      where plural makes sense; legacy spellings (`--langs`, `--languages`)
#      stay as quiet aliases of it.
#   ② `--json` is the machine-readable opt-in convention (`--format` is
#      reserved for commands with more than two real formats).
module Nabu
  # Command-line entry point. Only `version` is functional in Phase 0; the
  # ingest/query subcommands are stubs that report "not implemented" and exit 1
  # so scripts and CI can rely on the failure signal before the real work lands.
  class CLI < Thor
    include DurationFormat

    # The DataCLI namespace note applies at the root too: without it Thor
    # 1.5's `tree` labels its root with the class auto-namespace ("nabu:c_l_i").
    namespace "nabu"

    # The tag-semantics note the axis-grouped surfaces (`list --axis`,
    # `status --axis`, P35-1) state ONCE: axes are TAGS over the source list,
    # so a source appears under every axis it serves — never a folder owning it.
    AXIS_TAG_NOTE = "Axes are tags, not folders — a source appears under every desk it serves."

    # Raise Thor::Error (rather than aborting the process abruptly) so failures
    # surface a clean stderr message and a non-zero exit status.
    def self.exit_on_failure?
      true
    end

    # `nabu search --help` (owner report 2026-07-18): this Thor build does
    # not intercept a help flag AFTER a command name, so "--help" reached
    # FTS5 as the literal query. Route `nabu CMD --help|-h` to `nabu help
    # CMD` for every known command; a literal "--help" stays searchable via
    # quoting inside a longer query (the fts literal fallback).
    def self.start(given_args = ARGV, config = {})
      if Thor::HELP_MAPPINGS.include?(given_args[1]) &&
         all_commands.key?(normalize_command_name(given_args.first.to_s))
        given_args = ["help", given_args.first]
      end
      # P44-i1b: a ^C is an OPERATOR DECISION, not a crash — one honest line
      # and the conventional 130, never a thread-backtrace storm. (Open3's
      # internal reader threads also die noisily at interrupt; bin/nabu turns
      # their report_on_exception chatter off.) State safety is the atomic
      # fetchers' job — an interrupted acquisition leaves staging debris the
      # next run sweeps, announced.
      super
    rescue Interrupt
      warn "\ninterrupted — partial work is staged safely; the next run cleans up and starts fresh."
      exit 130
    end

    # The --display flag, shared by every command that renders passage text to
    # the terminal (P27-0: show, align, search, concord, parallels, cognates).
    # Modes come from the Nabu::Display registry so sibling packets can add
    # modes (reading, …) without touching this declaration.
    def self.display_option
      option :display, type: :string, default: Nabu::Display::DEFAULT_MODE, banner: "MODE",
                       desc: "Display mode: default (config/display.yml policies), " \
                             "full (every stored byte, no transforms), plain (strip all " \
                             "defined mark classes), reading (edition apparatus simplified, " \
                             "qere read), diplomatic (edition marks as stored), " \
                             "translit (romanized rendering), " \
                             "mono (default without token colors) — see docs/display.md"
    end

    desc "version", "Print the Nabu version"
    def version
      say Nabu::VERSION
    end

    desc "data SUBCOMMAND ...ARGS", "The nabu-data production rail: document and build publishable derived datasets"
    subcommand "data", DataCLI

    desc "lect SUBCOMMAND ...ARGS", "Per-document lect rulings: the journaled overlay tier of lect resolution"
    subcommand "lect", LectCLI

    desc "creds SUBCOMMAND ...ARGS", "Stored upstream credentials (gated member areas): set, list"
    subcommand "creds", CredsCLI

    # P61-2: `nabu layer` is the core-layers front door — today one
    # command, `suggest`, the generalized census (lect + dating + places +
    # script sections). `nabu lect suggest` stays as the historical alias;
    # both run the same report.
    desc "layer SUBCOMMAND ...ARGS", "Core-layer postures: the generalized suggest front door"
    subcommand "layer", LayerCLI

    # P112-3: the fulltext-index operations surface — gauges,
    # freshness stamps, and the standalone merge consolidation.
    desc "index SUBCOMMAND ...ARGS", "Fulltext-index operations: doctor (gauges + freshness)"
    subcommand "index", IndexCLI

    # P121-1: `nabu export` is a command family — the research tables
    # (documents, links: a file + license manifest under exports/) and the
    # passage stream, which stays the DEFAULT command so `nabu export
    # --format jsonl ...` is byte-unchanged (ExportCLI).
    desc "export SUBCOMMAND ...ARGS",
         "Research exports — documents/links tables with a license manifest — and the passage stream"
    subcommand "export", ExportCLI

    no_commands do
      def pluralize(count, noun) = "#{count} #{noun}#{'s' unless count == 1}"

      def plural(count, noun)
        "#{count} #{noun}#{'s' unless count == 1}"
      end

      # Open the fulltext index for reading; nil when the file is absent OR the
      # FTS table was never built (both mean "no index" → the sync/rebuild hint).
      def open_fulltext(config)
        return nil unless File.exist?(config.fulltext_path)

        db = Nabu::Store.connect_fulltext(config.fulltext_path)
        return db if db.table_exists?(Nabu::Store::Indexer::TABLE)

        db.disconnect
        nil
      end

      # Group an integer's digits into thousands (12345 → "12,345"). Plain string
      # work — no locale gem for one display nicety.
      def commafy(number)
        number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      # One display line of pristine text: newlines flattened, capped at 100
      # chars (treebank sentences are single lines; the cap guards outliers).
      def truncate_line(text, max = 100)
        line = text.tr("\n", " ")
        line.length > max ? "#{line[0, max]}…" : line
      end

      def commas(count)
        count.to_s.gsub(/\B(?=(\d{3})+\z)/, ",")
      end

      # Wrap prose to the card's width, every line indented.
      def say_wrapped(text, indent:, width: 78)
        pad = " " * indent
        line = +""
        text.split(/\s+/).each do |word|
          if line.empty?
            line << word
          elsif pad.length + line.length + 1 + word.length > width
            say "#{pad}#{line}"
            line = +word
          else
            line << " " << word
          end
        end
        say "#{pad}#{line}" unless line.empty?
      end

      # Open the catalog db for reading if it has been built; nil otherwise so
      # status degrades gracefully to registry-only output.
      def open_catalog(config)
        return nil unless File.exist?(config.catalog_path)

        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.setup!(db)
        db
      end

      # Open the catalog for writing, creating + migrating it if this is the
      # first sync before any rebuild. Migrations are idempotent (only pending
      # ones run), so this is safe on an existing db too. Callers that also
      # open the ledger MUST open it first (open_or_create_ledger lifts a
      # pre-P7-1 catalog's history before migration 005 drops those tables).
      def open_or_create_catalog(config)
        require "fileutils"
        FileUtils.mkdir_p(File.dirname(config.catalog_path))
        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.migrate!(db)
        Nabu::Store.setup!(db)
        db
      end

      # Open the history ledger for reading; nil when absent (fresh machine —
      # read paths treat that as empty history) or not yet migrated.
      def open_ledger(config)
        return nil unless File.exist?(config.history_path)

        db = Nabu::Store::Ledger.connect(config.history_path)
        return Nabu::Store::Ledger.setup!(db) if db.table_exists?(:runs)

        db.disconnect
        nil
      end

      # Open the history ledger for writing: create + migrate it, and lift a
      # pre-P7-1 catalog's runs/pins/baselines into it (one-shot; the catalog
      # is then migrated forward, dropping the moved tables).
      def open_or_create_ledger(config)
        Nabu::Store::Ledger.open_with_lift!(
          history_path: config.history_path, catalog_path: config.catalog_path
        )
      end
    end
  end
end

# The CLI command areas (pure carve-outs of the one CLI class above).
require_relative "cli/sync"
require_relative "cli/census"
require_relative "cli/profile"
require_relative "cli/admin"
require_relative "cli/query"
require_relative "cli/links"
require_relative "cli/enrich"
require_relative "cli/lexicon"
require_relative "cli/signs"
require_relative "cli/reference"
require_relative "cli/passage_display"
require_relative "cli/progress"
