# frozen_string_literal: true

require "nokogiri"
require_relative "perseus"

module Nabu
  module Adapters
    # PTA — the Patristic Text Archive (Berlin-Brandenburgische Akademie der
    # Wissenschaften; github.com/PatristicTextArchive/pta_data, Zenodo concept
    # DOI 10.5281/zenodo.4066796): open editions of early Christian authors
    # in CapiTainS TEI — the Perseus repo layout, data/<tg>/<work>/
    # <tg>.<work>.<edition>.xml with dual __cts__.xml, urns
    # urn:cts:pta:<tg>.<work>.<edition>. A Perseus SUBCLASS (the First1K
    # seam): discover/fetch and the __cts__/teiHeader readers are inherited;
    # this class adds the grain rules, the per-document licence law, the
    # apparatus policy and the catalog mining below.
    #
    # == Grains (census at 524eb976, 2026-06-18 — HEAD on 2026-11-02)
    #
    # data/ holds 536 TEI files over 208 works; analyzed/ holds 487
    # automatically tokenized/lemmatized twins of data/ files (silver; not
    # walked — the lemma layer is its own later packet, censused in the
    # skips). The document = ONE GREEK EDITION FILE (`pta-grc<n>`): 198
    # files. Every edition is taken, not the highest version — PTA's
    # versions are distinct printed editions, not revisions (De sacrificiis
    # Caini: grc1 = Uthemann 1994, the critical text; grc2 = Savile's Eton
    # 1612 print), so a Perseus-style max pick would keep the worse text.
    # Skipped by rule, each counted in #discovery_skips:
    #
    # - unlicensed files (19 — all manuscript transcriptions): no grant in
    #   the header is no grant at all (checked FIRST, whatever the grain);
    # - manuscript transcriptions `pta-Ms*` (153 licensed): diplomatic
    #   witness layers of an edition the archive also serves;
    # - biblical-excerpt files `*Bibex` (32): verse lists extracted from
    #   an edition's quotations, not a text;
    # - editions in other languages (134: syc 95, deu 14, xcl 9, lat 7,
    #   eng 6, chu 1, com 1, rum 1 — the Syriac is largely the Peshitta
    #   (ETCBC, held as `peshitta`) and awaits its dedupe against the held
    #   syriac-corpus; the rest wait on their own lect work);
    # - the Bible textgroup's Greek (pta9999, 85 files): 58 Rahlfs
    #   Septuagint editions — the Rahlfs exclusion, 02-sources row 44 (the
    #   machine-readable lineage is CATSS-encumbered whatever a re-host
    #   says; the diorisis precedent) — and 27 SBL Greek New Testament
    #   books, held as `sblgnt` from its own upstream. Detected by the
    #   edition's own __cts__ <ti:description>, never by textgroup alone.
    #
    # Reconciliation against upstream's own count (its 536 data/ TEI files,
    # manifest.txt): 113 accepted + 19 unlicensed + 153 manuscript + 32
    # Bibex + 134 other-language + 58 Rahlfs + 27 SBLGNT = 536, residue 0
    # (the adapter's discovery over the 524eb976 clone, 2026-11-02).
    #
    # == The licence law (per document)
    #
    # README verbatim: "The individual files are licensed by different
    # Creative Commons Licenses. The respective license is mentioned in the
    # header of each file." Each file's own publicationStmt <licence
    # @target> is read and classed (LICENCE_CLASSES); the census over all
    # 536 files: by-sa-4.0 312, by-4.0 128, by-nc-4.0 65, by-nc-3.0-de 10,
    # by-nc-sa-3.0 2, none 19. Attribution licences ride the source class
    # (license_override nil); nc ones carry license_override "nc" — served
    # locally with their label, never redistributed (the sefaria mechanics).
    # A Greek edition with an UNKNOWN licence target stops discovery loudly
    # (Nabu::FetchError): a new grant is classed deliberately, never
    # guessed. Of the 113 accepted Greek editions: by-sa 75 · by 37 ·
    # by-nc-sa 1 (Anonymus Cyzicenus, Hansen's GCS text).
    #
    # == Apparatus (EpidocParser apparatus:)
    #
    # The critical editions inline their apparatus — 11,760 <rdg> in 18
    # Greek editions. rdg / rdgGrp / witDetail subtrees and <del> (text the
    # witness deleted; its <subst> twin <add> stays) contribute nothing;
    # <lem> is the edited text and stays.
    class Pta < Perseus
      NAMESPACE = "pta"
      LANGUAGE = "grc"

      MANIFEST = Nabu::SourceManifest.new(
        id: "pta",
        name: "Patristic Text Archive (BBAW) — Greek editions",
        license: "Per-document Creative Commons licence, each file's own teiHeader <licence> (README: " \
                 "\"The individual files are licensed by different Creative Commons Licenses. The " \
                 "respective license is mentioned in the header of each file.\"): CC BY-SA 4.0 / " \
                 "CC BY 4.0 → attribution; CC BY-NC(-SA) → license_override nc; unlicensed files are " \
                 "never ingested. Cite the Patristic Text Archive (pta.bbaw.de) and each edition's editors",
        license_class: "attribution",
        upstream_url: "https://github.com/PatristicTextArchive/pta_data",
        parser_family: "epidoc"
      )

      # Every licence target upstream ships (census above) → its class.
      LICENCE_CLASSES = {
        "https://creativecommons.org/licenses/by-sa/4.0/" => "attribution",
        "https://creativecommons.org/licenses/by/4.0/" => "attribution",
        "https://creativecommons.org/licenses/by-nc/4.0/" => "nc",
        "https://creativecommons.org/licenses/by-nc/3.0/de/" => "nc",
        "https://creativecommons.org/licenses/by-nc-sa/3.0/" => "nc",
        "https://creativecommons.org/licenses/by-nc-sa/3.0/deed.de" => "nc"
      }.freeze

      APPARATUS = %w[rdg rdgGrp witDetail del].freeze

      # The Bible textgroup and the two edition families its Greek ships.
      BIBLE_TEXTGROUP = "pta9999"
      RAHLFS = /\bRahlfs\b/
      SBLGNT = /\bSBL Edition\b/
      ANALYZED_GLOB = File.join("analyzed", "*", "*", "*.xml")

      def self.manifest
        MANIFEST
      end

      def manifest
        MANIFEST
      end

      def parse(document_ref)
        document = EpidocParser.new.parse(
          document_ref.path, urn: document_ref.id, language: LANGUAGE,
                             title: document_ref.metadata["title"], apparatus: APPARATUS
        )
        override = document_ref.metadata["license_override"]
        metadata = edition_metadata(document_ref).merge("license" => document_ref.metadata["license"])
        copy = Nabu::Document.new(urn: document.urn, language: document.language, title: document.title,
                                  canonical_path: document.canonical_path, metadata: metadata,
                                  license_override: override)
        document.passages.each { |passage| copy << passage }
        copy
      end

      def discovery_skips(workdir)
        skipped = census(workdir)[:skipped]
        notes = SKIP_NOTES.filter_map do |reason, label|
          files = skipped.fetch(reason, [])
          next if files.empty?

          "#{files.size} #{label.call(files)}: #{files.sort.first(5).join(', ')}#{', …' if files.size > 5}"
        end
        analyzed = Dir.glob(File.join(workdir, ANALYZED_GLOB)).size
        if analyzed.positive?
          notes << "analyzed/ tree: #{analyzed} automatically tokenized twin#{'s' unless analyzed == 1} of " \
                   "data/ files (silver lemma layer) — not walked"
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped.values.sum(&:size), notes: notes)
      end

      SKIP_NOTES = {
        unlicensed: ->(files) { "unlicensed file#{'s' unless files.size == 1} (no <licence> in the header)" },
        manuscript: ->(files) { "manuscript transcription#{'s' unless files.size == 1} (pta-Ms*)" },
        bibex: ->(files) { "biblical-excerpt file#{'s' unless files.size == 1} (*Bibex)" },
        language: lambda do |files|
          tally = files.map { |name| name[/\.pta-([a-z]+)\d*[a-z]?\z/, 1] }.tally.sort
          "edition#{'s' unless files.size == 1} in other languages " \
            "(#{tally.map { |tag, count| "#{tag} #{count}" }.join(', ')})"
        end,
        rahlfs: lambda do |files|
          "Rahlfs Septuagint edition#{'s' unless files.size == 1} (02-sources row 44 — the CATSS-encumbered lineage)"
        end,
        sblgnt: lambda do |files|
          "SBL Greek New Testament edition#{'s' unless files.size == 1} (held as sblgnt from its own upstream)"
        end
      }.freeze
      private_constant :SKIP_NOTES

      private

      # The accepted Greek editions, every one (no highest-version pick).
      def best_editions(workdir)
        census(workdir)[:accepted]
      end

      def edition_refs(workdir)
        super.map do |ref|
          licence = licence_targets(ref.path).first
          klass = LICENCE_CLASSES[licence]
          unless klass
            raise Nabu::FetchError, "#{ref.path}: unrecognized licence #{licence.inspect} — class it in " \
                                    "Pta::LICENCE_CLASSES before ingesting"
          end
          ref.with(metadata: ref.metadata.merge(
            "license" => licence,
            "license_override" => klass == manifest.license_class ? nil : klass
          ).compact)
        end
      end

      def census(workdir)
        @census ||= {}
        @census[workdir] ||= classify(workdir)
      end

      def classify(workdir)
        accepted = []
        skipped = Hash.new { |hash, key| hash[key] = [] }
        all_candidates(workdir).each do |candidate|
          reason = skip_reason(candidate)
          reason ? skipped[reason] << File.basename(candidate.path, ".xml") : accepted << candidate
        end
        { accepted: accepted, skipped: skipped }
      end

      # Ordered: no grant first (whatever the grain), then the grain rules.
      def skip_reason(candidate)
        return :unlicensed if licence_targets(candidate.path).empty?
        return :manuscript if candidate.edition.start_with?("pta-Ms")
        return :bibex if candidate.edition.include?("Bibex")
        return :language unless candidate.version
        return nil unless candidate.textgroup == BIBLE_TEXTGROUP

        description = edition_description(candidate).to_s
        return :rahlfs if RAHLFS.match?(description)

        :sblgnt if SBLGNT.match?(description)
      end

      # Every edition file under data/ (Greek or not) as a Candidate; a
      # non-Greek edition carries version nil.
      def all_candidates(workdir)
        Dir.glob(File.join(workdir, "data", "*", "*", "*.xml")).filter_map do |path|
          name = File.basename(path).match(PTA_FILENAME)
          next unless name

          version = name[:edition][GREEK_EDITION, :version]
          Candidate.new(textgroup: name[:textgroup], work: name[:work], edition: name[:edition],
                        version: version, language: LANGUAGE, path: File.expand_path(path))
        end
      end

      PTA_FILENAME = /\A(?<textgroup>[^.]+)\.(?<work>[^.]+)\.(?<edition>pta-[^.]+)\.xml\z/
      GREEK_EDITION = /\Apta-grc(?<version>\d+)\z/
      private_constant :PTA_FILENAME, :GREEK_EDITION

      # Every <licence @target> of the publicationStmt (header slice only).
      def licence_targets(path)
        slice = header_slice(path)
        return [] if slice.nil?

        slice.scan(/<licence\b[^>]*\btarget="([^"]+)"/).flatten.uniq
      end

      # The work __cts__.xml's <ti:description> for this edition — the
      # printed edition it follows.
      def edition_description(candidate)
        work_cts(File.dirname(candidate.path))&.dig(:editions, edition_urn(candidate), :description)
      end

      def edition_urn(candidate)
        "urn:cts:#{NAMESPACE}:#{candidate.textgroup}.#{candidate.work}.#{candidate.edition}"
      end

      # The work-level __cts__.xml, read once per work directory.
      def work_cts(work_dir)
        @work_cts ||= {}
        return @work_cts[work_dir] if @work_cts.key?(work_dir)

        path = File.join(work_dir, "__cts__.xml")
        @work_cts[work_dir] = File.file?(path) ? read_work_cts(path) : nil
      end

      DCT = { "ti" => "http://chs.harvard.edu/xmlns/cts", "dct" => "http://purl.org/dc/terms/",
              "dc" => "http://purl.org/dc/elements/1.1/", "cpt" => "http://purl.org/capitains/ns/1.0#" }.freeze
      private_constant :DCT

      def read_work_cts(path)
        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "pta work catalog"))
        editions = doc.xpath("/ti:work/ti:edition", DCT).to_h do |edition|
          [edition["urn"], {
            description: clean_text(edition.at_xpath("ti:description", DCT)&.text),
            year: clean_text(edition.at_xpath("cpt:structured-metadata/dct:dateCopyrighted", DCT)&.text)
          }]
        end
        meta = doc.at_xpath("/ti:work/cpt:structured-metadata", DCT)
        texts = ->(xpath) { meta ? meta.xpath(xpath, DCT).filter_map { |node| clean_text(node.text) } : [] }
        { editions: editions, created: texts.call("dct:created").first, spatial: texts.call("dct:spatial").first,
          types: texts.call("dct:type"), identifiers: texts.call("dc:identifier") }
      end

      # == The catalog mining (the aggressive-mining policy)
      #
      # The work __cts__.xml's cpt:structured-metadata, census over the 185
      # works carrying Greek (2026-11-02):
      #
      # - dct:created "0401–0404" (105 works; 80 carry a bare "–") → metadata
      #   "date" {not_before, not_after, raw, class composition} — the
      #   archive's dating of the WORK, MetadataDates :structured. The span
      #   "0030–0800" (18 works, all with "Genre missing" and/or the XXXXX
      #   place) is the catalog's unfilled default — the archive's whole
      #   period, not a claim: it mints no date and rides "created_raw".
      # - dct:spatial "https://pleiades.stoa.org/places/<id>" (84 works) →
      #   metadata "place" {"pleiades", "ref"}: the place the archive
      #   attaches to the work (Pleiades ids, all in the held gazetteer).
      #   The "…/places/XXXXX" placeholder and the empty value mint nothing.
      # - dct:type, the comphistsem text-type head + sub ("Paraenetic",
      #   "Sermon") → metadata "genre" joined "|" (the kind map's split),
      #   folded in config/kind_map.yml; "Genre missing" rides verbatim
      #   and folds to nothing (a declared non-claim).
      # - dc:identifier "SCHEME:id" (PTA 185, TLG 145, CPG 94, Pinakes 93,
      #   Aldama 45, BHG 27, GND 19 …) → metadata "identifiers"
      #   {scheme => id}, with "cpg" and "tlg" lifted beside it.
      #
      # The edition's own __cts__ record adds "edition" (the printed
      # edition, verbatim) and "edition_year" (dct:dateCopyrighted); the
      # teiHeader adds "edition_status" (the editionstatus keyword:
      # critical-edition / critical-edition-no-app / pre-critical-edition …).
      PLACEHOLDER_SPANS = ["0030–0800"].freeze
      SPAN = /\A(?<from>\d{1,4})\s*[–-]\s*(?<to>\d{1,4})\z/
      PLEIADES = %r{\Ahttps?://pleiades\.stoa\.org/places/(?<id>\d+)\z}
      private_constant :PLACEHOLDER_SPANS, :SPAN, :PLEIADES

      def edition_metadata(document_ref)
        base = super
        work = work_cts(File.dirname(document_ref.path)) || {}
        edition = work.fetch(:editions, {}).fetch(document_ref.id, {})
        identifiers = (work[:identifiers] || []).filter_map do |value|
          scheme, id = value.split(":", 2)
          [scheme, id] unless id.nil? || id.strip.empty?
        end.to_h
        genre = (work[:types] || []).join("|")
        base.merge(
          "date" => created_date(work[:created]),
          "created_raw" => (work[:created] if PLACEHOLDER_SPANS.include?(work[:created])),
          "place" => pleiades_place(work[:spatial]),
          "genre" => (genre unless genre.empty?),
          "identifiers" => (identifiers unless identifiers.empty?),
          "cpg" => identifiers["CPG"], "tlg" => identifiers["TLG"],
          "edition" => edition[:description], "edition_year" => edition[:year],
          "edition_status" => edition_status(document_ref.path)
        ).compact
      end

      def created_date(raw)
        return nil if raw.nil? || PLACEHOLDER_SPANS.include?(raw)

        span = SPAN.match(raw) or return nil
        from = Integer(span[:from], 10)
        to = Integer(span[:to], 10)
        { "not_before" => [from, to].min, "not_after" => [from, to].max, "raw" => raw, "class" => "composition" }
      end

      def pleiades_place(uri)
        match = PLEIADES.match(uri.to_s) or return nil

        { "pleiades" => match[:id], "ref" => uri }
      end

      def edition_status(path)
        slice = header_slice(path) or return nil

        keywords = slice[%r{<keywords\s+scheme="#editionstatus">(.*?)</keywords>}m, 1]
        keywords && clean_text(keywords[%r{<term>([^<]+)</term>}, 1])
      end
    end
  end
end
