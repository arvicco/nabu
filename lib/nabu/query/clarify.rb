# frozen_string_literal: true

require_relative "../normalize"
require_relative "range"

module Nabu
  module Query
    # The reference normalizer (nabu_clarify): a partial, misspelled, or
    # half-remembered work-or-passage reference in, an honest reading of it
    # out — is the input a REFERENCE at all, which urn it names when it
    # parses UNIQUELY, what a deeper citation looks like there, and typed
    # CANDIDATES (document · source · lemma · place) for everything else.
    # Never a silent guess: an ambiguous reference (two editions sharing a
    # title, a citation two of them hold) resolves to nothing and lists
    # every reading; a fuzzy (misspelling-lane) match is only ever a
    # candidate.
    #
    # Desk doctrine: every read is a bounded probe of PRECOMPILED data —
    # urn input resolves through the catalog's unique urn indexes; names
    # resolve through the fulltext index's clarify lane (Store::Indexer
    # #rebuild_clarify! — a B-tree prefix lane, an FTS5 token lane, an
    # FTS5 trigram misspelling lane). An absent lane is an honest hint,
    # never a scan; urn resolution needs no lane and still answers.
    class Clarify
      # One typed candidate. +match+ says how the input reached it: exact
      # (whole folded name) · prefix (whole-name prefix) · token (every
      # input token, the last as a prefix) · fuzzy (trigram similarity — a
      # misspelling guess, said so). +is_primary+: the matched name is the
      # entry's primary title, not an alias. +ref_urn+: present when a
      # citation was given — the passage that citation names in this
      # document.
      Candidate = Data.define(:title, :key, :type, :is_primary, :source, :language, :license_class,
                              :detail, :match, :ref_urn) do
        def initialize(detail: nil, ref_urn: nil, **) = super
      end

      # What the resolved urn IS: passage · document · citation_prefix ·
      # range — with its document's identity and license fields.
      Ref = Data.define(:kind, :urn, :document_urn, :title, :language, :license_class, :source)

      # The citation shape one level deeper: the document's live passage
      # count, its first/last citation suffixes, their depth (dot/colon
      # segments), a first-passage example urn and a two-passage range
      # example; +citation+ is the resolved passage's own suffix (nil at
      # document grain). Citation fields are nil when the document's passage
      # urns do not extend its urn (no suffix grammar to teach).
      Structure = Data.define(:document_urn, :passages, :first_citation, :last_citation, :depth,
                              :example, :range_example, :citation)

      Result = Data.define(:query, :is_ref, :resolved_urn, :ref, :structure, :completions,
                           :index_present, :index_built_at, :note)

      # Never served unless include_restricted (the MCP never-leak stance).
      # const: the license model's private classes (Model::Validation)
      EXCLUDED = %w[research_private restricted].freeze

      # Candidate-pool bounds per lane (the page is cut to +limit+ after the
      # Ruby re-rank).
      # const: probe bounds, not corpus claims
      PREFIX_POOL = 60
      TOKEN_POOL = 200
      FUZZY_POOL = 400
      # The misspelling lane probes the input's rarest trigrams only (their
      # postings are short — the lane stays a probe, never a scan) and keeps
      # candidates at or above this edit-distance similarity (#similarity).
      # const: a matching heuristic, not a corpus claim
      FUZZY_TRIGRAMS = 6
      FUZZY_MIN_SIMILARITY = 0.6
      FUZZY_NAME_CAP = 80
      # A trailing token carrying a digit reads as a citation ("Iliad 1.1").
      CITATION = /\A(?<title>.+?)\s+(?<citation>[\p{L}\p{N}]*\p{N}[\p{L}\p{N}.:-]*)\z/
      # Document candidates probed for a title + citation reading.
      # const: a probe bound, not a corpus claim
      CITATION_PROBES = 10
      # Lane rank (lower = better) and type order for the re-rank.
      MATCH_RANK = { "exact" => 0, "prefix" => 1, "token" => 2, "fuzzy" => 3 }.freeze
      TYPE_RANK = { "document" => 0, "source" => 1, "place" => 2, "lemma" => 3 }.freeze
      HIGH = "\u{10FFFF}"
      # Candidates per page when the caller names no limit.
      # const: a render bound, not a corpus claim
      DEFAULT_LIMIT = 10

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      def run(input, limit: DEFAULT_LIMIT, include_restricted: false)
        text = Nabu::Normalize.nfc(input.to_s.strip)
        @include_restricted = include_restricted
        return urn_result(text, limit) if text.start_with?("urn:")

        name_result(text, limit)
      end

      private

      # -- urn input ------------------------------------------------------------

      def urn_result(text, limit)
        ref = passage_ref(text) || document_ref(text) || prefix_ref(text) || range_ref(text)
        if ref
          return result(text, is_ref: true, resolved_urn: ref.urn, ref: ref,
                              structure: structure(ref.document_urn, citation_of(ref)), completions: [])
        end

        completions = urn_completions(text, limit)
        note = if completions.empty?
                 "no held urn starts with #{text} — nabu_status shows what this corpus holds"
               else
                 "not a held urn — #{completions.size} document urn(s) extend it"
               end
        result(text, is_ref: false, completions: completions, note: note)
      end

      def passage_ref(urn)
        row = live_documents.join(:passages, document_id: Sequel[:documents][:id])
                            .where(Sequel[:passages][:urn] => urn, Sequel[:passages][:withdrawn] => false)
                            .select(*document_columns).first
        row && build_ref("passage", urn, row)
      end

      def document_ref(urn)
        row = live_documents.where(Sequel[:documents][:urn] => urn).select(*document_columns).first
        row && build_ref("document", urn, row)
      end

      # A ":"-bounded citation prefix with at least one child passage (the
      # nabu_show browsing grain): the longest held document urn heading
      # it, then one indexed range probe for a child.
      def prefix_ref(urn)
        head = urn.dup
        while (cut = head.rindex(":"))
          head = head[0...cut]
          row = live_documents.where(Sequel[:documents][:urn] => head).select(*document_columns).first
          next unless row

          child = %w[. : #].any? do |boundary|
            lower = "#{urn}#{boundary}"
            @catalog[:passages].where(document_id: row[:id], withdrawn: false)
                               .where(Sequel[:urn] >= lower).where(Sequel[:urn] < "#{lower}#{HIGH}").any?
          end
          return child ? build_ref("citation_prefix", urn, row) : nil
        end
        nil
      end

      def range_ref(urn)
        slice = Query::Range.new(catalog: @catalog).resolve(urn)
        return nil if slice.nil?

        row = live_documents.where(Sequel[:documents][:id] => slice.document_id).select(*document_columns).first
        row && build_ref("range", urn, row)
      rescue Query::Range::Error
        nil
      end

      def build_ref(kind, urn, row)
        Ref.new(kind: kind, urn: urn, document_urn: row[:urn], title: row[:title], language: row[:language],
                license_class: row[:license_class], source: row[:slug])
      end

      def citation_of(ref)
        return nil unless ref.kind == "passage"

        suffix(ref.urn, ref.document_urn)
      end

      # Document urns extending a partial urn — one B-tree range probe.
      def urn_completions(text, limit)
        rows = live_documents.where(Sequel[:documents][:urn] >= text)
                             .where(Sequel[:documents][:urn] < "#{text}#{HIGH}")
                             .order(Sequel[:documents][:urn])
        rows = rows.exclude(license_expr => EXCLUDED) unless @include_restricted
        rows.limit(limit).select(*document_columns).map do |row|
          Candidate.new(title: row[:title] || row[:urn], key: row[:urn], type: "document", is_primary: true,
                        source: row[:slug], language: row[:language], license_class: row[:license_class],
                        match: "prefix")
        end
      end

      # -- name input -------------------------------------------------------------

      def name_result(text, limit)
        unless lane?
          return result(text, is_ref: false, completions: [], index_present: false,
                              note: "the title index (the fulltext clarify lane) is not built on this " \
                                    "box — `rake index:clarify` derives it (minutes, catalog-only), and " \
                                    "every rebuild does; urn input still resolves without it")
        end

        split = text.match(CITATION)
        split ? citation_result(text, split, limit) : title_result(text, limit)
      end

      # The whole input as a name: an EXACT document title is a reference
      # (resolved only when one document bears it).
      def title_result(text, limit)
        completions = lookup(text, limit)
        exact_documents = completions.select { |c| c.match == "exact" && c.type == "document" }
        resolved = exact_documents.size == 1 ? exact_documents.first.key : nil
        ref = resolved && document_ref(resolved)
        result(text, is_ref: !exact_documents.empty?, resolved_urn: ref&.urn, ref: ref,
                     structure: ref && structure(ref.document_urn, nil), completions: completions,
                     note: name_note(completions, exact_documents.size))
      end

      # "Title citation": the title's EXACT document readings, each probed
      # for the citation (one indexed IN-list over passage urns); a unique
      # holder resolves, several are listed (ref_urn each), none falls back
      # to reading the WHOLE input as a name (a title may itself end in a
      # number).
      def citation_result(text, split, limit)
        documents = lookup(split[:title], CITATION_PROBES).select { |c| c.type == "document" && c.match == "exact" }
        wanted = documents.to_h { |c| ["#{c.key}:#{split[:citation]}", c] }
        held = wanted.empty? ? [] : @catalog[:passages].where(urn: wanted.keys, withdrawn: false).select_map(:urn)
        return title_result(text, limit) if held.empty?

        candidates = held.sort.map { |urn| wanted.fetch(urn).with(ref_urn: urn) }
        ref = held.size == 1 ? passage_ref(held.first) : nil
        result(text, is_ref: true, resolved_urn: ref&.urn, ref: ref,
                     structure: ref && structure(ref.document_urn, citation_of(ref)),
                     completions: candidates.first(limit),
                     note: if held.size == 1
                             "resolved uniquely"
                           else
                             "#{held.size} documents hold this citation — " \
                               "pick by ref_urn, never a silent guess"
                           end)
      end

      def name_note(completions, exact)
        return "no candidates — the name may be spelled differently or not held here" if completions.empty?
        return "#{exact} documents share this exact title — pick one, never a silent guess" if exact > 1

        "#{completions.size} candidate(s); match = exact · prefix · token · fuzzy (a misspelling guess)"
      end

      # The three lanes, merged per entry (its best match), license-gated,
      # re-ranked, bounded.
      def lookup(text, limit)
        folded = Nabu::Store::Indexer.clarify_fold(text)
        return [] if folded.empty?

        matches = {}
        prefix_lane(folded).each { |id, name, primary| note_match(matches, id, folded, name, primary) }
        token_lane(folded).each { |id| matches[id] ||= { match: "token", primary: nil } }
        fuzzy_lane(folded).each { |id, sim| matches[id] ||= { match: "fuzzy", primary: nil, sim: sim } } if
          matches.size < limit
        candidates(matches, folded).first(limit)
      end

      def note_match(matches, id, folded, name, primary)
        match = name == folded ? "exact" : "prefix"
        current = matches[id]
        better = current.nil? || ([MATCH_RANK[match], primary ? 0 : 1] <=>
                                  [MATCH_RANK[current[:match]], current[:primary] ? 0 : 1]).negative?
        matches[id] = { match: match, primary: primary } if better
      end

      def prefix_lane(folded)
        @fulltext[Nabu::Store::Indexer::CLARIFY_NAMES_TABLE]
          .where(Sequel[:folded] >= folded).where(Sequel[:folded] < "#{folded}#{HIGH}")
          .order(:folded).limit(PREFIX_POOL)
          .select_map(%i[entry_id folded is_primary])
          .map { |id, name, primary| [id, name, [true, 1].include?(primary)] }
      end

      # Every input token, the last as a prefix (≥ 2 chars — the prefix
      # index's floor), quoted for FTS5.
      def token_lane(folded)
        tokens = folded.scan(/[\p{L}\p{N}]+/)
        return [] if tokens.empty?

        terms = tokens.each_with_index.map do |token, i|
          quoted = %("#{token}")
          i == tokens.size - 1 && token.length >= 2 ? "#{quoted}*" : quoted
        end
        @fulltext[Nabu::Store::Indexer::CLARIFY_FTS_TABLE]
          .where(Sequel.lit("clarify_fts MATCH ?", terms.join(" ")))
          .limit(TOKEN_POOL).select_map(Sequel.lit("rowid"))
      end

      # The misspelling lane: the input's rarest held trigrams (vocab doc
      # counts), ORed, best-ranked first, then kept by trigram Jaccard
      # similarity against the entry's names.
      def fuzzy_lane(folded)
        grams = trigrams(folded)
        return [] if grams.empty?

        counts = @fulltext[Nabu::Store::Indexer::CLARIFY_VOCAB_TABLE].where(term: grams.to_a)
                                                                     .select_hash(:term, :doc)
        probe = counts.sort_by { |term, docs| [docs, term] }.first(FUZZY_TRIGRAMS).map(&:first)
        return [] if probe.empty?

        expression = probe.map { |term| %("#{term.gsub('"', '""')}") }.join(" OR ")
        ids = @fulltext[Nabu::Store::Indexer::CLARIFY_TRIGRAM_TABLE]
              .where(Sequel.lit("clarify_trigram MATCH ?", expression))
              .order(Sequel.lit("rank")).limit(FUZZY_POOL).select_map(Sequel.lit("rowid"))
        names = @fulltext[Nabu::Store::Indexer::CLARIFY_NAMES_TABLE].where(entry_id: ids)
                                                                    .select_hash_groups(:entry_id, :folded)
        ids.filter_map do |id|
          sim = names.fetch(id, []).map { |name| similarity(folded, name) }.max || 0
          [id, sim] if sim >= FUZZY_MIN_SIMILARITY
        end
      end

      def trigrams(text)
        (0..(text.length - 3)).to_set { |i| text[i, 3] }
      end

      # 1 − (edit distance / longer length): a doubled letter or one
      # transposition costs one unit, so "illiad" ~ "iliad" reads 0.83 —
      # what a misspelling IS, which trigram overlap underrates on short
      # titles. Names past FUZZY_NAME_CAP chars are compared on their head.
      def similarity(input, name)
        name = name[0, FUZZY_NAME_CAP]
        longer = [input.length, name.length].max
        longer.zero? ? 0 : 1 - levenshtein(input, name).fdiv(longer)
      end

      def levenshtein(left, right)
        previous = (0..right.length).to_a
        left.each_char.with_index(1) do |lchar, i|
          current = [i]
          right.each_char.with_index(1) do |rchar, j|
            current << [previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (lchar == rchar ? 0 : 1)].min
          end
          previous = current
        end
        previous.last
      end

      def candidates(matches, folded)
        return [] if matches.empty?

        rows = @fulltext[Nabu::Store::Indexer::CLARIFY_TABLE].where(id: matches.keys)
        # A NULL class (a gazetteer place whose module has no sources row)
        # is not a restricted one — NOT IN alone would drop it.
        unless @include_restricted
          rows = rows.where(Sequel.|({ license_class: nil },
                                     Sequel.~(license_class: EXCLUDED)))
        end
        primaries = primary_names(matches)
        ranked = rows.all.map do |row|
          match = matches.fetch(row[:id])
          [candidate(row, match, primaries[row[:id]], folded), match[:sim] || 0]
        end
        ranked.sort_by { |c, sim| rank(c, sim) }.map(&:first)
      end

      def primary_names(matches)
        @fulltext[Nabu::Store::Indexer::CLARIFY_NAMES_TABLE]
          .where(entry_id: matches.keys, is_primary: true).select_hash(:entry_id, :folded)
      end

      # Token and fuzzy matches decide is_primary from the PRIMARY name: the
      # input reached the title itself (every token present / the closer
      # trigram set) or only an alias.
      def candidate(row, match, primary_name, folded)
        primary = match[:primary]
        if primary.nil?
          primary = !primary_name.nil? && (match[:match] == "fuzzy" ||
                    folded.scan(/[\p{L}\p{N}]+/).all? { |token| primary_name.include?(token) })
        end
        Candidate.new(title: row[:name], key: row[:key], type: row[:type], is_primary: primary,
                      source: row[:source], language: row[:language], license_class: row[:license_class],
                      detail: row[:detail], match: match[:match])
      end

      # Lane first, then (fuzzy) similarity in 0.1 bands, then type (documents — the work being named — before
      # sources, places, headwords), primary over alias, closer trigram similarity (fuzzy), shorter title.
      def rank(candidate, sim)
        [MATCH_RANK.fetch(candidate.match), -sim.round(1), TYPE_RANK.fetch(candidate.type, 9),
         candidate.is_primary ? 0 : 1, -sim, candidate.title.length, candidate.key]
      end

      # -- structure ------------------------------------------------------------

      def structure(document_urn, citation)
        document_id = @catalog[:documents].where(urn: document_urn).get(:id)
        passages = @catalog[:passages].where(document_id: document_id, withdrawn: false)
        ordered = passages.order(:sequence).limit(2).select_map(:urn)
        last = passages.order(Sequel.desc(:sequence)).get(:urn)
        first_citation = ordered.first && suffix(ordered.first, document_urn)
        Structure.new(
          document_urn: document_urn, passages: passages.count,
          first_citation: first_citation, last_citation: last && suffix(last, document_urn),
          depth: first_citation&.split(/[.:]/)&.size,
          example: first_citation && ordered.first,
          range_example: range_example(ordered, document_urn), citation: citation
        )
      end

      def range_example(ordered, document_urn)
        first, second = ordered.map { |urn| suffix(urn, document_urn) }
        first && second ? "#{document_urn}:#{first}-#{second}" : nil
      end

      def suffix(urn, document_urn)
        prefix = "#{document_urn}:"
        urn.start_with?(prefix) ? urn.delete_prefix(prefix) : nil
      end

      # -- plumbing ---------------------------------------------------------------

      def lane?
        !@fulltext.nil? && @fulltext.table_exists?(Nabu::Store::Indexer::CLARIFY_TABLE)
      end

      def built_at
        return nil unless @fulltext&.table_exists?(Nabu::Store::Indexer::CLARIFY_META_TABLE)

        @fulltext[Nabu::Store::Indexer::CLARIFY_META_TABLE].get(:built_at)
      end

      def result(text, is_ref:, completions:, resolved_urn: nil, ref: nil, structure: nil, note: nil,
                 index_present: lane?)
        if ref && !@include_restricted && EXCLUDED.include?(ref.license_class)
          ref = nil
          resolved_urn = nil
          structure = nil
          note = "the reference names withheld material (research_private/restricted) — pass " \
                 "include_restricted only if the requester will honor the restriction"
        end
        Result.new(query: text, is_ref: is_ref, resolved_urn: resolved_urn, ref: ref, structure: structure,
                   completions: completions, index_present: index_present,
                   index_built_at: index_present ? built_at : nil, note: note)
      end

      def live_documents
        @catalog[:documents].join(:sources, id: Sequel[:documents][:source_id])
                            .where(Sequel[:documents][:withdrawn] => false)
      end

      def document_columns
        [Sequel[:documents][:id], Sequel[:documents][:urn], Sequel[:documents][:title],
         Sequel[:documents][:language], Sequel[:sources][:slug], license_expr.as(:license_class)]
      end

      def license_expr
        Sequel.function(:coalesce, Sequel[:documents][:license_override], Sequel[:sources][:license_class])
      end
    end
  end
end
