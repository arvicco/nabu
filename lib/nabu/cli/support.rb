# frozen_string_literal: true

# Nabu::CLI — shared helpers: store openers and small formatting utilities.
# Carved out of lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
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
