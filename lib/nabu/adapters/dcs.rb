# frozen_string_literal: true

require "nokogiri"

require_relative "conllu_parser"

module Nabu
  module Adapters
    # The Digital Corpus of Sanskrit (P26-0): Oliver Hellwig's DCS CoNLL-U
    # dump — 15,900 chapter files / 270 texts / ~844 MB, ~5.46M analyzed
    # words, IAST — living at `dcs/data/conllu/` INSIDE the research repo
    # github.com/OliverHellwig/sanskrit (there is NO separate "dcs-data"
    # repo, and the format is standard CoNLL-U since the Aug 2022 release —
    # docs/02-sources.md row 7 corrected under this packet). The
    # analysis-side complement to GRETIL's breadth: every word carries a
    # verified lemma, so DCS is the FIRST gold Sanskrit occupant of the
    # lemma index — kaṇṭha/śīghrá/aṃśa fold-join MW's entries and starling
    # piet's IND stems with no new fold rules (scout-verified 7/7).
    #
    # == The gold gate (machine-declared, never prose)
    #
    # `lookup/chapter-info.xml` declares, per chapter,
    # `<layer type="gold">lexicon</layer>` + `<layer type="gold">
    # morpho-syntax</layer>` (all 15,900 at fixture time; 1,780 add gold
    # `syntax` — the Vedic Treebank subset, the only chapters whose
    # HEAD/DEPREL columns are filled). The readme's prose ("The analysis of
    # each string has been verified by one annotator") is corroboration;
    # the ADAPTER'S GOLD CLAIM GATES ON THE DECLARATION: a chapter file
    # absent from chapter-info.xml, or present without the gold lexicon
    # layer, quarantines (ParseError) — never a silent skip, never a
    # silently ingested automatic analysis. The `.conllu_parsed` SIBLINGS
    # (7,227 upstream) are the automatic layers and are never discovered at
    # all (the `*.conllu` glob cannot match them; pinned in tests).
    #
    # == Identity (FROZEN minting)
    #
    # One document per chapter FILE — the corpus's own unit (`each chapter
    # … is in a separate file`); one passage per sentence block. urns ride
    # upstream's own permanent numeric ids from chapter-info.xml:
    #
    #   document urn  urn:nabu:dcs:<textId>:<chapterId>     (urn:nabu:dcs:5:3656)
    #   passage urn   <document-urn>:<sent_id>              (…:3656:10902)
    #
    # (filenames — "Suśrutasaṃhitā-0115-Su, Ka., 4-3656.conllu" — carry
    # spaces, commas and diacritics; names live in titles/metadata, ids in
    # urns). sent_ids are upstream-verbatim and vary in shape per chapter
    # ("556276_1" vs "10902") — both honest. Language: san (IAST), the
    # GRETIL/UD-sanskrit-vedic tag.
    #
    # == Dedup pin — UD sanskrit-vedic (NO dedup wanted)
    #
    # The UD_Sanskrit-Vedic treebank is the same Hellwig material at a
    # different grain (UD conversion, train/dev/test splits) — two honest
    # witnesses, the MW-beside-kaikki precedent. The UD dedup guard exists
    # for RE-EXPORTS of already-synced sources (chu-PROIEL/orv-TOROT),
    # which this is not. Pinned in the adapter test + backlog P26-0.
    #
    # == License
    #
    # CC BY 4.0, VERBATIM in both data readmes fetched with the corpus:
    # `dcs/data/conllu/readme.md` — "The data in this directory are
    # licensed under the Creative Commons BY 4.0 (CC BY 4.0) license." —
    # and `dcs/data/readme.md` — "The data of the DCS and any data in
    # child directories are licensed under the Creative Common BY 4.0
    # (CC BY 4.0) license." → license_class attribution. Citation
    # requested: Oliver Hellwig, The Digital Corpus of Sanskrit (DCS),
    # 2010–2024.
    #
    # == fetch / sync policy (the 844 MB question)
    #
    # The repo is ~1.7 GB of which only dcs/data/conllu is corpus; fetch is
    # the SPARSE GitFetch recipe (P26-0: blobless no-checkout clone +
    # sparse-checkout cone) scoped to the conllu tree + the parent readme,
    # so the owner's first sync transfers the ~844 MB cone (well under the
    # repo's full weight; git compresses CoNLL-U text heavily on the wire).
    # Upstream releases are occasional (the dump regenerates from the DCS
    # database) → sync_policy manual, enabled: false until the owner-fired
    # first real sync.
    class Dcs < Nabu::Adapter
      REPO_URL = "https://github.com/OliverHellwig/sanskrit"

      # The sparse cone: the corpus tree + the parent readme that carries
      # the second license grant.
      SPARSE_PATHS = ["dcs/data/conllu", "dcs/data/readme.md"].freeze

      DATA_DIR = File.join("dcs", "data", "conllu").freeze

      LANGUAGE = "san"

      MANIFEST = Nabu::SourceManifest.new(
        id: "dcs",
        name: "Digital Corpus of Sanskrit (DCS) — gold lemmatized CoNLL-U",
        license: "CC BY 4.0 (verbatim, dcs/data/conllu/readme.md: \"The data in this directory " \
                 "are licensed under the Creative Commons BY 4.0 (CC BY 4.0) license.\"; " \
                 "citation requested: Oliver Hellwig, The Digital Corpus of Sanskrit, 2010-2024)",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "conllu"
      )

      URN_PREFIX = "urn:nabu:dcs:"

      def self.manifest
        MANIFEST
      end

      # One chapter's machine-readable declaration from chapter-info.xml.
      # +gold_layers+ is THE gate's input; the whole declaration rides into
      # the document metadata (deep-extraction: the Vedic Treebank's gold
      # syntax layer stays visible).
      Chapter = Data.define(:path, :text_name, :text_id, :chapter_name, :chapter_id,
                            :position, :time_slot, :details, :gold_layers) do
        def urn = "#{URN_PREFIX}#{text_id}:#{chapter_id}"
      end

      # One DocumentRef per `files/<Text>/*.conllu` chapter file, sorted by
      # urn. `.conllu_parsed` siblings never match the glob (pinned in
      # tests). A chapter absent from chapter-info.xml still yields a ref
      # (id urn:nabu:dcs:undeclared:<file chapter id>) so its quarantine at
      # parse is VISIBLE — never a silent drop. A pre-fetch workdir yields
      # nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The gold gate, then the shared ConlluParser over the chapter file.
      def parse(document_ref)
        info = document_ref.metadata["chapter_info"]
        gate_gold!(document_ref, info)
        ConlluParser.new.parse(
          document_ref.path,
          urn: document_ref.id, language: LANGUAGE,
          title: "#{info.fetch('text')} — #{info.fetch('chapter')}",
          metadata: document_metadata(info)
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Sparse GitFetch (class note): only the conllu cone + parent readme
      # materialize; the attic/breaker choreography is the shared one.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end

      def document_refs(workdir)
        chapters = chapter_info(workdir)
        Dir.glob(File.join(workdir, DATA_DIR, "files", "*", "*.conllu")).map do |path|
          rel = relative_chapter_path(workdir, path)
          chapter = chapters[rel]
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: chapter ? chapter.urn : undeclared_urn(path),
            path: File.expand_path(path),
            metadata: chapter ? { "chapter_info" => chapter_payload(chapter) } : {}
          )
        end.sort_by(&:id)
      end

      # The declaration as JSON-safe discover→parse metadata (DocumentRef
      # carries JSON data only).
      def chapter_payload(chapter)
        {
          "text" => chapter.text_name, "text_id" => chapter.text_id,
          "chapter" => chapter.chapter_name, "chapter_id" => chapter.chapter_id,
          "chapter_position" => chapter.position, "dcs_time_slot" => chapter.time_slot,
          "details" => chapter.details, "gold_layers" => chapter.gold_layers
        }.compact
      end

      # chapter-info.xml keys chapters by "<Text>/<file>.conllu" relative
      # to files/.
      def relative_chapter_path(workdir, path)
        base = File.expand_path(File.join(workdir, DATA_DIR, "files"))
        File.expand_path(path).delete_prefix("#{base}#{File::SEPARATOR}")
      end

      # A file chapter-info does not declare cannot mint the id urn; its
      # filename tail ("…-3656.conllu") still names it stably enough for
      # the quarantine to be readable.
      def undeclared_urn(path)
        tail = File.basename(path, ".conllu")[/-(\d+)\z/, 1] || "unknown"
        "#{URN_PREFIX}undeclared:#{tail}"
      end

      def gate_gold!(document_ref, info)
        if info.nil?
          raise ParseError,
                "#{document_ref.path}: not declared in lookup/chapter-info.xml — the corpus's " \
                "machine-readable gold declaration is the gate; an undeclared chapter carries " \
                "no verified-gold claim and is never ingested"
        end
        return if info.fetch("gold_layers", []).include?("lexicon")

        raise ParseError,
              "#{document_ref.path}: chapter-info.xml declares no <layer type=\"gold\">lexicon" \
              "</layer> for this chapter (gold layers: #{info.fetch('gold_layers', []).inspect}) " \
              "— the machine-readable gold gate refuses automatic lexicon layers"
      end

      def document_metadata(info)
        metadata = info.except("details").compact
        details = info.fetch("details", {})
        metadata["details"] = details unless details.empty?
        facets = chapter_facets(details)
        metadata["facets"] = facets unless facets.empty?
        metadata
      end

      # The faceted layers (deep-extraction): the Vedic details block's
      # register/veda ride as document facets where present.
      def chapter_facets(details)
        %w[register veda].each_with_object({}) do |key, out|
          value = details[key] or next
          out[key] = { "value" => value.downcase, "raw" => value }
        end
      end

      # { "Text/file.conllu" => Chapter } from lookup/chapter-info.xml —
      # 8.9 MB upstream, so streamed with XML::Reader (the house >5 MB
      # rule); each <chapter> element is tiny and parsed as a fragment.
      # Missing file = empty map: every chapter then quarantines loudly at
      # parse (a fetched tree without its lookup dir is damage, not a rule).
      def chapter_info(workdir)
        path = File.join(workdir, DATA_DIR, "lookup", "chapter-info.xml")
        return {} unless File.file?(path)

        chapters = {}
        File.open(path, "r:UTF-8") do |io|
          Nokogiri::XML::Reader(io).each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.name == "chapter"

            chapter = build_chapter(Nokogiri::XML(node.outer_xml).root)
            chapters[chapter.path] = chapter
          end
        end
        chapters
      end

      def build_chapter(node)
        Chapter.new(
          path: text_at(node, "path"), text_name: text_at(node, "textName"),
          text_id: text_at(node, "textId"), chapter_name: text_at(node, "chapterName"),
          chapter_id: text_at(node, "chapterId"), position: text_at(node, "chapterPosition"),
          time_slot: text_at(node, "dcsTimeSlot"),
          details: node.xpath("details/*").to_h { |child| [child.name, child.text] },
          gold_layers: node.xpath("annotation/layer[@type='gold']").map(&:text)
        )
      end

      def text_at(node, name)
        node.at_xpath(name)&.text
      end
    end
  end
end
