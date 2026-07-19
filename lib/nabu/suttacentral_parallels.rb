# frozen_string_literal: true

require "json"

module Nabu
  # Producer #7 for the links journal (P32-6): the SuttaCentral parallels
  # graph. sc-data's relationship/parallels.json — 8,221 curated relation
  # lists over SuttaCentral's own text-uid space (censused at commit
  # 8b3bcaf6, 2026-07-19: 5,646 "parallels" + 2,512 "mentions" + 63
  # "retells", 49,685 uid refs) — becomes kind=reference edges between
  # urn:nabu:suttacentral:<uid> document urns, so `nabu links` serves the
  # Kālāma Sutta ↔ MA 16 hop (and every other pli ↔ lzh pairing) natively.
  #
  # == The censused shape vocabulary (never invent — this is the whole of it)
  #
  # Each relation is a one-key object: {"parallels": [uids]}, {"mentions":
  # [uids]} or {"retells": [uids]} (upstream's loader also tolerates a
  # "remarks" key on an entry; none exist today — skipped by rule here).
  # A uid may carry a `~` prefix (resolved by inference — upstream renders
  # these "resembling") and a `#segment` suffix, including `#a-#b` ranges
  # ("ma1#t0421a12-#t0422a16" — Taishō line refs) and ONE `uid:segment`
  # colon variant (t765.132:10.0, censused twice corpus-wide). 1,132 refs
  # are free-text print citations ("Manusmṛti 6.77", "Bhikkhunī Parivāra
  # Pācittiya 49…" — 585 distinct): they name no stable id space (the
  # P19-4/P25-1 edge-worthiness rule), so they stay out of the journal and
  # are counted (+skipped_citations+) so the summary is honest.
  #
  # == Expansion follows upstream's own loader, verbatim
  #
  # suttacentral/suttacentral's arangoload.py (generate_relationship_edges)
  # is the semantics of record: a "parallels" list splits into full uids
  # and `~`partial uids — full×full pairs plus full×partial pairs, NEVER
  # partial×partial (two texts each resembling a third are not thereby
  # parallel); "mentions"/"retells" are a STAR from the FIRST uid (the
  # mentioned/retold text) to each later one. Edges are DOCUMENT-grain —
  # the uid before `#`/`:`, `~` stripped — because the relations are
  # document-grain upstream; the raw spellings (segments, ranges, `~`
  # flags) ride the detail verbatim: "parallels an7.68 ↔
  # ma1#t0421a12-#t0422a16". One journal row per unordered document pair;
  # a pair re-asserted from the other side keeps its first-seen detail,
  # and a pair carried by TWO kinds (55 parallels+mentions, 5
  # mentions+retells censused) merges both clauses into the one detail,
  # file order. Same-document pairs (segment cross-refs inside one text)
  # mint nothing and are counted (+skipped_self+).
  #
  # == Honesty: most endpoints are not in the catalog — minted anyway
  #
  # The graph names 33,667 distinct uid spellings across unpublished da*,
  # Taishō beyond the published subset, vinaya, sf* fragments… Censused
  # against the live catalog (2026-07-19): of 195,287 distinct
  # document-grain edges, 4,788 have both ends minted, 18,385 one end,
  # 172,114 neither. These ARE SuttaCentral's own stable id space (the
  # isicily tm: precedent, strengthened), so the urn:nabu form is minted
  # for every endpoint: the edges resolve the day upstream publishes, and
  # `nabu links` renders unminted counterparts "(not in catalog)" honestly.
  #
  # == Refresh mechanics (the standing producer contract)
  #
  # Edges are a pure function of (canonical graph file, code): SyncRunner
  # re-runs this producer after every suttacentral sync, superseding the
  # prior (producer, scope) run atomically. The graph file is fetched by
  # Adapters::Suttacentral#fetch (sha-pinned FileFetch, owner-fired with
  # the ordinary sync); a workdir WITHOUT the file — every parse-only sync
  # before the first graph fetch — is a no-op that supersedes NOTHING, so
  # standing edges survive. Rebuild never touches the journal; losing it
  # costs one re-run.
  class SuttacentralParallels
    PRODUCER = "suttacentral"
    KIND = "reference"
    CODE_VERSION = "suttacentral-parallels/1 nabu/#{VERSION}".freeze

    # Where Adapters::Suttacentral#fetch lands the graph, under the
    # source's canonical workdir (beside the bilara-data clone).
    DIRNAME = "parallels"
    FILENAME = "parallels.json"

    # The closed relation-kind set (class note). An unknown key is a LOUD
    # stop — a new upstream kind must be censused, never silently dropped.
    RELATION_KINDS = %w[parallels mentions retells].freeze
    IGNORED_KEYS = %w[remarks].freeze

    URN_PREFIX = "urn:nabu:suttacentral:"

    # What one refresh did — the LibraryReferences::Result shape (so the
    # CLI sync tail renders every producer identically) plus the two
    # honesty counters from the class note.
    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges,
                         :skipped_citations, :skipped_self)

    # +catalog+ rides the Adapter.reference_producer seam; the graph mints
    # edges for unminted uids too (class note), so only the journal is read
    # or written here.
    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive every parallels-graph edge from <workdir>/parallels/
    # parallels.json, superseding the prior (producer, scope) run. A
    # missing file is the honest no-op (class note).
    def run(slug, workdir: nil)
      path = workdir && File.join(workdir, DIRNAME, FILENAME)
      return absent_result(slug) unless path && File.file?(path)

      counts = Hash.new(0)
      edges = expand(parse_graph(path), counts)
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        write_edges(edges, run_id, counts)
      end
      Result.new(scope: slug, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 skipped_citations: counts[:citations], skipped_self: counts[:self])
    end

    private

    def absent_result(slug)
      Result.new(scope: slug, run_id: nil, edges_written: 0, edges_refreshed: 0,
                 superseded_runs: 0, superseded_edges: 0, skipped_citations: 0, skipped_self: 0)
    end

    def parse_graph(path)
      JSON.parse(File.read(path))
    rescue JSON::ParserError => e
      raise ParseError, "#{path}: malformed parallels graph: #{e.message}"
    end

    # { [from_doc, to_doc] sorted-pair key => { from:, to:, detail clauses } }
    # in file order — the in-memory dedup that keeps write counts honest.
    def expand(relations, counts)
      edges = {}
      relations.each do |relation|
        relation.each do |kind, uids|
          next if IGNORED_KEYS.include?(kind)
          unless RELATION_KINDS.include?(kind)
            raise ParseError, "parallels graph: unknown relation kind #{kind.inspect} — census it " \
                              "into SuttacentralParallels::RELATION_KINDS before parsing"
          end

          raw_pairs(kind, uids, counts).each { |from, to| record_pair(edges, kind, from, to, counts) }
        end
      end
      edges
    end

    # The upstream loader's expansion, verbatim (class note). Free-text
    # print citations — the space-carrying refs — never enter a pair.
    def raw_pairs(kind, uids, counts)
      ids = uids.grep(String).reject do |uid|
        uid.include?(" ").tap { |citation| counts[:citations] += 1 if citation }
      end
      if kind == "parallels"
        full, partial = ids.partition { |uid| !uid.start_with?("~") }
        full.combination(2).to_a + full.product(partial)
      else
        head, *rest = ids
        rest.map { |uid| [head, uid] }
      end
    end

    def record_pair(edges, kind, from, to, counts)
      from_doc = document_uid(from)
      to_doc = document_uid(to)
      return counts[:self] += 1 if from_doc == to_doc

      edge = edges[[from_doc, to_doc].sort] ||= { from: from_doc, to: to_doc, clauses: {} }
      edge[:clauses][kind] ||= "#{kind} #{from} ↔ #{to}"
    end

    # Document grain: `~` stripped, the uid before `#` (segment/range
    # suffixes) or `:` (the t765.132:10.0 colon variant, class note).
    def document_uid(uid)
      uid.delete_prefix("~").split("#", 2).first.split(":", 2).first
    end

    def write_edges(edges, run_id, counts)
      edges.each_value do |edge|
        outcome = Store::LinksJournal.write_edge!(
          @journal, from_urn: "#{URN_PREFIX}#{edge[:from]}", to_urn: "#{URN_PREFIX}#{edge[:to]}",
                    kind: KIND, score: nil, run_id: run_id, detail: edge[:clauses].values.join("; ")
        )
        counts[outcome == :inserted ? :inserted : :refreshed] += 1
      end
    end
  end
end
