# frozen_string_literal: true

module Nabu
  module Ops
    # `rake boards:check` — the local working boards' numbering self-check.
    # The boards are gitignored working files (.docs/), so this is a LOCAL
    # gate instrument: a checkout without them (any public clone, a lane
    # worktree) gets an announced skip, never a failure.
    #
    # A numbered register carries a header line "Next number: <sigil>X-n."
    # and mints entries "<sigil>X-k". The header goes stale when an entry
    # is minted and the header is not bumped — the next mint then reuses a
    # number. The check: for every register header, every <sigil>X-k
    # mentioned ANYWHERE on the boards (plan docs cite mints before the
    # register row lands) must sit below the header's n. A register that
    # keeps every row it ever minted (numbers 1..max all present — a log)
    # must moreover say exactly max+1: a header that skipped ahead is stale
    # too. Registers that remove ruled rows can only be checked one way.
    class BoardCheck
      # The register sigil (U+2116), from its codepoint: tracked files never
      # carry it literally.
      SIGIL = 0x2116.chr(Encoding::UTF_8)
      HEADER = /^Next number:\s*#{SIGIL}([A-Z]+)-(\d+)/
      MENTION = /#{SIGIL}([A-Z]+)-(\d+)/

      Finding = Data.define(:register, :message)
      Report = Data.define(:skipped, :registers, :findings) do
        def clean? = findings.empty?
      end

      # +boards_dir+ is the .docs/ directory; +exclude+ names subtrees that
      # are archives (their old mentions are history, not mints).
      def initialize(boards_dir:, exclude: %w[old-phases])
        @dir = boards_dir
        @exclude = exclude
      end

      def run
        return Report.new(skipped: true, registers: [], findings: []) unless File.directory?(@dir)

        headers = registers
        mentions = all_mentions
        findings = headers.flat_map do |path, (prefix, next_number)|
          check(path, prefix, next_number, mentions)
        end
        Report.new(skipped: false, registers: headers.keys.map { |path| rel(path) }, findings: findings)
      end

      private

      # { path => [prefix, next_number] } for every top-level board file
      # carrying a header line.
      def registers
        Dir[File.join(@dir, "*.md")].each_with_object({}) do |path, found|
          match = File.read(path, encoding: Encoding::UTF_8).match(HEADER)
          found[path] = [match[1], match[2].to_i] if match
        end
      end

      # { prefix => { number => [rel paths] } } over every board file,
      # header lines excluded (a header names the NEXT number, not a mint).
      def all_mentions
        mentions = Hash.new { |hash, key| hash[key] = Hash.new { |inner, number| inner[number] = [] } }
        board_files.each do |path|
          File.foreach(path, encoding: Encoding::UTF_8) do |line|
            next if line.match?(HEADER)

            line.scan(MENTION) { |prefix, number| mentions[prefix][number.to_i] |= [rel(path)] }
          end
        end
        mentions
      end

      def check(path, prefix, next_number, mentions)
        label = "#{rel(path)} (#{SIGIL}#{prefix}-)"
        numbers = mentions[prefix]
        too_high = numbers.keys.select { |number| number >= next_number }.sort
        unless too_high.empty?
          where = too_high.map { |number| "#{SIGIL}#{prefix}-#{number} (#{numbers[number].first(3).join(', ')})" }
          return [Finding.new(register: label,
                              message: "header says Next number #{SIGIL}#{prefix}-#{next_number} but " \
                                       "#{where.join('; ')} already minted — bump the header past " \
                                       "#{SIGIL}#{prefix}-#{too_high.max}")]
        end
        own = own_numbers(path, prefix)
        max = own.max || 0
        return [] unless own.any? && (1..max).all? { |number| own.include?(number) } && next_number != max + 1

        [Finding.new(register: label,
                     message: "a keep-every-row register (#{SIGIL}#{prefix}-1..#{max} all present) must say " \
                              "Next number #{SIGIL}#{prefix}-#{max + 1}, not -#{next_number}")]
      end

      # The numbers a register's own entry headings carry.
      def own_numbers(path, prefix)
        File.read(path, encoding: Encoding::UTF_8)
            .scan(/^#+\s*#{SIGIL}#{prefix}-(\d+)/).flatten.map(&:to_i)
      end

      def board_files
        Dir[File.join(@dir, "**", "*.md")].reject do |path|
          @exclude.any? { |sub| rel(path).start_with?("#{sub}/") }
        end
      end

      def rel(path) = path.delete_prefix("#{@dir}/")
    end
  end
end
