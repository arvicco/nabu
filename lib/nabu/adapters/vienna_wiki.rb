# frozen_string_literal: true

require "json"

require_relative "wiki_template_parser"
require_relative "../wiki_fetch"
require_relative "../normalize"

module Nabu
  module Adapters
    # The Vienna wiki inscription family (P29-3): the shared machinery
    # behind the Lexlep and Tir adapters — two Semantic-MediaWiki sites
    # from the same Vienna linguistics department, one template vocabulary
    # ({{inscription}}/{{object}}/{{site}}), one fetch path (WikiFetch),
    # one parser family (WikiTemplateParser). Subclasses provide only the
    # constants: manifest, API url, urn prefix, the language map, and the
    # concordance→related key table.
    #
    # == The grain
    #
    # Document = one Inscription page; passage = one reading LINE (the
    # " / " separator, riig's line-within-reading shape) carrying the
    # rendered scholarly transliteration; the wiki's Word-page link forms
    # ride each passage's annotations ("words") — the future join surface
    # to the lexicon shelf. An inscription whose reading is "unknown"
    # (BE·1: a glass bead whose traces defy reading) mints ONE
    # metadata-only document (text_layer "none", the ogham/local-library
    # precedent): catalogued, zero passages, never quarantined.
    #
    # == The object/site join
    #
    # Every inscription names its carrier ({{inscription |object=AO·1
    # Aosta}}); the Object page carries type/material/dating/findspot, its
    # Site page the coordinates and administrative geography. discover
    # resolves both page files and parse merges them into document
    # metadata: facets (object_type/material — EDH's vocabulary — plus
    # genre from type_inscription) and "place" (site, country, province,
    # WGS84 verbatim as metadata — the EDH coordinates decision; the axis
    # has no coordinate columns). A missing object/site page is an honest
    # absence: fewer metadata keys, never an error. Dating stays OUT of
    # document metadata — AxisBuilder::ViennaWikiDates reads it from
    # canonical at axis-build time (axes = f(canonical)).
    #
    # == Concordances → reference edges
    #
    # Print-corpus concordance params (LexLep: Morandi 2004, Solinas 1995;
    # TIR: Trismegistos) become metadata "related" keys ("morandi:43 a",
    # "tm:653493") and kind=reference edges after each sync — the riig
    # "rig:G593" pattern through the shared reference_producer seam.
    class ViennaWiki < Nabu::Adapter
      INSCRIPTION_CATEGORY = "Inscription"
      OBJECT_CATEGORY = "Object"
      SITE_CATEGORY = "Site"
      CATEGORIES = [INSCRIPTION_CATEGORY, OBJECT_CATEGORY, SITE_CATEGORY].freeze

      UNKNOWN = WikiTemplateParser::UNKNOWN

      # Inscription-template params carried into document metadata verbatim
      # (when present and not "unknown"). The reading's original-script
      # forms differ in name between the wikis (reading_lepontic /
      # reading_original) — both map to "reading_original".
      METADATA_PARAMS = %w[direction script alphabet position condition type_inscription meaning].freeze

      # The subclass constants, asserted here so a new wiki cannot forget
      # one silently.
      class << self
        def api_url = const_get(:API_URL)
        def urn_prefix = const_get(:URN_PREFIX)
        def language_map = const_get(:LANGUAGE_MAP)
        def concordances = const_get(:CONCORDANCES)
      end

      # A wiki page title as a urn segment: NFC, downcased, the sigla
      # separators ("·", spaces, "/") folded to hyphens — "AO·1.1" →
      # "ao-1.1", "AS 3.1" → "as-3.1" (stable: sigla are the wikis' own
      # permanent citation forms).
      def self.title_segment(title)
        Nabu::Normalize.nfc(title).downcase.gsub(%r{[·/\s]+}, "-")
      end

      # The concordance edges (class note).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        LibraryReferences.new(catalog: catalog, journal: journal, producer: manifest.id)
      end

      # P11-2: no git repo — the probe HEADs api.php (reachability; the API
      # serves no Last-Modified, so drift honestly reads unknown against
      # the revid-pinned state file). No license endpoint (the grant lives
      # on the wiki's Terms-of-use page) → license row reads unchecked.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "api.php", zip_url: "#{api_url}?action=query&meta=siteinfo&format=json",
          metadata_url: nil, state_subdir: ".", state_file: Nabu::WikiFetch::STATE_FILE
        )]
      end

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default.
      def initialize(delay: Nabu::WikiFetch::DELAY)
        super()
        @delay = delay
      end

      # One DocumentRef per Inscription page, sorted by urn. A workdir
      # without pages/Inscription/ yields nothing (pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        envelope = read_envelope(document_ref.path)
        params = parser.template_params(envelope["wikitext"], "inscription")
        raise ParseError, "#{document_ref.path}: no {{inscription}} template block" if params.nil?

        document = build_document(document_ref, envelope, params)
        add_passages(document, document_ref, params)
        document
      rescue ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The two-stage polite crawl (WikiFetch), guarded by the shared
      # mass-deletion breaker between member map and any tree change.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::WikiFetch.sync!(
          api_url: self.class.api_url, categories: self.class::CATEGORIES,
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(
          sha: result.sha, fetched_at: Time.now,
          notes: fetch_notes(result), repos: { self.class.api_url => result.sha }
        )
      rescue Nabu::WikiFetch::Error => e
        raise Nabu::FetchError, "#{manifest.id} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        @parser ||= WikiTemplateParser.new
      end

      def fetch_notes(result)
        notes = "pages: #{result.fetched} fetched, #{result.cached} cached " \
                "(#{result.member_count} members across #{self.class::CATEGORIES.size} categories)"
        atticked = attic_notes(result.atticked)
        atticked ? "#{notes} · #{atticked}" : notes
      end

      # -- discovery -------------------------------------------------------------

      def document_refs(workdir)
        Dir.glob(File.join(workdir, Nabu::WikiFetch::PAGES_DIRNAME, INSCRIPTION_CATEGORY, "*.json"))
           .map { |path| document_ref(workdir, File.expand_path(path)) }
           .sort_by(&:id)
      end

      # The minting decision is the parser's own extraction (the P25-3
      # ruling): a page whose reading renders no line is metadata-only. An
      # unreadable page file mints a plain ref whose parse carries the
      # honest quarantine.
      def document_ref(workdir, path)
        metadata = {}
        begin
          envelope = read_envelope(path)
          params = parser.template_params(envelope["wikitext"], "inscription") || {}
          metadata["kind"] = "metadata_only" if parser.reading_lines(params["reading"]).empty?
          join_paths(workdir, params) { |key, join_path| metadata[key] = join_path }
        rescue ParseError
          metadata = {} # parse will re-raise with the real message
        end
        Nabu::DocumentRef.new(source_id: manifest.id, id: urn_for(path), path: path, metadata: metadata)
      end

      # urn from the page FILENAME (the encoded title), so discovery ids
      # never depend on a readable envelope.
      def urn_for(path)
        title = Nabu::WikiFetch.decode_title(File.basename(path, ".json"))
        "#{self.class.urn_prefix}#{self.class.title_segment(title)}"
      end

      # The object page behind |object=, and its site page behind |site=.
      def join_paths(workdir, params)
        object_path = page_path(workdir, OBJECT_CATEGORY, params["object"]) or return
        yield "object_path", object_path

        site = read_params(object_path, "object")&.fetch("site", nil)
        site_path = page_path(workdir, SITE_CATEGORY, site) or return
        yield "site_path", site_path
      end

      def page_path(workdir, category, title)
        return nil if title.nil? || title.strip.empty?

        path = File.join(workdir, Nabu::WikiFetch::PAGES_DIRNAME, category,
                         "#{Nabu::WikiFetch.encode_title(title.strip)}.json")
        File.file?(path) ? File.expand_path(path) : nil
      end

      # -- parse -----------------------------------------------------------------

      def read_envelope(path)
        envelope = JSON.parse(File.read(path))
        raise ParseError, "#{path}: page envelope has no wikitext" unless envelope["wikitext"].is_a?(String)

        envelope
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable page envelope: #{e.message}"
      end

      def build_document(document_ref, envelope, params)
        Nabu::Document.new(
          urn: document_ref.id,
          language: language_for(params),
          title: Nabu::Normalize.nfc(envelope.fetch("title")),
          canonical_path: document_ref.path,
          metadata: document_metadata(document_ref, params)
        )
      end

      def add_passages(document, document_ref, params)
        return if document_ref.metadata["kind"] == "metadata_only"

        lines = parser.reading_lines(params["reading"])
        raise ParseError, "#{document_ref.path}: reading extracted no lines for #{document_ref.id}" if lines.empty?

        lines.each_with_index do |line, index|
          annotations = line.words.empty? ? {} : { "words" => line.words }
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{index + 1}", language: document.language,
            text: Nabu::Normalize.nfc(line.text), sequence: index, annotations: annotations
          )
        end
      end

      # The subclass map decides the tag; an unmapped upstream value reads
      # "und" with the verbatim value kept in metadata (language_raw) — a
      # vocabulary drift is visible, never a quarantine.
      def language_for(params)
        raw = params["language"].to_s.strip
        self.class.language_map.fetch(raw, "und")
      end

      def document_metadata(document_ref, params)
        metadata = template_metadata(params)
        metadata["text_layer"] = "none" if document_ref.metadata["kind"] == "metadata_only"
        object_params = read_params(document_ref.metadata["object_path"], "object")
        site_params = read_params(document_ref.metadata["site_path"], "site")
        facets = build_facets(params, object_params)
        metadata["facets"] = facets unless facets.empty?
        place = build_place(object_params, site_params)
        metadata["place"] = place unless place.empty?
        related = build_related(params)
        metadata["related"] = related unless related.empty?
        metadata
      end

      def template_metadata(params)
        metadata = {}
        METADATA_PARAMS.each do |key|
          value = present(params[key]) or next
          metadata[key] = Nabu::Normalize.nfc(value)
        end
        metadata.delete("type_inscription") # rides as the genre facet
        original = present(params["reading_original"]) || present(params["reading_lepontic"])
        metadata["reading_original"] = original if original
        metadata["object"] = Nabu::Normalize.nfc(params["object"]) if present(params["object"])
        raw = params["language"].to_s.strip
        metadata["language_raw"] = raw unless raw.empty?
        metadata
      end

      def build_facets(params, object_params)
        facets = {}
        add_facet(facets, "genre", present(params["type_inscription"]))
        add_facet(facets, "object_type", present(object_params&.fetch("type_object", nil)))
        add_facet(facets, "material", present(object_params&.fetch("material", nil)))
        facets
      end

      def add_facet(facets, facet, value)
        return if value.nil?

        normalized = Nabu::Normalize.nfc(value)
        facets[facet] = { "value" => normalized, "raw" => normalized }
      end

      # Findspot geography: the object's site + its coordinates when the
      # object page carries them (the findspot-precision layer), else the
      # site page's; administrative lanes from the site page. All verbatim.
      def build_place(object_params, site_params)
        place = {}
        site = present(object_params&.fetch("site", nil))
        place["site"] = Nabu::Normalize.nfc(site) if site
        %w[country province region].each do |key|
          value = present(site_params&.fetch(key, nil)) or next
          place[key] = Nabu::Normalize.nfc(value)
        end
        coordinates = coordinate_pair(object_params) || coordinate_pair(site_params)
        place.merge!(coordinates) if coordinates
        place
      end

      def coordinate_pair(params)
        north = present(params&.fetch("coordinate_n", nil))
        east = present(params&.fetch("coordinate_e", nil))
        return nil unless north && east

        { "coordinate_n" => north, "coordinate_e" => east }
      end

      def build_related(params)
        self.class.concordances.filter_map do |param, scheme|
          value = present(params[param]) or next
          "#{scheme}:#{Nabu::Normalize.nfc(value)}"
        end
      end

      def read_params(path, template)
        return nil if path.nil?

        parser.template_params(read_envelope(path)["wikitext"], template)
      rescue ParseError
        nil # a broken join page costs its metadata, never the document
      end

      def present(value)
        value = value.to_s.strip
        value.empty? || value == UNKNOWN ? nil : value
      end
    end
  end
end
