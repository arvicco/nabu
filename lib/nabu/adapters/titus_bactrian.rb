# frozen_string_literal: true

require_relative "titus_bactrian_parser"
require_relative "titus_pahlavi_parser"

module Nabu
  module Adapters
    # TITUS Bactrian Corpus — the Corpus of Bactrian Texts "electronically
    # prepared by Nicholas Sims-Williams, in connection with the editions
    # published in Bactrian Documents from Northern Afghanistan, vols. 1-2,
    # London 2000-2007 (Corpus inscriptionum iranicarum, II, 6/1 and 3/2)
    # and other editions; TITUS version by Jost Gippert, Frankfurt a/M,
    # 11.11.2010" (the corpus header, verbatim). Six genres (the corpus's
    # own CONTENTS list): dated documents, documents and fragments of
    # uncertain date, lists and accounts, letters, fragments of documents
    # of uncertain type, Buddhist texts — plus the Tang-i Safedak
    # inscription (TiS). 126 index entries over 126 pages (the TITUS index
    # frames baktcx1–6, censused 2026-10-10; baktc126.htm is the last page).
    #
    # == The grant (by email, 2026-10-06) and the credit duty
    #
    # Fetched under the owner's PERSONAL grant (Gippert): the Middle Iranian
    # families on TITUS — ONE retrieval per corpus, local personal research
    # use only, no redistribution, TITUS and the editors credited wherever
    # displayed. The titus-avestan mechanisms verbatim: `grant_required:
    # true` guards the fetch right; license_class `nc` + the manifest
    # +credit+ line (Sims-Williams + Gippert) carry the display duty.
    #
    # == Shape (see Nabu::Adapters::TitusBactrianParser)
    #
    # canonical/titus-bactrian/baktcNNN.htm — one TitusFetch walk (the
    # "Next part" chain from the baktc.htm frameset). One PAGE is one
    # document (normally one text: A, Aa, …, am, bb, za, TiS); passages at
    # the MANUSCRIPT LINE grain, `urn:nabu:titus-bactrian:<page>:<text>.<line>`
    # with the edition's own line labels verbatim (`A.1`, `Aa.1'`,
    # `Aa.(2)`, `am.5+6A`). Text sigla are CASE-SENSITIVE (M and m are
    # different texts on the index).
    #
    # == The headerless text (an upstream defect, kept honest)
    #
    # baktc047 opens the Letters genre with 22 lines whose anchors carry an
    # EMPTY text component (`Bactr.Corp._Lett.__1` — no Level-3 header;
    # their footnote links point at "am"/List.Acc.) before text bb. The
    # lines are real text: they mint as `<page>:<line>` (no text siglum,
    # no guessed identity), the passage carries no "text" annotation, and
    # the document records `unheaded_lines`.
    #
    # == Illegible-text pages (skipped by rule)
    #
    # Three pages (baktc037 ae, baktc117 xt, baktc121 yd) carry only a text
    # header and the editor's verdict ("illegible") — no Bactrian lane at
    # all. They are skipped at discovery and counted in discovery_skips; a
    # page with lanes but no minted line still quarantines.
    #
    # == Dating mined, conversion pending
    #
    # Dated documents open with a Bactrian-era year formula — "χϸονο ρʹ ιʹ"
    # (year 110), "[χ]ϸονο ρʹ λ̣ʹ δʹ" (134). The formula is mined from the
    # FIRST line of each dated-document text that carries one: raw text,
    # the summed Greek numeral, and an `uncertain` flag when the numeral
    # carries restoration brackets or subscript dots. The conversion to CE
    # (the era's epoch) is a ruled step, NOT taken here — the dating
    # posture is pending on it (config/postures.yml).
    class TitusBactrian < Nabu::Adapter
      SLUG = "titus-bactrian"
      LANGUAGE = "xbc" # Bactrian
      PARSER_FAMILY = "titus_bactrian"

      ENTRY_URL = "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/baktr/baktcorp/baktc.htm"

      PAGE_GLOB = "baktc*.htm"
      PAGE_RE = /\Abaktc\d+\.htm\z/
      TEXT_HEADER = /<!Level 3>Text:\s*([^<\s&]+)/n

      LICENSE = "personal grant, Gippert (by email, 2026-10-06): one retrieval, local personal " \
                "research use only, no redistribution; TITUS and the editors clearly indicated " \
                "wherever displayed"

      CREDIT = "TITUS (J. Gippert, Frankfurt) — Corpus of Bactrian Texts, electronically prepared " \
               "by N. Sims-Williams (Bactrian Documents from Northern Afghanistan I–II, London " \
               "2000–2007, and other editions); TITUS version J. Gippert (2010)."

      # The corpus's own CONTENTS list (baktc001.htm, verbatim) keyed by the
      # anchors' genre component.
      GENRES = {
        "Dat.Doc." => "Dated documents",
        "Doc.Fragm." => "Documents and fragments of uncertain date",
        "List.Acc." => "Lists and accounts",
        "Lett." => "Letters",
        "Fragm.Doc.Unc." => "Fragments of documents of uncertain type",
        "Buddh.T." => "Buddhist texts"
      }.freeze
      DATED_GENRE = "Dat.Doc."

      HEADER_SPANS = TitusPahlavi::HEADER_SPANS

      # Greek alphabetic numerals (the edition: "single letters used as
      # numerals are transcribed in the usual Greek manner").
      NUMERALS = {
        "α" => 1, "β" => 2, "γ" => 3, "δ" => 4, "ε" => 5, "ϛ" => 6, "ϝ" => 6, "ζ" => 7, "η" => 8,
        "θ" => 9, "ι" => 10, "κ" => 20, "λ" => 30, "μ" => 40, "ν" => 50, "ξ" => 60, "ο" => 70,
        "π" => 80, "ϙ" => 90, "ϟ" => 90, "ρ" => 100, "σ" => 200, "τ" => 300, "υ" => 400,
        "φ" => 500, "ϕ" => 500, "χ" => 600, "ψ" => 700, "ω" => 800, "ϡ" => 900
      }.freeze
      KERAIA = "ʹ" # ʹ, the numeral sign
      MARKS = "[\\[\\]̣]*"
      # "χϸονο" (year) with restoration brackets / uncertainty dots anywhere
      # in it, then one or more single-letter numerals.
      ERA_FORMULA = /#{MARKS}#{'χϸονο'.chars.map { |c| Regexp.escape(c) }.join(MARKS)}#{MARKS}
                     (?<numerals>(?:\s+#{MARKS}\p{Greek}#{MARKS}#{KERAIA}#{MARKS})+)/x

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "TITUS Bactrian Corpus",
          license: LICENSE,
          license_class: "nc",
          upstream_url: ENTRY_URL,
          parser_family: PARSER_FAMILY,
          credit: CREDIT
        )
      end

      # The frameset entry stands for the corpus — HEAD it for liveness; the
      # TitusFetch state file (url + sha) feeds the drift lane.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "baktc.htm entry", zip_url: ENTRY_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::TitusFetch::STATE_FILE
        )]
      end

      # The era formula of one line's text: { "formula", "era_year",
      # "uncertain" } or nil.
      def self.era_formula(text)
        m = ERA_FORMULA.match(text)
        return nil if m.nil?

        tokens = m[:numerals].split
        values = tokens.map { |token| NUMERALS[token.delete("[]̣").delete_suffix(KERAIA)] }
        return nil if values.any?(&:nil?)

        { "formula" => m[0].strip, "era_year" => values.sum, "uncertain" => m[0].match?(/[\[\]̣]/) }
      end

      def initialize(delay: Nabu::TitusFetch::DELAY)
        super()
        @delay = delay
      end

      # One DocumentRef per text page (ref.id IS the document urn); the
      # frameset and index frames (baktc.htm, baktcx*.htm) are not text, and
      # the ILLEGIBLE-TEXT pages are skipped by rule (see discovery_skips).
      def discover(workdir)
        page_paths(workdir).filter_map do |path|
          next if illegible_text_page?(path)

          stem = File.basename(path).delete_suffix(".htm")
          Nabu::DocumentRef.new(source_id: SLUG, id: "urn:nabu:#{SLUG}:#{stem}", path: path,
                                metadata: { "page" => stem })
        end
      end

      # The skip-by-rule census: pages that carry NO Bactrian content lane
      # at all — a text's Level-3 header and the editor's verdict only
      # (first sync 2026-10-10: baktc037 ae "illegible", baktc117 xt
      # "virtually nothing legible", baktc121 yd "Documents yd, ye
      # illegible"). The text is indexed upstream but has no transcribed
      # line, so there is nothing to mint; counted here, never silent.
      def discovery_skips(workdir)
        notes = page_paths(workdir).select { |path| illegible_text_page?(path) }.map do |path|
          siglum = File.binread(path)[TEXT_HEADER, 1]&.force_encoding(Encoding::UTF_8)
          "#{File.basename(path)}: text #{siglum || '?'}: no transcribed line " \
            "(an illegible-text page — header and editorial note only)"
        end
        DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: 0, notes: notes)
      end

      # Parse one page into a Document of line Passages. A page with no
      # text-bearing line is a structural failure (ParseError).
      def parse(document_ref)
        html = TitusPahlaviParser.read_page(document_ref.path)
        lines = TitusBactrianParser.parse(html)
        raise Nabu::ParseError, "#{SLUG}: no text lines in #{document_ref.path}" if lines.empty?

        stem = document_ref.metadata.fetch("page")
        metadata = document_metadata(html, lines)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(stem, metadata), metadata: metadata
        )
        seen = Hash.new(0)
        lines.each_with_index do |line, sequence|
          citation = [line.text, line.line].reject(&:empty?).join(".")
          occurrence = (seen[citation] += 1)
          document << Nabu::Passage.new(
            urn: passage_urn(document_ref.id, citation, occurrence), language: LANGUAGE,
            text: line.content, sequence: sequence, annotations: line_annotations(line, occurrence)
          )
        end
        document
      end

      # One polite TitusFetch walk (owner-run; never in tests — WebMock
      # blocks the network). Pages already on disk are never re-fetched
      # (the grant's ONE retrieval).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::TitusFetch.sync!(
          entry_url: ENTRY_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          page_re: PAGE_RE, delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue Nabu::TitusFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def page_paths(workdir)
        Dir.glob(File.join(workdir, PAGE_GLOB)).select { |path| File.basename(path).match?(PAGE_RE) }.sort
      end

      # A text header with no lane anywhere; an empty or header-less page is
      # NOT this rule's — it is yielded and quarantines at parse.
      def illegible_text_page?(path)
        bytes = File.binread(path)
        bytes.match?(TEXT_HEADER) && !TitusBactrianParser.lane_bearing?(bytes)
      end

      def passage_urn(document_urn, citation, occurrence)
        tail = occurrence > 1 ? "#{citation}##{occurrence}" : citation
        "#{document_urn}:#{tail}"
      end

      def line_annotations(line, occurrence)
        annotations = { "genre" => line.genre }
        annotations["line"] = line.line unless line.line.empty? # a line-less text-level section
        annotations["text"] = line.text unless line.text.empty?
        annotations["copy"] = line.copy if line.copy
        annotations["line_end_word"] = line.line_end_word if line.line_end_word
        annotations["occurrence"] = occurrence if occurrence > 1
        annotations
      end

      # Texts, genre (+ the genre facet), the corpus header statements, the
      # headerless-line count, and the mined era-year formulas.
      def document_metadata(html, lines)
        texts = lines.map(&:text).reject(&:empty?).uniq
        genres = lines.map(&:genre).uniq
        metadata = { "texts" => texts, "genre" => genres.join(" + "),
                     "editors" => "N. Sims-Williams; TITUS version J. Gippert" }
        names = genres.map { |code| GENRES.fetch(code, code) }
        metadata["genre_name"] = names.join(" + ")
        metadata["facets"] = { "genre" => { "value" => names.first } } if names.size == 1
        unheaded = lines.count { |line| line.text.empty? }
        metadata["unheaded_lines"] = unheaded if unheaded.positive?
        dates = era_dates(lines)
        metadata["era_dates"] = dates unless dates.empty?
        metadata.merge(header_statements(html))
      end

      def era_dates(lines)
        lines.select { |line| line.genre == DATED_GENRE }.group_by(&:text).filter_map do |text, text_lines|
          formula = text_lines.lazy.filter_map { |line| self.class.era_formula(line.content) }.first
          formula && { "text" => text }.merge(formula)
        end
      end

      def header_statements(html)
        doc = Nokogiri::HTML(html)
        HEADER_SPANS.each_with_object({}) do |(span_id, key), out|
          parts = doc.css(%(span[id="#{span_id}"])).map { |span| TitusPahlaviParser.clean(span.text) }
          text = parts.reject(&:empty?).join(" … ")
          out[key] = text unless text.empty?
        end
      end

      def title_for(stem, metadata)
        labels = (metadata["unheaded_lines"] ? ["untitled lines"] : []) + metadata["texts"]
        "Bactrian — #{labels.join(', ')} (#{stem})"
      end
    end
  end
end
