# frozen_string_literal: true

require "json"

module Nabu
  module Scansion
    # The validation harness (P152): the scanner run over every passage the
    # HELD metrical gold covers — pedecerto's Latin H/P lines, hypotactic's
    # Greek dactylic hexameters and pentameters (the P44 meter layer in the
    # catalog's enrichments table) — and its verdict compared with the
    # gold's, line by line. Read-only on the catalog; writes nothing.
    #
    # == What is compared
    #
    # The feet: hexameter feet 1-5 as D/S (pedecerto's 4-letter pattern
    # implies a fifth-foot dactyl, its 5-letter one names the spondeiazon;
    # hypotactic's "-uu --" quantity string is parsed into feet), the
    # pentameter's first-hemiepes pair (the second half is fixed). A
    # scanned line AGREES when meter and feet both match; the scanner's
    # meter is its own finding (it tries both templates), never read from
    # the gold. Greek additionally compares SYLLABLE quantities (final
    # anceps excluded) where the syllable counts meet.
    #
    # == The dev split (declared before the first measurement)
    #
    # DEV_SET is the slice the rules were developed against — Aeneid 1,
    # Amores 1, Iliad 1 — and is reported apart from the HELD-OUT rest, so
    # a reader can see whether the rules were fitted to their test set.
    # Nothing is tuned on the held-out numbers.
    class GoldCheck
      DEV_SET = [
        ["urn:cts:latinLit:phi0690.phi003.", "1."], # Vergil, Aeneid 1
        ["urn:cts:latinLit:phi0959.phi001.", "1."], # Ovid, Amores 1
        ["urn:cts:greekLit:tlg0012.tlg001.", "1."]  # Homer, Iliad 1
      ].freeze

      GOLD_MODELS = %w[pedecerto hypotactic].freeze
      BATCH = 5_000

      # The gold reading of one meter enrichment: [meter, feet, quantities]
      # (quantities only from hypotactic), or nil when the row is not
      # dactylic gold this lane scans (another meter, "not scanned", an
      # unparseable pattern).
      def self.decode(model, payload)
        meter = payload["meter"].to_s
        pattern = payload["pattern"].to_s
        case model
        when "pedecerto" then decode_pedecerto(meter, pattern)
        when "hypotactic" then decode_hypotactic(meter, pattern)
        end
      end

      def self.decode_pedecerto(meter, pattern)
        case meter
        when "H"
          return nil unless pattern.match?(/\A[DS]{4,5}\z/)

          [:hexameter, pattern.size == 4 ? "#{pattern}D" : pattern, nil]
        when "P"
          return nil unless pattern.match?(/\A[DS]{2}-\|DD-\z/)

          [:pentameter, pattern[0, 2], nil]
        end
      end

      def self.decode_hypotactic(meter, pattern)
        quantities = pattern.delete(" ")
        return nil unless quantities.match?(/\A[-u]+\z/)

        meter, count, tail = HYPOTACTIC_SHAPES[meter]
        return nil unless meter

        feet, rest = feet_from(quantities, count)
        feet && tail.match?(rest) ? [meter, feet, quantities] : nil
      end

      # hypotactic meter name => [meter, variable feet, the fixed tail]
      # (hexameter: the sixth foot; pentameter: the half-line long, the
      # fixed second hemiepes and its final anceps).
      HYPOTACTIC_SHAPES = {
        "dactylic hexameter" => [:hexameter, 5, /\A-[-u]\z/],
        "dactylic pentameter" => [:pentameter, 2, /\A--uu-uu[-u]\z/]
      }.freeze

      # Parse +count+ leading feet ("-uu" D / "--" S) off a quantity
      # string → [feet, rest], or nil when it is not dactylic there.
      def self.feet_from(quantities, count)
        feet = +""
        i = 0
        count.times do
          if quantities[i, 3] == "-uu"
            feet << "D"
            i += 3
          elsif quantities[i, 2] == "--"
            feet << "S"
            i += 2
          else
            return nil
          end
        end
        [feet, quantities[i..]]
      end

      def self.dev?(urn)
        DEV_SET.any? do |work, citation|
          urn.start_with?(work) && urn.split(":").last.start_with?(citation)
        end
      end

      # Per (language, gold meter, split) counters.
      class Tally
        attr_reader :lines, :agree, :disagree, :wrong_meter, :unscanned, :by_basis, :syllables_compared,
                    :syllables_agree

        def initialize
          @lines = 0
          @agree = 0
          @disagree = 0
          @wrong_meter = 0
          @unscanned = Hash.new(0)
          @by_basis = Hash.new { |h, k| h[k] = [0, 0] } # basis => [scanned, agree]
          @syllables_compared = 0
          @syllables_agree = 0
        end

        def add(gold, result)
          @lines += 1
          return @unscanned[result.reason] += 1 unless result.scanned?

          hit = result.meter == gold[0] && result.feet == gold[1]
          hit ? @agree += 1 : @disagree += 1
          @wrong_meter += 1 if result.meter != gold[0]
          @by_basis[result.basis][0] += 1
          @by_basis[result.basis][1] += 1 if hit
          compare_syllables(gold[2], result.quantities)
        end

        def scanned = @agree + @disagree

        def precision = scanned.zero? ? nil : @agree.fdiv(scanned)

        def coverage = @lines.zero? ? nil : scanned.fdiv(@lines)

        def agreement = @lines.zero? ? nil : @agree.fdiv(@lines)

        def merge!(other)
          @lines += other.lines
          @agree += other.agree
          @disagree += other.disagree
          @wrong_meter += other.wrong_meter
          other.unscanned.each { |reason, n| @unscanned[reason] += n }
          other.by_basis.each do |basis, (s, a)|
            @by_basis[basis][0] += s
            @by_basis[basis][1] += a
          end
          @syllables_compared += other.syllables_compared
          @syllables_agree += other.syllables_agree
          self
        end

        private

        def compare_syllables(gold_quantities, quantities)
          return unless gold_quantities && gold_quantities.size == quantities.size

          @syllables_compared += quantities.size - 1
          @syllables_agree += (0...(quantities.size - 1)).count { |i| gold_quantities[i] == quantities[i] }
        end
      end

      Report = Data.define(:tallies, :seconds, :gold_rows, :skipped_rows) do
        # [language, meter, split] => Tally, plus merged views.
        def total(language: nil, meter: nil, split: nil)
          tallies.each_with_object(Tally.new) do |(key, tally), acc|
            next if language && key[0] != language
            next if meter && key[1] != meter
            next if split && key[2] != split

            acc.merge!(tally)
          end
        end

        def lines_per_second = seconds.positive? ? total.lines / seconds : nil
      end

      def initialize(catalog:)
        @catalog = catalog
      end

      # Scan every gold-covered passage (optionally only +language+, or only
      # one +split+ — :dev while developing rules, so the held-out numbers
      # are never looked at mid-development); +progress+ is called with the
      # running row count every batch; +on_line+ (urn, gold, result) sees
      # every compared line (the CLI's --show-misses).
      def run(language: nil, split: nil, progress: nil, on_line: nil)
        tallies = Hash.new { |h, k| h[k] = Tally.new }
        rows = skipped = 0
        seconds = 0.0
        each_gold_row(language) do |row|
          rows += 1
          progress&.call(rows) if (rows % BATCH).zero?
          line_split = self.class.dev?(row[:urn]) ? :dev : :held_out
          next if split && line_split != split

          gold = self.class.decode(row[:model], JSON.parse(row[:payload_json].to_s))
          next skipped += 1 unless gold

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = Scansion.scan(row[:text], language: row[:language])
          seconds += Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          tallies[[row[:language], gold[0], line_split]].add(gold, result)
          on_line&.call(row[:urn], row[:text], gold, result)
        end
        Report.new(tallies: tallies, seconds: seconds, gold_rows: rows, skipped_rows: skipped)
      end

      private

      # Keyset-paged gold rows joined to their live passage text.
      def each_gold_row(language, &block)
        last = 0
        loop do
          batch = gold_dataset(language).where { Sequel[:enrichments][:id] > last }.limit(BATCH).all
          break if batch.empty?

          batch.each(&block)
          last = batch.last[:id]
        end
      end

      def gold_dataset(language)
        dataset = @catalog[:enrichments]
                  .join(:passages, id: Sequel[:enrichments][:passage_id])
                  .where(Sequel[:enrichments][:kind] => "meter", Sequel[:enrichments][:model] => GOLD_MODELS)
                  .where(Sequel[:passages][:withdrawn] => false)
                  .order(Sequel[:enrichments][:id])
                  .select(Sequel[:enrichments][:id], Sequel[:enrichments][:model], Sequel[:enrichments][:payload_json],
                          Sequel[:passages][:urn], Sequel[:passages][:text], Sequel[:passages][:language])
        language ? dataset.where(Sequel[:passages][:language] => language) : dataset
      end
    end
  end
end
