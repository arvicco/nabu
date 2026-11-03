# frozen_string_literal: true

require "json"
require_relative "../zip_range_fetch"
require_relative "source_read"

module Nabu
  module Adapters
    # osbct — the Sixth Buddhist Council Tipiṭaka (Chaṭṭhasaṅgītipiṭaka)
    # Unicode corpus of the Instituto de Estudios Buddhistas Hispano (IEBH)
    # and Buddhismo Theravāda Hispano A.R. (BTHAR): Zenodo record 23541744
    # (v2.11.0, 2026-10-21; concept 21495338; github.com/bthar-mx/OSBCT).
    # The Chaṭṭha Saṅgāyana recension of the Pāḷi canon WITH its Aṭṭhakathā
    # and Ṭīkā — 118 volumes (40 canon, 52 commentary, 26 subcommentary),
    # 89,512 paragraphs — converted from the legacy VZTimes-font PDFs of the
    # edition published by the Ministry of Religious Affairs, Yangon (Pāḷi
    # Series, romanised 2008 from the Myanmar-script edition of 2001), with
    # the printed footnote apparatus (variant readings with their sigla,
    # cross-references) parsed per paragraph. The record says it plainly:
    # "This is not the VRI / Igatpuri (CST) digital edition, which is a
    # different recension with its own editorial layer."
    #
    # == License (read first-hand 2026-11-02) — the text is nc
    #
    # The Zenodo record's license field is cc-by-4.0, but the deposit's own
    # LICENSE.md splits the material: "The underlying Pāḷi text (Tipiṭaka,
    # Aṭṭhakathā, Ṭīkā) is from the Sixth Council edition published by the
    # Ministry of Religious Affairs, Yangon, Myanmar, for free distribution
    # as a Gift of the Dhamma. The edition's own notice grants permission to
    # duplicate the material for free, non-commercial distribution. This
    # project reproduces that text faithfully and redistributes it on those
    # terms." CC BY 4.0 covers only "the derived data (the structural markup,
    # cross-layer links, parsed variant apparatus, concordance, and search
    # index)"; the code is MIT. README.md: the text "is not public domain".
    # So the redistributor's own claim over the TEXT is non-commercial —
    # class nc, with the CC BY grant recorded for the apparatus it carries.
    # UNVERIFIED: the Ministry edition's notice itself (the deposit omits
    # the source PDFs; its wording is known only through LICENSE.md), and
    # whether the Ministry holds rights it could grant. Recorded, not
    # resolved: commercial reuse is referred to the publisher
    # (buddhasasanasociety@gmail.com) by the deposit itself.
    #
    # == Delivery grains (census of the v2.11.0 zip, 2026-11-02 — 46,326
    #    members, 1.73 GB unpacked)
    #
    # - site/<VOL>.json — TAKEN: one volume each (118 = the record's count;
    #   placed by data/concordance.json into canon / commentary /
    #   subcommentary and a work group). {paragraphs: [...], headings:
    #   [...]} (+ vol/source on 93 of the 118). A paragraph carries its
    #   unique key "<VOL>#<k>" (ordinal on 114 volumes; 21KhuT01, 22AbhiT01,
    #   23AbhiT02, 24AbhiT03 skip numbers after a re-segmentation — the key
    #   stays unique), printed/pdf page, paragraph number n..n_to, the
    #   book/vagga/sutta path, peyyāla flag, and the text. The DOCUMENT.
    # - site/reader/apparatus/<VOL>.appk.json — TAKEN as annotations: the
    #   printed footnote notes keyed by paragraph ORDINAL (73,431 notes;
    #   55,241 variant readings + 34,048 xrefs counted over the notes — the
    #   record's 54,036/27,153 count distinct readings in its own tables).
    # - site/downloads.data.json (per-volume work title, source PDF) and
    #   data/concordance.json (layer + group) — TAKEN as metadata tables;
    #   with site/build.json and site/errata.json they are the four
    #   non-volume site/*.json, skipped by rule (counted).
    # - site/reader/apparatus/<VOL>.app.json (the same notes keyed by the
    #   hierarchical id, NOT unique — 12,110 collisions per upstream),
    #   site/reader/{verse,bold,nav,…}, site/index/ (search shards),
    #   stores/ (dictionary lookups built with DPD), _xc/, _review/, _panel/,
    #   pipeline/, docs/, the HTML reader — REJECTED: outside the Range
    #   cone (KEEP), never fetched; the fixture pins one .app.json.
    # Reconciliation: 118 volumes accepted = the record's 118; paragraphs
    # 89,512 = the record's 89,512 exactly.
    #
    # == Passage text
    #
    # Upstream's text verbatim, NFC, except the edition's inline note
    # markers: a 1–2 digit run glued to a letter (Anupiyaṁ nāma1) is the
    # footnote pointer the reader renders as a superscript (upstream's own
    # rule, check_fn_markers.js: ([letter])(\d{1,2})); Pāḷi words carry no
    # digits (upstream's census: a–z + ā ī ū ṁ ṅ ñ ṇ ṭ ḍ ḷ). The marker
    # leaves the text and rides note_markers [[offset, n], …] (offset =
    # the character position in the stored text just after the annotated
    # letter), so a search for nāma finds it. 70,599 markers over the
    # corpus. The niggahita stays the edition's ṁ (suttacentral prints ṃ;
    # the search fold meets them). The appk notes for the paragraph ride
    # verbatim as apparatus — no marker-to-note pairing is claimed (the
    # deposit attaches notes by page window, not by marker).
    #
    # == Overlap (census 2026-11-02, 6-token shingles, ≥50% of a
    #    paragraph's shingles present = witnessed)
    #
    # Same canon, different editions — WITNESSES, never duplicates. Canon:
    # 38,752 of 49,453 paragraphs witnessed in a held edition (suttacentral
    # Mahāsaṅgīti 37,799; tipitaka-lk BJT 23,913), 7,660 not (the Paṭṭhāna
    # volumes' abbreviation differences dominate), 3,041 too short to
    # measure. Commentary: 21,773 of 29,206 witnessed (tipitaka-lk's CST
    # aṭṭhakathā 21,308; Kaṅkhāvitaraṇī is not held there). Subcommentary:
    # 48 of 10,853 — the Ṭīkā layer is new to the library, as is the
    # parsed printed apparatus.
    class Osbct < Nabu::Adapter
      SLUG = "osbct"
      LANGUAGE = "pli"
      URN_PREFIX = "urn:nabu:osbct:"
      RECORD_URL = "https://zenodo.org/records/23541744"
      ZIP_URL = "https://zenodo.org/api/records/23541744/files/bthar-mx/OSBCT-v2.11.0.zip/content"
      # sha256 of the v2.11.0 zip's central directory (the ZipRangeFetch
      # identity; zip md5 8d89920db175cd59ddd50025434f2d21 = the record's
      # checksum, 463,341,640 bytes, downloaded 2026-11-02).
      DIRECTORY_SHA256 = "3d1c2b1bcc436c3b5f2a8e8d5ae8a9035bb9b54d90afb98cd455def7a44a5f77"

      # The Range cone: the volumes, their ordinal-keyed apparatus, the two
      # metadata tables, and the deposit's license/citation files.
      KEEP = %r{\A(?:LICENSE\.md|README\.md|CITATION\.cff|\.zenodo\.json|data/concordance\.json|
                 site/[^/]+\.json|site/reader/apparatus/[^/]+\.appk\.json)\z}x
      SITE_DIR = "site"
      APPARATUS_DIR = File.join("site", "reader", "apparatus")
      CONCORDANCE = File.join("data", "concordance.json")
      DOWNLOADS = File.join("site", "downloads.data.json")
      VOLUME = /\A\d\d[A-Za-z]+\d*\z/
      LAYERS = %w[canon commentary subcommentary].freeze
      # upstream's reader rule for the edition's footnote pointer.
      MARKER = /(?<=\p{L})(\d{1,2})(?!\d)/
      EDITION = "Chaṭṭha Saṅgāyana (Sixth Council) edition, Ministry of Religious Affairs, Yangon — Pāḷi " \
                "Series, romanised 2008 from the Myanmar edition of 2001; Unicode conversion and apparatus " \
                "by IEBH / BTHAR, v2.11.0"
      ATTRIBUTION = "Ministry of Religious Affairs, Yangon (Sixth Council edition); IEBH / BTHAR (Unicode corpus)"

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Sixth Buddhist Council Tipiṭaka (Chaṭṭhasaṅgītipiṭaka) — Unicode corpus (IEBH / BTHAR)",
        license: "The Pāḷi text: the Sixth Council edition published by the Ministry of Religious " \
                 "Affairs, Yangon, \"for free distribution as a Gift of the Dhamma. The edition's own notice " \
                 "grants permission to duplicate the material for free, non-commercial distribution\" " \
                 "(the deposit's LICENSE.md, Zenodo record 23541744, read 2026-11-02; the notice itself " \
                 "not seen first-hand). The deposit's derived data (structural markup, parsed apparatus, " \
                 "links, concordance) CC BY 4.0, attribute IEBH / BTHAR (the record's license field " \
                 "cc-by-4.0). Non-commercial use only",
        license_class: "nc",
        upstream_url: RECORD_URL,
        parser_family: "osbct-json",
        credit: "Sixth Buddhist Council Tipiṭaka (Chaṭṭhasaṅgītipiṭaka) — Unicode corpus, v2.11.0, IEBH / " \
                "BTHAR, Zenodo 10.5281/zenodo.23541744 — from the edition of the Ministry of Religious " \
                "Affairs, Yangon."
      )

      def self.manifest = MANIFEST

      # #parse reads one volume (+ its apparatus) and keeps nothing between refs.
      def self.parallel_parse? = true

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(label: "zenodo 23541744", zip_url: ZIP_URL, metadata_url: nil,
                                            state_subdir: "", state_file: Nabu::ZipRangeFetch::STATE_FILE,
                                            liveness_only: true)]
      end

      def self.keep?(rel) = KEEP.match?(rel)

      def initialize(range_fetch: ->(**kwargs) { Nabu::ZipRangeFetch.new(**kwargs) })
        super()
        @range_fetch = range_fetch
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        tables = tables(workdir)
        volume_files(workdir).each do |stem, path|
          placement = tables[:layers][stem] or next
          yield Nabu::DocumentRef.new(
            source_id: SLUG, id: "#{URN_PREFIX}#{stem}", path: path,
            metadata: { "volume" => stem, "layer" => placement[:layer], "group" => placement[:group],
                        "group_work" => placement[:work] }.merge(tables[:downloads].fetch(stem, {}))
          )
        end
      end

      def discovery_skips(workdir)
        site = Dir.glob(File.join(workdir, SITE_DIR, "*.json")).map { |path| File.basename(path, ".json") }.sort
        metadata = site.grep_v(VOLUME)
        layers = tables(workdir)[:layers]
        strays = site.select { |stem| VOLUME.match?(stem) && !layers.key?(stem) }
        notes = []
        unless metadata.empty?
          notes << "site metadata, not volumes (skipped by rule): #{metadata.map { |stem| "#{stem}.json" }.join(', ')}"
        end
        notes << "volume-shaped files data/concordance.json does not place: #{strays.join(', ')}" unless strays.empty?
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: metadata.size, unrecognized: strays.size, notes: notes)
      end

      def parse(document_ref)
        meta = document_ref.metadata
        stem = meta.fetch("volume")
        data = read_json(document_ref.path)
        paragraphs = data.fetch("paragraphs")
        apparatus = apparatus_for(document_ref.path, stem)
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: "#{meta['work'] || stem} (#{stem})",
                                      metadata: document_metadata(meta, data, apparatus))
        paragraphs.each_with_index do |paragraph, ordinal|
          passage = passage_for(document_ref.id, paragraph, apparatus[ordinal.to_s], ordinal)
          document << passage if passage
        end
        raise Nabu::ParseError, "#{document_ref.path}: no paragraphs" if document.empty?

        document
      rescue KeyError, TypeError, Nabu::ValidationError => e
        raise Nabu::ParseError, "#{SLUG}: #{document_ref.path}: #{e.class}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        fetch = @range_fetch.call(url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
                                  select: ->(rel) { self.class.keep?(rel) }, progress: progress)
        fetch.prepare!
        result = fetch.result
        unless fetch.not_modified?
          verify_pin!(result.sha)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        end
        fetch.complete!
        Nabu::FetchReport.new(
          sha: result.sha, fetched_at: Time.now,
          notes: [fetch_note(fetch, result), attic_notes(fetch.result.atticked)].compact.join("; ")
        )
      rescue Nabu::ZipRangeFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def fetch_note(fetch, result)
        return "not modified (directory pin, every kept member on disk)" if fetch.not_modified?

        "zenodo v2.11.0 directory pin verified; #{result.kept} members kept by Range, #{result.skipped} never read"
      end

      def volume_files(workdir)
        Dir.glob(File.join(workdir, SITE_DIR, "*.json"))
           .map { |path| [File.basename(path, ".json"), File.expand_path(path)] }
           .select { |stem, _path| VOLUME.match?(stem) }.sort
      end

      # The two upstream tables: data/concordance.json (stem → layer, group,
      # group work) and site/downloads.data.json (stem → work title, PDF).
      def tables(workdir)
        { layers: layers(File.join(workdir, CONCORDANCE)), downloads: downloads(File.join(workdir, DOWNLOADS)) }
      end

      def layers(path)
        return {} unless File.file?(path)

        read_json(path).fetch("groups").each_with_object({}) do |group, index|
          LAYERS.each do |layer|
            Array(group.dig(layer, "files")).each do |stem|
              index[stem] ||= { layer: layer, group: group.fetch("group"), work: Normalize.nfc(group.fetch("work")) }
            end
          end
        end
      end

      def downloads(path)
        return {} unless File.file?(path)

        read_json(path).values.flatten.to_h do |entry|
          [entry.fetch("file"), { "work" => Normalize.nfc(entry.fetch("work")), "source_pdf" => entry["key"] }]
        end
      end

      def apparatus_for(volume_path, stem)
        path = File.join(File.dirname(volume_path), "reader", "apparatus", "#{stem}.appk.json")
        File.file?(path) ? read_json(path) : {}
      end

      def document_metadata(meta, data, apparatus)
        {
          "volume" => meta["volume"], "layer" => meta["layer"], "group" => meta["group"],
          "group_work" => meta["group_work"], "work" => meta["work"],
          "source_pdf" => data["source"] || meta["source_pdf"], "upstream_vol" => data["vol"],
          "facets" => { "layer" => { "value" => meta["layer"], "raw" => meta["layer"] } },
          "edition" => EDITION, "attribution" => ATTRIBUTION,
          "apparatus_notes" => apparatus.values.sum(&:size)
        }.compact
      end

      def passage_for(urn, paragraph, notes, ordinal)
        raw = Normalize.nfc(paragraph.fetch("text").to_s)
        text, markers = strip_markers(raw)
        return nil if text.strip.empty?

        citation = paragraph.fetch("key").to_s.split("#", 2).last
        Nabu::Passage.new(urn: "#{urn}:#{citation}", language: LANGUAGE, text: text, sequence: ordinal,
                          annotations: annotations(paragraph, markers, notes))
      end

      # Each marker leaves the text; its offset is where it stood in the
      # stripped string (just after the annotated letter).
      def strip_markers(raw)
        markers = []
        removed = 0
        text = raw.gsub(MARKER) do
          match = Regexp.last_match
          markers << [match.begin(0) - removed, Integer(match[1], 10)]
          removed += match[0].length
          ""
        end
        [text, markers]
      end

      def annotations(paragraph, markers, notes)
        number = paragraph["n"]
        {
          "printed_page" => paragraph["printed"], "pdf_page" => paragraph["pdf_page"],
          "paragraph" => number, "paragraph_to" => (paragraph["n_to"] if paragraph["n_to"] != number),
          "covers" => (paragraph["covers"] unless Array(paragraph["covers"]).empty? || paragraph["covers"] == [number]),
          "book" => nfc(paragraph["book"]), "vagga" => nfc(paragraph["vagga"]), "sutta" => nfc(paragraph["sutta"]),
          "sutta_n" => paragraph["sutta_n"], "path" => nfc(paragraph["id"]),
          "unnumbered" => (true if paragraph["unnumbered"]), "peyyala" => (true if paragraph["peyyala"]),
          "note_markers" => (markers unless markers.empty?),
          "apparatus" => (deep_nfc(notes) unless Array(notes).empty?)
        }.compact
      end

      def nfc(value) = value.nil? ? nil : Normalize.nfc(value)

      def deep_nfc(value)
        case value
        when String then Normalize.nfc(value)
        when Array then value.map { |item| deep_nfc(item) }
        when Hash then value.transform_values { |item| deep_nfc(item) }
        else value
        end
      end

      def read_json(path)
        JSON.parse(SourceRead.utf8_file(path, label: SLUG))
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "#{SLUG}: #{path}: not JSON (#{e.message})"
      end

      def verify_pin!(sha)
        return if sha == DIRECTORY_SHA256

        raise Nabu::FetchError,
              "#{SLUG}: the zip directory misses the v2.11.0 pin (expected #{DIRECTORY_SHA256}, got #{sha}) — " \
              "Zenodo files are immutable, so this is corruption or a new version; read #{RECORD_URL} and re-pin"
      end
    end
  end
end
