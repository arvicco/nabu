# frozen_string_literal: true

require "nokogiri"
require_relative "../fetch/file_fetch"
require_relative "source_read"

module Nabu
  module Adapters
    # The CEIPP rongorongo corpus — the transliteration code streams of the
    # 25 surviving inscribed objects of Easter Island (Rapa Nui): the
    # twenty tablets, the Santiago Staff, the two reimiro, the tangata manu
    # and the snuff box, in Thomas Barthel's numeric sign system (1958) as
    # extended and edited by the Rongorongo Commission of the C.E.I.P.P.
    # (Cercle d'Études sur l'Île de Pâques et la Polynésie — the expansion
    # as the rongorongo.org copy on the same host states it), in Philip
    # Spaelti's corpus XML on kohaumotu.org. The script is UNDECIPHERED:
    # these are sign codes, not readings.
    #
    # == License / scope
    #
    # Held under a license grant (no public license; the site's copyright
    # page: "All of these works are as far as I know under copyright …
    # Individuals wishing to use any part of the materials on this site, are
    # asked to observe the usual rules of attribution. Individuals wishing
    # to use any of these materials for commercial purposes are requested to
    # seek the copyright holders permission directly."). The terms bind the
    # adapter: the CODES ONLY — never the glyph tracings or any image
    # (Barthel/Fischer material) — non-commercial, attributed. Class `nc`;
    # `grant_required: true` guards the fetch right; the manifest +credit+
    # line (the CEIPP corpus + kohaumotu.org) rides every passage through
    # the credit seam and each document's "citation". NO bytes in the
    # public repo: fixtures live under gitignored
    # local/fixtures/ceipp-rongorongo/.
    #
    # == Grains (enumerated 2026-11-21; local fixture README)
    #
    # - xml/corpus.xml — the whole corpus, versioned in its own header
    #   (database_version 1.0.1, created 2011-12-14; "Numbering as edited by
    #   CEIPP. XML format by p.spaelti"): ACCEPTED, the one text source.
    # - xml/A.xml … Y.xml — per-tablet twins "maintained separately … it is
    #   possible for differences to creep in" (the index page): REJECTED,
    #   never fetched; one found in the workdir counts skipped-by-rule.
    # - every <glyph>'s <image> (PNG/SVG tracing references) and the
    #   image-only slots (empty code — line-start/segment-end strips and
    #   uncoded positions): REJECTED by the grant's scope. <image> is never
    #   read; an image-only slot contributes only its link mark to the line
    #   (exactly as upstream's codes-only XSL renders it) and is counted.
    # - tablets.html — the object table ("originally from the CEIPP site"):
    #   ACCEPTED as document metadata, joined by Barthel code.
    #
    # Reconciliation (whole corpus.xml, 2026-11-21): 25 tablets / 43 sides /
    # 314 lines / 17,405 glyph slots / 15,273 coded glyphs (2,132
    # image-only), against the site intro's "only 25 items with inscriptions
    # are known to remain today" — exact. The object table lists 26 rows:
    # its Z (Poike) has no tablet page and no corpus entry upstream —
    # upstream's own residue, named in discovery_skips' notes. Expected
    # first sync: 25 documents / 314 passages, 0 skipped by rule.
    #
    # == Identity / passages
    #
    # Document = object, urn:nabu:ceipp-rongorongo:<Barthel siglum> (A–Y; a
    # tablet without a readable siglum is censused unrecognized, never
    # minted from its position). Passage = line, keyed by upstream's own
    # label siglum + side + line code (…:A:Aa01 — the dt the codes-only
    # XSL prints). Text = that XSL's rendering verbatim: each glyph's
    # code/ceipp followed by its link (CEIPP marks: - juxtaposed, . linked,
    # : stacked, ; linked stacking, * end of line, … a break; `_` an
    # unreadable slot, ? uncertain, ! illegible, (nnn-nnn) a worn run's
    # estimate) — never cleaned. Each coded glyph rides the passage's
    # "tokens" ({form, link, loc = seg-num.glyph-num}) so the code/link
    # boundary the flat string blurs ("522_*") stays recoverable.
    #
    # == Mining (the aggressive-mining rule)
    #
    # From the corpus: sides (code, name, line count), slot/coded/
    # image-only counts, the header's version and creation date. From the
    # object table: material (its Orliac 2010 footnote verbatim as
    # material_note), dimensions (length/width/thickness verbatim — the
    # table states no unit; millimetres by magnitude, DECLARED unstated),
    # upstream's own line and sign counts (lines_stated/signs_stated,
    # verbatim, never reconciled against the corpus), condition, the
    # tablet page URL, and the table's name when it differs from the
    # corpus's (catalogue_name: "Honolulu 4 [#445]"). No date and no place
    # is carried per object — the dating/places postures say so.
    #
    # == Lect / script
    #
    # Language rap, the registry anchor whose own note warns that the
    # tablets writing Rapa Nui "is the default assumption, not a
    # demonstrated fact" — the lect_overrides row carries that claim at
    # tier approximation. The held bytes are Latin-alphabet/numeric CEIPP
    # codes; the ARTIFACT script is rongorongo (ISO 15924 Roro, unencoded
    # in Unicode). The registry scripts table carries no roro tag yet, so
    # the config/artifact_scripts.yml row is queued on that registry mint.
    #
    # == fetch / sync policy
    #
    # Two FileFetch GETs over plain http (the host's TLS certificate expired
    # 2018-06-27), one subdirectory each (corpus/, tablets/), two-phase with
    # sha256 pins measured at acquisition: drift aborts BEFORE the tree
    # mutates — a re-pin is an owner decision. The site is dormant (corpus
    # Last-Modified 2018-03-28); sync_policy manual.
    class CeippRongorongo < Nabu::Adapter
      SLUG = "ceipp-rongorongo"
      LANGUAGE = "rap"
      URN_PREFIX = "urn:nabu:ceipp-rongorongo:"
      BASE_URL = "http://kohaumotu.org/Rongorongo/"
      CORPUS_URL = "#{BASE_URL}xml/corpus.xml".freeze
      TABLETS_URL = "#{BASE_URL}tablets.html".freeze

      CORPUS = "corpus"
      TABLETS = "tablets"
      FILES = {
        CORPUS => { url: CORPUS_URL, filename: "corpus.xml" },
        TABLETS => { url: TABLETS_URL, filename: "tablets.html" }
      }.freeze

      # sha256 of each file, measured at acquisition 2026-11-21.
      PINS = {
        CORPUS => "4aee2361a367fbed5ffba0b77c50e0ef3c055a35ee2499f66a757a903e61e627",
        TABLETS => "87a3273e1b2d9b488d808bf5e8a49db0dac97f518ccc21bb0dad2e83b4b3dabd"
      }.freeze

      FRAGMENT = %r{<tablet>.*?</tablet>}m
      HEADER = %r{<header>.*?</header>}m
      SIGLUM = /\A[A-Z]\z/
      TWIN = %r{\A(?:.*/)?[A-Z]\.xml\z}

      CREDIT = "Rongorongo corpus — Thomas Barthel's numbering as edited by the C.E.I.P.P. " \
               "(Cercle d'Études sur l'Île de Pâques et la Polynésie), XML format by P. Spaelti; " \
               "kohaumotu.org (#{BASE_URL})".freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "CEIPP rongorongo corpus — the Barthel-code transliteration of the Easter Island " \
              "inscriptions (kohaumotu.org)",
        license: "restricted: the transliteration codes only — never the glyph tracings or any image; " \
                 "non-commercial use; the CEIPP corpus and kohaumotu.org credited wherever displayed. " \
                 "Upstream's copyright notice, verbatim: \"Individuals wishing to use any part of the " \
                 "materials on this site, are asked to observe the usual rules of attribution. Individuals " \
                 "wishing to use any of these materials for commercial purposes are requested to seek the " \
                 "copyright holders permission directly.\" Cite: #{CREDIT}",
        license_class: "nc",
        upstream_url: BASE_URL,
        parser_family: "ceipp-xml",
        credit: CREDIT
      )

      Row = Data.define(:name, :material, :material_note, :dimensions, :lines, :signs, :condition, :page_url)

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        FILES.map do |stem, spec|
          Nabu::Adapter::HttpProbeTarget.new(label: spec.fetch(:filename), zip_url: spec.fetch(:url),
                                             metadata_url: nil, state_subdir: stem,
                                             state_file: Nabu::FileFetch::STATE_FILE)
        end
      end

      # +pins+ exists for the WebMock'd fetch tests — real syncs keep PINS.
      def initialize(pins: PINS)
        super()
        @pins = pins
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = file_path(workdir, CORPUS)
        return unless File.file?(path)

        fragments(path).each_with_index do |fragment, index|
          siglum = siglum_of(fragment) or next

          block.call(Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{siglum}", path: path,
                                           metadata: { "index" => index }))
        end
      end

      # The census: siglum-less tablets (unrecognized), per-tablet twins
      # (skipped by rule), any other stray file (unrecognized), plus the
      # image-only slot count and the object table's corpus-less rows.
      def discovery_skips(workdir)
        return DiscoverySkips.new unless File.directory?(workdir)

        notes = []
        unrecognized = []
        twins = 0
        stray_files(workdir).each do |rel|
          if TWIN.match?(rel)
            twins += 1
            notes << "#{rel}: a per-tablet XML twin — the corpus file is the versioned whole"
          else
            unrecognized << "#{rel}: unrecognized file in the CEIPP tree"
          end
        end
        corpus_census(workdir, notes, unrecognized)
        DiscoverySkips.new(skipped_by_rule: twins, unrecognized: unrecognized.size, notes: notes + unrecognized)
      end

      def parse(document_ref)
        fragment = fragments(document_ref.path)[document_ref.metadata.fetch("index")] or
          raise Nabu::ParseError, "#{document_ref.id}: tablet fragment vanished (stale ref?)"
        tablet = parse_fragment(fragment, document_ref.id)
        siglum = siglum_of(fragment)
        row = table_rows(document_ref.path).fetch(siglum, nil)
        build_document(document_ref, tablet, siglum, row)
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      # Two GETs, two-phase: prepare holds both bodies, the pins verify
      # them, the breaker sees the doomed set, then both complete.
      def fetch(workdir, progress: nil, force: false)
        fetches = FILES.to_h do |stem, spec|
          [stem, Nabu::FileFetch.new(url: spec.fetch(:url), dir: File.join(workdir, stem),
                                     filename: spec.fetch(:filename),
                                     attic_dir: File.join(workdir, ATTIC_DIRNAME, stem), progress: progress)]
        end
        fetches.each_value(&:prepare!)
        fetches.each { |stem, fetch| verify_pin!(stem, fetch) }
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        notes = ["corpus.xml #{fetches.fetch(CORPUS).sha[0, 12]} + tablets.html sha256 pins verified",
                 attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
        Nabu::FetchReport.new(sha: fetches.fetch(CORPUS).sha, fetched_at: Time.now, notes: notes)
      rescue Nabu::FileFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def file_path(workdir, stem) = File.expand_path(File.join(workdir, stem, FILES.fetch(stem).fetch(:filename)))

      def verify_pin!(stem, fetch)
        return if fetch.sha == @pins.fetch(stem)

        raise Nabu::FetchError,
              "#{SLUG}: #{FILES.fetch(stem).fetch(:filename)} drifted — fetched sha256 #{fetch.sha} != pinned " \
              "#{@pins.fetch(stem)}; the site has been dormant since 2018 — review upstream and re-pin " \
              "(owner decision)"
      end

      # Every file under the workdir that is neither one of the two fetch
      # targets nor fetch machinery (state files, the attic).
      def stray_files(workdir)
        expected = FILES.map { |stem, spec| File.join(stem, spec.fetch(:filename)) }
        Dir.glob("**/*", File::FNM_DOTMATCH, base: workdir).sort.reject do |rel|
          !File.file?(File.join(workdir, rel)) || rel.split("/").first == ATTIC_DIRNAME ||
            File.basename(rel) == Nabu::FileFetch::STATE_FILE || expected.include?(rel)
        end
      end

      def corpus_census(workdir, notes, unrecognized)
        path = file_path(workdir, CORPUS)
        return unless File.file?(path)

        sigla = []
        image_only = 0
        fragments(path).each_with_index do |fragment, index|
          siglum = siglum_of(fragment)
          siglum ? sigla << siglum : unrecognized << "tablet #{index + 1}: no readable Barthel siglum — never minted"
          image_only += fragment.scan(%r{<ceipp>\s*</ceipp>|<ceipp/>}).size
        end
        if image_only.positive?
          notes << "#{image_only} image-only glyph slots (tracing references without a code) dropped — codes only"
        end
        table_residue(workdir, sigla).each { |note| notes << note }
      end

      def table_residue(workdir, sigla)
        return [] unless File.file?(file_path(workdir, TABLETS))

        missing = table_rows(file_path(workdir, CORPUS)).except(*sigla)
        missing.map do |code, row|
          "#{code} (#{row.name}): listed in the object table, no transliteration in the corpus upstream"
        end
      end

      # Raw-byte tablet spans, cached per [path, mtime] (the ociana cut —
      # corpus.xml is 5.6 MB, so no whole-file DOM).
      def fragments(path)
        key = [path, File.mtime(path)]
        return @fragments_cache if defined?(@fragments_key) && @fragments_key == key

        raw = SourceRead.utf8_file(path, label: "#{SLUG} corpus.xml")
        @header = header_fields(raw[HEADER])
        @fragments_key = key
        @fragments_cache = raw.scan(FRAGMENT)
      end

      def header_fields(xml)
        return {} if xml.nil?

        header = Nokogiri::XML(xml, &:strict).root
        { "database_version" => header.at_xpath("database_version")&.text,
          "database_created" => header.at_xpath("date_of_creation")&.text }.reject { |_, v| v.to_s.strip.empty? }
      rescue Nokogiri::XML::SyntaxError
        {}
      end

      def siglum_of(fragment)
        siglum = fragment[%r{<tablet-code>(.*?)</tablet-code>}m, 1].to_s.strip
        SIGLUM.match?(siglum) ? siglum : nil
      end

      def parse_fragment(fragment, urn)
        Nokogiri::XML(fragment, &:strict).root
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{urn}: malformed tablet XML (#{e.message.lines.first&.strip})"
      end

      # {Barthel code => Row} from the object table beside the corpus.
      def table_rows(corpus_path)
        path = File.join(File.dirname(corpus_path), "..", TABLETS, FILES.fetch(TABLETS).fetch(:filename))
        path = File.expand_path(path)
        unless File.file?(path)
          raise Nabu::ParseError, "#{SLUG}: #{path} missing — the object table (tablets.html) is part of the fetch"
        end

        key = [path, File.mtime(path)]
        return @rows_cache if defined?(@rows_key) && @rows_key == key

        @rows_key = key
        @rows_cache = read_table(path)
      end

      def read_table(path)
        html = Nokogiri::HTML(SourceRead.utf8_file(path, label: "#{SLUG} tablets.html"))
        note = html.at_xpath("//a[@name='note1']/parent::p")&.text.to_s.sub(/\A\s*1\.\s*/, "").strip
        html.xpath("//table[@id='tablet_info']//tr[td]").to_h do |tr|
          cells = tr.xpath("td")
          [clean(cells[0]), table_row(cells, note)]
        end
      end

      def table_row(cells, note)
        footnoted = cells[2].at_xpath(".//a[@class='ref']")
        dimensions = { "length" => cells[3], "width" => cells[4], "thickness" => cells[5] }
                     .transform_values { |cell| clean(cell) }.reject { |_, v| v.nil? || v == "n/a" }
        href = cells[1].at_xpath(".//a/@href")&.value
        Row.new(name: clean(cells[1]), material: clean(cells[2], drop_refs: true),
                material_note: footnoted && !note.empty? ? Normalize.nfc(note) : nil,
                dimensions: dimensions, lines: clean(cells[6]), signs: clean(cells[7]),
                condition: clean(cells[8]), page_url: href && "#{BASE_URL}#{href}")
      end

      def clean(cell, drop_refs: false)
        return nil if cell.nil?

        cell = cell.dup.tap { |copy| copy.xpath(".//a[@class='ref']").each(&:remove) } if drop_refs
        text = cell.text.gsub(/\s+/, " ").strip
        text.empty? ? nil : Normalize.nfc(text)
      end

      def build_document(document_ref, tablet, siglum, row)
        name = Normalize.nfc(tablet.at_xpath("tablet-name").text.strip)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: "#{name} (#{siglum})", metadata: metadata_for(tablet, siglum, name, row)
        )
        tablet.xpath("side").each do |side|
          side.xpath("line").each { |line| document << line_passage(document, siglum, side, line) }
        end
        raise Nabu::ParseError, "#{document_ref.id}: no lines" if document.empty?

        document
      end

      def line_passage(document, siglum, side, line)
        side_code = side.at_xpath("side-code").text.strip
        label = "#{siglum}#{side_code}#{line.at_xpath('line-code').text.strip}"
        glyphs = line.xpath("glyph")
        text = glyphs.map { |glyph| code(glyph) + link(glyph) }.join
        raise Nabu::ParseError, "#{document.urn}: line #{label} renders no code" if text.strip.empty?

        tokens = glyphs.reject { |glyph| code(glyph).empty? }.map do |glyph|
          { "form" => code(glyph), "link" => link(glyph),
            "loc" => "#{glyph.at_xpath('loc/seg-num').text}.#{glyph.at_xpath('loc/glyph-num').text}" }
        end
        annotations = { "citation" => label, "side" => side_code,
                        "side_name" => Normalize.nfc(side.at_xpath("side-name").text.strip),
                        "line" => Integer(line.at_xpath("line-num").text, 10), "tokens" => tokens }
        image_only = glyphs.size - tokens.size
        annotations["image_only_slots"] = image_only if image_only.positive?
        Nabu::Passage.new(urn: "#{document.urn}:#{label}", language: LANGUAGE, text: Normalize.nfc(text),
                          sequence: document.size, annotations: annotations)
      end

      def code(glyph) = Normalize.nfc(glyph.at_xpath("code/ceipp")&.text.to_s)

      def link(glyph) = Normalize.nfc(glyph.at_xpath("link")&.text.to_s)

      def metadata_for(tablet, siglum, name, row)
        glyphs = tablet.xpath("side/line/glyph")
        coded = glyphs.count { |glyph| !code(glyph).empty? }
        meta = {
          "siglum" => siglum, "name" => name,
          "sides" => tablet.xpath("side").map do |side|
            { "code" => side.at_xpath("side-code").text.strip,
              "name" => Normalize.nfc(side.at_xpath("side-name").text.strip), "lines" => side.xpath("line").size }
          end,
          "glyph_slots" => glyphs.size, "coded_glyphs" => coded, "image_only_slots" => glyphs.size - coded,
          "citation" => CREDIT
        }.merge(@header || {})
        meta.merge(row_metadata(row, name))
      end

      def row_metadata(row, name)
        return {} if row.nil?

        { "catalogue_name" => row.name == name ? nil : row.name, "material" => row.material,
          "material_note" => row.material_note, "dimensions" => row.dimensions.empty? ? nil : row.dimensions,
          "lines_stated" => row.lines, "signs_stated" => row.signs, "condition" => row.condition,
          "page_url" => row.page_url }.compact
      end
    end
  end
end
