# frozen_string_literal: true

module Nabu
  module Ops
    # `rake stamps:rebless_by_proof` — the BY-PROOF sibling of
    # `rake stamps:rebless` (Ops::StampRebless; read its danger doctrine
    # first: everything there applies here). The situation it serves: a
    # semantic NO-OP refactor of derivation code (a pure move, a file fold, a
    # rename) re-hashes the shared core, every source's stamp reads dirty, and
    # the next incremental degenerates into a multi-day full replay that
    # reproduces byte-identical rows. Plain rebless would bless all of it on
    # the owner's word alone; by-proof makes current code DEMONSTRATE the
    # identity first, source by source.
    #
    # Per DIRTY source:
    #
    # 1. Eligibility (mechanical, before any parse): the stamp exists, the
    #    identity is not weak, and the stamp's migration level AND canonical
    #    identity both match the current fingerprint — so the drift lives
    #    only in code/config components (parser, fold, config). A canonical
    #    or migration drift, an unstamped or weak source, a non-passages
    #    content kind, or a declared secondary dictionary lane is NOT
    #    provable here and stays dirty, named.
    # 2. Discovery census: the adapter's full discover_with_attic (cheap
    #    directory walking, no parse) must still yield every live document
    #    the catalog holds for the source — a held urn no longer discovered
    #    is what a replay would withdraw.
    # 3. The sample: a deterministic stratified slice of the discovered refs
    #    (first, last, evenly spaced between; .sample_indices) is parsed
    #    through CURRENT code by exactly the call the replay makes
    #    (Adapter#parse on a discover_with_attic ref — Store::Loader#load_from's
    #    seam, minus the loader: nothing is written), and each produced
    #    document is byte-compared against the catalog's stored rows: passage
    #    count, then per passage (sequence order) urn and text, then the
    #    passage content sha (language, normalized text, annotations,
    #    sequence) and the document sha, metadata JSON, license override and
    #    retirement flag — every column the loader's upsert would touch. A
    #    sampled ref the catalog does NOT hold must still be declined
    #    (DocumentSkipped/ParseError) — current code producing a document
    #    there is a divergence too.
    #
    # Identical ⇒ the source's stamp is rewritten through StampRebless's own
    # write path. ANY divergence ⇒ the stamp is untouched and the source is
    # NAMED with the first diverging urn and a hint of the difference.
    #
    # WHAT THE PROOF COVERS — AND DOES NOT. It covers CODE: current code,
    # run over the canonical bytes the stamp was minted from, reproduces the
    # catalog on the sample. It does not cover DATA (hence the attestation:
    # canonical unchanged since the stamps were minted — re-checked
    # mechanically through the canonical identity where the tree can be
    # named), and a sample is evidence, not exhaustion: a change that alters
    # only documents the sample missed passes. It is the instrument for
    # UNIFORM no-op refactors; for a change that targets a subset of
    # documents, run the incremental rebuild.
    #
    # Never fetches, never touches the network: discover + parse over the
    # local canonical tree only. Lives in ops/ deliberately (excluded from
    # the fingerprint's shared core, like StampRebless).
    class StampProof
      ATTESTATION = "i-verified-canonical-unchanged-since-stamping"
      DEFAULT_SAMPLE = 20

      # What a run decided. +proven+/+diverged+/+unprovable+ are Verdicts;
      # +cleans+ the slugs already clean (nothing to prove).
      Result = Data.define(:proven, :diverged, :unprovable, :cleans)

      # One source's by-proof verdict: +state+ :proven | :diverged |
      # :unprovable; +urn+ the first diverging urn (diverged only); +detail+
      # the hint / reason; +sampled+/+total+ the sample against discovery.
      Verdict = Data.define(:slug, :state, :drift, :urn, :detail, :sampled, :total) do
        def initialize(slug:, state:, drift: nil, urn: nil, detail: nil, sampled: nil, total: nil)
          super
        end
      end

      # A divergence found while comparing (internal flow control).
      Divergence = Data.define(:urn, :detail)

      # Drift components the proof can cover: code and config, never data.
      PROVABLE_DRIFT = %i[parser fold config].freeze

      # The deterministic stratified sample over +total+ discovered refs:
      # indices of the first, the last, and evenly spaced refs between,
      # +size+ in all (every index when total <= size). Pure arithmetic —
      # the same (total, size) always names the same refs.
      def self.sample_indices(total, size)
        return [] if total.zero? || size < 1
        return (0...total).to_a if total <= size
        return [0] if size == 1

        (0...size).map { |i| (i * (total - 1).fdiv(size - 1)).round }.uniq
      end

      def initialize(config:, registry:)
        @config = config
        @registry = registry
      end

      # Prove-then-rebless every dirty source; print the estimate, one
      # verdict line per dirty source and a closing tally to +out+. Raises
      # Nabu::Error on a refused attestation, a bad sample size, a missing
      # catalog or catalog/code schema drift.
      def run(attestation:, sample: DEFAULT_SAMPLE, out: $stdout)
        refuse_attestation!(attestation)
        sample = sample_size!(sample)
        refuse_catalog!
        db = Store.connect(@config.catalog_path)
        rebless = StampRebless.new(config: @config, registry: @registry)
        rebless.refuse_schema_drift!(db)
        prove_all(db, rebless, sample, out)
      ensure
        db&.disconnect
      end

      private

      def refuse_attestation!(attestation)
        return if attestation == ATTESTATION

        raise Nabu::Error,
              "stamps:rebless_by_proof REFUSED. This re-parses a SAMPLE of each dirty source " \
              "through current code and, where the sample matches the catalog byte for byte, " \
              "rewrites the source's derivation stamp WITHOUT re-deriving it. The proof covers " \
              "CODE, not DATA: it is valid ONLY when canonical/ is unchanged since the stamps " \
              "were minted, and only for uniform no-op refactors (pure moves) — a change " \
              "touching documents the sample misses blesses rows current code would not " \
              "produce, and every future incremental silently skips the drift " \
              "(under-derivation, no error anywhere); when in doubt run the incremental or a " \
              "full rebuild. If — and only if — canonical is verified unchanged since " \
              "stamping, run: rake \"stamps:rebless_by_proof[#{ATTESTATION}]\" " \
              "(optional second argument: documents sampled per source, default #{DEFAULT_SAMPLE})"
      end

      def sample_size!(sample)
        value = sample.nil? || sample.to_s.empty? ? DEFAULT_SAMPLE : Integer(sample.to_s, 10)
        raise Nabu::Error, "stamps:rebless_by_proof: sample must be >= 2 (got #{value})" if value < 2

        value
      rescue ArgumentError
        raise Nabu::Error, "stamps:rebless_by_proof: sample must be an integer (got #{sample.inspect})"
      end

      def refuse_catalog!
        return if File.exist?(@config.catalog_path)

        raise Nabu::Error,
              "no catalog at #{@config.catalog_path} — nothing to prove; full rebuild required"
      end

      def prove_all(db, rebless, sample, out)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        swept = sweep(db)
        clean, dirty = swept.partition { |_, _, _, drift| drift.nil? }
        cleans = clean.map { |entry, *| entry.slug }
        out.puts estimate_line(dirty, sample, cleans.size)
        out.flush if out.respond_to?(:flush)
        verdicts = dirty.map do |entry, fingerprint, stamp, drift|
          verdict = prove_source(db, entry, fingerprint, stamp, drift, sample)
          report(verdict, out)
          rebless.rebless_source(db, fingerprints, entry, out) if verdict.state == :proven
          out.flush if out.respond_to?(:flush)
          verdict
        end
        result = Result.new(proven: verdicts.select { |v| v.state == :proven },
                            diverged: verdicts.select { |v| v.state == :diverged },
                            unprovable: verdicts.select { |v| v.state == :unprovable },
                            cleans: cleans)
        out.puts tally(result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
        result
      end

      # [entry, fingerprint, stamp, drift] per replayable source; drift nil =
      # clean. The verdict logic is IncrementalRebuild's own
      # (Fingerprint#drift_against, fold scoped by the language census).
      def sweep(db)
        @registry.each_source.select { |entry| replayable?(entry) }.map do |entry|
          languages = Store::DerivationStamp.derived_languages(db, entry.slug)
          fingerprint = fingerprints.for_source(entry, languages: languages)
          stamp = Store::DerivationStamp.fetch(db, entry.slug)
          [entry, fingerprint, stamp, fingerprint.drift_against(stamp)]
        end
      end

      def prove_source(db, entry, fingerprint, stamp, drift, sample)
        reason = unprovable_reason(db, entry, fingerprint, stamp, drift)
        return Verdict.new(slug: entry.slug, state: :unprovable, drift: drift, detail: reason) if reason

        source_id = db[:sources].where(slug: entry.slug).get(:id)
        adapter = entry.build_adapter
        refs = adapter.discover_with_attic(@config.source_workdir(entry.slug)).to_a
        indices = self.class.sample_indices(refs.size, sample)
        divergence = census_divergence(db, source_id, refs) ||
                     indices.lazy.filter_map { |index| ref_divergence(db, source_id, adapter, refs[index]) }.first
        state = divergence ? :diverged : :proven
        Verdict.new(slug: entry.slug, state: state, drift: drift, urn: divergence&.urn,
                    detail: divergence&.detail, sampled: indices.size, total: refs.size)
      end

      def unprovable_reason(db, entry, fingerprint, stamp, drift)
        return "#{drift} drift — the proof covers code, not data" unless provable_drift?(drift)
        return "stamp/fingerprint component mismatch beyond code" unless code_only_drift?(fingerprint, stamp)

        kind = entry.adapter_class.content_kind
        return "content kind #{kind} — by-proof covers passage sources only" unless kind == :passages
        if entry.adapter_class.dictionary_lane
          return "declares a secondary dictionary lane — by-proof covers passages only"
        end
        return "no sources row in the catalog" if db[:sources].where(slug: entry.slug).empty?

        nil
      end

      # A fold drift arrives as :fold (the String "fold(...)" is only the
      # owner-facing rendering IncrementalRebuild prints).
      def provable_drift?(drift) = PROVABLE_DRIFT.include?(drift)

      # Belt and braces over drift_against's first-blame order: the DATA
      # components must match the stamp directly (a parser drift must not
      # mask a canonical one) — the same direct comparison IncrementalRebuild
      # #trustable? makes.
      def code_only_drift?(fingerprint, stamp)
        !stamp.nil? && !fingerprint.weak? &&
          stamp[:migration_level] == fingerprint.migration_level &&
          stamp[:canonical_identity] == fingerprint.canonical_identity
      end

      # A live catalog document whose urn discovery no longer yields — what
      # the replay's full-load sweep would withdraw.
      def census_divergence(db, source_id, refs)
        discovered = refs.to_set(&:id)
        missing = db[:documents].where(source_id: source_id, withdrawn: false).order(:urn).select_map(:urn)
                                .find { |urn| !discovered.include?(urn) }
        return nil if missing.nil?

        Divergence.new(urn: missing, detail: "held document no longer discovered (a replay would withdraw it)")
      end

      def ref_divergence(db, source_id, adapter, ref)
        row = db[:documents].where(source_id: source_id, urn: ref.id, withdrawn: false).first
        document = parse_or_decline(adapter, ref)
        if document.is_a?(Nabu::Error)
          return nil if row.nil?

          return Divergence.new(urn: ref.id, detail: "held document now declined by current code " \
                                                     "(#{document.class}: #{clip(document.message)})")
        end
        if row.nil?
          return Divergence.new(urn: ref.id, detail: "current code yields a document the catalog does not hold")
        end

        document_divergence(db, row, document, ref)
      end

      # The replay's own parse call; a decline (DocumentSkipped/ParseError —
      # the loader's skip/quarantine) comes back as the error value. Any
      # other error propagates and aborts the run, exactly as it aborts a load.
      def parse_or_decline(adapter, ref)
        adapter.parse(ref)
      rescue Nabu::DocumentSkipped, Nabu::ParseError => e
        e
      end

      def document_divergence(db, row, document, ref)
        stored = db[:passages].where(document_id: row[:id], withdrawn: false).order(:sequence)
                              .select(:urn, :sequence, :text, :content_sha256).all
        parsed = document.passages.sort_by(&:sequence)
        if stored.size != parsed.size
          return Divergence.new(urn: document.urn,
                                detail: "passage count: catalog #{stored.size} vs current code #{parsed.size}")
        end

        passage_divergence(stored, parsed) || document_fields_divergence(row, document, ref)
      end

      def passage_divergence(stored, parsed)
        stored.zip(parsed).each_with_index do |(held, made), index|
          if held[:urn] != made.urn
            return Divergence.new(urn: held[:urn], detail: "passage #{index} urn: catalog #{held[:urn]} vs " \
                                                           "current code #{made.urn}")
          end
          if held[:text] != made.text
            return Divergence.new(urn: held[:urn], detail: "text: catalog #{clip(held[:text])} vs " \
                                                           "current code #{clip(made.text)}")
          end
          next if held[:content_sha256] == Store::ContentHash.passage(made)

          return Divergence.new(urn: held[:urn],
                                detail: "passage sha differs (language, normalized text, annotations or sequence)")
        end
        nil
      end

      def document_fields_divergence(row, document, ref)
        hint =
          if row[:content_sha256] != document_sha(document)
            "document sha differs (title, language or canonical path)"
          elsif row[:metadata_json] != Store::ContentHash.canonical_json(document.metadata)
            "metadata differs"
          elsif row[:license_override] != document.license_override
            "license override differs"
          elsif row[:retired_upstream] != (ref.metadata[Nabu::Adapter::RETAINED_KEY] ? true : false)
            "retirement flag differs"
          end
        hint && Divergence.new(urn: document.urn, detail: hint)
      end

      # Exactly the loader's document sha: passage shas keyed by urn in parse
      # order (Store::Loader#encode_passages), then ContentHash.document.
      def document_sha(document)
        shas = document.passages.to_h { |passage| [passage.urn, Store::ContentHash.passage(passage)] }
        Store::ContentHash.document(document, shas.values)
      end

      def clip(text, limit = 60)
        text = text.to_s
        (text.length > limit ? "#{text[0, limit]}…" : text).inspect
      end

      def report(verdict, out)
        case verdict.state
        when :proven
          out.puts "  proven  #{verdict.slug} — #{verdict.sampled}/#{verdict.total} sampled identical " \
                   "(#{verdict.drift} drift)"
        when :diverged
          out.puts "  DIVERGE #{verdict.slug} — #{verdict.urn}: #{verdict.detail} — stays dirty"
        else
          out.puts "  dirty   #{verdict.slug} — not provable: #{verdict.detail} — stays dirty"
        end
      end

      def tally(result, seconds)
        "by-proof: #{result.proven.size} proven + reblessed · #{result.diverged.size} diverged · " \
          "#{result.unprovable.size} not provable · #{result.cleans.size} already clean " \
          "(#{Nabu::Eta.format_seconds(seconds)})"
      end

      # The up-front estimate: each dirty source's last rebuild :load timing
      # (Store::StageTimings, rows = documents replayed) scaled to the sample
      # size — an over-estimate (a replay also inserts) that excludes the
      # discovery walks; sources with no history say so, never a guess.
      def estimate_line(dirty, sample, clean_count)
        with_readonly_ledger do |ledger|
          estimates = dirty.map do |entry, *|
            Nabu::Eta.for(ledger, kind: "rebuild", scope: entry.slug, stage: "load", rows: sample)
          end
          known = estimates.select(&:real?)
          seconds = known.sum(&:seconds)
          estimate = known.empty? ? "no ledger history — no estimate" : "~#{Nabu::Eta.format_seconds(seconds)}"
          unknown = estimates.size - known.size
          missing = unknown.positive? && known.any? ? "; #{unknown} without history" : nil
          "by-proof: #{dirty.size} dirty sources (#{clean_count} clean), sampling up to #{sample} documents " \
            "each — #{estimate} (rebuild load timings scaled to the sample; discovery walks excluded#{missing})"
        end
      end

      def with_readonly_ledger
        return yield(nil) unless File.exist?(@config.history_path)

        ledger = Store.connect(@config.history_path, readonly: true)
        yield ledger
      ensure
        ledger&.disconnect
      end

      # The incremental sweep's identity memos (:use — derived db/ data), so
      # a by-proof run pays no more tree hashing than a dry run does.
      def fingerprints
        @fingerprints ||= DerivationFingerprint.new(
          config: @config,
          identity_cache: CanonicalIdentityCache.for_config(@config, mode: :use),
          repo_cache: GitIdentityCache.for_config(@config, mode: :use)
        )
      end

      # Same rule as Rebuild#replayable?: local canonical data exists.
      def replayable?(entry)
        dir = @config.source_workdir(entry.slug)
        Dir.exist?(dir) && !Dir.empty?(dir)
      end
    end
  end
end
