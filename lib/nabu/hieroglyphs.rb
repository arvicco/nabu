# frozen_string_literal: true

require_relative "normalize"

module Nabu
  # A pure READ seam over Unicode's Unikemet.txt (P65-2): the normative
  # Egyptian Hieroglyph data file of the UCD — 5,067 signs at 17.0 with
  # Gardiner-plus catalog codes, descriptions, functions, phonetic values,
  # and the JSesh/Hieroglyphica/IFAO concordances — the Egyptian analogue
  # of Unihan, and the sign spine of the P65-2 `nabu char` Egyptian card.
  # The osl/SignList posture exactly: no catalog table, no migration; the
  # unikemet feature module's one canonical asset is
  # canonical/unikemet/Unikemet.txt, landed by `nabu sync unikemet`.
  #
  # Line grammar (the Unihan tag format): `U+xxxxx<TAB>kEH_Field<TAB>value`,
  # `#` comments. Census at 17.0 (fixture README): every (codepoint, field)
  # pair is unique — fields are scalar — and kEH_JSesh codes are globally
  # unique, so the Gardiner-style code lane is a deterministic single hit.
  # An absent field is nil on the record (kEH_Core absent = the upstream
  # default N), never a placeholder.
  class Hieroglyphs
    FILE = "Unikemet.txt"
    SLUG = "unikemet"

    FIELDS = {
      "kEH_Cat" => :cat, "kEH_UniK" => :unik, "kEH_Core" => :core,
      "kEH_Desc" => :desc, "kEH_Func" => :func, "kEH_FVal" => :fval,
      "kEH_JSesh" => :jsesh, "kEH_HG" => :hg, "kEH_IFAO" => :ifao,
      "kEH_AltSeq" => :alt_seq, "kEH_NoMirror" => :no_mirror,
      "kEH_NoRotate" => :no_rotate
    }.freeze

    # One Unikemet sign. +glyph+ is the rendered codepoint; +jsesh+ is the
    # Gardiner-style code the field (and the aes hiero_inventar annotations)
    # spell (A1, G5, N35); +core+ is "C"/"L" or nil (= upstream default N).
    Sign = Data.define(:codepoint, :glyph, :cat, :unik, :core, :desc, :func,
                       :fval, :jsesh, :hg, :ifao, :alt_seq, :no_mirror, :no_rotate)

    def self.load(path)
      new(path)
    end

    # Feature-detect from the owner's canonical tree: nil when `nabu sync
    # unikemet` has not landed the file (the SignList lane-off posture).
    def self.load_default(config: Nabu::Config.load)
      path = File.join(config.canonical_dir, SLUG, FILE)
      return nil unless File.file?(path)

      (@cache ||= {})[path] ||= load(path)
    end

    def self.reset!
      @cache = nil
    end

    def initialize(path)
      fields = Hash.new { |hash, key| hash[key] = {} }
      File.foreach(path, encoding: Encoding::UTF_8) do |line|
        next if line.start_with?("#") || line.strip.empty?

        code, field, value = line.chomp.split("\t", 3)
        key = FIELDS[field]
        fields[code][key] = value if key && value
      end
      index(fields)
    end

    def sign_for_glyph(glyph)
      @by_glyph[glyph.to_s]
    end

    def sign_for_codepoint(codepoint)
      @by_codepoint[codepoint.to_s]
    end

    # Gardiner-style code (kEH_JSesh: A1, G5, N35) → the sign, nil when the
    # code is not in the held file. A deterministic single hit (see census).
    def sign_for_code(code)
      @by_code[code.to_s]
    end

    def sign_count = @by_codepoint.size

    private

    def index(fields)
      @by_codepoint = {}
      @by_glyph = {}
      @by_code = {}
      fields.each do |code, values|
        glyph = code[/\AU\+(\h+)\z/, 1]&.to_i(16)&.chr(Encoding::UTF_8)
        sign = Sign.new(codepoint: code, glyph: glyph,
                        **Sign.members.drop(2).to_h { |member| [member, values[member]] })
        @by_codepoint[code] = sign
        @by_glyph[glyph] = sign if glyph
        @by_code[sign.jsesh] ||= sign if sign.jsesh
      end
    end
  end
end
