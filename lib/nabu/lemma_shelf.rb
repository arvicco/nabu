# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "errors"

module Nabu
  # The SANCTIONED write gateway to the local-lemmas shelf (P84-1,
  # architecture §16) — the FIFTH local-shelf gateway, beside
  # LanguageShelf, LibraryShelf, SourceShelf and NoteShelf, and the same
  # doctrine at machine grain: the silver-lemma enricher's model output is
  # NON-DERIVABLE (hours of CPU per campaign — the derivability law routes
  # it to a shelf, never db/), so `nabu lemma-enrich` lands it here through
  # this one gateway. Everything else — the silver-lemma indexer, the
  # census surfaces, LocalFetch's pin scan — stays read-only on the shelf.
  #
  # == Layout
  #
  #   local/shelves/local-lemmas/<language>/shard-NNNNNN.jsonl
  #   local/shelves/local-lemmas/<language>/.lemma-enrich-state.json
  #
  # One language lane per catalog code (lat first). Shards are append-only
  # JSONL — one object per line, one PASSAGE per object, raw model tokens
  # kept verbatim ([surface, lemma, upos] triples) so index-time policy
  # (folding, filters) can change without re-running the model. A shard
  # lands whole via tmp + validate + rename (the NoteShelf/P20-1 rule); the
  # state file is the campaign checkpoint (the corpus-corporum two-grain
  # mold): crash recovery loses at most one unflushed batch.
  class LemmaShelf
    # The shelf's directory name under local/shelves/ — also its registry
    # slug.
    SLUG = "local-lemmas"

    # The campaign checkpoint's file name (dot-prefixed: shelf furniture,
    # never a shard).
    STATE_FILE = ".lemma-enrich-state.json"

    SHARD_GLOB = "shard-*.jsonl"
    SHARD_FORMAT = "shard-%06d.jsonl"

    # A gateway refusal (invalid record, language mismatch, empty batch).
    # The CLI reports it; nothing was written.
    class Error < Nabu::Error; end

    # A shard the reader cannot faithfully parse — raised naming file:line;
    # the indexer must never guess past a malformed record.
    class FormatError < Nabu::Error; end

    # One lemmatized passage: raw model output plus provenance. +tokens+ is
    # an array of [surface, lemma, upos] triples exactly as the model
    # emitted them; +package+ names the model package (e.g.
    # "la:default(ittb)") so rows from a future re-run are distinguishable.
    Record = Data.define(:urn, :language, :source, :model, :model_version,
                         :package, :tokens, :generated_at) do
      def self.from_h(hash)
        new(urn: hash["urn"], language: hash["language"], source: hash["source"],
            model: hash["model"], model_version: hash["model_version"],
            package: hash["package"], tokens: hash["tokens"],
            generated_at: hash["generated_at"])
      end

      def to_h
        { "urn" => urn, "language" => language, "source" => source,
          "model" => model, "model_version" => model_version,
          "package" => package, "tokens" => tokens,
          "generated_at" => generated_at }
      end
    end

    # P71-2 (the local/ elevation): the shelf's home is resolved by the
    # config's workdir seam — local/shelves/<slug>.
    def self.dir(config)
      config.source_workdir(SLUG)
    end

    def initialize(dir:)
      @dir = dir
    end

    attr_reader :dir

    def language_dir(language)
      File.join(@dir, language)
    end

    # Append one batch of records as the language lane's next numbered
    # shard. Every record is validated BEFORE any byte lands; the shard is
    # staged to .tmp, reparsed whole, and only then renamed into place — a
    # shard the reader would refuse can never exist. Returns the shard path.
    def append_batch!(language:, records:)
      raise Error, "refusing an empty batch — nothing to shelve" if records.empty?

      records.each { |record| validate!(record, language) }
      dir = language_dir(language)
      FileUtils.mkdir_p(dir)
      path = File.join(dir, format(SHARD_FORMAT, next_shard_number(dir)))
      tmp = "#{path}.tmp"
      File.write(tmp, records.map { |r| JSON.generate(r.to_h) }.join("\n") << "\n")
      revalidate!(tmp)
      File.rename(tmp, path)
      path
    end

    # Stream every record in the language lane, shard order then line
    # order. A malformed line raises FormatError naming shard:line.
    def each_record(language:)
      shard_paths(language).each do |path|
        File.foreach(path).with_index(1) do |line, lineno|
          yield parse_line(line, path, lineno)
        end
      end
      nil
    end

    # The lane's covered urns — the enricher's resume set and the
    # indexer's census, one pass over the shards.
    def urns(language:)
      set = Set.new
      each_record(language: language) { |record| set << record.urn }
      set
    end

    def shard_paths(language)
      Dir[File.join(language_dir(language), SHARD_GLOB)]
    end

    # The shelved language lanes (subdirectories holding at least one
    # shard), sorted — the indexer's iteration order.
    def languages
      return [] unless Dir.exist?(@dir)

      Dir.children(@dir).select do |child|
        File.directory?(File.join(@dir, child)) && !shard_paths(child).empty?
      end.sort
    end

    # The campaign checkpoint, or nil when no campaign has run.
    def state(language:)
      path = state_path(language)
      return nil unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError => e
      raise FormatError, "malformed campaign state #{path}: #{e.message}"
    end

    # Checkpoint the campaign (tmp + rename — a crash mid-write leaves the
    # prior checkpoint intact, never a torn one).
    def write_state!(language:, payload:)
      dir = language_dir(language)
      FileUtils.mkdir_p(dir)
      path = state_path(language)
      tmp = "#{path}.tmp"
      File.write(tmp, JSON.pretty_generate(payload))
      File.rename(tmp, path)
      path
    end

    # Parse one shard line into a Record (public: the local-lemmas
    # adapter's validation lane reads shards through this very method, so
    # gateway and discovery can never disagree on the format). A malformed
    # line raises FormatError naming shard:line.
    def parse_line(line, path, lineno)
      hash = JSON.parse(line)
      raise JSON::ParserError, "not a JSON object" unless hash.is_a?(Hash)

      Record.from_h(hash)
    rescue JSON::ParserError => e
      raise FormatError, "malformed lemma shard #{File.basename(path)}:#{lineno} (#{path}): #{e.message}"
    end

    private

    def state_path(language)
      File.join(language_dir(language), STATE_FILE)
    end

    def next_shard_number(dir)
      last = Dir[File.join(dir, SHARD_GLOB)].map { |p| p[/shard-(\d+)\.jsonl\z/, 1].to_i }.max || 0
      last + 1
    end

    def validate!(record, language)
      raise Error, "a lemma record needs a urn" if record.urn.to_s.strip.empty?
      if record.language != language
        raise Error, "record #{record.urn} claims language #{record.language.inspect} " \
                     "but the batch shelves #{language.inspect}"
      end
      raise Error, "record #{record.urn} carries no tokens — an empty model answer is not shelf material" \
        if !record.tokens.is_a?(Array) || record.tokens.empty?
      raise Error, "record #{record.urn} needs model provenance (model + model_version + package)" \
        if [record.model, record.model_version, record.package].any? { |v| v.to_s.strip.empty? }
      raise Error, "record #{record.urn} needs a source slug" if record.source.to_s.strip.empty?

      record.tokens.each do |token|
        next if token.is_a?(Array) && token.size == 3 && token.first.is_a?(String)

        raise Error, "record #{record.urn} has a malformed token #{token.inspect} — " \
                     "[surface, lemma, upos] triples only"
      end
    end

    # The staged shard must parse whole before it may claim a shard name.
    def revalidate!(tmp)
      File.foreach(tmp).with_index(1) { |line, lineno| parse_line(line, tmp, lineno) }
    rescue FormatError
      FileUtils.rm_f(tmp)
      raise
    end
  end
end
