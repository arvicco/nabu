# frozen_string_literal: true

require_relative "openmgh_tei_parser"

module Nabu
  module Adapters
    # openMGH (P45-2) — the Monumenta Germaniae Historica critical editions
    # as per-volume TEI-XML, from the MGH + Bayerische Staatsbibliothek
    # "digital MGH" project. Scouted live 2026-07-25: 153 volumes on the
    # index page (www.mgh.de/en/digital-mgh/openmgh/mgh-editions-in-openmgh),
    # each a single zip at data.mgh.de/openmgh/<bsbid>.zip holding exactly
    # one <bsbid>.xml. The id space is SPARSE (an unlisted bsb id 404s), so
    # enumeration comes from the index page, never a sweep — the allowlist
    # below is that index's machine-extracted state.
    #
    # == Identity
    #
    #   document urn  urn:nabu:openmgh:<bsbid>          (…:bsb00000728)
    #   passage urn   <doc>:w<k>.p<page>  (Scriptores — work ordinal + the
    #                 printed page number, THE citation grain MGH volumes
    #                 are cited by: "MGH SS rer. Germ. 25, p. 12")
    #                 <doc>:c<charternum> (Diplomata — the edition's own
    #                 charter number: "D Rudolf. 1")
    #
    # Both minted by the bespoke `openmgh-tei` parser (see its refutation
    # header for why no existing family composes).
    #
    # == License (read live 2026-07-25 — page AND in-file grant agree)
    #
    # openMGH page verbatim: "The resources are provided under the licence
    # of Creative Commons Attribution 4.0 International (CC BY 4.0). The
    # licence includes the annotations (tags)… The edited medieval texts
    # themselves are free from copyright." Every volume's own
    # <availability><licence>: "Distributed under the Creative Commons
    # Attribution 4.0 International (CC BY 4.0) license." … "We do not
    # claim any rights on the text itself which is believed to be in the
    # public domain." Citation duty: name the MGH and the Bayerische
    # Staatsbibliothek (BSB). → class attribution.
    #
    # == The first wave (DECISION ITEM D45-d, owner ratifies)
    #
    # FIRST_WAVE_VOLUMES is the complete SS rer. Germ. series ("Scriptores
    # rerum Germanicarum in usum scholarum separatim editi", 57 volumes) —
    # the coherent famous-chronicles core: Einhard's Vita Karoli, the
    # Annales regni Francorum/Bertiniani/Fuldenses, Widukind, Liudprand,
    # Nithard, Regino, Adam of Bremen, Helmold, Otto of Freising,
    # Hrotsvitha… All Latin, all small (48-525 KB zipped; the wave is
    # ~15 MB). The owner extends/replaces the scope via the registry's
    # `classes:` seam (the kanripo/kitab owner-posture passthrough). The
    # remaining 96 volumes (Auct. ant., SS rer. Merov., SS rer. Germ.
    # N. S., Diplomata, QQ zur Geistesgesch., Dt. Chron., Staatsschriften,
    # Ldl, Dt. MA…) are a documented future step — the parser already
    # handles both dialects.
    #
    # == Languages (no xml:lang exists anywhere upstream)
    #
    # Per-series table from the index: the 9 Dt. Chron. volumes are Middle
    # High German (gmh — the ReM code); every other series censused is
    # Latin, INCLUDING the German-NAMED Dt. MA ("Deutsches Mittelalter":
    # Briefe Heinrichs IV., Brunos Sachsenkrieg — Latin texts). First real
    # sync eyeballs any volume this table has not seen.
    #
    # == fetch / sync policy
    #
    # One ZipFetch per allowlisted volume into <workdir>/<bsbid>/ (the
    # ORACC multi-zip choreography: ALL volumes prepared and staged, ONE
    # mass-deletion guard over the union, then every tree swaps in;
    # Last-Modified conditional GETs make re-syncs cheap 304s). wired:
    # false, sync_policy manual — the first real sync is owner-fired.
    class Openmgh < Nabu::Adapter
      ZIP_BASE = "https://data.mgh.de/openmgh"
      INDEX_URL = "https://www.mgh.de/en/digital-mgh/openmgh/mgh-editions-in-openmgh"
      URN_PREFIX = "urn:nabu:openmgh:"

      # D45-d: the complete SS rer. Germ. series, machine-extracted from the
      # live index 2026-07-25 (57 of the 153 available volumes).
      FIRST_WAVE_VOLUMES = %w[
        bsb00000701 bsb00000702 bsb00000703 bsb00000704 bsb00000705
        bsb00000706 bsb00000707 bsb00000708 bsb00000709 bsb00000710
        bsb00000711 bsb00000712 bsb00000713 bsb00000714 bsb00000715
        bsb00000716 bsb00000717 bsb00000718 bsb00000719 bsb00000720
        bsb00000721 bsb00000722 bsb00000723 bsb00000724 bsb00000726
        bsb00000727 bsb00000728 bsb00000729 bsb00000730 bsb00000731
        bsb00000734 bsb00000735 bsb00000736 bsb00000737 bsb00000738
        bsb00000739 bsb00000740 bsb00000741 bsb00000743 bsb00000744
        bsb00000746 bsb00000756 bsb00000757 bsb00000758 bsb00000759
        bsb00000760 bsb00000761 bsb00000762 bsb00000763 bsb00000764
        bsb00000765 bsb00000767 bsb00000768 bsb00000771 bsb00000772
        bsb00000880 bsb00000945
      ].freeze

      # The Middle High German volumes: the MGH Dt. Chron. series complete
      # (Kaiserchronik, Trierer Silvester, Sächsische Weltchronik, Jansen
      # Enikel, Limburger Chronik, Kreuzfahrt Ludwigs, Ottokars Reimchronik
      # 1-2, Österreichische Chronik), from the index 2026-07-25. Everything
      # else defaults to Latin.
      GMH_VOLUMES = %w[
        bsb00000773 bsb00000774 bsb00000775 bsb00000776 bsb00000777
        bsb00000778 bsb00000779 bsb00000780 bsb00000781
      ].freeze

      DEFAULT_LANGUAGE = "lat"

      MANIFEST = Nabu::SourceManifest.new(
        id: "openmgh",
        name: "openMGH — Monumenta Germaniae Historica editions (MGH / BSB, digital MGH)",
        license: "CC BY 4.0 — the openMGH page verbatim: \"The resources are provided under the " \
                 "licence of Creative Commons Attribution 4.0 International (CC BY 4.0). The licence " \
                 "includes the annotations (tags)… The edited medieval texts themselves are free from " \
                 "copyright.\" Per-volume in-file grant agrees. Cite www.mgh.de/mgh-digital/openmgh " \
                 "and name the Monumenta Germaniae Historica (MGH) and the Bayerische " \
                 "Staatsbibliothek (BSB).",
        license_class: "attribution",
        upstream_url: "https://www.mgh.de/en/digital-mgh/openmgh",
        parser_family: "openmgh-tei"
      )

      def self.manifest
        MANIFEST
      end

      # No git repo — the remote probe HEADs each allowlisted volume zip.
      def self.upstream_repo_urls = []

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        FIRST_WAVE_VOLUMES.map do |bsbid|
          Nabu::Adapter::HttpProbeTarget.new(
            label: bsbid, zip_url: "#{ZIP_BASE}/#{bsbid}.zip",
            metadata_url: nil, state_subdir: bsbid
          )
        end
      end

      # The per-series language table (class note): Dt. Chron. is Middle
      # High German; everything else censused is Latin.
      def self.volume_language(bsbid)
        GMH_VOLUMES.include?(bsbid) ? "gmh" : DEFAULT_LANGUAGE
      end

      # +classes+ (the registry `classes:` seam — the kanripo/kitab
      # owner-posture passthrough): the volume allowlist the fetch sweeps.
      # nil keeps the D45-d first wave.
      def initialize(classes: nil)
        super()
        @volumes = classes || FIRST_WAVE_VOLUMES
      end

      # One DocumentRef per <bsbid>/<bsbid>.xml on disk, sorted by urn —
      # disk-driven, so re-parses and rebuilds see every fetched volume
      # regardless of the current allowlist.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        OpenmghTeiParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: self.class.volume_language(document_ref.metadata["bsbid"].to_s)
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The ORACC multi-zip choreography: every allowlisted volume prepared
      # (downloaded + staged, live trees untouched), one mass-deletion guard
      # over the union, then each tree swaps in. HTTP/unzip failures abort
      # as Nabu::FetchError; a tripped breaker as Nabu::SyncAborted.
      def fetch(workdir, progress: nil, force: false)
        fetches = zip_fetches(workdir, progress)
        begin
          fetches.each_value(&:prepare!)
          guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
          fetches.each_value(&:complete!)
        ensure
          fetches.each_value(&:cleanup!)
        end
        report(fetches)
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "openmgh fetch failed into #{workdir}: #{e.message}"
      end

      private

      def zip_fetches(workdir, progress)
        @volumes.to_h do |bsbid|
          [bsbid, Nabu::ZipFetch.new(
            url: "#{ZIP_BASE}/#{bsbid}.zip", dir: File.join(workdir, bsbid),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, bsbid), progress: progress
          )]
        end
      end

      def report(fetches)
        shas = fetches.transform_values(&:sha)
        fresh = fetches.count { |_, fetch| !fetch.not_modified? }
        atticked = fetches.values.sum { |fetch| fetch.atticked.size }
        notes = "openmgh: #{fresh} volume(s) fetched, #{fetches.size - fresh} unchanged (304) — " \
                "#{fetches.keys.join(' ')}"
        notes = "#{notes} · atticked #{atticked} upstream-deleted file(s)" if atticked.positive?
        Nabu::FetchReport.new(
          sha: shas.values.compact.last, fetched_at: Time.now, notes: notes,
          repos: shas.transform_keys { |bsbid| "#{ZIP_BASE}/#{bsbid}.zip" }
        )
      end

      def document_refs(workdir)
        Dir.glob(File.join(workdir, "bsb*", "bsb*.xml")).map do |path|
          bsbid = File.basename(path, ".xml")
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{bsbid}",
            path: File.expand_path(path),
            metadata: { "bsbid" => bsbid }
          )
        end.sort_by(&:id)
      end
    end
  end
end
