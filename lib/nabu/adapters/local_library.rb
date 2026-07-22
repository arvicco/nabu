# frozen_string_literal: true

require_relative "../library_manifest"
require_relative "../local_fetch"
require_relative "../pdf_text"

module Nabu
  module Adapters
    # The local-library shelf (P19-4, architecture §16; design:
    # canonical-memory §2) — the SECOND local shelf: PDFs, scans and
    # articles the owner acquires, under
    # canonical/local-library/<collection>/ with one manifest.yml per
    # collection as the source of record. An ordinary source in every
    # pipeline sense (registry entry, discovery census, quarantine, attic,
    # rebuild) with `kind: shelf`: no upstream, no network; #fetch is
    # LocalFetch (re-scan + per-file sha pins). Unlike the dossier shelf
    # this one mints DOCUMENTS + PASSAGES, so the full adapter conformance
    # suite applies.
    #
    # == content_kind verdict (:passages, deliberately NOT a new :article)
    #
    # The design sketch said "content_kind :article", but in this codebase
    # content_kind is the LOADER ROUTING enum (:passages → Store::Loader,
    # :dictionary, :language — "a closed set; a new kind means a new
    # loader"). Articles parse into Nabu::Document + Nabu::Passage — exactly
    # the :passages content SHAPE, handled by Store::Loader unchanged — so a
    # fourth enum value would be a routing word without a loader behind it
    # (and would silently skip the document-grain withdrawal trend rule in
    # SyncRunner). Article-ness is a fact about the DOCUMENT, not the
    # pipeline: it rides in Document#metadata ("kind" => "article").
    #
    # == Identity (FROZEN minting)
    #
    # urn = urn:nabu:local-library:<collection>:<slug>, slug derived from
    # the manifest entry's file stem (lowercased, non-alphanumeric runs →
    # "-"). The FILE NAME is the stable id: renaming a file is honestly a
    # new document (the manifest is the record; `nabu ingest` will keep
    # names stable). Passage urns: page grain `…:p12` for PDFs (see
    # Nabu::PdfText — the page is the only citation unit a PDF keeps stable
    # and the one scholarship cites), paragraph ordinals `…:3` for
    # born-digital text files (blank-line paragraphs are authorial there,
    # not extraction artifacts).
    #
    # == Honest failure ladder
    #
    # - PDF with a text layer → page-grain passages (mutool via
    #   Nabu::Shell).
    # - PDF that reads clean but has NO text (a scan) → metadata-only
    #   document, metadata "text_layer" => "none" — catalogued and queued
    #   for the HTR era (improvements §3.4), NEVER quarantined for being a
    #   scan.
    # - Images (png/jpg/tiff/djvu/…) → metadata-only, same marking.
    # - Genuinely unreadable file (mutool nonzero, invalid UTF-8 text) →
    #   ParseError, quarantined.
    # - Manifested but missing on disk → no ref (census note); the ledger
    #   pin lingers and health shouts (the P19-1 vanished story). Atticked
    #   copy → rediscovered retained, document retired, passages persist.
    # - On disk but unmanifested → unrecognized in the census (awaiting
    #   `nabu ingest`).
    #
    # == License doctrine
    #
    # Shelf class research_private (MCP default-excluded, never
    # redistributed) — acquired scholarly PDFs are mostly copyrighted, so
    # silence means the conservative class (LibraryManifest applies the
    # default). An entry claiming a more open class is honored as a
    # per-document license_override (the P10-4 column) — an owner decision,
    # explicit in the manifest.
    class LocalLibrary < Adapter
      SLUG = "local-library"
      URN_PREFIX = "urn:nabu:#{SLUG}".freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Local library (PDFs, scans, articles — local shelf)",
        license: "Per-item via collection manifest.yml; shelf default research_private",
        license_class: "research_private",
        upstream_url: "canonical/local-library (local — no upstream)",
        parser_family: "library-manifest"
      )

      # Extensions catalogued metadata-only until the HTR/cluster era
      # (improvements §3.4) — plus anything else we cannot extract yet.
      IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .tif .tiff .gif .webp .bmp .djvu].freeze
      TEXT_EXTENSIONS = %w[.txt .md].freeze

      def self.manifest = MANIFEST

      # No upstream to probe: kind: shelf short-circuits the remote
      # probe to the "local" verdict (P19-1/P39-0 machinery).
      def self.upstream_repo_urls = []

      # The manifests' related: urns feed kind=reference edges into the
      # links journal after every load (SyncRunner → Nabu::LibraryReferences).
      def self.reference_edges? = true

      # +pdf_text+ is the extraction seam (a callable path → [page texts]),
      # defaulting to the real mutool boundary; tests inject a fake so the
      # suite never depends on mutool being installed.
      def initialize(pdf_text: PdfText.method(:pages))
        super()
        @pdf_text = pdf_text
      end

      # Re-scan the tree (LocalFetch): sha-pins every file (manifests and
      # unmanifested strays included — integrity covers what cataloguing
      # hasn't reached yet), reports un-atticked disappearances loudly, and
      # trips the house mass-deletion breaker (--force overrides).
      def fetch(workdir, progress: nil, force: false)
        progress&.call("Scanning #{workdir}…\n")
        result = LocalFetch.sync!(
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), force: force,
          hint: "for local-library: create #{SLUG}/<collection>/ with files + a manifest.yml"
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: fetch_notes(result), repos: pin_map(result))
      rescue LocalFetch::Error => e
        raise FetchError, "#{manifest.id}: #{e.message}"
      end

      # One ref per manifest entry whose file is on disk (live, or retired
      # into the attic — those yield retained refs), in manifest order
      # within each sorted collection (the manifest is the review surface;
      # its order is stable and meaningful). The entry itself rides in
      # ref.metadata so parse never re-reads the manifest.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        walk_collections(workdir) do |collection, manifest|
          seen = Set.new
          manifest.entries.each do |entry|
            ref = entry_ref(workdir, collection, entry)
            next if ref.nil? || !seen.add?(ref.id)

            yield ref
          end
        end
        self
      end

      # The census (P11-7): everything the manifests cannot account for is
      # LOUD — unmanifested files, manifested-but-missing files, uncataloged
      # collections, malformed manifests, stray root files. Nothing on this
      # shelf skips by rule: the manifest is the record, so every gap is a
      # cataloguing defect (or an ingest waiting to happen), never a norm.
      def discovery_skips(workdir)
        notes = collection_notes(workdir) + root_notes(workdir)
        DiscoverySkips.new(unrecognized: notes.size, notes: notes)
      end

      # Parse one manifest entry into a Document (+ passages when text is
      # extractable). Damage — unreadable PDF, invalid UTF-8, vanished file
      # — quarantines the ENTRY; a scan is not damage (class comment).
      def parse(document_ref)
        meta = document_ref.metadata
        document = build_document(document_ref, meta)
        append_passages(document, document_ref, meta)
        document
      rescue PdfText::Error, Errno::ENOENT, Errno::EACCES => e
        raise ParseError, "#{document_ref.id}: #{e.message}"
      rescue Nabu::Normalize::EncodingError => e
        raise ParseError, "#{document_ref.id}: undecodable text (#{e.message})"
      end

      # slug for one manifest file name: the stem, lowercased, squeezed to
      # [a-z0-9-] runs. Stable by construction (pure function of the name).
      def self.slug_for(file)
        stem = File.basename(file, ".*")
        slug = stem.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
        slug.empty? ? stem.downcase : slug
      end

      def self.urn_for(collection, file)
        "#{URN_PREFIX}:#{collection}:#{slug_for(file)}"
      end

      private

      # -- discovery ----------------------------------------------------------

      # Collection subdirs (sorted) that carry a parseable manifest; the
      # census reports the rest.
      def walk_collections(workdir)
        collection_dirs(workdir).each do |collection|
          manifest = load_manifest(workdir, collection)
          yield collection, manifest unless manifest.nil?
        end
      end

      def collection_dirs(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.children(workdir).sort.select do |name|
          File.directory?(File.join(workdir, name)) && name != ATTIC_DIRNAME
        end
      end

      def load_manifest(workdir, collection)
        path = File.join(workdir, collection, LibraryManifest::FILENAME)
        return nil unless File.file?(path)

        LibraryManifest.load(path)
      rescue LibraryManifest::FormatError
        nil
      end

      # The ref for one entry: the live file, else its attic copy (retained
      # — the loader loads it retired), else nil (vanished — census + pins
      # carry the story; a full load withdraws the document honestly).
      def entry_ref(workdir, collection, entry)
        live = File.join(workdir, collection, entry.file)
        attic = File.join(workdir, ATTIC_DIRNAME, collection, entry.file)
        metadata = entry_metadata(collection, entry)
        if File.file?(live)
          path = live
        elsif File.file?(attic)
          path = attic
          metadata[RETAINED_KEY] = true
        else
          return nil
        end
        Nabu::DocumentRef.new(source_id: manifest.id, id: self.class.urn_for(collection, entry.file),
                              path: File.expand_path(path), metadata: metadata)
      end

      # The manifest entry as JSON-clean ref metadata (empty lanes omitted).
      def entry_metadata(collection, entry)
        metadata = { "collection" => collection, "file" => entry.file, "title" => entry.title,
                     "license_class" => entry.license_class }
        metadata["creator"] = entry.creator if entry.creator
        metadata["year"] = entry.year if entry.year
        metadata["provenance"] = entry.provenance if entry.provenance
        metadata["source_url"] = entry.source_url if entry.source_url
        %w[languages tags related].each do |key|
          values = entry.public_send(key)
          metadata[key] = values unless values.empty?
        end
        metadata
      end

      # -- census ---------------------------------------------------------------

      def collection_notes(workdir)
        collection_dirs(workdir).flat_map do |collection|
          path = File.join(workdir, collection, LibraryManifest::FILENAME)
          next ["#{collection}/: no #{LibraryManifest::FILENAME} — uncataloged collection"] unless File.file?(path)

          begin
            manifest = LibraryManifest.load(path)
          rescue LibraryManifest::FormatError => e
            next ["#{collection}/#{LibraryManifest::FILENAME}: #{e.message}"]
          end
          missing_notes(workdir, collection, manifest) + unmanifested_notes(workdir, collection, manifest)
        end
      end

      def missing_notes(workdir, collection, manifest)
        manifest.entries.filter_map do |entry|
          next if File.file?(File.join(workdir, collection, entry.file))
          next if File.file?(File.join(workdir, ATTIC_DIRNAME, collection, entry.file))

          "#{collection}/#{entry.file}: manifested but MISSING (not in .attic) — " \
            "restore from backup, or move to .attic/ to retire"
        end
      end

      def unmanifested_notes(workdir, collection, manifest)
        catalogued = manifest.entries.to_set(&:file)
        dir = File.join(workdir, collection)
        Dir.glob("**/*", base: dir)
           .select { |rel| File.file?(File.join(dir, rel)) }
           .reject { |rel| rel == LibraryManifest::FILENAME || catalogued.include?(rel) }
           .sort
           .map { |rel| "#{collection}/#{rel}: unmanifested — catalog it (nabu ingest) or remove" }
      end

      # Root-level files are not collection content: README.md and the scan
      # state file are the shelf's own furniture; anything else is a stray.
      def root_notes(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.children(workdir).sort
           .select { |name| File.file?(File.join(workdir, name)) }
           .reject { |name| ["README.md", LocalFetch::STATE_FILE].include?(name) }
           .map { |name| "#{name}: loose file outside any collection — move it into <collection>/ and manifest it" }
      end

      # -- parsing --------------------------------------------------------------

      def build_document(document_ref, meta)
        Nabu::Document.new(
          urn: document_ref.id,
          language: (meta["languages"] || []).first || "und",
          title: meta.fetch("title"),
          canonical_path: document_ref.path,
          license_override: license_override(meta),
          metadata: document_metadata(document_ref, meta)
        )
      end

      # The entry's class becomes a per-document override ONLY when it
      # differs from the shelf class — silence and an explicit
      # research_private both inherit (nil), so the source row stays the one
      # visible default.
      def license_override(meta)
        entry_class = meta.fetch("license_class")
        entry_class == manifest.license_class ? nil : entry_class
      end

      def document_metadata(document_ref, meta)
        metadata = { "kind" => "article", "collection" => meta.fetch("collection"), "file" => meta.fetch("file") }
        %w[creator year languages provenance source_url tags related].each do |key|
          metadata[key] = meta[key] if meta.key?(key)
        end
        layer = text_layer(document_ref, meta)
        metadata["text_layer"] = layer if layer
        metadata
      end

      # The honest extraction marker, decided BEFORE building the document:
      # "pages" (a PDF whose text layer minted page passages), "none" (a
      # scan, an image, an empty or unextractable format — catalogued,
      # queued for the HTR era), nil for born-digital text files (nothing
      # to mark: the file IS the text). PDFs must actually be read to know
      # — a scan reads clean but blank.
      def text_layer(document_ref, meta)
        case File.extname(meta.fetch("file")).downcase
        when ".pdf" then pdf_pages(document_ref).any? { |page| !page.strip.empty? } ? "pages" : "none"
        when *TEXT_EXTENSIONS then paragraphs(document_ref).empty? ? "none" : nil
        else "none"
        end
      end

      def append_passages(document, document_ref, meta)
        case File.extname(meta.fetch("file")).downcase
        when ".pdf"
          pdf_pages(document_ref).each_with_index do |page, index|
            text = Nabu::Normalize.nfc(page).strip
            next if text.empty?

            document << page_passage(document, index + 1, text)
          end
        when *TEXT_EXTENSIONS
          paragraphs(document_ref).each_with_index do |text, index|
            document << Nabu::Passage.new(urn: "#{document.urn}:#{index + 1}", language: document.language,
                                          text: text, sequence: index + 1)
          end
        end
      end

      def page_passage(document, page_number, text)
        Nabu::Passage.new(urn: "#{document.urn}:p#{page_number}", language: document.language,
                          text: text, sequence: page_number)
      end

      # Memoized per parse call-chain (text_bearing? + append_passages read
      # the same file): one mutool run / one file read per document.
      def pdf_pages(document_ref)
        @pdf_pages_cache ||= {}
        @pdf_pages_cache[document_ref.path] ||= @pdf_text.call(document_ref.path)
      end

      def paragraphs(document_ref)
        @paragraphs_cache ||= {}
        @paragraphs_cache[document_ref.path] ||= begin
          text = Nabu::Normalize.nfc(File.read(document_ref.path, encoding: "UTF-8"))
          text.split(/\n[ \t]*\n+/).map(&:strip).reject(&:empty?)
        end
      end

      # -- fetch plumbing (the P19-1 pin/vanished story, verbatim) --------------

      def pin_map(result)
        result.files.merge(result.vanished).transform_keys { |rel| "local:#{rel}" }
      end

      def fetch_notes(result)
        notes = []
        unless result.vanished.empty?
          notes << "#{result.vanished.size} file(s) VANISHED without an attic copy: " \
                   "#{result.vanished.keys.join(', ')} — restore from backup, or move to .attic/ to retire"
        end
        notes << "#{result.retired} file(s) retired into the attic" if result.retired.positive?
        notes.empty? ? nil : notes.join("; ")
      end
    end
  end
end
