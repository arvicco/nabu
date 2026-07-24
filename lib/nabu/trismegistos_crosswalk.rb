# frozen_string_literal: true

require "json"

module Nabu
  # Producer #8 for the links journal (P43-3): the Trismegistos TexRelations
  # crosswalk. The links graph already holds ~7,185 kind=reference edges
  # whose targets are bare `tm:<id>` external ids (minted by the
  # isicily/itant/tir/ceipom/vienna-wiki concordance extraction from each
  # record's own <idno>/related metadata) — DANGLING, because nothing
  # resolved a Trismegistos id. This producer makes them resolvable.
  #
  # The trismegistos feature module's fetch lands one JSON per swept tm id
  # under canonical/trismegistos/texrelations/<id>.json (the dataservices
  # texrelations response — an array of one-key objects: first
  # {"TM_ID":["<id>"]}, then one per partner project EDB/EDH/EDCS/EDR/ISic/
  # DDBDP/HGV/PHI/CPI/… 80+, value null / string / array). This producer
  # reads that canonical tree and mints TWO edge kinds, both kind=reference:
  #
  #   TYPE A — the crosswalk hub. For every NON-NULL partner value:
  #     tm:<id> → <partner target>, detail "Trismegistos concordance: <SCHEME>".
  #     A partner in HELD_SCHEMES targets its urn:nabu:<source> form (so the
  #     tm hub resolves straight to the held witness); any other partner
  #     targets a compact "<scheme>:<value>" external id that renders
  #     "(not in catalog)" honestly (the suttacentral-parallels precedent —
  #     the id space is real, the edge resolves the day we hold that side).
  #
  #   TYPE B — same-stone identity INSIDE the library. Trismegistos is the
  #     stable identity of one physical text; when we hold that stone under
  #     TWO sources (an isicily record that references tm:<id> AND the edh
  #     record its EDH partner names, say), the two witnesses are the same
  #     text. For each tm:<id> we assemble the set of HELD urns identified
  #     with it — {catalog urns that reference tm:<id> in the journal} ∪
  #     {HELD_SCHEMES partner urns that are catalog-resident} — and mint a
  #     clique of urn:nabu:<held> ↔ urn:nabu:<held> edges, detail
  #     "same text (Trismegistos <id>)". The catalog-residency guard is what
  #     keeps a partner-scheme urn builder honest: a mis-derived urn simply
  #     never matches, so it silently mints nothing rather than a false edge.
  #
  # == The held-scheme urn mapping (derived from each adapter's urn scheme)
  #
  # EDH  — edh's urn is urn:nabu:edh:hd<digits> (EdhEpidocParser::URN_PREFIX
  #        + the HD id downcased). NB Trismegistos spells its EDH value WITH
  #        the "HD" prefix ("HD007132"), whereas I.Sicily stores the digits
  #        bare and prepends "hd" itself — so here the value is only
  #        downcased: "HD007132" → urn:nabu:edh:hd007132. FIXTURE-VERIFIED
  #        (test/fixtures/trismegistos/texrelations/175903.json).
  # ISic — isicily's urn is urn:nabu:isicily:isic<digits> (downcased
  #        filename). Trismegistos's ISic value is the same ISic<digits>
  #        identifier, so "ISic000419" → urn:nabu:isicily:isic000419. NOT
  #        fixture-verified (neither staged response carries a non-null
  #        ISic) — derived from the known isicily urn scheme + the ISic id
  #        form, and made SAFE by the Type-B catalog guard (a wrong spelling
  #        mints nothing). Confirm at the owner's first real sync.
  #
  # DDBDP is DELIBERATELY ABSENT. papyri-ddbdp's urn keys off the ddb-hybrid
  # (urn:nabu:ddbdp:<hybrid>, ";"→":"), but Trismegistos's DDBDP value
  # format (a numeric TM-ddb id vs the hybrid) is unobservable offline —
  # both staged responses carry a null DDBDP — so building the urn would be
  # a guess. Wire it (add an entry here) once a first-sync response carries a
  # real DDBDP value and its shape is confirmed. Until then DDBDP still rides
  # a Type-A external edge (tm:<id> → ddbdp:<value>).
  #
  # == Refresh mechanics (the standing producer contract, suttacentral shape)
  #
  # Edges are a pure function of (canonical texrelations tree, catalog,
  # journal, code): SyncRunner re-runs this producer after every
  # trismegistos sync via Adapter.reference_producer, superseding the prior
  # (producer, scope) run atomically. A workdir WITHOUT the tree — every
  # parse-only sync before the first fetch — is a no-op that supersedes
  # NOTHING, so standing edges survive. Rebuild never touches the journal;
  # losing it costs one re-run. Derived-and-rebuildable: dropping links and
  # re-running re-derives identical edges (the rebuild-equivalence test).
  #
  # The isicily→tm: edges this producer reads are recorded under the
  # "isicily"/"itant"/… producers, so this producer's supersede! (scoped to
  # "trismegistos") never disturbs them. write_edge! keeps at most one edge
  # per unordered pair per kind globally, so a Type-B pair an adapter already
  # asserted directly (isicily's own urn:nabu:edh: concordance) is refreshed
  # in place, not duplicated.
  class TrismegistosCrosswalk
    PRODUCER = "trismegistos"
    KIND = "reference"
    CODE_VERSION = "trismegistos-crosswalk/1 nabu/#{VERSION}".freeze

    # Where Adapters::Trismegistos#fetch lands the responses, under the
    # source's canonical workdir.
    DIRNAME = "texrelations"

    # The key naming the TM id itself (skipped as a partner).
    TM_KEY = "TM_ID"

    # Partner scheme → urn:nabu builder for the sources we HOLD (class note).
    # Guarded by catalog residency at Type-B time, so an unverified builder
    # can only under-produce, never mint a false edge.
    HELD_SCHEMES = {
      "EDH" => ->(id) { "urn:nabu:edh:#{id.downcase}" },
      "ISic" => ->(id) { "urn:nabu:isicily:#{id.downcase}" }
    }.freeze

    # What one refresh did — the LibraryReferences::Result shape (so the CLI
    # sync tail renders every producer identically) plus the two honesty
    # counters: +external_edges+ (Type A) and +internal_edges+ (Type B), and
    # +files+ (texrelations responses read).
    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges,
                         :external_edges, :internal_edges, :files)

    # +catalog+ resolves partner urns to held witnesses; +journal+ is read
    # (which held urns reference each tm id) and written.
    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive every crosswalk edge from <workdir>/texrelations/*.json,
    # superseding the prior (producer, scope) run. A missing tree is the
    # honest no-op (class note).
    def run(slug, workdir: nil)
      dir = workdir && File.join(workdir, DIRNAME)
      files = dir && File.directory?(dir) ? Dir.glob(File.join(dir, "*.json")) : []
      return absent_result(slug) if files.empty?

      counts = Hash.new(0)
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        files.each { |path| write_file_edges(path, run_id, counts) }
      end
      Result.new(scope: slug, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 external_edges: counts[:external], internal_edges: counts[:internal],
                 files: files.size)
    end

    private

    def absent_result(slug)
      Result.new(scope: slug, run_id: nil, edges_written: 0, edges_refreshed: 0,
                 superseded_runs: 0, superseded_edges: 0,
                 external_edges: 0, internal_edges: 0, files: 0)
    end

    def write_file_edges(path, run_id, counts)
      tm_id, partners = parse_crosswalk(path)
      return if tm_id.nil?

      tm_urn = "tm:#{tm_id}"
      held_partner_urns = []
      partners.each do |scheme, values|
        builder = HELD_SCHEMES[scheme]
        values.each do |value|
          target = builder ? builder.call(value) : "#{compact_scheme(scheme)}:#{value}"
          write_edge(from: tm_urn, to: target, run_id: run_id, counts: counts, kind_counter: :external,
                     detail: "Trismegistos concordance: #{scheme}")
          held_partner_urns << target if builder && catalog_urn?(target)
        end
      end
      mint_internal_edges(tm_id, tm_urn, held_partner_urns, run_id, counts)
    end

    # TYPE B: the clique over {held urns that reference tm:<id>} ∪ {held
    # partner urns}, all catalog-resident (class note). Fewer than two held
    # witnesses → no same-stone assertion.
    def mint_internal_edges(tm_id, tm_urn, held_partner_urns, run_id, counts)
      held = (referencing_urns(tm_urn) + held_partner_urns).uniq
      return if held.size < 2

      detail = "same text (Trismegistos #{tm_id})"
      held.combination(2).each do |from, to|
        write_edge(from: from, to: to, run_id: run_id, counts: counts,
                   kind_counter: :internal, detail: detail)
      end
    end

    # Catalog-resident urns that carry a kind=reference edge to tm:<id> in
    # the journal (either direction — write_edge! stores one per unordered
    # pair). These are the held witnesses on "our side" of the crosswalk.
    def referencing_urns(tm_urn)
      links = @journal[:links]
      neighbors = links.where(to_urn: tm_urn, kind: KIND).select_map(:from_urn) +
                  links.where(from_urn: tm_urn, kind: KIND).select_map(:to_urn)
      neighbors.uniq.reject { |urn| urn == tm_urn }.select { |urn| catalog_urn?(urn) }
    end

    def write_edge(from:, to:, run_id:, counts:, kind_counter:, detail:)
      return if from == to

      outcome = Store::LinksJournal.write_edge!(@journal, from_urn: from, to_urn: to,
                                                          kind: KIND, score: nil, run_id: run_id, detail: detail)
      counts[outcome == :inserted ? :inserted : :refreshed] += 1
      counts[kind_counter] += 1
    end

    def catalog_urn?(urn)
      @catalog[:documents].where(urn: urn).any?
    end

    # The texrelations array → [tm_id, { scheme => [values] }]. Null/empty
    # partner values are dropped (only asserted crosswalk ids mint edges);
    # a string value becomes a one-element list, an array stays as given.
    def parse_crosswalk(path)
      entries = JSON.parse(File.read(path))
      unless entries.is_a?(Array)
        raise ParseError, "#{path}: TexRelations response must be a JSON array of one-key objects"
      end

      tm_id = nil
      partners = {}
      entries.each do |entry|
        next unless entry.is_a?(Hash) && entry.size == 1

        scheme, raw = entry.first
        if scheme == TM_KEY
          tm_id = Array(raw).first
          next
        end
        values = Array(raw).map(&:to_s).reject(&:empty?)
        partners[scheme] = values unless values.empty?
      end
      [tm_id, partners]
    rescue JSON::ParserError => e
      raise ParseError, "#{path}: malformed TexRelations response: #{e.message}"
    end

    # A compact, urn-safe scheme token for an external (non-held) partner:
    # downcased, non-alphanumerics folded out ("PATHs(CLM)" → "pathsclm",
    # "MAMA IX" → "mamaix"). The human scheme name rides the detail verbatim,
    # so nothing is lost.
    def compact_scheme(scheme)
      scheme.downcase.gsub(/[^a-z0-9]/, "")
    end
  end
end
