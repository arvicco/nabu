# frozen_string_literal: true

module Nabu
  module Scansion
    # The metrical templates and the fit (P152). A template is one slot per
    # syllable — :L (a long position), :S (a short one), :X (the line-final
    # anceps). A syllable FITS a slot unless the rules made it :short where
    # the slot is :L, or :long where it is :S; an :anceps syllable fits
    # anything. The syllable count alone fixes how many dactyls a line has,
    # so the fit is a placement question, answered exhaustively (32
    # hexameter templates, 4 pentameter ones — no search heuristics).
    #
    # == Hard constraints vs metrical laws
    #
    # Hard: the slot fit, and the pentameter's central diaeresis (a word
    # must end after the first half's closing long — the rule Latin and
    # Greek elegists keep without exception that matters here). When more
    # than one template survives, the classical hexameter LAWS rank them:
    # a fifth-foot spondee (the rare spondeiazon) costs one, a line with no
    # main caesura (penthemimeral, feminine third-foot, or hephthemimeral)
    # costs one. A unique minimum scans with basis :laws. A tie left there
    # goes to the last tier, the grammar DEFAULTS (Latin final-syllable
    # rules, Scansion::Latin): the fit contradicting fewest of them, if
    # unique, scans with basis :defaults. A tie at the end stays
    # :ambiguous — unscanned.
    module Meters
      HEXAMETER = :hexameter
      PENTAMETER = :pentameter
      ALL = [HEXAMETER, PENTAMETER].freeze

      DACTYL = %i[L S S].freeze
      SPONDEE = %i[L L].freeze

      # One template: the meter, its D/S feet string, the slots, the slot
      # index after which the template demands (pentameter) or prefers
      # (hexameter caesurae) a word end, and the foot boundaries.
      Template = Data.define(:meter, :feet, :slots, :diaeresis, :caesurae)

      # One surviving fit: the template, its law violations, and how many
      # grammar defaults it contradicts (the last tie-break tier).
      Fit = Data.define(:template, :violations, :misses)

      module_function

      def templates(meter)
        @templates ||= {}
        @templates[meter] ||= case meter
                              when HEXAMETER then hexameter_templates
                              when PENTAMETER then pentameter_templates
                              else raise ArgumentError, "unknown meter #{meter.inspect}"
                              end
      end

      # Every template of +meter+ the syllables fit, with its law cost.
      def fits(syllables, meter:)
        templates(meter).filter_map do |template|
          next unless template.slots.size == syllables.size
          next unless slots_fit?(template.slots, syllables)
          next if template.diaeresis && !syllables[template.diaeresis].word_final

          Fit.new(template: template, violations: violations(template, syllables),
                  misses: default_misses(template.slots, syllables))
        end
      end

      # The verdict over +meters+: a Result (scanned, or unscanned with the
      # reason). See the module note for the ranking.
      def choose(syllables, meters: ALL)
        all = meters.flat_map { |meter| fits(syllables, meter: meter) }
        return Result.unscanned(:no_fit, syllables: syllables) if all.empty?

        by_laws = minimal(all, &:violations)
        best = minimal(by_laws, &:misses)
        if best.size > 1
          reason = best.map { |fit| fit.template.meter }.uniq.size > 1 ? :ambiguous_meter : :ambiguous
          return Result.unscanned(reason, syllables: syllables)
        end

        template = best.first.template
        basis = if all.size == 1 then :unique
                elsif by_laws.size == 1 then :laws
                else :defaults
                end
        Result.new(status: :scanned, meter: template.meter, feet: template.feet,
                   quantities: template.slots.map { |slot| slot == :S ? "u" : "-" }.join,
                   basis: basis, reason: nil, syllables: syllables)
      end

      def minimal(fits, &cost)
        least = fits.map(&cost).min
        fits.select { |fit| cost.call(fit) == least }
      end

      # Slots whose quantity contradicts a syllable's grammar default.
      def default_misses(slots, syllables)
        slots.each_with_index.count do |slot, i|
          default = syllables[i].default
          (slot == :L && default == :short) || (slot == :S && default == :long)
        end
      end

      def slots_fit?(slots, syllables)
        slots.each_with_index.all? do |slot, i|
          quantity = syllables[i].quantity
          !((slot == :L && quantity == :short) || (slot == :S && quantity == :long))
        end
      end

      def violations(template, syllables)
        return 0 unless template.meter == HEXAMETER

        cost = template.feet[4] == "S" ? 1 : 0
        cost += 1 unless template.caesurae.any? { |i| syllables[i].word_final }
        cost
      end

      # Feet 1-5 dactyl or spondee, the sixth a long + the final anceps.
      # Caesura slots: after the third foot's long (penthemimeral), after
      # its first short when it is a dactyl (feminine), after the fourth
      # foot's long (hephthemimeral).
      def hexameter_templates
        %w[D S].repeated_permutation(5).map do |feet|
          slots = []
          starts = []
          feet.each do |foot|
            starts << slots.size
            slots.concat(foot == "D" ? DACTYL : SPONDEE)
          end
          caesurae = [starts[2], starts[3]]
          caesurae << (starts[2] + 1) if feet[2] == "D"
          Template.new(meter: HEXAMETER, feet: feet.join, slots: slots + %i[L X],
                       diaeresis: nil, caesurae: caesurae)
        end
      end

      # Two hemiepes: (D|S)(D|S) L ‖ D D X — the second half admits no
      # spondee, and a word ends at the ‖.
      def pentameter_templates
        %w[D S].repeated_permutation(2).map do |feet|
          first = feet.flat_map { |foot| foot == "D" ? DACTYL : SPONDEE } + [:L]
          Template.new(meter: PENTAMETER, feet: feet.join, slots: first + DACTYL + DACTYL + [:X],
                       diaeresis: first.size - 1, caesurae: [])
        end
      end
    end
  end
end
