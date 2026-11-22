# frozen_string_literal: true

# Nabu::CLI — `nabu note` (owner notes).
# A partial of lib/nabu/cli/query.rb, which loads it.
module Nabu
  class CLI < Thor
    desc "note URN|CODE [TEXT]", "Annotate any urn the corpus knows, or a language code (→ local-notes/)"
    long_desc <<~HELP, wrap: false
      The owner's annotation lane (architecture §16) — scholia of one's own,
      keyed by ANY urn the corpus knows: a document, a passage, a range, a
      dictionary entry. A bare LANGUAGE CODE (chu, zle-ort — no colon) is a
      target too (P85): `nabu note chu "…"` files a PRIVATE per-language note
      that the `nabu language chu` card composes beneath the published overlay
      (it stays local/, never published — the urn:nabu:lang:<code> layer).
      Notes are canonical memory: they live as YAML files
      under canonical/local-notes/<topic>.yml (append-only through the
      Nabu::NoteShelf gateway; hand-edits welcome — the file is the record),
      and the catalog only indexes them (urn_notes, rebuilt at every
      sync/rebuild). Once noted, the urn's renders carry the note: `show`
      prints an "owner note (topic, date): …" footer (a document also counts
      its passage-note children), `define` prints entry notes after the
      body, `links` shows an owner-notes lane, and the MCP surface serves
      notes by default (withheld wherever the target document is withheld).

      Modes:
        nabu note URN "TEXT"    scripted append (TEXT may be several words)
        nabu note URN           existing notes? show them; none? prompt for
                                one (TTY only — a pipe without TEXT refuses
                                honestly BEFORE any write)
        nabu note --list        enumerate notes (bounded --limit; --topic
                                narrows)

      The urn must RESOLVE in the catalog — a note on a typo'd urn would sit
      unreachable forever, so a miss is an error naming it. --force records
      a note on a not-yet-held urn deliberately (notes on planned material);
      such notes read "(dangling)" at render until the urn arrives.

      --topic groups notes however you like (default "#{Nabu::NoteShelf::DEFAULT_TOPIC}";
      one file per topic); --tags rides a comma-separated tag list.

      Examples:
        nabu note urn:nabu:ccmh:mar:mt "Collate against Jagić 1883 before citing."
        nabu note urn:nabu:dict:lsj:logos "Anchor for the John 1.1 witness comparison." --topic lexicon
        nabu note urn:nabu:planned:vaillant --force "Order the reprint." --tags acquisitions
        nabu note urn:nabu:ccmh:mar:mt         # read what you said
        nabu note --list --topic lexicon
    HELP
    option :topic, type: :string, banner: "NAME",
                   desc: "Topic file under canonical/local-notes/ (default #{Nabu::NoteShelf::DEFAULT_TOPIC}; " \
                         "with --list: narrow to this topic)"
    option :tags, type: :string, banner: "collation,ocs", desc: "Tags, comma-separated"
    option :force, type: :boolean, default: false,
                   desc: "Record a note on a not-yet-held urn (flagged dangling at render)"
    option :list, type: :boolean, default: false,
                  desc: "Enumerate notes (bounded; --topic narrows, --limit lifts)"
    option :rm, type: :string, banner: "ID",
                desc: "Remove one note by its id (nabu note --list shows ids)"
    option :limit, type: :numeric, default: Nabu::Query::Notes::DEFAULT_LIMIT,
                   desc: "With --list: how many notes (default #{Nabu::Query::Notes::DEFAULT_LIMIT})"
    def note(urn = nil, *text_parts)
      config = Nabu::Config.load
      return note_list(config, urn) if options[:list]
      return note_remove(config, urn) if options[:rm]

      target = urn.to_s.strip
      raise Thor::Error, "note: give a urn or a language code (or --list)" if target.empty?

      # P85-A: a bare language code (chu, zle-ort — no colon) targets the
      # private language-note layer via its canonical pseudo-URN; anything
      # colon-bearing stays an ordinary corpus-URN note.
      code = Nabu::LanguageNote.code_for(target)
      urn = code ? Nabu::LanguageNote.urn(code) : target

      text = text_parts.join(" ").strip
      text = show_notes_or_prompt(config, urn) if text.empty?
      return if text.nil? # existing notes were shown — a read, not a write

      append_note(config, urn, text)
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    end

    no_commands do
      # -- nabu note (P24-1) -------------------------------------------------

      # The `show`/`define` notes footer: one "owner note (topic, date): …"
      # line per note on the urn, and — on a document — the passage-note
      # children count. Zero-signal silence when unnoted (the linked-footer
      # stance); a catalog predating migration 015 has no lane at all.
      # Split note: also used by show and the lexicon commands; kept with its primary user.
      def print_notes_footer(catalog, result)
        reader = Nabu::Query::Notes.new(catalog: catalog)
        return unless reader.available?

        reader.for_urn(result.urn).each do |row|
          say "  owner note (#{row.topic}, #{row.added}): #{row.note}#{note_tags_fragment(row)}"
        end
        return unless result.is_a?(Nabu::Query::Show::DocumentResult)

        children = reader.child_count(result.urn)
        say "  passage notes: #{children}" if children.positive?
      end

      # Split note: also used by the links commands; kept with its primary user.
      def note_line(row)
        id = Nabu::NoteFile.record_id(topic: row.topic, urn: row.urn, added: row.added, note: row.note)
        "[#{id}] (#{row.topic}, #{row.added}) #{row.note}#{note_tags_fragment(row)}"
      end

      # Split note: also used by the reference commands; kept with its primary user.
      def note_tags_fragment(row)
        row.tags.empty? ? "" : "  [#{row.tags.join(', ')}]"
      end

      # `nabu note --list`: the bounded enumeration, oldest first, each urn
      # resolution-checked so a --force note on a not-yet-held urn reads
      # honestly dangling.
      # note --rm ID: one removal through the gateway, then the same
      # surgical derived refresh the append uses (file rewritten) or a
      # topic teardown (last note removed the file): rows + pin dropped.
      def note_remove(config, urn_arg)
        raise Thor::Error, "note: --rm takes no urn argument (--topic scopes the id search)" \
          unless urn_arg.to_s.strip.empty?

        shelf = Nabu::NoteShelf.new(dir: Nabu::NoteShelf.dir(config), resolver: nil)
        removal = shelf.remove_note!(id: options[:rm], topic: options[:topic])
        say "  removed  [#{options[:rm].strip.downcase}] #{removal.record.urn} — " \
            "#{removal.record.note[0, 60]}#{'…' if removal.record.note.length > 60}"
        if removal.file_deleted
          drop_note_topic(config, removal.topic, removal.path)
        else
          refresh_note_topic(config, removal.path)
        end
      end

      # The last note of a topic left the shelf: its derived rows and its
      # ledger pin go with the file (millisecond ops, the fast-path rule).
      def drop_note_topic(config, topic, path)
        catalog = open_catalog(config)
        begin
          catalog[:urn_notes].where(topic: topic).delete if catalog&.table_exists?(:urn_notes)
        ensure
          catalog&.disconnect
        end
        ledger = open_ledger(config)
        begin
          if ledger
            Nabu::Store::Pin.where(source_slug: Nabu::NoteShelf::SLUG,
                                   repo_url: "local:#{File.basename(path)}").delete
          end
        ensure
          ledger&.disconnect
        end
      end

      def note_list(config, urn_arg)
        raise Thor::Error, "note: --list takes no urn (--topic narrows, --limit lifts)" \
          unless urn_arg.to_s.strip.empty?

        catalog = open_catalog(config)
        raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

        page = Nabu::Query::Notes.new(catalog: catalog).list(topic: options[:topic], limit: options[:limit].to_i)
        return say(%(no notes yet — nabu note URN "TEXT" writes the first)) if page.total.zero?

        resolved = Nabu::NoteShelf.catalog_resolver(catalog)
        page.rows.each do |row|
          say "#{row.urn}#{' (dangling)' unless resolved.call(row.urn)} — #{note_line(row)}"
        end
        remaining = page.total - page.rows.size
        say "… and #{remaining} more (--limit lifts, --topic narrows)" if remaining.positive?
      ensure
        catalog&.disconnect
      end

      # `nabu note URN` without TEXT: existing notes are SHOWN (a read —
      # works piped or not); a bare urn with none prompts on a TTY and
      # refuses honestly otherwise, BEFORE any write (the ingest precedent).
      # Returns the text to append, or nil when notes were shown.
      def show_notes_or_prompt(config, urn)
        existing = existing_notes(config, urn)
        unless existing.empty?
          say "notes on #{urn} (#{existing.size}):"
          existing.each { |row| say "  #{note_line(row)}" }
          say %(add another: nabu note #{urn} "TEXT" · remove one: nabu note --rm ID)
          return nil
        end
        unless $stdin.tty?
          raise Thor::Error, "note: no TEXT and no TTY to prompt — pass the note as an argument " \
                             "(nabu note URN \"TEXT\"); nothing was written"
        end

        # Plain $stdin.gets, NOT Thor's ask: Thor routes ask through
        # LineEditor::Readline when the readline ext exists (CI's Ruby 3.3
        # bundles it; homebrew 4.0 dropped it), and Readline reads the real
        # fd — invisible to the suite's $stdin double and to piped input.
        # One prompt, one line; the say keeps the ingest prompt furniture.
        say "  note for #{urn} (type it, Enter saves, ^C aborts):"
        answer = $stdin.gets.to_s.strip
        raise Thor::Error, "note: refusing an empty note — nothing was written" if answer.empty?

        answer
      end

      def existing_notes(config, urn)
        catalog = open_catalog(config)
        return [] unless catalog

        Nabu::Query::Notes.new(catalog: catalog).for_urn(urn, topic: options[:topic])
      ensure
        catalog&.disconnect
      end

      # The note-resolution seam (P85-A): a language pseudo-URN resolves when
      # the library actually knows the code (a held corpus language OR a
      # curated/census-named one) — so a note on a typo'd code refuses like a
      # note on a typo'd corpus URN; everything else defers to the standard
      # corpus-URN resolver.
      def note_resolver(catalog)
        return nil unless catalog

        base = Nabu::NoteShelf.catalog_resolver(catalog)
        languages = Nabu::Languages.new(catalog: catalog)
        lambda do |urn|
          code = Nabu::LanguageNote.code_of(urn)
          code ? known_language?(catalog, languages, code) : base.call(urn)
        end
      end

      def known_language?(catalog, languages, code)
        return true if languages.name(code)

        catalog.table_exists?(:documents) && !catalog[:documents].where(language: code).empty?
      end

      # The write path: resolution-checked append through the NoteShelf
      # gateway, then a SURGICAL derived refresh — parse the one topic file,
      # replace its urn_notes rows, upsert its ledger pin. NEVER the shelf's
      # ordinary sync: that path runs LocalFetch discovery plus the corpus
      # indexer, minutes of machinery for a one-line append (owner defect
      # 2026-07-18: "notes supposed to be lightning fast"). The full sync/
      # rebuild replays the same rows from the same file — consistency is by
      # construction, speed is the feature.
      def append_note(config, urn, text)
        resolved = true
        catalog = open_catalog(config)
        begin
          resolver = note_resolver(catalog)
          resolved = resolver ? resolver.call(urn) : false if options[:force]
          shelf = Nabu::NoteShelf.new(dir: Nabu::NoteShelf.dir(config), resolver: resolver)
          path = shelf.append_note!(urn: urn, note: text,
                                    topic: options[:topic] || Nabu::NoteShelf::DEFAULT_TOPIC,
                                    tags: (options[:tags] || "").split(","), force: options[:force])
          say "  noted    #{urn} → #{path}"
        ensure
          catalog&.disconnect
        end
        refresh_note_topic(config, path)
        unless resolved
          say "  note: #{urn} is not in the catalog yet — it reads (dangling) until the urn arrives", :yellow
        end
        say "try: bin/nabu show #{urn}" if resolved
      end

      # The fast-append derived refresh (P26 hotfix): one topic file parsed,
      # its urn_notes rows replaced, its per-file ledger pin upserted — the
      # exact rows a full sync would produce for this file, in milliseconds.
      # Other topics' pins are untouched (the sync-time set-reconcile stays
      # the full pipeline's job). Absent db/ledger degrade honestly: the
      # note is canonical either way and the next sync/rebuild indexes it.
      def refresh_note_topic(config, path)
        note_file = Nabu::NoteFile.load(path)
        catalog = open_catalog(config)
        if catalog
          begin
            Nabu::Store::NoteLoader.replace_for_topic!(catalog, note_file)
          ensure
            catalog.disconnect
          end
        else
          say "  (no catalog yet — the note indexes at the next sync/rebuild)"
        end
        ledger = open_ledger(config)
        return unless ledger

        begin
          key = "local:#{File.basename(path)}"
          sha = Digest::SHA256.file(path).hexdigest
          row = Nabu::Store::Pin.first(source_slug: Nabu::NoteShelf::SLUG, repo_url: key)
          if row
            row.update(last_sync_sha: sha)
          else
            Nabu::Store::Pin.create(
              source_slug: Nabu::NoteShelf::SLUG, repo_url: key, last_sync_sha: sha
            )
          end
        ensure
          ledger.disconnect
        end
      end
    end
  end
end
