# frozen_string_literal: true

require "digest"
require_relative "titus_pahlavi_parser"
require_relative "titus_manichaica_parser"
require_relative "titus_tocharian_a"

module Nabu
  module Adapters
    # TITUS Manichaica — the Manichaean Middle Iranian corpora on TITUS (J. W.
    # Goethe-Universität Frankfurt, Prof. Jost Gippert), the three corpora
    # TITUS serves under iran/miran/manich/ (framesets probed open
    # 2026-10-10; last pages HEAD-probed the same day):
    #
    # - manreadc — the Manichaean Reader arranged by texts: Mary Boyce, A
    #   Reader in Manichaean Middle Persian and Parthian (Leiden 1975),
    #   entered by J. Gippert (1989), corrections D.N. MacKenzie (1993), with
    #   Gippert's interlinear plain transcription — 134 pages, one Reader text
    #   each (a … by …).
    # - mirmankb — the Corpus of Manichaean Texts arranged by editions (22
    #   editions, Mir.Man. … GL; 426 items on its index), prepared by D.
    #   Durkin-Meisterernst, D.N. MacKenzie, N. Sims-Williams, W. Sundermann
    #   and others — 430 pages, roughly one edition item each.
    # - sermseel — the Sermon of the Soul (Parthian and Sogdian), W.
    #   Sundermann's 1988 edition with P. Zieme's Turkish fragments,
    #   electronically prepared by the editors (Berlin 1996) — 23 pages, one
    #   fragment each.
    #
    # Languages are the edition's own lane claims, per passage: Manichaean
    # Middle Persian `pal`, Parthian `xpr`, Sogdian `sog`, and the Sermon's
    # Turkic appendix `oui` (see TitusManichaicaParser).
    #
    # == The grant (by email, 2026-10-06) and the credit duty
    #
    # Fetched under the owner's PERSONAL grant (Gippert): the Middle Iranian
    # families on TITUS, ONE retrieval per corpus, local personal research use
    # only, no redistribution, TITUS and the editors credited wherever
    # displayed — the titus-pahlavi mechanisms verbatim (`grant_required`,
    # license_class `nc`, the manifest +credit+ line, each document's own
    # "editors" metadata).
    #
    # == Shape
    #
    # canonical/titus-manichaica/<corpus>/<prefix>NNN.htm — one subdir per
    # TITUS corpus directory. One PAGE is one document
    # (`urn:nabu:titus-manichaica:<corpus>.<page>`); passages sit at the
    # deepest citation level the page reaches (Reader: Text / Chapter /
    # Paragraph; the Corpus: Edition / Item / Page of Ed. — items with no
    # edition-page level are one passage; the Sermon: Text / Fragment /
    # Part), cited by the header values (`…:Reader.a.1.1`,
    # `…:Sogd.Tales.Mag.T.40`, `…:SS.2.128`). Nothing is materialized beside
    # upstream's pages (TitusFetch's dot-state file aside, as in every titus
    # source), so no materialized_paths.
    class TitusManichaica < Nabu::Adapter
      SLUG = "titus-manichaica"
      PARSER_FAMILY = "titus_manichaica"

      BASE_URL = "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/manich/"

      # One TITUS corpus: +path+ the frameset under BASE_URL, +prefix+ its
      # page-file stem, +name+ verbatim from the frameset title, +editors+
      # from its first page's header, +credit_name+ the short form the
      # source-level credit line carries.
      Corpus = Data.define(:path, :prefix, :name, :editors, :credit_name) do
        def entry_url = "#{BASE_URL}#{path}"
        def page_re = /\A#{Regexp.escape(prefix)}\d+\.htm\z/
      end

      # census 2026-10-10: the three framesets under manich/ (page counts by
      # HEAD probe: manre 134, mirma 430, serms 23 — 587 pages)
      CORPORA = {
        "manreadc" => Corpus.new(path: "manreadc/manre.htm", prefix: "manre",
                                 name: "Manichaean Reader (arr. by texts)",
                                 editors: "M. Boyce (A Reader in Manichaean Middle Persian and Parthian, " \
                                          "Leiden 1975); entered by J. Gippert (1989), corrections " \
                                          "D.N. MacKenzie (1993); transcription J. Gippert",
                                 credit_name: "Boyce/Gippert/MacKenzie"),
        "mirmankb" => Corpus.new(path: "mirmankb/mirma.htm", prefix: "mirma",
                                 name: "Corpus of Manichaean Texts (arr. by eds.)",
                                 editors: "D. Durkin-Meisterernst, D.N. MacKenzie, N. Sims-Williams, " \
                                          "W. Sundermann and others; TITUS version J. Gippert",
                                 credit_name: "Durkin-Meisterernst/MacKenzie/Sims-Williams/Sundermann"),
        "sermseel" => Corpus.new(path: "sermseel/serms.htm", prefix: "serms",
                                 name: "Sermon of the Soul",
                                 editors: "W. Sundermann (Der Sermon von der Seele, Berlin 1988; Turkish " \
                                          "fragments P. Zieme), electronically prepared by the editors " \
                                          "(Berlin 1996); TITUS version J. Gippert",
                                 credit_name: "Sundermann/Zieme")
      }.freeze

      LICENSE = "personal grant, Gippert (by email, 2026-10-06): one retrieval per corpus, local " \
                "personal research use only, no redistribution; TITUS and the editors clearly " \
                "indicated wherever displayed"

      CREDIT = "TITUS (J. Gippert, Frankfurt) — Manichaean Middle Iranian texts, editors " \
               "#{CORPORA.values.map(&:credit_name).join(', ')} " \
               "(each document names its corpus's editors; the Corpus's items name their editions).".freeze

      # Header spans mined into document metadata (an item/fragment page
      # carries its own; continuation pages honestly carry none).
      HEADER_SPANS = { "title" => "page_title", "textdescr" => "data_entry", "bibliogr" => "bibliography" }.freeze

      # A Berlin Turfan find signature in a manuscript subtitle — the
      # Reader's "M_5794_I (= T_II_D_126_I)": expedition numeral, site
      # siglum, number. Its siglum resolves through the titus-tocharian-a
      # SITE_SIGLA (Š Šorčuq, D Qočo) — DELIBERATELY coarse and declared:
      # an uncensused siglum mints no place, the raw signature still rides.
      FIND_SIGNATURE = /\bT_[IV0]+_[^_\s()]+_[^\s()]+/

      # find_signatures (every one a page names) + findspot (only when every
      # resolved siglum names the SAME site — one page, one claim).
      def self.find_metadata(subtitles)
        signatures = subtitles.flat_map { |s| s.scan(FIND_SIGNATURE) }.uniq
        return {} if signatures.empty?

        places = signatures.filter_map { |sig| TitusTocharianA.findspot_for(sig) }.uniq
        metadata = { "find_signatures" => signatures }
        metadata["findspot"] = places.first if places.size == 1
        metadata
      end

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "TITUS Manichaica",
          license: LICENSE,
          license_class: "nc",
          upstream_url: "#{BASE_URL}manreadc/manre.htm",
          parser_family: PARSER_FAMILY,
          credit: CREDIT
        )
      end

      # Each corpus's frameset entry stands for that corpus — HEAD it for
      # liveness; its TitusFetch state file (url + sha) feeds the drift lane.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        CORPORA.map do |id, corpus|
          Nabu::Adapter::HttpProbeTarget.new(
            label: "#{id} entry", zip_url: corpus.entry_url, metadata_url: nil,
            state_subdir: id, state_file: Nabu::TitusFetch::STATE_FILE
          )
        end
      end

      # +corpora+ narrows the walk (tests); +delay+ is TitusFetch's polite
      # pause between requests.
      def initialize(corpora: CORPORA, delay: Nabu::TitusFetch::DELAY)
        super()
        @corpora = corpora
        @delay = delay
      end

      # One DocumentRef per text page of every known corpus (ref.id IS the
      # document urn). Framesets, index pages and unknown directories are not
      # text.
      def discover(workdir)
        @corpora.flat_map do |id, corpus|
          Dir.glob(File.join(workdir, id, "#{corpus.prefix}*.htm")).filter_map do |path|
            name = File.basename(path)
            next unless name.match?(corpus.page_re)

            stem = name.delete_suffix(".htm")
            Nabu::DocumentRef.new(source_id: SLUG, id: "urn:nabu:#{SLUG}:#{id}.#{stem}", path: path,
                                  metadata: { "corpus" => id, "page" => stem })
          end
        end
      end

      # Parse one page into a Document of citation-grain Passages. Pages are
      # read through the shared TITUS severed-UTF-8 repair; a page with no
      # text-bearing section is a structural failure (ParseError).
      def parse(document_ref)
        html = TitusPahlaviParser.read_page(document_ref.path)
        sections = TitusManichaicaParser.parse(html)
        raise Nabu::ParseError, "titus-manichaica: no text sections in #{document_ref.path}" if sections.empty?

        corpus_id = document_ref.metadata.fetch("corpus")
        corpus = CORPORA.fetch(corpus_id)
        document = Nabu::Document.new(
          urn: document_ref.id, language: predominant_language(sections), canonical_path: document_ref.path,
          title: "#{corpus.name} (#{document_ref.metadata['page']})",
          metadata: document_metadata(corpus_id, corpus, html, sections)
        )
        seen = Hash.new(0)
        sections.each_with_index do |section, sequence|
          citation = citation_for(section)
          occurrence = (seen[citation] += 1)
          document << Nabu::Passage.new(
            urn: passage_urn(document_ref.id, citation, occurrence), language: section.language,
            text: section.text, sequence: sequence, annotations: section_annotations(section, occurrence)
          )
        end
        document
      end

      # One polite TitusFetch walk per corpus (owner-run; never in tests —
      # WebMock blocks the network), each into its own subdir with its own
      # page pattern, state file and attic subtree. Pages already on disk are
      # never re-fetched (the grant's ONE retrieval). The source pin is the
      # sha256 over the per-corpus page-set pins.
      def fetch(workdir, progress: nil, force: false)
        shas = []
        atticked = []
        @corpora.each do |id, corpus|
          result = Nabu::TitusFetch.sync!(
            entry_url: corpus.entry_url, dir: File.join(workdir, id),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, id), page_re: corpus.page_re,
            delay: @delay, progress: progress,
            guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
          )
          shas << "#{id}:#{result.sha}"
          atticked.concat(result.atticked)
        end
        FetchReport.new(sha: Digest::SHA256.hexdigest(shas.join("\n")), fetched_at: Time.now,
                        notes: attic_notes(atticked))
      rescue Nabu::TitusFetch::Error => e
        raise Nabu::FetchError, "titus-manichaica fetch failed into #{workdir}: #{e.message}"
      end

      private

      # The page's language: the one carrying most passage text.
      def predominant_language(sections)
        sections.group_by(&:language)
                .max_by { |language, group| [group.sum { |s| s.text.length }, language] }
                .first
      end

      # The dotted citation from the header values: empties (absent levels)
      # drop, and a value's own trailing period ("Mir.Man.", "Mag.T.") drops
      # so the dots stay separators.
      def citation_for(section)
        section.components.reject(&:empty?).map { |c| c.delete_suffix(".") }.join(".")
      end

      # A citation a page re-anchors keys as `<citation>#<occurrence>` (the
      # titus-pahlavi shape) with an honest "occurrence" annotation.
      def passage_urn(document_urn, citation, occurrence)
        tail = occurrence > 1 ? "#{citation}##{occurrence}" : citation
        "#{document_urn}:#{tail}"
      end

      def section_annotations(section, occurrence)
        annotations = { "unit" => section.label }
        annotations.merge!(section.location)
        annotations["languages"] = section.languages if section.languages.size > 1
        annotations["transliteration"] = section.transliteration if section.transliteration
        annotations["occurrence"] = occurrence if occurrence > 1
        annotations
      end

      # Corpus identity + the page header's own statements (title, data
      # entry, edition basis, the subtitles that name the item's languages
      # and manuscripts) + the lanes' representation and languages.
      def document_metadata(corpus_id, corpus, html, sections)
        metadata = { "corpus" => corpus_id, "corpus_name" => corpus.name, "editors" => corpus.editors }
        doc = Nokogiri::HTML(html)
        HEADER_SPANS.each do |span_id, key|
          parts = doc.css(%(span[id="#{span_id}"])).map { |span| TitusPahlaviParser.clean(span.text) }
          text = parts.reject(&:empty?).uniq.join(" … ")
          metadata[key] = text unless text.empty?
        end
        subtitles = doc.css('span[id="subtitle"]').map { |span| TitusPahlaviParser.clean(span.text) }
        metadata["subtitles"] = subtitles.reject(&:empty?) unless subtitles.all?(&:empty?)
        metadata.merge!(self.class.find_metadata(subtitles))
        representation = sections.flat_map { |s| s.representation.split("+") }.uniq.sort
        metadata["representation"] = representation.join("+") unless representation.empty?
        metadata["languages"] = sections.flat_map(&:languages).uniq.sort
        metadata
      end
    end
  end
end
