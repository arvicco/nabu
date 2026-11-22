# frozen_string_literal: true

# Nabu::Store::Indexer — the clarify lane (nabu_clarify's precompiled backing).
# A partial of lib/nabu/store/indexer.rb, which loads it.
module Nabu
  module Store
    module Indexer
      module_function

      # == The clarify lane (nabu_clarify's precompiled backing) =============
      #
      # The reference normalizer answers "what did the caller MEAN" from
      # names alone: every live document title, every source, every
      # dictionary headword, every gazetteer place — one typed ENTRY each
      # (type document|source|lemma|place, its key: urn / slug / entry urn /
      # namespaced place ref) with its NAMES, the primary plus aliases
      # (a source's slug, a headword's raw key, a place's gazetteer name
      # keys), folded ONE way both sides (#clarify_fold). Three read lanes,
      # each a bounded probe, never a scan:
      #   - clarify_names: a B-tree over the folded names — exact and
      #     whole-name PREFIX completion by range (`folded >= q < q+max`);
      #   - clarify_fts: FTS5 unicode61 (prefix-indexed) over the folded
      #     name + aliases (+ the document urn's tokens) — token completion;
      #   - clarify_trigram: FTS5 trigram over the folded names — the
      #     misspelling lane, probed on the input's RAREST trigrams (sized
      #     through the clarify_trigram_vocab fts5vocab view).
      # Restricted entries are stored WITH their effective license class;
      # the reader gates them (the MCP never-leak stance lives there).
      #
      # Lifecycle: the reference rebuild derives it whole (stage "clarify");
      # refresh_source! re-derives one source's slice when the lane exists
      # (a pre-lane index is left alone — the lane is NOT an incremental
      # prerequisite, so a sync never bootstraps a corpus-wide build);
      # reconcile_stages! and `rake index:clarify` re-derive it standalone.
      CLARIFY_TABLE = :clarify_entries
      CLARIFY_NAMES_TABLE = :clarify_names
      CLARIFY_FTS_TABLE = :clarify_fts
      CLARIFY_TRIGRAM_TABLE = :clarify_trigram
      CLARIFY_VOCAB_TABLE = :clarify_trigram_vocab
      CLARIFY_META_TABLE = :clarify_meta

      # Gazetteer namespace → the registry slug that derives it (the place
      # entries' source; a refresh of that slug re-derives its places).
      CLARIFY_GAZETTEER_SOURCES = { "pleiades" => "pleiades", "tm" => "trismegistos-geo",
                                    "cigs" => "cigs" }.freeze

      # const: a write-batch size (statement bound), not a corpus claim
      CLARIFY_BATCH = 5_000

      CLARIFY_FTS_SQL = <<~SQL
        CREATE VIRTUAL TABLE clarify_fts USING fts5(
          name, aliases,
          content = '', contentless_delete = 1,
          tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3'
        )
      SQL
      CLARIFY_TRIGRAM_SQL = <<~SQL
        CREATE VIRTUAL TABLE clarify_trigram USING fts5(
          names, content = '', contentless_delete = 1, tokenize = 'trigram'
        )
      SQL
      CLARIFY_VOCAB_SQL = "CREATE VIRTUAL TABLE clarify_trigram_vocab USING fts5vocab(clarify_trigram, 'row')"

      # The one name fold both sides share: NFC → downcase → mark strip
      # (Normalize's generic fold) → final sigma → the Latin ligatures æ/œ
      # expanded to the digraphs a typist writes (the Vulgate's "Matthæus"
      # answers "Matthaeus"; letters, not marks, so the mark strip leaves
      # them) → collapsed whitespace. A change here re-folds the stored
      # names: bump STAGE_VERSIONS["clarify"] with it.
      def clarify_fold(text)
        Normalize.fold_diacritics(Normalize.nfc(text.to_s).downcase).tr("ς", "σ")
                 .gsub(/[æœ]/, CLARIFY_LIGATURES).gsub(/\s+/, " ").strip
      end
      CLARIFY_LIGATURES = { "æ" => "ae", "œ" => "oe" }.freeze

      # Derive the whole lane from +catalog+ (drop + recreate). +stamp+
      # advances the "clarify" stage stamp (the standalone/rake path; the
      # reference rebuild stamps every stage itself). Returns {entries:}.
      def rebuild_clarify!(catalog:, fulltext:, stamp: false)
        drop_clarify!(fulltext)
        create_clarify_tables(fulltext)
        count = 0
        fulltext.transaction do
          count += write_clarify_entries(fulltext, clarify_source_rows(catalog))
          count += write_clarify_entries(fulltext, clarify_place_rows(catalog))
          count += write_clarify_entries(fulltext, clarify_document_rows(catalog))
          count += write_clarify_entries(fulltext, clarify_lemma_rows(catalog))
          write_clarify_meta(fulltext)
        end
        stamp_stages!(fulltext, versions: { "clarify" => STAGE_VERSIONS.fetch("clarify") }) if stamp
        { entries: count }
      end

      # Re-derive ONE source's slice (sync time): its source row, its live
      # documents, its dictionary headwords, and — for a gazetteer slug —
      # its places. A fulltext without the lane is left alone (no
      # bootstrap). Returns the slice's entry count, or nil when skipped.
      def refresh_clarify_source!(catalog:, fulltext:, slug:)
        return nil unless fulltext.table_exists?(CLARIFY_TABLE)

        fulltext.transaction do
          ids = fulltext[CLARIFY_TABLE].where(source: slug).select_map(:id)
          delete_clarify_entries(fulltext, ids)
          source_id = catalog[:sources].where(slug: slug).get(:id)
          count = write_clarify_entries(fulltext, clarify_source_rows(catalog, slug: slug))
          count += write_clarify_entries(fulltext, clarify_place_rows(catalog, slug: slug))
          if source_id
            count += write_clarify_entries(fulltext, clarify_document_rows(catalog, source_id: source_id))
            count += write_clarify_entries(fulltext, clarify_lemma_rows(catalog, source_id: source_id))
          end
          write_clarify_meta(fulltext)
          count
        end
      end

      def drop_clarify!(fulltext)
        [CLARIFY_VOCAB_TABLE, CLARIFY_FTS_TABLE, CLARIFY_TRIGRAM_TABLE, CLARIFY_NAMES_TABLE,
         CLARIFY_TABLE, CLARIFY_META_TABLE].each { |table| fulltext.drop_table?(table) }
      end

      def create_clarify_tables(fulltext)
        fulltext.create_table(CLARIFY_TABLE) do
          primary_key :id
          String :type, null: false
          String :key, null: false
          String :name, null: false
          String :source
          String :language
          String :license_class
          String :detail
          index :source
        end
        fulltext.create_table(CLARIFY_NAMES_TABLE) do
          Integer :entry_id, null: false
          String :folded, null: false
          TrueClass :is_primary, null: false
          index :folded
          index :entry_id
        end
        fulltext.run(CLARIFY_FTS_SQL)
        fulltext.run(CLARIFY_TRIGRAM_SQL)
        fulltext.run(CLARIFY_VOCAB_SQL)
        fulltext.create_table(CLARIFY_META_TABLE) do
          String :built_at, null: false
          Integer :entries, null: false
        end
      end

      # Write entry hashes ({type:, key:, name:, source:, language:,
      # license_class:, detail:, aliases: [], urn_tokens:}) in batches with
      # explicit ids, so the names and both FTS lanes key on the same rowid.
      def write_clarify_entries(fulltext, rows)
        next_id = (fulltext[CLARIFY_TABLE].max(:id) || 0) + 1
        count = 0
        rows.each_slice(CLARIFY_BATCH) do |slice|
          entries = []
          names = []
          fts = []
          trigram = []
          slice.each do |row|
            id = next_id
            next_id += 1
            entries << row.slice(:type, :key, :name, :source, :language, :license_class, :detail).merge(id: id)
            primary = row[:primary] ? clarify_fold(row[:name]) : nil
            aliases = row.fetch(:aliases, []).map { |name| clarify_fold(name) }.reject(&:empty?).uniq - [primary]
            names << { entry_id: id, folded: primary, is_primary: true } if primary && !primary.empty?
            aliases.each { |folded| names << { entry_id: id, folded: folded, is_primary: false } }
            fts << { rowid: id, name: primary.to_s, aliases: [*aliases, row[:urn_tokens]].compact.join(" | ") }
            trigram_text = [primary, *aliases].compact.join(" | ")
            # Headwords stay OUT of the misspelling lane: the dictionary
            # desks fold their own lookups, and three million short
            # headwords would crowd every work title out of the probe.
            trigram << { rowid: id, names: trigram_text } unless trigram_text.empty? || row[:type] == "lemma"
          end
          fulltext[CLARIFY_TABLE].multi_insert(entries)
          fulltext[CLARIFY_NAMES_TABLE].multi_insert(names)
          fulltext[CLARIFY_FTS_TABLE].multi_insert(fts)
          fulltext[CLARIFY_TRIGRAM_TABLE].multi_insert(trigram) unless trigram.empty?
          count += slice.size
        end
        count
      end

      def delete_clarify_entries(fulltext, ids)
        ids.each_slice(CLARIFY_BATCH) do |slice|
          fulltext[CLARIFY_NAMES_TABLE].where(entry_id: slice).delete
          fulltext[CLARIFY_FTS_TABLE].where(rowid: slice).delete
          fulltext[CLARIFY_TRIGRAM_TABLE].where(rowid: slice).delete
          fulltext[CLARIFY_TABLE].where(id: slice).delete
        end
      end

      def write_clarify_meta(fulltext)
        fulltext[CLARIFY_META_TABLE].delete
        fulltext[CLARIFY_META_TABLE].insert(built_at: Time.now.utc.iso8601,
                                            entries: fulltext[CLARIFY_TABLE].count)
      end

      # -- the four entry producers (lazy enumerators over the catalog) -------

      def clarify_source_rows(catalog, slug: nil)
        scope = catalog[:sources]
        scope = scope.where(slug: slug) if slug
        scope.order(:slug).select(:slug, :name, :license_class).map do |row|
          { type: "source", key: row[:slug], name: row[:name] || row[:slug], source: row[:slug],
            license_class: row[:license_class], primary: true, aliases: [row[:slug]] }
        end
      end

      def clarify_place_rows(catalog, slug: nil)
        return [] unless catalog.table_exists?(:place_index)

        gazetteers = CLARIFY_GAZETTEER_SOURCES.select { |_gazetteer, source| slug.nil? || source == slug }
        places = catalog[:place_index]
        places = places.where(gazetteer: gazetteers.keys) if slug
        return [] if slug && gazetteers.empty?

        classes = catalog[:sources].select_hash(:slug, :license_class)
        names = catalog[:place_index_names].where(gazetteer: places.select(:gazetteer).distinct)
                                           .select_hash_groups(%i[gazetteer place_id], :name_key)
        places.order(:gazetteer, :position).select(:gazetteer, :place_id, :title).lazy.map do |row|
          source = CLARIFY_GAZETTEER_SOURCES.fetch(row[:gazetteer], row[:gazetteer])
          { type: "place", key: "#{row[:gazetteer]}:#{row[:place_id]}",
            name: row[:title] || "#{row[:gazetteer]}:#{row[:place_id]}", source: source,
            license_class: classes[source], detail: row[:gazetteer], primary: !row[:title].nil?,
            aliases: names.fetch([row[:gazetteer], row[:place_id]], []) }
        end
      end

      def clarify_document_rows(catalog, source_id: nil)
        scope = catalog[:documents].join(:sources, id: Sequel[:documents][:source_id])
                                   .where(Sequel[:documents][:withdrawn] => false)
        scope = scope.where(Sequel[:documents][:source_id] => source_id) if source_id
        scope.order(Sequel[:documents][:id])
             .select(Sequel[:documents][:urn], Sequel[:documents][:title], Sequel[:documents][:language],
                     Sequel[:sources][:slug],
                     Sequel.function(:coalesce, Sequel[:documents][:license_override],
                                     Sequel[:sources][:license_class]).as(:license_class))
             .lazy.map do |row|
               { type: "document", key: row[:urn], name: row[:title] || row[:urn], source: row[:slug],
                 language: row[:language], license_class: row[:license_class], primary: !row[:title].nil?,
                 urn_tokens: row[:urn] }
             end
      end

      def clarify_lemma_rows(catalog, source_id: nil)
        return [] unless catalog.table_exists?(:dictionary_entries)

        scope = catalog[:dictionary_entries]
                .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
                .join(:sources, id: Sequel[:dictionaries][:source_id])
                .where(Sequel[:dictionary_entries][:withdrawn] => false)
        scope = scope.where(Sequel[:dictionaries][:source_id] => source_id) if source_id
        scope.order(Sequel[:dictionary_entries][:id])
             .select(Sequel[:dictionary_entries][:urn], Sequel[:dictionary_entries][:headword],
                     Sequel[:dictionary_entries][:key_raw], Sequel[:dictionaries][:language],
                     Sequel[:dictionaries][:title].as(:dictionary_title), Sequel[:sources][:slug],
                     Sequel[:sources][:license_class])
             .lazy.map do |row|
               { type: "lemma", key: row[:urn], name: row[:headword], source: row[:slug],
                 language: row[:language], license_class: row[:license_class],
                 detail: row[:dictionary_title], primary: true, aliases: [row[:key_raw]].compact }
             end
      end
    end
  end
end
