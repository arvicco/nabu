# frozen_string_literal: true

require "json"

module Nabu
  module Adapters
    # GregoBase (gregobase.selapa.net) — the community-transcribed database
    # of Gregorian chant scores in GABC, the plain-text notation of the
    # Gregorio typesetting project. Started by Olivier Berten as a personal
    # project; most of its content came from The Caecilia Project and from
    # volunteers typesetting whole books (the Solesmes graduals and
    # antiphonals, the Dominican Graduale and Antiphonarium, the Palmer &
    # Burgess English gradual, the Hartker antiphoner of St Gall…).
    #
    # == Canonical artifact: upstream's own database export
    #
    # The site's maintainer publishes the full database as a phpMyAdmin
    # dump, `gregobase_online.sql` (17,173,291 bytes at the 2024-01-05
    # "Update DB" commit 2ebcda3), in the site's code repository
    # github.com/gregorio-project/GregoBase, fetched by the ordinary
    # GitFetch path. Cadence: irregular — 17 dump commits 2016-01-13 →
    # 2024-01-05 (the repo's later commits touch the PHP code only); the
    # live site has grown past the dump (third-party scrapes exist, e.g.
    # bbloomf/gregobase-backup, 20,805 chant ids at 2026-10-28), but the dump
    # is the export upstream itself publishes, the only bulk route carrying
    # the `copyrighted` flag, and stable at a public URL. No pin: a newer
    # dump is new content under the same CC0 statement.
    #
    # == License (verbatim)
    #
    # The site's About page (https://gregobase.selapa.net/?page_id=2): "All
    # chant transcriptions are released under CC0 (a.k.a. Public Domain)
    # license." (linking creativecommons.org/publicdomain/zero/1.0/) → open.
    # The 33 rows upstream flags `copyrighted` (chant.php: "This tune is
    # still under copyright." and no download offered) are skipped by rule.
    #
    # == Shape: one chant row = one document
    #
    # gregobase_chants (18,762 rows at 2ebcda3) → urn:nabu:gregobase:<id>,
    # title = the incipit. Its `gabc` column is JSON: a string (one score)
    # or an array of [layer, content, {}] elements interleaving "gabc"
    # scores with "tex" blocks. Passages, in record order:
    #   :<n>            the n-th GABC element (upstream's own "Element n"
    #                   download numbering; a string is element 1)
    #   :tex-<k>        a TeX element that carries text (rubrics such as
    #                   "Omnes : Glória, laus. ut supra.", typeset psalm
    #                   verses); layout-only TeX (\grechangedim …) drops
    #   :verses-<k>     the gabc_verses column (further hymn stanzas),
    #                   split at its verse numbers
    #   :tex-verses-<k> the tex_verses column (TeX-typeset verses), split
    #                   at blank lines
    # Passage text = the sung text (GabcParser: notes, clefs, bars, NABC,
    # <v> TeX, <alt> above-staff text and [..] translation lines drop); the
    # raw GABC/TeX rides each passage's annotations ("gabc" / "tex") so the
    # notation layer is preserved whole. A chant whose scores carry no
    # syllable text at all is skipped by rule (DocumentSkipped).
    #
    # == Mined fields (document metadata)
    #
    # cantus_id (the Cantus Index chant id — the cross-shelf chant-identity
    # key; upstream's sentinel "0" drops), office_part (upstream's usage
    # code; its Latin label from the site's own include/txt.php table rides
    # as office_part_label; the kind axis folds the code — kind_map.yml),
    # mode + mode_var verbatim, version (the edition/tradition the
    # transcription follows), transcriber, commentary (scripture refs,
    # sometimes TeX-marked — verbatim), remarks, the tags (liturgical
    # occasion / usage labels), the inline GABC header when a score carries
    # one, and sources: the books each chant was transcribed from or found
    # in (gregobase_chant_sources ⋈ gregobase_sources: title, editor, year,
    # period, page, description). Columns deliberately not carried:
    # `initial` (drop-cap typesetting flag), `headers` (NULL on every row),
    # a book's `caption`/`pages`/`urls` (scan credits and page-image maps).
    #
    # Dating (the structured shape, TimelineBuilder): a chant found in a
    # MANUSCRIPT source (the books carrying a `period`: the Hartker
    # antiphoner, Cod. Sang. 390/391, "around 990-1000"; Cod. Lichtenthal
    # 28, "mid XIIIth c.") dates by that witness, class-less (the artifact's
    # own date); otherwise its printed books' years give an edition-class
    # envelope (min..max). No source with a year → no date claim.
    # Places: none claimed — a book's `editor` names the editing house
    # (Solesmes, Vatican, Westmalle, Dominican…), not an imprint place, and
    # the codices' `description` names their present library (custody, not
    # origin); both ride verbatim in sources.
    #
    # == Language
    #
    # Latin by default; upstream's own `version` field names the vernacular
    # and Greek transcriptions (VERSION_LANGUAGES, every row read on the
    # full dump), and the four vernacular rows of two mixed versions are
    # listed by id (CHANT_LANGUAGES). Greek-versioned rows without Greek
    # letters are romanized (grc-Latn: the "Byzantine" row). A script +
    # stopword census over the Latin-default rows found no further
    # vernacular text; a Latin chant carrying English or Greek rubrics
    # (Kyrie eleison, "Choir repeats") stays lat. One language per chant,
    # passages inheriting it — deliberately coarse, declared.
    #
    # == Rejected row grains (skipped by rule, censused in discovery_skips)
    #
    # copyrighted = 1 (33); duplicateof > 0 — a retired duplicate whose page
    # redirects to the kept chant (276); duplicateof = -1 — withdrawn, the
    # page redirects to the score list (19); an empty gabc column (17, 13 of
    # them also duplicates). Census at 2ebcda3: 18,762 rows − 332 skipped =
    # 18,430 documents discovered.
    class Gregobase < Nabu::Adapter
      REPO_URL = "https://github.com/gregorio-project/GregoBase"
      DUMP_FILENAME = "gregobase_online.sql"
      URN_PREFIX = "urn:nabu:gregobase:"
      CHANT_URL = "https://gregobase.selapa.net/chant.php?id=%d"

      # The site's own usage labels (include/txt.php $txt['usage']).
      OFFICE_PARTS = {
        "al" => "Alleluia", "an" => "Antiphona", "ca" => "Canticum", "co" => "Communio",
        "gr" => "Graduale", "hy" => "Hymnus", "in" => "Introitus", "im" => "Improperia",
        "ky" => "Kyriale", "of" => "Offertorium", "pa" => "Prosa", "ps" => "Psalmus",
        "re" => "Responsorium", "rb" => "Responsorium breve", "rh" => "Rhythmus",
        "se" => "Sequentia", "su" => "Supplicatio", "tr" => "Tractus", "tp" => "Tropa",
        "or" => "Toni Communes", "pr" => "Praefationes", "va" => "Varia"
      }.freeze

      # Upstream `version` values naming a non-Latin transcription (full-dump
      # census at 2ebcda3, every row of each read: all of each version's
      # rows are in that language). "Portugal" (8 rows, 6 of them Latin
      # propers) and "French"/"french" (4 rows, 2 Latin) are NOT
      # version-wide claims — their vernacular rows ride CHANT_LANGUAGES.
      VERSION_LANGUAGES = {
        "Palmer & Burgess" => "eng",           # 721 — the English plainchant gradual (Wantage)
        "English" => "eng",
        "Old English (Faeder Ure)" => "ang",   # the Pater noster in Old English
        "Annamitice" => "vie",                 # 180 — Vietnamese
        "Annamitice Novus Ordo" => "vie",
        "Annamitice - VKP" => "vie",
        "Polish" => "pol",                     # 17
        "Español" => "spa",
        "Chmerice" => "khm",                   # Khmer
        "Sinice" => "zho",                     # Chinese (the Regina caeli)
        "Graece " => "grc",
        "Graece transliteratum" => "grc",
        "Byzantine" => "grc"
      }.freeze
      # Single vernacular rows inside a mixed version (the same census).
      CHANT_LANGUAGES = {
        18_412 => "por", 18_413 => "por", # "Portugal": Ressuscitei…, Um dos soldados…
        17_676 => "fra", 17_924 => "fra"  # "French"/"french": Un seul Dieu…, Les portes du Paradis…
      }.freeze
      DEFAULT_LANGUAGE = "lat"
      GREEK = /\p{Greek}/

      CANTUS_SENTINELS = ["", "0"].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "gregobase",
        name: "GregoBase — a database of Gregorian scores (gregobase.selapa.net)",
        license: "CC0 1.0 — \"All chant transcriptions are released under CC0 (a.k.a. Public Domain) " \
                 "license.\" (gregobase.selapa.net/?page_id=2)",
        license_class: "open",
        upstream_url: REPO_URL,
        parser_family: "gabc"
      )

      def self.manifest
        MANIFEST
      end

      # +repo_url+ exists for the tests (a local upstream); no-arg
      # construction stays the registry contract.
      def initialize(repo_url: REPO_URL)
        super()
        @repo_url = repo_url
        @corpus = {}
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: @repo_url, workdir: workdir, progress: progress, force: force)
      end

      # One DocumentRef per accepted chant row, in id order. A workdir
      # without the dump (never fetched) yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        dump = File.join(workdir, DUMP_FILENAME)
        return unless File.file?(dump)

        corpus_for(File.expand_path(dump)).chants.each_value do |row|
          next if skip_reason(row)

          block.call(Nabu::DocumentRef.new(
                       source_id: MANIFEST.id, id: "#{URN_PREFIX}#{row.fetch('id')}",
                       path: File.expand_path(dump), metadata: { "title" => title_of(row) }.compact
                     ))
        end
      end

      # The rejected row grains (class note), one reason per row.
      def discovery_skips(workdir)
        dump = File.join(workdir, DUMP_FILENAME)
        return Nabu::Adapter::DiscoverySkips.new unless File.file?(dump)

        reasons = corpus_for(File.expand_path(dump)).chants.each_value.filter_map { |row| skip_reason(row) }.tally
        notes = SKIP_REASONS.filter_map do |reason, label|
          "#{reasons[reason]} #{label}" if reasons[reason]
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: reasons.values.sum, notes: notes)
      end

      def parse(document_ref)
        corpus = corpus_for(document_ref.path)
        id = Integer(document_ref.id.delete_prefix(URN_PREFIX), exception: false)
        row = id && corpus.chants[id]
        raise Nabu::ParseError, "#{document_ref.path}: no chant row for #{document_ref.id}" if row.nil?

        build_document(corpus, row, urn: document_ref.id, path: document_ref.path)
      rescue ValidationError, JSON::ParserError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      SKIP_REASONS = {
        copyrighted: "upstream-flagged copyrighted (copyrighted = 1)",
        duplicate: "retired duplicate(s) (duplicateof > 0 — the page redirects to the kept chant)",
        withdrawn: "withdrawn (duplicateof = -1 — the page redirects to the score list)",
        no_gabc: "without GABC (empty gabc column)"
      }.freeze

      # chant column → document metadata key (verbatim when non-empty).
      TEXT_FIELDS = {
        "office-part" => "office_part", "mode" => "mode", "mode_var" => "mode_var",
        "version" => "version", "transcriber" => "transcriber", "commentary" => "commentary",
        "remarks" => "remarks"
      }.freeze
      # book columns carried per cited source (plus page/description/source_id).
      SOURCE_FIELDS = %w[title editor year period].freeze

      private

      def skip_reason(row)
        return :copyrighted if row["copyrighted"].to_i == 1
        return :duplicate if row["duplicateof"].to_i.positive?
        return :withdrawn if row["duplicateof"].to_i.negative?

        :no_gabc if blank?(row["gabc"])
      end

      def blank?(value) = value.to_s.strip.empty?
      def nfc(value) = Normalize.nfc(value.to_s)

      def title_of(row)
        blank?(row["incipit"]) ? nil : nfc(row["incipit"].strip)
      end

      # -- corpus loading (one streaming pass per table, memoized per dump) --

      Corpus = Data.define(:chants, :sources, :chant_sources, :tags, :chant_tags)
      private_constant :Corpus

      def corpus_for(path)
        @corpus[path] ||= load_corpus(path)
      end

      def load_corpus(path)
        parser = CorphSqlParser.new(path)
        chants = parser.each_row("gregobase_chants").sort_by { |row| row.fetch("id") }.to_h { |row| [row["id"], row] }
        Corpus.new(
          chants: chants,
          sources: parser.each_row("gregobase_sources").to_h { |row| [row.fetch("id"), row] },
          chant_sources: group(parser.each_row("gregobase_chant_sources"), "chant_id"),
          tags: parser.each_row("gregobase_tags").to_h { |row| [row.fetch("id"), row.fetch("tag")] },
          chant_tags: group(parser.each_row("gregobase_chant_tags"), "chant_id")
        )
      end

      def group(rows, key)
        rows.with_object({}) { |row, map| (map[row.fetch(key)] ||= []) << row }
      end

      # -- document building --------------------------------------------------

      def build_document(corpus, row, urn:, path:)
        units = passage_units(row)
        if units.empty?
          raise DocumentSkipped.new("#{urn}: no sung text in any score (notation only)",
                                    reason: "no sung text (notation-only score)")
        end

        language = language_of(row, units)
        document = Document.new(urn: urn, language: language, title: title_of(row),
                                canonical_path: path, metadata: document_metadata(corpus, row))
        units.each_with_index do |(suffix, text, annotations), sequence|
          document << Passage.new(urn: "#{urn}:#{suffix}", language: language, text: nfc(text),
                                  annotations: annotations, sequence: sequence)
        end
        document
      end

      # [[urn suffix, text, annotations]] in record order (class note).
      def passage_units(row)
        units = []
        score = 0
        tex = 0
        elements(row).each do |layer, raw|
          case layer
          when "gabc"
            score += 1
            text = GabcParser.text(raw)
            next if text.empty?

            units << [score.to_s, text, { "layer" => "gabc", "element" => score, "gabc" => nfc(raw) }]
          when "tex"
            text = GabcParser.tex_text(raw)
            units << ["tex-#{tex += 1}", text, { "layer" => "tex", "tex" => nfc(raw) }] unless text.empty?
          end
        end
        units.concat(verse_units(row))
      end

      def verse_units(row)
        units = GabcParser.verse_chunks(row["gabc_verses"].to_s).each_with_index.map do |chunk, index|
          ["verses-#{index + 1}", GabcParser.text(chunk), { "layer" => "gabc_verses", "gabc" => nfc(chunk) }]
        end
        stanzas = GabcParser.tex_stanzas(row["tex_verses"].to_s).filter_map do |stanza|
          text = GabcParser.tex_text(stanza)
          [text, stanza] unless text.empty?
        end
        stanzas.each_with_index do |(text, stanza), index|
          units << ["tex-verses-#{index + 1}", text, { "layer" => "tex_verses", "tex" => nfc(stanza) }]
        end
        units
      end

      # The `gabc` column's JSON: a string score, or [layer, content, {}]
      # elements. An unknown layer is damage, never silently dropped.
      def elements(row)
        value = JSON.parse(row["gabc"].to_s)
        case value
        when String then [["gabc", value]]
        when Array
          value.map do |element|
            layer, raw = element
            unless %w[gabc tex].include?(layer) && raw.is_a?(String)
              raise Nabu::ParseError, "chant #{row['id']}: unknown gabc element #{element.inspect[0, 80]}"
            end

            [layer, raw]
          end
        else raise Nabu::ParseError, "chant #{row['id']}: gabc column is neither a score nor an element list"
        end
      end

      def language_of(row, units)
        language = CHANT_LANGUAGES[row["id"]] || VERSION_LANGUAGES.fetch(row["version"].to_s, DEFAULT_LANGUAGE)
        return language unless language == "grc"

        units.any? { |_, text, _| text.match?(GREEK) } ? "grc" : "grc-Latn"
      end

      # -- document metadata ---------------------------------------------------

      def document_metadata(corpus, row)
        id = row.fetch("id")
        meta = { "gregobase_id" => id, "url" => format(CHANT_URL, id) }
        cantus = row["cantusid"].to_s.strip
        meta["cantus_id"] = nfc(cantus) unless CANTUS_SENTINELS.include?(cantus)
        TEXT_FIELDS.each { |column, key| meta[key] = nfc(row[column].strip) unless blank?(row[column]) }
        meta["office_part_label"] = OFFICE_PARTS[meta["office_part"]] if OFFICE_PARTS.key?(meta["office_part"])
        header = gabc_header(row)
        meta["gabc_header"] = header unless header.empty?
        tags = (corpus.chant_tags[id] || []).filter_map { |link| corpus.tags[link["tag_id"]] }.map { |tag| nfc(tag) }
        meta["tags"] = tags unless tags.empty?
        sources = chant_sources(corpus, id)
        meta["sources"] = sources unless sources.empty?
        date = date_claim(sources)
        meta["date"] = date if date
        meta
      end

      # The first inline GABC header among the scores (values NFC).
      def gabc_header(row)
        elements(row).each do |layer, raw|
          next unless layer == "gabc"

          header, = GabcParser.split_header(raw)
          next if header.empty?

          return header.transform_values { |value| value.is_a?(Array) ? value.map { |v| nfc(v) } : nfc(value) }
        end
        {}
      end

      def chant_sources(corpus, id)
        links = (corpus.chant_sources[id] || []).sort_by { |link| link["source"] }
        links.map do |link|
          book = corpus.sources[link["source"]] || {}
          entry = SOURCE_FIELDS.to_h { |field| [field, book[field]] }
          entry["page"] = link["page"]
          entry["description"] = book["description"]
          entry["source_id"] = link["source"]
          entry.reject { |_, value| value.nil? || value == "" }
               .transform_values { |value| value.is_a?(String) ? nfc(value.strip) : value }
        end
      end

      # Class note: a manuscript witness dates by its codex (class-less);
      # else the printed books' years, class edition.
      def date_claim(sources)
        witnesses = sources.select { |source| source["period"] && source["year"] }
        if witnesses.any?
          years = witnesses.flat_map { |source| witness_years(source) }
          raw = witnesses.map { |source| "#{source['title']} (#{source['period']})" }.join("; ")
          return { "not_before" => years.min, "not_after" => years.max, "raw" => raw }
        end

        printed = sources.select { |source| source["year"] }
        return nil if printed.empty?

        years = printed.map { |source| source["year"] }
        { "not_before" => years.min, "not_after" => years.max, "class" => "edition",
          "raw" => printed.map { |source| "#{source['title']} (#{source['year']})" }.uniq.join("; ") }
      end

      # "around 990-1000" → [990, 1000]; a period without its own years
      # ("mid XIIIth c.") falls back to the book's typed year.
      def witness_years(source)
        stated = source["period"].to_s.scan(/\b\d{3,4}\b/).map(&:to_i)
        stated.size >= 2 ? stated.minmax : [source["year"]]
      end
    end
  end
end
