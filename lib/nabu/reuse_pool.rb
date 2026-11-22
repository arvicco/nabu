# frozen_string_literal: true

require "etc"
require_relative "errors"

module Nabu
  # The reuse engine's fork pool (the census passes and the postings
  # scoring workers, Nabu::ReuseCensus / Nabu::BatchParallelsPostings): a
  # bounded set of FORKED workers mapping tasks to results, delivered to
  # the caller strictly in TASK ORDER — the single-committer half of the
  # design (workers compute, one process writes).
  #
  #   pool = ReusePool.new(workers: 8, setup: ->(index) { state }, work: ->(state, task) { result },
  #                        finish: ->(state) { final })
  #   finals = pool.map(tasks) { |result| commit(result) }
  #
  # - +setup+ runs once IN EACH WORKER after the fork (its own SQLite
  #   handles open there, never inherited); +finish+ runs at the worker's
  #   end of input and its value comes back as that worker's FINAL (the
  #   census workers' per-file tallies). With +workers+ ≤ 1 the same three
  #   callables run in-process — one code path, so the serial run is the
  #   reference the forked one is tested against.
  # - Dispatch is dynamic with IN_FLIGHT tasks per worker; one pump thread
  #   per worker drains its result pipe (blocked reads release the GVL), so
  #   a large task write can never deadlock against a large result write.
  # - Tasks and results cross the fork as Marshal frames — plain arrays,
  #   hashes, strings and numbers only (the callers' payloads).
  #
  # Failure is loud and positional: a worker exception travels back and is
  # raised as WorkerError at its own slot (every earlier result delivered
  # first); a worker that dies, or fails outside any task, raises at once;
  # every child is reaped on every exit path. The ParsePool precedent,
  # narrowed to what the reuse engine needs (no byte caps — its tasks are
  # sized by the caller's chunk grain).
  class ReusePool
    class WorkerError < Nabu::Error; end

    IN_FLIGHT = 2
    HEADER = "Q>"
    HEADER_BYTES = 8

    # The default worker count: cores − 1 (the committer keeps one), the
    # ParsePool ceiling applied.
    def self.default_workers(nprocessors: Etc.nprocessors) = (nprocessors - 1).clamp(1, 8)

    Worker = Struct.new(:index, :pid, :requests, :results, :outstanding)

    # A task's failure, buffered at its slot until delivery reaches it.
    Failure = Data.define(:message)

    def initialize(workers:, setup:, work:, finish: nil)
      @workers = workers.to_i
      @setup = setup
      @work = work
      @finish = finish
    end

    # Map +tasks+ (any Enumerable), yielding each result in task order.
    # Returns the workers' finals, in worker-index order.
    def map(tasks, &)
      @workers <= 1 ? serial(tasks, &) : forked(tasks, &)
    end

    private

    def serial(tasks)
      state = @setup.call(0)
      tasks.each { |task| yield @work.call(state, task) }
      [@finish&.call(state)]
    end

    def forked(tasks, &)
      @pool = Array.new(@workers) { |index| fork_worker(index) }
      @queue = Thread::Queue.new
      @pumps = @pool.map { |worker| Thread.new { pump(worker) } }
      clean = false
      drive(tasks.each_entry, &)
      finals = collect_finals
      clean = true
      finals
    ensure
      shutdown(clean: clean)
    end

    # The dispatch/reorder loop: keep every worker IN_FLIGHT-deep, deliver
    # the buffered results that are next in order.
    def drive(enum)
      sent = 0
      delivered = 0
      buffer = {}
      exhausted = false
      loop do
        exhausted, sent = fill(enum, sent) unless exhausted
        break if exhausted && delivered == sent

        seq, value = take_result
        buffer[seq] = value
        while buffer.key?(delivered)
          value = buffer.delete(delivered)
          raise WorkerError, value.message if value.is_a?(Failure)

          yield value
          delivered += 1
        end
      end
    end

    def fill(enum, sent)
      @pool.sort_by(&:outstanding).each do |worker|
        while worker.outstanding < IN_FLIGHT
          more, task = next_task(enum)
          return [true, sent] unless more

          write_frame(worker.requests, Marshal.dump([sent, task]))
          worker.outstanding += 1
          sent += 1
        end
      end
      [false, sent]
    end

    def next_task(enum)
      [true, enum.next]
    rescue StopIteration
      [false, nil]
    end

    # The next result frame off any pump; worker failures raise here.
    def take_result
      worker, frame = @queue.pop
      raise WorkerError, "reuse worker #{worker.index} (pid #{worker.pid}) died mid-task" if frame.nil?

      message = Marshal.load(frame) # rubocop:disable Security/MarshalLoad -- our own child's bytes
      case message
      in [:ok, seq, value]
        worker.outstanding -= 1
        [seq, value]
      in [:error, seq, klass, text, backtrace]
        failure = "reuse worker #{worker.index} failed on task #{seq}: #{klass}: #{text}\n  " \
                  "#{Array(backtrace).first(8).join("\n  ")}"
        raise WorkerError, failure if seq.negative? # the worker itself, not one task

        worker.outstanding -= 1
        [seq, Failure.new(failure)]
      end
    end

    # Close every request pipe (workers read EOF, run +finish+, send their
    # final) and gather one final per worker.
    def collect_finals
      @pool.each { |worker| worker.requests.close }
      finals = {}
      until finals.size == @pool.size
        worker, frame = @queue.pop
        next if frame.nil? && finals.key?(worker.index) # the EOF after a delivered final
        raise WorkerError, "reuse worker #{worker.index} (pid #{worker.pid}) died before its final" if frame.nil?

        message = Marshal.load(frame) # rubocop:disable Security/MarshalLoad -- our own child's bytes
        raise WorkerError, "reuse worker #{worker.index} failed at finish: #{message[2]}: #{message[3]}" \
          if message.first == :error

        finals[worker.index] = message.last
      end
      finals.sort.map(&:last)
    end

    def pump(worker)
      while (frame = read_frame(worker.results))
        @queue << [worker, frame]
      end
      @queue << [worker, nil]
    rescue IOError
      @queue << [worker, nil]
    end

    def fork_worker(index)
      requests_r, requests_w = IO.pipe
      results_r, results_w = IO.pipe
      inherited = (@forked ||= []).flat_map { |worker| [worker.requests, worker.results] }
      $stdout.flush
      $stderr.flush
      pid = quiet_sqlite_fork_warning do
        fork do
          inherited.each { |io| io.close unless io.closed? }
          requests_w.close
          results_r.close
          work_loop(index, requests_r, results_w)
        end
      end
      requests_r.close
      results_w.close
      Worker.new(index, pid, requests_w, results_r, 0).tap { |worker| @forked << worker }
    end

    # The child's whole life. exit! — never the parent's at_exit handlers.
    # The rescues TRANSPORT a failure to the parent (re-raised there as
    # WorkerError at the task's slot); they never swallow it.
    def work_loop(index, requests, results)
      state = @setup.call(index)
      while (frame = read_frame(requests))
        seq, task = Marshal.load(frame) # rubocop:disable Security/MarshalLoad -- our own parent's bytes
        write_frame(results, Marshal.dump(outcome(state, seq, task)))
      end
      write_frame(results, Marshal.dump(finish_outcome(state)))
      exit!(0)
    rescue StandardError, ScriptError => e
      write_frame(results, Marshal.dump([:error, -1, e.class.name, e.message, e.backtrace]))
      exit!(1)
    ensure
      exit!(1)
    end

    def outcome(state, seq, task)
      [:ok, seq, @work.call(state, task)]
    rescue StandardError, ScriptError => e
      [:error, seq, e.class.name, e.message, e.backtrace]
    end

    def finish_outcome(state)
      [:final, @finish&.call(state)]
    rescue StandardError, ScriptError => e
      [:error, -1, e.class.name, e.message, e.backtrace]
    end

    def shutdown(clean:)
      Array(@pool).each do |worker|
        worker.requests.close unless worker.requests.closed?
        terminate(worker.pid) unless clean
        Process.wait(worker.pid)
      rescue Errno::ECHILD
        nil
      end
      Array(@pumps).each(&:join)
      Array(@pool).each { |worker| worker.results.close unless worker.results.closed? }
    end

    # TERM a worker that may already have exited (then it only needs the
    # reaping wait that follows).
    def terminate(pid)
      Process.kill("TERM", pid)
    rescue Errno::ESRCH
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

    # The sqlite3 gem warns (in the child) about every writable handle the
    # fork inherited, then discards it — exactly right here, so the warning
    # is silenced for these forks alone (the ParsePool precedent).
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
  end
end
