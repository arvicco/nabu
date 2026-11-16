# frozen_string_literal: true

require_relative "source_read"

module Nabu
  module Adapters
    # dicta-bavli: Dicta's vocalized Babylonian Talmud — the whole Bavli (37
    # tractates, Vilna pagination) pointed by Dicta's rabbinic Nakdan and
    # then reviewed and corrected by professional vocalizers (upstream
    # README), published as github.com/Dicta-Israel-Center-for-Text-Analysis/
    # Talmud-Bavli-with-Nikud. A plain-text family of its own (no existing
    # parser reads the "*** דף ב. ***" header shape).
    #
    # == Upstream's delivery grains (the repo tree, censused 2026-11-16)
    #
    # 38 top-level tractate directories, each holding the tractate TWICE —
    # <hebrew-name>.combinedfullmaleh.txt (ktiv male: the spelling with the
    # matres lectionis as printed in the Vilna Shas) and
    # <hebrew-name>.combinedfullhaser.txt (ktiv haser: the defective spelling
    # Dicta recommends for vocalized text — the README's "royal road") — plus
    # two Word files of corrections lists (Berakhot, Shabbat) and the README.
    # Inside a file: one daf/amud header line (" *** דף ב. *** " — gematria
    # daf, "." = amud a, ":" = amud b) followed by the amud's paragraphs, one
    # per line, blank lines between. The two variants are LINE-ALIGNED in
    # every tractate (identical line counts and blank-line skeletons, 76
    # files censused): 78,782 paragraph lines, 61,896 of which differ
    # between the spellings.
    #
    # The document is the TRACTATE; the passage is one paragraph line,
    # cited <daf><a|b>.<n> (n = 1-based within the amud — the sefaria Bavli
    # citation shape). The marker lines upstream prints between sections
    # (גמ' / מַתְנִי') are upstream text and stay passages, verbatim — they
    # are too irregular (a few dozen across the Shas) to rebuild a
    # Mishnah/Gemara structure from.
    #
    # The ktiv MALE file is the passage text — the Vilna print's own
    # orthography, so an unpointed query in the printed spelling folds onto
    # it (the search form strips the points, never the matres). The ktiv
    # HASER line rides the passage's annotations ("ktiv_haser") wherever it
    # differs, paired by line index; a tractate whose files are NOT aligned
    # pairs nothing and says so (metadata ktiv_haser "unaligned" — never a
    # guessed pairing); a tractate with no haser file says "absent".
    #
    # Rejected grains, skipped BY RULE and counted (discovery_skips):
    # - the Meila directory: a byte-identical duplicate of Meilah (same
    #   sha256 for both files, 2026-11-16) — DUPLICATE_DIRS;
    # - the corrections .docx files (errata lists in Word, not text).
    # Reconciliation: 38 directories = 37 documents + 1 duplicate skipped;
    # 78 files = 74 tractate texts + 2 duplicate texts + 2 .docx.
    #
    # == LICENSE (README, read 2026-11-13 and 2026-11-16, verbatim)
    #
    # "This vocalized text of the Babylonian Talmud is released under a CC
    # BY-SA license. If you make use of the text, please attribute as
    # follows: This text of the Babylonian Talmud was vocalized by Dicta:
    # The Israel Center for Text Analysis (www.dicta.org.il)" — no version
    # number, no LICENSE file. Admitted with the requested credit (the
    # admit-with-credit posture, owner ruling 2026-11-03) → attribution, the
    # house BY-SA class.
    #
    # == Language
    #
    # The Bavli is Jewish Babylonian Aramaic interleaved with Rabbinic
    # Hebrew (the Mishnah, baraitot, much of the halakhic discourse) at
    # sub-paragraph grain — no per-passage split is possible. The adapter
    # codes every passage bare `arc`, the house Bavli code (the sefaria
    # bavli shelf's ruling); config/lect_overrides.yml files it on the same
    # node the sefaria Bavli resolves to (arc:mid, approximation — the
    # declared Hebrew-mix coarseness). `arc` is NFC-exempt, so Dicta's mark
    # order is stored byte-verbatim (the search form folds it either way).
    class DictaBavli < Nabu::Adapter
      REPO_URL = "https://github.com/Dicta-Israel-Center-for-Text-Analysis/Talmud-Bavli-with-Nikud"
      URN_PREFIX = "urn:nabu:dicta-bavli:"
      LANGUAGE = "arc"

      MALE_SUFFIX = ".combinedfullmaleh.txt"
      HASER_SUFFIX = ".combinedfullhaser.txt"

      # Upstream directory → the directory it duplicates byte-for-byte.
      DUPLICATE_DIRS = { "Meila" => "Meilah" }.freeze

      # " *** דף קעו: *** " (one census header lacks the trailing space).
      HEADER = /\A\s*\*\*\*\s*דף\s+(\S+?)([.:])\s*\*\*\*\s*\z/

      # Hebrew letter values (the daf numerals are plain additive gematria;
      # טו/טז sum like any other pair).
      GEMATRIA = {
        "א" => 1, "ב" => 2, "ג" => 3, "ד" => 4, "ה" => 5, "ו" => 6, "ז" => 7, "ח" => 8, "ט" => 9,
        "י" => 10, "כ" => 20, "ך" => 20, "ל" => 30, "מ" => 40, "ם" => 40, "נ" => 50, "ן" => 50,
        "ס" => 60, "ע" => 70, "פ" => 80, "ף" => 80, "צ" => 90, "ץ" => 90, "ק" => 100, "ר" => 200,
        "ש" => 300, "ת" => 400
      }.freeze

      # The six orders (the sefaria seder facet values), by upstream's
      # directory name.
      SEDARIM = {
        "Zeraim" => %w[Berakhot],
        "Moed" => %w[Shabbat Eruvin Pesachim Rosh_Hashanah Yoma Sukkah Beitzah Taanit Megillah
                     Moed_Katan Chagigah],
        "Nashim" => %w[Yevamot Ketubot Nedarim Nazir Sota Gittin Kiddushin],
        "Nezikin" => %w[Bava_Kamma Bava_Metzia Bava_Batra Sanhedrin Makkot Shevuot Avoda_Zara Horayot],
        "Kodashim" => %w[Zevahim Menahot Hullin Bekhorot Arakhin Temura Karetot Meilah Tamid],
        "Tahorot" => %w[Niddah]
      }.flat_map { |seder, dirs| dirs.map { |dir| [dir, seder] } }.to_h.freeze

      GRANT = "This vocalized text of the Babylonian Talmud is released under a CC BY-SA license. " \
              "If you make use of the text, please attribute as follows: This text of the Babylonian " \
              "Talmud was vocalized by Dicta: The Israel Center for Text Analysis (www.dicta.org.il)"

      MANIFEST = Nabu::SourceManifest.new(
        id: "dicta-bavli",
        name: "Dicta — the vocalized Babylonian Talmud (Talmud Bavli with Nikud, ktiv male + haser)",
        license: "CC BY-SA, unversioned (repo README, verbatim: \"#{GRANT}\"); no LICENSE file",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "dicta-bavli-txt",
        credit: "This text of the Babylonian Talmud was vocalized by Dicta: The Israel Center for Text " \
                "Analysis (www.dicta.org.il)"
      )

      # One discovery walk: refs, rule-skip notes, unrecognized notes.
      Scan = Data.define(:refs, :skipped, :unrecognized)

      def self.manifest = MANIFEST

      # Each parse reads its own two files — no state crosses refs.
      def self.parallel_parse? = true

      # The daf number of a gematria numeral ("קעו" → 176).
      def self.daf_number(numeral)
        numeral.each_char.sum do |char|
          GEMATRIA.fetch(char) { raise ParseError, "daf numeral #{numeral.inspect}: #{char.inspect} is not a letter" }
        end
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        scan(workdir).refs.each(&block)
      end

      def discovery_skips(workdir)
        result = scan(workdir)
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: result.skipped.size,
                                          unrecognized: result.unrecognized.size,
                                          notes: result.skipped + result.unrecognized)
      end

      def parse(document_ref)
        male = lines(document_ref.path)
        haser_path = document_ref.metadata["haser_path"]
        haser = haser_path && lines(haser_path)
        aligned = haser && aligned?(male, haser)
        state = if haser.nil? then "absent"
                elsif aligned then "aligned"
                else "unaligned"
                end
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: document_ref.metadata.fetch("title"),
          canonical_path: document_ref.path, metadata: document_metadata(document_ref.metadata, state)
        )
        append_passages(document, male, aligned ? haser : nil)
        raise ParseError, "#{document_ref.path}: no paragraph under any daf header" if document.empty?

        document
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end

      def scan(workdir)
        refs = []
        skipped = []
        unrecognized = []
        return Scan.new(refs: refs, skipped: skipped, unrecognized: unrecognized) unless Dir.exist?(workdir)

        Dir.children(workdir).sort.each do |name|
          dir = File.join(workdir, name)
          next if name.start_with?(".") || !File.directory?(dir)

          Dir.glob("*.docx", base: dir).sort.each do |docx|
            skipped << "#{name}/#{docx}: a corrections list in Word (.docx), not tractate text"
          end
          if (original = DUPLICATE_DIRS[name])
            skipped << "#{name}/: a byte-identical duplicate of #{original}/ (upstream ships both)"
            next
          end
          ref = tractate_ref(dir, name)
          ref ? refs << ref : unrecognized << "#{name}/: no *#{MALE_SUFFIX} tractate file"
        end
        Scan.new(refs: refs.sort_by(&:id), skipped: skipped, unrecognized: unrecognized)
      end

      def tractate_ref(dir, name)
        male = Dir.glob("*#{MALE_SUFFIX}", base: dir).min
        return nil unless male

        haser = Dir.glob("*#{HASER_SUFFIX}", base: dir).min
        Nabu::DocumentRef.new(
          source_id: manifest.id,
          id: "#{URN_PREFIX}#{name.downcase.tr('_', '-')}",
          path: File.expand_path(File.join(dir, male)),
          metadata: {
            "tractate_dir" => name,
            "title" => name.tr("_", " "),
            "he_title" => Normalize.nfc(male.delete_suffix(MALE_SUFFIX).delete_suffix(".").tr("_", " ")),
            "haser_path" => haser && File.expand_path(File.join(dir, haser))
          }.compact
        )
      end

      def lines(path)
        SourceRead.utf8_file(path, label: "dicta-bavli").split("\n", -1)
      end

      # The variants pair line by line only when their skeletons agree:
      # same line count, blank lines and headers on the same indices.
      def aligned?(male, haser)
        male.size == haser.size &&
          male.each_index.all? { |i| shape(male[i]) == shape(haser[i]) }
      end

      def shape(line)
        return :blank if line.strip.empty?

        line.match?(HEADER) ? line.strip : :text
      end

      def append_passages(document, male, haser)
        daf = amud = nil
        ordinal = 0
        male.each_with_index do |line, index|
          text = line.strip
          next if text.empty?

          if (match = text.match(HEADER))
            daf = self.class.daf_number(match[1])
            amud = match[2] == "." ? "a" : "b"
            ordinal = 0
            next
          end
          if daf.nil?
            raise ParseError, "#{document.canonical_path}: text before the first daf header (line #{index + 1})"
          end

          ordinal += 1
          document << passage(document, text, daf, amud, ordinal, haser && haser[index].strip)
        end
      end

      def passage(document, text, daf, amud, ordinal, haser)
        annotations = { "daf" => daf, "amud" => amud }
        annotations["ktiv_haser"] = SourceRead.nfc(haser, language: LANGUAGE) if haser && haser != text
        Nabu::Passage.new(
          urn: "#{document.urn}:#{daf}#{amud}.#{ordinal}", language: LANGUAGE,
          text: SourceRead.nfc(text, language: LANGUAGE), sequence: document.size, annotations: annotations
        )
      end

      def document_metadata(ref_metadata, haser_state)
        seder = SEDARIM[ref_metadata["tractate_dir"]]
        {
          "he_title" => ref_metadata["he_title"],
          "genre" => "Talmud Bavli",
          "text_layer" => "vocalized",
          "orthography" => "ktiv male (the Vilna print's spelling); ktiv haser per passage annotation",
          "ktiv_haser" => haser_state,
          "facets" => seder && { "seder" => { "value" => "seder-#{seder.downcase}", "raw" => seder } }
        }.compact
      end
    end
  end
end
