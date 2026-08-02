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
    # == The two waves (D45-d first wave; P56-3 second wave)
    #
    # FIRST_WAVE_VOLUMES is the complete SS rer. Germ. series ("Scriptores
    # rerum Germanicarum in usum scholarum separatim editi", 57 volumes) —
    # the coherent famous-chronicles core: Einhard's Vita Karoli, the
    # Annales regni Francorum/Bertiniani/Fuldenses, Widukind, Liudprand,
    # Nithard, Regino, Adam of Bremen, Helmold, Otto of Freising,
    # Hrotsvitha… All Latin, all small (48-525 KB zipped; the wave is
    # ~15 MB). It stays byte-frozen as the historical D45-d record.
    #
    # SECOND_WAVE_VOLUMES (P56-3) is everything else on the index —
    # re-censused 2026-08-02, byte-identical to the 2026-07-25 scout: 153
    # volumes total, so the second wave is the remaining 96 (Auct. ant. 16,
    # SS rer. Merov. 8, SS rer. Lang. 1, SS rer. Germ. N. S. 14, Dt.
    # Chron. 9, Ldl 3, Staatsschriften 10, Diplomata 13, QQ zur
    # Geistesgesch. 18, Dt. MA 4). ALL_VOLUMES — the default allowlist
    # since P56-3 — is the union; the owner still narrows/replaces via the
    # registry's `classes:` seam (the kanripo/kitab owner-posture
    # passthrough). A P56-3 five-volume byte sample (one per unseen risk:
    # Auct. ant., N. S. ×3, Staatsschriften) confirmed the second wave is
    # the SAME Scriptores dialect wave 1 pinned — the only novelty is a
    # transparent <div type="section"> nesting level below work/part,
    # which the chunker already passes through (only work divs count).
    #
    # == Languages (no xml:lang exists anywhere upstream)
    #
    # Per-series table from the index: the 9 Dt. Chron. volumes are Middle
    # High German (gmh — the ReM code); every other series censused is
    # Latin, INCLUDING the German-NAMED Dt. MA ("Deutsches Mittelalter":
    # Briefe Heinrichs IV., Brunos Sachsenkrieg — Latin texts) — PLUS two
    # per-volume exceptions the P56-3 byte census caught hiding in Latin
    # series (see GMH_VOLUMES). Titles prove nothing either way: the
    # German-titled Kölner Weltchronik (bsb00000695) and Weltchronik des
    # Mönchs Albert (bsb00000697) are LATIN chronicles, verified from
    # their body bytes. First real sync eyeballs any volume no census has
    # seen.
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

      # P56-3: the remaining 96 index volumes, machine-extracted from the
      # live index 2026-08-02 (153 ids total, byte-identical to the wave-1
      # scout of 2026-07-25 — upstream has not grown between waves).
      SECOND_WAVE_VOLUMES = %w[
        bsb00000785 bsb00000786 bsb00000788 bsb00000789 bsb00000790
        bsb00000791 bsb00000792 bsb00000793 bsb00000794 bsb00000795
        bsb00000796 bsb00000797 bsb00000799 bsb00000824 bsb00000826
        bsb00000827
        bsb00000747 bsb00000749 bsb00000750 bsb00000751 bsb00000752
        bsb00000753 bsb00000754 bsb00050862
        bsb00000858
        bsb00000682 bsb00000683 bsb00000684 bsb00000686 bsb00000687
        bsb00000689 bsb00000690 bsb00000691 bsb00000692 bsb00000693
        bsb00000695 bsb00000696 bsb00000697 bsb00000944
        bsb00000773 bsb00000774 bsb00000775 bsb00000776 bsb00000777
        bsb00000778 bsb00000779 bsb00000780 bsb00000781
        bsb00000828 bsb00000829 bsb00000830
        bsb00000646 bsb00000647 bsb00000648 bsb00000649 bsb00000650
        bsb00000651 bsb00000652 bsb00000653 bsb00000654 bsb00000655
        bsb00000356 bsb00000359 bsb00000361 bsb00000435 bsb00000457
        bsb00000458 bsb00000459 bsb00000461 bsb00000463 bsb00000464
        bsb00002026 bsb00002027 bsb00066349
        bsb00000618 bsb00000619 bsb00000620 bsb00000621 bsb00000622
        bsb00000623 bsb00000624 bsb00000625 bsb00000626 bsb00000628
        bsb00000629 bsb00000630 bsb00000631 bsb00000632 bsb00000633
        bsb00000634 bsb00000635 bsb00050770
        bsb00000614 bsb00000615 bsb00000616 bsb00000617
      ].freeze
      # ^ index order by section: Auct. ant. (16), SS rer. Merov. (8),
      #   SS rer. Lang. (1), SS rer. Germ. N. S. (14), Dt. Chron. (9),
      #   Ldl (3), Staatsschriften (10), Diplomata (13: DD Merov. / DD
      #   Lo I.+II. / DD Rudolf. / DD Arn / DD dt. Könige u. Kaiser),
      #   QQ zur Geistesgesch. (18), Dt. MA (4).

      # The full censused index — the default allowlist since P56-3.
      ALL_VOLUMES = (FIRST_WAVE_VOLUMES + SECOND_WAVE_VOLUMES).sort.freeze

      # The Middle High German volumes: the MGH Dt. Chron. series complete
      # (Kaiserchronik, Trierer Silvester, Sächsische Weltchronik, Jansen
      # Enikel, Limburger Chronik, Kreuzfahrt Ludwigs, Ottokars Reimchronik
      # 1-2, Österreichische Chronik), from the index 2026-07-25 — plus the
      # two German-language works the P56-3 byte census (2026-08-02) found
      # hiding in Latin series: Jakob Unrest's Österreichische Chronik
      # (bsb00000691, SS rer. Germ. N. S. 11 — "Als man vor in der
      # Osterreichischen coronikn list…") and the Reformation Kaiser
      # Siegmunds (bsb00000655, Staatsschriften 6 — "Almechtiger got,
      # schöpffer himels und ertrichs…"; late texts, but inside ISO 639-2
      # gmh's ca. 1050-1500 window). Everything else defaults to Latin.
      GMH_VOLUMES = %w[
        bsb00000773 bsb00000774 bsb00000775 bsb00000776 bsb00000777
        bsb00000778 bsb00000779 bsb00000780 bsb00000781
        bsb00000655 bsb00000691
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
        ALL_VOLUMES.map do |bsbid|
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
      # nil takes the full censused index (P56-3; wave 1 alone was the
      # D45-d default).
      def initialize(classes: nil)
        super()
        @volumes = classes || ALL_VOLUMES
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
