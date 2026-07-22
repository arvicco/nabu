# frozen_string_literal: true

module Nabu
  module Adapters
    # Menotec (P40-2) — the Old Norwegian treebanks + the Poetic Edda / Codex
    # Regius, gold PROIEL-scheme morphology and dependency syntax by the
    # Menotec project (Odd Einar Haugen et al., University of Bergen / UiO).
    # nabu's first CLARINO INESS source: the data is served ONLY through the
    # INESS portal's ephemeral-session REST API (clarino.uib.no/iness/rest) —
    # NOT the proiel/proiel-treebank GitHub repo (that holds only the classical
    # PROIEL texts). All fetching is Nabu::InessFetch (get-session →
    # list-resources → get-treebank-documents → get-sentences, the design note
    # on that class + architecture §8).
    #
    # == One document per treebank; sibling reader
    #
    # INESS returns each get-sentences export as a BLANK-LINE-SEPARATED STREAM
    # of per-sentence PROIEL-XML fragments (its own `<?xml?>` + one
    # `<sentence>` per block), NOT the single `<proiel>` document ProielParser
    # streams — so the token/morph mapping is reused via the sibling
    # MenotecStreamParser, which mints the SAME passage/annotation shape (see
    # its header for the compose-vs-sibling argument). A treebank's sentence ids
    # are unique across its several upstream documents, so one treebank = one
    # nabu Document: `canonical/menotec/<treebank>/*.xml` → one DocumentRef,
    # urn `urn:nabu:menotec:<treebank>`, passages `<doc-urn>:<sentence-@id>`.
    # Language `non` for every treebank INCLUDING the Edda (Old Icelandic rides
    # the treebank's own `non` tag — the one-tag-per-treebank honesty of the
    # RNC/DipSGG precedents). Menota / island-id back-references ride each
    # token's `foreign_ids` annotation.
    #
    # == License
    #
    # CC BY-NC-SA 4.0 — the INESS resource metadata license block verbatim
    # ("Creative_Commons-BY-NC-SA (CC-BY-NC-SA)",
    # creativecommons.org/licenses/by-nc-sa/4.0/); the Språkbanken /
    # Nasjonalbiblioteket catalogue record agrees. CLARINO handle
    # hdl.handle.net/11495/E628-DBC4-82EE-1. license_class `nc`, the
    # PROIEL/ISWOC posture; nc documents are MCP-excluded downstream.
    class Menotec < Nabu::Adapter
      # The INESS REST endpoint (test seam: #rest_url).
      REST_URL = "https://clarino.uib.no/iness/rest"

      URN_PREFIX = "urn:nabu:menotec:"
      LANGUAGE = "non"

      # The 7 Menotec dependency treebanks (INESS list-resources, all
      # language `non`, type `dependency`), each with its human title. This is
      # the configured fetch scope; INESS mints no per-repo id beyond these.
      TREEBANKS = {
        "non-edda-regius-dep" => "Poetic Edda (Codex Regius)",
        "non-homiliebok-dep" => "Old Norwegian Homily Book",
        "non-konungs-skuggsia-dep" => "Konungs skuggsjá (King's Mirror)",
        "non-landslov-holmperg34-dep" => "Landslov (Holm perg 34)",
        "non-olavssaga-dep" => "Óláfs saga",
        "non-pamphilus-dep" => "Pamphilus",
        "non-strengleikar-dep" => "Strengleikar"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "menotec",
        name: "Menotec — Old Norwegian treebanks + the Poetic Edda (Codex Regius), PROIEL scheme",
        license: "CC BY-NC-SA 4.0 (INESS resource metadata verbatim: " \
                 "\"Creative_Commons-BY-NC-SA (CC-BY-NC-SA)\"; " \
                 "http://creativecommons.org/licenses/by-nc-sa/4.0/; handle 11495/E628-DBC4-82EE-1)",
        license_class: "nc",
        upstream_url: "https://clarino.uib.no/iness",
        parser_family: "menotec"
      )

      def self.manifest
        MANIFEST
      end

      # No git remote and no HEAD-able zip: the INESS session API is not a
      # health-probe target, so — like the vendored no-git sources — declare no
      # upstream repos and take the no-network probe treatment (the portal URL
      # stays on the manifest for provenance). Per-file integrity against the
      # InessFetch ledger is the local-integrity invariant's job.
      def self.upstream_repo_urls = []

      # One DocumentRef per treebank subdirectory (dotdirs — the .attic — are
      # skipped; the base class runs discover against .attic itself for the
      # retention overlay). Sorted by urn.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        treebank_dirs(workdir).each do |dir|
          treebank = File.basename(dir)
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id,
            id: "#{URN_PREFIX}#{treebank}",
            path: File.expand_path(dir),
            metadata: { "treebank" => treebank }
          )
        end
      end

      # Parse the whole treebank: every *.xml under its subdir, in filename
      # order (Dir.glob is lexicographically sorted by default), concatenated
      # into one Document (sentence ids are treebank-global).
      def parse(document_ref)
        treebank = document_ref.metadata.fetch("treebank")
        paths = Dir.glob(File.join(document_ref.path, "*.xml"))
        MenotecStreamParser.new.parse(
          paths,
          urn: document_ref.id,
          language: LANGUAGE,
          title: TREEBANKS.fetch(treebank, treebank),
          canonical_path: document_ref.path
        )
      end

      # The session-based fetch (Nabu::InessFetch). The report pin is the
      # aggregate content sha (INESS has no commit sha); the guard protects at
      # DOCUMENT grain (each treebank's *.xml files).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::InessFetch.sync!(
          base_url: rest_url, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          treebanks: TREEBANKS.keys, progress: progress,
          guard: ->(doomed) { guard_document_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::InessFetch::Error => e
        raise Nabu::FetchError, "menotec fetch failed into #{workdir}: #{e.message}"
      end

      private

      # Test seam (the Sefaria/UD precedent): fetch tests point this at a local
      # rig, keeping the session flow off the network.
      def rest_url = REST_URL

      def fetch_notes(result)
        notes = "session=#{result.session_date} treebanks #{result.treebanks.size} · " \
                "documents #{result.documents}"
        notes += " · atticked #{result.atticked.size} upstream-deleted document(s)" unless result.atticked.empty?
        notes
      end

      # The per-document mass-deletion breaker: ingestible unit = one *.xml
      # document file under a treebank subdir (InessFetch dooms at that grain).
      def guard_document_deletion!(workdir, doomed, force:)
        return if force || doomed.empty?

        ingestible = Dir.glob(File.join(workdir, "*", "*.xml")).to_set { |path| File.expand_path(path) }
        doomed_docs = doomed.count { |path| ingestible.include?(path) }
        return if doomed_docs <= MASS_DELETION_THRESHOLD * ingestible.size

        raise Nabu::SyncAborted.new(existing_count: ingestible.size,
                                    would_withdraw_count: doomed_docs,
                                    threshold: MASS_DELETION_THRESHOLD)
      end

      # Immediate subdirectories that are treebanks: skip dotdirs (.attic) so a
      # live discover never mistakes the retention store for a treebank. Sorted.
      def treebank_dirs(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.children(workdir).sort
           .reject { |name| name.start_with?(".") }
           .map { |name| File.join(workdir, name) }
           .select { |path| File.directory?(path) }
      end
    end
  end
end
