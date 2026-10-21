# frozen_string_literal: true

require_relative "senie_tei_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # The SENIE adapter: the Corpus of Early Written Latvian ("Senie:
    # latviešu valodas seno tekstu korpuss" — AiLab IMCS UL with the
    # Latvian Language Institute and the Faculty of Humanities, University
    # of Latvia; CLARIN-LV hdl:20.500.12574/141, issued 2025-11-27). The
    # written Latvian of the 16th–18th centuries as printed and copied:
    # the earliest Lord's-prayer specimens (Gisbert 1507, Grunau 1520),
    # the 1585 Catholic catechism and the 1586/1587 Lutheran Enchiridion
    # and Gospels-and-Epistles, Mancelius' Lettus and Phraseologia (1638)
    # and his postil (1654), Elger's Catholic hymnal and gospels, Glück's
    # Bible (New Testament 1685, Old Testament 1689–94, Apocrypha 1689),
    # the 17th-c. manuscript dictionaries (Fürecker, Langius), oaths and
    # guild statutes, and the Enlightenment prints of the Stenders.
    # 3,236,079 tokens / 2,363,483 words (the deposit's own count), the
    # Latvian interleaved with German, Latin and some Polish, Estonian,
    # Greek and Aramaic, each run language-tagged upstream.
    #
    # == Upstream and grains
    #
    # The CLARIN-LV item serves four bitstreams (census 2026-10-21):
    #   SENIE_Unicode.tei.xml.zip  (8.81 MB → one 61 MB TEI P5 file) —
    #       THE ASSET: a <teiCorpus> of 186 <TEI> elements
    #   SENIE_Unicode_unhyphened.tei.xml.zip  — the same corpus with
    #       line-break hyphenation contracted by machine; rejected: the
    #       contraction also rewrites <sic> spans across the break (AP1622
    #       p. 6: "ayz- / ayz ledz" became <sic>ayzayz ledz</sic>), and the
    #       line-faithful file already carries what the contraction would
    #       give (the search form rejoins, SenieTeiParser.search_source)
    #   Senie-DSL-plaintext.zip  — the legacy @-coded plaintext the TEI
    #       was converted from (2017); rejected: superseded by the TEI
    #   docs.zip  — metadata.ods (the source catalog: id, name, author,
    #       order, year, genre, subgenre, manuscript) and
    #       codes-explained.ods (the @-code legend); not fetched: every
    #       catalog field but the in-collection order is in the TEI
    #       headers, and the legend documents the DSL encoding
    # Inside the asset, the <TEI> grain is two-level: 102 top-level TEIs
    # (the deposit's "102 sources") of which three are CONTAINERS —
    # Apokr1689 (14 books), JT1685 (30), VD1689_94 (40) — whose child TEIs
    # carry the text. THE DOCUMENT is each text-bearing leaf TEI: 99
    # top-level leaves + 84 container children = 183 documents. The three
    # containers are skipped by rule (counted in discovery_skips); their
    # header (title, e.g. "Tas Jauns Testaments") rides on each child as
    # "collection_title".
    #
    # == Reconciliation (fixture-time census of the 2025-11-27 asset)
    #
    # Upstream advertises 102 sources (the item description; metadata.ods
    # lists the same 102 plus the 84 container children, 186 rows).
    # Accepted 183 leaf documents + 3 containers skipped by rule = 186
    # TEIs = the catalog's 186 rows; 99 + 3 = the 102 sources. Residue 0.
    # (First real sync pending — the gate re-states these counts.)
    #
    # == Reading one document out of one file
    #
    # discover scans the file's bytes once for the <TEI>/</TEI> tags
    # (nesting depth ≤ 2, no attributes on TEI — censused) and records each
    # leaf's byte range; parse slices that range and walks it with the
    # senie-tei family. The file is read once per adapter instance
    # (memoized by path + size + mtime), never re-read per document.
    #
    # == Identity
    #
    #   document urn  urn:nabu:senie:<id>   (fileDesc id lowercased, the
    #                 container separator "::" read "." —
    #                 urn:nabu:senie:ap1622, urn:nabu:senie:jt1685.2j)
    #   passage urn   <document urn>:<citation>  (p.6 · 1.1 · s.5.6 ·
    #                 1.head · front — see SenieTeiParser)
    #
    # == License
    #
    # CC BY-SA 4.0. The CLARIN-LV item page, verbatim: "This item is
    # Publicly Available and licensed under: Creative Commons -
    # Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)" (rights
    # URI creativecommons.org/licenses/by-sa/4.0/). Share-alike → class
    # attribution (the glaux/scat precedent).
    #
    # == Axes (the aggressive-mining policy)
    #
    # date — the header <date> (the print's or manuscript's year: "1622";
    # a span as "1681_90" / "1650_70" / "1643_44" / "1689_94" → its
    # envelope) on every document, the artifact date (:structured).
    # genre — the header <domain> text ("Garīgie teksti; Bībele, Vecā
    # Derība": upstream's genre; subgenre), projected as the genre facet
    # and folded in config/kind_map.yml; its @type (religious/public/
    # education) rides as domain_type. medium — <chanel>manuscript</chanel>
    # (13 TEIs) → "manuscript", else "print". author — the header author,
    # Latvianized as upstream writes it ("Georgs Mancelis"); "nezināms"
    # (unknown) rides as no author. lect — the per-run language tags make
    # every passage's language its majority run language (lv for nearly
    # all; a German preface page reads de); the Old Latvian stage is a
    # registry candidate (postures.yml). places — the asset names no
    # imprint or writing place (the titles' "BRVNSBERGAE"-style imprints
    # stay inside the page text) — unplaced, declared.
    #
    # == fetch / sync policy
    #
    # One public bitstream over HTTPS (Nabu::ZipFetch). A CLARIN deposit
    # version is frozen → sync_policy manual; a new version is a new
    # handle/bitstream.
    class Senie < Nabu::Adapter
      ZIP_URL = "https://repository.clarin.lv/repository/xmlui/bitstream/handle/20.500.12574/141/" \
                "SENIE_Unicode.tei.xml.zip?sequence=2&isAllowed=y"
      CORPUS_FILE = "SENIE_Unicode.tei.xml"
      URN_PREFIX = "urn:nabu:senie:"
      UNKNOWN_AUTHOR = "nezināms"
      HEADER_END = "</teiHeader>".b.freeze
      HEADER_FIELDS = {
        "author" => %r{<author>(.*?)</author>}m, "title" => %r{<title>(.*?)</title>}m,
        "date" => %r{<date>(.*?)</date>}m, "channel" => %r{<chanel>(.*?)</chanel>}m
      }.freeze
      # Ref metadata that never reaches the Document (the read coordinates;
      # the title rides as Document#title).
      DOCUMENT_ONLY = %w[byte_offset byte_length title].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "senie",
        name: "SENIE — the Corpus of Early Written Latvian (AiLab IMCS UL / Latvian Language Institute, " \
              "University of Latvia)",
        license: "CC BY-SA 4.0 (CLARIN-LV item hdl:20.500.12574/141: \"This item is Publicly Available and " \
                 "licensed under: Creative Commons - Attribution-ShareAlike 4.0 International (CC BY-SA " \
                 "4.0)\"); credit The Corpus of Early Written Latvian (2025), AiLab IMCS UL and the Latvian " \
                 "Language Institute, University of Latvia (Andronova, Baltiņa, Frīdenberga, Grūzītis et al.)",
        license_class: "attribution",
        upstream_url: "https://hdl.handle.net/20.500.12574/141",
        parser_family: "senie-tei"
      )

      # One TEI element of the corpus file: its fileDesc id, byte range,
      # header fields, and whether it is a container (holds child TEIs).
      Tei = Data.define(:id, :offset, :length, :header, :parent, :container)

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "SENIE_Unicode.tei.xml.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # One ref per text-bearing leaf TEI, sorted by urn.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        teis = scan(workdir)
        by_id = teis.to_h { |tei| [tei.id, tei] }
        teis.reject(&:container).map { |tei| ref(workdir, tei, by_id) }.sort_by(&:id).each(&block)
      end

      # The three Bible containers skip by rule; nothing else is skipped.
      def discovery_skips(workdir)
        containers = scan(workdir).select(&:container)
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: containers.size,
          notes: containers.map { |tei| "container TEI (its books are the documents): #{tei.id}" }
        )
      end

      def parse(document_ref)
        meta = document_ref.metadata
        bytes = SourceRead.slice(corpus_bytes(document_ref.path), offset: meta.fetch("byte_offset"),
                                                                  length: meta.fetch("byte_length"),
                                                                  what: "#{document_ref.path}: TEI #{meta['senie_id']}")
        xml = SourceRead.utf8(bytes, label: "senie: #{meta['senie_id']}")
        units = parser.units(xml, path: document_ref.path)
        build_document(document_ref, units)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path} (#{meta['senie_id']}): #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress, guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "senie fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        @parser ||= SenieTeiParser.new
      end

      # The corpus file's bytes, memoized per (path, size, mtime).
      def corpus_bytes(path)
        stat = File.stat(path)
        key = [path, stat.size, stat.mtime.to_f]
        return @bytes if @bytes_key == key

        @bytes_key = key
        @bytes = SourceRead.utf8_file(path, label: "senie").b
      end

      def corpus_path(workdir)
        File.join(workdir, CORPUS_FILE)
      end

      # Every <TEI> element of the corpus file, document order.
      def scan(workdir)
        path = corpus_path(workdir)
        return [] unless File.file?(path)

        bytes = corpus_bytes(path)
        teis = []
        stack = []
        bytes.scan(%r{<TEI>|</TEI>}n) do
          match = Regexp.last_match
          if match[0] == "<TEI>"
            stack.push([match.begin(0), []])
          else
            start, children = stack.pop
            raise ParseError, "#{path}: unbalanced </TEI> at byte #{match.begin(0)}" if start.nil?

            finish = match.end(0)
            tei = tei_at(bytes, start, finish, children, path)
            stack.last[1] << tei.id unless stack.empty?
            teis << tei
          end
        end
        raise ParseError, "#{path}: #{stack.size} unclosed <TEI>" unless stack.empty?

        assign_parents(teis)
      end

      def tei_at(bytes, start, finish, children, path)
        stop = bytes.index(HEADER_END, start)
        raise ParseError, "#{path}: the <TEI> at byte #{start} has no teiHeader" if stop.nil? || stop > finish

        slice = SourceRead.slice(bytes, offset: start, length: stop - start, what: "#{path}: TEI header")
        head = SourceRead.utf8(slice, label: "senie header")
        header = header_fields(head)
        raise ParseError, "#{path}: a <TEI> at byte #{start} has no fileDesc id" if header["id"].nil?

        Tei.new(id: header["id"], offset: start, length: finish - start, header: header,
                parent: children, container: !children.empty?)
      end

      # Children were collected on the parent; turn them into parent links.
      def assign_parents(teis)
        parents = {}
        teis.each { |tei| tei.parent.each { |child| parents[child] = tei.id } }
        teis.map { |tei| tei.with(parent: parents[tei.id]) }.sort_by(&:offset)
      end

      # +header+ is the TEI's own teiHeader (up to its close tag).
      def header_fields(header)
        fields = { "id" => header[/fileDesc id="([^"]*)"/, 1] }
        HEADER_FIELDS.each { |key, pattern| fields[key] = header[pattern, 1]&.strip }
        domain = header.match(%r{<domain type="([^"]*)">(.*?)</domain>}m)
        fields["domain_type"] = domain && domain[1]
        fields["genre"] = domain && domain[2].strip
        fields.transform_values { |value| value && Normalize.nfc(value) }
      end

      def ref(workdir, tei, by_id)
        Nabu::DocumentRef.new(source_id: MANIFEST.id, id: urn(tei.id),
                              path: File.expand_path(corpus_path(workdir)),
                              metadata: ref_metadata(tei, by_id[tei.parent]))
      end

      def urn(id)
        "#{URN_PREFIX}#{id.downcase.gsub('::', '.')}"
      end

      def ref_metadata(tei, container)
        header = tei.header
        meta = { "senie_id" => tei.id, "byte_offset" => tei.offset, "byte_length" => tei.length,
                 "medium" => header["channel"] == "manuscript" ? "manuscript" : "print" }
        meta["title"] = header["title"] if header["title"]
        meta["author"] = header["author"] if header["author"] && header["author"] != UNKNOWN_AUTHOR
        meta["genre"] = header["genre"] if header["genre"]
        meta["domain_type"] = header["domain_type"] if header["domain_type"]
        date = header_date(header["date"])
        meta["date"] = date if date
        if container
          meta["collection_id"] = container.id
          meta["collection_title"] = container.header["title"] if container.header["title"]
        end
        meta
      end

      # "1622" → {1622, 1622}; "1681_90" → {1681, 1690} (the decade-tail
      # span convention); anything else rides raw only.
      def header_date(raw)
        return nil if raw.nil? || raw.empty?

        case raw
        when /\A(\d{4})\z/
          year = Integer(Regexp.last_match(1), 10)
          { "not_before" => year, "not_after" => year, "raw" => raw }
        when /\A(\d{4})_(\d{2})\z/
          from = Integer(Regexp.last_match(1), 10)
          to = ((from / 100) * 100) + Integer(Regexp.last_match(2), 10)
          { "not_before" => from, "not_after" => to, "raw" => raw }
        else
          { "raw" => raw }
        end
      end

      def build_document(document_ref, units)
        meta = document_ref.metadata
        totals = units.each_with_object(Hash.new(0)) do |unit, sum|
          unit.annotations["languages"].each { |code, count| sum[code] += count }
        end
        language = totals.min_by { |code, count| [-count, code] }&.first || "lv"
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, canonical_path: document_ref.path,
          title: meta["title"] || meta["senie_id"],
          metadata: meta.except(*DOCUMENT_ONLY).merge("languages" => totals.sort.to_h)
        )
        units.each_with_index do |unit, sequence|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{unit.citation}", language: unit.language, text: unit.text,
            text_normalized: Normalize.search_form(SenieTeiParser.search_source(unit.text, unit.annotations),
                                                   language: unit.language),
            annotations: unit.annotations, sequence: sequence
          )
        end
        raise ParseError, "#{document_ref.path} (#{meta['senie_id']}): no text-bearing unit" if document.empty?

        document
      end
    end
  end
end
