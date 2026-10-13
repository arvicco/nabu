# frozen_string_literal: true

require "nokogiri"

require_relative "dharma_base"
require_relative "../eras"

module Nabu
  module Adapters
    # South Indian Inscriptions — the DHARMA conversions, grant-bearing
    # subset (P122-3). github.com/erc-dharma/south-indian-inscriptions holds
    # the Archaeological Survey of India's printed SII volumes 1–42 re-keyed
    # as DHARMA EpiDoc ("SII_B_clean", README: "ERC DHARMA project online
    # editions, displayed on https://dharmalekha.info") beside the raw
    # conversion stages (SII_A_raw — OCR/mastercopy intermediates, not
    # editions). Census at HEAD 3ea671b6 (2026-10-12): 4,974 SII_B_clean
    # edition files, 3,912 of them Tamil.
    #
    # == The cone: only files that carry their OWN grant
    #
    # The repo has NO repo-level licence (no LICENSE/LICENCE file, no
    # GitHub-detected licence). 907 of the 4,974 files carry an in-file
    # <licence target="https://creativecommons.org/licenses/by-sa/4.0/">CC
    # BY-SA 4.0</licence> in publicationStmt/availability — the ones the
    # project has carried through its full conversion pass; the other
    # 4,067 carry no grant of any kind and stay OUT (deliberate and
    # documented: no grant, no ingest — they enter by themselves the day
    # upstream stamps them). Grant-bearing by volume: SII 2 (69), 3 (3),
    # 4 (2), 8 (174), 17 (54), 22 (593), 26 (11), 41 (1).
    #
    # Of those 907, 258 are "~DHARMA_" files — the family's in-progress
    # marker (upstream renames ~DHARMA_X → DHARMA_X when an edition is
    # promoted; the SII commit log shows exactly those renames). The family
    # rule holds here as in dharma-tamil: the sparse cone materializes
    # DHARMA_*.xml only, so the in-progress files arrive by promotion. The
    # source's working set today: 649 grant-bearing DHARMA_ editions.
    #
    # The grant test runs at DISCOVER over the fetched bytes (a sparse cone
    # cannot filter by content): a DHARMA_ file without an in-file <licence
    # target> is skipped by rule and censused per volume, never silently.
    #
    # == Identity
    #
    #   urn:nabu:sii-clean:<file stem sans "DHARMA_">  (…:INSSIIv22p0i0252)
    #   passage: the dharma-epidoc grain — <urn>:<line n> | <urn>:<lg n>.<l n>
    #
    # Stems are unique across the volume dirs (they carry vNN p0 iNNNN).
    # Five grant-bearing stems also have a DHARMA re-edition in
    # tfa-sii-epigraphy (dharma-tamil's INStfaSII…: SII 22.103, 22.333,
    # 26.174, 26.491, 41.265) — a different edition of the same
    # inscription (the printed SII text converted vs. DHARMA's own
    # re-reading), so both stand, each under its own urn.
    #
    # == Languages (census over the 649, 2026-10-12)
    #
    # Document codes tam-Latn 579 · san-Latn 4 · tel-Latn 4 · kan-Latn 2;
    # passages tam-Latn 8,182 · san-Latn 107 · tel-Latn 74 · kan-Latn 9.
    # "und" (6 editions) quarantines loudly — the family stance.
    #
    # == Aggressive mining (owner rule 2026-09-26) and its declared limits
    #
    # The SII editors' printed headings survive as the alt title ("No. 252.
    # (A.R. No. 252 of 1906) NORTH ARCOT DISTRICT, CHEYYAR TALUK,
    # TIRUPPANAṄGĀḌU. ŚIVA TEMPLE—ON THE SAME WALL. ACHYUTADĒVA-MAHĀRĀYA—Śaka
    # 1460."), recorded verbatim as "alt_title" and mined:
    # - "annual_report" — the Annual Report on (South-)Indian Epigraphy
    #   number and year ("A.R. No. 252 of 1906": the year the copy was
    #   made, never the inscription's date);
    # - the findspot sentence (the one naming a TALUK/DISTRICT/STATE) →
    #   "findspot" verbatim, "taluk"/"district" (colonial-era units as
    #   printed), and "place" = the village when exactly one non-unit
    #   segment remains, of at most PLACE_MAX_WORDS words (SII 8's "…TEMPLE AT
    #   GUDIMALLAM, …" reads the name after the last " AT "; a "SAME TALUK"
    #   unit names nothing, and a segment saying "SAME" is never a village).
    #   Census: 435 findspot sentences, 419 villages. SII 8's many "ON THE WEST WALL OF THE SAME
    #   SHRINE" headings inherit their place from the preceding entry —
    #   that inference is NOT made (declared coarseness);
    # - dating: the editor's own "A.D." conversion when printed ("A.D.
    #   1003-04" → [1003, 1004], basis "title A.D."), else a Śaka year
    #   through config/eras.yml (Śaka Y → Y+78, the ruled single offset;
    #   basis "title"); every such phrase rides "title_dating" verbatim.
    #   Failing both, the summary's single reign line "Year N: YYYY A.D."
    #   (SUMMARY_AD; basis "summary A.D."). Census 2026-10-12: 211 of the
    #   589 parsed docs dated — 179 title A.D., 20 title Śaka, 12 summary.
    #   Regnal years ("RĀJARĀJA I—19th YEAR") stay in the verbatim alt title
    #   only (no ruled South-Indian regnal table); hedged summary prose
    #   ("1164 or 1168 A.D. (?)", "might probably correspond to Śaka
    #   1271") is never read.
    # The header also yields "editors" (respStmt), "original_editor" (the
    # main title's "original edition by …"), "sii_volume"/"sii_number",
    # "summary" (msContents, the printed summary), "script_rendition" and
    # "revision_status" — the dharma-tamil set.
    class SiiClean < DharmaBase
      SLUG = "sii-clean"
      NAME = "South Indian Inscriptions — DHARMA editions (grant-bearing subset)"
      CREDIT_CORPUS = "South Indian Inscriptions vols. 1–42 converted to DHARMA EpiDoc " \
                      "(Archaeological Survey of India's printed editions; the original editors " \
                      "named per document)"
      REPO_URL = "https://github.com/erc-dharma/south-indian-inscriptions"
      XML_DIR = "SII_B_clean"

      SPARSE = ["/SII_B_clean/*/DHARMA_*.xml", "/SII_B_clean/README.txt"].freeze

      LANGUAGES = %w[tam-Latn san-Latn tel-Latn kan-Latn].freeze

      # The in-file grant that admits a file into the source.
      GRANT = /<licence\b[^>]*\btarget="[^"]+"/

      # The alt title's findspot sentence: the first sentence after a closing
      # parenthesis that names an administrative unit.
      FINDSPOT = /\)\.?\s*([^.]*?\b(?:TALUK|DISTRICT|STATE)\b[^.]*)\./i
      UNIT = /\b(TALUK|DISTRICT|STATE)\b/i
      SAME = /\bSAME\b/i
      PLACE_MAX_WORDS = 4 # const: a village name, not a monument description
      ANNUAL_REPORT = /A\.R\. No\. [^)]*?of \d{4}/

      # The editor's CE conversion and the Śaka phrases (census 2026-10-12:
      # 181 "A.D." headings, 27 Śaka-typed, all in SII 22).
      AD_PHRASE = /A\.\s?D\.\s*(\d{3,4})(?:\s*[-–—]\s*(\d{1,4}))?/
      SAKA_PHRASE = /\b([ŚśSs][Aa][Kk][Aa])\s+\[?(\d{3,4})\]?/

      # SII 17/26/41 summaries open with the editor's reign line "King.
      # Year N: YYYY[-YY] A.D." — a CE conversion read only when the
      # summary carries exactly one, never a hedged "(?)" or "or" reading.
      SUMMARY_AD = /\bYear \[?\d+\]?: (\d{3,4})(?:\s*[-–]\s*(\d{1,4}))? A\.\s?D\.(?!\s*\(\?\))/

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: NAME,
          license: "per-file <licence> CC BY-SA 4.0 (in publicationStmt/availability), recorded " \
                   "verbatim per document; the repo carries no licence, so only files bearing " \
                   "their own grant are ingested — class attribution",
          license_class: "attribution",
          upstream_url: REPO_URL,
          parser_family: "dharma-epidoc",
          credit: "DHARMA — #{CREDIT_CORPUS} (ERC no. 809994, EFEO/CNRS/CEIAS; " \
                  "erc-dharma/south-indian-inscriptions on GitHub, displayed on dharmalekha.info). " \
                  "Cite the SII volume, its original editor and the digital editors wherever used."
        )
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
        alt_title.scan(AD_PHRASE) { phrases << Regexp.last_match(0).strip }
        alt_title.scan(SAKA_PHRASE) { phrases << Regexp.last_match(0).strip }
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
        match = SAKA_PHRASE.match(alt_title) or return nil
        key = eras&.resolve(match[1]) or return nil
        conversion = eras.to_ce(key, Integer(match[2], 10))
        conversion.to_date_bounds.merge(
          "raw" => match[0].strip, "era" => key, "era_year" => conversion.year, "basis" => "title"
        )
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
        sentence.split(/,\s*/).each do |segment|
          if (unit = segment[UNIT])
            next if segment.match?(SAME)

            key = unit.downcase
            value = segment.sub(UNIT, "").strip
            facts[key] = value if %w[taluk district].include?(key) && !value.empty?
          else
            others << segment.strip
          end
        end
        facts.merge("place" => village(others))
      end

      def self.village(segments)
        return nil unless segments.size == 1 && !segments.first.match?(SAME)

        name = segments.first.split(/\s+AT\s+/i).last.sub(/\s+NEAR\s+.*\z/i, "").strip
        name.split.size.between?(1, PLACE_MAX_WORDS) ? name : nil
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        super do |ref|
          yield Nabu::DocumentRef.new(
            source_id: ref.source_id, id: ref.id, path: ref.path,
            metadata: ref.metadata.merge("volume" => File.basename(File.dirname(ref.path)))
          )
        end
      end

      # Grant-less editions are the documented cone boundary — censused per
      # volume (one note each), never one line per file.
      def discovery_skips(workdir)
        skipped = xml_paths(workdir).reject { |path| edition_file?(path) }
        grantless, other = skipped.partition { |path| prefixed?(path) }
        by_volume = grantless.group_by { |path| File.basename(File.dirname(path)) }
        notes = by_volume.sort.map do |volume, paths|
          "#{volume}: #{paths.size} edition(s) without an in-file <licence> grant (outside the cone)"
        end
        notes += other.map { |path| "#{File.basename(path)}: not a DHARMA_ edition file" }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped.size, unrecognized: 0, notes: notes)
      end

      def parse(document_ref)
        base = super
        document = Nabu::Document.new(
          urn: base.urn, language: base.language, canonical_path: base.canonical_path,
          title: base.title, metadata: base.metadata.merge(header_metadata(document_ref.path))
        )
        base.passages.each { |passage| document << passage }
        document
      end

      private

      def sparse_paths = SPARSE

      def xml_paths(workdir)
        Dir.glob(File.join(workdir, XML_DIR, "*", "*.xml")).sort # rubocop:disable Lint/RedundantDirGlobSort -- the urn-order guarantee, stated
      end

      def edition_file?(path)
        prefixed?(path) && File.read(path, encoding: "UTF-8").match?(GRANT)
      end

      def prefixed?(path) = File.basename(path).start_with?(FILE_PREFIX)

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
