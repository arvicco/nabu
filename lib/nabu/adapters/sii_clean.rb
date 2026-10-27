# frozen_string_literal: true

require "nokogiri"

require_relative "dharma_base"
require_relative "../eras"

module Nabu
  module Adapters
    # South Indian Inscriptions — the DHARMA conversions (P122-3; widened
    # 2026-10-21). github.com/erc-dharma/south-indian-inscriptions holds the
    # Archaeological Survey of India's printed SII volumes 1–42 re-keyed as
    # DHARMA EpiDoc, in two layers:
    #
    #   SII_B_clean/SII<NN>/DHARMA_*.xml   the editions ("ERC DHARMA project
    #                                      online editions, displayed on
    #                                      https://dharmalekha.info")
    #   SII_A_raw/3out/<NN>/~DHARMA_*.xml  one conversion per inscription,
    #                                      split by Michaël Meyer from the
    #                                      contractor's keying "with DHARMA
    #                                      editorial markup as far as
    #                                      possible" — the files the clean
    #                                      editions are made from
    #
    # == Census at HEAD 76608102 (2026-10-21) and the reconciliation
    #
    # Upstream serves 25,593 blobs. Grains and their fate:
    # - SII_B_clean DHARMA_ editions: 4,796 — ALL in the cone (accepted);
    # - SII_B_clean ~DHARMA_ in-progress files: 179 — outside the sparse
    #   cone (they arrive by promotion, the family rule); one pinned in the
    #   fixtures, skipped by rule when present;
    # - SII_B_clean/README.txt (the licence statement) and one worklist
    #   (SII17/SII_to_update.html) — not documents;
    # - SII_A_raw/3out per-inscription conversions: 20,554 (+ one .tsv
    #   worklist) — in the cone; 4,801 of them are inscriptions a clean
    #   edition already holds (4,786 by exact stem, 15 through a clean range
    #   "i0290-0293" or a lettered number "i0017A") and are SUPERSEDED,
    #   skipped by rule and censused per volume: one inscription, one
    #   document, the edition winning. 15,753 stand in for inscriptions no
    #   clean edition covers (vols 9, 10, 15, 16, 18–20 and 23–42 are raw
    #   bar a few dozen clean editions). The 798 clean edition-less stubs were checked
    #   against their raw counterparts: none has text there either (781
    #   text-less, 12 "und", 5 without a raw file), so supersession loses
    #   nothing;
    # - SII_A_raw/1orig (3 files: the contractor's whole-corpus dumps, ~110
    #   MB) and SII_A_raw/2mastercopy (53 per-volume master copies + the
    #   split tooling): the SAME text at the corpus / volume grain that 3out
    #   carries per inscription — rejected at the sparse cone (ingesting
    #   them would double every raw inscription).
    # Accepted + skipped therefore account for upstream's whole document
    # surface: 4,796 + 20,554 = 25,350 per-inscription files, of which
    # 4,801 superseded → 20,549 refs.
    #
    # Census parse over a sparse clone at that HEAD (these rules, 2026-10-21):
    # 20,549 refs → 18,490 documents / 314,882 passages. Clean 4,796 →
    # 3,969 docs / 54,626 passages (827 quarantines: 798 edition-less stubs,
    # 17 text-less, 6 "und", 4 mar-Latn, 2 lang-less); raw 15,753 → 14,521
    # docs / 260,256 passages (1,232 quarantines: 831 text-less, 400 "und",
    # 1 sin-Latn). Mined: 1,536 dated (clean 487 · raw 1,049), 10,380
    # villages (clean 1,833 · raw 8,547).
    #
    # == Licence (the 2026-10-21 statement)
    #
    # Until 2026-10-21 the repo carried no licence and only files with an
    # in-file <licence> were ingested (649 then). On 2026-10-21 the DHARMA
    # maintainer added to SII_B_clean/README.txt: "All files in this
    # repository are under CC BY-SA 4.0 license." Every clean edition is
    # therefore in scope: the in-file target is recorded verbatim when
    # present (729 files), else the README statement ("license_basis"
    # names which). The raw 3out files each carry their own in-file
    # <licence> CC BY-SA 4.0 (15,753 / 15,753 of the raw-only set); since
    # the README's header names "SII_B_clean", a raw file WITHOUT its own
    # grant quarantines loudly rather than leaning on the statement (none
    # today). Class attribution throughout.
    #
    # == Identity
    #
    #   urn:nabu:sii-clean:<file stem sans "DHARMA_" / "~DHARMA_">
    #   passage: the dharma-epidoc grain — <urn>:<line n> | <urn>:<lg n>.<l n>
    #
    # Stems carry vNN pN iNNNN and are unique within each layer; across the
    # layers an exact stem is always superseded, so urns never collide. The
    # slug keeps its historical name (urn stability for the held editions);
    # "layer" ("edition" | "raw") rides every document. When upstream
    # promotes an inscription into SII_B_clean, its raw stand-in is
    # superseded on the next sync (withdrawn) and the edition takes the same
    # urn when the stems agree — a revision, not a second document.
    #
    # 176 SII inscriptions also have a DHARMA re-edition in tfa-sii-
    # epigraphy (dharma-tamil's INStfaSII…; 125 coincide with clean stems,
    # 50 with raw-only ones) — a different edition of the same inscription
    # (the printed SII text converted vs. DHARMA's own re-reading), so both
    # stand, each under its own urn.
    #
    # == Languages (census 2026-10-21, document codes)
    #
    # clean: tam-Latn 3,712 · san-Latn 126 · tel-Latn 38 · kan-Latn 21, plus
    # upstream's bare "tam" (68 — romanized Tamil, aliased as dharma-tamil
    # does), "san" (1) and "lat" (1, a Latin epitaph at Egmore); nld-Latn 2
    # (Dutch epitaphs). raw-only: tam-Latn 5,772 · tel-Latn 4,964 · kan-Latn
    # 3,749 · pra-Latn 23 (Aśokan and Nāgārjunakoṇḍa Prakrit) · nld-Latn 9 ·
    # per-Latn 2 (aliased: ISO 639-2/B "per" = 639-3 "fas") · ara-Latn 1 ·
    # san-Latn 1. Every admitted code resolves on a held registry anchor.
    # QUARANTINED LOUDLY (the family stance): "und" (6 clean / 400 raw), the
    # 2 lang-less clean files. mar-Latn (4 clean — Maratha-period Tanjore
    # records) and sin-Latn (1 raw — the Rāmēśvaram Sinhala record)
    # quarantined until the registry carried the anchors; the mr/si mint
    # merged 2026-10-21 and both codes are admitted since.
    #
    # == Aggressive mining (owner rule 2026-09-26) and its declared limits
    #
    # The SII editors' printed headings survive as the alt title ("No. 252.
    # (A.R. No. 252 of 1906) NORTH ARCOT DISTRICT, CHEYYAR TALUK,
    # TIRUPPANAṄGĀḌU. ŚIVA TEMPLE—ON THE SAME WALL. ACHYUTADĒVA-MAHĀRĀYA—Śaka
    # 1460."), in BOTH layers, recorded verbatim as "alt_title" and mined:
    # - "annual_report" — the Annual Report on (South-)Indian Epigraphy
    #   number and year ("A.R. No. 252 of 1906": the year the copy was
    #   made, never the inscription's date);
    # - the findspot sentence (the one naming a TALUK/DISTRICT/STATE) →
    #   "findspot" verbatim, "taluk"/"district" (colonial-era units as
    #   printed), and "place" = the village when exactly one candidate
    #   segment remains: a segment opening with a monument description
    #   ("ON A PILLAR LYING NEAR …", "IN A CAVE …") is description, not a
    #   candidate, unless it names the place after its last " AT " (SII 8's
    #   "…TEMPLE AT GUDIMALLAM"); a trailing parenthetical gloss
    #   ("MAMALLAPURAM (SEVEN PAGODAS)", "TIRUMALAI (NEAR TIRUPATI)") is
    #   dropped from the name (it stays in the findspot); a name with
    #   digits, brackets, "SAME", an inner IN/OF/ON/NEAR ("HOSAKERI IN
    #   BARAKUR" — two places) or more than PLACE_MAX_WORDS words claims
    #   nothing. SII 8's "ON THE WEST WALL OF THE SAME SHRINE" headings
    #   inherit their place from the preceding entry — that inference is
    #   NOT made (declared coarseness);
    # - dating: the editor's own "A.D." conversion when printed ("A.D.
    #   1003-04" → [1003, 1004], basis "title A.D."), else a Śaka year
    #   through config/eras.yml (Śaka Y → Y+78, the ruled single offset;
    #   basis "title") — spelled out ("Śaka 1460", "ŚAKA 1504") or in the SII
    #   10 editors' abbreviation "Ś. 1066" (513 raw headings), never a
    #   hedged "Ś. 1169. (?)"; a last digit the editor restored in brackets
    #   ("Ś. 107[3]", "ŚAKA 142(4)") completes the year, a lost one ("Ś.
    #   108-.", a bare "Ś. 106.") spans its decade (SAKA_ABBR — 48 headings
    #   once misread as Śaka 1NN, i.e. 179–229 CE); every such phrase rides "title_dating"
    #   verbatim. Failing both, the summary's single reign line "Year N:
    #   YYYY A.D." (SUMMARY_AD; basis "summary A.D."). Regnal years
    #   ("RĀJARĀJA I—19th YEAR") stay in the verbatim alt title only (no
    #   ruled South-Indian regnal table); cyclic-year names ("(Prabhava.)")
    #   ride the alt title only; hedged summary prose ("1164 or 1168 A.D.
    #   (?)", "might probably correspond to Śaka 1271") is never read.
    # The header also yields "editors" (respStmt), "original_editor" (the
    # main title's "original edition by …"), "sii_volume"/"sii_number",
    # "summary" (msContents, the printed summary — mostly empty in the raw
    # layer),
    # "script_rendition" and "revision_status" — the dharma-tamil set.
    class SiiClean < DharmaBase
      SLUG = "sii-clean"
      NAME = "South Indian Inscriptions — DHARMA editions and conversions"
      CREDIT_CORPUS = "South Indian Inscriptions vols. 1–42 converted to DHARMA EpiDoc " \
                      "(Archaeological Survey of India's printed editions; the original editors " \
                      "named per document)"
      REPO_URL = "https://github.com/erc-dharma/south-indian-inscriptions"
      XML_DIR = "SII_B_clean"
      RAW_DIR = "SII_A_raw/3out"
      RAW_PREFIX = "~DHARMA_"

      SPARSE = [
        "/SII_B_clean/*/DHARMA_*.xml", "/SII_B_clean/README.txt",
        "/SII_A_raw/3out/*/~DHARMA_*.xml", "/SII_A_raw/README.txt"
      ].freeze

      LANGUAGES = %w[tam-Latn san-Latn tel-Latn kan-Latn pra-Latn nld-Latn lat-Latn ara-Latn fas-Latn
                     mar-Latn sin-Latn].freeze
      # Censused upstream tag dirt → the held codes (class comment).
      ALIASES = { "tam" => "tam-Latn", "san" => "san-Latn", "lat" => "lat-Latn",
                  "per-Latn" => "fas-Latn" }.freeze

      BY_SA = "https://creativecommons.org/licenses/by-sa/4.0/"
      IN_FILE = "in-file <licence>"
      REPO_STATEMENT = "SII_B_clean/README.txt repository statement, 2026-10-21: " \
                       "\"All files in this repository are under CC BY-SA 4.0 license\""

      # An in-file grant (the raw layer's admission test, at parse).
      GRANT = /<licence\b[^>]*\btarget="[^"]+"/

      # The inscription a stem names: volume, part, number or range, an
      # optional letter ("…i0017A" claims No. 17's slot).
      STEM_KEY = /\AINSSIIv(\d+)p(\d+)i(\d+)(?:-(\d+))?[A-Z]*\z/

      # The alt title's findspot sentence: the first sentence after a closing
      # parenthesis that names an administrative unit.
      FINDSPOT = /\)\.?\s*([^.]*?\b(?:TALUK|DISTRICT|STATE)\b[^.]*)\./i
      UNIT = /\b(TALUK|DISTRICT|STATE)\b/i
      SAME = /\b(?:SAME|ABOVE)\b/i
      PLACE_MAX_WORDS = 4 # const: a village name, not a monument description
      DESCRIPTION = /\A(?:ON|IN|INSIDE|OVER|NEAR|BELOW|ABOVE|CLOSE|INSCRIPTIONS?)\s/i
      LOCATIVE_AT = /(?:\A|\s+)AT\s+/i
      NOT_A_NAME = /[\d()\[\];:]|\s(?:IN|OF|ON|NEAR|FROM|TO)\s/i
      GLOSS = /\s*\([^()]*\)\s*\z/
      ANNUAL_REPORT = /A\.R\. No\. [^)]*?of \d{4}/

      # The editor's CE conversion and the Śaka phrases (census 2026-10-12:
      # 181 "A.D." headings, 27 Śaka-typed, all in SII 22; 2026-10-21: 513
      # raw headings carry SII 10's "Ś. NNNN" abbreviation).
      AD_PHRASE = /A\.\s?D\.\s*(\d{3,4})(?:\s*[-–—]\s*(\d{1,4}))?/
      # SII 39 spells the era out with the same restored last digit, in
      # brackets or parentheses ("ŚAKA 151[9] (1596-97 A.D.)", "ŚAKA
      # 142(4) (1502 A.D.)" — the editor's own A.D. gloss confirms it).
      SAKA_PHRASE = /\b([ŚśSs][Aa][Kk][Aa])\s+\[?(\d{3,4})\]?(?:[\[(](\d)\.?[\])])?/
      # SII 10's "Ś. NNNN", with the editor's two damaged-year forms (census
      # of the held vol. 10, 2026-10-27: 45 headings): a last digit restored
      # in square brackets ("Ś. 107[3]", "Ś. 113[6.]" — the bracketed digit
      # completes the four-digit year; the stone reads "śakavarṣaṁbulu 107
      # 3") and a last digit lost ("Ś. 108-.", or the bare surviving three
      # "Ś. 106." / "Ś. 120. ." over a body reading "śakavarṣaṁbulu 106
      # <gap>"). A bracket is never a year's end, so a bracket-less reading
      # stopping at "[" is not taken.
      SAKA_ABBR = /Ś\.\s*(?<digits>\d{3,4})(?:\[(?<restored>\d)\.?\]|(?<lost>-))?(?![\d\[])(?![.\s]*\(\?\))/
      # A bare three-digit "Ś. 1NN" is a four-digit year missing its last
      # digit, read as its decade 1NN0–1NN9 — the deliberate rule: Śaka
      # 100–199 (178–277 CE) predates every Śaka-dated South Indian
      # vernacular record by six centuries (SII 10's earliest genuine reading
      # is Ś. 894), every such heading in the held volume sits in the
      # volume's chronological run among Ś. 10NN–11NN neighbours, and its
      # body shows the lost character. Genuine three-digit readings (Ś. 894
      # … 984, Eastern Chalukya) are untouched; no prefix digit is invented.
      SAKA_LOST_DIGIT = /\A1\d\d\z/

      # SII 17/26/41 summaries open with the editor's reign line "King.
      # Year N: YYYY[-YY] A.D." — a CE conversion read only when the
      # summary carries exactly one, never a hedged "(?)" or "or" reading.
      SUMMARY_AD = /\bYear \[?\d+\]?: (\d{3,4})(?:\s*[-–]\s*(\d{1,4}))? A\.\s?D\.(?!\s*\(\?\))/

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: NAME,
          license: "repository-wide CC BY-SA 4.0 (SII_B_clean/README.txt, DHARMA maintainer, " \
                   "2026-10-21) and per-file <licence> CC BY-SA 4.0, recorded per document with " \
                   "its basis — class attribution",
          license_class: "attribution",
          upstream_url: REPO_URL,
          parser_family: "dharma-epidoc",
          credit: "DHARMA — #{CREDIT_CORPUS} (ERC no. 809994, EFEO/CNRS/CEIAS; " \
                  "erc-dharma/south-indian-inscriptions on GitHub, displayed on dharmalekha.info). " \
                  "Cite the SII volume, its original editor and the digital editors wherever used."
        )
      end

      # The inscription slot a file stem names: ["v<NN>p<N>", low..high], or
      # [stem, nil] for a stem outside the SII numbering (keys on itself).
      def self.inscription_key(stem)
        match = STEM_KEY.match(stem) or return [stem, nil]
        low = Integer(match[3], 10)
        high = match[4] ? Integer(match[4], 10) : low
        ["v#{match[1]}p#{match[2]}", low..high]
      end

      # The dating/findspot reading of one alt title (a class method so the
      # census and the tests read the same rule).
      def self.title_facts(alt_title, eras: Nabu::Eras.default)
        return {} if alt_title.nil? || alt_title.empty?

        {
          "annual_report" => alt_title[ANNUAL_REPORT],
          "title_dating" => dating_phrases(alt_title),
          "date" => ad_date(alt_title) || saka_date(alt_title, eras)
        }.merge(findspot_facts(alt_title)).reject { |_, value| value.nil? || value.empty? }
      end

      def self.dating_phrases(alt_title)
        phrases = []
        [AD_PHRASE, SAKA_PHRASE, SAKA_ABBR].each do |pattern|
          alt_title.scan(pattern) { phrases << Regexp.last_match(0).strip }
        end
        phrases
      end

      def self.ad_date(alt_title)
        match = AD_PHRASE.match(alt_title) or return nil
        low = Integer(match[1], 10)
        high = match[2] ? expand_year(match[1], match[2]) : low
        return nil if high.nil? || high < low

        { "not_before" => low, "not_after" => high, "raw" => match[0].strip, "basis" => "title A.D." }
      end

      # "1003-04" → 1004; "999-1000" → 1000; "1533—34" → 1534.
      def self.expand_year(first, second)
        return Integer(second, 10) if second.length >= first.length

        Integer(first[0, first.length - second.length] + second, 10)
      end

      def self.saka_date(alt_title, eras)
        if (match = SAKA_PHRASE.match(alt_title))
          era_word = match[1]
          # A restored digit completes a three-digit reading only.
          year = match[3] && match[2].length == 3 ? match[2] + match[3] : match[2]
        elsif (match = SAKA_ABBR.match(alt_title))
          return saka_abbr_date(match, eras)
        else
          return nil
        end
        key = eras&.resolve(era_word) or return nil
        conversion = eras.to_ce(key, Integer(year, 10))
        conversion.to_date_bounds.merge(
          "raw" => match[0].strip, "era" => key, "era_year" => conversion.year, "basis" => "title"
        )
      end

      # One SAKA_ABBR reading: the restored digit completes the year; a lost
      # one (dash, or a bare "1NN") spans the decade ("era_years" low/high).
      def self.saka_abbr_date(match, eras)
        key = eras&.resolve("Śaka") or return nil
        digits = match[:digits]
        base = { "raw" => match[0].strip, "era" => key }
        if match[:restored]
          year = Integer(digits + match[:restored], 10)
        elsif match[:lost] || digits.match?(SAKA_LOST_DIGIT)
          low = eras.to_ce(key, Integer("#{digits}0", 10))
          high = eras.to_ce(key, Integer("#{digits}9", 10))
          bounds = { "not_before" => low.not_before, "not_after" => high.not_after }
          return bounds.merge(base, "era_years" => [low.year, high.year], "basis" => "title")
        else
          year = Integer(digits, 10)
        end
        conversion = eras.to_ce(key, year)
        conversion.to_date_bounds.merge(base, "era_year" => conversion.year, "basis" => "title")
      end

      # The summary's single reign-line CE conversion (SUMMARY_AD), or nil.
      def self.summary_date(summary)
        matches = summary.to_s.to_enum(:scan, SUMMARY_AD).map { Regexp.last_match }
        return nil unless matches.size == 1

        match = matches.first
        low = Integer(match[1], 10)
        high = match[2] ? expand_year(match[1], match[2]) : low
        return nil if high < low

        { "not_before" => low, "not_after" => high, "raw" => match[0], "basis" => "summary A.D." }
      end

      def self.findspot_facts(alt_title)
        sentence = FINDSPOT.match(alt_title)&.[](1)&.strip or return {}

        facts = { "findspot" => sentence }
        others = []
        sentence.split(/,\s*/).map(&:strip).reject(&:empty?).each do |segment|
          if (unit = segment[UNIT])
            next if segment.match?(SAME)

            key = unit.downcase
            value = segment.sub(UNIT, "").strip
            facts[key] = value if %w[taluk district].include?(key) && !value.empty?
          else
            others << segment
          end
        end
        facts.merge("place" => village(others))
      end

      # Exactly one candidate segment, once monument descriptions are set
      # aside, names the village (class comment) — else no claim.
      def self.village(segments)
        candidates = segments.filter_map { |segment| candidate(segment) }
        return nil unless candidates.size == 1

        name = candidates.first
        return nil if name.match?(NOT_A_NAME) || name.match?(SAME) || name.match?(DESCRIPTION)

        name.split.size.between?(1, PLACE_MAX_WORDS) ? name : nil
      end

      # A segment's candidate name (nil = description, no candidate).
      def self.candidate(segment)
        located = segment.match?(LOCATIVE_AT)
        return nil if !located && segment.match?(DESCRIPTION)

        name = located ? segment.split(LOCATIVE_AT).last.to_s : segment
        name = name.sub(GLOSS, "") while name.match?(GLOSS)
        name.sub(/\s+(?:NEAR|ALIAS)\s+.*\z/i, "").strip
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        clean = clean_paths(workdir)
        clean.each { |path| block.call(ref_for(path, layer: "edition")) }
        held = coverage(clean)
        raw_paths(workdir).each do |path|
          block.call(ref_for(path, layer: "raw")) unless superseded?(path, held)
        end
      end

      # Every rejected grain the fetched tree can hold, counted with its
      # note: superseded raw conversions per volume, in-progress clean files
      # and stray xml one line each.
      def discovery_skips(workdir)
        held = coverage(clean_paths(workdir))
        superseded = raw_paths(workdir).select { |path| superseded?(path, held) }
        strays = clean_xml(workdir).reject { |path| prefixed?(path, FILE_PREFIX) } +
                 raw_xml(workdir).reject { |path| prefixed?(path, RAW_PREFIX) }
        notes = superseded.group_by { |path| volume_of(path) }.sort.map do |volume, paths|
          "#{volume}: #{paths.size} raw conversion(s) superseded by a SII_B_clean edition " \
            "(one inscription, one document)"
        end
        notes += strays.map { |path| stray_note(path) }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: superseded.size + strays.size,
                                          unrecognized: 0, notes: notes)
      end

      def parse(document_ref)
        layer = document_ref.metadata["layer"]
        bytes_granted = File.read(document_ref.path, encoding: "UTF-8").match?(GRANT)
        if layer == "raw" && !bytes_granted
          raise ParseError, "#{document_ref.path}: raw conversion without an in-file <licence> " \
                            "(the repository statement names SII_B_clean) — outside the cone"
        end

        base = super
        metadata = base.metadata.merge(header_metadata(document_ref.path),
                                       licence_metadata(base.metadata["license"]),
                                       "layer" => layer, "volume" => document_ref.metadata["volume"])
        document = Nabu::Document.new(
          urn: base.urn, language: base.language, canonical_path: base.canonical_path,
          title: base.title, metadata: metadata.compact
        )
        base.passages.each { |passage| document << passage }
        document
      end

      private

      def sparse_paths = SPARSE

      def ref_for(path, layer:)
        stem = File.basename(path, ".xml")
        Nabu::DocumentRef.new(
          source_id: SLUG, id: "urn:nabu:#{SLUG}:#{stem.sub(/\A~?#{FILE_PREFIX}/o, '')}",
          path: File.expand_path(path),
          metadata: { "stem" => stem, "layer" => layer, "volume" => volume_of(path) }
        )
      end

      # SII_B_clean/SII04/… and SII_A_raw/3out/04/… both read "SII04".
      def volume_of(path)
        dir = File.basename(File.dirname(path))
        dir.start_with?("SII") ? dir : "SII#{dir}"
      end

      def clean_xml(workdir)
        Dir.glob(File.join(workdir, XML_DIR, "*", "*.xml")).sort # rubocop:disable Lint/RedundantDirGlobSort -- the urn-order guarantee, stated
      end

      def raw_xml(workdir)
        Dir.glob(File.join(workdir, RAW_DIR, "*", "*.xml")).sort # rubocop:disable Lint/RedundantDirGlobSort -- the urn-order guarantee, stated
      end

      def clean_paths(workdir) = clean_xml(workdir).select { |path| prefixed?(path, FILE_PREFIX) }

      def raw_paths(workdir) = raw_xml(workdir).select { |path| prefixed?(path, RAW_PREFIX) }

      # The base family's xml census reads the clean slice.
      def xml_paths(workdir) = clean_xml(workdir)

      def prefixed?(path, prefix) = File.basename(path).start_with?(prefix)

      def stem_of(path) = File.basename(path, ".xml").sub(/\A~?#{FILE_PREFIX}/o, "")

      # key => the ranges (or the exact stem, for an unparsed key) the clean
      # editions hold.
      def coverage(clean)
        clean.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |path, held|
          key, range = self.class.inscription_key(stem_of(path))
          held[key] << range
        end
      end

      def superseded?(path, held)
        key, range = self.class.inscription_key(stem_of(path))
        return false unless held.key?(key)
        return true if range.nil?

        held[key].any? { |other| other && other.first <= range.last && range.first <= other.last }
      end

      def stray_note(path)
        name = File.basename(path)
        if name.start_with?(RAW_PREFIX)
          "#{name}: in-progress clean file (arrives in SII_B_clean by promotion)"
        else
          "#{name}: not a DHARMA_ edition file"
        end
      end

      def licence_metadata(in_file)
        { "license" => in_file || BY_SA, "license_basis" => in_file ? IN_FILE : REPO_STATEMENT }
      end

      def header_metadata(path)
        doc = Nokogiri::XML(File.read(path, encoding: "UTF-8"))
        doc.remove_namespaces!
        title = squeeze(doc.at_xpath("//teiHeader//titleStmt/title[not(@type)]")&.text)
        alt = squeeze(doc.at_xpath('//teiHeader//titleStmt/title[@type="alt"]')&.text)
        prose = summary(doc)
        facts = self.class.title_facts(alt)
        facts["date"] ||= self.class.summary_date(prose)
        {
          "sii_volume" => title[/\ASII (\d+)\./, 1]&.to_i,
          "sii_number" => title[/\ASII \d+\.(\S+?):/, 1],
          "original_editor" => title[/original edition by (.+)\z/, 1],
          "alt_title" => alt,
          "editors" => editors(doc),
          "summary" => prose,
          "script_rendition" => doc.at_xpath('//body//div[@type="edition"]/@rendition')&.value,
          "revision_status" => doc.at_xpath("//revisionDesc/change[@status][1]/@status")&.value
        }.merge(facts).reject { |_, value| value.nil? || value == "" || value == [] }
      end

      def squeeze(text) = Normalize.nfc(text.to_s.gsub(/\s+/, " ").strip)

      def editors(doc)
        doc.xpath("//teiHeader//titleStmt/respStmt/persName").filter_map do |person|
          name = squeeze(person.text)
          name.empty? ? nil : name
        end.uniq
      end

      def summary(doc)
        paragraphs = doc.xpath("//msContents/summary//p").map { |p| squeeze(p.text) }.reject(&:empty?)
        paragraphs.empty? ? nil : paragraphs.join("\n")
      end
    end
  end
end
