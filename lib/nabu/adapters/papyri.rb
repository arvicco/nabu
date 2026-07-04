# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The Papyri.info adapter (architecture §3, packet P3-6): a thin
    # composition of the DdbdpParser family with the idp.data repo layout. It
    # owns what the streaming parser deliberately does not: repo walking,
    # header metadata resolution (idnos/title/language peeked cheaply from
    # each file's teiHeader), and fetch.
    #
    # == Layout and discovery
    #
    # The DDbDP tree lives under DDB_EpiDoc_XML/<collection>/, with volumed
    # collections nesting one more level (<collection>.<volume>/): both
    # bgu/bgu.1/bgu.1.102.xml (nested) and c.epist.lat/c.epist.lat.10.xml
    # (flat, volume-less) occur. Discover globs both shapes and peeks each
    # header; files without an <idno type="ddb-hybrid"> or an edition
    # language are skipped defensively (the repo carries the odd non-DDbDP
    # artifact that must not error discover).
    #
    # == Identity (FROZEN minting)
    #
    # urn = urn:nabu:ddbdp:<ddb-hybrid with ";" replaced by ":">, e.g. idno
    # "bgu;1;102" → urn:nabu:ddbdp:bgu:1:102. Empty hybrid segments survive:
    # "c.epist.lat;;10" (volume-less) → urn:nabu:ddbdp:c.epist.lat::10. The
    # parser mints from the same idno and cross-checks, so
    # ref.id == parse(ref).urn (the conformance identity the sync circuit
    # breaker relies on). HGV and TM idnos ride along in DocumentRef metadata
    # for future cross-linking (Trismegistos is the id crosswalk of the
    # papyrological world).
    #
    # == fetch
    #
    # Single upstream repo → the Perseus git clone/pull pattern verbatim.
    # idp.data is HUGE (hundreds of thousands of files, years of edit
    # history), so the house `--depth 1` clone matters even more than usual
    # here. sync_policy: manual — DDbDP updates continuously but syncing it
    # is an owner decision, not a scheduled one.
    #
    # == License
    #
    # Repo and per-document <availability> agree: CC BY 3.0 ("© Duke Databank
    # of Documentary Papyri … Creative Commons Attribution 3.0 License") —
    # license_class "attribution". "per-document availability" in the
    # manifest license string records where the authoritative statement
    # lives.
    class Papyri < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "papyri-ddbdp",
        name: "Papyri.info — Duke Databank of Documentary Papyri",
        license: "CC BY 3.0 (per-document availability)",
        license_class: "attribution",
        upstream_url: "https://github.com/papyri/idp.data",
        parser_family: "ddbdp"
      )

      # Header idno types discover records (beyond ddb-hybrid identity).
      IDNO_TYPES = %w[ddb-hybrid HGV TM].freeze
      private_constant :IDNO_TYPES

      def self.manifest
        MANIFEST
      end

      # Walk <workdir>/DDB_EpiDoc_XML for both nested and flat collections,
      # one DocumentRef per DDbDP file, sorted by urn. Returns an Enumerator
      # without a block (the adapter contract's lazy shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Delegate to the DdbdpParser with the urn/language/title discover
      # resolved from the header.
      def parse(document_ref)
        DdbdpParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: document_ref.metadata["language"],
          title: document_ref.metadata["title"]
        )
      end

      # Clone (first time) or ff-only pull (thereafter) the idp.data repo
      # into +workdir+, returning a Nabu::FetchReport pinning HEAD. No
      # network in tests: exercised against a local fixture git repo. A
      # Shell failure aborts the sync as Nabu::FetchError.
      def fetch(workdir, progress: nil)
        if Dir.exist?(File.join(workdir, ".git"))
          git_pull(workdir, progress)
        else
          git_clone(workdir, progress)
        end
        sha = Nabu::Shell.run("git", "-C", workdir, "rev-parse", "HEAD").strip
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now, notes: nil)
      rescue Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{manifest.id} fetch failed for #{repo_url} into #{workdir}: #{e.message}"
      end

      private

      # The upstream repo URL, split out so fetch tests can point a singleton
      # at a local git tmpdir (the house pattern), keeping fetch off the
      # network.
      def repo_url
        manifest.upstream_url
      end

      def git_clone(workdir, progress)
        return Nabu::Shell.run("git", "clone", "--depth", "1", repo_url, workdir) unless progress

        progress.call("Cloning #{repo_url}…")
        Nabu::Shell.stream("git", "clone", "--progress", "--depth", "1", repo_url, workdir) { |line| progress.call(line) }
      end

      def git_pull(workdir, progress)
        return Nabu::Shell.run("git", "-C", workdir, "pull", "--ff-only") unless progress

        progress.call("Pulling #{repo_url}…")
        Nabu::Shell.stream("git", "-C", workdir, "pull", "--progress", "--ff-only") { |line| progress.call(line) }
      end

      def document_refs(workdir)
        root = File.join(workdir, "DDB_EpiDoc_XML")
        paths = Dir.glob(File.join(root, "*", "*.xml")) + Dir.glob(File.join(root, "*", "*", "*.xml"))
        paths.filter_map do |path|
          header = peek_header(path)
          next unless header

          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:ddbdp:#{header[:hybrid].tr(';', ':')}",
            path: File.expand_path(path),
            metadata: metadata_for(header, path)
          )
        end.sort_by(&:id)
      end

      def metadata_for(header, path)
        metadata = {
          "language" => header[:language],
          "title" => header[:title] || File.basename(path, ".xml")
        }
        metadata["hgv"] = header[:hgv] if header[:hgv]
        metadata["tm"] = header[:tm] if header[:tm]
        metadata
      end

      # Cheap Reader peek at a file's teiHeader (Proiel#peek_source pattern):
      # the interesting idnos, the titleStmt <title>, and — first thing past
      # the header — the edition div's xml:lang (mapped la→lat), stopping
      # right there. Returns nil — skip the file — when the ddb-hybrid idno
      # or the edition language is missing, or the XML is malformed. Never
      # reads past the edition div's start tag.
      def peek_header(path)
        idnos, title, language = read_header(path)
        hybrid = idnos["ddb-hybrid"]
        return nil if hybrid.nil? || hybrid.empty? || language.nil?

        { hybrid: hybrid, title: title, language: language, hgv: idnos["HGV"], tm: idnos["TM"] }
      rescue Nokogiri::XML::SyntaxError
        nil
      end

      def read_header(path)
        idnos = {}
        title = language = nil
        capture = nil # :title, an IDNO_TYPES member, or nil
        File.open(path, "r") do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            case node.node_type
            when Nokogiri::XML::Reader::TYPE_ELEMENT
              case node.name.split(":").last
              when "idno"
                capture = IDNO_TYPES.find { |type| type == node.attribute("type") }
              when "title"
                capture = :title if title.nil?
              when "div"
                if node.attribute("type") == "edition"
                  language = DdbdpParser.normalize_language(node.attribute("xml:lang"))
                  break # the peek never reads past the edition div's start tag
                end
              end
            when Nokogiri::XML::Reader::TYPE_END_ELEMENT
              capture = nil
            when Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_CDATA
              value = node.value.to_s.strip
              title = value if capture == :title
              idnos[capture] = value if capture.is_a?(String)
              capture = nil
            end
          end
        end
        [idnos, title, language]
      end
    end
  end
end
