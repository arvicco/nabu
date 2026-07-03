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
  end
end
