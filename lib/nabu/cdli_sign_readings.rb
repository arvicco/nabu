# frozen_string_literal: true

require_relative "atf_tokenizer"

module Nabu
  # A pure READ seam over the CDLI sign-reading concordance that rides
  # INSIDE the held OSL repo (canonical/osl/00etc/cdli_sign_readings.tsv,
  # CC0 with the repo — no separate fetch): sign name → readings with the
  # CDLI meaning gloss ("A → n. water"), the one humanist-gloss column the
  # ASL grammar itself lacks. First consumer: the P65-1 `nabu char`
  # cuneiform sign card's glosses section.
  #
  # CDLI spells sign names and readings in C-ATF ASCII (SZESZ, szesz,
  # |ABxASZ2|, 'a3); this seam folds BOTH to the OSL spelling (ŠEŠ, šeš,
  # |AB×AŠ₂|, ʾa₃) at load, so card-side joins key on record.name directly.
  # A folded name with no OSL match simply never gets asked — honest
  # absence, not an error. Census 2026-08-09: all 1,860 upstream rows carry
  # preferred_reading=1; the flag rides anyway (upstream may differentiate).
  class CdliSignReadings
    TSV_FILE = File.join("00etc", "cdli_sign_readings.tsv")
    SLUG = "osl"

    # One CDLI reading row: the folded reading, the preferred flag, the
    # meaning gloss (nil when CDLI has none — most rows).
    Reading = Data.define(:reading, :preferred, :meaning)

    def self.load(path)
      new(path)
    end

    # Feature-detect from the owner's canonical tree: nil when `nabu sync
    # osl` has not landed the file (the SignList lane-off posture). Memoized
    # per path; reset! clears (tests).
    def self.load_default(config: Nabu::Config.load)
      path = File.join(config.canonical_dir, SLUG, TSV_FILE)
      return nil unless File.file?(path)

      (@cache ||= {})[path] ||= load(path)
    end

    def self.reset!
      @cache = nil
    end

    def initialize(path)
      @by_name = Hash.new { |hash, key| hash[key] = [] }
      tokenizer = Nabu::AtfTokenizer.new(dialect: :catf)
      File.readlines(path, encoding: Encoding::UTF_8).drop(1).each do |line|
        _id, name, reading, preferred, _period, _prov, _lang, meaning = line.chomp.split("\t", 8)
        next if name.nil? || reading.nil?

        gloss = meaning.to_s.strip
        @by_name[tokenizer.fold_name(name)] << Reading.new(
          reading: tokenizer.fold_name(reading), preferred: preferred == "1",
          meaning: gloss.empty? || gloss == "NULL" ? nil : gloss
        )
      end
    end

    # Folded OSL-spelled sign name → readings in file order ([] when CDLI
    # has none for this sign).
    def readings_for(name)
      @by_name.fetch(name.to_s, [])
    end
  end
end
