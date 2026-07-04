# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The PROIEL Treebank adapter (architecture §3, packet P3-4): a thin
    # composition of the ProielParser family with the proiel-treebank repo
    # layout (one flat directory of per-source *.xml files). It owns what the
    # streaming parser deliberately does not: repo walking, source-level
    # metadata resolution (title/language read cheaply from each file's
    # <source> header), and fetch.
    #
    # == One DocumentRef per source file
    #
    # The repo ships one file per work (cic-off.xml, wulf-gothic.xml, …); each
    # is one document. The urn is minted from the file's own <source id> —
    # urn:nabu:proiel:<source-id> — NOT the filename, so a rename upstream does
    # not silently fork a document's identity. ref.id == parse(ref).urn (the
    # conformance identity the sync circuit breaker relies on) because the
    # parser mints the document urn from that same id.
    #
    # == fetch
    #
    # Single upstream repo (unlike UD's N repos), so the Perseus git clone/pull
    # pattern applies verbatim. NOTE FOR THE FUTURE: proiel-treebank is FROZEN at
    # release 20180408 — its successor is proiel/syntacticus-treebank-data. This
    # adapter is registered sync_policy: frozen; when the corpus migrates,
    # point upstream_url at the successor (and re-verify the schema) rather than
    # expecting new commits here.
    #
    # == License
    #
    # CC BY-NC-SA — the repo README states 3.0, but every per-source <source>
    # header carries its own <license> (cic-off: CC BY-NC-SA 4.0). The manifest
    # records the class (nc) so query/export filters never over-share; the
    # verbatim per-source text lives in the files (the parser ignores it; a
    # future enrichment could surface it).
    class Proiel < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "proiel",
        name: "PROIEL Treebank",
        license: "CC BY-NC-SA (3.0 repo / 4.0 per-source — see source headers)",
        license_class: "nc",
        upstream_url: "https://github.com/proiel/proiel-treebank",
        parser_family: "proiel"
      )

      def self.manifest
        MANIFEST
      end

      # Walk <workdir>/*.xml (sorted), one DocumentRef per treebank source file.
      # Files without a readable <source> element are skipped defensively (the
      # repo carries the odd non-treebank .xml — e.g. schema/build artifacts —
      # that must not error discover). Returns an Enumerator without a block.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Delegate to the ProielParser with the urn/language/title discover
      # resolved from the source header.
      def parse(document_ref)
        ProielParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: document_ref.metadata["language"],
          title: document_ref.metadata["title"]
        )
      end

      # Clone (first time) or ff-only pull (thereafter) the single upstream repo
      # into +workdir+, returning a Nabu::FetchReport pinning HEAD. No network in
      # tests: exercised against a local fixture git repo. A Shell failure aborts
      # the sync as Nabu::FetchError.
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

      # The upstream repo URL. Resolved through the overridable #manifest (not
      # the lexical MANIFEST constant) so subclasses — TOROT (P3-5) — fetch
      # THEIR own repo, not proiel-treebank. Split out so fetch tests can point a
      # singleton at a local git tmpdir (the Perseus/UD test pattern), keeping
      # fetch off the network.
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
        Dir.glob(File.join(workdir, "*.xml")).filter_map do |path|
          header = peek_source(path)
          next unless header

          Nabu::DocumentRef.new(
            # source_id follows the (possibly subclassed) manifest — "torot" for
            # the TOROT sibling — while the urn namespace stays the literal
            # "proiel": TOROT's source ids share the PROIEL id-space, so both
            # corpora mint under one namespace on purpose (see Torot's header).
            source_id: manifest.id,
            id: "urn:nabu:proiel:#{header[:id]}",
            path: File.expand_path(path),
            metadata: { "language" => header[:language], "title" => header[:title] }
          )
        end.sort_by(&:id)
      end

      # Cheap Reader peek at a file's <source> header: id + language attributes
      # and the source <title> text, stopping at the first <div> (the header is
      # near the top, so a treebank file is read only a few KB in). Returns nil —
      # skip the file — when no <source> is found or the XML is malformed. Never
      # DOMs the multi-MB body.
      def peek_source(path)
        id = language = title = nil
        in_source = false
        capture_title = false
        File.open(path, "r") do |io|
          reader = Nokogiri::XML::Reader(io, path)
          reader.each do |node|
            case node.node_type
            when Nokogiri::XML::Reader::TYPE_ELEMENT
              case node.name
              when "source"
                in_source = true
                id = node.attribute("id")
                language = node.attribute("language")
              when "title"
                capture_title = true if in_source && title.nil?
              when "div"
                break
              end
            when Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_CDATA
              if capture_title
                title = node.value.to_s.strip
                capture_title = false
              end
            end
          end
        end
        id.nil? ? nil : { id: id, language: language, title: title }
      rescue Nokogiri::XML::SyntaxError
        nil
      end
    end
  end
end
