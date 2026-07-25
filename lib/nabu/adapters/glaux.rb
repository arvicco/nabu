# frozen_string_literal: true

require_relative "glaux_parser"

module Nabu
  module Adapters
    # GLAUx — "the Greek Language Automated" (P44-1): Alek Keersmaekers'
    # ~20M-token corpus of Ancient Greek (8th c. BC – ~4th c. AD),
    # automatically annotated for morphology, syntax, lemmas, animacy and word
    # senses, roughly following the Ancient Greek Dependency Treebank (AGDT)
    # guidelines. The analysis-side complement to the held Perseus/First1K
    # editions (the DCS-beside-GRETIL pattern): every word carries a lemma and
    # a 9-place postag, so `search --lemma --lang grc` and vocab gain
    # corpus-scale Greek coverage beyond the hand-treebanked canon. A thin
    # composition of the `glaux` parser family; the adapter owns identity, the
    # per-text license census, and the sparse fetch.
    #
    # == Identity
    #
    # The repo ships one file per work at xml/<tlg-author>-<work>.xml
    # (0003-002.xml …); the filename stem IS the corpus's own text id (the
    # sentences' document_id attribute), so:
    #
    #   document urn  urn:nabu:glaux:<stem>            (urn:nabu:glaux:0003-002)
    #   passage urn   <document-urn>:<struct_id>       (…:0003-002:27421)
    #
    # struct_id is GLAUx's global sentence key (PROIEL-style stable db-key),
    # minted by the parser. ref.id == parse(ref).urn (the conformance identity
    # the sync breaker relies on).
    #
    # == THE SILVER TIER (analysis="auto")
    #
    # Most of GLAUx is AUTOMATICALLY annotated (every sentence carries
    # analysis="auto"; the README's accuracy table — morphology 97.2%, lemmas
    # 98.8%, syntax ~80% — is machine output). So sources.yml registers
    # `lemma_tier: silver`: every lemma count this corpus feeds renders
    # LABELED, never gold attestation (the CDLI/TLHdig/diorisis precedent). The
    # conservative source-wide floor never over-claims: the hand-treebanked
    # subset (analysis rides each passage) is left silver here, a future packet
    # may promote it. The manually-annotated sentences are ALSO the ones whose
    # annotation license is NC (see below) — silver + nc travel together.
    #
    # == LICENSE — the D44-a census (metadata.txt, all 1,421 rows, 2026-07-24)
    #
    # SOURCE_LICENSE column: CC BY-SA 4.0 ×999, CC-BY-SA 3.0 ×227, NA ×174,
    # CC BY 4.0 ×10, then a long tail of singletons (CC BY-SA 2.5/2.0, GPL,
    # OpenEdition) and 7 NC/ND source texts. DOMINANT = share-alike →
    # registry class `attribution` (the Perseus/Diorisis/First1K class).
    #
    # The restrictive slice is bigger than the source-license column alone
    # shows, because GLAUx's VALUE is the ANNOTATION and some manual
    # annotations are NC even over a BY-SA source text: the TREEBANK_ANNOTATIONS
    # column names PROIEL (CC BY-NC-SA 3.0, ×25) and the Gorman trees
    # (CC BY-NC-SA 4.0, ×40). So the texts needing `nc` = {7 NC source-license}
    # ∪ {25 PROIEL-annotated} ∪ {40 Gorman-annotated} = 72 of 1,421 (5.1%, no
    # overlap). Each such text carries a per-document `license_override: nc`
    # (the P43-1 UD idiom) so query/export filters NEVER over-share; the
    # BY-SA/BY/NA majority inherits the source's `attribution` class. 5.1% is a
    # minority (D44-a needs no owner ruling), but honest labelling is cheap.
    #
    # == fetch / sync policy
    #
    # Sparse GitFetch (the DCS recipe): a blobless no-checkout clone with a
    # sparse-checkout cone scoped to xml/ + metadata.txt + README.md, so the
    # owner's first sync transfers the annotation tree without the repo's build
    # cruft. The xml tree is large (files 6 KB – 31 MB, ~20M tokens); expect a
    # multi-hundred-MB working tree. Upstream releases occasionally →
    # sync_policy manual, enabled: false until the owner-fired first real sync.
    class Glaux < Nabu::Adapter
      REPO_URL = "https://github.com/alekkeersmaekers/glaux"

      # The sparse cone: the annotation tree + the per-text metadata (license
      # census, titles) + the README (verbatim license + citation).
      SPARSE_PATHS = ["xml", "metadata.txt", "README.md"].freeze

      XML_DIR = "xml"
      METADATA_FILE = "metadata.txt"
      LANGUAGE = "grc"
      URN_PREFIX = "urn:nabu:glaux:"

      # metadata.txt columns (0-based, tab-separated; header verified 2026-07-24).
      COL_TEXT_ID = 1        # TLG — the document id, == the xml filename stem
      COL_AUTHOR = 4         # AUTHOR_STANDARD
      COL_TITLE = 5          # TITLE_STANDARD
      COL_GENRE = 6          # GENRE_STANDARD
      COL_DIALECT = 7        # DIALECT
      COL_START = 2          # STARTDATE
      COL_END = 3            # ENDDATE
      COL_SOURCE = 8         # SOURCE
      COL_LICENSE = 9        # SOURCE_LICENSE
      COL_ANNOTATION = 13    # TREEBANK_ANNOTATIONS
      private_constant :COL_TEXT_ID, :COL_AUTHOR, :COL_TITLE, :COL_GENRE, :COL_DIALECT,
                       :COL_START, :COL_END, :COL_SOURCE, :COL_LICENSE, :COL_ANNOTATION

      # The NC-licensed manual-annotation projects (README, verbatim licenses):
      # PROIEL (CC BY-NC-SA 3.0) and Vanessa Gorman's trees (CC BY-NC-SA 4.0).
      # A text carrying either as its manual annotation needs `nc` even when its
      # source text is BY-SA. Matched by substring (upstream spells Gorman's as
      # "Vanessa Gorman's Ancient Greek Prose Dependency Treebanks").
      NC_ANNOTATION_PATTERNS = [/PROIEL/i, /Gorman/i].freeze
      private_constant :NC_ANNOTATION_PATTERNS

      MANIFEST = Nabu::SourceManifest.new(
        id: "glaux",
        name: "GLAUx — the Greek Language Automated (Keersmaekers)",
        license: "CC BY-SA (README, verbatim: \"Most of the data is available under a " \
                 "CC BY-SA license but some texts are more restrictive (e.g. CC BY-NC): the " \
                 "license of each source text is also specified in the metadata file.\") — " \
                 "class attribution; per-text license_override nc for the 72/1,421 texts " \
                 "(5.1%) whose source text OR manual annotation (PROIEL, Gorman) is NC. " \
                 "Cite Keersmaekers 2021, doi:10.18653/v1/2021.lchange-1.6",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "glaux"
      )

      def self.manifest
        MANIFEST
      end

      # The per-text license class the census assigns: `nc` when the source
      # license is NonCommercial OR the manual annotation is from an NC project
      # (PROIEL / Gorman); nil otherwise (inherit the source's attribution
      # class). Pure function — the census logic, unit-testable without a
      # workdir.
      def self.license_class_for(source_license:, annotation:)
        return "nc" if source_license.to_s.match?(/NC/i)
        return "nc" if NC_ANNOTATION_PATTERNS.any? { |re| annotation.to_s.match?(re) }

        nil
      end

      # One DocumentRef per xml/<stem>.xml, sorted by urn; the metadata row
      # (title, per-text license class, document metadata) rides the ref to
      # parse. A pre-fetch workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Delegate to the GlauxParser with identity, language (grc), the resolved
      # title and the per-document license override from the census.
      def parse(document_ref)
        metadata = document_ref.metadata
        GlauxParser.new.parse(
          document_ref.path,
          urn: document_ref.id, language: LANGUAGE,
          title: metadata["title"],
          metadata: document_metadata(metadata),
          license_override: metadata["license_class"]
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Sparse GitFetch (class note): only the xml cone + metadata + README
      # materialize; the attic/breaker choreography is the shared one.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      # { text_id => license_class_or_nil } over every metadata.txt row — the
      # census, exposed for the override integration test.
      def license_index(workdir)
        metadata_rows(workdir).transform_values do |row|
          self.class.license_class_for(source_license: row[COL_LICENSE], annotation: row[COL_ANNOTATION])
        end
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end

      def document_refs(workdir)
        rows = metadata_rows(workdir)
        Dir.glob(File.join(workdir, XML_DIR, "*.xml")).map do |path|
          stem = File.basename(path, ".xml")
          row = rows[stem]
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{stem}",
            path: File.expand_path(path),
            metadata: ref_metadata(stem, row)
          )
        end.sort_by(&:id)
      end

      # The discover→parse hint: title, the per-document license class (only
      # when the census tightens to nc — absent = inherit attribution, the UD
      # P10-4 idiom), and the raw metadata columns the document carries.
      def ref_metadata(stem, row)
        metadata = { "title" => title_for(stem, row) }
        if row
          klass = self.class.license_class_for(source_license: row[COL_LICENSE],
                                               annotation: row[COL_ANNOTATION])
          metadata["license_class"] = klass if klass
          metadata["row"] = row
        end
        metadata
      end

      def title_for(stem, row)
        return stem unless row

        [presence(row[COL_AUTHOR]), presence(row[COL_TITLE])].compact.join(" — ").then do |t|
          t.empty? ? stem : t
        end
      end

      # The document-level metadata journaled from the metadata.txt row (the
      # SOURCE_LICENSE rides verbatim — the per-text license record).
      def document_metadata(ref_metadata)
        row = ref_metadata["row"] or return {}
        {
          "author" => presence(row[COL_AUTHOR]),
          "work" => presence(row[COL_TITLE]),
          "genre" => na_or(row[COL_GENRE]),
          "dialect" => na_or(row[COL_DIALECT]),
          "start_date" => presence(row[COL_START]),
          "end_date" => presence(row[COL_END]),
          "source" => presence(row[COL_SOURCE]),
          "source_license" => na_or(row[COL_LICENSE]),
          "treebank_annotations" => na_or(row[COL_ANNOTATION])
        }.compact
      end

      # { text_id => [columns] } from metadata.txt (tab-separated, header
      # skipped). A workdir without the file yields an empty map — every
      # discovered doc then inherits the source class and a stem title
      # (defensive: a fetched tree missing metadata.txt is degraded, not a
      # hard error, and the license floor stays attribution).
      def metadata_rows(workdir)
        path = File.join(workdir, METADATA_FILE)
        return {} unless File.file?(path)

        rows = {}
        File.foreach(path, encoding: "UTF-8").with_index do |line, index|
          next if index.zero? # header

          columns = line.chomp.split("\t", -1)
          text_id = columns[COL_TEXT_ID]
          rows[text_id] = columns if text_id && !text_id.empty?
        end
        rows
      end

      def presence(value)
        value if value && !value.empty?
      end

      # metadata.txt spells "unknown" as the literal "NA" — surface nil, not the
      # sentinel string, so document metadata never carries a fake value.
      def na_or(value)
        v = presence(value)
        v == "NA" ? nil : v
      end
    end
  end
end
