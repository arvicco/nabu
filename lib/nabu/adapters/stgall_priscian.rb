# frozen_string_literal: true

module Nabu
  module Adapters
    # St Gall Priscian Glosses — the digital edition (v2.1, 2023; Rijcklof
    # Hofman, Pádraic Moran, Bernhard Bauer; stgallpriscian.ie) of the
    # glosses in St Gallen, Stiftsbibliothek, Cod. Sang. 904: Priscian's
    # Institutiones grammaticae copied by Irish scribes in AD 850–1 with over
    # 9,400 interlinear and marginal glosses in Latin and Old Irish plus
    # thousands of construe marks — the third pillar of the Old Irish gloss
    # corpus beside Würzburg and Milan. Composes the corph-sql parser family
    # (CorphSqlParser).
    #
    # == Canonical artifact
    #
    # The edition's website repo github.com/padraicmoran/stgallpriscian
    # carries the whole database as one phpMyAdmin dump, db_priscian_v2.sql
    # (7.7 MB; unchanged since the v2.1 upgrade of 2023-06-28). The repo is
    # ~210 MB because of the edition's page scans (images/ — Keil and
    # Thesaurus pages, MS thumbnails), so the fetch is a SPARSE GitFetch of
    # the dump, the LICENSE/README and the three prose pages whose
    # statements the dating/places postures quote (home_text.php,
    # glosses.php, resource.php). Not pinned: the repo is maintained.
    #
    # == Shape: four tables
    #
    # glosses (13,395 rows) → passages; priscian_lines (Hertz's text in
    # Keil's GL II–III, 23,245 lines) → each gloss's glossed line as context
    # (the base text itself is NOT ingested as documents — the glosses are
    # this source; the Priscian text is a separate decision); word_instances
    # (17,526 Old Irish word analyses on 3,466 glosses) → the P7-5 gold
    # token layer; types (86 rows) → the gloss-typology labels.
    #
    # == Grain
    #
    # Document = manuscript page (upstream's ms_num column; 239 pages, the
    # e-codices image unit and the edition's own "browse by MS page"),
    # urn:nabu:stgall-priscian:p<page>. Passage = one gloss cited by the
    # edition's own gloss id (recordID — the site's ?id= permalink and the
    # word_instances foreign key), urn <doc>:<recordID>, in recordID order.
    #
    # == Text
    #
    # A gloss record is <term>…</term><gloss>…</gloss> pairs (the glossed
    # Priscian word, the gloss) plus optional {…} editorial notes (parallels
    # in the Karlsruhe/Erlangen/Leiden Priscians). The passage text is the
    # GLOSS (the CorPH precedent — its own St Gall units are gloss-only); the
    # terms ride "terms", the notes "notes". A gloss with no words of its own
    # (a construe mark, a symbol, a term-only record) reads through its
    # anchor words in upstream's display form "term: symbol", flagged
    # "construe". Markup renders as the site renders it: expansions and
    # additions inline, the construe pointer " &gt; (" as " → (", <g>/<u>/<i>
    # unwrapped; a scribal <del> keeps its letters in the house erasure
    # brackets ⟦…⟧, an editorial <supplied> (site: "<…>") in ⟨…⟩, the one
    # <gap/> as […]. Upstream "7" (the Tironian et, ⁊ only in the site's
    # display) stays verbatim.
    #
    # == Language honesty (censused on the full dump, 2026-10-14)
    #
    # Upstream's irish flag marks 3,102 glosses; it is not a complete
    # language tag — 505 Latin-flagged glosses carry Irish material
    # (Thesaurus refs, analysed forms), most of them wholly Irish (".i.
    # libardaib"). Passage language: irish=1 → sga (the flag wins, wart
    # cases included); otherwise sga when the edition's analysed Old Irish
    # forms number at least half the gloss's words (".i." and editorial
    # parentheses not counted) — "language_basis" => "analysis", 422
    # glosses; otherwise lat. Measured: sga 3,524 / lat 9,871 passages; of
    # the 9,595 glosses with words of their own, sga 3,520 = 37% (upstream:
    # "more than one-third"); 3,800 are construe/symbol glosses. Document
    # language = the majority over its lexical glosses (construe glosses
    # abstain): 198 lat + 41 sga pages. Translations and analyses are
    # modern English annotation, never a text claim.
    class StgallPriscian < Nabu::Adapter
      REPO_URL = "https://github.com/padraicmoran/stgallpriscian"
      DUMP_FILENAME = "db_priscian_v2.sql"
      SPARSE = %w[/db_priscian_v2.sql /LICENSE /README.md /home_text.php /glosses.php /resource.php].freeze
      URN_PREFIX = "urn:nabu:stgall-priscian:"
      SITE = "https://www.stgallpriscian.ie"

      IRISH = "sga"
      LATIN = "lat"
      SCRIPT = "Latn"

      MANUSCRIPT = "St Gallen, Stiftsbibliothek, Cod. Sang. 904"
      REPOSITORY = "St Gallen, Stiftsbibliothek"
      EDITION = "St Gall Priscian Glosses, version 2.1 (2023), ed. Rijcklof Hofman, Pádraic Moran, " \
                "Bernhard Bauer — www.stgallpriscian.ie"

      # The manuscript's copying date, as upstream states it (home_text.php:
      # "written by Irish scribes in 850–1, probably in Ireland") — the
      # artifact's date, not a composition era (glosses older than the copy
      # are not separated upstream).
      DATE = {
        "not_before" => 850, "not_after" => 851,
        "raw" => "AD 850–1 (the manuscript's copying — upstream: \"written by Irish scribes in 850–1, " \
                 "probably in Ireland\")"
      }.freeze

      # Upstream's hedged origin claim, verbatim uncertainty (the ReM
      # "Siegburg (?)" convention). St Gallen is the holding library — a
      # PRESENT location ("reaching St Gall sometime after 888") — and rides
      # "repository" only.
      ORIG_PLACE = "Ireland (?)"

      MANIFEST = Nabu::SourceManifest.new(
        id: "stgall-priscian",
        name: "St Gall Priscian Glosses (St Gallen, Stiftsbibliothek 904) — digital edition v2.1",
        license: "MIT License / Copyright (c) 2023 Pádraic Moran (repo LICENSE, covers the repository " \
                 "including the database dump db_priscian_v2.sql), verbatim grant: \"Permission is hereby " \
                 "granted, free of charge, to any person obtaining a copy of this software and associated " \
                 "documentation files (the \"Software\"), to deal in the Software without restriction, " \
                 "including without limitation the rights to use, copy, modify, merge, publish, distribute, " \
                 "sublicense, and/or sell copies of the Software […] subject to the following conditions: The " \
                 "above copyright notice and this permission notice shall be included in all copies or " \
                 "substantial portions of the Software.\" Edition: Rijcklof Hofman, Pádraic Moran, Bernhard Bauer.",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "corph-sql"
      )

      # An upstream headword with a homonym index ("ad 1", "de 1") — split so
      # lemma search matches the headword (the corph precedent).
      HOMONYM = /\A(.+?)\s+(\d+)\z/

      # word_instances column → token key (verbatim when non-empty);
      # form/lemma/homonym/lang are derived separately.
      TOKEN_FIELDS = {
        "DIL_headword" => "dil_headword",
        "wordclass" => "wordclass",
        "subclass" => "subclass",
        "breakdown" => "breakdown",
        "meaning" => "meaning",
        "submeaning" => "submeaning",
        "analysis" => "analysis",
        "mutation" => "mutation",
        "voice" => "voice",
        "rel" => "rel",
        "dep" => "dep"
      }.freeze

      ROMAN_VOLUMES = { 2 => "II", 3 => "III" }.freeze

      # "(m.l.)" margo lateralis etc., "(ibid.)", and the construe pointer —
      # editorial apparatus, never gloss words.
      EDITORIAL_PARENS = /\((?:m\.\w\.|ibid\.)\)/
      ID_EST = /\A\.i\.?\z/

      def self.manifest = MANIFEST

      def initialize
        super
        @corpus = {}
      end

      # One DocumentRef per manuscript page carrying glosses, in page order.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        dump = File.join(workdir, DUMP_FILENAME)
        return unless File.file?(dump)

        pages = CorphSqlParser.new(dump).each_row("glosses").map { |row| Integer(row.fetch("ms_num")) }.uniq.sort
        pages.each do |page|
          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}p#{page}",
                                      path: File.expand_path(dump),
                                      metadata: { "ms_page" => page, "title" => title(page) })
        end
      end

      def parse(document_ref)
        corpus = corpus_for(document_ref.path)
        page = Integer(document_ref.id.delete_prefix("#{URN_PREFIX}p"), 10)
        rows = corpus.pages[page]
        raise Nabu::ParseError, "#{document_ref.path}: no glosses on page #{page}" if rows.nil?

        build_document(corpus, rows, urn: document_ref.id, page: page, path: document_ref.path)
      rescue ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Sparse GitFetch (fetch objects → breaker → attic → ff-merge;
      # architecture §8): the dump + the edition's prose, never the scans.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, sparse: SPARSE)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url = REPO_URL

      def title(page) = "St Gall Priscian glosses, p. #{page}"

      # -- corpus loading (one streaming pass per table, memoized per dump) --

      Corpus = Data.define(:pages, :words, :lines, :types)
      private_constant :Corpus

      def corpus_for(path)
        @corpus[path] ||= load_corpus(path)
      end

      def load_corpus(path)
        parser = CorphSqlParser.new(path)
        pages = parser.each_row("glosses").group_by { |row| Integer(row.fetch("ms_num")) }
        pages.each_value { |rows| rows.sort_by! { |row| row.fetch("recordID") } }
        words = parser.each_row("word_instances").group_by { |row| row.fetch("glossID").to_s }
        words.each_value { |rows| rows.sort_by! { |row| [row["old_recordID"] || 0, row.fetch("recordID")] } }
        lines = parser.each_row("priscian_lines").to_h do |row|
          [[row["keil_vol"], row["keil_page"], row["keil_line"]], row["text"]]
        end
        types = parser.each_row("types").with_object({}) do |row, map|
          (map[row.fetch("code").to_s] ||= []) << strip_tags(row.fetch("description").to_s)
        end
        Corpus.new(pages: pages, words: words, lines: lines, types: types)
      end

      # -- document building --------------------------------------------------

      def build_document(corpus, rows, urn:, page:, path:)
        glosses = rows.map { |row| gloss(corpus, row, urn: urn) }
        document = Document.new(
          urn: urn, language: majority_language(glosses), title: title(page),
          canonical_path: path, metadata: document_metadata(rows, page)
        )
        glosses.each_with_index do |unit, sequence|
          document << Passage.new(urn: unit[:urn], language: unit[:language], text: unit[:text],
                                  annotations: unit[:annotations], sequence: sequence)
        end
        document
      end

      def document_metadata(rows, page)
        {
          "ms_page" => page, "manuscript" => MANUSCRIPT, "repository" => REPOSITORY,
          "orig_place" => ORIG_PLACE, "date" => DATE.dup, "script" => SCRIPT,
          "images" => "https://www.e-codices.unifr.ch/en/csg/0904/#{page}",
          "edition" => EDITION,
          "priscian_books" => rows.filter_map { |row| row["book"] }.uniq.sort
        }
      end

      # Majority language over the lexical glosses (construe glosses
      # abstain); tally order breaks ties deterministically; a page of
      # symbols only falls back to Latin (upstream's irish=0 for all).
      def majority_language(glosses)
        votes = glosses.reject { |unit| unit[:construe] }.map { |unit| unit[:language] }
        return LATIN if votes.empty?

        votes.tally.max_by { |_code, count| count }.first
      end

      # -- one gloss ------------------------------------------------------------

      def gloss(corpus, row, urn:)
        id = row.fetch("recordID")
        main, notes = split_notes(row.fetch("text").to_s)
        notes = notes.map { |note| render(note) }.reject(&:empty?)
        gloss_raw = main.scan(%r{<gloss>(.*?)</gloss>}m).flatten.join(" ")
        words = gloss_words(gloss_raw)
        tokens = (corpus.words[id.to_s] || []).map { |word| token(word) }
        construe = words.empty?
        language, basis = language_of(row, words, tokens)
        text = construe ? render(main.gsub("</term><gloss>", "</term>: <gloss>")) : render(gloss_raw)
        raise Nabu::ParseError, "gloss #{id}: renders to empty text" if text.empty?

        annotations = gloss_annotations(corpus, row, main: main, notes: notes, tokens: tokens)
        annotations["construe"] = true if construe
        annotations["language_basis"] = basis if basis
        { urn: "#{urn}:#{id}", language: language, text: Normalize.nfc(text), construe: construe,
          annotations: deep_nfc(annotations) }
      end

      # [language, basis-when-not-the-flag] — the class note's rule.
      def language_of(row, words, tokens)
        return [IRISH, nil] if row["irish"] == 1
        return [IRISH, "analysis"] if !words.empty? && tokens.size * 2 >= words.size

        [LATIN, nil]
      end

      # The gloss's own words: construe symbols, pointers and editorial
      # parentheses out; tags unwrapped in place (an expansion is part of
      # its word); ".i." (id est, both languages) and letterless tokens
      # never count.
      def gloss_words(gloss_raw)
        text = gloss_raw.gsub(%r{<g>.*?</g>}m, " ").gsub(/&gt;\s*\([^)]*\)/, " ")
                        .gsub(%r{\(<i>.*?</i>\)}m, " ").gsub(EDITORIAL_PARENS, " ")
        decode(strip_tags(text)).split(/\s+/).select { |word| word.match?(/\p{L}/) && !word.match?(ID_EST) }
      end

      def gloss_annotations(corpus, row, main:, notes:, tokens:)
        annotations = { "gloss_id" => row.fetch("recordID"), "ms_ref" => row["ms_ref"].to_s,
                        "book" => row["book"], "irish" => row["irish"] }
        annotations["code"] = row["code"] unless blank?(row["code"])
        terms = main.scan(%r{<term>(.*?)</term>}m).flatten.map { |term| render(term) }.reject(&:empty?)
        annotations["terms"] = terms unless terms.empty?
        annotations["notes"] = notes unless notes.empty?
        annotations["translation"] = row["translation"] unless blank?(row["translation"])
        apply_thesaurus(annotations, row)
        apply_priscian(annotations, corpus, row)
        apply_types(annotations, corpus, row)
        annotations["tokens"] = tokens unless tokens.empty?
        annotations
      end

      # Thesaurus Palaeohibernicus ii reference, in upstream's own display
      # form (formatThesRef: zero padding dropped — "001a02" → "1a2"); a
      # malformed upstream value ("50", "105") rides as given.
      def apply_thesaurus(annotations, row)
        ref = row["thesaurus_ref"].to_s.strip
        return if ref.empty?

        annotations["thesaurus"] = ref.gsub(/(^|a|b|\s)0{0,2}/, '\1')
        annotations["thesaurus_page"] = row["thesaurus_page"] if row["thesaurus_page"]
      end

      # The glossed line of Hertz's text (Keil, GL II–III) and upstream's
      # reference display ("GL II 1,5"), plus the site's permalink.
      def apply_priscian(annotations, corpus, row)
        vol, page, line = row.values_at("keil_vol", "keil_page", "keil_line")
        return unless vol && page

        annotations["keil"] = "GL #{ROMAN_VOLUMES.fetch(vol, vol)} #{page}#{",#{line}" if line}"
        annotations["url"] = "#{SITE}/index.php?kV=#{vol}&kP=#{page}&id=#{row.fetch('recordID')}#hi"
        context = corpus.lines[[vol, page, line]]
        annotations["priscian"] = decode(strip_tags(context.to_s)).squeeze(" ").strip unless blank?(context)
      end

      def apply_types(annotations, corpus, row)
        codes = row["types"].to_s.split("+").reject(&:empty?)
        return if codes.empty?

        annotations["types"] = codes
        labels = codes.filter_map { |code| corpus.types[code]&.join("; ") }
        annotations["type_labels"] = labels unless labels.empty?
      end

      # One word_instances row → the P7-5 token contract.
      def token(row)
        token = {}
        token["form"] = row["word_instance"].to_s unless blank?(row["word_instance"])
        headword = row["headword"].to_s.strip
        unless headword.empty?
          if (m = HOMONYM.match(headword))
            token["lemma"] = m[1]
            token["homonym"] = m[2]
          else
            token["lemma"] = headword
          end
        end
        token["lang"] = IRISH
        TOKEN_FIELDS.each { |column, key| token[key] = row[column].to_s unless blank?(row[column]) }
        token
      end

      # -- markup rendering (the class note's display rules) -------------------

      # [main, notes]: every TOP-LEVEL {…} span is one editorial note (a
      # nested "{{212}}" marker stays whole — "{212}"); an unmatched "}" is
      # upstream text and stays (gloss 7464's typo for ")"); an unclosed "{"
      # notes the rest of the record.
      def split_notes(raw)
        main = +""
        notes = []
        note = nil
        depth = 0
        raw.each_char do |char|
          if depth.zero? && char == "{"
            note = +""
            depth = 1
          elsif depth.zero?
            main << char
          elsif char == "}" && depth == 1
            notes << note
            main << " "
            depth = 0
          else
            depth += 1 if char == "{"
            depth -= 1 if char == "}"
            note << char
          end
        end
        notes << note if depth.positive?
        [main, notes]
      end

      def render(fragment)
        text = fragment.gsub(/ &gt; (?=\()/, " → ")
                       .gsub(%r{<del>(.*?)</del>}m) { "⟦#{Regexp.last_match(1)}⟧" }
                       .gsub("<supplied>", "⟨").gsub("</supplied>", "⟩")
                       .gsub(%r{<gap\s*/>}, "[…]")
                       .gsub("</gloss>", "</gloss> ")
        decode(strip_tags(text)).gsub(/\s+/, " ").strip
      end

      # Attribute-tolerant (two <add hand="C"> in the dump).
      def strip_tags(text) = text.gsub(%r{</?[a-z]+(?:\s[^<>]*)?/?>}, "")

      def decode(text) = text.gsub("&gt;", ">").gsub("&lt;", "<").gsub("&amp;", "&")

      def blank?(value) = value.to_s.strip.empty?

      def deep_nfc(value)
        case value
        when String then Normalize.nfc(value)
        when Hash then value.transform_values { |v| deep_nfc(v) }
        when Array then value.map { |v| deep_nfc(v) }
        else value
        end
      end
    end
  end
end
