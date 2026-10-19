# frozen_string_literal: true

require "etc"

module Nabu
  # A bounded pool of FORKED parse workers feeding one writer, in input
  # order (the parallel replay lever: parse is pure — adapters never touch
  # SQL, architecture §3 — while the single writer stays single).
  #
  #   pool = ParsePool.new(adapter: adapter, workers: 7)
  #   pool.each(refs) { |result| document = result.value! ... }
  #
  # - Workers are forked once per #each call, from the caller's process, so
  #   they inherit the adapter exactly as discovery left it (catalog
  #   indexes built during discover are shared copy-on-write, never
  #   rebuilt per worker).
  # - Workers never open SQLite. Writable handles the parent already holds
  #   are DISCARDED in the child by the sqlite3 gem's fork hook (the file is
  #   never closed or checkpointed from the child); the gem's warning about
  #   them is silenced for exactly the duration of the pool's own forks.
  # - Dispatch is dynamic (an idle worker takes the next ref), so one slow
  #   mega-document does not stall the others; delivery is strictly in
  #   input order through a reorder buffer. In-flight work is bounded by a
  #   document window (IN_FLIGHT_PER_WORKER per worker) and a byte cap on
  #   undelivered results, so memory stays bounded whatever the writer's
  #   pace.
  # - Documents cross the fork as Marshal-ed house value objects. A pump
  #   thread drains the result pipes (raw bytes only — it releases the GVL
  #   while blocked) so workers keep parsing while the writer writes; the
  #   Marshal.load happens on the consuming thread and is measured
  #   (#decode_seconds) — the IPC cost the writer actually pays.
  #
  # Failure semantics mirror the serial path slot for slot: a parse
  # exception travels back as itself and Result#value! re-raises it at its
  # own position (ParseError/DocumentSkipped stay rescuable by the
  # caller; anything else aborts exactly where the serial parse would
  # have). A worker that DIES mid-document surfaces as ParseWorkerError at
  # the first slot it held — every earlier result is delivered first,
  # nothing after it. Every child is reaped on every exit path.
  class ParsePool
    # The default worker count's ceiling: cores − 1 (the writer keeps one),
    # capped where the curve flattens. Measured on a synthetic four-source
    # replay (dta/eebo-tcp/okhc/kanripo fixtures replicated, 24.7k docs,
    # 193k passages; 10-core Apple Silicon, 4P+6E): serial 42.4 s,
    # N=2 28.7, N=4 22.0, N=6 20.4, N=8 19.2, N=9 18.9 — past ~8 the
    # parse-bound sources are near their floor and the writer-bound ones
    # never moved.
    DEFAULT_CAP = 8

    # Documents dispatched-but-undelivered per worker (the reorder window).
    IN_FLIGHT_PER_WORKER = 16

    # Requests queued on one worker's pipe at a time. Deep enough that a
    # worker never idles waiting on the pump thread (which shares the GVL
    # with the writer): measured on a 23k-record JSONL source of tiny
    # documents, depth 2 left the pool at 1.7x serial, depth 8 reached
    # 3.6x; deeper bought nothing.
    PIPELINE_DEPTH = 8

    # Undelivered result bytes (plus in-flight refs priced at the mean
    # result size) past which no new ref is dispatched.
    BUFFER_BYTES = 256 * 1024 * 1024

    HEADER = "Q>"
    HEADER_BYTES = 8

    # One ref's parse outcome. +document+ is the parsed Nabu::Document (nil
    # when +error+ is set); +value!+ returns it or re-raises the error.
    Result = Data.define(:ref, :document, :error) do
      def value!
        raise error if error

        document
      end
    end

    # One worker's parent-side state.
    Worker = Struct.new(:pid, :requests, :results, :outstanding, :alive)

    def self.default_workers(nprocessors: Etc.nprocessors)
      (nprocessors - 1).clamp(1, DEFAULT_CAP)
    end

    # The pids forked by the last #each (empty before, or for an empty
    # ref list). Seconds the consumer spent blocked waiting for results
    # (+wait_seconds+) and un-Marshal-ing them (+decode_seconds+); the
    # summed in-worker parse time (+worker_parse_seconds+); result bytes
    # that crossed the pipes (+ipc_bytes+).
    attr_reader :pids, :wait_seconds, :decode_seconds, :worker_parse_seconds, :ipc_bytes

    def initialize(adapter:, workers:, buffer_bytes: BUFFER_BYTES)
      raise ArgumentError, "a parse pool needs at least one worker (got #{workers})" if workers < 1

      @adapter = adapter
      @size = workers
      @buffer_bytes = buffer_bytes
      @pids = []
      @wait_seconds = 0.0
      @decode_seconds = 0.0
      @worker_parse_seconds = 0.0
      @ipc_bytes = 0
    end

    # Parse every ref in +refs+ (an Array) across the workers and yield a
    # Result per ref, in input order. Returns nil.
    def each(refs)
      return if refs.empty?

      start(refs)
      clean = false
      refs.each_index { |seq| yield take(seq) }
      clean = true
      nil
    ensure
      shutdown(clean: clean) if @workers
    end

    private

    def start(refs)
      @refs = refs
      @mutex = Mutex.new
      @arrived = ConditionVariable.new
      @frames = {}
      @buffered = 0
      @received = 0
      @received_bytes = 0
      @next_take = 0
      @fatal = nil
      @stopping = false
      @workers = Array.new([@size, refs.size].min) { fork_worker }
      @pids = @workers.map(&:pid)
      @wake_r, @wake_w = IO.pipe
      @pump = Thread.new do
        Thread.current.report_on_exception = false
        pump
      end
    end

    # -- the consumer side ---------------------------------------------------

    def take(seq)
      frame = await(seq)
      @mutex.synchronize do
        @frames.delete(seq)
        @buffered -= frame.is_a?(String) ? frame.bytesize : 0
        @next_take = seq + 1
      end
      wake
      decode(@refs[seq], frame)
    end

    def await(seq)
      started = clock
      @mutex.synchronize do
        until @frames.key?(seq)
          raise @fatal if @fatal

          @arrived.wait(@mutex)
        end
        @frames[seq]
      end
    ensure
      @wait_seconds += clock - started
    end

    def decode(ref, frame)
      return Result.new(ref: ref, document: nil, error: frame) if frame.is_a?(Exception)

      started = clock
      status, payload, seconds = Marshal.load(frame) # rubocop:disable Security/MarshalLoad -- our own child's bytes
      @decode_seconds += clock - started
      @worker_parse_seconds += seconds
      @ipc_bytes += frame.bytesize
      return Result.new(ref: ref, document: payload, error: nil) if status == :ok

      Result.new(ref: ref, document: nil, error: payload)
    end

    # -- the pump thread -----------------------------------------------------

    # Dispatch refs to idle workers (within the window) and drain finished
    # results into the reorder buffer, until every ref has a result or the
    # consumer stops. A dead worker fails every slot it still held.
    def pump
      next_seq = 0
      loop do
        next_seq = dispatch(next_seq)
        live = @workers.select(&:alive)
        break if @stopping || (next_seq == @refs.size && live.all? { |worker| worker.outstanding.empty? })
        raise ParseWorkerError, "every parse worker died before #{@refs[next_seq].id}" if live.empty?

        ready, = IO.select([@wake_r] + live.map(&:results))
        ready.each do |io|
          if io == @wake_r
            drain_wake
          else
            receive(@workers.find { |worker| worker.results == io })
          end
        end
      end
    rescue StandardError => e
      # Transported, never swallowed: the consumer re-raises it at once.
      @mutex.synchronize do
        @fatal = e
        @arrived.broadcast
      end
    end

    # Hand refs to workers with room in their pipeline, within the reorder
    # window and the byte budget: undelivered bytes plus the in-flight
    # refs priced at the mean result size seen so far (a mega-document
    # source thereby narrows its own window). Something is always allowed
    # in flight, so a single huge document still makes progress.
    def dispatch(next_seq)
      limit, buffered = @mutex.synchronize { [@next_take + (@workers.size * IN_FLIGHT_PER_WORKER), @buffered] }
      in_flight = @workers.sum { |worker| worker.outstanding.size }
      @workers.each do |worker|
        while worker.alive && worker.outstanding.size < PIPELINE_DEPTH && next_seq < @refs.size && next_seq < limit
          break unless (in_flight.zero? && buffered.zero?) || buffered + ((in_flight + 1) * mean_frame) < @buffer_bytes

          begin
            write_frame(worker.requests, Marshal.dump(@refs[next_seq]))
          rescue Errno::EPIPE
            worker_died(worker)
            break
          end
          worker.outstanding << next_seq
          in_flight += 1
          next_seq += 1
        end
      end
      next_seq
    end

    def mean_frame = @received.zero? ? 0 : @received_bytes / @received

    def receive(worker)
      frame = read_frame(worker.results)
      return worker_died(worker) if frame.nil?

      @received += 1
      @received_bytes += frame.bytesize
      seq = worker.outstanding.shift
      @mutex.synchronize do
        @frames[seq] = frame
        @buffered += frame.bytesize
        @arrived.broadcast
      end
    end

    # EOF before a result: the child is gone. Reap it now for an honest
    # status and fail every slot it still held (the first of them is where
    # the consumer will raise).
    def worker_died(worker)
      worker.alive = false
      status = reap(worker.pid)
      @mutex.synchronize do
        worker.outstanding.each do |seq|
          @frames[seq] = ParseWorkerError.new(
            "parse worker #{worker.pid} died (#{status_text(status)}) while parsing #{@refs[seq].id}"
          )
        end
        @arrived.broadcast
      end
      worker.outstanding.clear
    end

    def status_text(status)
      return "status unknown" if status.nil?

      status.signaled? ? "signal #{status.termsig}" : "exit #{status.exitstatus}"
    end

    def wake
      @wake_w.write_nonblock(".", exception: false)
    end

    def drain_wake
      @wake_r.read_nonblock(4096, exception: false)
    end

    # -- the workers ---------------------------------------------------------

    def fork_worker
      requests_r, requests_w = IO.pipe
      results_r, results_w = IO.pipe
      inherited = (@workers_forked ||= []).flat_map { |worker| [worker.requests, worker.results] }
      $stdout.flush
      $stderr.flush
      pid = quiet_sqlite_fork_warning do
        fork do
          inherited.each(&:close)
          requests_w.close
          results_r.close
          work(requests_r, results_w)
        end
      end
      requests_r.close
      results_w.close
      Worker.new(pid, requests_w, results_r, [], true).tap { |worker| @workers_forked << worker }
    end

    # The child's whole life: parse each ref it is handed, ship the outcome
    # back, exit on EOF. exit! — never the parent's at_exit handlers (a
    # test runner, an open progress line) in a child.
    def work(requests, results)
      while (frame = read_frame(requests))
        ref = Marshal.load(frame) # rubocop:disable Security/MarshalLoad -- our own parent's bytes
        write_frame(results, outcome(ref))
      end
      exit!(0)
    ensure
      exit!(1)
    end

    # The fork boundary must carry EVERY parse failure back to the writer,
    # which re-raises it at the ref's slot (so the serial path's rescue
    # discipline applies unchanged on the other side) — this rescue
    # transports, it never swallows.
    def outcome(ref)
      started = clock
      payload = begin
        [:ok, @adapter.parse(ref)]
      rescue StandardError, ScriptError, SystemStackError => e
        [:raised, e]
      end
      dump_outcome(payload, clock - started)
    end

    def dump_outcome(payload, seconds)
      Marshal.dump(payload + [seconds])
    rescue TypeError => e
      Marshal.dump([:raised, portable_error(payload[1], e), seconds])
    end

    # An exception (or a document) that will not Marshal still reaches the
    # writer with its class's DISPOSITION intact: a quarantine stays a
    # quarantine, a skip a skip, anything else an abort.
    def portable_error(original, marshal_error)
      case original
      when DocumentSkipped then DocumentSkipped.new(original.message, reason: original.reason)
      when ParseError then ParseError.new(original.message)
      when Exception then ParseWorkerError.new("#{original.class}: #{original.message}")
      else ParseWorkerError.new("parse result could not cross the fork: #{marshal_error.message}")
      end
    end

    # The sqlite3 gem warns (in the child) about every writable handle the
    # fork inherited, then discards it. These forks are deliberate and the
    # discard is exactly right, so the warning is silenced for them alone;
    # any other fork in the process still warns.
    def quiet_sqlite_fork_warning
      return yield unless defined?(SQLite3::ForkSafety)

      previous = SQLite3::ForkSafety.instance_variable_get(:@suppress)
      SQLite3::ForkSafety.suppress_warnings!
      begin
        yield
      ensure
        SQLite3::ForkSafety.instance_variable_set(:@suppress, previous)
      end
    end

    # Stop the pump, close every pipe (idle workers read EOF and exit), and
    # reap every child. An abnormal exit TERMs workers first: one may be
    # deep in a mega-document, or blocked writing a result nobody reads.
    def shutdown(clean:)
      @mutex.synchronize { @stopping = true }
      wake
      @pump&.join
      @workers.each do |worker|
        worker.requests.close unless worker.requests.closed?
        worker.results.close unless worker.results.closed?
      end
      @workers.each { |worker| terminate(worker) } unless clean
      @workers.each { |worker| reap(worker.pid) if worker.alive }
      [@wake_r, @wake_w].each { |io| io.close unless io.closed? }
      @workers = nil
      @workers_forked = nil
    end

    def terminate(worker)
      Process.kill(:TERM, worker.pid) if worker.alive
    rescue Errno::ESRCH
      nil
    end

    def reap(pid)
      _, status = Process.wait2(pid)
      status
    rescue Errno::ECHILD
      nil
    end

    def write_frame(io, bytes)
      io.write([bytes.bytesize].pack(HEADER), bytes)
    end

    # nil on EOF (including a frame cut short by a dying writer).
    def read_frame(io)
      header = io.read(HEADER_BYTES)
      return nil if header.nil? || header.bytesize < HEADER_BYTES

      length = header.unpack1(HEADER)
      body = io.read(length)
      return nil if body.nil? || body.bytesize < length

      body
    end

    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
