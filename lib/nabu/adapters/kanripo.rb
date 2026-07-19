# frozen_string_literal: true

module Nabu
  module Adapters
    # Kanripo / Kanseki Repository (P33-0) — the open Classical Chinese
    # library: github.com/kanripo, ONE GITHUB REPO PER TEXT (9,355 repos at
    # the 2026-07-20 census; the KR-Catalog lists 10,080 ids — 61 wave-1 ids
    # have no repo, the recorded-absent path). nabu's first many-repo
    # source: all fetching is Nabu::KanripoFetch (catalog-driven scope,
    # per-text shallow GitFetch, polite pacing, resumable per-text ledger
    # pins — the design note lives on that class and architecture §8).
    #
    # == Scope: classes (config/sources.yml `classes:`)
    #
    # The KR id's prefix is its 四部-style class: KR1 經 classics, KR2 史
    # histories, KR3 子 masters, KR4 集 belles-lettres, KR5 道 Daoist canon,
    # KR6 佛 Buddhist canon. Wave 1 (owner-widened at the P33 gate) is
    # KR1+KR3+KR4 (2,934 repos, ~1.25 GB git size at census); KR2/KR5 are
    # P33-1, KR6 is EXCLUDED this phase (doctrine call journaled in
    # 02-sources: CBETA is the scholarly Buddhist shelf). `classes:` scopes
    # ACQUISITION only — discover ingests whatever texts are on disk, so an
    # owner narrowing the config never mass-withdraws held texts.
    #
    # == Identity (FROZEN minting)
    #
    # Document per text: urn:nabu:kanripo:<KR-id>. Passage per PAGE of the
    # base edition: <doc-urn>:<juan>:<leaf><side> from the `<pb:>` anchors
    # (the mandoku census: anchors carry no line component, so leaf-side is
    # the citation grain). Edition choice: Kanripo keeps alternate editions
    # as git BRANCHES of each text repo (censused: master + e.g. WYG/SBCK/
    # _data); the master working tree IS the BASEEDITION text (its header
    # names it — CHANT, WYG, SBCK … in the probe set), and nabu syncs
    # master only. The edition rides document metadata and the verbatim
    # anchors, so a future multi-edition wave can mint edition-qualified
    # documents WITHOUT touching these urns.
    #
    # == License (the org-level grant, recorded verbatim)
    #
    # The github org description is verbatim: "Comprehensive collection of
    # premodern Chinese texts. Licensed as CC BY SA 4.0." — sampled repos
    # carry NO per-repo LICENSE file (github license field null).
    # Corroboration: ytenx's DATA_LICENSE.md ("Kanseki Repository material
    # marked as CC BY-SA must be used under the applicable Creative Commons
    # Attribution-ShareAlike terms"). A belt-and-braces confirmation email
    # to Christian Wittern is SENT and NON-BLOCKING (№25, 2026-07-20) →
    # license_class attribution on the org-level grant.
    #
    # Gaiji: `&KR0809;`-style refs stay verbatim in text + annotations; the
    # KR-Gaiji repo is journaled, never fetched (no resolution this phase).
    class Kanripo < Nabu::Adapter
      ORG_URL = "https://github.com/kanripo"
      CATALOG_URL = "#{ORG_URL}/KR-Catalog".freeze

      # Wave 1 (P33-0). The registry's `classes:` list overrides this.
      DEFAULT_CLASSES = %w[KR1 KR3 KR4].freeze
      VALID_CLASS = /\AKR[1-6]\z/

      TEXT_DIR = /\AKR\d[a-z]\d{4}\z/
      URN_PREFIX = "urn:nabu:kanripo:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "kanripo",
        name: "Kanripo — Kanseki Repository 漢籍リポジトリ (wave 1: KR1 classics, KR3 masters, KR4 belles-lettres)",
        license: "Org-level grant verbatim: \"Comprehensive collection of premodern Chinese texts. " \
                 "Licensed as CC BY SA 4.0.\" (github.com/kanripo org description; no per-repo LICENSE " \
                 "file; corroborated by ytenx DATA_LICENSE.md; confirmation email to C. Wittern sent " \
                 "2026-07-20, non-blocking)",
        license_class: "attribution",
        upstream_url: ORG_URL,
        parser_family: "mandoku"
      )

      def self.manifest
        MANIFEST
      end

      # The org URL is not ls-remote-able; the honest probe target is the
      # discovery index every sync starts from. Per-text pins live in the
      # fetch ledger, not the ledger pins table (2,934 rows would say less
      # than the one catalog pin the wave is keyed by).
      def self.upstream_repo_urls
        [CATALOG_URL]
      end

      attr_reader :classes

      def initialize(classes: DEFAULT_CLASSES)
        super()
        unless classes.is_a?(Array) && !classes.empty? && classes.all? { |c| c.is_a?(String) && c.match?(VALID_CLASS) }
          raise ValidationError, "kanripo classes must be a non-empty list matching KR1–KR6, got #{classes.inspect}"
        end

        @classes = classes.uniq
      end

      # One ref per text dir on disk (sorted; the catalog clone, ledger and
      # attic are not texts). `classes:` deliberately does not filter here —
      # see the class note.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        text_dirs(workdir).each do |dir|
          id = File.basename(dir)
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{id}", path: dir,
            metadata: { "class" => id[0, 3] }
          )
        end
      end

      def parse(document_ref)
        MandokuParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          text_id: File.basename(document_ref.path)
        )
      end

      # The many-repo wave (KanripoFetch, the §8 design note). The report
      # pin is the CATALOG sha — the wave identity every per-text ledger pin
      # is keyed by.
      def fetch(workdir, progress: nil, force: false)
        result = KanripoFetch.sync!(
          catalog_url: catalog_url, repo_base: repo_base,
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          classes: classes, delay: fetch_delay, progress: progress,
          guard: ->(text_dir, doomed) { guard_text_deletion!(text_dir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.catalog_sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::Shell::Error, KanripoFetch::Error => e
        raise Nabu::FetchError, "kanripo fetch failed into #{workdir}: #{e.message}"
      end

      private

      # Test seams (the UD repo_url precedent): fetch tests point these at
      # local rigs. fetch_delay is the polite-pacing knob — override here if
      # the owner ever wants a different rhythm (KanripoFetch::DEFAULT_DELAY
      # documents the default).
      def catalog_url = CATALOG_URL
      def repo_base = ORG_URL
      def fetch_delay = KanripoFetch::DEFAULT_DELAY

      # The per-text mass-deletion breaker (see KanripoFetch: texts complete
      # sequentially, so the guard protects at text grain — stricter than a
      # source-wide fraction). Doomed non-content files (Readme.org) never
      # count.
      def guard_text_deletion!(text_dir, doomed, force:)
        return if force || doomed.empty?

        ingestible = Dir.glob(File.join(text_dir, "KR*_*.txt")).to_set { |path| File.expand_path(path) }
        doomed_texts = doomed.count { |path| ingestible.include?(path) }
        return if doomed_texts <= MASS_DELETION_THRESHOLD * ingestible.size

        raise Nabu::SyncAborted.new(existing_count: ingestible.size,
                                    would_withdraw_count: doomed_texts,
                                    threshold: MASS_DELETION_THRESHOLD)
      end

      def fetch_notes(result)
        notes = "catalog=#{result.catalog_sha[0, 12]} classes=#{classes.join(',')} " \
                "cloned #{result.cloned.size} · refreshed #{result.refreshed.size} · " \
                "skipped #{result.skipped} · absent #{result.absent.size}"
        notes += " · atticked #{result.atticked.size} upstream-deleted file(s)" unless result.atticked.empty?
        notes
      end

      def text_dirs(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.children(workdir).sort
           .grep(TEXT_DIR)
           .map { |name| File.join(workdir, name) }
           .select { |dir| File.directory?(dir) }
      end
    end
  end
end
