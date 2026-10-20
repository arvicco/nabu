# frozen_string_literal: true

require "digest"
require "json"

module Nabu
  # Per-scope derivation stamps for the links stage (owner ruling
  # 2026-10-19; architecture §15). The links stage is the heaviest corpus
  # stage of a replay (3h46m of the 2026-10-15 full rebuild's 13.5h, almost
  # all of it three batch scopes); before this, every rebuild — and every
  # dirty incremental — wiped the journal and re-mined every recorded
  # scope. Edges are urn-keyed and live in their own db, so nothing in a
  # carried scope dangles on re-minted catalog ids: a scope whose inputs
  # are provably unchanged can keep its edges. The vectors posture
  # (expensive-derived, content-keyed, never dropped blind) generalized.
  #
  # == The stamp (one per recorded link_scopes.yml scope)
  #
  # sha256 over the scope's INPUTS, every one of which can change output:
  #
  # - producer_code — a digest of the producer's code closure: the
  #   transitive require_relative closure of its root file(s) plus the
  #   shared replay code (LinkScopeReplay, LinksJournal) and declared
  #   extras. Test-pinned by TracePoint: every lib file a real replay
  #   executes must sit inside the closure (link_stamps_test), so a code
  #   change can never hide behind a carried scope.
  # - params — the recorded params, plus (parallels) the RESOLVED reuse
  #   profile: retuning config/reuse_profiles.yml retunes the replay, so it
  #   moves the stamp even under the same profile name.
  # - members — the member sources' CONTENT identities
  #   (Store::SourceContentIdentity: live documents' and entries' content
  #   shas). Content, not derivation stamps: a content-neutral loader edit
  #   moves every derivation fingerprint while leaving the rows the miners
  #   read byte-identical — and that is exactly the full rebuild the cache
  #   must survive. A source that re-parsed to different content moves its
  #   identity and re-mines every scope it is a member of.
  #   Membership is per producer, declared below: a SCOPE-LOCAL producer
  #   (formulas, the place pair) reads only its slice's sources; parallels
  #   is GLOBAL — it scores by corpus-wide gram document frequency and
  #   finds candidates anywhere, so every source is a member.
  # - extras — what else the producer reads: the fulltext-index identity
  #   (parallels: index-core code digest + stage versions + the registry's
  #   index flags), the gazetteer's name keys and the hand stop list
  #   (place-mine), the nabu-places registry tree (place-link).
  #
  # == Carrying is per COMPONENT, not per scope
  #
  # LinksJournal.write_edge! keeps one edge per pair per kind ACROSS runs
  # (a later run refreshes, and so owns, an earlier run's edge), and
  # place-link promotes place-mine's candidate edges. So scopes sharing an
  # edge kind (written or read) are one component: a dirty scope re-mines
  # its whole component, in replay order — the exact sequence a full
  # re-mine runs, hence the same final edges. Components never share a
  # kind, so carried and re-mined edges cannot interact. A component
  # carries only when every scope in it is stampable, its stored stamp
  # matches, and the journal holds EXACTLY the runs the stamps name (a
  # stray or half-finished run of the producer dirties it).
  #
  # Volatile producers are never carried: cognates reads the lect facets,
  # the lemma tiers and the alignment/reflex index — inputs no member
  # identity covers — and re-mines in seconds; the slug-scoped reference
  # lane (Rebuild#rederive_links!) re-runs whole every stage (~100 s),
  # since trismegistos-style producers read their peers' edges.
  #
  # == The self-check (the derivability guarantee kept auditable)
  #
  # Every SELF_CHECK_EVERY-th links stage (or on the owner's
  # `--full-links`) carries NOTHING: every scope re-mines, and each scope
  # that WOULD have been carried has its edges digested before and after
  # (LinksJournal.edge_digests — pair, kind, score, detail; never ids or
  # timestamps). A difference is DRIFT: the stamp vouched for edges a
  # fresh mine no longer produces — a real incident (an input the stamp
  # misses), announced loudly and carried into the rebuild summary. The
  # fresh mine is kept either way, so the journal ends correct.
  #
  # == The code-change recheck
  #
  # A scope re-mined because ONLY its producer code moved (its blame is
  # exactly producer_code — or it was dragged by such a component-mate
  # with its own stamp unchanged) is compared the same way, on any stage:
  # its stamped edges are digested before they are dropped. Equal digests
  # are REPRODUCED — a performance-only rewrite proves itself on the first
  # live stage after it lands; a difference is CHANGED, reported beside
  # the summary but never drift (a code change may legitimately move
  # output). A scope whose members or params moved too is not rechecked:
  # a difference there would prove nothing.
  class LinkStamps
    LIB_DIR = File.expand_path(__dir__)

    # const: the self-check cadence. Every 4th links stage re-derives every
    # scope and compares. The economics (2026-10-15 ledger): the stage costs
    # ~3.8 h and is ~28 % of a full replay; full rebuilds ran every 1-8
    # days through October. N=4 keeps three quarters of the cache's win
    # (~2.8 h saved per rebuild on average when inputs are unchanged)
    # while bounding a lying stamp's life to three carried rebuilds —
    # about one to two weeks at that cadence. A larger N buys under 10 %
    # more saving per step at a proportionally longer exposure; the owner
    # forces one any time with `--full-links`.
    SELF_CHECK_EVERY = 4

    # Code every batch replay runs, whatever the producer.
    SHARED_ROOTS = %w[link_scope_replay.rb store/links_journal.rb].freeze

    # One producer's stamping posture. +kinds+ are the edge kinds it
    # writes OR reads (the component key); +roots+ the files its code
    # closure starts from; +membership+ :scope | :global; +volatile+ a reason
    # string when the producer is never stamped (then nothing else
    # matters).
    Producer = Data.define(:kinds, :roots, :membership, :volatile) do
      def initialize(kinds:, roots: [], membership: :scope, volatile: nil)
        super
      end
    end

    PRODUCERS = {
      "parallels" => Producer.new(kinds: %w[parallel],
                                  roots: %w[batch_parallels.rb reuse_profiles.rb store/cjk_bigrams.rb],
                                  membership: :global),
      "formulas" => Producer.new(kinds: %w[formula], roots: %w[batch_formulas.rb]),
      "place-mine" => Producer.new(kinds: %w[place-candidate], roots: %w[place_mine.rb]),
      "place-link" => Producer.new(kinds: %w[place place-candidate], roots: %w[place_link.rb]),
      "cognates" => Producer.new(kinds: %w[cognate],
                                 volatile: "reads the lect facets, lemma tiers and alignment/reflex " \
                                           "index — inputs no member identity covers; re-mines in seconds")
    }.freeze

    # One recorded scope, stamped (or volatile). +inputs+ is the stamp's
    # preimage, stored beside it so a re-mine can NAME what moved.
    Unit = Data.define(:producer, :scope, :params, :kinds, :stamp, :inputs, :volatile) do
      def key = [producer, scope]

      def label = "#{producer} #{scope}"

      # The input names whose value differs from +stored+ (a stored inputs
      # hash) — what the re-mine announcement blames.
      def blame(stored)
        return [] if stored.nil? || inputs.nil?

        (inputs.keys | stored.keys).reject { |name| inputs[name] == stored[name] }.sort
      end
    end

    # The links stage's batch-half plan. +carried_keys+ are kept as-is;
    # +verify_runs+ (self-check only: { key => stamped run ids }) would have
    # been carried and are compared after their re-mine; +reasons+ maps a
    # re-mined unit's key to why (blamed inputs, "unstamped", "volatile",
    # "component (...)", "self-check").
    # +recheck_runs+ ({ key => stamped run ids }) the code-only re-mines
    # compared after their re-mine (the code-change recheck).
    Plan = Data.define(:units, :carried_keys, :carried_run_ids, :self_check, :verify_runs, :reasons,
                       :recheck_runs) do
      def carried?(unit) = carried_keys.include?(unit.key)

      def verify_keys = verify_runs.keys

      def mode
        return "self-check" if self_check && verify_runs.any?

        carried_keys.empty? ? "full" : "stamped"
      end
    end

    # What the batch half of one links stage did — the rebuild summary's
    # links line. Lists hold "producer scope" labels; +drift+ one line per
    # drifted scope; +reasons+ label => why it re-mined; +failures+ the
    # contained producer failures (reference lane included);
    # +next_check_in+ stamped stages left before the next self-check;
    # +reproduced+ / +changed+ the code-change recheck's verdicts (labels /
    # one line per changed scope).
    Outcome = Data.define(:mode, :mined, :carried, :verified, :drift, :reasons, :failures, :next_check_in,
                          :reproduced, :changed) do
      def summary
        line = mode_summary
        return line if reproduced.empty? && changed.empty?

        verdict = "reproduced #{reproduced.size} exactly"
        verdict += ", changed #{changed.size}: #{changed.join(' · ')}" unless changed.empty?
        "#{line} · code-change re-mines: #{verdict}"
      end

      def mode_summary
        case mode
        when "self-check"
          verdict = drift.empty? ? "no drift" : "DRIFT in #{drift.size}: #{drift.join(' · ')}"
          "links self-check: re-mined #{mined.size} scope(s), verified #{verified.size} against " \
            "their stamps — #{verdict}"
        when "stamped"
          "links: carried #{carried.size} scope(s) on their stamps (#{carried.join(', ')}), " \
          "mined #{mined.size} · self-check in #{next_check_in} stage(s)"
        else
          "links: mined #{mined.size} scope(s) — nothing carried (no matching stamps)"
        end
      end
    end

    class << self
      # The producer's code closure: absolute paths, sorted.
      def code_files(producer)
        spec = PRODUCERS.fetch(producer)
        queue = (spec.roots + SHARED_ROOTS).map { |rel| File.join(LIB_DIR, rel) }
        closure = []
        until queue.empty?
          file = queue.shift
          next if closure.include?(file) || !File.file?(file)

          closure << file
          queue.concat(required_files(file))
        end
        closure.sort
      end

      # { producer => digest } for every stampable producer — pinned at
      # rebuild START (the P89-1 lesson: a stamp minted hours into a run
      # must describe the code the run loaded, not the bytes on disk by
      # then).
      def code_digests
        PRODUCERS.reject { |_name, spec| spec.volatile }.to_h do |name, _spec|
          tokens = code_files(name).map { |file| "#{file.delete_prefix("#{LIB_DIR}/")}:#{code_file_digest(file)}" }
          [name, Digest::SHA256.hexdigest(tokens.join("\n"))]
        end
      end

      # Seam (tests divert one file to simulate a code change).
      def code_file_digest(path) = Digest::SHA256.file(path).hexdigest

      private

      def required_files(file)
        paths = File.read(file).scan(/^\s*require_relative\s+["']([^"']+)["']/).flatten.map do |rel|
          path = File.expand_path(rel, File.dirname(file))
          path.end_with?(".rb") ? path : "#{path}.rb"
        end
        paths.select { |path| path.start_with?(LIB_DIR) }
      end
    end

    # +catalog+ the (final) catalog the producers read; +config+ for the
    # canonical dir (the nabu-places tree); +registry+ (SourceRegistry or
    # nil) for the index flags; +code_digests+ the run-start pin (computed
    # now when not given).
    def initialize(catalog:, config:, registry:, code_digests: nil)
      @catalog = catalog
      @config = config
      @registry = registry
      @code_digests = code_digests || self.class.code_digests
      @members = {}
    end

    # The stamped (or volatile) unit for one recorded scope hash.
    def unit(scope)
      producer = scope["producer"]
      params = scope["params"] || {}
      spec = PRODUCERS[producer]
      if spec.nil? || spec.volatile
        return Unit.new(producer: producer, scope: scope["scope"], params: params,
                        kinds: spec&.kinds || ["?#{producer}"], stamp: nil, inputs: nil,
                        volatile: spec ? spec.volatile : "unknown producer")
      end

      inputs = inputs_for(producer, spec, scope["scope"], params)
      volatile = inputs.delete(:volatile)
      stamp = volatile ? nil : Digest::SHA256.hexdigest(JSON.generate(inputs.sort.to_h))
      Unit.new(producer: producer, scope: scope["scope"], params: params, kinds: spec.kinds,
               stamp: stamp, inputs: volatile ? nil : inputs, volatile: volatile)
    end

    # Decide what the stage carries. +scopes+ in replay order
    # (LinkScopeReplay.order); +force_full+ the owner's --full-links.
    def plan(scopes, journal:, force_full: false)
      units = scopes.map { |scope| unit(scope) }
      stored = Store::LinksJournal.scope_stamps(journal)
      self_check = force_full ||
                   Store::LinksJournal.stamped_streak(journal) >= SELF_CHECK_EVERY - 1
      clean_keys = []
      clean_runs = []
      reasons = {}
      components(units).each do |members|
        verdict = component_verdict(members, stored, journal)
        if verdict.nil?
          clean_keys.concat(members.map(&:key))
          clean_runs.concat(members.flat_map { |unit| stored.fetch(unit.key)[:run_ids] })
        else
          members.each { |unit| reasons[unit.key] = verdict.call(unit) }
        end
      end
      recheck = recheck_runs(units, stored, reasons)
      if self_check
        clean_keys.each { |key| reasons[key] = "self-check" }
        Plan.new(units: units, carried_keys: [], carried_run_ids: [], self_check: true,
                 verify_runs: clean_keys.to_h { |key| [key, stored.fetch(key)[:run_ids]] }, reasons: reasons,
                 recheck_runs: recheck)
      else
        Plan.new(units: units, carried_keys: clean_keys, carried_run_ids: clean_runs.sort, self_check: false,
                 verify_runs: {}, reasons: reasons, recheck_runs: recheck)
      end
    end

    # The stage's opening move under +plan+: digest what the self-check
    # will compare, drop the stamps of everything about to re-mine (FIRST —
    # a crash mid-mine must never leave a stamp vouching for edges that are
    # gone), then every run the plan does not carry. Returns the expected
    # digests for #mine!.
    def prepare!(plan, journal:)
      expected = plan.verify_runs.merge(plan.recheck_runs)
                     .transform_values { |ids| Store::LinksJournal.edge_digests(journal, ids) }
      Store::LinksJournal.retain_scope_stamps!(journal, plan.carried_keys)
      Store::LinksJournal.retain_runs!(journal, plan.carried_run_ids)
      expected
    end

    # The batch half: walk the plan's units in replay order, carrying the
    # carried and re-mining the rest through the caller's block (which
    # receives the recorded scope hash), stamping each successful mine with
    # the runs it minted. A Nabu::Error/ArgumentError from the block is
    # contained into +failures+ (that scope stays unstamped, so its
    # component re-mines next stage). Then the self-check comparison, the
    # stage log row, and the Outcome.
    def mine!(plan, scopes, journal:, expected:, failures:, progress: nil, &replay)
      mined = []
      carried = []
      fresh = {}
      plan.units.zip(scopes).each do |unit, scope|
        if plan.carried?(unit)
          carried << unit.label
          progress&.stage("links: #{unit.label} — carried (stamp #{unit.stamp[0, 12]})")
          next
        end
        progress&.stage("links: #{unit.label} — mining (#{plan.reasons[unit.key]})")
        ids = mine_unit(unit, scope, journal, failures, &replay)
        next if ids.nil?

        mined << unit.label
        fresh[unit.key] = ids
      end
      verified, drift = compare(plan, expected, fresh, journal)
      reproduced, changed = recheck(plan, expected, fresh, journal)
      Store::LinksJournal.record_stage_run!(journal, mode: plan.mode, mined: mined.size, carried: carried.size,
                                                     verified: verified.size, drift: drift)
      Outcome.new(mode: plan.mode, mined: mined, carried: carried, verified: verified, drift: drift,
                  reasons: plan.units.reject { |unit| plan.carried?(unit) }
                               .to_h { |unit| [unit.label, plan.reasons[unit.key]] },
                  failures: failures,
                  next_check_in: SELF_CHECK_EVERY - 1 - Store::LinksJournal.stamped_streak(journal),
                  reproduced: reproduced, changed: changed)
    end

    private

    # Re-mine one unit; returns the run ids it minted, or nil on a contained
    # failure (recorded in +failures+, the pre-stamps "producer scope: msg").
    def mine_unit(unit, scope, journal, failures)
      before = Store::LinksJournal.max_run_id(journal)
      yield scope
      ids = Store::LinksJournal.run_ids_for(journal, producers: [unit.producer]).select { |id| id > before }
      if unit.stamp
        Store::LinksJournal.write_scope_stamp!(journal, producer: unit.producer, scope: unit.scope,
                                                        stamp: unit.stamp, inputs: unit.inputs, run_ids: ids)
      end
      ids
    rescue Nabu::Error, ArgumentError => e
      failures << "#{unit.label}: #{e.message}"
      nil
    end

    # The self-check: each would-be-carried unit that re-mined cleanly is
    # VERIFIED when its fresh edges digest equal to the stamped ones;
    # otherwise it DRIFTED — announced at once, on stderr, beside the
    # summary line it also reaches.
    def compare(plan, expected, fresh, journal)
      verified = []
      drift = []
      plan.verify_runs.each_key do |key|
        next unless fresh.key?(key)

        unit = plan.units.find { |candidate| candidate.key == key }
        before = expected.fetch(key)
        after = Store::LinksJournal.edge_digests(journal, fresh.fetch(key))
        verified << unit.label
        next if before == after

        line = "#{unit.label}: #{edge_count(before)} edges stamped, #{edge_count(after)} freshly mined — " \
               "the stamp vouched for edges a fresh mine does not produce"
        warn "links SELF-CHECK DRIFT: #{line}"
        drift << line
      end
      [verified, drift]
    end

    # The code-change recheck's comparison: → [reproduced labels, changed
    # lines]. Informational — a changed scope is announced, never drift.
    def recheck(plan, expected, fresh, journal)
      reproduced = []
      changed = []
      plan.recheck_runs.each_key do |key|
        next unless fresh.key?(key)

        unit = plan.units.find { |candidate| candidate.key == key }
        before = expected.fetch(key)
        after = Store::LinksJournal.edge_digests(journal, fresh.fetch(key))
        if before == after
          reproduced << unit.label
        else
          changed << "#{unit.label}: #{edge_count(before)} edges before the code change, " \
                     "#{edge_count(after)} after — content differs"
        end
      end
      [reproduced, changed]
    end

    # The units re-mined for a code change alone: re-mined (a reason
    # recorded), stamped before, volatile-free, and blaming nothing but
    # producer_code — their own (a "dirty" reason) or a component-mate's
    # (a "component" reason, own stamp unchanged). → { key => run ids }.
    def recheck_runs(units, stored, reasons)
      units.each_with_object({}) do |unit, picked|
        row = stored[unit.key]
        reason = reasons[unit.key]
        next if row.nil? || unit.volatile || reason.nil?
        next unless reason.start_with?("dirty", "component")
        next unless (unit.blame(row[:inputs]) - ["producer_code"]).empty?

        picked[unit.key] = row[:run_ids]
      end
    end

    def edge_count(digests) = digests.values.sum { |slot| slot[:edges] }

    # Units grouped into kind-connected components (union over shared
    # kinds), each component's units in replay order.
    def components(units)
      groups = []
      units.each do |unit|
        touching = groups.select { |group| group.any? { |other| other.kinds.intersect?(unit.kinds) } }
        merged = touching.flatten + [unit]
        groups -= touching
        groups << merged
      end
      groups.map { |group| units.select { |unit| group.include?(unit) } }
    end

    # nil when the component may carry, else a lambda naming each unit's
    # re-mine reason.
    def component_verdict(members, stored, journal)
      if (volatile = members.find(&:volatile))
        return ->(unit) { unit.volatile ? "volatile: #{unit.volatile}" : "component (#{volatile.label})" }
      end

      drifted = members.reject { |unit| stored[unit.key]&.dig(:stamp) == unit.stamp }
      unless drifted.empty?
        return lambda do |unit|
          next "component (#{drifted.first.label})" unless drifted.include?(unit)

          row = stored[unit.key]
          row ? "dirty (#{unit.blame(row[:inputs]).join(', ')})" : "unstamped"
        end
      end

      producers = members.map(&:producer).uniq
      stamped_runs = members.flat_map { |unit| stored.fetch(unit.key)[:run_ids] }.sort
      stale_stamps = stored.keys.select { |key| producers.include?(key.first) } - members.map(&:key)
      actual_runs = Store::LinksJournal.run_ids_for(journal, producers: producers)
      return nil if actual_runs == stamped_runs && stale_stamps.empty? && finished?(journal, actual_runs)

      ->(_unit) { "journal runs differ from the stamped runs" }
    end

    # No carried run may be a half-finished chunked run.
    def finished?(journal, run_ids)
      journal[:link_runs].where(id: run_ids, status: "running").empty?
    end

    def inputs_for(producer, spec, scope, params)
      inputs = { "producer_code" => @code_digests.fetch(producer),
                 "params" => resolved_params(producer, params),
                 "members" => members(spec.membership == :global ? all_slugs : scope_slugs(scope)) }
      case producer
      when "parallels" then inputs["index"] = index_identity
      when "place-mine"
        inputs["gazetteer"] = gazetteer_identity(params["gazetteer"] || "chgis")
        inputs["stop_names"] = file_identity(PlaceMine::STOP_NAMES_PATH)
      when "place-link"
        tree = DerivationFingerprint.canonical_identity(File.join(@config.canonical_dir, Places::DIRNAME))
        inputs[:volatile] = "the nabu-places tree has no honest identity" if tree.nil?
        inputs["places_registry"] = tree
      end
      inputs
    end

    # The recorded params in canonical key order; parallels also folds in
    # the profile it re-resolves at replay (LinkScopeReplay).
    def resolved_params(producer, params)
      resolved = params.sort.to_h
      if producer == "parallels" && params["profile"]
        resolved["resolved_profile"] = ReuseProfiles.default.fetch(params["profile"]).to_h.transform_keys(&:to_s)
      end
      resolved
    end

    def members(slugs)
      missing = slugs - @members.keys
      @members.merge!(Store::SourceContentIdentity.for_slugs(@catalog, missing)) unless missing.empty?
      slugs.sort.to_h { |slug| [slug, @members.fetch(slug)] }
    end

    def all_slugs = @catalog[:sources].select_order_map(:slug)

    # The scope grammar of Query::Scope: an exact source slug, else the
    # sources owning live documents under the urn prefix.
    def scope_slugs(scope)
      return [scope] if @catalog[:sources].where(slug: scope).any?

      doc = Sequel[:documents][:urn]
      @catalog[:documents].join(:sources, id: Sequel[:documents][:source_id])
                          .where(doc >= scope).where(doc < "#{scope}\u{10FFFF}")
                          .distinct.select_order_map(Sequel[:sources][:slug])
    end

    # What the fulltext index is a function of beyond catalog content: the
    # index-core code, the per-stage derivation versions, and the
    # registry's index-shaping flags.
    def index_identity
      @index_identity ||= begin
        flags = if @registry
                  { "fuzzy" => @registry.fuzzy_slugs.sort, "cjk" => @registry.cjk_slugs.sort,
                    "lemma_tiers" => @registry.lemma_tiers.sort.to_h,
                    "lemma_filter" => @registry.lemma_filter_slugs.sort }
                else
                  {}
                end
        Digest::SHA256.hexdigest(JSON.generate([DerivationFingerprint.index_core_digest,
                                                Store::Indexer::STAGE_VERSIONS.sort, flags]))
      end
    end

    def gazetteer_identity(gazetteer)
      digest = Digest::SHA256.new
      @catalog[:place_index_names].where(gazetteer: gazetteer).order(:name_key, :place_id)
                                  .select(:name_key, :place_id).each do |row|
        digest << row[:name_key] << "\x1f" << row[:place_id] << "\n"
      end
      digest.hexdigest
    end

    def file_identity(path) = File.file?(path) ? Digest::SHA256.file(path).hexdigest : "absent"
  end
end
