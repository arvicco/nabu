# frozen_string_literal: true

require "date"
require "fileutils"
require "time"
require "yaml"

module Nabu
  module Ops
    # The cadence of the two standing proofs that otherwise run on memory
    # alone: `rake ops:drill` (the derivability law's proof — the three
    # folders restore and re-derive db/) and `rake fixtures:check` (the
    # fixture sentinel — every checked-in fixture still matches upstream).
    # Each task stamps its last SUCCESSFUL run (a full, clean completion
    # only — a refused, crashed or failing drill and a drifting or
    # single-source fixtures:check stamp nothing); `rake boards:check`
    # flags a proof whose stamp is older than MAX_AGE_DAYS, or missing.
    #
    # The stamps are loop-written instance state in local/proofs/ (inside
    # the gitignored instance folder, the trickle runner's pattern —
    # local/trickle/ — created on first stamp), one YAML file per proof:
    #
    #   local/proofs/<proof>.yml   { last_success: <ISO-8601 UTC>, detail: <one line> }
    #
    # No proofs home (a public clone, a lane worktree, a box that has run
    # neither proof since the stamps existed) is an announced skip.
    module ProofCadence
      DIRNAME = "proofs"
      MAX_AGE_DAYS = 60
      # proof id → the command that re-proves it.
      PROOFS = { "ops-drill" => "rake ops:drill", "fixtures-check" => "rake fixtures:check" }.freeze

      def self.dir(local_dir) = File.join(local_dir, DIRNAME)
      def self.stamp_path(local_dir, proof) = File.join(dir(local_dir), "#{proof}.yml")

      # Record +proof+'s successful completion at +at+.
      def self.record!(local_dir:, proof:, at: Time.now.utc, detail: nil)
        raise ArgumentError, "unknown proof #{proof.inspect} (#{PROOFS.keys.join(', ')})" unless PROOFS.key?(proof)

        FileUtils.mkdir_p(dir(local_dir))
        path = stamp_path(local_dir, proof)
        File.write(path, YAML.dump({ "last_success" => at.utc.iso8601, "detail" => detail }.compact))
        path
      end

      # The `rake boards:check` staleness probe over the stamps.
      class Check
        Report = Data.define(:skipped, :stamps, :findings) do
          def clean? = findings.empty?
        end

        def initialize(local_dir:, today: Date.today, max_age_days: MAX_AGE_DAYS)
          @local_dir = local_dir
          @today = today
          @max_age = max_age_days
        end

        def run
          home = ProofCadence.dir(@local_dir)
          return Report.new(skipped: true, stamps: {}, findings: []) unless File.directory?(home)

          stamps = {}
          findings = PROOFS.filter_map do |proof, command|
            date = last_success(proof)
            stamps[proof] = date if date.is_a?(Date)
            judge(proof, command, date)
          end
          Report.new(skipped: false, stamps: stamps, findings: findings)
        end

        private

        # A Date, :missing, or :unreadable.
        def last_success(proof)
          path = ProofCadence.stamp_path(@local_dir, proof)
          return :missing unless File.file?(path)

          data = YAML.safe_load_file(path)
          Time.iso8601(data.fetch("last_success").to_s).utc.to_date
        rescue Psych::Exception, KeyError, ArgumentError, NoMethodError
          :unreadable
        end

        def judge(proof, command, date)
          case date
          when :missing then "#{proof}: no recorded successful run — run `#{command}`"
          when :unreadable then "#{proof}: stamp #{ProofCadence.stamp_path(@local_dir, proof)} unreadable — " \
                                "run `#{command}` to re-stamp"
          else
            age = (@today - date).to_i
            return if age <= @max_age

            "#{proof}: last successful run #{date.iso8601} (#{age} days ago, over #{@max_age}) — run `#{command}`"
          end
        end
      end
    end
  end
end
