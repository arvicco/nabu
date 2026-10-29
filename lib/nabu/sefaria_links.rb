# frozen_string_literal: true

require "csv"
require "json"

require_relative "store/links_journal_bulk"

module Nabu
  # The Sefaria LINKS layer (P150): Sefaria's own connection graph —
  # commentary, quotation, targum, midrash, mesorat hashas, ein mishpat …
  # edges between refs — as kind=reference edges in the links journal
  # between HELD passages. Producer for the links journal riding the
  # existing `sefaria` source (Adapters::Sefaria#fetch lands the shards;
  # this producer re-derives after every sefaria sync and every rebuild's
  # links stage through the reference-producer seam).
  #
  # == The upstream artifact (censused 2026-10-29, the 2026-10-02 index)
  #
  # The bucket's special files carry links/links0.csv … links16.csv
  # (17 shards, 680 MB, 5,069,488 rows) beside two AGGREGATE files —
  # links_by_book.csv / links_by_book_without_commentary.csv (book-pair
  # link COUNTS, not edges) — which are a rejected grain: never fetched,
  # never read. Shard columns: Citation 1, Citation 2, Conection Type
  # (upstream's spelling), Text 1, Text 2, Category 1, Category 2. The
  # 27 type strings (rows): commentary 2,268,385 · (empty) 2,052,074 ·
  # reference 381,154 · ein mishpat / ner mitsvah 118,802 · mesorat
  # hashas 45,848 · targum 34,727 · quotation 27,950 · ein mishpat
  # 21,553 · related 18,177 · related passage 16,347 · super_commentary
  # 15,382 · sifrei mitzvot 14,071 · quotation_auto_tanakh 12,596 ·
  # quotation_auto 11,557 · super commentary 9,504 · midrash 9,183 ·
  # essay 3,466 · mishnah in talmud 2,390 · parshanut 1,963 · none 1,928
  # · dibur_hamatchil 1,651 · allusion 751 · liturgy 13 · ellucidation 12
  # · explication 2 · law 1 · summary 1. Every type is taken; the string
  # rides the edge detail VERBATIM ("(untyped)" renders the empty one) —
  # no fold, no vocabulary, upstream's duplicates and typos included.
  #
  # == Scope: held ∩ held (the kitab-reuse join, censused)
  #
  # An edge needs BOTH endpoints held; a row with a side the library does
  # not hold is skipped and counted (+unknown_ids+, the sync tail's
  # "?N unknown upstream"), the per-side reasons and the top unheld titles
  # recorded on the run row's params — never guessed, never dropped
  # silently. Full-scale run against the live catalog (read-only, 1,970
  # sefaria documents / 675 titles + oshb's 39 books; 2026-10-29): of
  # 5,069,488 rows, 625,102 resolve on both sides (12.3%) → 622,476
  # edges (pairs asserted by several rows merge; 117 rows whose refs
  # land on one passage skip as self). Unresolved: 4,444,269 rows;
  # by side, 5,007,345 name a title not held and 153,472 a held title's
  # segment no held version carries — 49% of all 10.1M endpoints
  # resolve. The residue is upstream's breadth beyond the held shelves
  # (Talmud commentaries, Acharonim, responsa, the reference shelf —
  # 2.7M rows have exactly one held side), not a resolver gap. Edges
  # by type: (untyped) 265,395 · commentary 144,125 · ein mishpat / ner
  # mitsvah 88,222 · mesorat hashas 37,060 · targum 28,880 · related
  # passage 16,136 · related 12,191 · quotation_auto_tanakh 9,147 · ein
  # mishpat 8,877 · midrash 4,181 · quotation_auto 3,296 · mishnah in
  # talmud 2,388 · quotation 1,029 · reference 828 · sifrei mitzvot 671
  # · the rest < 30 (first clause's type per edge). One pass: ~75–110 s,
  # ~1.6 GB peak (the resolver tables + the pair table).
  #
  # == Ref → urn (the frozen sefaria minting, read backward)
  #
  # The adapter mints <doc-urn>:<citation>, citation = the node slugs and
  # the 1-based index path joined "." (daf.amud on the Bavli shelves —
  # Sefaria's own "25b:3" spelling). So a ref resolves as:
  #
  # 1. TITLE: the longest ", "-prefix of the row's Text column that is a
  #    held index title — Text carries the complex-title node path
  #    ("Tur, Orach Chayim", "Ruth Rabbah, Petichta"), the held title is
  #    the index title ("Tur", "Ruth Rabbah"); simple titles with commas
  #    ("Mishneh Torah, Virgin Maiden") match whole.
  # 2. CITATION: what follows the title — node names slugged (the frozen
  #    fold), the trailing address with ":" → "."; a RANGE anchors at its
  #    start ("Tamid 27a:2-3" → 27a.2; the verbatim ref rides the
  #    detail). A section-level ref ("Mishnah Tamid 1", "Zohar Chadash,
  #    Bereshit 1") lands on the first held passage under it, in reading
  #    order. A bare title is the hub document itself (document grain).
  # 3. VERSION: refs are version-free; urns are per version. Each title's
  #    held versions are ranked ONCE — original language before English,
  #    then the most open licence (open < attribution < nc), then urn —
  #    and a citation lands on the first version that holds it. One hub
  #    per citation, so every connection is one edge (never a version
  #    fan-out); declared coarseness: another version's passage shows no
  #    edge in `nabu links` (the ot alignment hub carries the
  #    version↔version join where it exists).
  # 4. TANAKH BASE TEXT: the 39 Tanakh book titles resolve to the held
  #    Masoretic witness, oshb (WLC) — Sefaria's Hebrew Tanakh is the
  #    Masoretic text in Masoretic versification, the oshb grid exactly
  #    (spot-checked: Gen 32:33, Deut 13:19, Joel 4:21, Mal 3:24, Ps
  #    51:21 all present). Sefaria's own Tanakh versions are not held.
  #
  # A citation the held versions lack (a partial translation, a trimmed
  # tail, a daf ref without its amud — "Shabbat 88") is a counted
  # "citation_not_held" side, never a nearest-neighbour guess.
  #
  # == Pairs
  #
  # One journal row per unordered urn pair (the journal's invariant),
  # first-seen direction kept (Citation 1 → Citation 2); a pair asserted
  # by several rows merges their distinct clauses ("<type>: <ref1> ↔
  # <ref2>"), file order, capped at MAX_CLAUSES with a "+n more" tail.
  # A row whose two refs land on the SAME passage mints nothing and is
  # counted (+skipped_self+). score is nil — a curated link, not a mined
  # similarity.
  #
  # == Licence
  #
  # Sefaria-Export's LICENSE.md speaks for texts only: "Each text is
  # licensed separately, so there is no overall license for this
  # repository. You can find the license for each text in their JSON
  # versions under the `license` field." The links/ files carry no
  # licence field or statement. Sefaria's developer guide states:
  # "Everything that you contribute to Sefaria (texts and data like
  # connections) is published with a Public License (Public Domain,
  # CC0, CC-BY, or CC BY-SA)" (developers.sefaria.org/docs/
  # guide-to-contributing). The layer is therefore treated as
  # ATTRIBUTION-class (the most restrictive licence that statement
  # names; credit Sefaria) — recorded on every run row.
  #
  # == Refresh mechanics (the standing producer contract)
  #
  # Edges are a pure function of (canonical shards, catalog, code):
  # superseded per (producer, scope) run; a workdir WITHOUT the shards —
  # every sync before the first links fetch — is a no-op that supersedes
  # nothing. Rebuild's links stage re-runs it with the other reference
  # producers (the slug-scoped reference lane — this pass adds ~2 min).
  class SefariaLinks
    PRODUCER = "sefaria-links"
    KIND = "reference"
    CODE_VERSION = "sefaria-links/1 nabu/#{VERSION}".freeze

    LINKS_DIRNAME = "links"
    # The edge shards; links_by_book*.csv (aggregate counts) never match.
    SHARD = /\Alinks\d+\.csv\z/

    SOURCE_SLUG = "sefaria"
    URN_PREFIX = "urn:nabu:sefaria:"
    LICENSE = "attribution (no licence on links/; Sefaria's contributor terms: PD/CC0/CC-BY/CC-BY-SA)"

    # Sefaria's Tanakh index titles → the held Masoretic witness (oshb).
    TANAKH_DOCUMENTS = {
      "Genesis" => "gen", "Exodus" => "exod", "Leviticus" => "lev", "Numbers" => "num",
      "Deuteronomy" => "deut", "Joshua" => "josh", "Judges" => "judg", "I Samuel" => "1sam",
      "II Samuel" => "2sam", "I Kings" => "1kgs", "II Kings" => "2kgs", "Isaiah" => "isa",
      "Jeremiah" => "jer", "Ezekiel" => "ezek", "Hosea" => "hos", "Joel" => "joel", "Amos" => "amos",
      "Obadiah" => "obad", "Jonah" => "jonah", "Micah" => "mic", "Nahum" => "nah", "Habakkuk" => "hab",
      "Zephaniah" => "zeph", "Haggai" => "hag", "Zechariah" => "zech", "Malachi" => "mal",
      "Psalms" => "ps", "Proverbs" => "prov", "Job" => "job", "Song of Songs" => "song", "Ruth" => "ruth",
      "Lamentations" => "lam", "Ecclesiastes" => "eccl", "Esther" => "esth", "Daniel" => "dan",
      "Ezra" => "ezra", "Nehemiah" => "neh", "I Chronicles" => "1chr", "II Chronicles" => "2chr"
    }.transform_values { |code| "urn:nabu:oshb:#{code}" }.freeze

    # const: a detail render cap (one pair's merged clauses), not a census
    MAX_CLAUSES = 4
    # const: how many unheld titles the run row names (the census is whole)
    TOP_UNHELD = 25
    WRITE_SLICE = 5_000
    LICENSE_RANK = { nil => 0, "open" => 0, "attribution" => 1 }.freeze

    COLUMNS = ["Citation 1", "Citation 2", "Conection Type", "Text 1", "Text 2", "Category 1", "Category 2"].freeze

    # The trailing address of a ref: "1:1", "25b:3", "1:1-6:1", "2a:3-5".
    ADDRESS = /(?:\A|\s)(\d+[ab]?(?::\d+[ab]?)*)(?:-[\dab:]+)?\z/

    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges,
                         :files, :rows_read, :unknown_ids, :skipped_self)

    # One held title: its ranked document urns and { citation => [doc
    # index, passage citation] } (section prefixes → the first passage).
    Title = Data.define(:documents, :citations)

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    def run(slug, workdir: nil)
      files = shard_files(workdir)
      return absent_result(slug) if files.empty?

      @titles = load_titles
      @title_cache = {}
      census = { rows: 0, resolved_rows: 0, unknown_rows: 0, skipped_self: 0,
                 sides: Hash.new(0), unheld: Hash.new(0) }
      pairs = collect_pairs(files, census)
      @titles = @title_cache = nil # the resolver tables are done — let the write phase reclaim them
      write(slug, files, pairs, census)
    end

    private

    def shard_files(workdir)
      return [] unless workdir

      dir = File.join(workdir, LINKS_DIRNAME)
      Dir.children(dir).grep(SHARD).sort_by { |name| name[/\d+/].to_i }.map { |name| File.join(dir, name) }
    rescue Errno::ENOENT
      []
    end

    def absent_result(slug)
      Result.new(scope: slug, run_id: nil, edges_written: 0, edges_refreshed: 0, superseded_runs: 0,
                 superseded_edges: 0, files: 0, rows_read: 0, unknown_ids: 0, skipped_self: 0)
    end

    # { [from, to] => clauses } in first-seen order and direction.
    # { "from\tto" => clause | [clauses] } in first-seen order and
    # direction (string keys and a bare String for the common one-clause
    # pair keep the full-scale table compact — ~625k pairs).
    def collect_pairs(files, census)
      pairs = {}
      files.each do |path|
        header = true
        CSV.foreach(path, encoding: "UTF-8") do |row|
          if header
            check_header!(path, row)
            header = false
            next
          end
          census[:rows] += 1
          collect_row(row, pairs, census)
        end
      end
      pairs
    end

    # The censused column layout; a reshaped export stops the run loudly
    # rather than resolving the wrong columns.
    def check_header!(path, row)
      return if row == COLUMNS

      raise Nabu::Error, "sefaria links: #{path}: unexpected columns #{row.inspect} (expected #{COLUMNS.inspect})"
    end

    def collect_row(row, pairs, census)
      ref1, ref2, type, text1, text2 = row
      from = resolve(ref1.to_s, text1.to_s, census)
      to = resolve(ref2.to_s, text2.to_s, census)
      if from.nil? || to.nil?
        census[:unknown_rows] += 1
        return
      end
      if from == to
        census[:skipped_self] += 1
        return
      end

      census[:resolved_rows] += 1
      merge_clause(pairs, from, to, "#{type_label(type)}: #{ref1} ↔ #{ref2}")
    end

    def merge_clause(pairs, from, to, clause)
      key = "#{from}\t#{to}"
      key = "#{to}\t#{from}" unless pairs.key?(key) || !pairs.key?("#{to}\t#{from}")
      case pairs[key]
      in nil then pairs[key] = clause
      in String => one then pairs[key] = [one, clause] unless one == clause
      in Array => many then many << clause unless many.include?(clause)
      end
    end

    def type_label(type) = type.to_s.empty? ? "(untyped)" : type

    # The held urn a ref names, or nil (the side's reason counted).
    def resolve(ref, text, census)
      title_name = title_for(text)
      if title_name.nil?
        census[:sides]["unheld_title"] += 1
        census[:unheld][text] += 1
        return nil
      end

      urn = locate(@titles.fetch(title_name), citation_for(ref, title_name))
      census[:sides]["citation_not_held"] += 1 if urn.nil?
      urn
    end

    # The longest ", "-prefix of +text+ that is a held title.
    def title_for(text)
      @title_cache.fetch(text) do
        parts = text.split(", ")
        candidates = parts.size.downto(1).lazy.map { |n| parts.first(n).join(", ") }
        @title_cache[text] = candidates.find { |name| @titles.key?(name) }
      end
    end

    # The adapter's citation for what follows the title, or nil when the
    # ref does not continue the title at a word boundary.
    def citation_for(ref, title_name)
      return nil unless ref.start_with?(title_name)

      rest = ref[title_name.size..]
      return nil unless rest.empty? || rest.start_with?(" ", ",")

      rest = rest.sub(/\A,/, "").strip
      match = rest.match(ADDRESS)
      nodes = match ? rest[0...match.begin(0)] : rest
      segments = nodes.split(", ").map { |node| Adapters::SefariaJsonParser.slug(node) }.reject(&:empty?)
      segments << match[1].tr(":", ".") if match
      segments.join(".")
    end

    def locate(title, citation)
      return nil if citation.nil?
      return title.documents.first if citation.empty?

      index, cited = title.citations[citation]
      index && "#{title.documents[index]}:#{cited}"
    end

    # -- the held side ------------------------------------------------------

    def load_titles
      titles = sefaria_titles
      TANAKH_DOCUMENTS.each do |name, urn|
        next if titles.key?(name)

        doc = @catalog[:documents].where(urn: urn, withdrawn: false).select(:id, :urn).first
        titles[name] = build_title([doc]) if doc
      end
      titles
    end

    def sefaria_titles
      rows = @catalog[:documents].join(:sources, id: :source_id)
                                 .where(Sequel[:sources][:slug] => SOURCE_SLUG,
                                        Sequel[:documents][:withdrawn] => false)
                                 .select(Sequel[:documents][:id], Sequel[:documents][:urn],
                                         Sequel[:documents][:language], Sequel[:documents][:license_override],
                                         Sequel[:documents][:metadata_json])
                                 .all
      rows.group_by { |row| JSON.parse(row[:metadata_json])["title"] }
          .reject { |name, _| name.nil? }
          .transform_values { |docs| build_title(docs.sort_by { |doc| rank(doc) }) }
    end

    def rank(doc)
      [doc[:language] == "eng" ? 1 : 0, LICENSE_RANK.fetch(doc[:license_override], 2), doc[:urn]]
    end

    # Exact citations first across every ranked version, then section
    # prefixes (each → the first passage under it, reading order).
    def build_title(docs)
      citations = {}
      passage_lists = docs.map do |doc|
        prefix = "#{doc[:urn]}:"
        @catalog[:passages].where(document_id: doc[:id]).order(:sequence)
                           .select_map(:urn).map { |urn| urn.delete_prefix(prefix).freeze }
      end
      add_exact(citations, passage_lists)
      add_prefixes(citations, passage_lists)
      Title.new(documents: docs.map { |doc| doc[:urn] }.freeze, citations: citations)
    end

    def add_exact(citations, passage_lists)
      passage_lists.each_with_index do |cited, index|
        cited.each { |citation| citations[citation] ||= [index, citation] }
      end
    end

    # Runs AFTER every version's exact citations, so a section-level
    # passage in one version is never shadowed by another's prefix.
    def add_prefixes(citations, passage_lists)
      passage_lists.each_with_index do |cited, index|
        cited.each do |citation|
          parts = citation.split(".")
          (1...parts.size).each { |n| citations[parts.first(n).join(".")] ||= [index, citation] }
        end
      end
    end

    # -- the journal ----------------------------------------------------------

    def write(slug, files, pairs, census)
      counts = { inserted: 0, refreshed: 0 }
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                           params: run_params(census), code_version: CODE_VERSION)
        pairs.each_slice(WRITE_SLICE) do |slice|
          edges = slice.map { |key, clauses| [*key.split("\t", 2), nil, detail(Array(clauses))] }
          Store::LinksJournal.write_edges!(@journal, edges, kind: KIND, run_id: run_id)
                             .each { |outcome, n| counts[outcome] += n }
        end
      end
      Result.new(scope: slug, run_id: run_id, edges_written: counts[:inserted],
                 edges_refreshed: counts[:refreshed], superseded_runs: superseded[0],
                 superseded_edges: superseded[1], files: files.size, rows_read: census[:rows],
                 unknown_ids: census[:unknown_rows], skipped_self: census[:skipped_self])
    end

    def detail(clauses)
      shown = clauses.first(MAX_CLAUSES).join("; ")
      clauses.size > MAX_CLAUSES ? "#{shown}; +#{clauses.size - MAX_CLAUSES} more" : shown
    end

    def run_params(census)
      { kind: KIND, license: LICENSE, rows: census[:rows], resolved_rows: census[:resolved_rows],
        unresolved_rows: census[:unknown_rows], skipped_self: census[:skipped_self],
        unresolved_sides: census[:sides].sort.to_h,
        top_unheld_titles: census[:unheld].sort_by { |name, n| [-n, name] }.first(TOP_UNHELD) }
    end
  end
end
