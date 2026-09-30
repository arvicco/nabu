# frozen_string_literal: true

module Nabu
  module Adapters
    # The SBLGNT adapter (P11-5): the SBL Greek New Testament (Faithlife/
    # SBLGNT — LogosBible/SBLGNT redirects there), a critical edition of the
    # Greek NT under a clean CC BY 4.0. The Greek witness the alignment hub's
    # nt work gains beside PROIEL's greek-nt treebank (same verses, different
    # edition — distinct documents, never a dedupe).
    #
    # == Layout and identity (FROZEN minting)
    #
    # The repo ships 27 per-book plain-text files under data/sblgnt/text/
    # (verse-per-line TSV — the SblgntParser family; the word-level XML
    # variant is deliberately not ingested; the sblgntapp apparatus joins
    # as per-verse "apparatus" annotations since P110-4).
    # One file = one document: urn = urn:nabu:sblgnt:<file-stem-downcased>
    # (Mark.txt → urn:nabu:sblgnt:mark, 1Cor.txt → urn:nabu:sblgnt:1cor),
    # title = the file's first-line Greek title (ΚΑΤΑ ΜΑΡΚΟΝ), passage urns
    # <doc-urn>:<chapter>.<verse>. Minting is frozen once used.
    #
    # == License
    #
    # CC BY 4.0 → license_class "attribution". Verbatim (repo README): "The
    # SBLGNT is licensed under a Creative Commons Attribution 4.0
    # International License. Copyright 2010 by the Society of Biblical
    # Literature and Logos Bible Software." The historically restrictive
    # SBLGNT EULA is superseded — sblgnt.com/license itself serves CC BY 4.0.
    # NB morphgnt/sblgnt's morphology layer is CC-BY-SA-3.0 copyleft and is
    # deliberately NOT used. See test/fixtures/sblgnt/README.md.
    #
    # == fetch
    #
    # The shared git path (Adapter#git_fetch! → GitFetch: attic + pre-merge
    # mass-deletion breaker); the whole repo is ~2.3 MB.
    class Sblgnt < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "sblgnt",
        name: "SBL Greek New Testament (SBLGNT)",
        license: "CC BY 4.0",
        license_class: "attribution",
        upstream_url: "https://github.com/Faithlife/SBLGNT",
        parser_family: "sblgnt-tsv"
      )

      TEXT_DIR = File.join("data", "sblgnt", "text")
      APPARATUS_DIR = File.join("data", "sblgntapp", "xml")

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per book file under data/sblgnt/text/, sorted by urn.
      # Returns an Enumerator without a block (the adapter contract's lazy
      # shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        SblgntParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: "grc",
          title: document_ref.metadata["title"],
          apparatus: apparatus_notes(document_ref.path)
        )
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Split out so fetch tests can point a singleton at a local git tmpdir
      # (the house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end

      # P110-4 (the sidecar harvest): the repo's own critical apparatus —
      # per-book flat XML beside the text tree, <verse>Book C:V</verse>
      # followed by its <note> lines (variant readings with witness sigla,
      # kept verbatim). Keyed "C.V" to match passage urns; the verse ref's
      # book prefix varies ("3 John" vs the 3John file stem), so only the
      # trailing C:V is read. A book without an apparatus file (or an
      # unfetched tree) contributes an empty map — the pre-P110 parse.
      def apparatus_notes(text_path)
        path = text_path.sub("#{File::SEPARATOR}#{TEXT_DIR}#{File::SEPARATOR}",
                             "#{File::SEPARATOR}#{APPARATUS_DIR}#{File::SEPARATOR}")
                        .sub(/\.txt\z/, ".xml")
        return {} unless path != text_path && File.file?(path)

        notes = Hash.new { |h, k| h[k] = [] }
        verse = nil
        File.readlines(path, encoding: "UTF-8").each do |line|
          if (ref = line[%r{<verse>[^<]*?(\d+:\d+)\s*</verse>}, 1])
            verse = ref.tr(":", ".")
          elsif (note = line[%r{<note>(.*?)</note>}, 1])
            notes[verse] << Normalize.nfc(note.strip) if verse
          end
        end
        notes
      end

      def document_refs(workdir)
        parser = SblgntParser.new
        Dir.glob(File.join(workdir, TEXT_DIR, "*.txt")).map do |path|
          stem = File.basename(path, ".txt")
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:sblgnt:#{stem.downcase}",
            path: File.expand_path(path),
            metadata: { "title" => parser.title(path) || stem, "language" => "grc" }
          )
        end.sort_by(&:id)
      end
    end
  end
end
