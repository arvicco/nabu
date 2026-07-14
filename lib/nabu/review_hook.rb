# frozen_string_literal: true

require "json"
require "open3"

module Nabu
  # The OPTIONAL post-sync AI-review hook (P18-7). `nabu sync SLUG --review
  # CMD` assembles a structured JSON brief of what the sync just did and pipes
  # it to CMD's stdin; CMD is any executable — the bundled
  # script/review-sync-claude wires `claude -p` with the nabu MCP server, but
  # nabu itself neither knows nor cares (the hook is a SUBPROCESS BOUNDARY: no
  # cloud dependency enters the core, docs/ops.md §11).
  #
  # Contract:
  # - the brief is one JSON object on stdin (shape below, schema-tagged so a
  #   hook can refuse a version it does not understand);
  # - the hook's combined output is relayed to the operator verbatim;
  # - the hook's exit status is REPORTED honestly and NEVER fails the sync —
  #   the sync already happened; the review is judgment, not a gate.
  #
  # Brief shape (nabu.sync-review/1):
  #   source            slug
  #   fetched_sha       the fetched commit (null on --parse-only)
  #   counts            added/updated/skipped/withdrawn/errored/indexed
  #   quarantine        errored + the ledger baseline/anchor (post-advance;
  #                     null when the ledger predates migration 005)
  #   discovery         selected/skipped_by_rule/unrecognized + loud notes
  #   warnings          the deviation warning messages (quarantine delta,
  #                     withdrawal sweep) — the mechanical layer's verdicts
  #   sample_urns       up to SAMPLE_URNS fresh passage (or dictionary-entry)
  #                     urns from this sync, for spot reads via MCP
  module ReviewHook
    SAMPLE_URNS = 5

    # +status+ is the hook's exit status, or nil when it could not be started
    # at all (missing command); +output+ its combined stdout+stderr.
    Result = Data.define(:status, :output) do
      def ok? = !status.nil? && status.zero?
    end

    module_function

    # Assemble the brief for a finished (non-aborted) sync Outcome. Read-only
    # on both handles.
    def brief(outcome:, db:, ledger:)
      report = outcome.load_report
      {
        schema: "nabu.sync-review/1",
        source: outcome.slug,
        fetched_sha: outcome.fetch_report&.sha,
        counts: {
          added: report.added, updated: report.updated, skipped: report.skipped,
          withdrawn: report.withdrawn, errored: report.errored, indexed: outcome.indexed
        },
        quarantine: quarantine_section(ledger, outcome.slug, report.errored),
        discovery: discovery_section(outcome.discovery),
        warnings: outcome.warnings.map(&:message),
        sample_urns: sample_urns(db, outcome.slug)
      }
    end

    # Pipe +brief+ (as JSON) to +command+'s stdin. Never raises: a hook that
    # cannot even start is a Result with status nil, reported like any other.
    def run(command:, brief:)
      output, status = Open3.capture2e(command, stdin_data: JSON.generate(brief))
      Result.new(status: status.exitstatus, output: output)
    rescue SystemCallError => e
      Result.new(status: nil, output: e.message)
    end

    def quarantine_section(ledger, slug, errored)
      row = Health::QuarantineBaseline.read(ledger, slug)
      { errored: errored, baseline: row&.fetch(:baseline), anchor: row&.fetch(:anchor) }
    end

    def discovery_section(discovery)
      return nil if discovery.nil?

      {
        skipped_by_rule: discovery.skipped_by_rule,
        unrecognized: discovery.unrecognized,
        notes: discovery.notes
      }
    end

    # Up to SAMPLE_URNS urns this sync freshly wrote, via the provenance
    # journal (the loaders stamp loaded/revised rows): passage urns for text
    # corpora, entry urns for dictionary sources. Most-recent first; empty
    # when the sync wrote nothing (all-skipped resync) — honest, not padded.
    def sample_urns(db, slug)
      source = db[:sources].where(slug: slug).select(:id).first
      return [] if source.nil?

      urns = passage_samples(db, source)
      urns.empty? ? entry_samples(db, source) : urns
    end

    def passage_samples(db, source)
      doc_ids = db[:provenance]
                .where(event: %w[loaded revised])
                .where(document_id: db[:documents].where(source_id: source[:id]).select(:id))
                .order(Sequel.desc(:at), Sequel.desc(:id))
                .select_map(:document_id).uniq.first(SAMPLE_URNS)
      doc_ids.filter_map { |id| db[:passages].where(document_id: id).order(:sequence).get(:urn) }
    end

    def entry_samples(db, source)
      return [] unless db.table_exists?(:dictionary_entries) && db[:provenance].columns.include?(:dictionary_entry_id)

      entry_ids = db[:dictionary_entries]
                  .where(dictionary_id: db[:dictionaries].where(source_id: source[:id]).select(:id))
                  .select(:id)
      db[:provenance]
        .where(event: %w[loaded revised], dictionary_entry_id: entry_ids)
        .order(Sequel.desc(:at), Sequel.desc(:id))
        .select_map(:dictionary_entry_id).uniq.first(SAMPLE_URNS)
        .filter_map { |id| db[:dictionary_entries].where(id: id).get(:urn) }
    end
  end
end
