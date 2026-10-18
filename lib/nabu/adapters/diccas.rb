# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # DiCCAS — the Disaster Corpus in Classical Arabic Sources (P95-4,
    # the long-tail sweep; CLARIN.SI hdl 11356/2097, Cicola, University
    # of Bologna 2025). One 3.6 MB TEI file of disaster accounts
    # excerpted from ten classical sources — the Qurʾān, Ṣaḥīḥ Muslim,
    # Ṣaḥīḥ al-Bukhārī, al-Ṭabarī's history and tafsīr, Ibn Taghrībirdī,
    # al-Maqrīzī, al-Dhahabī, Ibn al-Jawzī, al-Jāḥiẓ — with catastrophe
    # terminology tagged. License: deposit page AND in-file <licence>
    # agree, CC BY-NC-SA 4.0 → nc. The arabic desk's third member.
    #
    # == Shape
    #
    # Document = one <div1 type="book"> (10 upstream; title = the
    # header's msDesc msName by matching @n; genre = the div1's @ana —
    # religious/history/tafsir, "#" stripped). Passage = one <p>, text
    # at paragraph grain; citation = the div @n ladder + p ordinal
    # within its division ("2.155.p1" — positional at the leaf, stable
    # because the deposit is frozen and sync_policy is manual).
    #
    # == The gloss policy (the censused quirk)
    #
    # Most paragraphs embed an English translation as
    # <gloss ana="translation" xml:lang="en"> INSIDE the Arabic <p>.
    # The gloss never enters the passage text (the text is the Arabic
    # source, not a bilingual soup); it rides the passage annotations
    # as "gloss_en" — searchable context, honestly labelled machine-side
    # metadata of the corpus's own making. <term>/<hi>/<placeName> stay
    # reading text (the passage text is unchanged by any tag).
    #
    # == The tagged layers (mined, censused over the full deposit 2026-10-18)
    #
    # * <placeName translation="Egypt"> (2,779; Egypt 501 · Damascus 270 ·
    #   Cairo 235 · Sham 204 · Baghdad 150 …) → passage annotation
    #   "places" [{name, translation}], and per book the distinct
    #   translations as "places_mentioned" (the place_mentioned facet).
    #   These are places the accounts are ABOUT — never the book's origin,
    #   so no axis place claim is minted (places posture: unplaced, noted).
    #   Only paragraph-borne tags count (the 129 in heads/the header
    #   imprint are not passage text).
    # * <term type="catastrophe" translation="wind" subtype="divine">
    #   (2,521; 454 subtyped) → passage annotation "catastrophes"
    #   [{term, translation, subtype}], verbatim; per book the distinct
    #   translations as "disaster_types" (the disaster facet — ONE fold:
    #   the 167 "earhquake" spellings join "earthquake", an upstream typo
    #   of the same label) and the distinct subtypes as "disaster_classes"
    #   ("divine,unspecified" splits on the comma).
    # * <byline> per book (9 of 10; the Qurʾān has none): the author's
    #   Arabic name + its transliteration gloss ("author", "author_ar")
    #   and <date type="birth|death"> life dates ("author_life") — written
    #   AH/CE ("194/810") or, for two authors, CE/AH ("767/150",
    #   "1126/510"), read by magnitude (for these centuries CE > AH), the
    #   CE half kept as upstream states it; Muslim's carries a bare CE
    #   year with @when. The life span is the dating lane's envelope
    #   ("date", class composition — the work was written within it).
    # * The header msDesc listBibl per book: the source EDITION's imprint
    #   (author/title/editor/publisher/pubPlace/date + refs) → "edition",
    #   verbatim, "no data" fillers absent — edition lineage, never
    #   projected. Book 4's bibl swaps <author> and <title> upstream;
    #   carried as written.
    # * <persName> (43 isnād transmitters/actors) stays reading text — a
    #   declared remainder for the person lane.
    class Diccas < Nabu::Adapter
      FILE_URL = "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/2097/" \
                 "DiCCAS.tei.xml?sequence=21&isAllowed=y"
      FILENAME = "DiCCAS.tei.xml"

      LANGUAGE = "ara"

      URN_PREFIX = "urn:nabu:diccas:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "diccas",
        name: "DiCCAS — Disaster Corpus in Classical Arabic Sources (Cicola, Bologna)",
        license: "CC BY-NC-SA 4.0 (deposit page: \"Creative Commons - " \
                 "Attribution-NonCommercial-ShareAlike 4.0 International\"; in-file <licence> " \
                 "agrees; cite Cicola, hdl 11356/2097)",
        license_class: "nc",
        upstream_url: "http://hdl.handle.net/11356/2097",
        parser_family: "diccas-tei"
      )

      def self.manifest
        MANIFEST
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: FILE_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, FILENAME)
        return unless File.file?(path)

        corpus(path).books.each do |book|
          block.call(Nabu::DocumentRef.new(
                       source_id: manifest.id, id: "#{URN_PREFIX}#{book[:n]}",
                       path: File.expand_path(path), metadata: { "n" => book[:n] }
                     ))
        end
      end

      def parse(document_ref)
        book = corpus(document_ref.path).books.find { |b| b[:n] == document_ref.metadata["n"] } or
          raise ParseError, "#{document_ref.path}: book #{document_ref.metadata['n']} vanished"

        document = Document.new(
          urn: document_ref.id, language: LANGUAGE, title: book[:title],
          canonical_path: document_ref.path, metadata: book_metadata(book)
        )
        book[:passages].each_with_index do |unit, sequence|
          document << Passage.new(
            urn: "#{document_ref.id}:#{unit[:citation]}", language: LANGUAGE,
            text: unit[:text],
            annotations: { "unit" => "p", "gloss_en" => unit[:gloss],
                           "places" => presence(unit[:places]),
                           "catastrophes" => presence(unit[:catastrophes]) }.compact,
            sequence: sequence
          )
        end
        raise ParseError, "#{document_ref.path}: book #{book[:n]} has no paragraphs" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::FileFetch.new(url: FILE_URL, dir: workdir, filename: FILENAME,
                                    attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        fetch.prepare!
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: nil)
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "diccas fetch failed into #{workdir}: #{e.message}"
      end

      # The one typo fold of the disaster facet (class comment).
      DISASTER_FOLDS = { "earhquake" => "earthquake" }.freeze

      LIFE_PAIR = %r{\A(\d{1,4})\s*/\s*(\d{1,4})\z}
      LIFE_YEAR = /\A(\d{3,4})\z/
      WHEN_YEAR = /\A0*(\d{1,4})\z/

      # One byline life date → {"raw", "ce", "ah"?}, nil when it does not
      # parse. A slash pair is AH/CE in either order — the larger number
      # is the CE year (true for every year after AD 622); a bare year is
      # CE (Muslim's, whose @when agrees).
      def self.life_year(text, when_attr: nil)
        raw = text.to_s.strip
        if (pair = LIFE_PAIR.match(raw))
          ah, ce = [Integer(pair[1], 10), Integer(pair[2], 10)].minmax
          return { "raw" => raw, "ce" => ce, "ah" => ah }
        end
        year = raw[LIFE_YEAR, 1] || when_attr.to_s[WHEN_YEAR, 1]
        year && { "raw" => raw, "ce" => Integer(year, 10) }
      end

      private

      def presence(list)
        list.nil? || list.empty? ? nil : list
      end

      def book_metadata(book)
        catastrophes = book[:passages].flat_map { |unit| unit[:catastrophes] }
        places = book[:passages].flat_map { |unit| unit[:places] }
        {
          "genre" => book[:genre], "book" => book[:n],
          # P109-4: the per-book genre word (religious/history/
          # tafsir/adab) projected as a facet.
          "facets" => (book[:genre] ? { "genre" => { "value" => book[:genre] } } : nil),
          "author" => book.dig(:byline, :author), "author_ar" => book.dig(:byline, :author_ar),
          "author_life" => book.dig(:byline, :life),
          "date" => life_envelope(book.dig(:byline, :life)),
          "edition" => book[:edition],
          "disaster_types" => presence(catastrophes.map { |t| DISASTER_FOLDS.fetch(t["translation"], t["translation"]) }
                                                   .compact.uniq),
          "disaster_classes" => presence(catastrophes.flat_map { |t| t["subtype"].to_s.split(",") }
                                                     .map(&:strip).reject(&:empty?).uniq),
          "places_mentioned" => presence(places.filter_map { |pl| pl["translation"] }.uniq)
        }.compact
      end

      # The author-life envelope, class composition; nil without a date.
      def life_envelope(life)
        return nil if life.nil?

        birth = life["birth"]
        death = life["death"]
        raw = [birth && "b. #{birth['raw']}", death && "d. #{death['raw']}"].compact.join(" – ")
        { "not_before" => birth&.dig("ce"), "not_after" => death&.dig("ce"), "raw" => raw,
          "class" => "composition" }
      end

      # One DOM parse per file, memoized per path+mtime (the whole corpus
      # is one 3.6 MB document — the <5 MB house DOM ceiling).
      def corpus(path)
        key = [path, File.mtime(path)]
        return @corpus[1] if @corpus && @corpus[0] == key

        doc = Nokogiri::XML(File.read(path), &:strict)
        doc.remove_namespaces!
        @corpus = [key, Extraction.new(doc).call]
        @corpus[1]
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # The one-pass extraction: header msNames by @n, then each div1's
      # paragraph units with ladder citations and the gloss split.
      class Extraction
        Result = Data.define(:books)

        def initialize(doc)
          @doc = doc
        end

        def call
          titles = @doc.xpath("//sourceDesc/msDesc").to_h do |ms|
            [ms["n"], ms.at_xpath(".//msName")&.text&.strip]
          end
          editions = @doc.xpath("//sourceDesc/msDesc").to_h { |ms| [ms["n"], edition(ms)] }
          books = @doc.xpath("//body/div1").map do |div1|
            n = div1["n"]
            {
              n: n, title: titles[n] || "Book #{n}",
              genre: div1["ana"]&.delete_prefix("#"),
              byline: byline(div1.at_xpath("./byline")), edition: editions[n],
              passages: passages(div1)
            }
          end
          Result.new(books: books)
        end

        # The header imprint fields per msDesc ("no data" fillers absent).
        EDITION_FIELDS = { "author" => "author", "title" => "title", "editor" => "editor",
                           "publisher" => "publisher", "pub_place" => "pubPlace", "date" => "date" }.freeze
        NO_DATA = "no data"

        private

        def edition(ms_desc)
          bibl = ms_desc.at_xpath(".//listBibl/bibl") or return nil
          fields = EDITION_FIELDS.filter_map do |key, tag|
            value = squash(bibl.at_xpath("./#{tag}")&.text.to_s)
            [key, Normalize.nfc(value)] unless value.empty? || value == NO_DATA
          end.to_h
          refs = bibl.xpath("./ref").filter_map { |ref| ref["target"] }
          fields["refs"] = refs unless refs.empty?
          fields.empty? ? nil : fields
        end

        # The byline's author (the transliteration gloss sits inside or
        # beside the <name>) and its typed life dates.
        def byline(node)
          return nil if node.nil?

          name = node.at_xpath("./name[@type='author']")
          translit = node.at_xpath(".//gloss[@ana='translitteration']")
          life = %w[birth death].to_h do |type|
            date = node.at_xpath("./date[@type='#{type}']")
            [type, date && Diccas.life_year(date.text, when_attr: date["when"])]
          end.compact
          {
            author: translit && Normalize.nfc(squash(translit.text)),
            author_ar: name && Normalize.nfc(squash(name.xpath("./text()").map(&:text).join(" "))),
            life: life.empty? ? nil : life
          }.compact
        end

        def passages(div1)
          counters = Hash.new(0)
          div1.xpath(".//p").filter_map do |p|
            ladder = p.ancestors.reverse.filter_map { |a| a["n"] if a.name.start_with?("div") && a.name != "div1" }
            key = ladder.join(".")
            counters[key] += 1
            gloss = p.xpath(".//gloss").map { |g| squash(g.text) }.reject(&:empty?).join(" ")
            text = arabic_text(p)
            next nil if text.empty?

            citation = [key, "p#{counters[key]}"].reject(&:empty?).join(".")
            { citation: citation, text: text, gloss: gloss.empty? ? nil : gloss,
              places: tagged(p, "placeName") do |node|
                { "name" => tag_text(node), "translation" => node["translation"] }
              end,
              catastrophes: tagged(p, "term[@type='catastrophe']") do |node|
                { "term" => tag_text(node), "translation" => node["translation"], "subtype" => node["subtype"] }
              end }
          end
        end

        # The paragraph's tagged elements (gloss subtrees excluded),
        # mapped to compacted annotation hashes in document order.
        def tagged(paragraph, selector)
          paragraph.xpath(".//#{selector}[not(ancestor::gloss)]").map do |node|
            yield(node).reject { |_, value| value.nil? || value.strip.empty? }
          end
        end

        def tag_text(node)
          Normalize.nfc(squash(node.text))
        end

        # The passage text: the paragraph minus its gloss subtrees (the
        # embedded English translations — annotation, never text).
        def arabic_text(paragraph)
          clone = paragraph.dup
          clone.xpath(".//gloss").each(&:remove)
          Normalize.nfc(squash(clone.text))
        end

        def squash(text)
          text.gsub(/[[:space:]]+/, " ").strip
        end
      end
      private_constant :Extraction
    end
  end
end
