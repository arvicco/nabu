# frozen_string_literal: true

module Nabu
  # Is a process still running? The one probe the dead-row sweep, the
  # rebuild-run reader, the engine-intent replay and the index watcher
  # share. Process.kill(0) answers "does the pid exist" — but a killed
  # process its parent has not yet reaped still exists as a ZOMBIE, and a
  # zombie writes nothing ever again; so a surviving pid is confirmed
  # against its ps state ("Z…" = dead). ps is the base system's, reached
  # through Nabu::Shell (no new dependency). A pid owned by another user
  # (EPERM) is alive. A recycled pid can only read as alive — the
  # conservative error every caller is built to tolerate.
  module ProcessProbe
    module_function

    def alive?(pid)
      return false if pid.nil?

      Process.kill(0, pid)
      !zombie?(pid)
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    # The process's ps state letters ("R+", "S", "Z"…), nil when ps knows
    # no such pid.
    def state(pid)
      Shell.run("ps", "-o", "stat=", "-p", pid.to_s).strip
    rescue Shell::Error
      nil
    end

    def zombie?(pid)
      current = state(pid)
      current.nil? || current.start_with?("Z")
    end
  end
end
