# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The SARIT adapter (P26-2): scholarly TEI editions of Sanskrit (and a
    # few Braj/Awadhi) texts from SARIT — Search and Retrieval of Indic
    # Texts. A thin composition of the SaritParser family with the corpus
    # repo layout: one flat directory of per-work TEI files at the repo
    # root. ~60 of the 83 works are texts GRETIL lacks, including a complete
    # Mahābhārata (the Southern Recension — see below).
    #
    # == Identity (FROZEN minting)
    #
    # urn = urn:nabu:sarit:<text-slug>, the LITERAL filename stem (the
    # GRETIL precedent: upstream file names are the stable ids). Passage
    # urns append the parser's citation. Trimmed FIXTURES carry suffixed
    # names (…-s1-2, …-adi1-svarga1), so fixture urns never collide with the
    # real corpus urns minted at the owner-fired first sync (UD-style).
    #
    # == Discovery
    #
    # discover globs the top-level *.xml (texts live flat at the root; the
    # schemas/ and tools/ trees are not editions) and peeks each header for
    # title + language. Two files are skipped by rule and censused in
    # discovery_skips: saritcorpus.xml (a <teiCorpus> xi:include wrapper,
    # not an edition) and 00-sarit-tei-header-template.xml (the upstream
    # header template).
    #
    # == Language (the census ladder, 2026-07-18)
    #
    # <text>/@xml:lang (63 files) → <body>/@xml:lang (14: buddhacarita,
    # nyāyasudhā, the Braj/Awadhi texts, …) → for the six files that declare
    # NEITHER (rasārṇava, sarvadarśanasaṅgraha, cakrapāṇidatta,
    # pramāṇāntarbhāva, vādasthāna, kalyāṇakāraka — all Sanskrit works), a
    # script sniff of the first body text: Devanagari codepoints → san-Deva,
    # else san-Latn. Mapped ISO 639-1/bare names → 639-3 (sa → san,
    # braj → bra, avadhi → awa), script subtag preserved. 41/83 files are
    # Devanagari-surface; the parser mints their search form from the
    # Deva→IAST transcode (Nabu::Deva), canonical text untouched.
    #
    # == License (the GRETIL-upgrade posture)
    #
    # Whole-corpus header census 2026-07-18: CC BY-SA 4.0 ×56, CC BY-SA 3.0
    # ×26, MIT ×1 — ZERO NC (GRETIL itself stays nc-locked; this is the open
    # Sanskrit shelf). All three grants fold to license_class "attribution".
    # The manifest carries the census; the PARSER re-verifies every file's
    # <availability> at parse and stores the per-document grant in
    # Document#metadata["license"] — a grant outside BY-SA/MIT quarantines.
    #
    # == The Mahābhārata recension caveat (censused, not assumed)
    #
    # SARIT's MBh is the SOUTHERN RECENSION (Kumbakonam: T.R. Krishnacharya
    # & T.R. Vyasacharya, 1906–1910, per its own editionStmt) — NOT the BORI
    # critical edition and NOT the Calcutta vulgate that Monier-Williams's
    # "MB." citations reference. Numbering diverges throughout, so MW
    # citation joins are NOT promised for this text (02-sources row).
    #
    # == fetch
    #
    # canonical/sarit/ is one git clone of github.com/sarit/SARIT-corpus via
    # the shared non-destructive path (Adapter#git_fetch! → Nabu::GitFetch,
    # attic + breaker). Full-corpus footprint at HEAD 1eac9ee (2026-07-18):
    # ~170 MB of TEI + ~33 MB .git ≈ 204 MB on disk. Upstream is a dormant
    # scholarly project (last merge 2021) → sync_policy manual.
    class Sarit < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "sarit",
        name: "SARIT — Search and Retrieval of Indic Texts (scholarly TEI editions)",
        license: "CC BY-SA 4.0 x56 / CC BY-SA 3.0 x26 / MIT x1 (per-file availability, censused 2026-07-18; " \
                 "corpus default CC BY-SA 3.0)",
        license_class: "attribution",
        upstream_url: "https://github.com/sarit/SARIT-corpus",
        parser_family: "sarit"
      )

      # Skipped by rule at discovery (censused in discovery_skips).
      TEMPLATE_BASENAME = "00-sarit-tei-header-template.xml"
      CORPUS_WRAPPER_BASENAME = "saritcorpus.xml"
      NON_EDITIONS = [TEMPLATE_BASENAME, CORPUS_WRAPPER_BASENAME].freeze

      # Devanagari block, for the script sniff of undeclared-language files.
      DEVANAGARI = /[ऀ-ॿ]/

      def self.manifest
        MANIFEST
      end

      # Walk <workdir> top-level for SARIT TEI editions, one DocumentRef per
      # file, sorted by urn. Returns an Enumerator without a block (the
      # adapter contract's lazy shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The two by-rule non-editions (template + teiCorpus wrapper) plus any
      # file the header peek cannot read — visible, never silent (P11-7).
      def discovery_skips(workdir)
        skipped = Dir.glob(File.join(workdir, "*.xml")).count { |path| peek_header(path).nil? }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped)
      end

      def parse(document_ref)
        SaritParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: document_ref.metadata["language"],
          title: document_ref.metadata["title"]
        )
      end

      # Clone or non-destructively pull the corpus repo (attic + mass-deletion
      # breaker). No network in tests: exercised against a local fixture repo.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Split out so fetch tests can point a singleton at a local git tmpdir
      # (the house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end

      def document_refs(workdir)
        Dir.glob(File.join(workdir, "*.xml")).filter_map do |path|
          header = peek_header(path)
          next unless header

          slug = File.basename(path, ".xml")
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:sarit:#{slug}",
            path: File.expand_path(path),
            metadata: { "language" => header[:language], "title" => header[:title] || slug }
          )
        end.sort_by(&:id)
      end

      # Cheap Reader peek: the main title, and the language ladder —
      # <text>/@xml:lang → <body>/@xml:lang → script sniff of the first
      # non-blank body text (san default; see the class comment). Returns
      # nil — skip the file — for the two by-rule non-editions, a
      # <teiCorpus> root, or malformed XML.
      def peek_header(path)
        return nil if NON_EDITIONS.include?(File.basename(path))

        title, language = read_header(path)
        return nil if language == :not_an_edition

        { title: title, language: language }
      rescue Nokogiri::XML::SyntaxError
        nil
      end

      def read_header(path)
        peek = HeaderPeek.new
        File.open(path, "r") do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            break if peek.process(node) == :done
          end
        end
        return [nil, :not_an_edition] if peek.corpus_root?

        [peek.title, peek.language]
      end

      # Streaming header peek state (title + language ladder + root check).
      class HeaderPeek
        attr_reader :title

        def initialize
          @title = nil
          @root_seen = false
          @corpus_root = false
          @capture_title = false
          @text_lang = nil
          @body_lang = nil
          @in_body = false
          @sniffed = nil
        end

        def corpus_root?
          @corpus_root
        end

        # The declared tag, else the sniffed script default (san).
        def language
          SaritParser.normalize_language(@text_lang || @body_lang) || @sniffed
        end

        def process(node)
          case node.node_type
          when Nokogiri::XML::Reader::TYPE_ELEMENT then element(node)
          when Nokogiri::XML::Reader::TYPE_END_ELEMENT
            @capture_title = false
            :done if node.name.split(":").last == "body"
          when Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_CDATA
            text(node)
          end
        end

        private

        def element(node)
          name = node.name.split(":").last
          unless @root_seen
            @root_seen = true
            @corpus_root = name == "teiCorpus"
            return :done if @corpus_root
          end
          case name
          when "title" then @capture_title = true if @title.nil?
          when "text" then @text_lang ||= node.attribute("xml:lang")
          when "body"
            @body_lang ||= node.attribute("xml:lang")
            @in_body = true
            # A declared language ends the peek; otherwise stream on to
            # sniff the first body text.
            return :done if @text_lang || @body_lang
          end
          nil
        end

        def text(node)
          value = node.value.to_s
          if @capture_title
            stripped = value.strip
            @title = stripped unless stripped.empty?
            @capture_title = false
          end
          return unless @in_body && @sniffed.nil?

          stripped = value.strip
          return if stripped.empty?

          @sniffed = Sarit::DEVANAGARI.match?(stripped) ? "san-Deva" : "san-Latn"
          :done
        end
      end
      private_constant :HeaderPeek
    end
  end
end
