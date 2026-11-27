# frozen_string_literal: true

require "fileutils"
require "json"

require_relative "corpus_coranicum"

module Nabu
  module Adapters
    # The one clone of telota/corpus-coranicum-tei the Corpus Coranicum
    # sibling sources read (corpus-coranicum-manuscripts,
    # corpus-coranicum-variants): canonical/corpus-coranicum/, fetched and
    # pinned by the corpus-coranicum source (Nabu::Adapters::CorpusCoranicum,
    # PINNED_SHA). The repository is cloned ONCE; each sibling declares
    # `requires: [corpus-coranicum]` in its registry row and reads the
    # sibling tree at parse time — the bhsa → bridging precedent
    # (architecture §5, the parse-time cross-source canonical read).
    #
    # A sibling's own canonical dir holds a single materialized file, the
    # pin record (PIN_FILE: the clone's slug and the commit it was read at),
    # written by the sibling's fetch after it has verified that the clone's
    # HEAD is the pinned commit. The record gives the sibling's tree a
    # strong identity (declared in materialized_paths), and a re-pin of the
    # clone edits CorpusCoranicum::PINNED_SHA — code — so the siblings'
    # stamps move with it. The fetch makes no network call.
    module CorpusCoranicumClone
      SLUG = "corpus-coranicum"
      PIN_FILE = "corpus-coranicum.pin.json"

      module_function

      # The clone beside +workdir+ (canonical/<sibling> → canonical/corpus-coranicum).
      def dir_for(workdir) = File.expand_path(File.join(workdir, "..", SLUG))

      # Verify +clone+ is a checkout of the pinned commit and record the pin
      # in +workdir+; a Nabu::FetchError names what is wrong otherwise.
      def fetch!(source_id:, workdir:, clone:, pinned_sha:)
        unless File.directory?(File.join(clone, "data"))
          raise Nabu::FetchError, "#{source_id}: the #{SLUG} clone is missing at #{clone} — sync #{SLUG} first " \
                                  "(this source reads its tree; requires: [#{SLUG}])"
        end
        sha = head(source_id, clone)
        unless sha == pinned_sha
          raise Nabu::FetchError, "#{source_id}: the #{SLUG} clone is at #{sha[0, 12]}, but the source reads it " \
                                  "pinned to #{pinned_sha[0, 12]} — re-pin both sources together (owner decision)"
        end
        FileUtils.mkdir_p(workdir)
        File.write(File.join(workdir, PIN_FILE), "#{JSON.generate('source' => SLUG, 'sha' => sha)}\n")
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now, notes: ["read from canonical/#{SLUG} at #{sha[0, 12]}"])
      end

      def head(source_id, clone)
        Nabu::Shell.run("git", "-C", clone, "rev-parse", "HEAD").strip
      rescue Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{source_id}: #{clone} is not a git checkout (#{e.message.lines.first&.strip})"
      end
    end
  end
end
