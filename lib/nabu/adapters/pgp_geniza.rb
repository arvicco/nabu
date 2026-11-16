# frozen_string_literal: true

require "csv"

require_relative "source_read"

module Nabu
  module Adapters
    # pgp-geniza — the Princeton Geniza Project's documentary corpus through
    # its own data export (github.com/princetongenizalab/pgp-metadata; the
    # Zenodo-deposited "Princeton Geniza Project datasets", concept DOI
    # 10.5281/zenodo.15839055): the everyday documents of the Cairo Geniza —
    # letters, court records, contracts, accounts, petitions, lists — in
    # Judaeo-Arabic above all, beside Hebrew, Aramaic and Arabic, with the
    # PGP's own digital editions and translations as plain text.
    #
    # == Grains (enumerated 2026-11-16 against the live repository)
    #
    #   data/documents.csv  one row per PGP document (pgpid) — the catalogue
    #                       and THE DOCUMENT GRAIN: shelfmark, type, tags,
    #                       description, languages, the document's own date
    #                       (original + calendar + CE standard) or a scholar's
    #                       inferred date, the place relations (origin /
    #                       destination / location / mentioned …), holding
    #                       library and collection.
    #   data/footnotes.csv  one row per (document, scholarly source) link.
    #                       A row whose doc_relation is "Digital Edition" or
    #                       "Digital Translation" carries the PGP's plain-text
    #                       transcription / translation in `content` — the
    #                       TEXT grain, folded into its document's passages.
    #                       Content-less rows (Discussion, Edition and
    #                       Translation citations) are bibliography: they ride
    #                       the document only through scholarship_records.
    #   data/fragments.csv  the material-support grain (one row per shelfmark,
    #                       pgpids " ; "-joined) — joined for provenance class
    #                       (Geniza / Probably Geniza / Not Geniza) and
    #                       material; never a document.
    #   data/sources.csv    the bibliography grain — joined by slug for a
    #                       translation's publication language; never a document.
    #   data/places.csv     the place authority — joined by name for the
    #                       origin's coordinates (DMS → WGS84 decimal).
    #   data/people.csv     the people authority — the export carries only
    #                       counts, no document links: not joined.
    #   README.md, CHANGELOG.md, CITATION.cff, pgp_datapackage.json — the
    #                       dataset's own documentation, never text.
    #
    # A document yields up to two kinds of ref: urn:nabu:pgp-geniza:<pgpid>
    # when it carries at least one digital edition, and one translation
    # sibling urn:nabu:pgp-geniza:<pgpid>-<lang> per translation language
    # (the aio / elephantine mold — kind translation, translation_of the
    # base urn). Skipped by rule, counted in discovery_skips: documents with
    # no text at all (metadata-only — the large majority); text-bearing
    # footnotes whose relation names no digital layer (legacy "Edition ;
    # Translation" / blank relations — edition vs translation undecidable);
    # text footnotes naming a pgpid absent from documents.csv (suppressed or
    # merged records) or naming no document at all.
    #
    # == Reconciliation (live census 2026-11-16, main 2234d35e)
    #
    # Upstream serves 36,512 documents.csv rows (README's v1.2 figure: 36,204
    # — the git export is rolling, ahead of the deposit) and 25,591
    # footnotes, 10,601 with content: 8,365 Digital Editions and 2,222
    # Digital Translations attached to a live document, 7 undecidable-
    # relation rows and 7 orphans (5 with no document_id, 2 naming absent
    # pgpids) — 14 skipped by rule. Text-bearing documents: 7,784 (7,669
    # with an edition, 115 translation-only); metadata-only skips = 36,512 −
    # 7,784 = 28,728. Full dry parse: 9,848 refs (7,669 editions + 2,179
    # translation siblings: en 1,396 · heb 775 · fr 7 · de 1), 303,860
    # passages, 0 parse errors. Upstream's own flags (has_transcription Y
    # 7,680 / has_translation Y 2,088) agree to the residue.
    #
    # == Passages
    #
    # One passage per non-blank content line (the PGP editions are line
    # transcriptions; translations follow them line by line or as
    # paragraphs), urn <document>:<source_slug>.<n> for editions and
    # <sibling>:<source_slug>.t<n> for translations — keyed by the edition's
    # own source slug (stable when another edition is added; the "t" keeps
    # translation lines from posing as line-aligned parallels). Several
    # editions of one document ride one document in slug order. Side labels
    # the editors write as their own lines ("Recto", "Verso, address:",
    # "Recto, top fragment") are layout, not text: they become the "side"
    # annotation of the lines that follow (a run of labels with no text
    # between rides whole, " · "-joined). Text is verbatim — editorial
    # brackets, //insertions//, [[deletions]] and "(!)" kept — NFC at this
    # boundary except Aramaic, stored byte-verbatim (NFC_EXEMPT_LANGUAGES).
    #
    # == Languages
    #
    # The document's language is its first languages_primary entry the
    # registry can name (else the first secondary, else und — 898 edition
    # documents carry no language tag upstream): Judaeo-Arabic → jrb (no
    # registry node yet; the posture records it pending), Hebrew heb,
    # Aramaic arc, Arabic ara, and the minor tags below. Numeral systems,
    # "Unidentified" and Judaeo-languages without a node stay verbatim in
    # metadata only. Declared coarse: a multi-language document's passages
    # all carry the document language. A translation's language is read
    # from its script (Hebrew → heb, Arabic → ara) or, in Latin script,
    # from its source's publication language (French/German) — else en.
    #
    # == Axes (the aggressive-mining law)
    #
    # date: doc_date_standard (the CE conversion of the document's own
    # dating; original + calendar ride raw) else inferred_date_standard (the
    # scholar's dating, basis "inferred", rationale + notes kept) — every
    # " ; "-alternative and "/"-range folded into one envelope. place: the
    # origin (where written), with its places.csv coordinates; destination
    # a second, role place (MetadataDates ROLE_PLACES); location / mentioned /
    # possibly_mentioned verbatim lists (facets). kind: the PGP type
    # (config/kind_map.yml); tags, library, collection, provenance class and
    # material project as facets (config/facet_map.yml). The axes ride ONE
    # document per pgpid — the edition when held, else the first
    # translation sibling — so a timeline row never doubles a document.
    #
    # == License (verified 2026-11-16)
    #
    # README "Sharing / access information": "Dataset is released under the
    # noncommercial Creative Commons Attribution 4.0 license (CC-BY-NC.4.0)";
    # pgp_datapackage.json licenses: CC-BY-NC-4.0; the Zenodo record's
    # license field cc-by-nc-4.0 (concept DOI 10.5281/zenodo.15839055,
    # latest v1.2 = 10.5281/zenodo.22663982). No LICENSE file and no GitHub
    # license field — the grant rests on the README + datapackage + Zenodo.
    # NonCommercial → class nc (the openiti precedent).
    #
    # == fetch / sync policy
    #
    # The house GitFetch of the repository (attic + breaker + ff-merge),
    # depth-1: upstream's history is ~2 GB of automated re-exports. main is
    # rolling (several automated export commits a day) → sync_policy manual.
    class PgpGeniza < Nabu::Adapter
      REPO_URL = "https://github.com/princetongenizalab/pgp-metadata"
      URN_PREFIX = "urn:nabu:pgp-geniza:"
      DATA_DIR = "data"

      CREDIT = "Princeton Geniza Project datasets (Princeton Geniza Lab, Princeton University; " \
               "M. Rustow and R. Koeser), https://geniza.princeton.edu, doi:10.5281/zenodo.15839055 " \
               "— CC BY-NC 4.0"

      MANIFEST = Nabu::SourceManifest.new(
        id: "pgp-geniza",
        name: "Princeton Geniza Project — documentary Geniza editions and translations (pgp-metadata)",
        license: "CC BY-NC 4.0 (README: \"Dataset is released under the noncommercial Creative Commons " \
                 "Attribution 4.0 license (CC-BY-NC.4.0)\"; pgp_datapackage.json licenses CC-BY-NC-4.0; " \
                 "Zenodo 10.5281/zenodo.15839055 license field cc-by-nc-4.0). No LICENSE file in the " \
                 "repository. Credit the Princeton Geniza Project / Princeton Geniza Lab; the editions " \
                 "and translations are drawn from the scholarly sources named on each document.",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "pgp-csv",
        credit: CREDIT
      )

      EDITION = "Digital Edition"
      TRANSLATION = "Digital Translation"

      # PGP language label → registry code. Labels absent here (numeral
      # systems, Unidentified, Judaeo-Greek/-Italian/-French/-Turkish,
      # Garshuni, Samaritan, Romance …) name no node and ride verbatim only.
      LANGUAGES = {
        "Judaeo-Arabic" => "jrb", "Hebrew" => "heb", "Aramaic" => "arc", "Arabic" => "ara",
        "Ladino" => "lad", "Judaeo-Persian" => "jpr", "Persian" => "fa", "Ottoman Turkish" => "ota",
        "Coptic" => "cop", "Greek" => "grc", "Syriac (Serto)" => "syc", "Syriac (Estrangelo)" => "syc",
        "Latin" => "lat", "Yiddish" => "yi", "Italian" => "it", "Spanish" => "es", "French" => "fr",
        "German" => "de", "English" => "en", "Portuguese" => "pt", "Catalan" => "ca"
      }.freeze

      # A Latin-script translation's language by its source's publication
      # language; anything else is English.
      LATIN_TRANSLATION_LANGUAGES = { "French" => "fr", "German" => "de" }.freeze
      TRANSLATION_NAMES = { "en" => "English", "heb" => "Hebrew", "ara" => "Arabic", "fr" => "French",
                            "de" => "German" }.freeze

      # An editor's side/margin label written as its own Latin-script line.
      SIDE_LABEL = /\A(?:(?:recto|verso)\b|
                     (?:(?:right|left|top|bottom|upper|lower|outer|inner)\s+)?margins?\b|
                     (?:(?:first|second|third|fourth|right|left|middle)\s+)?columns?\b)/xi
      SIDE_LABEL_MAX = 60
      SIDE_JOIN = " · "

      # A date-standard side: YYYY[-MM[-DD]] (3–4 digit CE years).
      DATE_SIDE = /\A(\d{3,4})(?:-\d{2}(?:-\d{2})?)?\z/
      DMS = /(\d+)°\s*(\d+)′\s*(\d+(?:\.\d+)?)″\s*([NSEW])/
      LIST_SPLIT = /\s*;\s*/

      def self.manifest = MANIFEST

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: REPO_URL, workdir: workdir, progress: progress, force: force)
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        corpus = corpus(workdir) or return
        corpus.documents.keys.sort_by(&:to_i).each do |pgpid|
          texts = corpus.texts.fetch(pgpid)
          unless texts[:editions].empty?
            yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{pgpid}",
                                        path: corpus.path, metadata: { "pgpid" => pgpid })
          end
          texts[:translations].keys.sort.each do |lang|
            yield Nabu::DocumentRef.new(
              source_id: MANIFEST.id, id: "#{URN_PREFIX}#{pgpid}-#{lang}", path: corpus.path,
              metadata: { "pgpid" => pgpid, "kind" => "translation", "language" => lang }
            )
          end
        end
      end

      def discovery_skips(workdir)
        corpus = corpus(workdir) or return DiscoverySkips.new
        counts = corpus.skips
        notes = []
        notes << count_note(counts[:metadata_only], "metadata-only document",
                            "(no digital edition or translation) skipped by rule")
        notes << count_note(counts[:undecidable], "text footnote",
                            "whose relation names no digital layer (edition vs translation " \
                            "undecidable) skipped by rule")
        notes << count_note(counts[:absent], "text footnote", "naming a pgpid absent from documents.csv " \
                                                              "skipped by rule")
        notes << count_note(counts[:orphan], "text footnote", "with no document_id skipped by rule")
        DiscoverySkips.new(skipped_by_rule: counts.values.sum, notes: notes.compact)
      end

      def parse(document_ref)
        corpus = corpus(File.dirname(document_ref.path, 2)) or
          raise Nabu::ParseError, "#{document_ref.id}: no pgp-metadata export under #{document_ref.path}"
        pgpid = document_ref.metadata.fetch("pgpid")
        row = corpus.documents[pgpid] or
          raise Nabu::ParseError, "#{document_ref.id}: pgpid #{pgpid} carries no text in the export (stale ref?)"
        texts = corpus.texts.fetch(pgpid)
        if document_ref.metadata["kind"] == "translation"
          parse_translation(document_ref, row, texts, corpus)
        else
          parse_edition(document_ref, row, texts, corpus)
        end
      rescue Nabu::ValidationError, KeyError => e
        raise Nabu::ParseError, "#{document_ref.id}: #{e.message}"
      end

      # The indexed export: documents (text-bearing rows only), their text
      # footnotes split into editions / translations-by-language, the join
      # tables, and the skip census. Memoized per (path, mtimes).
      Corpus = Data.define(:path, :documents, :texts, :fragments, :places, :skips)

      private

      def count_note(count, noun, tail)
        return nil if count.zero?

        "#{count} #{noun}#{'s' unless count == 1} #{tail}"
      end

      def corpus(workdir)
        data = File.join(workdir, DATA_DIR)
        files = %w[documents footnotes fragments sources places].to_h { |name| [name, File.join(data, "#{name}.csv")] }
        return nil unless File.file?(files["documents"]) && File.file?(files["footnotes"])

        key = files.values.map { |path| [path, File.file?(path) && File.mtime(path)] }
        return @corpus if defined?(@corpus_key) && @corpus_key == key

        @corpus_key = key
        @corpus = build_corpus(files)
      end

      def build_corpus(files)
        sources = optional_table(files["sources"]).to_h { |row| [row["slug"], row["languages"]] }
        texts, skips = text_footnotes(files["footnotes"], sources)
        documents = {}
        each_row(files["documents"]) do |row|
          pgpid = row["pgpid"].to_s.strip
          if texts.key?(pgpid)
            documents[pgpid] = row.to_h
          else
            skips[:metadata_only] += 1
          end
        end
        texts.each_key { |pgpid| skips[:absent] += texts[pgpid][:count] unless documents.key?(pgpid) }
        Corpus.new(path: File.expand_path(files["footnotes"]), documents: documents, texts: texts,
                   fragments: fragments(files["fragments"], documents), places: places(files["places"]),
                   skips: skips)
      end

      # {pgpid => {editions: [row], translations: {lang => [row]}, count:}}
      # plus the footnote-grain skip census.
      def text_footnotes(path, sources)
        skips = Hash.new(0)
        skips[:metadata_only] = 0
        texts = {}
        each_row(path) do |row|
          next if row["content"].to_s.strip.empty?

          pgpid = row["document_id"].to_s.strip
          next skips[:orphan] += 1 if pgpid.empty?
          next skips[:undecidable] += 1 unless [EDITION, TRANSLATION].include?(row["doc_relation"])

          entry = texts[pgpid] ||= { editions: [], translations: Hash.new { |h, k| h[k] = [] }, count: 0 }
          entry[:count] += 1
          note = row.to_h
          if row["doc_relation"] == EDITION
            entry[:editions] << note
          else
            entry[:translations][translation_language(note, sources)] << note
          end
        end
        [texts, skips]
      end

      def translation_language(note, sources)
        content = note["content"].to_s
        hebrew = content.scan(/\p{Hebrew}/).size
        arabic = content.scan(/\p{Arabic}/).size
        latin = content.scan(/\p{Latin}/).size
        return "heb" if hebrew > arabic && hebrew > latin
        return "ara" if arabic > latin

        LATIN_TRANSLATION_LANGUAGES.fetch(sources[note["source_slug"]].to_s.strip, "en")
      end

      # {pgpid => {provenance: [..], material: [..]}} for text documents.
      def fragments(path, documents)
        joined = Hash.new { |hash, key| hash[key] = { provenance: [], material: [] } }
        optional_table(path).each do |row|
          row["pgpids"].to_s.split(LIST_SPLIT).each do |pgpid|
            next unless documents.key?(pgpid)

            joined[pgpid][:provenance] << row["provenance_display"] if present?(row["provenance_display"])
            joined[pgpid][:material] << row["material_support"] if present?(row["material_support"])
          end
        end
        joined
      end

      # {name => "lat, lon"} from the DMS coordinates column.
      def places(path)
        optional_table(path).each_with_object({}) do |row, map|
          geo = decimal_pair(row["coordinates"].to_s)
          map[row["name"].to_s.strip] = geo if geo
        end
      end

      def decimal_pair(text)
        parts = text.scan(DMS)
        return nil unless parts.size == 2

        values = parts.map do |deg, min, sec, hemi|
          value = (Integer(deg, 10) + (Integer(min, 10) / 60.0) + (Float(sec) / 3600.0)).round(5)
          %w[S W].include?(hemi) ? -value : value
        end
        values.join(", ")
      end

      def optional_table(path)
        return [] unless File.file?(path)

        rows = []
        each_row(path) { |row| rows << row }
        rows
      end

      # Upstream ships utf-8-sig: the leading BOM is the file's encoding
      # mark, not header text, so it is dropped before the header parse.
      def each_row(path, &)
        text = SourceRead.utf8_file(path, label: "pgp-geniza").delete_prefix("\uFEFF")
        CSV.parse(text, headers: true, &)
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "pgp-geniza: #{path}: #{e.message}"
      end

      # --- documents ------------------------------------------------------------------

      def parse_edition(ref, row, texts, corpus)
        language = document_language(row)
        document = Nabu::Document.new(
          urn: ref.id, language: language, canonical_path: ref.path, title: title(row),
          metadata: base_metadata(row).merge(axis_metadata(row, corpus))
                                      .merge("editions" => citations(texts[:editions]))
        )
        append_blocks(document, texts[:editions], language: language, prefix: "")
        raise Nabu::ParseError, "#{ref.id}: the editions carry no text line" if document.empty?

        document
      end

      def parse_translation(ref, row, texts, corpus)
        language = ref.metadata.fetch("language")
        notes = texts[:translations].fetch(language) do
          raise Nabu::ParseError, "#{ref.id}: no #{language} translation in the export (stale ref?)"
        end
        pgpid = ref.metadata.fetch("pgpid")
        metadata = base_metadata(row).merge(
          "kind" => "translation", "translation_of" => "#{URN_PREFIX}#{pgpid}", "translations" => citations(notes)
        )
        metadata.merge!(axis_metadata(row, corpus)) if axis_bearer?(language, texts)
        document = Nabu::Document.new(
          urn: ref.id, language: language, canonical_path: ref.path,
          title: "#{title(row)} — #{TRANSLATION_NAMES.fetch(language)} translation", metadata: metadata
        )
        append_blocks(document, notes, language: language, prefix: "t")
        raise Nabu::ParseError, "#{ref.id}: the translation carries no text line" if document.empty?

        document
      end

      # The axes ride the edition document when one is held, else the
      # first translation sibling (by language tail) — one row per pgpid.
      def axis_bearer?(language, texts)
        texts[:editions].empty? && texts[:translations].keys.min == language
      end

      def append_blocks(document, notes, language:, prefix:)
        keyed(notes).each do |key, note|
          lines = passage_lines(note["content"], language)
          lines.each_with_index do |(line, side, marks), index|
            annotations = { "source_slug" => note["source_slug"] }
            annotations["side"] = side if side
            annotations["marks"] = marks unless marks.empty?
            document << Nabu::Passage.new(
              urn: "#{document.urn}:#{key}.#{prefix}#{index + 1}", language: language,
              text: line, annotations: annotations, sequence: document.size
            )
          end
        end
      end

      # [[text, side, marks]] for one content block. Side labels set the
      # side of what follows (a label run joins whole); a line that folds
      # to nothing (a lone numeral glyph such as the Coptic epact 𐋢) cannot
      # be a searchable passage, so it rides the NEXT passage's "marks"
      # annotation (the last passage's when the block ends on it).
      def passage_lines(content, language)
        out = []
        side = nil
        labels = []
        marks = []
        content_lines(content).each do |raw|
          next labels << raw if side_label?(raw)

          line = SourceRead.nfc(raw, language: language)
          next marks << line if Normalize.search_form(line, language: language).strip.empty?

          side = labels.join(SIDE_JOIN) unless labels.empty?
          labels = []
          out << [line, side, marks]
          marks = []
        end
        out.last[2] += marks if out.any? && !marks.empty?
        out
      end

      # [[urn key, note]] in source-slug order; a slug cited twice for one
      # layer gets a ~2, ~3 … suffix in file order.
      def keyed(notes)
        seen = Hash.new(0)
        notes.each_with_index.sort_by { |note, index| [note["source_slug"].to_s, index] }.map do |note, _|
          slug = note["source_slug"].to_s
          seen[slug] += 1
          [seen[slug] == 1 ? slug : "#{slug}~#{seen[slug]}", note]
        end
      end

      def content_lines(content)
        content.to_s.split(/\r?\n|\r/).map { |line| line.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "") }
                                      .reject(&:empty?)
      end

      def side_label?(line)
        line.length <= SIDE_LABEL_MAX && SIDE_LABEL.match?(line) && !line.match?(/[\p{Hebrew}\p{Arabic}]/)
      end

      def title(row)
        Normalize.nfc("#{row['shelfmark'].to_s.strip} (PGPID #{row['pgpid'].to_s.strip})")
      end

      def document_language(row)
        names = list(row["languages_primary"], ",") + list(row["languages_secondary"], ",")
        names.each { |name| (code = LANGUAGES[name]) and return code }
        "und"
      end

      # Identity + link metadata every document of a pgpid carries.
      def base_metadata(row)
        meta = { "pgpid" => row["pgpid"].to_s.strip }
        meta["shelfmark"] = text(row["shelfmark"]) if present?(row["shelfmark"])
        meta["url"] = row["url"].to_s.strip if present?(row["url"])
        meta
      end

      # The axis fields — carried by exactly one document per pgpid.
      def axis_metadata(row, corpus)
        pgpid = row["pgpid"].to_s.strip
        meta = {}
        meta["document_type"] = text(row["type"]) if present?(row["type"])
        put_list(meta, "tags", row["tags"], ",")
        meta["description"] = text(row["description"].to_s.gsub(/\r\n?/, "\n")) if present?(row["description"])
        primary = list(row["languages_primary"], ",")
        secondary = list(row["languages_secondary"], ",")
        codes = (primary + secondary).filter_map { |name| LANGUAGES[name] }.uniq
        meta["languages"] = codes unless codes.empty?
        meta["languages_primary"] = primary unless primary.empty?
        meta["languages_secondary"] = secondary unless secondary.empty?
        meta["language_note"] = text(row["language_note"]) if present?(row["language_note"])
        date = date_claim(row)
        meta["date"] = date if date
        place = place_claim(row, corpus.places)
        meta["place"] = place if place
        meta["destination"] = list(row["destination"], ",").join("; ") if present?(row["destination"])
        %w[location mentioned possibly_mentioned formerly_believed_to_be_mentioned].each do |key|
          put_list(meta, key, row[key], ",")
        end
        put_list(meta, "library", row["library"], ";")
        put_list(meta, "collection", row["collection"], ";")
        put_list(meta, "shelfmarks_historic", row["shelfmarks_historic"], ";")
        put_list(meta, "iiif_urls", row["iiif_urls"], ";")
        %w[side region multifragment].each { |key| meta[key] = text(row[key]) if present?(row[key]) }
        joined = corpus.fragments[pgpid]
        if joined
          meta["provenance"] = joined[:provenance].uniq unless joined[:provenance].empty?
          meta["material"] = joined[:material].uniq unless joined[:material].empty?
        end
        meta
      end

      def date_claim(row)
        if (bounds = date_bounds(row["doc_date_standard"]))
          document_date(row, bounds)
        elsif (bounds = date_bounds(row["inferred_date_standard"]))
          inferred_date(row, bounds)
        end
      end

      def document_date(row, bounds)
        standard = row["doc_date_standard"].to_s.strip
        original = row["doc_date_original"].to_s.strip
        calendar = row["doc_date_calendar"].to_s.strip
        reading = [original, (calendar.empty? ? nil : "(#{calendar})")].reject { |part| part.nil? || part.empty? }
        raw = reading.empty? ? standard : "#{reading.join(' ')} = #{standard}"
        date = { "not_before" => bounds[0], "not_after" => bounds[1], "raw" => text(raw),
                 "basis" => "document", "standard" => standard }
        date["original"] = text(original) unless original.empty?
        date["calendar"] = text(calendar) unless calendar.empty?
        date["inferred_standard"] = row["inferred_date_standard"].to_s.strip if present?(row["inferred_date_standard"])
        date
      end

      def inferred_date(row, bounds)
        standard = row["inferred_date_standard"].to_s.strip
        display = present?(row["inferred_date_display"]) ? row["inferred_date_display"].to_s.strip : standard
        rationale = row["inferred_date_rationale"].to_s.strip
        raw = rationale.empty? ? "#{display} (inferred)" : "#{display} (inferred: #{rationale})"
        date = { "not_before" => bounds[0], "not_after" => bounds[1], "raw" => text(raw),
                 "basis" => "inferred", "standard" => standard }
        date["rationale"] = text(rationale) unless rationale.empty?
        date["notes"] = text(row["inferred_date_notes"]) if present?(row["inferred_date_notes"])
        date
      end

      # Every " ; " alternative and "/" range side → [min, max] CE years;
      # nil when any side does not parse (never a guessed bound).
      def date_bounds(value)
        sides = value.to_s.strip.split(LIST_SPLIT).flat_map { |alt| alt.split("/") }.map(&:strip)
        return nil if sides.empty? || sides.any?(&:empty?)

        years = sides.map { |side| (match = DATE_SIDE.match(side)) ? Integer(match[1], 10) : nil }
        return nil if years.include?(nil)

        years.minmax
      end

      def place_claim(row, places)
        origins = list(row["origin"], ",")
        return nil if origins.empty?

        claim = { "ancient" => origins.join("; ") }
        geo = origins.size == 1 ? places[origins.first] : nil
        claim["geo"] = geo if geo
        claim
      end

      def citations(notes)
        keyed(notes).map do |key, note|
          cite = { "slug" => key }
          { "source" => "source", "location" => "location", "notes" => "notes",
            "emendations" => "emendations", "url" => "url" }.each do |field, out|
            cite[out] = text(note[field]) if present?(note[field])
          end
          cite
        end
      end

      def put_list(meta, key, value, separator)
        values = list(value, separator)
        meta[key] = values unless values.empty?
      end

      def list(value, separator)
        value.to_s.split(separator).map { |item| text(item.strip) }.reject(&:empty?).uniq
      end

      def present?(value) = !value.to_s.strip.empty?

      def text(value) = SourceRead.nfc(value.to_s.strip, language: "und")
    end
  end
end
