# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The GRETIL adapter (architecture §3, packet P9-4b): a thin composition of
    # the GretilParser family with the mass-converted TEI corpus layout. It owns
    # what the streaming parser deliberately does not: corpus walking, header
    # metadata resolution (title + language peeked cheaply from each file's
    # teiHeader), urn minting, and fetch.
    #
    # == Layout and discovery
    #
    # The TEI corpus is one flat directory of per-work files named
    # "<lang>_<TextName>.xml" (e.g. sa_brahmabindUpaniSad.xml). discover globs
    # **/*.xml under the workdir (the default Dir.glob skips the .attic dotdir,
    # so the retention overlay stays the base class's job) and peeks each
    # header; a file without a <text>/@xml:lang (not a GRETIL edition) is
    # skipped defensively.
    #
    # == Identity (FROZEN minting)
    #
    # urn = urn:nabu:gretil:<text-slug>, where <text-slug> is the LITERAL
    # filename stem (extension dropped, prefix KEPT): sa_brahmabindUpaniSad.xml
    # → urn:nabu:gretil:sa_brahmabindUpaniSad. The "sa_" language prefix is part
    # of GRETIL's stable upstream file id, so it stays in the slug (the scout's
    # P9-4a "keep the literal filename slug" decision — no re-slugification that
    # could drift). Passage urns append the parser's citation:
    # <doc-urn>:<citation> (…:sa_brahmabindUpaniSad:1). Minting is frozen once
    # used (standing rule). NOTE: the trimmed Ṛgveda fixture is named
    # sa_Rgveda-edAufrecht-m1s1-3.xml, so its fixture urn carries the trim
    # suffix; the real corpus file sa_Rgveda-edAufrecht.xml mints
    # urn:nabu:gretil:sa_Rgveda-edAufrecht at the owner-fired first sync
    # (UD-style: the fixture is a trim, its urn is a fixture urn).
    #
    # == fetch (the shared git path — mirror-scope verified P9-4b)
    #
    # canonical/gretil/ is populated by cloning the GitHub TEI mirror
    # mmehner/gretil-corpus-tei, which serves BYTE-IDENTICAL copies of the site
    # files (verified: the two whole fixtures match the live
    # gretil.sub.uni-goettingen.de/gretil/corpustei/ bytes exactly) and — despite
    # a 2021 pushed_at — still covers the FULL CURRENT TEI corpus: the live
    # corpustei directory holds 784 XML files (781 sa_ + 2 xct_ + 1 ta-sa_),
    # the SAME count and language mix as the mirror, i.e. GRETIL's TEI
    # conversion has been stable since 2021. So fetch stays on the ordinary
    # Perseus/Papyri git clone/pull path (Adapter#git_fetch! → Nabu::GitFetch,
    # attic + pre-merge mass-deletion breaker); no per-file HTTP crawler is
    # needed. The manifest upstream_url points at the mirror; the live site and
    # the fuller INDOLOGY/GRETIL-mirror are recorded here as cross-checks. No
    # network in tests: exercised against a local fixture git repo.
    #
    # == License
    #
    # Uniform CC BY-NC-SA 4.0 in every teiHeader <availability>, under a
    # good-faith/takedown disclaimer (GRETIL is an aggregator, not the
    # rights-holder) → license_class "nc" (the same class UD-PROIEL lives
    # under). Ingestable for local research, indexed/searchable, but
    # default-excluded from the MCP surface and never redistributed.
    class Gretil < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "gretil",
        name: "GRETIL — Göttingen Register of Electronic Texts in Indian Languages (TEI corpus)",
        license: "CC BY-NC-SA 4.0 (per-text availability; aggregator, takedown disclaimer)",
        license_class: "nc",
        upstream_url: "https://github.com/mmehner/gretil-corpus-tei",
        parser_family: "gretil"
      )

      def self.manifest
        MANIFEST
      end

      # Walk <workdir> for GRETIL TEI files, one DocumentRef per file, sorted by
      # urn. Returns an Enumerator without a block (the adapter contract's lazy
      # shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Delegate to GretilParser with the urn/language/title discover resolved
      # from the header.
      def parse(document_ref)
        GretilParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: document_ref.metadata["language"],
          title: document_ref.metadata["title"]
        )
      end

      # Clone or non-destructively pull the TEI mirror into +workdir+ via the
      # shared git path (Adapter#git_fetch! → Nabu::GitFetch, P5-2: attic +
      # pre-merge mass-deletion breaker), returning a Nabu::FetchReport pinning
      # HEAD. No network in tests: exercised against a local fixture git repo.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # The upstream repo URL, split out so fetch tests can point a singleton at
      # a local git tmpdir (the house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end

      def document_refs(workdir)
        Dir.glob(File.join(workdir, "**", "*.xml")).filter_map do |path|
          header = peek_header(path)
          next unless header

          slug = File.basename(path, ".xml")
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:gretil:#{slug}",
            path: File.expand_path(path),
            metadata: { "language" => header[:language], "title" => header[:title] || slug }
          )
        end.sort_by(&:id)
      end

      # Cheap Reader peek at a file's header: the titleStmt <title> and the
      # <text>/@xml:lang (mapped sa→san), stopping at <body>. Returns nil — skip
      # the file — when there is no text language (not a GRETIL edition) or the
      # XML is malformed.
      def peek_header(path)
        title, language = read_header(path)
        return nil if language.nil?

        { title: title, language: language }
      rescue Nokogiri::XML::SyntaxError
        nil
      end

      def read_header(path)
        title = language = nil
        capture_title = false
        File.open(path, "r") do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            case node.node_type
            when Nokogiri::XML::Reader::TYPE_ELEMENT
              case node.name.split(":").last
              when "title" then capture_title = true if title.nil?
              when "text"
                language = GretilParser.normalize_language(node.attribute("xml:lang"))
              when "body" then break # the peek never reads into the text body
              end
            when Nokogiri::XML::Reader::TYPE_END_ELEMENT
              capture_title = false
            when Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_CDATA
              if capture_title
                value = node.value.to_s.strip
                title = value unless value.empty?
                capture_title = false
              end
            end
          end
        end
        [title, language]
      end
    end
  end
end
