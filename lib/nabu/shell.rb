# frozen_string_literal: true

require "open3"

module Nabu
  # Runs external commands (git, mutool, ...) with argv semantics — the program
  # and each argument are passed as separate strings and never interpreted by a
  # shell, so arguments containing spaces, $VAR, globs, etc. are passed
  # literally. Captures stdout and stderr; returns stdout on success and raises
  # Nabu::Shell::Error (carrying exit status and stderr) on nonzero exit.
  #
  #   Nabu::Shell.run("git", "-C", repo, "rev-parse", "HEAD") # => "<sha>\n"
  #
  # Never use backticks or Kernel#system for command execution — always route
  # through here.
  module Shell
    # Raised when a command exits nonzero (or cannot be spawned). Carries the
    # exit status and the captured stderr for diagnostics.
    class Error < Nabu::Error
      attr_reader :status, :stderr

      def initialize(message, status:, stderr:)
        super(message)
        @status = status
        @stderr = stderr
      end
    end

    # Run +argv+ (program followed by its arguments). Returns captured stdout on
    # success; raises Nabu::Shell::Error on nonzero exit or spawn failure.
    def self.run(*argv)
      raise ArgumentError, "Shell.run requires a command" if argv.empty?

      stdout, stderr, status = Open3.capture3(*argv)
      return stdout if status.success?

      raise failure(argv, status.exitstatus, stderr)
    rescue Errno::ENOENT => e
      raise Error.new("command not found: #{argv.first} (#{e.message})", status: nil, stderr: "")
    end

    # Like run, but streams: stdout and stderr are merged and forwarded to the
    # block line by line AS THEY ARRIVE, so long operations (a git clone) can
    # show live progress instead of several minutes of silence. Lines are split
    # on \n OR \r, so git's `--progress` updates — which overwrite the current
    # line with \r and never emit a newline until the end — forward live rather
    # than buffering until the command finishes. Everything forwarded is also
    # captured, so a nonzero exit raises the SAME Nabu::Shell::Error (with the
    # captured output as stderr) as run() would. Returns nil on success.
    #
    #   Nabu::Shell.stream("git", "clone", "--progress", url, dir) { |l| warn l }
    def self.stream(*argv, &on_line)
      raise ArgumentError, "Shell.stream requires a command" if argv.empty?

      captured = +""
      status = Open3.popen2e(*argv) do |stdin, out, wait_thread|
        stdin.close
        forward_lines(out, captured, &on_line)
        wait_thread.value
      end
      return if status.success?

      raise failure(argv, status.exitstatus, captured)
    rescue Errno::ENOENT => e
      raise Error.new("command not found: #{argv.first} (#{e.message})", status: nil, stderr: "")
    end

    # A line-oriented REQUEST/RESPONSE session with one long-lived
    # subprocess (P84-1: the stanza lemma worker — model load costs ~10s,
    # so the enricher keeps ONE worker alive and feeds it batches). The
    # block receives a Duplex session (#write_line / #read_line); stderr is
    # drained concurrently and carried onto the Error whether the worker
    # exits nonzero, dies mid-protocol, or ends before answering. Returns
    # the block's value on clean exit.
    #
    #   Shell.duplex(python, "worker.py") do |w|
    #     w.write_line(request_json)
    #     JSON.parse(w.read_line)
    #   end
    def self.duplex(*argv)
      raise ArgumentError, "Shell.duplex requires a command" if argv.empty?
      raise ArgumentError, "Shell.duplex requires a block" unless block_given?

      captured = +""
      Open3.popen3(*argv) do |stdin, stdout, stderr, wait_thread|
        drain = Thread.new do
          stderr.each_line { |line| captured << line }
        rescue IOError
          # A block-raised exception unwinds popen3, which closes stderr
          # under us — the drain has captured everything it could.
          nil
        end
        on_death = lambda do |reason|
          stdin.close unless stdin.closed?
          status = wait_thread.value
          drain.join
          raise failure(argv, status.exitstatus, captured, prefix: reason)
        end
        result = yield Duplex.new(stdin: stdin, stdout: stdout, on_death: on_death)
        stdin.close unless stdin.closed?
        status = wait_thread.value
        drain.join
        raise failure(argv, status.exitstatus, captured) unless status.success?

        result
      end
    rescue Errno::ENOENT => e
      raise Error.new("command not found: #{argv.first} (#{e.message})", status: nil, stderr: "")
    end

    # The two ends of a duplex session. Any sign the worker is gone (EPIPE
    # on write, EOF on read) routes to +on_death+, which raises a
    # Shell::Error carrying the worker's stderr — the protocol never
    # returns a half-truth.
    class Duplex
      def initialize(stdin:, stdout:, on_death:)
        @stdin = stdin
        @stdout = stdout
        @on_death = on_death
      end

      def write_line(line)
        @stdin.puts(line)
        @stdin.flush
      rescue Errno::EPIPE
        @on_death.call("worker closed its input pipe")
      end

      def read_line
        line = @stdout.gets
        @on_death.call("worker ended before answering") if line.nil?
        line.chomp
      end
    end

    # The message names the command AND (bounded, one line) what it said —
    # P77-r12: a bare "command failed (exit 1): rsync" hid an out-of-disk
    # condition; the stderr was captured, carried, and shown nowhere. The
    # full untruncated stderr still rides on the error object.
    DETAIL_CHARS = 300

    def self.failure(argv, exitstatus, stderr, prefix: "command failed")
      message = "#{prefix} (exit #{exitstatus}): #{argv.first}"
      # P78-r4: stderr is UNTRUSTED BYTES (unzip echoes junk-named zip
      # members raw — the goryeosa-jeoryo CP949 crash); scrub before any
      # string surgery or the message builder masks the real failure.
      detail = stderr.to_s.scrub("�").strip.gsub(/\s+/, " ")
      message << " — #{detail[0, DETAIL_CHARS]}" unless detail.empty?
      Error.new(message, status: exitstatus, stderr: stderr)
    end
    private_class_method :failure

    # Drain +io+ to EOF, appending every byte to +captured+ and (if a block was
    # given) yielding each \n- or \r-terminated line as it arrives, plus any
    # unterminated trailing fragment at EOF.
    def self.forward_lines(io, captured, &on_line)
      buffer = +""
      begin
        loop do
          chunk = io.readpartial(4096)
          captured << chunk
          next unless on_line

          buffer << chunk
          while (index = buffer.index(/[\r\n]/))
            on_line.call(buffer.slice!(0..index))
          end
        end
      rescue EOFError
        nil
      end
      on_line.call(buffer) if on_line && !buffer.empty?
    end
    private_class_method :forward_lines
  end
end
