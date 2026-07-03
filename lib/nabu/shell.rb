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

      raise Error.new(
        "command failed (exit #{status.exitstatus}): #{argv.first}",
        status: status.exitstatus,
        stderr: stderr
      )
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

      raise Error.new(
        "command failed (exit #{status.exitstatus}): #{argv.first}",
        status: status.exitstatus,
        stderr: captured
      )
    rescue Errno::ENOENT => e
      raise Error.new("command not found: #{argv.first} (#{e.message})", status: nil, stderr: "")
    end

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
