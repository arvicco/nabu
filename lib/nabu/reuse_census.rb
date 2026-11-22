# frozen_string_literal: true

require "digest"
require "json"
require "time"
require_relative "errors"
require_relative "reuse_pool"
require_relative "derivation_fingerprint"
require_relative "query/catalog_join"
require_relative "query/scope"
require_relative "query/grams"
require_relative "query/parallels_postings"
require_relative "store/cjk_bigrams"
require_relative "store/fts5_tokens"
require_relative "store/reuse_postings"
require_relative "store/source_content_identity"

module Nabu
  # The gram-postings CENSUS (`nabu reuse build SCOPE`; the reuse-batch
  # redesign, architecture §15): one scan over the corpus that records, for
  # every gram a SCOPE's anchors will probe, exactly the passages the FTS
  # phrase probe would return — the store Query::ParallelsPostings scores
  # from (Store::ReusePostings, its one write gateway).
  #
  # == Fold-both-sides, three emissions
  #
  # The FTS engine answers a gram with the UNION of two lanes, and the
  # census reproduces each from the catalog text the lanes were built from:
  #
  # 1. ANCHOR GRAMS (pass 1) — the scope's anchors gram'd by the engine's
  #    own code (Query::Grams via ParallelsPostings#anchor_keys: elision
  #    strip, Han char grain, shingles) and keyed as a phrase MATCH folds
  #    them. These are the WANTED keys; their folded tokens are the
  #    VOCABULARY pass 2 prunes by.
  # 2. MAIN-LANE EMULATION (pass 2) — every live passage's indexed token
  #    stream, read back from SQLite's own unicode61 tokenizer
  #    (Store::Fts5Tokens), windowed into gram_size-token keys. A phrase
  #    matches a passage iff its folded tokens occur consecutively in that
  #    stream, so a window IS a match.
  # 3. RUN WINDOWS (pass 2) — for passages of the CJK lane's sources
  #    (passages_cjk_scope), every gram_size-char window of a Han run
  #    (CjkBigrams::RUN — the lane's own mint grammar): a bigram phrase
  #    matches exactly a substring of one run.
  #
  # Pruning that stays exact: a window is emitted only when EVERY token is
  # in the vocabulary (a key equal to an anchor key consists of anchor
  # tokens), and a passage is skipped unread when it holds no character of
  # the vocabulary's scripts (folding never changes a character's script —
  # case and diacritic folds stay inside it). Finalize then keeps only the
  # wanted keys (Store::ReusePostings::Build#finalize_shard!).
  #
  # == Exactness, stated
  #
  # df counts distinct passages over BOTH lanes, as the FTS union does. Two
  # residues are named, not hidden: a gram token SQLite's tokenizer splits
  # (Ruby's newer Unicode tables call a character a letter that SQLite's do
  # not) cannot be emulated — such grams are COUNTED into the stamp
  # (counts.unkeyable_grams) — and the census reads the CATALOG, so a
  # fulltext left behind its catalog (a sync not yet indexed) differs from
  # it exactly as its own staleness says.
  #
  # == The stamp and staleness
  #
  # Every build stamps what it was built from (#identity, taken as the scan
  # starts, plus the build's own parameters and counts): the scope,
  # lang, gram size, the common-gram CAP (the D36-a cutoff at build), the
  # census code digest, the fulltext-index code identity
  # (DerivationFingerprint.index_core_digest — the tokenizer and lane mint
  # live there), the SQLite version (the tokenizer's tables), the CJK lane's
  # source set, and the universe's per-source content slice
  # ({slug => [live passages, max revision]}). #staleness compares each
  # with the live state and names every moved input; the postings engine
  # refuses a stale store.
  class ReuseCensus
    include Query::CatalogJoin
    include Query::Scope

    CODE_VERSION = "reuse-census/1"
    # The files whose code shapes the store's rows (the census digest).
    CODE_FILES = %w[
      reuse_census.rb store/reuse_postings.rb store/fts5_tokens.rb query/parallels_postings.rb
      query/parallels.rb query/grams.rb store/cjk_bigrams.rb
    ].freeze
    DEFAULT_SHARDS = 16
    # Passages per census task (pass 1 anchors; pass 2 universe rows).
    ANCHOR_BATCH = 2_000
    UNIVERSE_BATCH = 5_000

    # The scripts a vocabulary's characters can come from, for the pass-2
    # prefilter. A vocabulary holding a character outside every listed
    # script (or a Common/Inherited one) turns the prefilter OFF — never a
    # guess.
    PREFILTER_SCRIPTS = %w[
      Han Hiragana Katakana Hangul Latin Greek Cyrillic Armenian Georgian Hebrew Arabic Syriac Thaana
      Devanagari Bengali Gurmukhi Gujarati Oriya Tamil Telugu Kannada Malayalam Sinhala Tibetan Thai Lao
      Myanmar Khmer Mongolian Ethiopic Coptic Gothic Runic Ogham Cherokee Yi Javanese Balinese Tifinagh
      Glagolitic Old_Italic Brahmi Cuneiform Egyptian_Hieroglyphs Linear_B Ugaritic Avestan Samaritan
    ].to_h { |name| [name, /\p{#{name}}/] }.freeze

    # +manifest+ the installed build (nil for a measure run); +measurement+
    # the measure run's counts and projection (nil for a real build).
    Result = Data.define(:manifest, :seconds, :measurement)

    class << self
      def code_digest
        tokens = CODE_FILES.map do |rel|
          "#{rel}:#{Digest::SHA256.file(File.join(DerivationFingerprint::LIB_DIR, rel)).hexdigest}"
        end
        Digest::SHA256.hexdigest(([CODE_VERSION] + tokens).join("\n"))
      end

      # The pass-2 prefilter for +vocab+: a Regexp a passage must match to
      # be able to produce any vocabulary token, or nil (prefilter off).
      #
      # A decimal digit (script Common) joins as its LITERAL character: it
      # has no case and no composed forms, so no other raw character folds
      # to it (probed: unicode61 keeps fullwidth and superscript digits as
      # themselves). Any other character outside the listed scripts turns
      # the prefilter off.
      def prefilter(vocab)
        scripts = Set.new
        digits = Set.new
        vocab.each do |token|
          token.each_char do |char|
            next digits << char if char.match?(/\p{Nd}/)

            name, = PREFILTER_SCRIPTS.find { |_name, pattern| char.match?(pattern) }
            return nil if name.nil?

            scripts << name
          end
        end
        return nil if scripts.empty? && digits.empty?

        Regexp.union(scripts.sort.map { |name| PREFILTER_SCRIPTS.fetch(name) } +
                     (digits.empty? ? [] : [/[#{Regexp.escape(digits.sort.join)}]/]))
      end
    end

    def initialize(catalog:, fulltext:, root:)
      @catalog = catalog
      @fulltext = fulltext
      @root = root
    end

    # Build (or rebuild) the store for +scope+. +progress+ (nil-safe) is
    # called with (stage, done) after every task. Returns a Result.
    #
    # +measure+ (a passage count) is the BOUNDED timing run: the corpus pass
    # stops after that many universe passages (id order), every pass is
    # timed, and nothing is installed — the Result carries the counts,
    # per-pass seconds and a linear projection of the full corpus pass
    # instead of a manifest. Pass 1 (the scope) and finalize run whole.
    def run(scope, gram_size:, lang: nil, shards: DEFAULT_SHARDS, workers: 1, progress: nil, measure: nil)
      started = clock
      cutoff = Query::ParallelsPostings.cutoff(@catalog)
      lane = lane_slugs
      # Stamped from the state the scan STARTS on: a sync landing mid-build
      # then reads as staleness, never as a build that claims it.
      start_identity = identity(lane: lane)
      name = Store::ReusePostings.build_name(scope: scope, lang: lang, gram_size: gram_size)
      counts = { "pass_seconds" => {} }
      manifest = Store::ReusePostings.build!(root: @root, name: name, shards: shards) do |build|
        vocab = timed(counts, "anchors") do
          anchor_pass(build, scope, lang: lang, gram_size: gram_size, lane: lane, workers: workers,
                                    counts: counts, progress: progress)
        end
        timed(counts, "universe") do
          universe_pass(build, vocab, gram_size: gram_size, lane: lane, workers: workers, counts: counts,
                                      progress: progress, limit: measure)
        end
        timed(counts, "finalize") { finalize(build, cap: cutoff, workers: workers, counts: counts, progress: progress) }
        next build.discard! if measure

        build.stamp!(start_identity.merge(
                       "scope" => scope, "lang" => lang, "gram_size" => gram_size, "shards" => shards, "cap" => cutoff,
                       "built_at" => Time.now.utc.iso8601, "seconds" => (clock - started).round(1),
                       "workers" => workers, "counts" => counts
                     ))
      end
      Result.new(manifest: manifest, seconds: clock - started, measurement: measure && measurement(counts))
    end

    # What a build was made from, as of NOW (the stamp, and the live side
    # #staleness compares against).
    def identity(lane: lane_slugs)
      { "code" => self.class.code_digest, "index_core" => DerivationFingerprint.index_core_digest,
        "sqlite" => @catalog.get(Sequel.function(:sqlite_version)),
        "lane" => lane, "universe" => universe_slices }
    end

    # The moved inputs of +manifest+ against the live catalog/fulltext, as
    # human-readable reasons; empty = current. The universe comparison is
    # one grouped pass over the live passages (~a minute on the full
    # corpus) — the honest price of a content-grain staleness reading.
    def staleness(manifest)
      stamped = manifest.provenance
      live = identity
      reasons = []
      reasons << "census code changed since the build" if stamped["code"] != live["code"]
      reasons << "fulltext index code changed since the build" if stamped["index_core"] != live["index_core"]
      if stamped["sqlite"] != live["sqlite"]
        reasons << "SQLite #{stamped['sqlite']} → #{live['sqlite']} (tokenizer tables)"
      end
      reasons << "CJK lane sources changed" if stamped["lane"] != live["lane"]
      cutoff = Query::ParallelsPostings.cutoff(@catalog)
      reasons << "common-gram cutoff #{cutoff} now exceeds the build's cap #{manifest.cap}" if cutoff > manifest.cap
      moved = moved_sources(stamped["universe"] || {}, live["universe"])
      unless moved.empty?
        more = moved.size > 5 ? " +#{moved.size - 5}" : ""
        reasons << "#{moved.size} source(s) moved: #{moved.first(5).join(', ')}#{more}"
      end
      reasons
    end

    private

    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def timed(counts, pass)
      started = clock
      result = yield
      counts["pass_seconds"][pass] = (clock - started).round(2)
      result
    end

    # A measure run's reading: its counts plus the corpus pass projected
    # LINEARLY from the scanned share of the passage-id range (the catalog
    # high-water mark). Linear in id order is an approximation — sources
    # cluster by id, so a slice heavy or light in the vocabulary's script
    # skews it; the prefiltered share is reported beside it to judge.
    def measurement(counts)
      high_water = @catalog[:passages].max(:id).to_i
      scanned = counts.fetch("passages_scanned")
      seconds = counts.dig("pass_seconds", "universe")
      projected = scanned.positive? ? (seconds * high_water.fdiv(scanned)).round(1) : nil
      counts.merge("high_water" => high_water, "projected_universe_seconds" => projected)
    end

    # The CJK lane's indexed source set (what THIS fulltext's lane holds),
    # or nil when the fulltext carries no lane (the engine then never
    # probes it).
    def lane_slugs
      return nil unless @fulltext&.table_exists?(Store::Indexer::CJK_TABLE)
      return [] unless @fulltext.table_exists?(Store::Indexer::CJK_SCOPE_TABLE)

      @fulltext[Store::Indexer::CJK_SCOPE_TABLE].select_order_map(:slug)
    end

    def universe_slices
      Store::SourceContentIdentity.slices(@catalog, lang: nil, slugs: @catalog[:sources].select_order_map(:slug))
    end

    def moved_sources(stamped, live)
      (stamped.keys | live.keys).sort.reject { |slug| stamped[slug] == live[slug] }
    end

    # Keyset pages of +dataset+ by passage id (never the whole set in memory).
    def pages(dataset, batch)
      Enumerator.new do |yielder|
        last = 0
        loop do
          rows = dataset.where(Sequel[:passages][:id] > last).order(Sequel[:passages][:id]).limit(batch).all
          break if rows.empty?

          yielder << rows
          last = rows.last.fetch(:passage_id)
        end
      end
    end

    # Pass 1: the scope's wanted keys into per-worker files; returns the
    # vocabulary (every folded token of every wanted key).
    def anchor_pass(build, scope, lang:, gram_size:, lane:, workers:, counts:, progress:)
      anchors = scoped_passages(scope, lang: lang)
                .select(Sequel[:passages][:id].as(:passage_id), Sequel[:passages][:text_search].as(:text))
      tasks = pages(anchors, ANCHOR_BATCH).lazy.map { |rows| rows.map { |row| row.fetch(:text) } }
      pool = ReusePool.new(
        workers: workers,
        setup: ->(index) { [Query::ParallelsPostings.new(cutoff: 0, lane: !lane.nil?), build.wanted_writer(index)] },
        work: lambda { |(engine, writer), texts|
          keys, unkeyable = engine.anchor_keys(texts, gram_size: gram_size)
          keys.each { |text_keys| text_keys.each { |key| writer.add_wanted(key) } }
          [texts.size, keys.flatten.flat_map(&:split).uniq, unkeyable]
        },
        finish: lambda { |(engine, writer)|
          writer.close
          engine.close
          writer.rows
        }
      )
      vocab = Set.new
      anchors_done = unkeyable = 0
      finals = pool.map(tasks) do |done, tokens, missed|
        anchors_done += done
        unkeyable += missed
        vocab.merge(tokens)
        progress&.call(:anchors, anchors_done)
      end
      counts.merge!("anchors" => anchors_done, "wanted_rows" => finals.sum, "unkeyable_grams" => unkeyable,
                    "vocabulary" => vocab.size)
      vocab
    end

    # Pass 2: every live passage's main-lane windows (and the lane
    # sources' run windows) over the vocabulary, into per-worker files.
    def universe_pass(build, vocab, gram_size:, lane:, workers:, counts:, progress:, limit: nil)
      filter = self.class.prefilter(vocab)
      lane_sources = lane ? @catalog[:sources].where(slug: lane).select_map(:id).to_set : Set.new
      universe = Store::Indexer.live_passages(@catalog)
                               .select(Sequel[:passages][:id].as(:passage_id),
                                       Sequel[:passages][:text_search].as(:text),
                                       Sequel[:documents][:source_id])
      scanned = skipped = 0
      stream = pages(universe, limit ? [UNIVERSE_BATCH, limit].min : UNIVERSE_BATCH).lazy
      stream = stream.take_while { scanned < limit } if limit
      tasks = stream.filter_map do |rows|
        scanned += rows.size
        kept = rows.select { |row| filter.nil? || row.fetch(:text).to_s.match?(filter) }
        skipped += rows.size - kept.size
        kept.map { |row| [row.fetch(:passage_id), row.fetch(:text).to_s, lane_sources.include?(row[:source_id])] }
      end
      pool = ReusePool.new(
        workers: workers,
        setup: ->(index) { [Store::Fts5Tokens.new, build.raw_writer(index)] },
        work: ->((tokens, writer), rows) { emit_windows(tokens, writer, rows, vocab, gram_size) },
        finish: lambda { |(tokens, writer)|
          writer.close
          tokens.close
          writer.rows
        }
      )
      emitted = 0
      finals = pool.map(tasks) do |passages|
        emitted += passages
        progress&.call(:universe, emitted)
      end
      counts.merge!("passages_scanned" => scanned, "passages_prefiltered" => skipped,
                    "passages_windowed" => emitted, "raw_rows" => finals.sum,
                    "prefilter" => filter&.source)
    end

    # One task's windows: the main lane's indexed stream (SQLite's own
    # tokens) and, for lane passages, the runs' Han windows.
    def emit_windows(tokens, writer, rows, vocab, gram_size)
      streams = tokens.streams(rows.map { |row| row[1] })
      rows.each_with_index do |(passage_id, text, in_lane), i|
        windows(streams[i], vocab, gram_size) { |key| writer.add(key, passage_id, Store::ReusePostings::LANE_MAIN) }
        next unless in_lane

        text.scan(Store::CjkBigrams::RUN) do |run|
          chars = run.chars.map { |char| char.match?(Query::Grams::HAN_CHAR) ? char : nil }
          windows(chars, vocab, gram_size) { |key| writer.add(key, passage_id, Store::ReusePostings::LANE_CJK) }
        end
      end
      rows.size
    end

    # Yield every +size+-wide window of consecutive vocabulary tokens.
    def windows(stream, vocab, size)
      run = 0
      stream.each_with_index do |token, i|
        run = token && vocab.include?(token) ? run + 1 : 0
        yield stream[(i - size + 1)..i].join(" ") if run >= size
      end
    end

    def finalize(build, cap:, workers:, counts:, progress:)
      done = 0
      totals = Hash.new(0)
      pool = ReusePool.new(workers: [workers, build.shards].min, setup: ->(_index) {},
                           work: ->(_state, shard) { build.finalize_shard!(shard, cap: cap) })
      pool.map(0...build.shards) do |shard_counts|
        shard_counts.each { |key, value| totals[key] += value }
        done += 1
        progress&.call(:finalize, done)
      end
      counts.merge!(totals)
    end
  end
end
