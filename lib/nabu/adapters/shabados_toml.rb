# frozen_string_literal: true

module Nabu
  module Adapters
    # Parser family "shabados-toml" (P122-3): the strict TOML SUBSET the
    # Shabad OS database collections are written in — no TOML gem (the
    # dependency budget), and no guessing: the census of every collection
    # file (154,221 files, shabados/shabados database/collections at
    # 307ed9d1, 2026-10-12) found exactly six line shapes, and this reader
    # accepts exactly those:
    #
    #   [table] / [table.sub]           (a nested table)
    #   [[array]]                       (an array-of-tables entry)
    #   key = "basic string"            (escapes \" \\ \n \t \r \uXXXX)
    #   key = 'literal string'
    #   key = 123                       (integer)
    #   key = [ "a", "b" ]              (one-line array of basic strings)
    #
    # plus blank lines and # comments. Anything else raises ParseError
    # naming the file and line — a new upstream shape is classified before
    # it is read, never half-parsed.
    module ShabadosToml
      KEY = /[A-Za-z0-9_-]+/
      BASIC = /"((?:[^"\\]|\\.)*)"/
      TABLE = /\A\[(#{KEY}(?:\.#{KEY})*)\]\z/
      ARRAY_TABLE = /\A\[\[(#{KEY}(?:\.#{KEY})*)\]\]\z/
      ASSIGN = /\A(#{KEY})\s*=\s*(.+)\z/
      ESCAPES = { '"' => '"', "\\" => "\\", "n" => "\n", "t" => "\t", "r" => "\r" }.freeze

      module_function

      def parse(text, path:)
        root = {}
        current = root
        text.each_line.with_index(1) do |raw, number|
          line = raw.strip
          next if line.empty? || line.start_with?("#")

          current = case line
                    when ARRAY_TABLE then append_table(root, Regexp.last_match(1).split("."), path, number)
                    when TABLE then dig_table(root, Regexp.last_match(1).split("."), path, number)
                    when ASSIGN
                      assign(current, Regexp.last_match(1), Regexp.last_match(2), path, number)
                      current
                    else fail!(path, number, "unrecognized line #{line[0, 60].inspect}")
                    end
        end
        root
      end

      def assign(table, key, raw, path, number)
        fail!(path, number, "duplicate key #{key.inspect}") if table.key?(key)
        table[key] = value(raw.strip, path, number)
      end

      def value(raw, path, number)
        case raw
        when /\A#{BASIC}\z/ then unescape(Regexp.last_match(1), path, number)
        when /\A'([^']*)'\z/ then Regexp.last_match(1)
        when /\A[+-]?\d+\z/ then Integer(raw, 10)
        when /\A\[\s*\]\z/ then []
        when /\A\[\s*(#{BASIC}(?:\s*,\s*#{BASIC})*)\s*,?\s*\]\z/
          raw.scan(BASIC).map { |(inner)| unescape(inner, path, number) }
        else fail!(path, number, "unsupported value #{raw[0, 60].inspect}")
        end
      end

      def unescape(inner, path, number)
        inner.gsub(/\\(u\h{4}|U\h{8}|.)/) do
          code = Regexp.last_match(1)
          if code.length > 1 && code.start_with?("u", "U") then [code[1..].hex].pack("U")
          else ESCAPES.fetch(code) { fail!(path, number, "unsupported escape \\#{code}") }
          end
        end
      end

      def dig_table(root, keys, path, number)
        keys.reduce(root) do |table, key|
          node = (table[key] ||= {})
          node = node.last if node.is_a?(Array)
          fail!(path, number, "#{key.inspect} is not a table") unless node.is_a?(Hash)

          node
        end
      end

      def append_table(root, keys, path, number)
        parent = dig_table(root, keys[0..-2], path, number)
        list = (parent[keys.last] ||= [])
        fail!(path, number, "#{keys.last.inspect} is not an array of tables") unless list.is_a?(Array)

        {}.tap { |entry| list << entry }
      end

      def fail!(path, number, message)
        raise Nabu::ParseError, "#{File.basename(path.to_s)}:#{number}: #{message}"
      end
    end
  end
end
