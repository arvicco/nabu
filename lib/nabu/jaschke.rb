# frozen_string_literal: true

require_relative "errors"
require_relative "normalize"
require_relative "xct"

module Nabu
  # Jäschke's romanisation of Tibetan (A Tibetan-English Dictionary, London
  # 1881) ↔ Unicode Tibetan. The print gives every headword twice — script
  # and romanisation — so this converter is the cross-check oracle for a
  # transcription of the jaschke-1881 scan (#agree?: does a transcribed
  # script form match its transcribed romanisation?) and a search fold for
  # romanised queries (#fold, and #to_ewts onto the house Tibetan fold,
  # Nabu::Xct).
  #
  # == The system, as printed (read off the scan, pp. 1–2 and the key)
  #
  # - aspirates carry the spiritus asper, U+0314: k̔ ཁ, t̔ ཐ, p̔ ཕ, ts̔ ཚ,
  #   c̀̔ ཆ, ṭ̔ ཋ;
  # - the palatal series carries a grave: c̀ ཅ, j̀ ཇ, s̀ ཤ, z̀ ཞ (input also
  #   takes ś š ṡ, ź ž ż, č ć ċ, ǰ — the common substitutions);
  # - ṅ ང, ny ཉ (ñ accepted), ṭ ḍ ṇ ṣ the retroflex letters;
  # - γ (Greek gamma) is the PREFIXED g: γyag གཡག against gyag གྱག;
  # - the ring ˳ is the a-chung: ˳bráṅs འབྲངས, ˳o འོ (° and a combining
  #   ring below accepted);
  # - a macron is the a-chung below the letter: kā ཀཱ, kī ཀཱི;
  # - the acute (and any grave on a vowel) is stress — prosodic, folded away;
  # - the closing a-chung of a prefixed open syllable is not written
  #   (dga དགའ, mk̔a མཁའ), nor the a-chung of the particles (kai ཀའི);
  # - the wa-zur is w (the print's own parenthesis also writes kva).
  #
  # Lenient input on top: plain "kh th ph ch tsh sh zh" read as the aspirate
  # and palatal letters, ' after a consonant as the spiritus, v as w; Skt
  # gh dh bh ḍh dzh as the h-stacks. Unhyphenated runs ("ka-lan-taka",
  # "kara") split onset-first, preferring a native coda.
  #
  # == Ambiguity: alternatives, never a guess
  #
  # #to_tibetan returns EVERY reading the romanisation admits, the native
  # reading first:
  # - a closing ṅ or m may be the anusvāra ཾ — the print itself spells
  #   kaṅ-ka both ཀཾ་ཀ (p. 1) and ཀང་ཀ (p. 2), and kam-po-rtse ཀཾ་པོ་རྩེ;
  # - "ai"/"au" may be the particle (kai ཀའི) or the vowel sign (ཀཻ — the
  #   Sanskrit vowel);
  # - #from_tibetan returns both readings of the anusvāra (ṅ, m).
  # What the romanisation cannot carry at all is out of reach by design:
  # Sanskrit conjuncts written as one stack across a syllable break render
  # as tsheg-separated syllables.
  module Jaschke
    class Error < Nabu::Error; end

    BASE = Xct::CONSONANTS.reject { |char, _| char == Xct::CARRIER }.to_h { |char, code| [code, char] }.freeze
    SUBJOINED = Xct::SUBJOINED.to_h { |char, code| [code, char] }.freeze
    CARRIER = Xct::CARRIER
    TSHEG = "་"
    A_CHUNG = "འ"
    LONG = "\u0F71"
    ANUSVARA = "\u0F7E"
    SIGNS = { "i" => "\u0F72", "u" => "\u0F74", "e" => "\u0F7A", "o" => "\u0F7C",
              "ai" => "\u0F7B", "au" => "\u0F7D" }.freeze

    # The h-stacks of the Sanskrit aspirates: code → [base code, "h"].
    H_STACKS = { "gh" => "g", "dh" => "d", "bh" => "b", "Dh" => "D", "dzh" => "dz" }.freeze

    PREFIX_PAIRS = Xct::PREFIX_PAIRS
    SUPERSCRIPTS = {
      "r" => %w[k g ng j ny t d n b m ts dz],
      "l" => %w[k g ng c j t d p b h],
      "s" => %w[k g ng ny t d n p b m ts]
    }.freeze
    SUBSCRIPTS = {
      "y" => %w[k kh g p ph b m h],
      "r" => %w[k kh g t th d p ph b m s h],
      "l" => %w[k g b z r s],
      "w" => %w[k kh g c ny t d ts tsh zh z r l sh s h]
    }.freeze
    SUFFIXES = Xct::SUFFIXES
    POSTSUFFIXES = Xct::POSTSUFFIXES

    # Canonical Jäschke spelling per code (the fold's output alphabet).
    ROMAN = {
      "k" => "k", "kh" => "k̔", "g" => "g", "G" => "γ", "ng" => "ṅ", "c" => "c̀", "ch" => "c̀̔",
      "j" => "j̀", "ny" => "ny", "t" => "t", "th" => "t̔", "d" => "d", "n" => "n", "p" => "p",
      "ph" => "p̔", "b" => "b", "m" => "m", "ts" => "ts", "tsh" => "ts̔", "dz" => "dz", "w" => "w",
      "zh" => "z̀", "z" => "z", "'" => "\u02F3", "y" => "y", "r" => "r", "l" => "l", "sh" => "s̀",
      "s" => "s", "h" => "h", "T" => "ṭ", "Th" => "ṭ̔", "D" => "ḍ", "Dh" => "ḍh", "N" => "ṇ",
      "Sh" => "ṣ", "gh" => "gh", "dh" => "dh", "bh" => "bh", "dzh" => "dzh"
    }.freeze

    # EWTS (Nabu::Xct output) → Jäschke, longest match first; "M" (the
    # anusvāra) is the one value with two readings.
    EWTS_ROMAN = {
      "tsh" => "ts̔", "ts" => "ts", "dz" => "dz", "kh" => "k̔", "ch" => "c̀̔", "th" => "t̔",
      "ph" => "p̔", "zh" => "z̀", "sh" => "s̀", "ng" => "ṅ", "ny" => "ny", "Th" => "ṭ̔",
      "Dh" => "ḍh", "Sh" => "ṣ", "~M" => %w[ṅ m], "c" => "c̀", "j" => "j̀", "T" => "ṭ",
      "D" => "ḍ", "N" => "ṇ", "A" => "ā", "I" => "ī", "U" => "ū", "M" => %w[ṅ m], "H" => "ḥ"
    }.freeze
    EWTS_TOKEN = Regexp.union(EWTS_ROMAN.keys.sort_by { |key| -key.length })

    SPIRITUS_MARKS = %W[\u0314 \u0313 \u0315].freeze
    SPIRITUS_LETTERS = ["\u02BD", "\u02BB", "\u02BC", "\u2018", "\u2019", "'"].freeze
    RING_LETTERS = ["\u02F3", "\u00B0", "\u02DA"].freeze
    PALATAL_MARKS = %W[\u0300 \u0301 \u030C \u0307].freeze
    SEPARATOR = /[-\s.་]/
    VOWELS = %w[a i u e o].freeze

    Syllable = Data.define(:onset, :vowel, :long, :second, :coda)
    Onset = Data.define(:prefix, :super, :root, :subs)

    module_function

    # The canonical Jäschke spelling of +roman+: stress folded away, the
    # mark variants unified (ś š → s̀, č → c̀, ' → spiritus, ° → ˳),
    # lowercased, NFC — the search key for romanised text.
    def fold(roman)
      chunks(roman).map do |chunk|
        chunk.map { |token| token.is_a?(String) ? ROMAN.fetch(token) : render_vowel(token) }.join
      end.join("-").unicode_normalize(:nfc)
    end

    # Every Unicode Tibetan reading of +roman+, the native reading first
    # (see the class comment for the ambiguities). Raises Jaschke::Error on
    # input outside the system.
    def to_tibetan(roman)
      per_syllable = chunks(roman).flat_map { |chunk| syllables(chunk) }.map { |syl| syllable_readings(syl) }
      raise Error, "nothing to convert in #{roman.inspect}" if per_syllable.empty?

      first, *rest = per_syllable
      first.product(*rest).map { |parts| Normalize.nfc(parts.join(TSHEG)) }.uniq
    end

    def unambiguous?(roman) = to_tibetan(roman).size == 1

    # The QA oracle: does the transcribed script form +tibetan+ match the
    # transcribed romanisation +roman+? (A closing tsheg or shad is ignored.)
    def agree?(tibetan:, roman:)
      to_tibetan(roman).include?(normalize_tibetan(tibetan))
    end

    # The house Tibetan search fold (EWTS skeleton, Nabu::Xct) of every
    # reading — what a romanised query reaches script text through.
    def to_ewts(roman) = to_tibetan(roman).map { |tibetan| Xct.to_ewts(tibetan) }.uniq

    # Every Jäschke reading of the Tibetan +tibetan+ (canonical spelling,
    # syllables hyphenated); the anusvāra reads both ṅ and m.
    def from_tibetan(tibetan)
      syllables = normalize_tibetan(tibetan).split(/[་༌།\s]+/).reject(&:empty?)
      raise Error, "no Tibetan syllable in #{tibetan.inspect}" if syllables.empty?

      first, *rest = syllables.map { |syllable| roman_readings(syllable) }
      first.product(*rest).map { |parts| parts.join("-").unicode_normalize(:nfc) }.uniq
    end

    # -- romanisation → tokens -------------------------------------------------

    # The input as hyphen/space-separated chunks of tokens: consonant codes
    # (Strings, the EWTS letter names plus "G" for γ) and vowel Hashes.
    def chunks(roman)
      graphemes(roman.to_s.unicode_normalize(:nfd).downcase).chunk_while { |a, b| a != :sep && b != :sep }
                                                            .reject { |chunk| chunk == [:sep] }
                                                            .map { |chunk| tokens(chunk) }
    end

    # [base, marks] pairs; standalone spiritus letters attach to the
    # preceding consonant, ring letters become an a-chung grapheme.
    def graphemes(text)
      out = []
      text.each_char do |char|
        if char.match?(/\p{M}/)
          raise Error, "stray mark U+#{char.ord.to_s(16).upcase} in #{text.inspect}" if out.empty? || out.last == :sep

          out.last[1] << char
        elsif SEPARATOR.match?(char) then out << :sep
        elsif SPIRITUS_LETTERS.include?(char) && out.last.is_a?(Array) && !VOWELS.include?(out.last[0])
          out.last[1] << "\u0314"
        elsif SPIRITUS_LETTERS.include?(char) || RING_LETTERS.include?(char) then out << ["\u02F3", []]
        else out << [char, []]
        end
      end
      out
    end

    def tokens(chunk)
      out = []
      index = 0
      while index < chunk.size
        base, marks = chunk[index]
        nxt = chunk[index + 1]
        out << "'" if marks.include?("\u0325") && base != "\u02F3" # a combining ring below
        code, used = letter(base, marks, nxt, chunk[index + 2])
        out << code
        index += used
      end
      out
    end

    # The token at one grapheme (with lookahead for the digraphs); returns
    # [token, graphemes consumed].
    def letter(base, marks, nxt, after)
      plain_h = plain_h?(nxt)
      aspirated = marks.intersect?(SPIRITUS_MARKS)
      case base
      when *VOWELS then [{ "v" => base, "long" => marks.include?("\u0304") }, 1]
      when "\u02F3" then ["'", 1]
      when "γ" then ["G", 1]
      when "k", "p", "c" then marked(base, "#{base}h", aspirated, plain_h)
      when "j" then ["j", 1]
      when "t" then t_letter(marks, nxt, after, aspirated)
      when "d" then d_letter(marks, nxt, after)
      when "n" then n_letter(marks, nxt)
      when "s" then s_letter(marks, plain_h)
      when "z" then marked("z", "zh", marks.intersect?(PALATAL_MARKS), plain_h)
      when "g", "b" then marked(base, "#{base}h", false, plain_h)
      when "v" then ["w", 1]
      when "m", "w", "y", "r", "l", "h" then [base, 1]
      else raise Error, "#{base.inspect} is not a letter of Jäschke's system"
      end
    end

    def plain_h?(grapheme) = !grapheme.nil? && grapheme[0] == "h" && grapheme[1].empty?

    # +plain+ or its +marked+ twin: the mark on the letter, or a following
    # plain h (consumed — the lenient "kh" spelling).
    def marked(plain, marked, mark, plain_h)
      return [marked, 2] if plain_h

      [mark ? marked : plain, 1]
    end

    def t_letter(marks, nxt, after, aspirated)
      return marked("T", "Th", aspirated, plain_h?(nxt)) if marks.include?("\u0323")
      return marked("t", "th", aspirated, plain_h?(nxt)) unless nxt && nxt[0] == "s"
      return ["tsh", 3] if plain_h?(after)

      [nxt[1].intersect?(SPIRITUS_MARKS) || aspirated ? "tsh" : "ts", 2]
    end

    def d_letter(marks, nxt, after)
      return marked("D", "Dh", false, plain_h?(nxt)) if marks.include?("\u0323")
      return marked("d", "dh", false, plain_h?(nxt)) unless nxt && nxt[0] == "z"

      plain_h?(after) ? ["dzh", 3] : ["dz", 2]
    end

    def n_letter(marks, nxt)
      return ["ng", 1] if marks.include?("\u0307")
      return ["ny", 1] if marks.include?("\u0303")
      return ["N", 1] if marks.include?("\u0323")
      return ["ny", 2] if nxt && nxt[0] == "y" && nxt[1].empty?

      ["n", 1]
    end

    def s_letter(marks, plain_h)
      return ["Sh", 1] if marks.include?("\u0323")
      return ["sh", plain_h ? 2 : 1] if marks.intersect?(PALATAL_MARKS) || plain_h

      ["s", 1]
    end

    def render_vowel(token)
      vowel = token.fetch("v")
      vowel = { "a" => "ā", "i" => "ī", "u" => "ū", "e" => "ē", "o" => "ō" }.fetch(vowel) if token["long"]
      vowel
    end

    # -- tokens → syllables ----------------------------------------------------

    def vowel?(token) = token.is_a?(Hash)

    # One chunk's syllables: vowel groups (a vowel + a particle i/o/u),
    # the consonant clusters between them split onset-first.
    def syllables(chunk)
      groups = vowel_groups(chunk)
      raise Error, "no vowel in #{chunk.map { |t| vowel?(t) ? t['v'] : t }.join.inspect}" if groups.empty?

      onset = chunk[0...groups.first.first]
      groups.each_with_index.map do |(start, stop), index|
        cluster_end = index + 1 < groups.size ? groups[index + 1].first : chunk.size
        cluster = chunk[(stop + 1)...cluster_end]
        coda, next_onset = index + 1 < groups.size ? split_cluster(cluster) : [cluster, []]
        syllable = build_syllable(onset, chunk[start..stop], coda)
        onset = next_onset
        syllable
      end
    end

    def vowel_groups(chunk)
      groups = []
      chunk.each_with_index do |token, index|
        next unless vowel?(token)

        last = groups.last
        if last && last[1] == index - 1 && last[0] == last[1] && %w[i o u].include?(token["v"]) && !token["long"]
          last[1] = index
        else
          groups << [index, index]
        end
      end
      groups
    end

    def build_syllable(onset, vowels, coda)
      first, second = vowels
      Syllable.new(onset: onset, vowel: first["v"], long: first["long"], second: second&.fetch("v"), coda: coda)
    end

    # [coda, next onset] for a cluster between two vowels: the largest
    # parseable onset whose remainder is a native coda; failing that, the
    # largest parseable onset (a Sanskrit coda).
    def split_cluster(cluster)
      sizes = cluster.size.downto(0).to_a
      native = sizes.find { |k| onset_ok?(cluster.last(k)) && native_coda?(cluster.first(cluster.size - k)) }
      chosen = native || sizes.find { |k| onset_ok?(cluster.last(k)) && cluster.size - k <= 2 }
      raise Error, "cannot syllabify the cluster #{cluster.join.inspect}" if chosen.nil?

      [cluster.first(cluster.size - chosen), cluster.last(chosen)]
    end

    def onset_ok?(onset) = onset.empty? || onset_parses(onset).any?

    def native_coda?(coda)
      return true if coda.empty?
      return SUFFIXES.include?(coda[0]) if coda.size == 1

      coda.size == 2 && SUFFIXES.include?(coda[0]) && POSTSUFFIXES.include?(coda[1])
    end

    # Every orthographically valid [prefix][superscript]root[subscripts]
    # reading of an onset cluster.
    def onset_parses(onset)
      return [Onset.new(prefix: nil, super: nil, root: "g", subs: [])] if onset == ["G"]

      parses = [nil, onset[0]].uniq.flat_map do |prefix|
        rest = prefix ? onset[1..] : onset
        next [] if rest.empty?

        [nil, rest[0]].uniq.filter_map do |sup|
          stack = sup ? rest[1..] : rest
          next if stack.empty?

          candidate = Onset.new(prefix: prefix, super: sup, root: stack[0], subs: stack[1..])
          candidate if valid_onset?(candidate)
        end
      end
      # γ is the prefixed g; a plain g reads as a prefix only when nothing
      # else parses (lenient input that dropped the gamma).
      plain_g = parses.select { |parse| parse.prefix == "g" }
      parses -= plain_g if plain_g.size < parses.size
      parses
    end

    def valid_onset?(onset)
      root = onset.root
      return false if root == "G" || !(BASE.key?(root) || H_STACKS.key?(root))
      return false if onset.subs.size > 2 || !valid_subs?(root, onset.subs)
      return false if onset.super && !SUPERSCRIPTS.fetch(onset.super, []).include?(root)
      return false if root == "'" && (onset.prefix || onset.super || onset.subs.any?)

      valid_prefix?(onset)
    end

    def valid_subs?(root, subs)
      return true if subs.empty?
      return false unless SUBSCRIPTS.fetch(subs[0], []).include?(root)

      subs.size == 1 || subs[1] == "w"
    end

    def valid_prefix?(onset)
      return true if onset.prefix.nil?

      prefix = onset.prefix == "G" ? "g" : onset.prefix
      return %w[r s l].include?(onset.super) && prefix == "b" if onset.super

      PREFIX_PAIRS.fetch(prefix, []).include?(onset.root)
    end

    # -- syllables → Tibetan ---------------------------------------------------

    def syllable_readings(syllable)
      onsets = syllable.onset.empty? ? [nil] : onset_parses(syllable.onset)
      raise Error, "no Tibetan reading for the onset #{syllable.onset.join.inspect}" if onsets.empty?

      onsets.flat_map do |onset|
        nucleus_readings(syllable, onset).flat_map do |nucleus|
          coda_readings(syllable, onset, nucleus).map { |coda| head(onset) + nucleus + coda }
        end
      end
    end

    def head(onset)
      return CARRIER if onset.nil?

      prefix = onset.prefix ? BASE.fetch(onset.prefix.tr("G", "g")) : ""
      stack = if onset.super
                BASE.fetch(onset.super) + subjoined(onset.root)
              else
                base(onset.root)
              end
      prefix + stack + onset.subs.map { |sub| SUBJOINED.fetch(sub) }.join
    end

    def base(code) = H_STACKS.key?(code) ? BASE.fetch(H_STACKS[code]) + SUBJOINED.fetch("h") : BASE.fetch(code)

    def subjoined(code)
      return SUBJOINED.fetch(H_STACKS[code]) + SUBJOINED.fetch("h") if H_STACKS.key?(code)

      SUBJOINED.fetch(code)
    end

    # The vowel (+ particle) readings: "ai"/"au" may be the particle or the
    # vowel sign.
    def nucleus_readings(syllable, _onset)
      long = syllable.long ? LONG : ""
      sign = syllable.vowel == "a" ? "" : SIGNS.fetch(syllable.vowel)
      return [long + sign] if syllable.second.nil?

      particle = long + sign + A_CHUNG + SIGNS.fetch(syllable.second)
      combined = syllable.vowel == "a" && %w[i u].include?(syllable.second) ? SIGNS.fetch("a#{syllable.second}") : nil
      [particle, combined && (long + combined)].compact
    end

    # The coda readings: a lone closing ng/m may be the anusvāra; a
    # prefixed open syllable takes its unwritten closing a-chung.
    def coda_readings(syllable, onset, nucleus)
      coda = syllable.coda
      if coda.empty?
        closing = onset&.prefix && onset.super.nil? && onset.subs.empty? && nucleus.empty? && !H_STACKS.key?(onset.root)
        return [closing ? A_CHUNG : ""]
      end

      letters = coda.map { |code| base(code) }.join
      %w[ng m].include?(coda.join) && coda.size == 1 ? [letters, ANUSVARA] : [letters]
    end

    # -- Tibetan → romanisation ------------------------------------------------

    def normalize_tibetan(tibetan)
      Normalize.nfc(tibetan.to_s).strip.sub(/[་༌།\s]+\z/, "")
    end

    def roman_readings(syllable)
      ewts = Xct.to_ewts(syllable)
      gamma = syllable.start_with?("ག") && syllable[1]&.match?(/[ཀ-ཬ]/) && ewts[1]&.match?(/[^aeiouAIU]/)
      readings = [+""]
      ewts.scan(/#{EWTS_TOKEN}|./o).each_with_index do |token, index|
        options = if token == "'" then [index.zero? ? "\u02F3" : ""]
                  elsif token == "g" && index.zero? && gamma then ["γ"]
                  else Array(EWTS_ROMAN.fetch(token, token))
                  end
        readings = readings.product(options).map(&:join)
      end
      readings
    end
  end
end
