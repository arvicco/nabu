# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # RuneS-DB — the runic inscription database of the Göttingen Academy's
    # long-term project "Runic Writing in the Germanic Languages" (RuneS),
    # as deposited on Zenodo (record 21788307, v1.0.0, 2026-08-01): one
    # TEI file per runic find, the whole archive one zip (runes_tei.zip,
    # 9.8 MB, 723 files). The finds span the older-futhark beginnings to
    # the post-Reformation period: Danish, Swedish and Norwegian stones,
    # the continental (South Germanic) brooches and capsules, the Old
    # English and Frisian corpora, and runica manuscripta — runes written
    # in medieval and early-modern manuscripts (Holm B, AM, BL, St. Gallen…).
    #
    # == The delivery grains (census of the 2026-08-01 zip, 723 files)
    #
    # The zip serves ONE grain: the find (runes_find-<id>.tei.xml, flat, no
    # top directory). Inside a find, sides (<div type="side" n="A"|"recto"|
    # "folio 4 recto"…, 874) carry sequences (<ab type="sequence">, 1,812)
    # of glyphs (<g>, 20,180 incl. ligature components), each glyph a
    # graphemic record: transliteration, rune name(s), formal type, and a
    # deep per-stroke runological description (elements, course, technique,
    # bounding boxes on the facsimile). Document = the find; passage = a
    # sequence (upstream's own reading unit). 613 finds carry at least one
    # transliterated glyph and become documents (1,611 passages); the other
    # 110 record their signs geometrically only (no glyph has a
    # transliteration — e.g. the South Germanic brooches SG-118, SG-72) and
    # are SKIPPED BY RULE as untransliterated finds (discovery_skips; never
    # dropped silently): 613 + 110 = 723, the zip's whole content (upstream
    # advertises no count of its own beyond the file list). Within a
    # text-bearing find, 11 sequences with no transliterated glyph mint no
    # passage and are counted on the document (untransliterated_sequences).
    #
    # == Identity
    #
    #   document urn  urn:nabu:runesdb:<find id>   (msIdentifier/idno = the
    #                                               filename's number)
    #   passage urn   <document-urn>:<sequence xml:id sans "seq-">
    #                 (…:A-1, …:folio_4_recto-5), the house :b<n> positional
    #                 disambiguator on upstream's repeated ids (AM 748 I b 4to
    #                 repeats its recto/verso sides once per rune of the row).
    #
    # == The text
    #
    # A passage's text is its glyphs' main transliterations (the en
    # variant; de is identical across the census) concatenated in document
    # order, verbatim — runological sigla included (":" word separators,
    # "*", "[...]", "?", bind-rune "a^r"). Ligature component glyphs
    # (<g type="ligature">, the bind-rune's parts) never re-enter the text;
    # they ride the parent glyph's annotation — except when the parent
    # carries no transliteration of its own (the Hogebeintum comb): the
    # bind-rune then reads as its components in upstream's own "^"
    # notation (d^*^d), flagged composed. A glyph without a
    # transliteration contributes nothing to the text and is marked in the
    # glyph annotations (translit nil) — no placeholder is invented.
    #
    # == Language (declared coarse)
    #
    # The TEI carries no language claim. Every document rides `gem`
    # (Germanic, ISO 639-5) — the honest family-level claim for an archive
    # spanning Proto-Norse, Old Norse, Old English, Frisian and continental
    # runic. upstream's siglum family (the Hauptsigle before its running
    # number: OE-GB, MJy, N KJ, SG, Holm B…) rides the siglum_family facet,
    # the seam the runesdb-siglum lect rule reads (config/lect_facet_rules.yml).
    #
    # == Axes (aggressive mining, declared)
    #
    # The TEI zip carries no date and no place. Upstream publishes those
    # (plus an editorial transcription and an English translation) in a
    # separate per-find LIDO record (https://www.runesdb.de/lido/<id>, CC BY-SA)
    # that this adapter does NOT fetch — the LIDO url rides metadata
    # lido_url, and the per-find LIDO harvest is the follow-up that lights
    # the dating and places axes.
    #
    # == License
    #
    # CC BY-SA 4.0: the Zenodo record's license field (cc-by-sa-4.0) and
    # every file's <availability> (verbatim "CC BY-SA 4.0 - Attribution-
    # ShareAlike 4.0 International", target the by-sa/4.0 deed) — censused
    # on all 723 files. The availability element says status="restricted"
    # beside that statement in every file; the statement and the record
    # govern. license_class attribution; a file whose statement is not
    # BY-SA goes restricted.
    class Runesdb < Nabu::Adapter
      ZIP_URL = "https://zenodo.org/records/21788307/files/runes_tei.zip"
      RECORD_URL = "https://doi.org/10.5281/zenodo.21788307"
      LIDO_URL = "https://www.runesdb.de/lido/%s"

      LANGUAGE = "gem"
      URN_PREFIX = "urn:nabu:runesdb:"
      FILE_PATTERN = /\Arunes_find-(?<id>\d+)\.tei\.xml\z/
      TITLE_LABEL = /\AInschrift:\s*/

      XML_NAMESPACE = "http://www.w3.org/XML/1998/namespace"
      NS = { "t" => "http://www.tei-c.org/ns/1.0", "r" => "https://www.runesdb.de/tei-extension" }.freeze
      # The cheap discover-time probe: does any glyph carry a transliteration?
      TRANSLITERATED = /<seg type="transliteration" subtype="main" xml:lang="en">\s*[^<\s]/

      # Sequence-level runological attributes carried verbatim (en side).
      SEQUENCE_ATTRIBUTES = {
        "readingDir" => "reading_direction", "layout-en" => "layout", "technique-en" => "technique",
        "impaired" => "impaired", "samstavsRunor" => "samstavsrunor"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "runesdb",
        name: "RuneS-DB — runic inscriptions of the Göttingen Academy project RuneS (TEI)",
        license: "CC BY-SA 4.0 — the Zenodo record's license field (cc-by-sa-4.0, record " \
                 "21788307, v1.0.0, 2026-08-01) and every file's <availability> (\"CC BY-SA 4.0 - " \
                 "Attribution-ShareAlike 4.0 International\"). Cite: Göttingen Academy of Sciences " \
                 "and Humanities in Lower Saxony, Project Runic writing in the Germanic languages " \
                 "(RuneS), RuneSDB.de inscription data, doi:10.5281/zenodo.21788307",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "runesdb-tei"
      )

      def self.manifest
        MANIFEST
      end

      # HEAD the zip: reachability + Last-Modified drift vs the pin.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "runes_tei.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # The siglum's family: the Hauptsigle before its running number
      # ("OE-GB-30" → "OE-GB", "N KJ38" → "N KJ", "Holm B 59 4to, 25v" →
      # "Holm B", "MJy 74" → "MJy"). nil when nothing precedes a digit.
      def self.siglum_family(siglum)
        family = siglum.to_s.sub(/[-\s]*\d.*\z/m, "").strip
        family.empty? ? nil : family
      end

      def self.license_override_for(statement)
        statement.to_s.match?(/CC BY-SA 4\.0/) ? nil : "restricted"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        find_files(workdir).each do |id, path|
          next unless transliterated?(path)

          yield Nabu::DocumentRef.new(source_id: manifest.id, id: "#{URN_PREFIX}#{id}",
                                      path: File.expand_path(path), metadata: { "find_id" => id })
        end
      end

      def discovery_skips(workdir)
        notes = find_files(workdir).reject { |_id, path| transliterated?(path) }.map do |_id, path|
          "#{File.basename(path)}: untransliterated find (signs recorded geometrically only, " \
            "no glyph transliteration)"
        end
        DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: 0, notes: notes)
      end

      def parse(document_ref)
        xml = Nokogiri::XML(File.read(document_ref.path, encoding: Encoding::UTF_8))
        raise ParseError, "#{document_ref.path}: not a RuneS-DB TEI find" if xml.at_xpath("/t:TEI", NS).nil?

        build_document(xml, document_ref)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{document_ref.path}: malformed TEI: #{e.message}"
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress, guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "runesdb fetch failed into #{workdir}: #{e.message}"
      end

      private

      # [find id, path] for every runes_find-<id>.tei.xml, sorted by urn.
      def find_files(workdir)
        files = Dir.glob(File.join(workdir, "runes_find-*.tei.xml")).filter_map do |path|
          match = FILE_PATTERN.match(File.basename(path)) or next
          [match[:id], path]
        end
        files.sort_by { |id, _path| "#{URN_PREFIX}#{id}" }
      end

      def transliterated?(path)
        File.read(path, encoding: Encoding::UTF_8).match?(TRANSLITERATED)
      end

      def build_document(xml, document_ref)
        readings, untransliterated = sequence_readings(xml, document_ref.id)
        raise ParseError, "#{document_ref.path}: no transliterated sequence" if readings.empty?

        metadata = document_metadata(xml, document_ref)
        metadata["untransliterated_sequences"] = untransliterated if untransliterated.positive?
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: document_title(xml),
          canonical_path: document_ref.path, metadata: metadata,
          license_override: self.class.license_override_for(metadata["license"])
        )
        readings.each_with_index do |(urn, text, annotations), index|
          document << Nabu::Passage.new(urn: urn, language: LANGUAGE, text: Normalize.nfc(text),
                                        sequence: index, annotations: annotations)
        end
        document
      end

      def document_title(xml)
        title = text_at(xml, "//t:titleStmt/t:title")
        title && Normalize.nfc(title.sub(TITLE_LABEL, ""))
      end

      def document_metadata(xml, document_ref)
        find_id = text_at(xml, "//t:msIdentifier/t:idno") || document_ref.metadata["find_id"]
        siglum = text_at(xml, "//t:msIdentifier/t:altIdentifier/t:idno[@type='hauptsigle']")
        family = self.class.siglum_family(siglum)
        {
          "find_id" => find_id,
          "siglum" => siglum && Normalize.nfc(siglum),
          "siglum_family" => family,
          "summary" => text_at(xml, "//t:msContents/t:summary"),
          "license" => text_at(xml, "//t:availability/t:p[@xml:lang='en']"),
          "license_url" => xml.at_xpath("//t:availability/t:ref/@target", NS)&.value,
          "lido_url" => format(LIDO_URL, find_id),
          "sides" => xml.xpath("//t:body//t:div[@type='side']", NS).size,
          "facets" => ({ "siglum_family" => { "value" => family } } if family)
        }.compact
      end

      # [[urn, text, annotations]…] for every transliterated sequence, plus
      # how many sequences carried no transliteration.
      def sequence_readings(xml, document_urn)
        seen = Hash.new(0)
        skipped = 0
        readings = []
        xml.xpath("//t:body//t:div[@type='side']", NS).each do |side|
          side.xpath("./t:ab[@type='sequence']", NS).each do |sequence|
            glyphs = glyph_records(sequence)
            text = glyphs.filter_map { |glyph| glyph["translit"] }.join
            if text.empty?
              skipped += 1
              next
            end

            readings << [passage_urn(document_urn, sequence, side, seen), text,
                         sequence_annotations(sequence, side, glyphs)]
          end
        end
        [readings, skipped]
      end

      def passage_urn(document_urn, sequence, side, seen)
        id = xml_id(sequence).to_s.delete_prefix("seq-")
        id = "#{side['n'].to_s.strip.tr(' ', '_')}-#{sequence['n']}" if id.empty?
        seen[id] += 1
        ref = seen[id] > 1 ? "#{id}:b#{seen[id]}" : id
        "#{document_urn}:#{ref}"
      end

      def sequence_annotations(sequence, side, glyphs)
        annotations = { "side" => side["n"].to_s.strip, "sequence" => sequence["n"] }
        SEQUENCE_ATTRIBUTES.each do |attribute, key|
          value = sequence.attribute_with_ns(attribute, NS["r"])&.value.to_s.strip
          annotations[key] = value unless value.empty? || value == "-"
        end
        annotations["facs"] = sequence["facs"] if sequence["facs"]
        annotations["glyphs"] = glyphs
        annotations
      end

      # One record per reading glyph (ligature components fold into their
      # parent's "ligature" list).
      def glyph_records(sequence)
        records = []
        by_id = {}
        sequence.xpath("./t:g", NS).each do |glyph|
          if glyph["type"] == "ligature"
            parent = by_id[glyph["ana"].to_s.delete_prefix("#")]
            (parent["ligature"] ||= []) << transliteration(glyph) if parent
            next
          end

          record = glyph_record(glyph)
          by_id[xml_id(glyph)] = record
          records << record
        end
        records.each { |record| compose_bind_rune(record) }
      end

      # A bind-rune whose parent glyph carries no transliteration of its
      # own reads as its components in upstream's own bind-rune notation
      # (the "a^r" form the transliterated parents use).
      def compose_bind_rune(record)
        parts = record["ligature"].to_a.compact
        return record if record["translit"] || parts.empty?

        record.merge!("translit" => parts.join("^"), "composed" => true)
      end

      def glyph_record(glyph)
        name = glyph.at_xpath("./t:seg[@type='runeName'][@subtype='primary'][@xml:lang='en']", NS)&.text.to_s.strip
        note = glyph.at_xpath("./t:note[@type='commentary']", NS)&.text.to_s.strip
        {
          "id" => xml_id(glyph),
          "translit" => transliteration(glyph),
          "rune_name" => (Normalize.nfc(name) unless name.empty? || name == "-"),
          "uncertain" => (true if glyph.attribute_with_ns("graphTypeUncertain", NS["r"])&.value == "true"),
          "separator" => (true if glyph.attribute_with_ns("separationSign", NS["r"])&.value == "true"),
          "note" => (Normalize.nfc(note) unless note.empty?)
        }.compact
      end

      def transliteration(glyph)
        value = glyph.at_xpath("./t:seg[@type='transliteration'][@subtype='main'][@xml:lang='en']", NS)&.text.to_s.strip
        value.empty? ? nil : Normalize.nfc(value)
      end

      def xml_id(node) = node.attribute_with_ns("id", XML_NAMESPACE)&.value

      def text_at(xml, xpath)
        value = xml.at_xpath(xpath, NS)&.text.to_s.gsub(/\s+/, " ").strip
        value.empty? ? nil : value
      end
    end
  end
end
