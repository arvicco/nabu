# frozen_string_literal: true

require_relative "indexed_wikisource"

module Nabu
  module Adapters
    # ms-wikisource (P120-3, under the owner-ruled Wikisource posture): the
    # Jawi manuscript cone of the Malay Wikisource — every ns-0 page
    # transcluding one of the 74 censused MANUSCRIPT Index pages (census
    # 2026-10-12: the Index names carrying a manuscript shelfmark — Leiden
    # Or. NNNN, BL/RAS MSS Malay, BnF Malayo-polynésien, KITLV/Leiden
    # NBG-Kl., Harvard MS Indo, Princeton Garrett, Berlin Schoemann, the
    # Leiden "8196 D 33"-style numbers, the WM ID Indonesian collection).
    # The transcriptions are made straight from the manuscript scans — no
    # printed edition intervenes, so there is no edition layer to taint.
    #
    # == The watch-the-ratchet cone
    #
    # Most Page: pages sit at ProofreadPage level 1 (not proofread). The
    # cone ingests what has text and RECORDS the level histogram per page
    # (metadata "proofread"); the census is the ratchet baseline — a later
    # re-sync shows the levels climbing. The level is never a filter.
    #
    # == Dates, scribes, script (aggressive mining)
    #
    # The page {{header}} year= is the manuscript's date as the wiki states
    # it — a year ("1718"), a span, or a century ("abad ke-17" → 1601–1700);
    # the Index Year= is the fallback. Both are manuscript (artifact) dates,
    # typed upstream → "date" (MetadataDates :structured). A Hijri-marked
    # year mints nothing (never converted by guess). The header editor=
    # names the SCRIBE/copyist on these pages — it rides verbatim in
    # metadata header.editor. Taint evidence is the header and Index YEAR
    # only: the Index names and page titles carry shelfmarks ("Or. 1954"),
    # never edition years (declared).
    #
    # Language: the Index Language= must be censused (LANGUAGES — anything
    # else quarantines loudly); the tag follows the MEASURED script of the
    # text — msa-Arab for Jawi (≥ 80% Arabic-script letters), msa-Rjng for
    # Rencong, bare msa for Rumi and for mixed pages (the Rencong + Latin
    # transliteration of Syair Perahu) — and metadata "script" records the
    # measurement ("Arab", "Latn", "mixed: Rjng+Latn"). Classical Malay has
    # no ISO code of its own: msa is declared coarse.
    class MsWikisource < IndexedWikisource
      API_URL = "https://ms.wikisource.org/w/api.php"
      STATE_FILE = ".ms-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:ms-wikisource:"
      INDEX_NS = "Indeks"
      PAGE_NS = 250

      MANUSCRIPT_INDEXES = [
        "(Collective volume with texts in Malay (I-VIII) The first story only of the Hikayat Bakhtiyar ; " \
        "and other texts) Or. 3374.pdf",
        "(Six paraenetical poems with interlinear translation in Malay and Acehnese…), Or. 7977 d.pdf",
        "Bustanus Salatin, Malayo-polynésien 28.pdf",
        "Bāb Maʿrifat al-Islām wal-Īmān Or. 7176.pdf",
        "Collection of two volumes with Arabic texts and Malay translation Or. 7204 a-b.pdf",
        "Collective volume with texts in Malay Hikayat Nakhoda Muda Or. 1763.pdf",
        "Collective volume with texts in Malay and Arabic (I-VI), Or. 3370.pdf",
        "Collective volume with texts in Malay, Acehnese, Or. 7291.pdf",
        "Collective volume with texts in Malay, Jawi (Nos. 1, 2) and Rumi (No. 3) script, Or. 1761.pdf",
        "Collective volume with texts in Malay, Minangkabau, Arabic script (1-2) No. 61. Oendang oendang " \
        "adat Lembaga Or. 12.182.pdf",
        "Collective volume with texts in Malay, Or. 1626.pdf",
        "Collective volume with texts in Malay, Or. 1722.pdf",
        "Collective volume with texts in Malay, Or. 1724.pdf",
        "Collective volume with texts in Malay, Or. 1726.pdf",
        "Collective volume with texts in Malay, Or. 1741.pdf",
        "Collective volume with texts in Malay, Or. 3346.pdf",
        "Egerton ms 933 Kitab Malayo a Malay and English Vocabulary (1731).pdf",
        "Hidayatus Salikin al-Falimbani Malayo-polynésien 29 btv1b10026844t.pdf",
        "Hikayat Aceh Or. 1954 (Leiden).pdf",
        "Hikayat Cekel Waneng Pati, a Panji story, Or. 1709.pdf",
        "Hikayat Darma Taʻsia ; manuscript, 1838. MS Indo 26. Houghton Library, Harvard University, " \
        "Cambridge, Mass.pdf",
        "Hikayat Iskandar Zulkarnain - volume 1 Or. 1696 1, Or. 1696 1.pdf",
        "Hikayat Nabi Allah Yusuf ; manuscript, 1836 ;.pdf",
        "Hikayat Pelanduk Jenaka Malayo-polynésien 70 btv1b53170465w.pdf",
        "Hikayat Pelanduk Jenaka Or. 1932.pdf",
        "Hikayat Pelanduk Jinaka, and other texts in Malay and Bugis texts MSS Malay B 10.pdf",
        "Hikayat Perang Pandawa Jaya MSS Malay B 12.pdf",
        "Hikayat Raja-Raja Pasai Malayo-polynésien 50 btv1b10088842g.pdf",
        "Hikayat Si Miskin Or. 3319.pdf",
        "Hikayat Sri Rama, a Malay version of the Indian epic of Rama Or. 1689 - part 1, Or. 1689 1.pdf",
        "Hikayat Sri Rama, a Malay version of the Indian epic of Rama Or. 1689 - part 2, Or. 1689 2.pdf",
        "Hikayat Tanah Hitu ; The History of Hitu between 1450-1643 - Or. 5448.pdf",
        "Hikayat negeri Jambi Or. 2013.pdf",
        "Hukum Mŭm-bhagi pusaka; manuscript, 1832. MS Indo 13. Houghton Library, Harvard University, " \
        "Cambridge, Mass.pdf",
        "Ikhtisar Ceritera Daripada Raja-raja di Negeri Siam Or. 2011.pdf",
        "Kitab Tibb Or. 1714.pdf",
        "Kitab tafsir (Turjuman al-Mustafid juz 2) Garrett no. 492Lq.pdf",
        "MSS Malay A2 Syair Perahu 1700.pdf",
        "MSS Malay D 3.pdf",
        "Malay-Javanese-Madurese vocabulary (MSS Malay A 3).pdf",
        "Mas'alat rasmi arḍi pada menjatakan peri hal keadaan moeka boemi dengan hal ihwal segala bangsa " \
        "manoesia jang dimoeka boemi pada zaman sekarang ini, 800 B 3.pdf",
        "Mawlid al-Nabi Or. 3289.pdf",
        "NBG Kl. 191.tif",
        "NBG-Kl. 180.pdf",
        "Or. 2016.pdf",
        "Or. 2276 e.pdf",
        "Rechtsbronnen van Zuid-Sumatra M r 840.pdf",
        "Sejarah Melayu Or. 1703.pdf",
        "Sejarah Melayu Or. 3210.pdf",
        "Sja'ir kitab an-nīkah wa-mā yataʿallaqu bihi 8197 D 40.pdf",
        "Sjair perdjalanan Soeltân Lingga, M hh 52.pdf",
        "Soerat Tarasoel, 8196 D 33.pdf",
        "Syair Ken Tambuhan NBG-Kl. 149.pdf",
        "Syair Ken Tambuhan Or. 14.080.pdf",
        "Syair Ken Tambuhan Or. 1965.pdf",
        "Syair Ken Tambuhan Or. 3375.pdf",
        "Syair Ken Tambuhan, Or. 1997.pdf",
        "Syair Mekah dan Medinah SBB-PK Berlin Schoemann V 41.pdf",
        "Syair Raja Mambang Jauhari Or. 1896.pdf",
        "Syair Sinyor Kista (or Kosta) Or. 1895.pdf",
        "Syair Sultan Abdul Muluk Or. 1740.pdf",
        "Syair Sultan Abdul Muluk Or. 3368.pdf",
        "Tāj al-salāṭīn Or 13295.pdf",
        "WM ID 010 0010 (Kitab Tafsir).pdf",
        "WM ID 010 0011 - (Da'wa).pdf",
        "WM ID 010 0013 (Kamus Arab-Indonesia).pdf",
        "WM ID 010 0014 (Kitab Tafsir).pdf",
        "WM ID 010 0023 - (Fiqih Puasa).pdf",
        "WM ID 010 0025 (Kitab Tafsir).pdf",
        "WM ID 010 0031 Majmū'ah Khutbah - مجموعة خطبة.pdf",
        "WM ID 010 0034 - (Tafsir).pdf",
        "WM ID 010 0074 - (Palangkahan).pdf",
        "WM ID 010 0075 - Tarjamah Dar al-Tsamin - ترجمة دار الثمين.pdf",
        "Ṯamarat al-mahamma ḍiyāfa li-al-umarāʾ wa-al-kubarāʾ li-ahl al-maḥkaman 8196 E 20.pdf"
      ].freeze

      CONE = { categories: {}, prefixes: [], titles: [], indexes: MANUSCRIPT_INDEXES }.freeze

      INDEX_FIELDS = {
        "title" => "Title", "author" => "Author", "editor" => "Editor", "publisher" => "Publisher",
        "place" => "Address", "year" => "Year", "source" => "Source", "progress" => "Progress",
        "language" => "Language", "remarks" => "Remarks"
      }.freeze
      # editor= names the scribe/copyist on the manuscript pages (verbatim).
      HEADER_FIELDS = { "author" => "author", "editor" => "editor", "translator" => "translator",
                        "year" => "year", "section" => "section", "notes" => "notes" }.freeze
      # The WM ID 010 series is one 20th-century author's papers (census
      # 2026-10-12: every transcluding page names Syekh Abdul Lathif Syakur
      # as author; the tafsir root states year=1949 while its 21 subpages
      # state nothing) — post-1930 compositions by an author who died in
      # 1963, never PD at the ruled cutoff. The whole series is out by name.
      SYAKUR = "Syekh Abdul Lathif Syakur (1882–1963) papers — 20th-century compositions " \
               "(the tafsir root states 1949); out by the post-1930 rule, series-wide"
      EXCLUDED_INDEXES = MANUSCRIPT_INDEXES.grep(/\AWM ID 010 /).to_h { |name| [name, SYAKUR] }.freeze
      # The Index Language= values the cone carries (census 2026-10-12).
      LANGUAGES = { "ms-arab" => "msa", "ms" => "msa", "ms-latn" => "msa", nil => "msa" }.freeze
      # The measured scripts (census 2026-10-12): Jawi, Rumi, and the
      # Kerinci Rencong (Rejang block) of Syair Perahu (MSS Malay A2), which
      # the wiki transcribes line-by-line beside a Latin transliteration.
      SCRIPTS = { "Arab" => /\p{Arabic}/, "Latn" => /\p{Latin}/, "Rjng" => /\p{Rejang}/ }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "ms-wikisource",
        name: "Malay Wikisource — the Jawi manuscript cone (Leiden · BL · BnF · KITLV manuscripts)",
        license: "Hosted texts PD (pre-1930 manuscripts); the transcription layer Creative Commons " \
                 "Attribution-ShareAlike 4.0 (ms.wikisource.org footer verbatim, verified 2026-10-12) → " \
                 "attribution, credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://ms.wikisource.org/",
        parser_family: "wikisource-html",
        credit: "Malay Wikisource (ms.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      # Taint evidence = the header year= only (the Index Year= joins via
      # #envelope_edition_years): titles and Index names carry shelfmarks.
      def edition_years(_title, wikitext)
        years_in(template_args(wikitext, HEADER_TEMPLATE)["year"].to_s)
      end

      # A manuscript date as stated → [not_before, not_after] or nil.
      def manuscript_date(text)
        value = display_text(text.to_s)
        return nil if value.empty? || value.match?(/\b(H|Hijrah|Hijriah|AH)\b|هجر/i)

        case value
        when /abad\s+ke[\s\-–]*(\d{1,2})/i
          century = Integer(::Regexp.last_match(1), 10)
          [((century - 1) * 100) + 1, century * 100]
        when /(?<!\d)(\d{3,4})\s*[–-]\s*(\d{3,4})(?!\d)/
          [Integer(::Regexp.last_match(1), 10), Integer(::Regexp.last_match(2), 10)]
        when /(?<!\d)(\d{4})(?!\d)/
          year = Integer(::Regexp.last_match(1), 10)
          [year, year]
        end
      end

      private

      def language_for(envelope)
        declared = Array(envelope["indexes"]).map { |index| index_role(index, "language")&.downcase }.uniq
        declared.each do |language|
          next if LANGUAGES.key?(language)

          raise ParseError, "#{envelope['title']}: Index language #{language.inspect} is not censused " \
                            "(LANGUAGES) — quarantined, never guessed"
        end
        case script_of(envelope)
        when "Arab" then "msa-Arab"
        when "Rjng" then "msa-Rjng"
        else "msa"
        end
      end

      def extra_metadata(envelope)
        {
          "script" => script_of(envelope),
          "index_language" => index_language(envelope),
          "date" => date_claim(envelope)
        }.compact
      end

      def index_language(envelope)
        declared = Array(envelope["indexes"]).filter_map { |index| index_role(index, "language") }.uniq
        declared.empty? ? nil : declared.join(", ")
      end

      # The measured script: Arab / Latn / mixed (neither letter class ≥ 80%).
      def script_of(envelope)
        text = passages_for(envelope).map(&:text).join(" ")
        counts = SCRIPTS.transform_values { |pattern| text.scan(pattern).size }.select { |_, count| count.positive? }
        total = counts.values.sum
        return nil if total.zero?

        dominant, count = counts.max_by { |_, size| size }
        return dominant if count >= total * 0.8

        "mixed: #{counts.sort_by { |_, size| -size }.map(&:first).join('+')}"
      end

      def date_claim(envelope)
        header_year = template_args(envelope.fetch("wikitext"), HEADER_TEMPLATE)["year"]
        if (bounds = manuscript_date(header_year))
          return { "not_before" => bounds[0], "not_after" => bounds[1],
                   "raw" => Nabu::Normalize.nfc("year: #{display_text(header_year)} (header)") }
        end

        Array(envelope["indexes"]).each do |index|
          year = index_role(index, "year")
          bounds = manuscript_date(year) or next

          return { "not_before" => bounds[0], "not_after" => bounds[1],
                   "raw" => Nabu::Normalize.nfc("Year: #{year} (#{INDEX_NS}:#{index['name']})") }
        end
        nil
      end
    end
  end
end
