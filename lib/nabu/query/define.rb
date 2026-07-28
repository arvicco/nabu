# frozen_string_literal: true

require_relative "../normalize"
require_relative "reflex_views"

module Nabu
  module Query
    # Dictionary lookup (P11-4): `nabu define <lemma>` over the catalog's
    # dictionary shelf (architecture §11). Folded-headword equality with the
    # same both-sides contract as lemma search — the query folds through the
    # Normalize.query_forms union, the shelf stores
    # Normalize.search_form(headword, dictionary language) — so μηνις finds
    # μῆνις and λόγος (typed with its final sigma) finds the entry folded
    # λογοσ.
    #
    # == Citation resolution — query time, best effort
    #
    # Entry citations carry a work-level CTS prefix and a dot citation
    # (store shape); here each is resolved against whatever edition of that
    # WORK the catalog currently holds: documents matching
    # <cts_work>.<edition>, preferring the original-language edition over
    # translations (a lexicon cites the Greek, not Butler), then the passage
    # urn <document>:<citation> must actually exist. Resolution is at query
    # time deliberately — works sync after dictionaries and vice versa, and a
    # rebuild re-mints everything; nothing stale is ever stored. Unresolved
    # citations keep their display text and a nil resolved_urn: an honest
    # miss, never an invented link.
    #
    # == The reconstruction shelf (P14-1, architecture §12)
    #
    # A LEADING ASTERISK is the comparativist's convention: `define *bogъ`
    # strips it (upstream stores reconstruction headwords bare) and scopes
    # the lookup to the reconstruction shelves (dictionary language ends
    # "-pro"), and reconstruction headwords display WITH the asterisk put
    # back. Reconstruction entries also carry +reflexes+ — their descendant
    # edges as ReflexViews::View values, attestation counts resolved when a
    # +fulltext+ handle was given (nil counts are honest absences).
    #
    # Degradation: a catalog predating migration 006 (or none at all) simply
    # has no shelf — run returns [], the MCP layer words the state.
    class Define
      # One dictionary entry hit. +citations+ are CitationView values in
      # entry order; +license_class+/+license+ come from the owning source;
      # +reflexes+ (P14-1) are ReflexViews::View values, [] off the
      # reconstruction shelves. +via_lila+ (P44-8) is nil for a direct hit and
      # "<queried form> → <canonical form>" when the entry was reached only by
      # the LiLa variant-form fallback (folded into the displayed headword so
      # the provenance shows in `define` output — "via LiLa: eclypsans →
      # eclipsans").
      Result = Data.define(:urn, :dictionary_slug, :dictionary_title, :language,
                           :headword, :key_raw, :gloss, :body,
                           :license, :license_class, :source_slug, :citations, :reflexes,
                           :withdrawn, :via_lila) do
        def initialize(withdrawn: false, via_lila: nil, **) = super
      end

      # One citation of an entry: display label always; resolved_urn is the
      # in-catalog passage urn or nil.
      CitationView = Data.define(:label, :urn_raw, :resolved_urn)

      DEFAULT_LIMIT = 5

      # LiLa is a Latin-only lemma spine (P44-8): the fallback fires only for a
      # Latin-eligible query, and it folds/looks up in Latin.
      LILA_LANGUAGE = "lat"

      # P48-r1 (D48-a): the curated Sanskrit stem-class rule — nominative ↔
      # stem candidates for a Latin/IAST-scripted query. Candidates that
      # don't exist as headwords simply match nothing; that existence check
      # IS the disambiguation (tapaḥ → tapa AND tapas; MW's s-stem entry is
      # the one that answers). Non-Latin scripts generate nothing.
      # const: a citation-practice crosswalk, not a morphology engine —
      # the general form→lemma table is nabu-data material.
      SANSKRIT_IASTISH = /\A[a-zāīūṛṝḷḹṃḥśṣṭḍṇñṅ]+\z/i
      def self.sanskrit_stem_variants(term)
        word = Nabu::Normalize.nfc(term.to_s.strip).downcase
        return [] unless word.match?(SANSKRIT_IASTISH)

        out = []
        # nominative → stem
        out << word.delete_suffix("ḥ") << word.sub(/aḥ\z/, "as") if word.end_with?("aḥ")
        out << word.delete_suffix("ḥ") << word.sub(/iḥ\z/, "is") if word.end_with?("iḥ")
        out << word.delete_suffix("ḥ") << word.sub(/uḥ\z/, "us") if word.end_with?("uḥ")
        out << word.sub(/ā\z/, "an") if word.end_with?("ā")
        out << "#{word}n" if word.end_with?("ma") # karma → karman
        # stem → nominative
        out << "#{word}ḥ" if word.match?(/[aiu]\z/) && !word.end_with?("ā")
        out << word.sub(/as\z/, "aḥ") if word.end_with?("as")
        out << word.sub(/is\z/, "iḥ") if word.end_with?("is")
        out << word.sub(/us\z/, "uḥ") if word.end_with?("us")
        out << word.delete_suffix("n") << word.sub(/an\z/, "ā") if word.end_with?("an")
        (out - [word]).uniq
      end

      # +lila+ is the P44-8 LiLa lemma-spine resolver used for the Latin
      # variant-form fallback (below). It defaults to :auto — feature-detected
      # from canonical/lila at first use, so absent-tree behavior is
      # byte-identical to before — and tests inject a fixture resolver (or nil
      # to force the direct-only path).
      def initialize(catalog:, fulltext: nil, lila: :auto)
        @catalog = catalog
        @reflex_views = ReflexViews.new(catalog: catalog, fulltext: fulltext)
        @lila = lila
      end

      # Look up +lemma+; +lang+ filters by dictionary language (grc/lat/…);
      # a leading "*" scopes to the reconstruction shelves. Returns up to
      # +limit+ Results ordered (dictionary, entry_id).
      #
      # P44-8: a Latin-eligible MISS (no direct entry) retries through the LiLa
      # Lemma Bank — if the queried form is a known orthographic VARIANT of a
      # LiLa canonical form (eclypsans→eclipsans, praeliaris→proeliaris), the
      # canonical form is looked up instead, and its hits carry a via_lila
      # note. A miss that LiLa cannot map, or a canonical form still absent
      # from the shelf, stays an honest miss.
      def run(lemma, lang: nil, limit: DEFAULT_LIMIT)
        return [] unless shelf?

        term = lemma.to_s.strip
        recon_only = term.start_with?("*")
        bare = term.delete_prefix("*")
        variants = Nabu::Normalize.query_forms(bare)
        return [] if variants.first.strip.empty?

        # P48-r1 (D48-a, owner-ruled 2026-07-28): Sanskrit citation practice
        # splits the shelves — MW/DCS cite STEMS (bodhisattva, manas), the
        # Mahāvyutpatti cites NOMINATIVES (bodhisattvaḥ, manaḥ). Candidates
        # are generated per stem class and validated BY EXISTENCE (the
        # lookup only returns real entries), so tapaḥ proposes tapa AND
        # tapas without blanket visarga-stripping ever corrupting an
        # s-stem. The general form→lemma table (derived from DCS gold) is
        # nabu-data material, deliberately not built here.
        unless recon_only
          variants = (variants + self.class.sanskrit_stem_variants(bare)
                                     .flat_map { |v| Nabu::Normalize.query_forms(v) }).uniq
        end

        rows = entry_rows(variants, lang: lang, limit: limit, recon_only: recon_only)
        return rows.map { |row| build_result(row) } unless rows.empty?
        return [] if recon_only # the reconstruction shelves are not LiLa's domain

        lila_fallback(term, lang: lang, limit: limit)
      end

      # Batch short-gloss lookup for lemma-search integration (P11-4):
      # +pairs+ is an array of [lemma, language]; returns
      # { [lemma, language] => gloss } for every pair a dictionary of that
      # language glosses. One query per distinct language.
      # Resolve ONE entry by the minted urn `define` prints on every headline
      # (P22-2 — the owner's natural next move was `show <that urn>`, which
      # missed). Withdrawn entries resolve too, flagged: this is show's
      # hides-nothing contract, not define's live-shelf lookup.
      def by_urn(urn)
        row = @catalog[:dictionary_entries]
              .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
              .join(:sources, id: Sequel[:dictionaries][:source_id])
              .where(Sequel[:dictionary_entries][:urn] => urn)
              .select(*entry_columns, Sequel[:dictionary_entries][:withdrawn])
              .first
        row && build_result(row)
      end

      def glosses(pairs)
        return {} unless shelf?

        pairs.uniq.group_by(&:last).each_with_object({}) do |(language, group), out|
          folded = group.to_h { |lemma, _| [Nabu::Normalize.search_form(lemma, language: language), lemma] }
          gloss_rows(folded.keys, language).each do |row|
            lemma = folded[row.fetch(:headword_folded)]
            out[[lemma, language]] ||= row.fetch(:gloss)
          end
        end
      end

      private

      def shelf?
        @catalog.table_exists?(:dictionary_entries)
      end

      def entry_rows(variants, lang:, limit:, recon_only: false)
        dataset = @catalog[:dictionary_entries]
                  .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
                  .join(:sources, id: Sequel[:dictionaries][:source_id])
                  .where(Sequel[:dictionary_entries][:headword_folded] => variants,
                         Sequel[:dictionary_entries][:withdrawn] => false)
        dataset = dataset.where(Sequel.like(Sequel[:dictionaries][:language], "%-pro")) if recon_only
        dataset = dataset.where(Sequel[:dictionaries][:language] => Nabu::Languages.code_variants(lang)) if lang
        dataset = dataset.order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:entry_id])
        # limit: nil = every matching shelf (P34-r2 — the CLI fetches all and
        # caps at render so truncation can announce itself honestly).
        dataset = dataset.limit(limit) if limit
        dataset.select(*entry_columns).all
      end

      def entry_columns
        [
          Sequel[:dictionary_entries][:id].as(:entry_row_id),
          Sequel[:dictionary_entries][:urn], Sequel[:dictionary_entries][:entry_id],
          Sequel[:dictionary_entries][:key_raw], Sequel[:dictionary_entries][:headword],
          Sequel[:dictionary_entries][:gloss], Sequel[:dictionary_entries][:body],
          Sequel[:dictionaries][:slug].as(:dictionary_slug),
          Sequel[:dictionaries][:title].as(:dictionary_title),
          Sequel[:dictionaries][:language],
          Sequel[:sources][:license], Sequel[:sources][:license_class],
          Sequel[:sources][:slug].as(:source_slug)
        ]
      end

      def gloss_rows(folded_keys, language)
        @catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .where(Sequel[:dictionary_entries][:headword_folded] => folded_keys,
                 Sequel[:dictionary_entries][:withdrawn] => false,
                 Sequel[:dictionaries][:language] => language)
          .exclude(Sequel[:dictionary_entries][:gloss] => nil)
          .order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:entry_id])
          .select(Sequel[:dictionary_entries][:headword_folded], Sequel[:dictionary_entries][:gloss])
          .all
      end

      def build_result(row, via_lila: nil)
        recon = row.fetch(:language).end_with?("-pro")
        base_headword = recon ? "*#{row.fetch(:headword)}" : row.fetch(:headword)
        Result.new(
          urn: row.fetch(:urn), dictionary_slug: row.fetch(:dictionary_slug),
          dictionary_title: row.fetch(:dictionary_title), language: row.fetch(:language),
          # The via-LiLa provenance rides the displayed headword (the fenced
          # CLI/MCP renderers print it as-is), so `define eclypsans` reads
          # "via LiLa: eclypsans → eclipsans — A Latin Dictionary …".
          headword: via_lila ? "via LiLa: #{via_lila}" : base_headword,
          key_raw: row.fetch(:key_raw),
          gloss: row.fetch(:gloss), body: row.fetch(:body),
          license: row.fetch(:license), license_class: row.fetch(:license_class),
          source_slug: row.fetch(:source_slug),
          citations: resolve_citations(row.fetch(:entry_row_id)),
          reflexes: recon ? @reflex_views.for_entry(row.fetch(:entry_row_id)) : [],
          withdrawn: row[:withdrawn] ? true : false,
          via_lila: via_lila
        )
      end

      # -- the LiLa variant-form fallback (P44-8) ----------------------------------

      # A Latin-eligible miss retries through the LiLa Lemma Bank: map the
      # queried form via LiLa's variant→canonical mapping, then look the
      # CANONICAL form up (Latin shelves), annotating each hit "<term> →
      # <canonical>". No LiLa tree, a non-Latin --lang, an unmapped form, or a
      # canonical form still absent from the shelf all yield [] — an honest
      # miss, byte-identical to before when LiLa is absent.
      def lila_fallback(term, lang:, limit:)
        return [] unless lat_eligible?(lang)

        resolver = lila or return []
        canonicals = resolver.lookup(term).map(&:form).reject { |f| f.nil? || f.strip.empty? }
        # Dedupe by folded canonical, keeping the display spelling; skip a
        # canonical that folds back onto the term (LiLa knows the word but the
        # shelf simply lacks it — the honest miss).
        term_key = Nabu::Normalize.search_form(term, language: LILA_LANGUAGE)
        seen = {}
        canonicals.each do |canonical|
          key = Nabu::Normalize.search_form(canonical, language: LILA_LANGUAGE)
          next if key == term_key || seen.key?(key)

          seen[key] = canonical
        end

        results = seen.values.flat_map do |canonical|
          rows = entry_rows(Nabu::Normalize.query_forms(canonical),
                            lang: LILA_LANGUAGE, limit: limit, recon_only: false)
          rows.map { |row| build_result(row, via_lila: "#{term} → #{canonical}") }
        end
        limit ? results.first(limit) : results
      end

      # LiLa is Latin-only: fall back when the query is unconstrained (a bare
      # `define <form>` carries no language) or --lang names Latin.
      def lat_eligible?(lang)
        lang.nil? || Nabu::Languages.code_variants(lang.to_s).include?(LILA_LANGUAGE)
      end

      # Feature-detect + memoize the resolver (class note). :auto loads it from
      # canonical/lila; a genuine parse error surfaces, an absent tree is nil.
      def lila
        return @lila unless @lila == :auto

        @lila = Nabu::Lila.load_default
      end

      # -- resolution --------------------------------------------------------------

      def resolve_citations(entry_row_id)
        rows = @catalog[:dictionary_citations]
               .where(dictionary_entry_id: entry_row_id)
               .order(:seq)
               .select(:urn_raw, :cts_work, :citation, :label)
               .all
        editions = {}
        rows.map do |row|
          CitationView.new(label: row.fetch(:label), urn_raw: row.fetch(:urn_raw),
                           resolved_urn: resolve(row, editions))
        end
      end

      def resolve(row, editions)
        work = row.fetch(:cts_work)
        citation = row.fetch(:citation)
        return nil if work.nil?

        edition_urns = (editions[work] ||= editions_of(work))
        return nil if edition_urns.empty?
        # Document-grain honesty (P17-4): a held work cited WITHOUT a
        # passage citation resolves to the document itself when the work is
        # keyed by its own nabu document urn (MW → GRETIL; Mn./Pāṇ. cite at
        # document grain by design). CTS works keep the old nil — a bare
        # work reference there names an abstract work, not a show-able doc.
        return document_urn?(work) ? edition_urns.first : nil if citation.nil?

        candidates = candidate_forms(work, citation).flat_map do |form|
          edition_urns.map { |urn| "#{urn}:#{form}" }
        end
        existing = @catalog[:passages]
                   .where(urn: candidates, withdrawn: false)
                   .select_map(:urn).to_set
        found = candidates.find { |urn| existing.include?(urn) }
        return found if found

        # P34-4: a HELD document-urn work whose page probe missed still
        # resolves — to the document. TLS cites kanripo texts by
        # (juan, page) whose pagination only sometimes matches the held
        # edition's anchors; the text-grain claim stays honest when the
        # page does not. CTS works keep the old nil (an abstract work,
        # not a show-able doc).
        document_urn?(work) ? edition_urns.first : nil
      end

      # A cts_work that IS an in-catalog document urn (urn:nabu:… — the MW
      # → GRETIL shape) versus a CTS work prefix that documents extend with
      # an edition token.
      def document_urn?(work)
        work.start_with?("urn:nabu:")
      end

      # Candidate citation forms: document-urn works probe the exact
      # citation then the pada suffixes (P17-4 — GRETIL verse editions cite
      # quarter/half-verses: RV 5.086.05 lives as 5.086.05a/05c; a bounded
      # variant of the citation_forms fallback, tried in order so an exact
      # verse always wins). CTS works keep the classical chapter/section
      # fallback.
      def candidate_forms(work, citation)
        return citation_forms(citation) unless document_urn?(work)

        [citation, *%w[a b c d].map { |pada| "#{citation}#{pada}" }]
      end

      # The citation as cited, then — for 3+-part citations — the classical
      # chapter/section double-citation fallback: "Cic. Off. 1, 2, 4" is
      # book 1, chapter 2, CONTINUOUS section 4, and Perseus editions cite
      # book.section, so 1.2.4 falls back to 1.4 (first, last). Tried only
      # when the full form matches nothing, so a genuinely 3-level edition
      # always wins with the exact citation.
      def citation_forms(citation)
        parts = citation.split(".")
        return [citation] if parts.length < 3

        [citation, "#{parts.first}.#{parts.last}"]
      end

      # Live editions of +work+, original language first (translations are a
      # last resort — a lexicon cites the source text), then urn order for
      # determinism. A document-urn work (P17-4) has exactly itself as its
      # edition when the document is live.
      def editions_of(work)
        return @catalog[:documents].where(urn: work, withdrawn: false).select_map(:urn) if document_urn?(work)

        @catalog[:documents]
          .where(Sequel.like(:urn, "#{work.gsub(/[%_]/) { |ch| "\\#{ch}" }}.%"))
          .where(withdrawn: false)
          .select_map(%i[urn language])
          .sort_by { |urn, language| [language == "eng" ? 1 : 0, urn] }
          .map(&:first)
      end
    end
  end
end
