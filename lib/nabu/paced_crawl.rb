# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

require_relative "errors"
require_relative "duration_format"

module Nabu
  # The paced-crawl rail (architecture §19): the engine a multi-segment
  # source CONFIGURES instead of hand-rolling — a census universe crawled a
  # slice per sync, politely paced, resumable at the id grain, with every
  # terminal refusal ledgered so it is never asked again.
  #
  # The adapter supplies a Spec (the lane's knobs and declared schedule) and
  # three lambdas:
  #
  #   universe  -> the ordered census ids (Strings; order IS crawl order)
  #   held      -> id => true when the id's payload is already on disk
  #   fetch_one -> id => an Outcome (:ok / :denied / :empty / :timeout) with
  #                its evidence ({http_status:, body_head:}); :ok means the
  #                lambda stored the payload (held? turns true). Anything
  #                that is not a terminal answer (5xx, network) RAISES — the
  #                crawl is resumable, the ledger already holds what the
  #                slice learned. Outcome.halt is the CLEAN STOP (a 429, a
  #                quota floor): the slice ends at once, the id stays
  #                selectable, the report classifies :clean_stop. A lane
  #                arming the outage breaker (Spec#outage_statuses) has
  #                those answers staged until upstream proves alive, and a
  #                run of outage_run of them classifies :outage_abort.
  #
  # The engine owns selection (universe − held − ledgered, order kept), the
  # slice loop under ONE budget (every id the slice asks for spends one unit,
  # whatever it answers — the budget bounds a slice's wall time, the
  # politeness unit; a refusal-burning slice is progress when the frontier
  # moves), pacing (delay between every two requests), the timeout policy
  # (attempts with doubling backoff, then the timeout class), the ledger
  # (atomic tmp+rename after every terminal answer, so a killed slice
  # resumes where it died; its on-disk shape is the Spec's codec, flat by
  # default) and the SLICE REPORT, printed on every path: the
  # reconciliation triple (census = held + ledgered + remaining, or a LOUD
  # mismatch), frontier position and movement, per-class deltas, refusal
  # evidence verbatim, requests/elapsed/pace, and on a zero-yield slice a
  # self-classification — all-refused (per-id refusals; the frontier moved
  # through a refusal stripe), upstream-refusing (the one held-id re-probe
  # was refused too — a wholesale block), cone-exhausted (an honest end) —
  # while selection-empty (nothing offered with ids remaining) and a frozen
  # frontier (an asked id still selectable afterwards) are bookkeeping bugs
  # and RAISE. A 100%-refused slice spends up to LOOKAHEAD_PROBES
  # exponentially spaced probes past the frontier to estimate the breakout.
  # Probes and the re-probe go through fetch_one and count in the request
  # tally, never against the slice budget; a probe's refusal is not ledgered
  # (the frontier reaches it in order).
  module PacedCrawl
    class Error < Nabu::Error; end
    # Selection offered nothing while the reconciliation says ids remain.
    class SelectionEmptyError < Error; end
    # An id the slice asked for is still selectable afterwards: the held?
    # oracle or the ledger is not recording outcomes (the frozen-frontier
    # signature — a slice that would re-offer the same ids forever).
    class FrozenFrontierError < Error; end

    STATUSES = %i[ok denied empty timeout halt].freeze
    TERMINAL = %i[denied empty timeout].freeze
    # The ledger section the engine persists its last report into, beside
    # the classes (each an array of ids).
    LAST_SLICE = "last_slice"
    REFUSAL_SAMPLES = 3
    LOOKAHEAD_PROBES = 6
    BODY_HEAD_BYTES = 80
    PROGRESS_EVERY = 50

    # The first bytes of an upstream answer, as quotable evidence: valid
    # UTF-8, whitespace collapsed, at most BODY_HEAD_BYTES bytes.
    def self.body_head(body)
      head = body.to_s.byteslice(0, BODY_HEAD_BYTES).to_s.dup.force_encoding(Encoding::UTF_8)
      head.scrub("").gsub(/\s+/, " ").strip
    end

    # The default ledger codec: the mold's flat shape — one sorted array of
    # ids per class at the top level. A codec maps the on-disk document to
    # {class name => Set of id Strings} (#load) and back (#dump), where +raw+
    # is the previous on-disk document ({} when absent or unreadable) minus
    # the engine-owned last_slice. Every section the codec does not own
    # passes through #dump. The flat codec owns the class keys it is handed;
    # a foreign top-level container (a "pages" map, an array from a class
    # the lane no longer declares) passes through verbatim, while a bare
    # top-level scalar is not a section and is dropped — the shape every
    # flat ledger has had since the rail began.
    module FlatCodec
      def self.load(raw)
        raw.reject { |_key, value| value.is_a?(Hash) }.transform_values { |ids| Array(ids).to_set(&:to_s) }
      end

      def self.dump(classes, raw)
        doc = classes.transform_values { |ids| ids.to_a.sort }
        raw.each do |key, value|
          doc[key] = value if !doc.key?(key) && (value.is_a?(Hash) || value.is_a?(Array))
        end
        doc
      end
    end
    FLAT_CODEC = FlatCodec

    # The declared cadence the phase slate reads off the adapter: how
    # often the lane runs, how many slices a phase spends, and how many
    # consecutive zero-yield slices stop a chained run.
    Schedule = Data.define(:cadence, :slices_per_phase, :stop_after_zero_slices)

    # One crawl lane's knobs. +classes+ maps each terminal Outcome status
    # (:denied / :empty / :timeout) to its ledger class name; +subclasses+
    # optionally names further classes per status (an upstream with two
    # kinds of refusal — a 404 "no text" beside a 403 — keeps them apart:
    # the Outcome names its ledger_class, the default is the status's own).
    # +codec+ is the ledger's on-disk shape (FLAT_CODEC unless the lane
    # keeps a nested one). +outage_statuses+ arms the OUTAGE BREAKER: an
    # answer of one of those statuses is staged, committed only when a later
    # id answers otherwise (upstream alive — the failures were real), and
    # +outage_run+ consecutive staged answers abort the slice with the run
    # dropped unledgered (upstream is down; the run is re-asked next slice).
    Spec = Data.define(:name, :ledger_file, :classes, :subclasses, :delay, :slice,
                       :timeout_attempts, :timeout_backoff, :schedule, :codec,
                       :outage_statuses, :outage_run) do
      def initialize(name:, ledger_file:, classes:, delay:, slice:, schedule:, subclasses: {},
                     timeout_attempts: 3, timeout_backoff: 5.0, codec: FLAT_CODEC,
                     outage_statuses: [], outage_run: nil)
        raise ArgumentError, "codec must answer #load and #dump" unless
          codec.respond_to?(:load) && codec.respond_to?(:dump)

        outage_statuses = Array(outage_statuses).uniq.freeze
        self.class.validate_outage!(outage_statuses, outage_run, classes)

        unknown = classes.keys - TERMINAL
        raise ArgumentError, "classes map only #{TERMINAL.inspect} (got #{unknown.inspect})" unless unknown.empty?
        raise ArgumentError, "classes must declare at least one ledger class" if classes.empty?

        orphans = subclasses.keys - classes.keys
        raise ArgumentError, "subclasses refine declared classes only (got #{orphans.inspect})" unless orphans.empty?
        raise ArgumentError, "slice must be a positive Integer" unless slice.is_a?(Integer) && slice.positive?
        unless timeout_attempts.is_a?(Integer) && timeout_attempts.positive?
          raise ArgumentError, "timeout_attempts must be a positive Integer"
        end

        super(name: name.to_s, ledger_file: ledger_file.to_s,
              classes: classes.transform_values(&:to_s).freeze,
              subclasses: subclasses.transform_values { |names| Array(names).map(&:to_s).freeze }.freeze,
              delay: Float(delay), slice: slice,
              timeout_attempts: timeout_attempts, timeout_backoff: Float(timeout_backoff), schedule: schedule,
              codec: codec, outage_statuses: outage_statuses, outage_run: outage_run)
      end

      def self.validate_outage!(statuses, run, classes)
        undeclared = statuses - classes.keys
        raise ArgumentError, "outage_statuses name declared classes only (got #{undeclared.inspect})" unless
          undeclared.empty?

        if statuses.empty?
          raise ArgumentError, "outage_run needs outage_statuses" unless run.nil?
        elsif !(run.is_a?(Integer) && run.positive?)
          raise ArgumentError, "outage_statuses need a positive Integer outage_run"
        end
      end

      def outage?(status) = outage_statuses.include?(status)

      # Every ledger class: each status's own, then its subclasses.
      def class_names = classes.flat_map { |status, klass| [klass, *subclasses.fetch(status, [])] }.uniq

      # The ledger classes an Outcome of +status+ may name.
      def classes_for(status) = [classes[status], *subclasses.fetch(status, [])].compact
    end

    # One answer from fetch_one. +ledger_class+ (terminal answers only)
    # names one of the Spec's subclasses for the status; nil ledgers the
    # status's own class.
    #
    # A :halt (Outcome.halt) is the CLEAN STOP: upstream said "no more for
    # now" (a 429, a quota floor read off a good answer's header). It is no
    # answer about the id — never ledgered, never refused, the id stays
    # selectable — and it ends the slice at once (no further id, no
    # re-probe, no look-ahead). Its +reason+ is required; its evidence is
    # kept verbatim (a quota header is not an HTTP status + body head).
    Outcome = Data.define(:status, :evidence, :ledger_class, :reason) do
      def self.from_body(status, http_status:, body:, ledger_class: nil)
        new(status: status, evidence: { http_status: http_status, body_head: PacedCrawl.body_head(body) },
            ledger_class: ledger_class)
      end

      def self.halt(reason:, evidence: {}) = new(status: :halt, evidence: evidence, reason: reason)

      def initialize(status:, evidence: {}, ledger_class: nil, reason: nil)
        raise ArgumentError, "Outcome status must be one of #{STATUSES.inspect} (got #{status.inspect})" unless
          STATUSES.include?(status)
        raise ArgumentError, "only a terminal Outcome names a ledger class" if
          ledger_class && !TERMINAL.include?(status)
        raise ArgumentError, "a halt Outcome needs a reason" if status == :halt && reason.to_s.strip.empty?
        raise ArgumentError, "only a halt Outcome carries a reason" if reason && status != :halt

        evidence = evidence.to_h
        evidence = if status == :halt
                     evidence.dup
                   else
                     { http_status: evidence[:http_status], body_head: evidence[:body_head] }
                   end
        super(status: status, evidence: evidence.freeze, ledger_class: ledger_class&.to_s, reason: reason&.to_s)
      end

      def ok? = status == :ok
      def halt? = status == :halt
      def http_status = evidence[:http_status]
      def body_head = evidence[:body_head]
    end

    # Shared text rendering for Report and Diagnosis.
    module Render
      include Nabu::DurationFormat

      def census_text(held_delta: nil, ledgered_delta: nil)
        held_now = held_count
        ledgered_now = ledgered_counts.values.sum
        sum = held_now + ledgered_now + remaining_count
        breakdown = ledgered_counts.map { |klass, count| "#{klass} #{count}" }.join(", ")
        strays_note = strays.positive? ? "; #{strays} ledgered id(s) outside the census" : ""
        unless sum == census
          return "RECONCILIATION MISMATCH: census #{census} ≠ held #{held_now} + ledgered #{ledgered_now} " \
                 "[#{breakdown}] + remaining #{remaining_count} = #{sum} " \
                 "(an id is held AND ledgered, or ledgered twice)#{strays_note}"
        end

        "census #{census} = held #{held_now}#{delta(held_delta)} + ledgered #{ledgered_now}" \
          "#{delta(ledgered_delta)} [#{breakdown}] + remaining #{remaining_count} — reconciles#{strays_note}"
      end

      def slices_to_end = (remaining_count / slice.to_f).ceil

      private

      def delta(value) = value.nil? ? "" : format(" (%+d)", value)
    end

    # The slice report: returned structured, rendered by #lines, persisted
    # (#to_json_h) into the ledger's last_slice section.
    Report = Data.define(:name, :at, :classification, :slice, :census, :held, :ledgered, :remaining,
                         :strays, :attempted, :ok, :refused, :stuck, :frontier, :statuses, :samples,
                         :reprobe, :lookahead, :requests, :elapsed, :halt, :outage) do
      include Render

      def zero_yield? = ok.zero?
      # The slice ended on a clean stop (Outcome.halt): halt is {id:,
      # reason:, evidence:}.
      def halted? = !halt.nil?
      # The outage breaker tripped (outage is {aborted:, count:, ids:,
      # statuses:, last:}; aborted false = a staged run the slice's end left
      # uncommitted).
      def outage_aborted? = outage&.fetch(:aborted) == true
      # Yield OR frontier movement — what a chained run asserts per slice.
      def progressed? = ok.positive? || frontier[:moved].positive?
      def reconciles? = held[:after] + ledgered.values.sum { |pair| pair[:after] } + remaining[:after] == census
      def held_count = held[:after]
      def remaining_count = remaining[:after]
      def ledgered_counts = ledgered.transform_values { |pair| pair[:after] }
      def pace = requests.zero? ? nil : elapsed / requests
      def breakout = lookahead.find { |probe| probe[:status] == :ok }

      def lines
        out = []
        out << halt_text if halted?
        out << outage_text if outage
        out << verdict_text if zero_yield? && !halted? && !outage_aborted?
        out << tally_text
        out << census_text(held_delta: held[:after] - held[:before],
                           ledgered_delta: ledgered.values.sum { |pair| pair[:after] - pair[:before] })
        out << frontier_text
        out << samples_text unless samples.empty?
        out << reprobe_text if reprobe
        out << lookahead_text unless lookahead.empty?
        out << pace_text
        out.map { |line| "#{name}: #{line}" }
      end

      def to_json_h = JSON.parse(JSON.generate(to_h))

      private

      def label = classification.to_s.tr("_", "-")

      def verdict_text
        case classification
        when :cone_exhausted
          "ZERO-YIELD SLICE [cone-exhausted]: nothing left to select — the crawl reached the end of its cone"
        when :upstream_refusing
          "ZERO-YIELD SLICE [upstream-refusing]: #{attempted}/#{attempted} asked refused (#{statuses_text}) " \
          "AND the held-id re-probe was refused — upstream is refusing wholesale, not per id; stop the chain"
        else
          "ZERO-YIELD SLICE [#{label}]: #{attempted}/#{attempted} asked refused (#{statuses_text}) — the " \
          "frontier advanced #{frontier[:moved]} position(s) through a refusal stripe; the ledger is this " \
          "slice's yield"
        end
      end

      def halt_text
        detail = halt[:evidence].to_h.map { |key, value| "#{key} #{value}" }.join(", ")
        detail = " (#{detail})" unless detail.empty?
        "CLEAN STOP at #{halt[:id]}: #{halt[:reason]}#{detail} — upstream asked the crawl to stop; the id " \
          "stays selectable (never ledgered) and the next slice starts there"
      end

      def outage_text
        ids = outage[:ids]
        span = ids.size == 1 ? ids.first : "#{ids.first}…#{ids.last}"
        what = "#{outage[:count]}#{' consecutive' if outage[:aborted]} outage answer(s) " \
               "(#{outage[:statuses].join(', ')}) at #{span}"
        last = "last: #{outage[:last][:id]} #{evidence_text(outage[:last])}"
        if outage[:aborted]
          "OUTAGE ABORT: #{what} — upstream looks down; the run was dropped unledgered and stays selectable " \
            "(the next slice re-asks it), everything ledgered before it stands; #{last}"
        else
          "OUTAGE STAGE: #{what} uncommitted when the slice ended — no later id confirmed upstream alive; " \
            "left unledgered, re-asked next slice; #{last}"
        end
      end

      def tally_text
        classes = refused.map { |klass, count| "#{klass} +#{count}" }.join(", ")
        stuck_list = stuck.empty? ? "" : " (#{stuck.join(', ')})"
        "slice +#{ok} ok of #{attempted}/#{slice} asked (#{classes}); #{stuck.size} stuck on timeout#{stuck_list}"
      end

      def frontier_text
        return "frontier: end of cone (nothing was selectable)" if frontier[:before].nil?

        after = frontier[:after] || "end of cone"
        "frontier #{frontier[:before]} → #{after} (advanced #{frontier[:moved]} of #{census} position(s))"
      end

      def statuses_text
        return "no answers" if statuses.empty?

        text = statuses.map { |status, count| "#{status.nil? ? 'no HTTP status' : "HTTP #{status}"} ×#{count}" }
        text << "uniform" if statuses.size == 1
        text.join(", ")
      end

      def evidence_text(entry)
        status = entry[:http_status] ? " HTTP #{entry[:http_status]}" : ""
        body = entry[:body_head].to_s.empty? ? "" : " \"#{entry[:body_head]}\""
        "#{entry[:status]}#{status}#{body}"
      end

      def samples_text
        "refusal samples: #{samples.map { |entry| "#{entry[:id]} #{evidence_text(entry)}" }.join('; ')}"
      end

      def reprobe_text
        verdict = if reprobe[:status] == :ok
                    "upstream alive (the refusals are per id, not a block)"
                  else
                    "upstream refuses a known-good id (a wholesale block)"
                  end
        "re-probe of held #{reprobe[:id]}: #{evidence_text(reprobe.merge(body_head: nil))} — #{verdict}"
      end

      def lookahead_text
        probes = lookahead.map do |probe|
          "+#{probe[:ahead]} #{probe[:id]} #{evidence_text(probe.merge(body_head: nil))}"
        end
        found = breakout
        tail = if found
                 cost = pace ? ", ~#{format_duration(found[:ahead] * pace)} at the current pace" : ""
                 "servable text answers #{found[:ahead]} id(s) past the frontier " \
                   "(~#{(found[:ahead] / slice.to_f).ceil} slice(s)#{cost})"
               else
                 "no servable text within #{lookahead.map { |probe| probe[:ahead] }.max} id(s) probed"
               end
        "look-ahead: #{probes.join('; ')} — #{tail}"
      end

      def pace_text
        rate = pace ? " (#{format('%.2f', pace)} s/request)" : ""
        "#{requests} request(s) in #{format_duration(elapsed)}#{rate}; ~#{slices_to_end} slice(s) of #{slice} " \
          "to the end of the cone"
      end
    end

    # The offline view (Engine#diagnose): on-disk set arithmetic only —
    # no request is made.
    Diagnosis = Data.define(:name, :slice, :census, :held_count, :ledgered_counts, :remaining_count,
                            :strays, :frontier, :frontier_position, :last_slice) do
      include Render

      def reconciles? = held_count + ledgered_counts.values.sum + remaining_count == census

      def lines
        out = [census_text]
        out << if frontier
                 "frontier #{frontier} (position #{frontier_position} of #{census})"
               else
                 "frontier: end of cone (nothing selectable)"
               end
        out << last_slice_text
        out << "~#{slices_to_end} slice(s) of #{slice} to the end of the cone"
        out.map { |line| "#{name}: #{line}" }
      end

      private

      def last_slice_text
        return "last slice: none recorded" unless last_slice

        "last slice #{last_slice['at']}: #{last_slice['classification'].to_s.tr('_', '-')}, " \
          "+#{last_slice['ok']} ok of #{last_slice['attempted']} asked, #{last_slice['requests']} request(s)"
      end
    end

    # One pass over the universe: who is held, ledgered, selectable.
    Census = Data.define(:universe, :positions, :held, :ledgered, :selectable, :strays) do
      def total = universe.size
      def frontier = selectable.first
      def position(id) = id.nil? ? total : positions.fetch(id)
    end

    # The crawl engine for one lane over one working directory.
    class Engine
      attr_reader :spec, :dir

      MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      SLEEP = ->(seconds) { sleep(seconds) }
      NOW = -> { Time.now.utc }

      def initialize(spec:, dir:, universe:, held:, fetch_one:, progress: nil,
                     clock: MONOTONIC, sleeper: SLEEP, now: NOW)
        @spec = spec
        @dir = dir
        @universe = universe
        @held = held
        @fetch_one = fetch_one
        @progress = progress
        @clock = clock
        @sleeper = sleeper
        @now = now
        @requests = 0
        @ledger = nil
      end

      # Every request this engine has made (slices and probes alike).
      attr_reader :requests

      # A copy of this engine with +held+ and/or +fetch_one+ wrapped: each
      # override is called as (id, original) — the conformance suite's
      # bookkeeping-bug injection (a lying held? oracle, an :ok that stores
      # nothing) against a lane's real wiring.
      def rewire(held: nil, fetch_one: nil)
        original_held = @held
        original_fetch = @fetch_one
        self.class.new(
          spec: spec, dir: dir, universe: @universe, progress: @progress,
          clock: @clock, sleeper: @sleeper, now: @now,
          held: held ? ->(id) { held.call(id, original_held) } : original_held,
          fetch_one: fetch_one ? ->(id) { fetch_one.call(id, original_fetch) } : original_fetch
        )
      end

      def ledger_path = File.join(dir, spec.ledger_file)

      # {class name => sorted ids}, as on disk.
      def ledger
        load_ledger! if @ledger.nil?
        spec.class_names.to_h { |klass| [klass, @ledger[klass].to_a.sort] }
      end

      # The last persisted report (JSON shape), or nil.
      def last_slice
        load_ledger! if @ledger.nil?
        @last_slice
      end

      # Run one slice; returns its Report (also persisted into the ledger).
      def slice!
        load_ledger!
        started = @clock.call
        requests_before = @requests
        before = scan
        tally = run_slice(before)
        after = scan
        guard_frontier!(tally[:asked] - tally.dig(:outage, :ids).to_a, after)
        stopped = tally[:halt] || tally.dig(:outage, :aborted)
        reprobe = tally[:ok].zero? && !tally[:asked].empty? && !stopped ? reprobe!(before, tally) : nil
        classification = classify(tally, reprobe)
        lookahead = classification == :all_refused ? lookahead!(after, tally) : []
        classification = :clean_stop if tally[:halt]
        after = scan if lookahead.any? { |probe| probe[:status] == :ok }
        report = build_report(before: before, after: after, tally: tally, reprobe: reprobe,
                              lookahead: lookahead, classification: classification,
                              requests: @requests - requests_before, elapsed: @clock.call - started)
        @last_slice = report.to_json_h
        write_ledger!
        report
      end

      # The offline diagnosis: universe + held? + the on-disk ledger, no
      # fetch_one call.
      def diagnose
        load_ledger!
        census = scan
        Diagnosis.new(
          name: spec.name, slice: spec.slice, census: census.total, held_count: census.held.size,
          ledgered_counts: census.ledgered, remaining_count: census.selectable.size, strays: census.strays,
          frontier: census.frontier, frontier_position: census.frontier && census.position(census.frontier),
          last_slice: @last_slice
        )
      end

      private

      def run_slice(census)
        tally = { asked: [], ok: 0, refused: spec.class_names.to_h { |klass| [klass, 0] },
                  stuck: [], refusals: [], halt: nil, staged: [], outage: nil }
        census.selectable.each do |id|
          break if tally[:asked].size >= spec.slice
          next if @held.call(id) # held since the scan: never re-fetched

          outcome = fetch_with_retries(id)
          break note_halt!(tally, id, outcome) if outcome.halt?

          if spec.outage?(outcome.status)
            stage!(tally, id, outcome)
            break if tally[:outage]
          else
            commit_staged!(tally)
            record!(tally, id, outcome)
          end
          report_progress(tally)
        end
        note_uncommitted!(tally)
        if tally[:asked].empty? && !tally[:halt] && !census.selectable.empty?
          raise SelectionEmptyError,
                "#{spec.name}: selection offered nothing while #{census.selectable.size} id(s) remain " \
                "(first: #{census.frontier}) — the held? oracle disagrees with itself"
        end
        tally
      end

      # A clean stop: noted on the tally (the id is NOT asked — it got no
      # answer about itself), never ledgered.
      def note_halt!(tally, id, outcome)
        tally[:halt] = { id: id, reason: outcome.reason, evidence: outcome.evidence }
        say("#{spec.name}: clean stop at #{id} — #{outcome.reason}")
      end

      def record!(tally, id, outcome)
        tally[:asked] << id
        if outcome.ok?
          tally[:ok] += 1
          return
        end

        ledger!(tally, id, outcome)
        write_ledger! # a killed slice resumes with what it learned
      end

      # The ledger class +outcome+ lands in, or a raise when the lane
      # declares none for it.
      def ledger_class!(id, outcome)
        klass = outcome.ledger_class || spec.classes[outcome.status]
        return klass if klass && spec.classes_for(outcome.status).include?(klass)

        raise Error, "#{spec.name}: fetch_one answered #{outcome.status}#{" (#{klass})" if klass} for #{id}, " \
                     "which this lane declares no such ledger class for"
      end

      # In memory only — the caller writes.
      def ledger!(tally, id, outcome)
        klass = ledger_class!(id, outcome)
        @ledger[klass] << id
        tally[:refused][klass] += 1
        tally[:stuck] << id if outcome.status == :timeout
        tally[:refusals] << [id, outcome]
      end

      # The outage breaker: an outage-status answer waits off the ledger
      # (it spent its budget unit); outage_run of them in a row abort.
      def stage!(tally, id, outcome)
        ledger_class!(id, outcome)
        tally[:asked] << id
        tally[:staged] << [id, outcome]
        return if tally[:staged].size < spec.outage_run

        tally[:outage] = outage_entry(tally[:staged], aborted: true)
        say("#{spec.name}: #{tally[:staged].size} consecutive outage answer(s) — upstream looks down; " \
            "slice aborted, the run left unledgered")
      end

      # A later id answered: upstream is alive, the staged failures were
      # real — they commit, in one write.
      def commit_staged!(tally)
        return if tally[:staged].empty?

        tally[:staged].each { |id, outcome| ledger!(tally, id, outcome) }
        tally[:staged].clear
        write_ledger!
      end

      # Staged answers no later id confirmed when the slice ended stay
      # unledgered (re-asked next slice); the report names them.
      def note_uncommitted!(tally)
        return if tally[:outage] || tally[:staged].empty?

        tally[:outage] = outage_entry(tally[:staged], aborted: false)
      end

      def outage_entry(staged, aborted:)
        id, outcome = staged.last
        { aborted: aborted, count: staged.size, ids: staged.map(&:first),
          statuses: staged.map { |_id, staged_outcome| staged_outcome.status }.uniq,
          last: evidence(id, outcome) }
      end

      def report_progress(tally)
        return unless (tally[:asked].size % PROGRESS_EVERY).zero?

        refused = tally[:refused].values.sum
        say("#{spec.name}: +#{tally[:ok]} ok, #{refused} refused (#{tally[:asked].size}/#{spec.slice})…")
      end

      def say(line) = @progress&.call("#{line}\n")

      def request(id)
        @sleeper.call(spec.delay) if spec.delay.positive? && @requests.positive?
        @requests += 1
        outcome = @fetch_one.call(id)
        raise Error, "#{spec.name}: fetch_one must answer a PacedCrawl::Outcome (got #{outcome.class})" unless
          outcome.is_a?(Outcome)

        outcome
      end

      # A timeout is retried with doubling backoff; only timeout_attempts
      # consecutive timeouts give up (the caller ledgers the timeout class).
      def fetch_with_retries(id)
        attempts = spec.timeout_attempts
        outcome = nil
        attempts.times do |attempt|
          outcome = request(id)
          return outcome unless outcome.status == :timeout
          break if attempt == attempts - 1

          say("#{spec.name}: #{id} timed out (attempt #{attempt + 1}/#{attempts}), retrying…")
          backoff = spec.timeout_backoff * (2**attempt)
          @sleeper.call(backoff) if backoff.positive?
        end
        say("#{spec.name}: #{id} timed out #{attempts}× — ledgered #{spec.classes[:timeout]}, moving on")
        outcome
      end

      def guard_frontier!(asked, after)
        selectable = after.selectable.to_set
        frozen = asked.select { |id| selectable.include?(id) }
        return if frozen.empty?

        raise FrozenFrontierError,
              "#{spec.name}: frontier frozen — #{frozen.size} asked id(s) still selectable after the slice " \
              "(first: #{frozen.first}); held?/the ledger are not recording outcomes"
      end

      def classify(tally, reprobe)
        return :clean_stop if tally[:halt]
        return :outage_abort if tally.dig(:outage, :aborted)
        return :yield if tally[:ok].positive?
        return :cone_exhausted if tally[:asked].empty?
        return :upstream_refusing if reprobe && reprobe[:status] != :ok

        :all_refused
      end

      # ONE request on a held id — the nearest before the slice's frontier —
      # answers upstream-alive vs wholesale-block. nil when nothing is held.
      # A halt answered to the re-probe is the clean stop, not a block.
      def reprobe!(census, tally)
        limit = census.position(census.frontier)
        target = census.held.reverse_each.find { |id| census.positions[id] < limit } || census.held.first
        return nil unless target

        outcome = request(target)
        return evidence(target, outcome) unless outcome.halt?

        note_halt!(tally, target, outcome)
        nil
      end

      # Up to LOOKAHEAD_PROBES probes at slice × 2^k ids past the new
      # frontier (clamped to the remaining cone): where does servable text
      # resume?
      # (A halted probe ends the probing: the clean stop.)
      def lookahead!(census, tally)
        pool = census.selectable
        return [] if pool.empty?

        aheads = (0...LOOKAHEAD_PROBES).map { |k| [spec.slice * (2**k), pool.size].min }.uniq
        probes = []
        aheads.each do |ahead|
          id = pool[ahead - 1]
          outcome = request(id)
          break note_halt!(tally, id, outcome) if outcome.halt?

          probes << evidence(id, outcome).merge(ahead: ahead)
        end
        probes
      end

      def evidence(id, outcome)
        { id: id, status: outcome.status, http_status: outcome.http_status, body_head: outcome.body_head }
      end

      def build_report(before:, after:, tally:, reprobe:, lookahead:, classification:, requests:, elapsed:)
        refusals = tally[:refusals]
        statuses = refusals.map { |_id, outcome| outcome.http_status }.tally
        ledgered = spec.class_names.to_h do |klass|
          [klass, { before: before.ledgered[klass], after: after.ledgered[klass] }]
        end
        Report.new(
          name: spec.name, at: @now.call.iso8601, classification: classification, slice: spec.slice,
          census: after.total,
          held: { before: before.held.size, after: after.held.size },
          ledgered: ledgered,
          remaining: { before: before.selectable.size, after: after.selectable.size },
          strays: after.strays, attempted: tally[:asked].size, ok: tally[:ok], refused: tally[:refused],
          stuck: tally[:stuck], frontier: frontier(before, after), statuses: statuses,
          samples: refusals.first(REFUSAL_SAMPLES).map { |id, outcome| evidence(id, outcome) },
          reprobe: reprobe, lookahead: lookahead, requests: requests, elapsed: elapsed.to_f, halt: tally[:halt],
          outage: tally[:outage]
        )
      end

      def frontier(before, after)
        from = before.frontier
        to = after.frontier
        moved = from.nil? ? 0 : [after.position(to) - before.position(from), 0].max
        { before: from, before_position: from && before.position(from), after: to,
          after_position: to && after.position(to), moved: moved }
      end

      def scan
        universe = Array(@universe.call).map(&:to_s).uniq
        positions = universe.each_with_index.to_h
        names = spec.class_names
        ledgered = names.to_h { |klass| [klass, 0] }
        held = []
        selectable = []
        universe.each do |id|
          classes = names.select { |klass| @ledger[klass].include?(id) }
          classes.each { |klass| ledgered[klass] += 1 }
          if @held.call(id)
            held << id
          elsif classes.empty?
            selectable << id
          end
        end
        strays = names.reduce(Set.new) { |all, klass| all | @ledger[klass] }.count { |id| !positions.key?(id) }
        Census.new(universe: universe, positions: positions, held: held, ledgered: ledgered,
                   selectable: selectable, strays: strays)
      end

      # Every read and write goes through spec.codec; the engine owns the
      # top-level last_slice beside whatever the codec writes. A ledger from
      # before a class existed reads that class empty; an unreadable ledger
      # reads blank (the mold's posture — it is rebuilt by re-asking, never
      # by guessing).
      def load_ledger!
        data = begin
          File.file?(ledger_path) ? JSON.parse(File.read(ledger_path)) : {}
        rescue JSON::ParserError
          {}
        end
        data = {} unless data.is_a?(Hash)
        @last_slice = data[LAST_SLICE]
        @raw = data.except(LAST_SLICE)
        loaded = spec.codec.load(@raw)
        @ledger = spec.class_names.to_h { |klass| [klass, loaded.fetch(klass, Set.new).to_set] }
      end

      def write_ledger!
        FileUtils.mkdir_p(dir)
        doc = spec.codec.dump(spec.class_names.to_h { |klass| [klass, @ledger[klass].dup] }, @raw)
        @raw = doc.except(LAST_SLICE)
        doc = @raw.merge(LAST_SLICE => @last_slice) if @last_slice
        File.write("#{ledger_path}.tmp", JSON.pretty_generate(doc))
        File.rename("#{ledger_path}.tmp", ledger_path)
      end
    end
  end
end
