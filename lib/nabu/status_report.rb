# frozen_string_literal: true

module Nabu
  # Renders `nabu status`: one aligned plain-text line per registered source —
  # enabled/disabled, sync policy, live document/passage counts (withdrawn
  # excluded), and the last run's outcome. Pure string building over the
  # registry plus (optionally) the catalog db and the history ledger (P7-1:
  # runs live in the ledger, slug-keyed), so it is unit-testable without the
  # CLI. A nil db means "not built yet"; a nil ledger means "no history yet"
  # (fresh machine) and the run column degrades honestly.
  module StatusReport
    module_function

    def render(registry:, db:, ledger:)
      return "No sources registered." if registry.empty?

      width = registry.each_source.map { |entry| entry.slug.length }.max
      registry.each_source.map { |entry| render_entry(entry, db, ledger, width) }.join("\n")
    end

    def render_entry(entry, db, ledger, width)
      head = "#{entry.slug.ljust(width)}  #{state(entry.enabled).ljust(8)}  #{entry.sync_policy.ljust(6)}"
      return "#{head}  no database (run nabu sync)" if db.nil?

      source = Store::Source.first(slug: entry.slug)
      return "#{head}  docs=0 passages=0  #{last_run(entry.slug, ledger)}" if source.nil?

      live = Store::Document.where(source_id: source.id, withdrawn: false)
      # retired (upstream-scrapped, attic-kept — P5-2) documents are live and
      # inside docs=; the extra count keeps upstream attrition visible.
      "#{entry.slug.ljust(width)}  #{state(source.enabled).ljust(8)}  #{entry.sync_policy.ljust(6)}  " \
        "docs=#{live.count} passages=#{passage_count(source.id)} " \
        "retired=#{live.where(retired_upstream: true).count}  #{last_run(entry.slug, ledger)}"
    end

    def passage_count(source_id)
      live_documents = Store::Document.where(source_id: source_id, withdrawn: false).select(:id)
      Store::Passage.where(withdrawn: false).where(document_id: live_documents).count
    end

    # The latest run of ANY kind — a rebuild replay is honest "last activity"
    # here (trend queries elsewhere filter kind=sync; status just reports).
    def last_run(slug, ledger)
      return "no run history" if ledger.nil?

      run = Store::Run.where(source_slug: slug).order(Sequel.desc(:id)).first
      return "never synced" if run.nil?

      "last run #{run.finished_at || run.started_at} #{run.status} " \
        "(+#{run.added} ~#{run.updated} -#{run.withdrawn_count} !#{run.errored})"
    end

    def state(enabled)
      enabled ? "enabled" : "disabled"
    end
  end
end
