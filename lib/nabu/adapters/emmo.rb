# frozen_string_literal: true

require_relative "emmo_tei_parser"
require_relative "../zip_fetch"

module Nabu
  module Adapters
    # emmo — Early Modern Manuscripts Online (Folger Shakespeare Library,
    # Washington DC; emmo.folger.edu): crowd-sourced and project-collated
    # transcriptions of English manuscripts in the Folger's collections,
    # encoded word by word in TEI P5 (the Dromio transcription/collation
    # tool) with every abbreviation expanded and every word regularized.
    # The public download is ONE zip, emmo.folger.edu/zip/emmo.zip.
    #
    # == Shape (censused 2026-11-03 over the zip built 2026-05-31: 2,988,429
    # bytes, md5 8ffbed9736da067193379fc58c123683 = its ETag)
    #
    # 101 members under emmo/: 100 TEI manuscripts + emmo.xsl (the display
    # stylesheet). Shelfmark families: L.a × 55 and L.b × 22 (the Bagot
    # family of Blithfield and the More family of Loseley — among the
    # latter John Donne's letters to Sir George More and Sir Thomas
    # Egerton about his clandestine marriage, 1602), L.d × 7 (Bacon-
    # Townshend of Stiffkey), L.e × 6 (Ferrers of Tamworth), X.c × 6 and
    # X.d × 4; 1552–1697 by the catalogue dates. Mostly letters (with
    # their superscriptions and endorsements), plus certificates, orders,
    # a warrant, depositions and examinations, a receipt and a legal
    # opinion.
    #
    # Delivery grains: the zip (TAKEN, the one artifact); its TEI files
    # (document = file, 100); pb pages (passage = page: 299 pb, 196 carry
    # text, 103 are outer leaves or blank versos with at most a call
    # number — counted per document as blank_pages); emmo.xsl (skipped by
    # rule — a stylesheet, not text); the page images (sourceDoc
    # surfaces → digitalcollections.folger.edu — NEVER fetched: images are
    # outside the grant and the library takes no images; the URL rides
    # each passage as a pointer). Reconciliation: 100 accepted + 1 skipped
    # by rule = the zip's 101 files (+ the fetcher's own .zip-fetch.json
    # state pin, also skipped by rule); EMMO's site advertises no corpus
    # total of its own for the zip.
    #
    # == Language
    #
    # Every file's msItem/textLang reads "eng" (100 of 100) → en; the
    # Latin is marked inline only (18 <foreign xml:lang="la"> spans, plus
    # xml:lang on a few reg/abbr) and rides each page's "foreign"
    # annotation — passage language stays en (deliberately coarse: the
    # spans are datelines, tags and formulae inside English letters).
    # Every catalogue date falls in en:early's [1500, 1700] band
    # (config/lect_overrides.yml).
    #
    # == Axes
    #
    # Dates: msDesc/history/origin@when (100 of 100; ISO year, year-month
    # or day) → a one-year envelope, class composition (a letter is dated
    # by its writing); the catalogue's own wording ("circa 1612 May 28",
    # "1622/1623 February 27") rides as raw. Places: the first
    # <placeName> inside the letter's <seg type="dateline"> — the writing
    # place, in its regularized form (46 of 100 documents; "Oxoniensis"
    # regularizes to "Oxford") → the document place, named (EMMO's names
    # carry no gazetteer refs). Every other <placeName>/<name> rides the
    # page as places/persons mentions (projected as passage facets).
    # Kind: the catalogue title's head noun ("Letter from …", "Deposition
    # by …") → document_type, folded in config/kind_map.yml; the header's
    # keywords term (Letters / Family Papers / …, on 65) rides as genre.
    #
    # == License (read 2026-11-03 in every file)
    #
    # Each file's availability/licence target is
    # creativecommons.org/licenses/by-sa/4.0/ (100 of 100): "This allows
    # you to use our transcriptions without additional permission provided
    # that you cite the Early Modern Manuscripts Online (EMMO) Project at
    # the Folger Shakespeare Library as the source and that you license
    # anything you create using the transcriptions under the same or
    # equivalent license." → attribution. The licence is checked per
    # document: a file carrying any other target quarantines. The images
    # are under separate Folger permissions and are never taken.
    class Emmo < Nabu::Adapter
      SLUG = "emmo"
      URN_PREFIX = "urn:nabu:emmo:"
      LANGUAGE = "en"
      ZIP_URL = "https://emmo.folger.edu/zip/emmo.zip"
      SITE_URL = "https://emmo.folger.edu"
      LICENCE = "https://creativecommons.org/licenses/by-sa/4.0/"
      STYLESHEET = "emmo.xsl"

      # The catalogue title's head noun (longest first) — the document_type
      # kind_map.yml folds.
      DOCUMENT_TYPES = ["Copy of an order", "Certificate of recusancy", "Legal opinion", "Letter", "Certificate",
                        "Order", "Warrant", "Deposition", "Examination", "Receipt"].freeze
      DOCUMENT_TYPE = /\A(#{Regexp.union(DOCUMENT_TYPES).source})\b/

      # "leaf 1 verso || leaf 2 recto" → "1v-2r" (the passage citation).
      LEAF = /\Aleaf\s+(\d+)\s*(recto|verso|r|v)\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "EMMO — Early Modern Manuscripts Online (Folger Shakespeare Library)",
        license: "CC BY-SA 4.0 — every file's licence (target creativecommons.org/licenses/by-sa/4.0/): " \
                 "\"use our transcriptions without additional permission provided that you cite the Early " \
                 "Modern Manuscripts Online (EMMO) Project at the Folger Shakespeare Library as the source and " \
                 "that you license anything you create using the transcriptions under the same or equivalent " \
                 "license\" (read 2026-11-03). Transcriptions only — the images are not taken.",
        license_class: "attribution",
        upstream_url: SITE_URL,
        parser_family: "emmo-tei",
        credit: "Early Modern Manuscripts Online (EMMO), Folger Shakespeare Library, emmo.folger.edu."
      )

      def self.manifest = MANIFEST

      def self.parallel_parse? = true

      # The zip is rebuilt in place (no versioned release): the probe HEADs
      # it for reachability + Last-Modified drift against the ZipFetch pin;
      # the license travels inside every file (metadata_url nil).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(label: "emmo.zip", zip_url: ZIP_URL, metadata_url: nil,
                                            state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE)]
      end

      # "leaf 2 verso || leaf 1 recto" → "2v-1r"; nil for anything else.
      def self.citation(label)
        parts = label.to_s.split("||").map { |part| LEAF.match(part.strip) }
        return nil if parts.empty? || parts.any?(&:nil?)

        parts.map { |m| "#{m[1]}#{m[2][0]}" }.join("-")
      end

      def self.document_type(title) = title.to_s[DOCUMENT_TYPE, 1]

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        document_files(workdir).each do |path|
          stem = Normalize.nfc(File.basename(path, ".xml"))
          yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{stem}", path: path,
                                      metadata: { "stem" => stem })
        end
      end

      # The stylesheet and the fetcher's own state pin skip by rule; any
      # other non-document file is unrecognized (a defect, never silent).
      def discovery_skips(workdir)
        return Nabu::Adapter::DiscoverySkips.new unless Dir.exist?(workdir)

        notes = []
        unrecognized = []
        Dir.children(workdir).sort.each do |name|
          next if name == ATTIC_DIRNAME || name.end_with?(".xml")

          case name
          when STYLESHEET then notes << "#{name}: the zip's display stylesheet — not text"
          when Nabu::ZipFetch::STATE_FILE then notes << "#{name}: the fetcher's own state pin — not upstream content"
          else unrecognized << name
          end
        end
        notes.concat(unrecognized.map { |name| "#{name}: unrecognized member of the EMMO zip" })
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size - unrecognized.size,
                                          unrecognized: unrecognized.size, notes: notes)
      end

      def parse(document_ref)
        result = EmmoTeiParser.new.parse(document_ref.path)
        header = result.header
        verify_licence!(document_ref, header)
        raise Nabu::ParseError, "#{document_ref.path}: no transcribed page" if result.pages.empty?

        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: nfc(header.title) || document_ref.metadata["stem"],
                                      metadata: document_metadata(result))
        add_passages(document, result, header)
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
                                      progress: progress,
                                      guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) })
        note = result.not_modified ? "not modified (304)" : "emmo.zip unpacked"
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now,
                              notes: [note, attic_notes(result.atticked)].compact.join("; "))
      rescue Nabu::ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def document_files(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.glob(File.join(workdir, "*.xml")).map { |path| File.expand_path(path) }.sort
      end

      def verify_licence!(document_ref, header)
        return if header.licence == LICENCE

        raise Nabu::ParseError, "#{document_ref.path}: licence target #{header.licence.inspect} is not " \
                                "#{LICENCE} — the per-document grant this source is held under"
      end

      def document_metadata(result)
        header = result.header
        places = result.pages.flat_map(&:places).uniq
        persons = result.pages.flat_map(&:persons).uniq
        {
          "emmo_id" => header.idno, "shelfmark" => header.shelfmark, "collection" => header.collection,
          "repository" => header.repository, "folger_bbid" => header.bbid, "author" => header.author,
          "summary" => header.summary, "language_raw" => header.text_lang,
          "document_type" => self.class.document_type(header.title),
          "genre" => header.keywords.empty? ? nil : header.keywords,
          "date" => date(header), "place" => result.writing_place,
          "place_role" => result.writing_place && "dateline",
          "places_mentioned" => places.empty? ? nil : places,
          "persons_mentioned" => persons.empty? ? nil : persons,
          "edition" => header.edition, "licence" => header.licence, "blank_pages" => result.blank_pages
        }.compact.then { |meta| deep_nfc(meta) }
      end

      # origin@when's year → a one-year envelope (class note).
      def date(header)
        year = header.origin_when.to_s[/\A(\d{4})/, 1] or return nil

        { "not_before" => Integer(year, 10), "not_after" => Integer(year, 10),
          "raw" => header.origin_raw || header.origin_when, "class" => "composition" }
      end

      def add_passages(document, result, header)
        seen = Hash.new(0)
        result.pages.each_with_index do |page, index|
          citation = self.class.citation(page.n) || "s#{index + 1}"
          seen[citation] += 1
          citation = "#{citation}-#{seen[citation]}" if seen[citation] > 1
          document << Nabu::Passage.new(urn: "#{document.urn}:#{citation}", language: LANGUAGE,
                                        text: Normalize.nfc(page.text), sequence: index + 1,
                                        annotations: annotations(page, header))
        end
      end

      def annotations(page, header)
        regularized = Normalize.nfc(page.regularized)
        deep_nfc({
          "page" => page.n, "image_url" => header.surfaces[page.n.to_s],
          "regularized" => (regularized unless regularized == Normalize.nfc(page.text.tr("\n", " "))),
          "places" => presence(page.places), "persons" => presence(page.persons),
          "foreign" => presence(page.foreign), "deletions" => presence(page.deletions),
          "notes" => presence(page.notes), "forme_work" => presence(page.forme_work)
        }.compact)
      end

      def presence(list) = list.empty? ? nil : list

      def nfc(value) = value && Normalize.nfc(value)

      def deep_nfc(value)
        case value
        when String then Normalize.nfc(value)
        when Hash then value.transform_values { |v| deep_nfc(v) }
        when Array then value.map { |v| deep_nfc(v) }
        else value
        end
      end
    end
  end
end
