# frozen_string_literal: true

require "strscan"

module Nabu
  module Adapters
    # The corph-sql parser family (P25-0): a streaming walker over a
    # MySQL/phpMyAdmin dump's `INSERT INTO … VALUES (…), (…);` statements —
    # the bulk carrier of CorPH (Corpus PalaeoHibernicum), whose canonical
    # artifact is the 39 MB `chronhibdev_2020.sql` in the ChronHib website
    # repo. A standalone, individually tested component the Corph adapter
    # composes, sibling to the other parser families.
    #
    # == Scope: INSERT walking, not SQL
    #
    # The walker understands exactly what the dump carries: `INSERT INTO
    # `TABLE` (`col`, …) VALUES` headers followed by parenthesised tuples
    # separated by commas and terminated by a semicolon. Everything else
    # (CREATE TABLE, SET, comments) is skipped by line shape. No SQL is ever
    # evaluated. One row = one { column name => value } hash, keyed by the
    # statement's own column list.
    #
    # == Streaming (never slurp)
    #
    # The file is read line by line (File.foreach); only the current —
    # possibly multi-line — tuple is buffered. Values in the real dump escape
    # newlines as \r\n, so tuples are one line each in practice, but the
    # scanner tolerates a tuple spanning lines rather than betting on it.
    #
    # == Value decoding
    #
    # SQL NULL → nil; bare integers → Integer; quoted strings decode the
    # MySQL escapes (\' \" \\ \n \r \t \0 \Z, plus '' for a quote; an
    # unknown escape yields the escaped character itself, MySQL's own rule).
    # Text arrives VERBATIM — NFC normalization is the adapter's boundary
    # job, not the walker's.
    #
    # Damage (a header without a column list, an unterminated statement or
    # string at EOF) raises Nabu::ParseError naming the file.
    class CorphSqlParser
      ESCAPES = {
        "n" => "\n", "r" => "\r", "t" => "\t", "0" => "\0",
        "Z" => "\x1a", "b" => "\b"
      }.freeze

      def initialize(path)
        @path = path
      end

      # Yield one { column => value } hash per row of +table+, in dump order,
      # across every INSERT statement for that table (phpMyAdmin chunks large
      # tables into many). Without a block, returns an Enumerator.
      def each_row(table, &block)
        return enum_for(:each_row, table) unless block

        prefix = "INSERT INTO `#{table}`"
        columns = nil
        buffer = +""
        File.foreach(@path) do |line|
          if columns.nil?
            next unless line.start_with?(prefix)

            columns = statement_columns(line)
            buffer = +(line[/VALUES\s*(.*)\z/m, 1] || "")
          else
            buffer << line
          end
          columns = nil if drain(buffer, columns, &block) == :done
        end
        return if columns.nil?

        raise ParseError, "#{@path}: unterminated INSERT INTO `#{table}` statement (truncated dump?)"
      end

      private

      def statement_columns(line)
        list = line[/\AINSERT INTO `\w+` \(([^)]*)\) VALUES/, 1]
        raise ParseError, "#{@path}: INSERT without a column list: #{line[0, 80].inspect}" if list.nil?

        list.split(",").map { |column| column.strip.delete("`") }
      end

      # Consume every COMPLETE tuple currently in +buffer+, yielding each as
      # a column-keyed hash; keep any incomplete tail for the next line.
      # Returns :done when the statement's ";" terminator was consumed.
      def drain(buffer, columns)
        scanner = StringScanner.new(buffer)
        outcome = :more
        loop do
          scanner.skip(/\s+/)
          break if scanner.eos?

          mark = scanner.pos
          values = scan_tuple(scanner)
          if values.nil? # incomplete tuple: wait for the next line
            scanner.pos = mark
            break
          end
          yield columns.zip(values).to_h
          scanner.skip(/\s*/)
          case scanner.getch
          when ";" then outcome = :done
          when "," then next
          when nil then break # separator arrives with the next line
          else raise ParseError, "#{@path}: malformed row separator in INSERT statement"
          end
          break if outcome == :done
        end
        buffer.replace(outcome == :done ? "" : scanner.rest)
        outcome
      end

      # One "(v, v, …)" tuple → its decoded values, or nil when the buffer
      # ends before the tuple closes (the caller waits for more input).
      def scan_tuple(scanner)
        return nil unless scanner.scan("(")

        values = []
        loop do
          scanner.skip(/\s+/)
          value = scanner.peek(1) == "'" ? scan_string(scanner) : scan_bare(scanner)
          return nil if value == :incomplete

          values << value
          scanner.skip(/\s+/)
          case scanner.getch
          when ")" then return values
          when "," then next
          else return nil # nil (end of buffer) or damage caught by drain
          end
        end
      end

      # A quoted string with MySQL escapes; :incomplete when the closing
      # quote has not arrived yet.
      def scan_string(scanner)
        scanner.getch # the opening quote
        value = +""
        loop do
          value << scanner.scan(/[^'\\]*/)
          if scanner.scan(/\\(.)/m)
            value << ESCAPES.fetch(scanner[1], scanner[1])
          elsif scanner.scan("''")
            value << "'"
          elsif scanner.scan("'")
            return value
          else
            return :incomplete # end of buffer inside the string
          end
        end
      end

      # A bare (unquoted) value: NULL → nil, integers native, anything else
      # (floats, hex) kept as its raw string. :incomplete only when the
      # buffer ends without a terminator (the tuple is still open).
      def scan_bare(scanner)
        raw = scanner.scan(/[^,)]*/).strip
        return :incomplete if scanner.eos?
        return nil if raw == "NULL"

        raw.match?(/\A-?\d+\z/) ? Integer(raw, 10) : raw
      end
    end
  end
end
