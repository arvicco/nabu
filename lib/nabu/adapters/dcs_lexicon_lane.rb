# frozen_string_literal: true

module Nabu
  module Adapters
    # The DCS lookup lane: the held DCS tree's `dcs/data/conllu/lookup/`
    # directory (inside the sparse cone, same CC BY 4.0 grant — citation:
    # Oliver Hellwig, The Digital Corpus of Sanskrit (DCS), 2010–2024)
    # carries the corpus's own reference tables beside chapter-info.xml,
    # which stays the primary adapter's gold gate. They ride the secondary
    # dictionary lane (Adapter.dictionary_lane, the oracc pilot's seam) as
    # TWO shelves — entry ids collide across the files, so one slug each:
    #
    # - "dcs-lexicon" ← dictionary.csv (TAB, header
    #   `id word grammar preverbs meanings`): the DCS lemma lexicon, keyed
    #   by the same LemmaId the gold tokens carry. headword = word (IAST),
    #   gloss = meanings verbatim ("; "-separated; empty stays nil — ~16k
    #   rows carry none and are still entries), body = headword (grammar),
    #   preverbs, meanings. Rows with an EMPTY word (176 upstream, 19 of
    #   them empty apart from the id) cannot mint a headword and are
    #   skipped by rule, censused. A duplicate id raises ParseError — none
    #   exists upstream, so one would mean the file changed shape.
    # - "dcs-senses" ← word-senses.csv: the WordNet-2.1-shaped sense bank.
    #   Header quirk: the header names FIVE columns
    #   (`id word wordnet21id wordnetSupersenseId wordnetSupersenseName`)
    #   but every row carries SIX — id, sense name, gloss, wn21 id,
    #   supersense id, supersense name, `_` = empty — so rows parse by
    #   observed reality. headword = the sense name (English), gloss = the
    #   gloss text, the WordNet fields into the body when present.
    #   Language: san — the tls-concepts precedent (an English-labelled
    #   concept net shelves under its members' object language).
    #
    # == Crossrefs (both onto the dcs-senses entries)
    #
    # - sembank-relations.csv (TAB, NO header, `from to "code"`): sense →
    #   sense edges as id-keyed DictionaryCrossrefs on the from-entry
    #   (to_dictionary dcs-senses, target_id = to-id; the tls concept-net
    #   precedent). kind = the upstream symbol verbatim; the label names
    #   the WordNet 2.1 pointer where the data confirms it (POINTER_NAMES)
    #   and falls back to the bare symbol otherwise. Census at the held
    #   tree (2026-10-17): 194,529 lines; 17 symbols — the WN 2.1 ones plus
    #   DCS's own short spellings "i" (general → named instance, woman →
    #   Draupadī: WN's ~i instance hyponym) and "m" (the exact inverse of
    #   "#m" on 11,846 of 11,847 pairs: member meronym); "\" is left
    #   unnamed (WN reads it as pertainym on adjectives but "derived from
    #   adjective" on adverbs, and the rows carry no part of speech). Five
    #   junk codes (77D15 ×7, 010DE, 010BE, 0108E, 0012D) and edges whose
    #   from-sense is not held are skipped and censused; exact duplicate
    #   lines (a few hundred, antonym pairs mostly) collapse to one row.
    #   Edges to unheld senses still mint a row — it renders unresolved.
    # - sembank-attestations.xml: per concept, the Sanskrit lemmas that
    #   lexicalize it, with per-text counts — one crossref per
    #   lexicalization FROM the sense TO dcs-lexicon (kind
    #   "lexicalization", target_id = LemmaId, target = the IAST form,
    #   label = "<IAST> (<N> attestations)", N the per-text counts summed).
    #   The file is NOT well-formed XML (only the last <concept> is ever
    #   closed, and notes carry bare "<" — "<> dualism", "As<sub>4</sub>"),
    #   so no XML parser can read it honestly; it is streamed line by line
    #   (14 MB, never slurped — the >5 MB rule's intent) over its rigid
    #   one-element-per-line shape. A lexicalization line off that shape
    #   raises ParseError rather than dropping silently.
    #
    # == Broken records
    #
    # Two upstream records carry a newline INSIDE a field: dictionary.csv
    # 39892 ("aiḍavi\na" — 2 fields, then a 4-field continuation) and
    # word-senses.csv 127090 (bāhyadruti's two numbered glosses — 3 + 4).
    # Physical lines are rejoined (with the newline) while the record has
    # fewer fields than the row shape; an exact fit is the repaired record
    # (censused :rejoined), an overshoot or an unterminated fragment at EOF
    # raises ParseError. The verbatim field keeps its newline in key_raw /
    # the body; the display headword and gloss space it.
    #
    # Both shelves inherit dcs's license and credit through the source
    # join; nothing new is declared.
    class DcsLexiconLane < Nabu::Adapter
      # Dcs::LANGUAGE (dcs.rb requires this file before Dcs is defined, so
      # the value is spelled here and the test pins the agreement).
      LANGUAGE = "san"

      LEXICON_SLUG = "dcs-lexicon"
      SENSES_SLUG = "dcs-senses"

      FILES = { LEXICON_SLUG => "dictionary.csv", SENSES_SLUG => "word-senses.csv" }.freeze
      TITLES = {
        LEXICON_SLUG => "DCS lexicon — the Digital Corpus of Sanskrit's lemma list (meanings)",
        SENSES_SLUG => "DCS senses — the Digital Corpus of Sanskrit's WordNet-shaped sense bank"
      }.freeze
      RELATIONS_FILE = "sembank-relations.csv"
      ATTESTATIONS_FILE = "sembank-attestations.xml"

      LEXICON_HEADER = %w[id word grammar preverbs meanings].freeze
      LEXICON_FIELDS = 5
      SENSE_FIELDS = 6
      EMPTY = "_"

      # The WordNet 2.1 pointer names, per symbol, where the data confirms
      # the reading (class note); a symbol absent here labels as itself.
      POINTER_NAMES = {
        "!" => "antonym", "@" => "hypernym", "~" => "hyponym",
        "i" => "instance hyponym",
        "#m" => "member holonym", "#s" => "substance holonym", "#p" => "part holonym",
        "m" => "member meronym", "%m" => "member meronym", "%s" => "substance meronym", "%p" => "part meronym",
        "=" => "attribute", "&" => "similar to", "^" => "also see", "$" => "verb group",
        "*" => "entailment", ">" => "cause", "<" => "participle of verb"
      }.freeze
      # Every symbol the relations file legitimately carries; anything else
      # (77D15, 010DE, …) is junk, skipped and censused.
      POINTER_CODES = (POINTER_NAMES.keys + ["\\"]).freeze

      CONCEPT_LINE = /\A<concept id="(\d+)"/
      LEXICALIZATION_LINE = /\A\s*<lexicalization lemma="(\d+)" id="([^"]+)">\s*\z/
      COUNT_LINE = %r{\A\s*<n text="[^"]*">\s*(\d+)</n>\s*\z}

      # Per-dictionary skip/repair counts from the latest parse of each
      # shelf ({ "dcs-lexicon" => { rejoined: 1, headwordless: 176 }, … }).
      def census
        @census ||= {}
      end

      # One ref per dictionary whose main file is present (the sidecars of
      # dcs-senses are read beside word-senses.csv at parse). id = the
      # dictionary slug — stable, identical for an attic copy.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        FILES.filter_map do |slug, file|
          path = File.join(workdir, Dcs::DATA_DIR, "lookup", file)
          next unless File.file?(path) && !File.empty?(path)

          Nabu::DocumentRef.new(source_id: Dcs::MANIFEST.id, id: slug, path: File.expand_path(path),
                                metadata: { "dictionary" => slug })
        end.each(&block)
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        document = Nabu::DictionaryDocument.new(slug: slug, language: LANGUAGE, title: TITLES.fetch(slug),
                                                canonical_path: document_ref.path)
        counts = census[slug] = Hash.new(0)
        if slug == LEXICON_SLUG
          parse_lexicon(document_ref.path, document, counts)
        else
          parse_senses(document_ref.path, document, counts)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "dcs lookup #{document_ref.id}: #{e.message}"
      end

      private

      # -- dcs-lexicon --------------------------------------------------------

      def parse_lexicon(path, document, counts)
        seen = Set.new
        each_record(path, LEXICON_FIELDS, counts, header: LEXICON_HEADER) do |id, word, grammar, preverbs, meanings|
          raise Nabu::ParseError, "dcs lookup dictionary.csv: duplicate lemma id #{id.inspect}" unless seen.add?(id)
          next counts[:headwordless] += 1 if word.strip.empty?

          document << lexicon_entry(id, word, grammar, preverbs, meanings)
        end
      end

      def lexicon_entry(id, word, grammar, preverbs, meanings)
        headword = display(word)
        gloss = meanings.strip.empty? ? nil : display(meanings)
        headline = grammar.strip.empty? ? headword : "#{headword} (#{grammar.strip})"
        lines = [headline]
        lines << "preverbs: #{preverbs.strip}" unless preverbs.strip.empty?
        lines << meanings unless gloss.nil?
        entry(id: id, key_raw: word, headword: headword, gloss: gloss, body: lines.join("\n"))
      end

      # -- dcs-senses ----------------------------------------------------------

      def parse_senses(path, document, counts)
        rows = []
        each_record(path, SENSE_FIELDS, counts) { |fields| rows << fields }
        names = rows.to_h { |id, name, *| [id, display(name)] }
        relations = read_relations(File.join(File.dirname(path), RELATIONS_FILE), names, counts)
        lexicalizations = read_attestations(File.join(File.dirname(path), ATTESTATIONS_FILE), names, counts)
        rows.each do |id, name, gloss, wn21, supersense_id, supersense|
          crossrefs = relations.fetch(id, []) + lexicalizations.fetch(id, [])
          document << sense_entry(id, name, gloss, [wn21, supersense_id, supersense].map { |v| value(v) }, crossrefs)
        end
      end

      def sense_entry(id, name, gloss, wordnet, crossrefs)
        headword = display(name)
        gloss_text = value(gloss)
        wn21, supersense_id, supersense = wordnet
        lines = [[headword, gloss_text].compact.join(" — ")]
        lines << "WordNet 2.1: #{wn21}" if wn21
        lines << "supersense: #{[supersense, supersense_id && "(#{supersense_id})"].compact.join(' ')}" if supersense
        entry(id: id, key_raw: name, headword: headword, gloss: gloss_text && display(gloss_text),
              body: lines.join("\n"), crossrefs: crossrefs)
      end

      # { from-id => [DictionaryCrossref] } in file order; an absent file
      # (an attic-only word-senses.csv) yields none.
      def read_relations(path, names, counts)
        return {} unless File.file?(path)

        seen = Set.new
        File.foreach(path, chomp: true, encoding: Encoding::UTF_8).each_with_object({}) do |line, out|
          next if line.strip.empty?

          from, to, code = relation_fields(line)
          next counts[:junk_codes] += 1 unless POINTER_CODES.include?(code)
          next counts[:unheld_from] += 1 unless names.key?(from)
          next counts[:duplicate_edges] += 1 unless seen.add?([from, to, code])

          counts[:relations] += 1
          (out[from] ||= []) << relation_crossref(to, code, names)
        end
      end

      def relation_fields(line)
        from, to, quoted, *rest = line.split("\t", -1)
        unless rest.empty? && from&.match?(/\A\d+\z/) && to&.match?(/\A\d+\z/) && quoted&.match?(/\A".+"\z/)
          raise Nabu::ParseError, "dcs lookup #{RELATIONS_FILE}: unexpected row #{line.inspect}"
        end

        [from, to, quoted[1..-2]]
      end

      def relation_crossref(to, code, names)
        target = names.fetch(to, to)
        Nabu::DictionaryCrossref.new(kind: code, label: "#{POINTER_NAMES.fetch(code, code)} #{target}",
                                     target: target, target_id: to, to_dictionary: SENSES_SLUG)
      end

      # { concept-id => [DictionaryCrossref] } from the line-streamed
      # attestation bridge (class note: not well-formed XML).
      def read_attestations(path, names, counts)
        return {} unless File.file?(path)

        out = {}
        concept = nil
        pending = nil
        flush = lambda do
          next if pending.nil?

          counts[:lexicalizations] += 1
          (out[concept] ||= []) << lexicalization_crossref(*pending)
          pending = nil
        end
        File.foreach(path, chomp: true, encoding: Encoding::UTF_8) do |line|
          if (match = CONCEPT_LINE.match(line))
            flush.call
            concept = names.key?(match[1]) ? match[1] : nil
            counts[:unheld_concepts] += 1 if concept.nil?
          elsif line.include?("<lexicalization ")
            flush.call
            match = LEXICALIZATION_LINE.match(line)
            raise Nabu::ParseError, "dcs lookup #{ATTESTATIONS_FILE}: unexpected line #{line.inspect}" if match.nil?

            pending = [match[1], Normalize.nfc(match[2]), 0] if concept
          elsif pending && (match = COUNT_LINE.match(line))
            pending[2] += match[1].to_i
          end
        end
        flush.call
        out
      end

      def lexicalization_crossref(lemma, form, total)
        noun = total == 1 ? "attestation" : "attestations"
        Nabu::DictionaryCrossref.new(kind: "lexicalization", label: "#{form} (#{total} #{noun})",
                                     target: form, target_id: lemma, to_dictionary: LEXICON_SLUG)
      end

      # -- shared ---------------------------------------------------------------

      # Yield each logical record of a TAB file as its +width+ fields,
      # rejoining physical lines split by an in-field newline (class note).
      # +header+, when given, must match the first line exactly; otherwise
      # the first line is skipped as the (quirky) header.
      def each_record(path, width, counts, header: nil)
        fragment = nil
        File.foreach(path, chomp: true, encoding: Encoding::UTF_8).with_index do |line, index|
          if index.zero?
            check_header!(path, line, header)
            next
          end
          fragment = fragment.nil? ? line : "#{fragment}\n#{line}"
          fields = fragment.split("\t", -1)
          next if fields.size < width

          if fields.size > width
            raise Nabu::ParseError, "dcs lookup #{File.basename(path)}: record overshoots #{width} fields " \
                                    "at line #{index + 1}: #{fragment.inspect}"
          end

          counts[:rejoined] += 1 if fragment.include?("\n")
          fragment = nil
          yield(fields.map { |field| Normalize.nfc(field) })
        end
        return if fragment.nil?

        raise Nabu::ParseError, "dcs lookup #{File.basename(path)}: unterminated record at EOF: #{fragment.inspect}"
      end

      def check_header!(path, line, header)
        fields = line.split("\t", -1)
        return if header ? fields == header : fields.first == "id"

        raise Nabu::ParseError, "dcs lookup #{File.basename(path)}: unexpected header #{line.inspect}"
      end

      def entry(id:, key_raw:, headword:, gloss:, body:, crossrefs: [])
        folded = Normalize.search_form(headword, language: LANGUAGE)
        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: key_raw, language: LANGUAGE, headword: headword,
          headword_folded: folded.nil? || folded.empty? ? headword : folded,
          gloss: gloss, body: body, crossrefs: crossrefs
        )
      end

      # Display form of a field: an in-field newline (the rejoined records)
      # reads as a space.
      def display(text) = text.tr("\n", " ").strip

      def value(field)
        text = field.to_s.strip
        text.empty? || text == EMPTY ? nil : text
      end
    end
  end
end
