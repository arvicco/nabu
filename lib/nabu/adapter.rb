# frozen_string_literal: true

require "json"

module Nabu
  # Abstract base for source adapters — the extensibility point of the whole
  # system (architecture §3). Every source is one subclass implementing four
  # methods; adapters emit the neutral Document/Passage model and never touch
  # SQL. Every subclass must pass the shared conformance suite
  # (test/support/adapter_conformance.rb) plus its own source-specific tests.
  #
  # Text discipline: adapters normalize upstream text to UTF-8 NFC at this
  # boundary (Nabu::Normalize.nfc) — Passage rejects non-NFC input outright.
  #
  # Error discipline: parse raises Nabu::ParseError (quarantines the
  # document); fetch raises Nabu::FetchError (aborts the sync); fetch raises
  # Nabu::SyncAborted when the mass-deletion breaker trips (see below).
  #
  # == Retention (P5-2): the attic, implemented once, here
  #
  # Upstream scrapping a document must never degrade the local collection.
  # The fetch layer (Nabu::GitFetch) preserves upstream-deleted files under
  # <workdir>/.attic/<same relative path>; this base class makes every
  # adapter rediscover them WITHOUT the adapter knowing the attic exists:
  # #discover_with_attic runs the subclass's own #discover against the attic
  # dir (same relative shapes, so the same walking logic applies) and marks
  # the resulting refs retained. Subclasses implement only #discover.
  class Adapter
    # Where GitFetch preserves upstream-deleted files, inside the source's
    # canonical workdir — so the attic replays through every rebuild
    # (db = f(canonical) includes it).
    ATTIC_DIRNAME = ".attic"

    # DocumentRef metadata keys discover_with_attic stamps on attic refs.
    RETAINED_KEY = "retained"
    RETIRED_SHA_KEY = "retired_sha"

    # One HTTP-zip remote-probe target (P11-2), for a :http_zip source. Each
    # fetched unit yields one: +zip_url+ is HEAD'd for reachability +
    # Last-Modified and is ALSO the ledger-pin key (the sync path pins each
    # unit by its zip URL); +metadata_url+ is GET'd for the license field —
    # nil means the source has NO license endpoint (the license lives inside
    # the fetched artifact itself; ASPR), and the probe's license row then
    # honestly reads unchecked instead of GETting anything; +state_subdir+ is
    # the unit's dir under the source workdir, holding the Last-Modified pin
    # the probe diffs against — +state_file+ names it (ZipFetch's
    # .zip-fetch.json by default; a FileFetch-backed source points it at
    # FileFetch::STATE_FILE).
    HttpProbeTarget = Data.define(:label, :zip_url, :metadata_url, :state_subdir, :state_file) do
      def initialize(label:, zip_url:, metadata_url:, state_subdir:, state_file: ZipFetch::STATE_FILE)
        super
      end
    end

    # Trip the mass-deletion breaker when an upstream pull would delete
    # strictly more than this fraction of the source's ingestible files.
    # (SyncRunner's load-side withdrawal guard shares this value.)
    MASS_DELETION_THRESHOLD = 0.2

    # P11-7 — the systemic skip-visibility value. A cheap discovery-time census
    # of the content-pattern files discover did NOT turn into refs, so a silent
    # ingestion gap can never hide again. Two classes:
    #
    # - +skipped_by_rule+: an EXPLICIT, benign skip (a 0-byte ORACC catalog-only
    #   skeleton, a non-edition XML with no <text>) — honest, expected, quiet.
    # - +unrecognized+: a file, or a whole registered unit, that matches the
    #   source's shape yet discover cannot account for (an ORACC project whose
    #   tree exists but yields zero corpusjson — the nested-root signature).
    #   Rendered PROMINENTLY: unrecognized ≥ 1 is a defect, not a norm.
    #
    # +notes+ carries the human lines for the unrecognized cases. This covers
    # ONLY what never reached the loader; the loader's LoadReport reports the
    # fate (loaded / skipped-by-rule / quarantined) of every ref discover DID
    # yield, and the two combine into the printed discovery accounting.
    DiscoverySkips = Data.define(:skipped_by_rule, :unrecognized, :notes) do
      def initialize(skipped_by_rule: 0, unrecognized: 0, notes: [])
        super
      end

      def clean? = unrecognized.zero?
    end

    # Static metadata for the source: a Nabu::SourceManifest (id, name,
    # license + license_class, upstream URL, parser family).
    def self.manifest
      raise NotImplementedError, "#{self} must implement .manifest"
    end

    # The discovery census (see DiscoverySkips) over +workdir+. Default: discover
    # yields exactly one ref per content file, so nothing is skipped or
    # unaccounted. Adapters with real skip rules (ORACC 0-byte + nested-root,
    # GRETIL non-editions) override this — cheaply, no content reads beyond the
    # header peeks discover already does, and called once per sync (never in the
    # hot guard/load loops).
    def discovery_skips(_workdir)
      DiscoverySkips.new
    end

    # Instances answer for their manifest too, so callers holding an adapter
    # never need to reach for .class.
    def manifest
      self.class.manifest
    end

    # The concrete upstream git repositories this source pulls from — what the
    # P5-3 remote health probe runs `git ls-remote` against. Single-repo
    # adapters (the common case) use the manifest URL; multi-repo adapters (UD,
    # one git repo per treebank) override to list every repo, so a dead
    # treebank is caught individually rather than hidden behind an un-probeable
    # org URL. Ordered and stable.
    def self.upstream_repo_urls
      [manifest.upstream_url]
    end

    # What #parse yields, and therefore which loader a sync/rebuild routes to
    # (P11-4, architecture §11): :passages (Nabu::Document → Store::Loader,
    # every text corpus) or :dictionary (Nabu::DictionaryDocument →
    # Store::DictionaryLoader, the reference shelf). A closed set — a new
    # kind means a new loader and a deliberate routing decision, never a
    # silent fall-through.
    def self.content_kind = :passages

    # Does this adapter's parser extract descendant reflexes into
    # dictionary_reflexes (P14-1)? Declared HERE — beside content_kind, the
    # other loader-facing capability — so `nabu health` can hold the promise
    # against the catalog (P18-7 flag-vs-artifact: reflex code shipping with
    # 0 rows pending resync was a real silent state). The wiktionary
    # adapters override to true.
    def self.reflex_bearing? = false

    # Does this adapter's parsed data carry reference targets the links
    # journal should hold as kind=reference edges (P19-4, the local-library
    # manifests' related: urns; P25-0, CorPH's DIL headword ids; P25-1,
    # riig's RIG sigla and ogham's dil.ie word links)? Declared
    # HERE — beside content_kind and reflex_bearing?, the other capability
    # flags — so SyncRunner can refresh the source's reference producer
    # after every load without special-casing slugs. Default false.
    def self.reference_edges? = false

    # The producer SyncRunner runs for a reference_edges? source (P25-0):
    # anything with #run(slug, workdir:) returning a
    # LibraryReferences::Result-shaped value (+workdir+ is the source's
    # canonical dir — for the producer whose input is a canonical file, P32-6;
    # catalog-derived producers ignore it). Default: the P19-4
    # manifest-related: producer; an adapter whose reference edges come from
    # elsewhere (corph's token DIL ids, suttacentral's parallels graph)
    # overrides.
    def self.reference_producer(catalog:, journal:)
      LibraryReferences.new(catalog: catalog, journal: journal)
    end

    # Remote-health probe strategy (P11-2). Default :git — the probe
    # ls-remotes each upstream_repo_urls. The HTTP-zip fetch path (ORACC,
    # Nabu::ZipFetch) has NO git repo to ls-remote, so it overrides to
    # :http_zip: the probe HEADs each project zip (reachability +
    # Last-Modified drift vs the on-disk .zip-fetch.json pin) and GETs each
    # project metadata.json for license drift. See Nabu::Health::RemoteProbe.
    def self.remote_probe_strategy = :git

    # HTTP-zip probe targets — one HttpProbeTarget per fetched unit. Only
    # consulted for a :http_zip source; the default (:git) never calls it.
    def self.http_probe_targets = []

    # Bring upstream to the local canonical dir at +workdir+ (git pull,
    # rsync, HTTP crawl with cache). Must be resumable, rate-limit polite,
    # and NON-DESTRUCTIVE: upstream deletions are preserved under the attic
    # (git-based adapters delegate to Nabu::GitFetch via #git_fetch!), and a
    # mass deletion trips the breaker (Nabu::SyncAborted) BEFORE the working
    # tree changes unless +force+ is true. Returns a Nabu::FetchReport (sha,
    # fetched_at, notes); raises Nabu::FetchError on failure, which aborts
    # the sync.
    #
    # +progress+ is an optional callable receiving short human-readable lines
    # ("Cloning…", raw git progress lines) as the fetch proceeds, so callers can
    # show live progress on long fetches. It is nil-safe: adapters that cannot
    # report progress ignore it and behave exactly as before.
    def fetch(workdir, progress: nil, force: false)
      raise NotImplementedError, "#{self.class} must implement #fetch"
    end

    # Enumerate the ingestible documents found in +workdir+ as
    # Nabu::DocumentRef values (stable ids — stability across syncs is what
    # lets the loader detect upstream deletions).
    def discover(workdir)
      raise NotImplementedError, "#{self.class} must implement #discover"
    end

    # Parse the document behind one +document_ref+ into a Nabu::Document
    # with its ordered Nabu::Passage list.
    def parse(document_ref)
      raise NotImplementedError, "#{self.class} must implement #parse"
    end

    # discover, plus the attic overlay: after the live refs, the subclass's
    # own #discover runs against <workdir>/.attic and yields those refs
    # flagged retained (metadata RETAINED_KEY, plus RETIRED_SHA_KEY — the
    # upstream sha the file vanished at — when the attic manifest knows it).
    # ref.id == parse(ref).urn keeps holding for attic refs: only path and
    # metadata differ from what a live discovery would mint.
    #
    # A urn discovered BOTH live and in the attic is yielded once — live
    # wins — and the attic duplicate goes to +on_superseded+ (restructures
    # and reappearing documents self-heal instead of duplicating). This is
    # what the loader, the sync breaker's load-side prediction, rebuild and
    # verify all enumerate: retained documents are present, not withdrawn.
    def discover_with_attic(workdir, on_superseded: nil, &block)
      return enum_for(:discover_with_attic, workdir, on_superseded: on_superseded) unless block

      seen = Set.new
      discover(workdir).each do |ref|
        seen.add(ref.id)
        yield ref
      end
      each_attic_ref(File.join(workdir, ATTIC_DIRNAME)) do |ref|
        seen.add?(ref.id) ? yield(ref) : on_superseded&.call(ref)
      end
      self
    end

    private

    # The retained refs found under +attic+ (already deduplicated against
    # nothing — the caller owns live-wins).
    def each_attic_ref(attic)
      return unless Dir.exist?(attic)

      vanished = attic_vanished_shas(attic)
      discover(attic).each do |ref|
        metadata = ref.metadata.merge(RETAINED_KEY => true)
        metadata[RETIRED_SHA_KEY] = vanished[ref.path] if vanished.key?(ref.path)
        yield ref.with(metadata: metadata)
      end
    end

    # Absolute attic path → upstream sha it vanished at, merged from every
    # GitFetch manifest under the attic (multi-repo sources keep one per
    # repo subdir). A missing or corrupt manifest only costs the sha
    # annotation, never discovery.
    def attic_vanished_shas(attic)
      Dir.glob(File.join(attic, "**", GitFetch::ATTIC_MANIFEST)).each_with_object({}) do |manifest, map|
        root = File.dirname(manifest)
        JSON.parse(File.read(manifest)).each { |rel, sha| map[File.expand_path(File.join(root, rel))] = sha }
      rescue JSON::ParserError
        nil
      end
    end

    # The standard non-destructive fetch for adapters whose canonical dir is
    # ONE git repo (Perseus family, PROIEL family, Papyri): GitFetch guarded
    # by the mass-deletion breaker, wrapped into the usual FetchReport /
    # FetchError contract. Multi-repo adapters (UD) compose GitFetch phases
    # themselves. +ref+ pins the sync to a release tag (P17-1, Coptic
    # Scriptorium's versioned upstream — see GitFetch.sync!).
    def git_fetch!(repo_url:, workdir:, progress: nil, force: false, ref: nil, sparse: nil)
      result = GitFetch.sync!(
        repo_url: repo_url, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
        progress: progress, ref: ref, sparse: sparse,
        guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
      )
      FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
    rescue Shell::Error => e
      raise FetchError, "#{manifest.id} fetch failed for #{repo_url} into #{workdir}: #{e.message}"
    end

    # The pre-merge mass-deletion breaker (architecture §8): +doomed_paths+
    # are the absolute working-tree paths the pending merge would delete;
    # the predictor is the fraction of this source's ingestible files (what
    # #discover currently yields from the untouched tree) among them. Exact
    # for every current adapter (one ref per file); deletions of files
    # discover does not ingest (translations, metadata) never count. Raises
    # Nabu::SyncAborted — with the tree still byte-unchanged — unless +force+.
    def guard_mass_deletion!(workdir, doomed_paths, force:)
      return if force || doomed_paths.empty?

      ingestible = discover(workdir).to_set(&:path)
      doomed = doomed_paths.count { |path| ingestible.include?(path) }
      return if doomed <= MASS_DELETION_THRESHOLD * ingestible.size

      raise SyncAborted.new(existing_count: ingestible.size, would_withdraw_count: doomed,
                            threshold: MASS_DELETION_THRESHOLD)
    end

    # FetchReport.notes fragment for what a fetch atticked; nil when nothing
    # was (the common case — notes stay quiet).
    def attic_notes(atticked)
      return nil if atticked.empty?

      "atticked #{atticked.size} upstream-deleted file(s)"
    end
  end
end
