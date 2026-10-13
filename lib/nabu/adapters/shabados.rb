# frozen_string_literal: true

require_relative "shabados_toml"

module Nabu
  module Adapters
    # Shabad OS — the Gurmukhī PRIMARY text of Sikh scripture and the
    # Panthic canon (P122-3). The Shabad OS database is a volunteer-
    # proofread digital representation of Gurbāṇī and Panthic texts with a
    # public correction log; development moved from the archived
    # shabados/database repo to the shabados/shabados monorepo, whose
    # database/collections/ is the live home (census at 307ed9d1,
    # 2026-10-12) — 141,264 line records under ten sources:
    #
    #   SGGS  Sri Guru Granth Sahib         51 sections · 60,555 lines
    #   SDGR  Sri Dasam Granth              17 sections · 67,758 lines
    #   VBGJ  Vārāṅ Bhāī Gurdās             41 sections ·  7,585 lines
    #   KSBG  Kabitt Savayye Bhāī Gurdās     1 section  ·  2,761 lines
    #   ZNNL  Zindagī-nāmā (Bhāī Nand Lāl)   1 section  ·  1,021 lines
    #   GZNL  Dīvān-i Goyā (Bhāī Nand Lāl)   2 sections ·    806 lines
    #   JBNL  Jot Bigās, Fārsī (Nand Lāl)    1 section  ·    352 lines
    #   GJNL  Ganj-nāmā (Bhāī Nand Lāl)     10 sections ·    331 lines
    #   SRBL  Sarabloh Granth (selections)   2 sections ·     78 lines
    #   ARDS  Ardās                          1 section  ·     17 lines
    #
    # == Scope: type = "primary" ONLY
    #
    # Every line record carries [[content]] entries of four types —
    # primary (the scripture itself, 141,945 entries), translation
    # (en/pa/es, 479,256), note (pa, 49,486), pronunciation. The database
    # README places "gurbani and panthic texts" in the public domain
    # (Public Domain Mark 1.0) — the scripture; the modern translations and
    # glosses riding the same records carry no grant of their own, so they
    # are never read. 681 lines carry a SECOND primary from another printed
    # source (the Dasam Granth's Damdami Taksāl gutkā reading beside the
    # SGPC Das Granthī): the first primary is the text, the others ride
    # annotations "variants" verbatim (assets + text).
    #
    # == Identity and grain
    #
    #   document = one SECTION (a raag of the Granth, a bāṇī, a vār):
    #     urn:nabu:shabados:<SOURCE>.<SECTION>     (…:SGGS.1DSA — Jap)
    #   passage = one LINE, cited by its upstream line id:
    #     <urn>:<LINE>                             (…:SGGS.1DSA:0NVY)
    #
    # Upstream ids are the database's own stable keys (retired ids are
    # recorded upstream, never reused). Sources and sections are read in
    # the database's own order; line groups (a shabad/stanza) ride each
    # passage as "line_group" with the group's author and SikhiToTheMax id
    # (sttm2); page ("ang") and the line on the page ride where the record
    # carries them (SGGS, the Dasam Granth, Ganj-nāmā).
    #
    # Text is the primary data VERBATIM (NFC): the database's vishrām
    # pause marks (";" and ".") inside the line are upstream's encoding,
    # never stripped.
    #
    # == Languages (a declared per-source/per-section judgment table)
    #
    # All text is Gurmukhī script. The language claim is coarse and
    # declared: the Guru Granth Sahib (its Sant Bhāṣā / Old Punjabi mix,
    # Lahndā, Braj and Sahaskritī passages all folded), the Vārāṅ and the
    # Ardās → "pan" (Punjabi, native script — the bare code); the Dasam
    # Granth, the Kabitt Savayye and the Sarabloh Granth → "bra-Guru"
    # (Braj in Gurmukhī) except its Punjabi Vār Srī Bhagautī Jī Kī (VJB5)
    # and its Persian Zafarnāmā (546R) and Hikāyatāṅ (1MZM); Bhāī Nand
    # Lāl's four works → "fas-Guru" (Persian transliterated into
    # Gurmukhī). An unclassified source quarantines loudly.
    #
    # == Fetch
    #
    # One sparse GitFetch of the monorepo: the cone is database/
    # collections/{sources,sections,line-groups,lines,authors,assets}/ +
    # the database README/LICENSE — the app/package code, the translation-
    # only collections and the schemas stay out.
    class Shabados < Nabu::Adapter
      SLUG = "shabados"
      REPO_URL = "https://github.com/shabados/shabados"
      COLLECTIONS = File.join("database", "collections")
      URN_PREFIX = "urn:nabu:#{SLUG}:".freeze

      SPARSE = %w[sources sections line-groups lines authors assets]
               .map { |dir| "/database/collections/#{dir}/" } + ["/database/README.md", "/database/LICENSE.md"]

      SOURCE_LANGUAGES = {
        "SGGS" => "pan", "VBGJ" => "pan", "ARDS" => "pan",
        "SDGR" => "bra-Guru", "KSBG" => "bra-Guru", "SRBL" => "bra-Guru",
        "GJNL" => "fas-Guru", "GZNL" => "fas-Guru", "JBNL" => "fas-Guru", "ZNNL" => "fas-Guru"
      }.freeze
      SECTION_LANGUAGES = { "VJB5" => "pan", "546R" => "fas-Guru", "1MZM" => "fas-Guru" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Shabad OS — Gurbāṇī and Panthic texts (Gurmukhī primary text)",
        license: "The database README: gurbani and panthic texts are identified as public domain " \
                 "(Public Domain Mark 1.0); the code is MIT. Only type = primary content (the " \
                 "scripture) is ingested — the modern translations and notes on the same records " \
                 "carry no grant and stay out",
        license_class: "open",
        upstream_url: REPO_URL,
        parser_family: "shabados-toml",
        credit: "Shabad OS Database (Shabad OS Organization and contributors; github.com/shabados) — " \
                "the sangat-proofread digital Gurbāṇī, after its printed sources (SGPC Shabadaarth, " \
                "Das Granthī, Bhāī Nand Lāl Granthāvalī …, named per document)."
      )

      def self.manifest = MANIFEST

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        root = File.join(workdir, COLLECTIONS)
        Dir.glob(File.join(root, "sources", "*.toml")).sort.each do |source_path| # rubocop:disable Lint/RedundantDirGlobSort -- the urn-order guarantee, stated
          source = File.basename(source_path, ".toml")
          read(source_path).fetch("sections", []).each_with_index do |section, index|
            yield Nabu::DocumentRef.new(
              source_id: SLUG, id: "#{URN_PREFIX}#{source}.#{section}",
              path: File.expand_path(File.join(root, "sections", "#{section}.toml")),
              metadata: { "source" => source, "section" => section, "section_order" => index + 1 }
            )
          end
        end
      end

      def discovery_skips(workdir)
        root = File.join(workdir, COLLECTIONS)
        listed = Dir.glob(File.join(root, "sources", "*.toml"))
                    .flat_map { |path| read(path).fetch("sections", []) }.to_set
        orphans = Dir.glob(File.join(root, "sections", "*.toml")).map { |path| File.basename(path, ".toml") }
                                                                 .reject { |id| listed.include?(id) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: 0, unrecognized: orphans.size,
          notes: orphans.sort.map { |id| "sections/#{id}.toml: listed by no source" }
        )
      end

      def parse(document_ref)
        root = File.dirname(document_ref.path, 2)
        source_id = document_ref.metadata.fetch("source")
        section_id = document_ref.metadata.fetch("section")
        language = language_for(source_id, section_id)
        source = read(File.join(root, "sources", "#{source_id}.toml"))
        section = read(document_ref.path)
        lookup = Lookup.new(root, self)

        passages = []
        authors = []
        assets = []
        section.fetch("lineGroups", []).each do |group_id|
          group = lookup.group(group_id)
          author = lookup.author(group["author"])
          authors << author if author
          group.fetch("lines", []).each do |line_id|
            primaries = lookup.primaries(line_id)
            assets.concat(primaries.flat_map { |entry| Array(entry["assets"]) })
            passages << passage(document_ref.id, line_id, primaries, language, passages.size,
                                group_id: group_id, author: author, sttm2: group.dig("externalReferences", "sttm2"))
          end
        end
        raise Nabu::ParseError, "#{SLUG}: #{source_id}.#{section_id}: no primary lines" if passages.empty?

        document = Nabu::Document.new(
          urn: document_ref.id, language: language, canonical_path: document_ref.path,
          title: [source.dig("name", "Latn"), section.dig("name", "Latn")].compact.join(" — "),
          metadata: document_metadata(document_ref, source, section, authors, assets, lookup)
        )
        passages.each { |unit| document << unit }
        document
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, sparse: SPARSE)
      end

      # Strict TOML-subset read (shabados-toml).
      def read(path)
        ShabadosToml.parse(File.read(path, encoding: "UTF-8"), path: path)
      rescue Errno::ENOENT
        raise Nabu::ParseError, "#{SLUG}: missing record #{path}"
      end

      # The sharded record paths: line-groups/<c>/<id>.toml,
      # lines/<c>/<cc>/<id>.toml.
      class Lookup
        def initialize(root, adapter)
          @root = root
          @adapter = adapter
          @authors = {}
          @assets = {}
        end

        def group(id) = @adapter.read(File.join(@root, "line-groups", id[0], "#{id}.toml"))

        def primaries(id)
          entries = @adapter.read(File.join(@root, "lines", id[0], id[0, 2], "#{id}.toml")).fetch("content", [])
          entries.select { |entry| entry["type"] == "primary" }.tap do |found|
            raise Nabu::ParseError, "#{SLUG}: line #{id} has no primary content" if found.empty?
          end
        end

        def author(id)
          return nil if id.nil?

          @authors.fetch(id) do
            path = File.join(@root, "authors", "#{id}.toml")
            @authors[id] = File.file?(path) ? @adapter.read(path).dig("name", "Latn") : id
          end
        end

        def asset(id)
          @assets.fetch(id) do
            path = File.join(@root, "assets", "#{id}.toml")
            @assets[id] = File.file?(path) ? @adapter.read(path).dig("name", "en") : nil
          end
        end
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url = REPO_URL

      def language_for(source_id, section_id)
        SECTION_LANGUAGES[section_id] || SOURCE_LANGUAGES.fetch(source_id) do
          raise Nabu::ParseError, "#{SLUG}: source #{source_id} has no language classification — classify it first"
        end
      end

      def passage(doc_urn, line_id, primaries, language, sequence, group_id:, author:, sttm2:)
        first, *others = primaries
        annotations = { "line_group" => group_id, "author" => author, "page" => first["page"],
                        "page_line" => first["line"], "sttm2" => sttm2, "assets" => first["assets"] }
        unless others.empty?
          annotations["variants"] = others.map do |entry|
            { "assets" => entry["assets"], "text" => Normalize.nfc(entry["data"].to_s),
              "page" => entry["page"], "page_line" => entry["line"] }.compact
          end
        end
        Nabu::Passage.new(urn: "#{doc_urn}:#{line_id}", language: language, text: Normalize.nfc(first["data"].to_s),
                          sequence: sequence, annotations: annotations.compact)
      end

      def document_metadata(ref, source, section, authors, assets, lookup)
        {
          "source" => ref.metadata["source"], "section" => ref.metadata["section"],
          "section_order" => ref.metadata["section_order"],
          "source_name" => source.dig("name", "Latn"), "source_name_guru" => source.dig("name", "Guru"),
          "source_translation" => source.dig("translation", "en"),
          "section_name" => section.dig("name", "Latn"), "section_name_guru" => section.dig("name", "Guru"),
          "section_description" => section.dig("description", "en"),
          "authors" => authors.uniq,
          "primary_sources" => assets.uniq.to_h { |id| [id, lookup.asset(id)] }.compact
        }.reject { |_, value| value.nil? || value == [] || value == {} }
      end
    end
  end
end
