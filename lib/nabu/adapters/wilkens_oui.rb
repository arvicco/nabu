# frozen_string_literal: true

require "fileutils"
require_relative "../normalize"
require_relative "../shell"
require_relative "../file_fetch"
require_relative "../stext_layout"
require_relative "../wilkens_oui"

module Nabu
  module Adapters
    # Jens Wilkens, Handwörterbuch des Altuigurischen. Altuigurisch –
    # Deutsch – Türkisch / Eski Uygurcanın El Sözlüğü (Göttingen:
    # Universitätsverlag Göttingen, 2021; DOI 10.17875/gup2021-1590) — the
    # Old Uyghur dictionary of the Göttingen Academy's Old Uyghur project:
    # the whole attested vocabulary of the Turfan/Dunhuang manuscripts,
    # block prints and inscriptions (Buddhist, Manichaean, Christian;
    # Uyghur, Manichaean, Brāhmī, Tibetan and runic scripts), each word
    # glossed in German and Turkish, with collocations and word pairs filed
    # under their first element and rejected readings of the editions
    # marked †. A born-digital PDF; segmentation is Nabu::WilkensOui over
    # the positioned, styled text layer (Nabu::StextLayout).
    #
    # == Upstream and grains
    #
    # Upstream serves ONE file: the whole book as a single 946-page PDF
    # (the cover JPEG and METS record beside it on the handle page are
    # metadata). Inside it, three grains:
    #   front matter  PDF pp. 1–16 (title, license page, Danksagung,
    #                 Vorbemerkungen, Hinweise zur Benutzung,
    #                 Abkürzungen, Symbole — roman folios or none)
    #   the body      PDF pp. 17–945 = printed folios 1–929 — THE GRAIN
    #   back cover    PDF p. 946 (blurb + ISBN, no folio)
    # The rule that separates them is the printed folio: a page whose
    # bottom band carries an arabic folio is dictionary body; a page
    # without one is front/back matter, the REJECTED grain (17 pages),
    # skipped by rule and counted in discovery_skips' notes. The document
    # is the PDF; the record grain is the dictionary ENTRY.
    #
    # == Reconciliation (the full book, measured 2026-10-22)
    #
    # 946 pages = 929 body pages + 17 matter pages. The segmenter yields
    # 49,621 records over the body (29,873 main entries + 19,748
    # sub-entries) — upstream advertises no entry count of its own, so the
    # cross-checks are the folio run (1–929, contiguous) and the gloss
    # split (99.99 % of glossed records carry both halves). Of the
    # 49,621: 49,619 ACCEPTED as entries + 2 SKIPPED BY RULE (records the
    # segmenter closed with an empty headword — a Hebrew etymon wrapped
    # onto an indent line under bidilhim, folio 169; a sub-entry led by a
    # roman "(auch mit Dat.)" under yala, folio 856; both stay readable
    # in the canonical PDF and are named in discovery_skips' notes).
    # 49,619 + 2 = 49,621 (29,873 main + 19,746 sub entries). Ids: 22
    # keys recur and take the positional ":2" suffix.
    #
    # Known residue, carried and declared (never "fixed" at parse):
    # - 1,355 records carry U+FFFD where Chinese characters stood — the
    #   book sets them in a font without a ToUnicode map, so the text
    #   layer cannot yield them. Each such entry carries the annotation
    #   text_layer_loss (the U+FFFD count). Recovery (rendering the glyphs
    #   or keying them from the printed page) is an ENRICHMENT, not a
    #   parse fix.
    # - 3 glossed records lack the "||" German/Turkish separator: served
    #   whole in the body, gloss nil, annotation shape "unsplit".
    # - 2 sub-entries open without an italic head and 2 lines sit at
    #   unexpected positions (the segmenter census, in the notes).
    # - doubled-letter typos and the 0.65 % alphabetical-order residue are
    #   the printed book's own (upstream collation), kept as printed.
    #
    # == Entry shape (dictionary slug wilkens-oui, language oui)
    #
    # - entry_id: main = "^<homonym>" + headword as printed ("^1a",
    #   "amramak", "amranmaklıg ~ amranmak(lıg)"); sub-entry =
    #   "<parent id>::<phrase>" ("^3a::a bašlap v tägi"); a recurring key
    #   takes ":<n>" in book order (stable while the pinned PDF is).
    # - headword: the bold (main) or italic (sub) head as printed;
    #   headword_folded: the generic fold of its FIRST variant (before
    #   " ~ ") with editorial brackets/marks and hyphens dropped
    #   (t(ä)ŋri → taŋri; amran- → amran).
    # - gloss: the first German sense; body: the printed record, then
    #   the German and Turkish halves on their own lines, then the
    #   printed page ("p. 44, left column" — the citation grain).
    # - annotations: entry_kind (main/sub), homonym, parent, page,
    #   column, german, turkish, labels (the book's (m) (c) (br) (r)
    #   (tib) (p) script/tradition marks and grammar labels), shape
    #   (glossed / cross-reference / note / unsplit), rejected_reading
    #   (the † class: 6,817 records), cross_reference (the → target
    #   text verbatim: 9,592 records), text_layer_loss, and the entry-facet
    #   pair tradition / script (below).
    # - Entry facets (config/facet_map.yml entry_fields): the six
    #   tradition/script marks are mapped by MARK_FACETS per the book's
    #   own Abkürzungen list (PDF pp. 13–14, folios VII–VIII) and its
    #   Hinweise (pp. 10–11): Buddhist terms go UNMARKED ("manichäische
    #   Termini [erhalten] den Vermerk (m), christliche ein (c)"); (br) and
    #   (tib) flag sources in Brāhmī / Tibetan script where the
    #   orthography deviates or the word is rare. So an unmarked entry
    #   claims nothing — never "Buddhist" by default. Every other label
    #   (grammar, n. pr. …) stays in "labels" unmapped, counted in the
    #   census notes. Whole book (2026-10-28): tradition Manichaean 611 ·
    #   Christian 119; script Brāhmī 498 · runic 200 · Tibetan 41 ·
    #   ʾPhags-pa 1; 12,972 labels of 11 other kinds unmapped.
    # - crossrefs: a sub-entry points at its parent (kind "subentry-of",
    #   id-keyed — the shuowen chongwen-of shape); a cross-reference
    #   record mints one pointer per "→" link (kind "false-reading" for
    #   a †-record's first link — the book's "fehlerhafte Lesung" — and
    #   "see" otherwise). A homonym-numbered target ("^1av") is id-keyed
    #   to that main entry when the book holds it; any other target is
    #   headword-keyed (folded) and resolves only when unique. Measured
    #   (in-memory load of the whole book): 19,746 subentry-of pointers,
    #   all resolved; 10,194 → pointers (5,627 false-reading + 4,567
    #   see; 1,735 of them id-keyed), 9,020 resolved — the rest name
    #   forms the book files under no unique headword. "→" inside glossed
    #   prose (~2,260 further records) stays body text.
    # - Not split (yet): the leading etymology chain ("< TochB jñāpake <
    #   Skt. jñāpaka") rides the head of the German half; the boundary
    #   is an italic-run signal the segmenter does not yet carry into its
    #   records — a recorded follow-up, never a regex guess.
    #
    # == License
    #
    # CC BY-SA 4.0 — the publisher's handle page (read 2026-10-22) and the
    # book's own license page (PDF p. 3, verbatim: "Dieses Werk ist
    # lizenziert unter einer Creative Commons Namensnennung - Weitergabe
    # unter gleichen Bedingungen 4.0 International Lizenz.") →
    # attribution with the share-alike rider (the VKS precedent).
    #
    # == fetch / sync policy
    #
    # One FileFetch of the PDF (~10 MB), sha256-verified against the pin
    # BEFORE the tree mutates (the baxter-sagart choreography). A
    # published book → sync_policy manual; a new printing is an owner
    # re-pin. Parse runs mutool's stext extraction in CHUNK_PAGES-page
    # slices fed through ONE segmenter in page order (measured ~45 s for
    # the whole book), so a record crossing a chunk seam stays whole.
    class WilkensOui < Nabu::Adapter
      PDF_URL = "https://univerlag.uni-goettingen.de/bitstream/handle/3/isbn-978-3-86395-481-9/" \
                "Wilkens_handwoerterbuch.pdf?sequence=4&isAllowed=y"
      PDF_NAME = "Wilkens_handwoerterbuch.pdf"
      PDF_SHA256 = "4f61ac8db2a7cd5a60f3b454b0524b1c598de6e6e9681008576f84087e383c94"
      DICTIONARY_SLUG = "wilkens-oui"
      LANGUAGE = "oui"
      TITLE = "Wilkens 2021 — Handwörterbuch des Altuigurischen (Altuigurisch–Deutsch–Türkisch)"
      CHUNK_PAGES = 25
      SUB_SEPARATOR = "::"
      HOMONYM_TARGET = /\A\^(\d+)(.+)\z/

      # The book's tradition/script marks → [entry-facet annotation key,
      # value], from its Abkürzungen (PDF pp. 13–14): (m) "manichäisch",
      # (c) "christlich", (br) "Brāhmī, in Brāhmī-Schrift", (r)
      # "Runenschrift", (tib) "tibetische Schrift", (p) "ʾPhags pa
      # (Schrift)" — the ʾPhags-pa script, NOT Pothī.
      MARK_FACETS = {
        "m" => %w[tradition Manichaean].freeze, "c" => %w[tradition Christian].freeze,
        "br" => %w[script Brāhmī].freeze, "r" => %w[script runic].freeze,
        "tib" => %w[script Tibetan].freeze, "p" => %w[script ʾPhags-pa].freeze
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "wilkens-oui",
        name: "Wilkens — Handwörterbuch des Altuigurischen (Old Uyghur–German–Turkish, 2021)",
        license: "CC BY-SA 4.0 — the Universitätsverlag Göttingen handle page (read 2026-10-22) and " \
                 "the book's license page verbatim: \"Dieses Werk ist lizenziert unter einer Creative " \
                 "Commons Namensnennung - Weitergabe unter gleichen Bedingungen 4.0 International " \
                 "Lizenz.\" Share-alike rider: derivatives under CC BY-SA 4.0. Credit Jens Wilkens, " \
                 "Handwörterbuch des Altuigurischen (Göttingen 2021), DOI 10.17875/gup2021-1590",
        license_class: "attribution",
        upstream_url: "https://doi.org/10.17875/gup2021-1590",
        parser_family: "wilkens-stext",
        credit: "Jens Wilkens, Handwörterbuch des Altuigurischen. Altuigurisch – Deutsch – Türkisch " \
                "(Universitätsverlag Göttingen 2021), DOI 10.17875/gup2021-1590, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      # Entries, not passages (architecture §11).
      def self.content_kind = :dictionary

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: PDF_NAME, zip_url: PDF_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # +extract+ (path, "a-b") → stext XML and +page_count+ (path) →
      # Integer are the mutool seams (the altaica-shm law: the suite runs
      # against RECORDED extractions); +pdf_sha256+ exists for the
      # WebMock'd fetch tests — real syncs keep the frozen pin.
      def initialize(extract: nil, page_count: nil, pdf_sha256: PDF_SHA256, chunk_pages: CHUNK_PAGES)
        super()
        @extract = extract || ->(path, pages) { Nabu::StextLayout.extract(path, pages: pages) }
        @page_count = page_count || method(:mutool_page_count)
        @pdf_sha256 = pdf_sha256
        @chunk_pages = chunk_pages
        @census = nil
      end

      # One ref: the PDF at the workdir root (the attic overlay rediscovers
      # a retained copy under the same id — live wins).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, PDF_NAME)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{PDF_NAME}",
                                    path: File.expand_path(path), metadata: { "dictionary" => DICTIONARY_SLUG })
      end

      # The census of the last parse on this instance (sync calls this
      # right after its load): records skipped by rule, the matter pages,
      # and the segmenter's anomaly counts. Without a parse it says so.
      def discovery_skips(_workdir)
        census = @census or
          return DiscoverySkips.new(notes: ["record-grain census rides the parse — none ran on this instance"])

        DiscoverySkips.new(skipped_by_rule: census[:skipped].size, notes: census_notes(census))
      end

      def parse(document_ref)
        segmenter, matter = segment(document_ref.path)
        records = segmenter.entries
        document = Nabu::DictionaryDocument.new(slug: DICTIONARY_SLUG, language: LANGUAGE, title: TITLE,
                                                canonical_path: document_ref.path)
        skipped = mint(records, document)
        @census = { skipped: skipped, matter: matter, anomalies: segmenter.anomalies.dup,
                    records: records.size, lost: document.count { |e| e.annotations.key?("text_layer_loss") },
                    labels: label_census(document) }
        document
      rescue Nabu::StextLayout::Error, Nabu::ValidationError, Normalize::EncodingError => e
        raise Nabu::ParseError, "wilkens-oui: #{document_ref.id}: #{e.message}"
      end

      # FileFetch phases run separately so the sha pin verifies BEFORE the
      # tree mutates (the baxter-sagart choreography).
      def fetch(workdir, progress: nil, force: false)
        fetch = FileFetch.new(url: PDF_URL, dir: workdir, filename: PDF_NAME,
                              attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        fetch.prepare!
        verify_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: attic_notes(fetch.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "wilkens-oui fetch failed into #{workdir}: #{e.message}"
      end

      # The search key: the first variant, editorial brackets and marks,
      # homonym markers and hyphens dropped, then the generic fold.
      def self.fold(text)
        form = text.to_s.split(/\s+~\s+/).first.to_s
        form = form.gsub(/\^\d+/, "").delete("()[]<>{}*†°?–-")
        folded = Normalize.search_form(Normalize.nfc(form.strip), language: LANGUAGE).strip
        folded.empty? ? nil : folded
      end

      private

      # -- extraction -------------------------------------------------------

      # Feed every page, CHUNK_PAGES at a time, through one segmenter in
      # page order. Pages without an arabic folio are the matter grain.
      def segment(path)
        segmenter = Nabu::WilkensOui::Segmenter.new
        matter = []
        previous = nil
        total = @page_count.call(path)
        (1..total).each_slice(@chunk_pages) do |slice|
          xml = @extract.call(path, "#{slice.first}-#{slice.last}")
          Nabu::StextLayout.pages(xml).each_with_index do |page, i|
            if page.folio.nil? || !page.folio.positive?
              matter << slice[i]
              next
            end
            segmenter.feed(page, continued: !previous.nil? && page.folio == previous + 1)
            previous = page.folio
          end
        end
        [segmenter, matter]
      end

      def mutool_page_count(path)
        Integer(Nabu::Shell.run("mutool", "show", path, "trailer/Root/Pages/Count").strip, 10)
      rescue Nabu::Error, ArgumentError => e
        raise Nabu::StextLayout::Error, "mutool page count failed for #{path} (#{e.message})"
      end

      def verify_pin!(fetch)
        return if fetch.sha == @pdf_sha256

        raise Nabu::FetchError,
              "wilkens-oui: #{PDF_NAME} drifted — fetched sha256 #{fetch.sha} != pinned #{@pdf_sha256}; " \
              "review upstream and re-pin (owner decision)"
      end

      # -- minting ------------------------------------------------------------

      # Mints every record into +document+; returns the records skipped by
      # rule (an empty headword cannot key an entry).
      def mint(records, document)
        keyed = assign_ids(records)
        mains = main_index(keyed)
        keyed.each { |record, id, parent| document << entry(record, id, parent, mains) }
        records.select { |record| record.headword.empty? }
      end

      # [record, entry id, its main entry {id:, headword:}] in book order.
      # A sub-entry's parent is the main entry the segmenter filed it
      # under — the last main before it (the segmenter opens a sub-entry
      # only inside a main entry's flow).
      def assign_ids(records)
        ids = Hash.new(0)
        parent = nil
        records.filter_map do |record|
          next if record.headword.empty?

          if record.kind == :main
            parent = { id: unique_id(key_raw(record), ids), headword: record.headword }
            [record, parent[:id], parent]
          else
            unless parent && parent[:headword] == record.parent
              raise Nabu::ParseError, "wilkens-oui: sub-entry #{record.headword.inspect} (p. #{record.folio}) " \
                                      "outside its main entry's flow"
            end
            [record, unique_id("#{parent[:id]}#{SUB_SEPARATOR}#{record.headword}", ids), parent]
          end
        end
      end

      def unique_id(base, ids)
        ids[base] += 1
        ids[base] == 1 ? base : "#{base}:#{ids[base]}"
      end

      # (homonym, printed form) → the main entry's id, for the "^1av"
      # pointers: every numbered main's whole headword AND each " ~ "
      # variant. A form two mains share is ambiguous and maps to nothing.
      def main_index(keyed)
        index = {}
        keyed.each do |record, id, _|
          next unless record.kind == :main && record.homonym

          [record.headword, *record.headword.split(/\s+~\s+/)].uniq.each do |form|
            key = [record.homonym, form]
            index[key] = index.key?(key) ? :ambiguous : id
          end
        end
        index
      end

      def entry(record, id, parent, mains)
        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: key_raw(record), language: LANGUAGE,
          headword: record.headword, headword_folded: self.class.fold(record.headword) || record.headword,
          gloss: gloss(record), body: body(record),
          crossrefs: (record.kind == :sub ? parent_ref(parent) : []) + xrefs(record, mains),
          annotations: annotations(record, parent)
        )
      end

      def key_raw(record) = "#{"^#{record.homonym}" if record.homonym}#{record.headword}"

      # The first top-level German sense.
      def gloss(record)
        return nil if record.german.nil? || record.german.strip.empty?

        depth = 0
        cut = record.german.each_char.with_index.find do |ch, _|
          depth += 1 if "([".include?(ch)
          depth -= 1 if ")]".include?(ch)
          ch == ";" && depth.zero?
        end&.last
        first = (cut ? record.german[0...cut] : record.german).strip
        first.empty? ? nil : first
      end

      def body(record)
        lines = [record.raw]
        lines << "German: #{record.german}" if present?(record.german)
        lines << "Turkish: #{record.turkish}" if present?(record.turkish)
        lines << "p. #{record.folio}, #{record.column} column"
        Normalize.nfc(lines.join("\n"))
      end

      def present?(text) = !text.nil? && !text.strip.empty?

      def annotations(record, parent)
        lost = record.raw.count("�")
        {
          "entry_kind" => record.kind.to_s,
          "homonym" => record.homonym,
          "parent" => (parent[:id] if record.kind == :sub),
          "page" => record.folio,
          "column" => record.column.to_s,
          "german" => (record.german if present?(record.german)),
          "turkish" => (record.turkish if present?(record.turkish)),
          "labels" => (record.labels.to_a unless record.labels.empty?),
          "shape" => shape(record),
          "rejected_reading" => (true if record.error),
          "cross_reference" => record.xref,
          "text_layer_loss" => (lost if lost.positive?)
        }.merge(mark_facets(record.labels)).compact
      end

      # {"tradition" => [...], "script" => [...]} from the record's marks
      # (MARK_FACETS); no key when the record carries none.
      def mark_facets(labels)
        labels.filter_map { |label| MARK_FACETS[label] }
              .group_by(&:first).transform_values { |pairs| pairs.map(&:last).uniq }
      end

      # Mapped facet values and unmapped labels, counted over the entries.
      def label_census(document)
        mapped = Hash.new(0)
        unmapped = Hash.new(0)
        document.each do |e|
          (e.annotations["labels"] || []).each do |label|
            pair = MARK_FACETS[label]
            pair ? mapped[pair] += 1 : unmapped[label] += 1
          end
        end
        { mapped: mapped, unmapped: unmapped }
      end

      def shape(record)
        if record.xref then "cross-reference"
        elsif record.note then "note"
        elsif record.german.nil? then "unsplit"
        else "glossed"
        end
      end

      # -- crossrefs ----------------------------------------------------------

      def parent_ref(parent)
        [Nabu::DictionaryCrossref.new(kind: "subentry-of", label: "under #{parent.fetch(:headword)}",
                                      target: parent.fetch(:headword), target_id: parent.fetch(:id))]
      end

      # One pointer per "→" link of the record's cross-reference chain.
      def xrefs(record, mains)
        return [] unless record.xref

        record.xref.split("→").each_with_index.filter_map do |link, i|
          target = link.strip.delete_suffix("†").strip.sub(/[.,;:]+\z/, "").strip
          next if target.empty?

          kind = i.zero? && record.error ? "false-reading" : "see"
          pointer(kind, target, mains)
        end
      end

      def pointer(kind, target, mains)
        label = kind == "false-reading" ? "† → #{target}" : "→ #{target}"
        if (match = HOMONYM_TARGET.match(target))
          id = mains[[Integer(match[1], 10), match[2]]]
          if id.is_a?(String)
            return Nabu::DictionaryCrossref.new(kind: kind, label: label, target: target, target_id: id)
          end
        end
        folded = self.class.fold(target)
        return nil if folded.nil?

        Nabu::DictionaryCrossref.new(kind: kind, label: label, target: target, target_folded: folded)
      end

      # -- the census ---------------------------------------------------------

      def census_notes(census)
        notes = []
        unless census[:matter].empty?
          notes << "#{census[:matter].size} PDF page(s) without an arabic folio skipped — the front/back " \
                   "matter grain (pp. #{page_ranges(census[:matter])})"
        end
        census[:skipped].each do |record|
          notes << "record skipped by rule (empty headword, p. #{record.folio}): #{record.raw[0, 60]}"
        end
        notes << "#{census[:lost]} entr(ies) carry U+FFFD where Chinese characters stood (text-layer loss)" if
          census[:lost].positive?
        notes.concat(label_notes(census[:labels]))
        residue = census[:anomalies].select { |key, _| residue_key?(key) }
        notes << "segmenter residue: #{residue.sort.map { |k, n| "#{k} #{n}" }.join(', ')}" unless residue.empty?
        notes
      end

      def label_notes(labels)
        notes = []
        unless labels[:mapped].empty?
          facets = labels[:mapped].group_by { |(key, _), _| key }.sort.map do |key, rows|
            "#{key} #{rows.map { |(_, value), n| "#{value} #{n}" }.sort.join(', ')}"
          end
          notes << "entry facets: #{facets.join('; ')}"
        end
        unless labels[:unmapped].empty?
          notes << "labels left unmapped (grammar/name labels, no facet): #{labels[:unmapped].values.sum} " \
                   "across #{labels[:unmapped].size} kinds"
        end
        notes
      end

      # The anomaly classes that name residue (the rest — sub_prefix,
      # dehyphenated, headword_wrap … — are the rules working).
      def residue_key?(key)
        key.to_s.match?(/orphan_line|_continuation_at_|sub_without_italic_head|odd_indent/)
      end

      def page_ranges(pages)
        pages.slice_when { |a, b| b != a + 1 }.map { |run| run.size == 1 ? run.first.to_s : "#{run.first}–#{run.last}" }
                                              .join(", ")
      end
    end
  end
end
