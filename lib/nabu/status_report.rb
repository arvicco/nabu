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

      # A synced source carries its live enabled state in the row; an
      # unsynced one falls back to the registry's declared enabled.
      source = Store::Source.first(slug: entry.slug)
      enabled = source ? source.enabled : entry.enabled
      "#{entry.slug.ljust(width)}  #{state(enabled).ljust(8)}  #{entry.sync_policy.ljust(6)}  " \
        "#{counts_fragment(entry, source)}  #{last_run(entry.slug, ledger)}"
    end

    # The count fragment of the row, shaped by the source's content_kind
    # (P11-10). A dictionary source's content is entries, not docs/passages —
    # rendering docs=0 passages=0 for a 168k-entry lexicon was a misleading
    # zero (the P11-7 missed-surface class). Passage sources keep the
    # docs/passages/retired triple.
    def counts_fragment(entry, source)
      return "entries=#{dictionary_entry_count(source)}" if dictionary?(entry)
      return "docs=0 passages=0" if source.nil?

      live = Store::Document.where(source_id: source.id, withdrawn: false)
      # retired (upstream-scrapped, attic-kept — P5-2) documents are live and
      # inside docs=; the extra count keeps upstream attrition visible.
      "docs=#{live.count} passages=#{passage_count(source.id)} " \
        "retired=#{live.where(retired_upstream: true).count}"
    end

    def dictionary?(entry)
      entry.adapter_class.content_kind == :dictionary
    rescue Nabu::Error
      # A broken/unknown adapter class is not this renderer's problem to
      # raise on; treat it as a plain passage source so status still prints.
      false
    end

    # Live dictionary entries owned by this source (across all its
    # dictionaries). Zero for an unsynced source (no rows yet) — honest, not
    # misleading, because the row shape already says "entries".
    def dictionary_entry_count(source)
      return 0 if source.nil?

      dictionaries = Store::Dictionary.where(source_id: source.id).select(:id)
      Store::DictionaryEntry.where(dictionary_id: dictionaries, withdrawn: false).count
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
