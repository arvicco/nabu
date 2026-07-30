# frozen_string_literal: true

require_relative "../tibetan_segmenter"

module Nabu
  module DataBuild
    # The in-band evaluation for xct/segmentation (P51-W5): leave-one-text-out
    # cross-validation against gold segmentation. For each gold text, a
    # segmenter is trained on the OTHER texts' token counts and scored on the
    # held-out text — so the published number never scores a model on
    # vocabulary harvested from the very lines it is scored on (the
    # train/test-honesty ruling in the packet: the eval is "clean", not
    # contaminated). The micro-averaged scores over all folds are what the
    # manifest's nabu.eval block and the dataset README publish.
    #
    # Metrics, computed per line over the joined gold text:
    #   boundary P/R/F1  char positions where a token starts (line-interior);
    #                    the honest grain — it prices clitic splits INSIDE a
    #                    tsheg-bar and merges across tshegs equally.
    #   token F1         exact token spans (both boundaries right).
    class SegmentationEval
      MINIMUM_TEXTS = 2

      PROTOCOL = "leave-one-text-out cross-validation"
      CONTAMINATION = "clean — each fold's segmenter is trained only on the other texts' " \
                      "gold counts, never on the text it is scored on"

      class << self
        # +docs+: { text_key => [ { text:, forms: [String] }, ... ] } — one
        # entry per gold text, passages carrying the joined text and the gold
        # token forms in order (forms.join == text; the builder validates).
        # Returns the eval hash the manifest publishes.
        def leave_one_text_out(docs)
          if docs.size < MINIMUM_TEXTS
            raise Error, "the leave-one-text-out eval needs at least #{MINIMUM_TEXTS} gold texts, " \
                         "got #{docs.size} — the protocol cannot hold out a text it trains on"
          end

          boundary = { tp: 0, fp: 0, fn: 0 }
          token = { tp: 0, fp: 0, fn: 0 }
          docs.each_key do |held_out|
            segmenter = TibetanSegmenter.train(counts(docs.except(held_out)))
            docs.fetch(held_out).each do |passage|
              score_line(passage, segmenter, boundary, token)
            end
          end

          report(docs, boundary, token)
        end

        # Token counts over gold forms (the segmenter drops non-word keys).
        def counts(docs)
          counts = Hash.new(0)
          docs.each_value do |passages|
            passages.each { |passage| passage.fetch(:forms).each { |form| counts[form] += 1 } }
          end
          counts
        end

        private

        def score_line(passage, segmenter, boundary, token)
          gold = spans_of(passage.fetch(:forms))
          predicted = segmenter.segment(passage.fetch(:text))
                               .map { |tok| [tok.offset, tok.offset + tok.form.length] }
          tally(boundary, interior_starts(gold), interior_starts(predicted))
          tally(token, gold.to_set, predicted.to_set)
        end

        def spans_of(forms)
          offset = 0
          forms.map do |form|
            span = [offset, offset + form.length]
            offset = span.last
            span
          end
        end

        # Token start positions, excluding line start (position 0 is not a
        # segmentation decision).
        def interior_starts(spans)
          spans.map(&:first).reject(&:zero?).to_set
        end

        def tally(counters, gold, predicted)
          counters[:tp] += (predicted & gold).size
          counters[:fp] += (predicted - gold).size
          counters[:fn] += (gold - predicted).size
        end

        def report(docs, boundary, token)
          precision, recall, f1 = scores(boundary)
          {
            "boundary_precision" => precision,
            "boundary_recall" => recall,
            "boundary_f1" => f1,
            "token_f1" => scores(token).last,
            "texts" => docs.size,
            "lines" => docs.each_value.sum(&:size),
            "tokens" => docs.each_value.sum { |passages| passages.sum { |passage| passage.fetch(:forms).size } },
            "protocol" => PROTOCOL,
            "contamination" => CONTAMINATION
          }
        end

        def scores(counters)
          tp = counters.fetch(:tp)
          precision = ratio(tp, tp + counters.fetch(:fp))
          recall = ratio(tp, tp + counters.fetch(:fn))
          f1 = (precision + recall).positive? ? (2 * precision * recall / (precision + recall)) : 0.0
          [precision, recall, f1].map { |value| value.round(4) }
        end

        def ratio(numerator, denominator)
          denominator.zero? ? 0.0 : numerator.to_f / denominator
        end
      end
    end
  end
end
