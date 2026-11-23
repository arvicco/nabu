# frozen_string_literal: true

require_relative "../inspected_text"
require_relative "../store/inspected_text_scan"

module Nabu
  module Ops
    # `rake "scrub:inspect_text[slug]"` — the live-rows instrument for the
    # inspected-object text defect (passage text stored as `{"k"=>…}` /
    # `#<Class…>` by a parser later fixed; the conformance invariant keeps
    # NEW loads clean, this finds what was loaded BEFORE the fix).
    #
    # Default: SCAN — count + samples, read-only, catalog only.
    #
    # SCRUB=1: DIAGNOSE, still read-only. There is no per-document sync
    # path (`nabu sync <slug> --parse-only` re-derives the whole source, the
    # one surgical-free seam), so the instrument never writes: it re-parses
    # each affected document in memory from canonical/ through the adapter
    # and says what the resync would actually do, then prints the command.
    # The verdicts matter because of the loader's quarantine shield: a
    # document that now QUARANTINES (the honest answer for an
    # unrecoverable shape) keeps its held rows — a quarantined urn shields
    # them from the withdrawal sweep (Store::Loader, P37-r2), under
    # `sync --parse-only` and `rebuild --incremental` alike (the same
    # full-load seam). Only a FULL `nabu rebuild` (drop + replay) clears
    # such rows, and rebuilds are owner-fired.
    class InspectTextScrub
      SAMPLE = 5
      TEXT_WIDTH = 72
      REASON_WIDTH = 240

      Verdict = Data.define(:document_urn, :passages, :outcome, :detail)

      OUTCOMES = {
        clean: "re-parses clean — a parse-only resync replaces the rows",
        absent: "no longer discovered — a parse-only resync withdraws it",
        quarantines: "now QUARANTINES — held rows are shielded from the withdrawal sweep; " \
                     "a parse-only resync and an incremental rebuild keep them, only a FULL rebuild clears them",
        still_inspected: "STILL inspect-shaped under the current adapter — an adapter defect; a resync reloads it"
      }.freeze

      # +adapter+/+workdir+ are needed only for +scrub+ (the re-parse
      # diagnosis); nil leaves the scan alone.
      def initialize(catalog:, slug:, adapter: nil, workdir: nil, scrub: false, sample: SAMPLE)
        @catalog = catalog
        @slug = slug
        @adapter = adapter
        @workdir = workdir
        @scrub = scrub
        @sample = sample
      end

      def hits
        @hits ||= Store::InspectedTextScan.new(db: @catalog).call(slug: @slug)
      end

      # One verdict per affected document (SCRUB=1).
      def verdicts
        raise ValidationError, "scrub needs the adapter and its canonical workdir" if @adapter.nil? || @workdir.nil?

        refs = @adapter.discover(@workdir).to_h { |ref| [ref.id, ref] }
        hits.group_by(&:document_urn).map do |urn, rows|
          outcome, detail = reparse(refs[urn])
          Verdict.new(document_urn: urn, passages: rows.size, outcome: outcome, detail: detail)
        end
      end

      def report
        lines = scan_lines
        lines.concat(scrub_lines) if @scrub && !hits.empty?
        lines.join("\n")
      end

      private

      def scan_lines
        documents = hits.map(&:document_urn).uniq.size
        lines = ["scrub:inspect_text #{@slug} — #{hits.size} inspect-shaped live passage(s) " \
                 "in #{documents} document(s)"]
        hits.first(@sample).each { |hit| lines << "  #{hit.passage_urn}  #{clip(hit.text)}" }
        lines << "  … #{hits.size - @sample} more" if hits.size > @sample
        lines << "  (scan only — SCRUB=1 re-parses the affected documents, prints the resync)" if !@scrub && hits.any?
        lines
      end

      def scrub_lines
        verdicts_now = verdicts
        lines = ["re-parse diagnosis (in memory, nothing written):"]
        verdicts_now.each do |verdict|
          lines << "  #{verdict.document_urn} (#{verdict.passages} passage(s)): #{OUTCOMES.fetch(verdict.outcome)}"
          lines << "    #{verdict.detail}" if verdict.detail
        end
        lines.concat(next_steps(verdicts_now.map(&:outcome).uniq))
      end

      def next_steps(outcomes)
        lines = ["no per-document sync path exists; the remedy is source-wide:"]
        if outcomes.intersect?(%i[clean absent])
          lines << "  bin/nabu sync #{@slug} --parse-only   # replaces/withdraws the clean and absent documents"
        end
        if outcomes.include?(:quarantines)
          lines << "  the quarantining documents clear only at the next FULL `nabu rebuild` (owner-fired)"
        end
        lines << "  fix the adapter first — a resync would reload the same text" if outcomes.include?(:still_inspected)
        lines
      end

      def reparse(ref)
        return [:absent, nil] if ref.nil?

        document = @adapter.parse(ref)
        still = document.passages.count { |passage| InspectedText.match?(passage.text) }
        still.positive? ? [:still_inspected, "#{still} passage(s) still match"] : [:clean, nil]
      rescue ParseError => e
        [:quarantines, clip(reason_of(e.message, ref.id), width: REASON_WIDTH)]
      end

      # The quarantine reason without its location prefixes (canonical
      # paths, the urn) — those are already on the verdict line.
      def reason_of(message, urn)
        message.gsub(%r{(?:\A|(?<=: ))\S*/\S+: }, "").gsub("#{urn}: ", "")
      end

      def clip(text, width: TEXT_WIDTH)
        flat = text.to_s.gsub(/\s+/, " ")
        flat.length > width ? "#{flat[0, width]}…" : flat
      end
    end
  end
end
