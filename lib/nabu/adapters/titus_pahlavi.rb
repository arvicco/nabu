# frozen_string_literal: true

require "digest"
require_relative "titus_pahlavi_parser"

module Nabu
  module Adapters
    # TITUS Pahlavi books — the Zoroastrian Middle Persian (Book Pahlavi)
    # text editions on TITUS (J. W. Goethe-Universität Frankfurt, Prof. Jost
    # Gippert): Ardā Wirāz, the Bundahišn, Dēnkard 4–7, Dādestān ī dēnīg,
    # Mēnōg ī xrad, Kārnāmag, the Mādayān, the Pahlavi Rivāyat, the Zand (the
    # Pahlavi versions of the Avesta), Šāyast nē šāyast, Zādspram, the Zand ī
    # Wahman yasn and the two minor-text corpora — 24 editions censused from
    # TITUS's own text index (texte2.htm, 2026-10-07).
    #
    # Deliberately OUT of this source: the Middle Persian Psalter (Christian,
    # Psalter-Pahlavi script — not a Pahlavi book), the Manichaean Middle
    # Persian corpora (Manichaean script, a different textual tradition) and
    # the inscriptions (listed "under preparation", nothing retrievable) —
    # each a separate packet under the same grant if wanted.
    #
    # == The grant (by email, 2026-10-06) and the credit duty
    #
    # Fetched under the owner's PERSONAL grant (Gippert): the Middle Iranian
    # families on TITUS "to whatever extent TITUS hosts them as retrievable
    # text" — ONE retrieval per corpus, local personal research use only, no
    # redistribution, TITUS and the editors credited wherever displayed. The
    # titus-avestan mechanisms verbatim: `grant_required: true` guards the
    # fetch right; license_class `nc` + the manifest +credit+ line carry the
    # display duty (every edition's data-entry editors named in it, and each
    # document's own "editors" metadata names its edition's).
    #
    # == Shape (see Nabu::Adapters::TitusPahlaviParser)
    #
    # canonical/titus-pahlavi/<edition>/<prefix>NNN.htm — one subdir per TITUS
    # edition, named by TITUS's own directory (two editions share the page
    # prefix `snstr`, so the edition is part of every urn). One PAGE is one
    # document; passages sit at the edition's own CITATION grain — whatever
    # its deepest `<!Level N>` header is (Sentence for Ardā Wirāz / Bundahišn
    # / the minor texts, Paragraph for the Mādayān / Šāyast nē šāyast, Verse
    # for the Zand of the Yasna), plus any text a higher level carries
    # directly (the chapter invocation "pad nām ī yazdān", a chapter
    # heading). The printed-edition page/line and manuscript locations ride
    # each passage as annotations, read from the section's full anchor.
    class TitusPahlavi < Nabu::Adapter
      SLUG = "titus-pahlavi"
      LANGUAGE = "pal" # Middle Persian (Pahlavi)
      PARSER_FAMILY = "titus_pahlavi"

      BASE_URL = "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/mpers/"

      # One TITUS edition: +path+ the frameset under BASE_URL, +prefix+ its
      # page-file stem, +name+ and +editors+ verbatim from TITUS's text index
      # (texte2.htm, "Data entry by …"), +credit_name+ the short form the
      # source-level credit line carries.
      Edition = Data.define(:path, :prefix, :name, :editors, :credit_name) do
        def entry_url = "#{BASE_URL}#{path}"
        def page_re = /\A#{Regexp.escape(prefix)}\d+\.htm\z/
      end

      # census: 24 editions on texte2.htm's Middle Persian list, 2026-10-07
      # (Psalter, Manichaean and inscriptions excluded — see the class doc)
      EDITIONS = {
        "arda" => Edition.new(path: "arda/arda.htm", prefix: "arda", name: "Ardā-virāf-nāmag",
                              editors: "P. Vavroušek (Praha)", credit_name: "Vavroušek"),
        "andoshn" => Edition.new(path: "andoshn/andos.htm", prefix: "andos", name: "Andarz-i Ōshnar-i Dānāg",
                                 editors: "Th. Jügel (Frankfurt)", credit_name: "Jügel"),
        "bundahis" => Edition.new(path: "bundahis/bunda.htm", prefix: "bunda", name: "Bundahišn",
                                  editors: "P. Olivier, J. Gippert (Frankfurt) and C.G. Cereti (Vienna)",
                                  credit_name: "Olivier/Gippert/Cereti"),
        "dadden" => Edition.new(path: "dadden/dadde.htm", prefix: "dadde", name: "Dādistān-i Dēnīg",
                                editors: "B. Ataei (Berlin)", credit_name: "Ataei"),
        "dk4" => Edition.new(path: "dk4/dk4.htm", prefix: "dk4", name: "Dēnkard Book 4",
                             editors: "M. Hale (Concordia)", credit_name: "Hale"),
        "dk5" => Edition.new(path: "dk5/dk5.htm", prefix: "dk5", name: "Dēnkard Book 5",
                             editors: "M. Hale (Concordia)", credit_name: "Hale"),
        "dk6" => Edition.new(path: "dk6/dk6.htm", prefix: "dk6", name: "Dēnkard Book 6",
                             editors: "M. Hale (Concordia)", credit_name: "Hale"),
        "dk7" => Edition.new(path: "dk7/dk7.htm", prefix: "dk7", name: "Dēnkard Book 7",
                             editors: "I. Shafiee (Tehran)", credit_name: "Shafiee"),
        "kap" => Edition.new(path: "kap/kap.htm", prefix: "kap", name: "Kārnāmag-i Ardašīr-i Pābagān",
                             editors: "D.N. MacKenzie", credit_name: "MacKenzie"),
        "mx" => Edition.new(path: "mx/mx.htm", prefix: "mx", name: "Mēnōg-i xrad",
                            editors: "D.N. MacKenzie", credit_name: "MacKenzie"),
        "mhd" => Edition.new(path: "mhd/mhd.htm", prefix: "mhd", name: "Mādigān-i hazār Dādastān",
                             editors: "M. Macuch and C. Naumann (Berlin)", credit_name: "Macuch/Naumann"),
        "pahlriv" => Edition.new(path: "pahlriv/pahlr.htm", prefix: "pahlr", name: "Pahlavī Rivāyat",
                                 editors: "I. Šafi'ī and M. Taghi Asl (Tehran)", credit_name: "Šafi'ī/Taghi Asl"),
        "yvrpt" => Edition.new(path: "avpt/yvrpt/yvrpt.htm", prefix: "yvrpt",
                               name: "Pahlavī version of Yasna and Vispered",
                               editors: "P.O. Skjærvø (Harvard)", credit_name: "Skjærvø"),
        "oavpt" => Edition.new(path: "avpt/oavpt/oavpt.htm", prefix: "oavpt",
                               name: "Pahlavī version of Old Avestan Texts",
                               editors: "R. Musavi (Tehran)", credit_name: "Musavi"),
        "yavpt" => Edition.new(path: "avpt/yavpt/yavpt.htm", prefix: "yavpt",
                               name: "Pahlavī version of Young Avestan Texts (Yasna, Niyayish, " \
                                     "Hadokht Nask, Vaetha Nask)",
                               editors: "M. A. Andrés-Toledo (Salamanca)", credit_name: "Andrés-Toledo"),
        "purs" => Edition.new(path: "avpt/purs/purs.htm", prefix: "purs",
                              name: "Pahlavī version of the Pursišnīhā",
                              editors: "M. A. Andrés Toledo (Salamanca)", credit_name: "Andrés"),
        "vdp" => Edition.new(path: "avpt/vdp/vdp.htm", prefix: "vdp",
                             name: "Pahlavī version of the Vidēvdād (Chapters 1-3 and 10-15)",
                             editors: "A. Cantera Glera and M. A. Andrés Toledo (Salamanca)",
                             credit_name: "Cantera"),
        "vd-19p" => Edition.new(path: "avpt/vd-19p/vd-19.htm", prefix: "vd-19",
                                name: "Pahlavī version of the Vidēvdād (Chapter 19)",
                                editors: "Céline Redard (London)", credit_name: "Redard"),
        "snstrl" => Edition.new(path: "snstrl/snstr.htm", prefix: "snstr", name: "Šāyast-nē-šāyast (transliteration)",
                                editors: "D. Durkin-Meisterernst (Berlin)", credit_name: "Durkin-Meisterernst"),
        "snstrs" => Edition.new(path: "snstrs/snstr.htm", prefix: "snstr", name: "Šāyast-nē-šāyast (transcription)",
                                editors: "D. Durkin-Meisterernst (Berlin)", credit_name: "Durkin-Meisterernst"),
        "zadspram" => Edition.new(path: "zadspram/zadsp.htm", prefix: "zadsp", name: "Vizīdagīhā-i Zadspram",
                                  editors: "L. Paul (Göttingen)", credit_name: "Paul"),
        "zwy" => Edition.new(path: "zwy/zwy.htm", prefix: "zwy", name: "Zand-ī vohuman yasn",
                             editors: "D. Durkin-Meisterernst (Berlin)", credit_name: "Durkin-Meisterernst"),
        "jamasp" => Edition.new(path: "jamasp/jamas.htm", prefix: "jamas",
                                name: "Corpus of minor Middle Persian (Pahlavī) texts",
                                editors: "J. Gippert (Frankfurt) and C.G. Cereti (Vienna)",
                                credit_name: "Gippert/Cereti"),
        "mpt" => Edition.new(path: "mpt/mpt.htm", prefix: "mpt",
                             name: "Other minor Middle Persian (Pahlavī) texts",
                             editors: "B. Ataei (Berlin)", credit_name: "Ataei")
      }.freeze

      LICENSE = "personal grant, Gippert (by email, 2026-10-06): one retrieval, local personal " \
                "research use only, no redistribution; TITUS and the editors clearly indicated " \
                "wherever displayed"

      CREDIT = "TITUS (J. Gippert, Frankfurt) — Middle Persian (Pahlavi) text editions, data entry " \
               "#{EDITIONS.values.map(&:credit_name).uniq.join(', ')} " \
               "(each document names its edition's editors).".freeze

      # Header spans mined into document metadata (the first page of each
      # edition carries them; continuation pages honestly carry none).
      HEADER_SPANS = { "title" => "page_title", "textdescr" => "data_entry", "bibliogr" => "bibliography" }.freeze

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "TITUS Pahlavi Books",
          license: LICENSE,
          license_class: "nc",
          upstream_url: "#{BASE_URL}arda/arda.htm",
          parser_family: PARSER_FAMILY,
          credit: CREDIT
        )
      end

      # Each edition's frameset entry stands for that edition — HEAD it for
      # liveness; its TitusFetch state file (url + sha) feeds the drift lane.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        EDITIONS.map do |id, edition|
          Nabu::Adapter::HttpProbeTarget.new(
            label: "#{id} entry", zip_url: edition.entry_url, metadata_url: nil,
            state_subdir: id, state_file: Nabu::TitusFetch::STATE_FILE
          )
        end
      end

      # +editions+ narrows the walk (tests); +delay+ is TitusFetch's polite
      # pause between requests.
      def initialize(editions: EDITIONS, delay: Nabu::TitusFetch::DELAY)
        super()
        @editions = editions
        @delay = delay
      end

      # One DocumentRef per text page of every known edition (ref.id IS the
      # document urn). Framesets and unknown directories are not text.
      # Apparatus-only pages — every content lane a variant reading (the
      # Vidēvdād 19 critical apparatus, vd-19p/vd-19050: 1 of 1,573 pages at
      # the first-sync census) — skip by rule, censused by discovery_skips.
      def discover(workdir)
        text_pages(workdir).reject { |_id, _stem, path| apparatus_only?(path) }.map do |id, stem, path|
          Nabu::DocumentRef.new(source_id: SLUG, id: document_urn(id, stem), path: path,
                                metadata: { "edition" => id, "page" => stem })
        end
      end

      def discovery_skips(workdir)
        skipped = text_pages(workdir).count { |_id, _stem, path| apparatus_only?(path) }
        notes = skipped.positive? ? ["#{skipped} apparatus-only page(s) skipped — variant readings, no text"] : []
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: 0, notes: notes)
      end

      # Parse one page into a Document of citation-grain Passages. A page
      # with no text-bearing section is a structural failure (ParseError).
      def parse(document_ref)
        html = TitusPahlaviParser.read_page(document_ref.path)
        sections = TitusPahlaviParser.parse(html)
        raise Nabu::ParseError, "titus-pahlavi: no text sections in #{document_ref.path}" if sections.empty?

        edition_id = document_ref.metadata.fetch("edition")
        edition = EDITIONS.fetch(edition_id)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: "Pahlavi — #{edition.name} (#{document_ref.metadata['page']})",
          metadata: document_metadata(edition_id, edition, html, sections)
        )
        seen = Hash.new(0)
        sections.each_with_index do |section, sequence|
          citation = citation_for(section)
          occurrence = (seen[citation] += 1)
          document << Nabu::Passage.new(
            urn: passage_urn(document_ref.id, citation, occurrence), language: LANGUAGE,
            text: section.text, sequence: sequence, annotations: section_annotations(section, occurrence)
          )
        end
        document
      end

      # One polite TitusFetch walk per edition (owner-run; never in tests —
      # WebMock blocks the network), each into its own subdir with its own
      # page pattern, state file and attic subtree. Pages already on disk are
      # never re-fetched (the grant's ONE retrieval). The source pin is the
      # sha256 over the per-edition page-set pins.
      def fetch(workdir, progress: nil, force: false)
        shas = []
        atticked = []
        @editions.each do |id, edition|
          result = Nabu::TitusFetch.sync!(
            entry_url: edition.entry_url, dir: File.join(workdir, id),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, id), page_re: edition.page_re,
            delay: @delay, progress: progress,
            guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
          )
          shas << "#{id}:#{result.sha}"
          atticked.concat(result.atticked)
        end
        FetchReport.new(sha: Digest::SHA256.hexdigest(shas.join("\n")), fetched_at: Time.now,
                        notes: attic_notes(atticked))
      rescue Nabu::TitusFetch::Error => e
        raise Nabu::FetchError, "titus-pahlavi fetch failed into #{workdir}: #{e.message}"
      end

      private

      # [edition id, page stem, path] for every numbered text page.
      def text_pages(workdir)
        @editions.flat_map do |id, edition|
          Dir.glob(File.join(workdir, id, "#{edition.prefix}*.htm")).filter_map do |path|
            name = File.basename(path)
            [id, name.delete_suffix(".htm"), path] if name.match?(edition.page_re)
          end
        end
      end

      # The cheap byte needle: the page names content lanes, and every one
      # is a variant-reading lane.
      def apparatus_only?(path)
        ids = File.binread(path).scan(/<span id=([a-z0-9]+)>/i).flatten.uniq
        lanes = ids.grep(TitusPahlaviParser::CONTENT_PREFIX)
        !lanes.empty? && lanes.all? { |id| TitusPahlaviParser.variant_lane?(id) }
      end

      # "<edition>.<page>" — the edition is needed: snstrl and snstrs share
      # the page prefix snstr.
      def document_urn(edition_id, stem)
        "urn:nabu:#{SLUG}:#{edition_id}.#{stem}"
      end

      # The dotted citation from the logical components: empties (absent
      # levels) drop, and a component's own trailing period (the edition
      # tokens "Bd.", "Denk.", "Ay.Zar.") drops so the dots stay separators.
      def citation_for(section)
        section.components.reject(&:empty?).map { |c| c.delete_suffix(".") }.join(".")
      end

      # A citation the page re-anchors (the jamasp colophon renumbers its
      # sentences 2-5 after Ayādgār ī Zarērān 114 — census 2026-10-07) keys
      # as `<citation>#<occurrence>` in document order (the titus-avestan
      # P43-i2 shape) with an honest "occurrence" annotation — real text,
      # never merged, never dropped.
      def passage_urn(document_urn, citation, occurrence)
        tail = occurrence > 1 ? "#{citation}##{occurrence}" : citation
        "#{document_urn}:#{tail}"
      end

      def section_annotations(section, occurrence)
        annotations = { "unit" => section.label }
        annotations.merge!(section.location)
        annotations["avestan"] = section.avestan if section.avestan
        annotations["transliteration"] = section.transliteration if section.transliteration
        annotations["occurrence"] = occurrence if occurrence > 1
        annotations
      end

      # Edition identity + the page header's own statements (data entry,
      # edition basis) + the lanes' representation, mined verbatim.
      def document_metadata(edition_id, edition, html, sections)
        metadata = { "edition" => edition_id, "edition_name" => edition.name, "editors" => edition.editors }
        doc = Nokogiri::HTML(html)
        HEADER_SPANS.each do |span_id, key|
          # Split spans of one kind (mhd: "as edited by" … <bibliogr> …
          # "electronically prepared by …") join with an ellipsis — the
          # elided part is the other span kind, recorded under its own key.
          parts = doc.css(%(span[id="#{span_id}"])).map { |span| TitusPahlaviParser.clean(span.text) }
          text = parts.reject(&:empty?).join(" … ")
          metadata[key] = text unless text.empty?
        end
        representation = sections.filter_map(&:representation).flat_map { |r| r.split("+") }.uniq.sort
        metadata["representation"] = representation.join("+") unless representation.empty?
        metadata
      end
    end
  end
end
