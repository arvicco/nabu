# frozen_string_literal: true

require_relative "lexicon_tei_parser"

module Nabu
  module Adapters
    # The Perseus lexica source (P11-4): LSJ + Lewis & Short from
    # PerseusDL/lexica — the first DICTIONARY-shaped source. Dictionaries ARE
    # registry sources (architecture §11): same canonical/<slug>/ dir, same
    # GitFetch attic-protected pull, same ledger runs/pins and health probes —
    # only the CONTENT SHAPE differs, declared via .content_kind so
    # SyncRunner/Rebuild route the load to Store::DictionaryLoader instead of
    # the passage Loader. parse returns Nabu::DictionaryDocument (entries),
    # never passages: dictionary entries must not flood full-text search.
    #
    # == Scope
    #
    # One clone carries both lexica. LSJ is 27 letter-split files
    # (grc.lsj.perseus-eng*.xml, all ingested); Lewis & Short ships twice and
    # only the Unicode variant is ingested (lat.ls.perseus-eng2.xml — eng1
    # keeps its Greek in betacode "for archival purposes only" per the
    # upstream README, and ingesting both would duplicate every entry). LSJ's
    # own Greek (keys, orths, quotes) IS betacode, decoded at this boundary
    # (Nabu::Betacode) like any other text normalization. The repo's third
    # lexicon dir (lat/viaf2845558) is out of scope.
    #
    # == License
    #
    # CC BY-SA 4.0, repo-wide (license.md is the BY-SA legalcode; the README
    # and both per-lexicon READMEs carry the grant: "This text may be freely
    # distributed under a CC BY-SA 4.0 license … You credit Perseus")
    # → license_class "attribution", the perseus-greek/latin class. Define
    # output labels every entry with it.
    class Lexica < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "lexica",
        name: "Perseus Lexica — LSJ + Lewis & Short",
        license: "CC BY-SA 4.0 (credit Perseus Digital Library; data from github.com/PerseusDL/lexica)",
        license_class: "attribution",
        upstream_url: "https://github.com/PerseusDL/lexica",
        parser_family: "lexicon-tei"
      )

      # The two dictionaries this source carries, keyed by dictionary slug.
      # Adding a dictionary from the same repo is one entry here; a dictionary
      # from ANOTHER upstream (Bosworth-Toller) is its own adapter writing the
      # same store shape (architecture §11).
      DICTIONARIES = {
        "lsj" => {
          title: "A Greek-English Lexicon (Liddell-Scott-Jones)",
          language: "grc", betacode: true,
          dir: "CTS_XML_TEI/perseus/pdllex/grc/lsj", glob: "grc.lsj.perseus-eng*.xml"
        },
        "lewis-short" => {
          title: "A Latin Dictionary (Lewis & Short)",
          language: "lat", betacode: false,
          dir: "CTS_XML_TEI/perseus/pdllex/lat/ls", glob: "lat.ls.perseus-eng2.xml"
        }
      }.freeze

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): this source loads through
      # Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # Clone or non-destructively pull the lexica repo via the shared git
      # path (GitFetch: attic + pre-merge mass-deletion breaker).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      # One DocumentRef per lexicon FILE (LSJ's 27 letter files + the one
      # Unicode Lewis & Short), sorted by id. The id embeds the dictionary
      # slug and the stable upstream basename; the same walk works under the
      # attic (same relative shapes), so retention costs nothing here.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        config = DICTIONARIES.fetch(slug)
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: config.fetch(:language),
          title: config.fetch(:title), canonical_path: document_ref.path
        )
        LexiconTeiParser.new
                        .entries(document_ref.path, language: config.fetch(:language),
                                                    betacode: config.fetch(:betacode))
                        .each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "lexica: #{document_ref.id}: #{e.message}"
      end

      private

      # Split out so fetch tests can point a singleton at a local git tmpdir
      # (the house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end

      def document_refs(workdir)
        DICTIONARIES.flat_map do |slug, config|
          Dir.glob(File.join(workdir, config.fetch(:dir), config.fetch(:glob))).map do |path|
            Nabu::DocumentRef.new(
              source_id: manifest.id,
              id: "lexica:#{slug}:#{File.basename(path)}",
              path: File.expand_path(path),
              metadata: { "dictionary" => slug }
            )
          end
        end.sort_by(&:id)
      end
    end
  end
end
