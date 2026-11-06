# frozen_string_literal: true

require "nokogiri"

require_relative "runesdb_lido"
require_relative "runesdb_lido_fetch"

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
    # == Axes — the LIDO layer (P160; aggressive mining, declared)
    #
    # The TEI zip carries no date and no place. Upstream publishes those —
    # plus object type, find context, material, the editorial
    # transcription and an English (often also German) translation — in a
    # separate per-find LIDO record (https://www.runesdb.de/lido/<id>).
    # #fetch harvests one per discovered find into lido/<id>.xml
    # (RunesdbLidoFetch: paced 1 req/s, resumable, never-delete) and
    # #parse merges the record into the find's metadata (RunesdbLido —
    # the field map lives there): "date" = the Production event's
    # earliest/latest years (the MetadataDates :structured lane, artifact
    # dating, no class), "place" = the Finding event's find place + its
    # GML point (manuscripts excepted: their finding event names the
    # holding library), the discovery date as "find_date" (never a dating
    # claim). A find without a harvested record parses exactly as before
    # (the TEI-only metadata) — so an unharvested tree and an interrupted
    # harvest stay honest, and nothing about a find's identity depends on
    # its LIDO record.
    #
    # == Translations (registry `translations: true`)
    #
    # A record's English translation mints a -en sibling document
    # (urn:nabu:runesdb:<id>-en, language eng, one passage :1 — the
    # riig/open-etruscan/aio shape) when it is a real rendering: "-" is
    # upstream's none, and a "translation" that merely restates the
    # reading (a manuscript's single rune "m", the TEI transliteration or
    # the LIDO transcription again, whitespace-insensitive) mints nothing.
    # Every translation string rides the find's metadata verbatim either
    # way (translation_en / translation_de), so nothing is dropped. German
    # translations stay metadata-only (the layer is the English one).
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
    #
    # The LIDO layer is the SAME grant, stated per record: every record's
    # recordRights reads "CC BY-SA 4.0 - Attribution-ShareAlike 4.0
    # International" (rdf:about the by-sa/4.0 deed), its objectDescription
    # rights "CC BY-SA 4.0"; rights holder the Göttingen Academy of
    # Sciences and Humanities in Lower Saxony (GND 16268620-1) — read on
    # the 27-record census, 2026-11-05. The site's data-sources page
    # (runesdb.de/en/data-sources, read 2026-11-05): "The rights to the
    # data are held by the Göttingen Academy of Sciences and Humanities in
    # Lower Saxony and are subject to the CC-BY-SA 4.0 law … The RuneS
    # database contains data from the Kiel Runenprojekt, the Danish
    # database runer.ku.dk and the Samnordisk runtextdatabas/Rundata
    # accessible under the Open Database License (ODbL)" — the Scandinavian
    # translations are Rundata-lineage, ODbL: an attribution + share-alike
    # grant too, so the class holds (attribution) and no override is
    # minted. The record's statement rides metadata lido_license; a record
    # whose statement is not BY-SA sends the find restricted, the TEI
    # gate's rule.
    class Runesdb < Nabu::Adapter
      ZIP_URL = "https://zenodo.org/records/21788307/files/runes_tei.zip"
      RECORD_URL = "https://doi.org/10.5281/zenodo.21788307"
      LIDO_URL = "https://www.runesdb.de/lido/%s"

      LANGUAGE = "gem"
      URN_PREFIX = "urn:nabu:runesdb:"
      TRANSLATION_SUFFIX = "-en"
      # LIDO fields that become facets beside the TEI's siglum_family:
      # facet => mined field (a list field facets every value).
      LIDO_FACETS = { "object_type" => "object_type", "classification" => "classification",
                      "material" => "material" }.freeze
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

      # The LIDO harvest lands beside the zip's flat TEI tree (the
      # declared-materializations rule). The plain tree hashes whole
      # regardless; the declaration keeps the contract explicit and
      # ZipFetch's keep: shields the dir from the zip's upstream-deletion
      # attic.
      def self.materialized_paths = [RunesdbLidoFetch::DIRNAME]

      # +translations+ arrives via SourceRegistry::Entry#build_adapter
      # (sources.yml `translations: true`); +lido_http+ / +lido_delay+ are
      # the harvest's seams (tests: a WebMock-backed connection, no pause).
      def initialize(translations: false, lido_http: nil, lido_delay: RunesdbLidoFetch::DELAY)
        super()
        @translations = translations
        @lido_http = lido_http
        @lido_delay = lido_delay
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

      # The text-bearing finds, plus (opted in) each one's -en translation
      # sibling — minted iff #parse_translation would find a real
      # rendering. Sorted by urn.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        refs = text_bearing_finds(workdir).flat_map do |id, path|
          urn = "#{URN_PREFIX}#{id}"
          base = Nabu::DocumentRef.new(source_id: manifest.id, id: urn, path: File.expand_path(path),
                                       metadata: { "find_id" => id })
          next [base] unless @translations && translated?(base)

          [base, Nabu::DocumentRef.new(source_id: manifest.id, id: "#{urn}#{TRANSLATION_SUFFIX}",
                                       path: base.path, metadata: { "find_id" => id, "kind" => "translation" })]
        end
        refs.sort_by(&:id).each(&block)
      end

      def discovery_skips(workdir)
        notes = find_files(workdir).reject { |_id, path| transliterated?(path) }.map do |_id, path|
          "#{File.basename(path)}: untransliterated find (signs recorded geometrically only, " \
            "no glyph transliteration)"
        end
        DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: 0, notes: notes)
      end

      def parse(document_ref)
        return parse_translation(document_ref) if document_ref.metadata["kind"] == "translation"

        build_document(tei(document_ref.path), document_ref)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The zip (ZipFetch, lido/ kept out of its upstream-deletion attic),
      # then the paced per-find LIDO harvest for every text-bearing find
      # (RunesdbLidoFetch — resumable; a 304 on the zip still runs it, so
      # an interrupted harvest completes on the next sync).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress, keep: [RunesdbLidoFetch::DIRNAME],
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        lido = RunesdbLidoFetch.sync!(dir: workdir, find_ids: text_bearing_finds(workdir).map(&:first),
                                      http: @lido_http || ZipFetch.default_http, delay: @lido_delay,
                                      progress: progress)
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result, lido))
      rescue ZipFetch::Error, RunesdbLidoFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "runesdb fetch failed into #{workdir}: #{e.message}"
      end

      # The -en sibling's text: the record's English translation when it is
      # a real rendering — nil for none ("-", absent) and for a restatement
      # of the reading (the TEI transliteration or the LIDO transcription,
      # whitespace-insensitive: a manuscript's single rune "m"). Public for
      # the discover/parse agreement the tests pin.
      def translation_for(document_ref)
        lido = lido_record(document_ref)
        text = lido && lido["translation_en"]
        return nil if text.nil?

        passages, _skipped = sequence_readings(tei(document_ref.path), document_ref.id)
        readings = [lido["transcription"], *passages.map { |_urn, reading, _annotations| reading }]
        squeezed = text.gsub(/\s+/, "")
        readings.compact.any? { |reading| reading.gsub(/\s+/, "") == squeezed } ? nil : text
      end

      private

      # The sibling-minting decision is #translation_for itself (the riig
      # stance): an unreadable TEI or LIDO record mints no sibling — the
      # base ref already carries the honest quarantine.
      def translated?(base_ref)
        !translation_for(base_ref).nil?
      rescue ParseError
        false
      end

      def tei(path)
        xml = Nokogiri::XML(SourceRead.utf8_file(path, label: "runesdb"))
        raise ParseError, "#{path}: not a RuneS-DB TEI find" if xml.at_xpath("/t:TEI", NS).nil?

        xml
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed TEI: #{e.message}"
      end

      # The harvested LIDO record's mined fields, nil when the find has no
      # record on disk (unharvested — the TEI-only parse).
      def lido_record(document_ref)
        find_id = document_ref.metadata["find_id"] || document_ref.id.delete_prefix(URN_PREFIX)
        path = File.join(File.dirname(document_ref.path), RunesdbLidoFetch.record_relpath(find_id))
        File.file?(path) ? RunesdbLido.read(path, find_id: find_id) : nil
      end

      # The -en sibling: one English passage, the find's title + label.
      def parse_translation(document_ref)
        base_urn = document_ref.id.delete_suffix(TRANSLATION_SUFFIX)
        base_ref = document_ref.with(id: base_urn, metadata: document_ref.metadata.except("kind"))
        text = translation_for(base_ref)
        raise ParseError, "#{document_ref.path}: no English translation for #{base_urn}" if text.nil?

        title = document_title(tei(document_ref.path))
        license = lido_record(base_ref)["lido_license"]
        document = Nabu::Document.new(
          urn: document_ref.id, language: "eng", title: title && "#{title} — English translation",
          canonical_path: document_ref.path,
          metadata: { "kind" => "translation", "translation_of" => base_urn, "license" => license }.compact,
          license_override: self.class.license_override_for(license)
        )
        document << Nabu::Passage.new(urn: "#{document_ref.id}:1", language: "eng", text: text, sequence: 0)
        document
      end

      def fetch_notes(zip, lido)
        notes = "lido=#{lido.sha[0, 12]} (#{lido.records} finds: #{lido.fetched} fetched, " \
                "#{lido.cached} on disk, #{lido.missing.size} without a record)"
        [attic_notes(zip.atticked), notes].compact.join(" · ")
      end

      # [find id, path] for the finds discover yields.
      def text_bearing_finds(workdir)
        find_files(workdir).select { |_id, path| transliterated?(path) }
      end

      # [find id, path] for every runes_find-<id>.tei.xml, sorted by urn.
      def find_files(workdir)
        files = Dir.glob(File.join(workdir, "runes_find-*.tei.xml")).filter_map do |path|
          match = FILE_PATTERN.match(File.basename(path)) or next
          [match[:id], path]
        end
        files.sort_by { |id, _path| "#{URN_PREFIX}#{id}" }
      end

      def transliterated?(path)
        SourceRead.utf8_file(path, label: "runesdb").match?(TRANSLITERATED)
      end

      def build_document(xml, document_ref)
        readings, untransliterated = sequence_readings(xml, document_ref.id)
        raise ParseError, "#{document_ref.path}: no transliterated sequence" if readings.empty?

        metadata = document_metadata(xml, document_ref)
        metadata["untransliterated_sequences"] = untransliterated if untransliterated.positive?
        lido = lido_record(document_ref)
        metadata = merge_lido(metadata, lido) if lido
        license_override = self.class.license_override_for(metadata["license"]) ||
                           (lido && self.class.license_override_for(lido["lido_license"]))
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: document_title(xml),
          canonical_path: document_ref.path, metadata: metadata, license_override: license_override
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

      # The TEI metadata wins on any shared key (none today — the LIDO
      # field names are disjoint by construction); facets merge.
      def merge_lido(metadata, lido)
        facets = (metadata["facets"] || {}).dup
        LIDO_FACETS.each do |facet, field|
          values = Array(lido[field])
          next if values.empty?

          facets[facet] = values.size == 1 ? { "value" => values.first } : { "values" => values }
        end
        metadata.merge(lido) { |_key, tei, _lido| tei }.merge("facets" => facets.empty? ? nil : facets).compact
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
