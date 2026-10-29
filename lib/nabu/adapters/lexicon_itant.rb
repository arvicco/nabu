# frozen_string_literal: true

require_relative "lila_ttl_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # Lexicon ItAnt (github.com/DigItAnt/Lexicon_ItAnt): the OntoLex-Lemon
    # lexicon of the languages of ancient Italy built by the DigItAnt team
    # (PRIN 2017 "Languages and Cultures of Ancient Italy", CNR-ILC Pisa +
    # Università di Firenze) in LexO, the sibling of the Corpus ItAnt
    # inscriptions the itant adapter holds — its form notes cite those
    # inscriptions ("hasAttestation: ItAnt_Oscan_1 B, l. 1"). Dictionary-
    # shaped (entries, not passages); the lila-ttl reader composes, widened
    # for this file (Unicode local names, """ literals, bare OWL literals).
    #
    # == Upstream + grains (census 2026-10-29, upstream e8fe52a, the last push 2024-10-15)
    #
    # The repo serves three files: README.md (the license line),
    # lexicon_1_0.ttl (5.2 MB GraphDB export — 21 lime:Lexicon nodes, one
    # per language, 1,301 lime:entry members, plus the bundled
    # lexinfo/OntoLex/SKOS/OWL vocabularies and a 1,136-concept Buck
    # semantic-field scheme) and semanticFields_Buck_ItAnt_skos.ttl (the
    # same concept scheme as a standalone SKOS file). Upstream advertises
    # no count. The document grain is the LEXICON (one language), one
    # dictionary slug each (itant-lexicon-<code>, the sabellic-loans/
    # calfa precedent):
    #
    #   ACCEPTED — the 16 ancient-Italy lexicons, 809 entries: osc 419 ·
    #     xve 85 · xum 82 · xfa 75 · pgn 31 · xcg 27 · spx 23 · umc 17 ·
    #     ett 16 · xvo 10 · ims 9 · xvs 8 · sbv 3 · snt 2 · xhr 1 · xca 1.
    #     Every labeled member is an entry, whatever its LexO subtype
    #     (Word / LexicalEntry / MultiWordExpression / Affix — the Etruscan
    #     lexicon's 4 Etymon-typed members are Etruscan words cited as loan
    #     donors, kept as entries).
    #   REJECTED by rule (counted in discovery_skips) — the five auxiliary
    #     lexicons, 492 members: the cognate/donor lexicons lat 157 and grc
    #     22 (Latin/Greek comparanda; the library's own Latin/Greek shelves
    #     are their home) and the reconstruction lexicons PIE 164, PIT 148,
    #     PUM 1 ("Language for etymology"). Their words ride the accepted
    #     entries as reflex rows (relation inherited/borrowed/cognate) —
    #     nothing is lost, they just mint no entry of their own.
    #   REJECTED by rule — semanticFields_Buck_ItAnt_skos.ttl: it duplicates
    #     the concept scheme already inside lexicon_1_0.ttl and is not
    #     well-formed Turtle (an undeclared dcterms: prefix, a missing ';').
    #   Any other *.ttl and any lexicon language outside the two tables is
    #     UNRECOGNIZED — loud, never silently ingested or dropped.
    #
    # Reconciliation: 809 accepted + 492 rule-skipped = the 1,301 lime:entry
    # memberships; one further typed Word (LexO_2024-10-1407_03_10_339,
    # labeled with its own id) belongs to no lexicon — an unattached LexO
    # stub, not an entry of any language.
    #
    # == Entry shape
    #
    # entry_id = the entry IRI's local name (meddíss_noun_osc_entry,
    # LexO_2023-…); headword = rdfs:label verbatim (NFC — upstream's
    # editorial marks medd[í]ks, l]oifirtạ stay, the fold drops the
    # brackets); gloss = the first sense's skos:definition; body = POS +
    # stem type, the numbered senses, one line per attested form (written
    # rep, morphology, the attestation note — HTML stripped), the etymology
    # links, the cognates and the bibliography (contributor, title, date).
    # Reflexes: each EtyLink source → inherited (inheritance, 502 links) /
    # borrowed (borrowing, 44), each ety:cognate → cognate, lang_code = the
    # word's own lexicon language (PIE → ine-pro, PIT → itc-pro, PUM stays
    # display-only — no registry code). Annotations: pos (lexinfo local
    # name) and semantic_field (the Buck concepts lexicalizing the entry's
    # senses, 204 sense links).
    #
    # == License
    #
    # README.md verbatim: "Lexicon_ItAnt  is licensed under CC-BY-NC-SA"
    # (no version, no LICENSE file, the GitHub license field empty;
    # verified 2026-10-29) → class nc, the Corpus ItAnt sibling's class.
    # The cc:license / dct:rights statements inside the TTL belong to the
    # bundled vocabularies (lexinfo CC BY 4.0, OntoLex CC0), not the data.
    #
    # == fetch / sync policy
    #
    # Plain GitFetch of the whole repo (~6 MB) through the attic + breaker
    # contract; dormant since 2024-10 → sync_policy manual.
    class LexiconItant < Nabu::Adapter
      REPO_URL = "https://github.com/DigItAnt/Lexicon_ItAnt"
      LEXICON_FILE = /\Alexicon_\d+_\d+\.ttl\z/
      SKOS_FILE = %r{\AsemanticFields_[^/]*\.ttl\z}

      # The accepted ancient-Italy lexicons: lime:language → display name.
      # Codes are upstream's verbatim (xca Capenate and snt Pre-Samnite are
      # upstream's own tags, unverified against ISO 639-3).
      LANGUAGES = {
        "osc" => "Oscan", "xum" => "Umbrian", "sbv" => "Sabine", "pgn" => "Paelignian",
        "umc" => "Marrucinian", "ims" => "Marsian", "xvs" => "Vestinian", "xvo" => "Volscian",
        "xhr" => "Hernican", "spx" => "South Picene", "snt" => "Pre-Samnite", "xfa" => "Faliscan",
        "xca" => "Capenate", "xve" => "Venetic", "ett" => "Etruscan", "xcg" => "Cisalpine Gaulish"
      }.freeze

      # The auxiliary lexicons, skipped by rule (class note).
      AUXILIARY = {
        "lat" => "Latin cognate/donor lexicon", "grc" => "Greek cognate/donor lexicon",
        "PIE" => "Proto-Indo-European etymon lexicon", "PIT" => "Proto-Italic etymon lexicon",
        "PUM" => "PUM etymon lexicon"
      }.freeze

      # Reflex language: upstream etymon-lexicon tags → registry codes;
      # PUM has none (display-only). Every other tag passes through.
      REFLEX_LANGUAGE = { "PIE" => "ine-pro", "PIT" => "itc-pro", "PUM" => nil }.freeze

      LINK_RELATIONS = { "inheritance" => "inherited", "borrowing" => "borrowed" }.freeze

      ENTITIES = { "amp" => "&", "lt" => "<", "gt" => ">", "quot" => '"', "apos" => "'", "nbsp" => " " }.freeze

      SKOS_NOTE = "the standalone Buck semantic-field scheme — duplicated inside the lexicon file, " \
                  "and not well-formed Turtle"

      RDF_TYPE = LilaTtlParser::RDF_TYPE
      LIME = "http://www.w3.org/ns/lemon/lime#"
      ONTOLEX = "http://www.w3.org/ns/lemon/ontolex#"
      LEXINFO = "http://www.lexinfo.net/ontology/3.0/lexinfo#"
      ETY = "http://lari-datasets.ilc.cnr.it/lemonEty#"
      DCT = "http://purl.org/dc/terms/"
      SKOS = "http://www.w3.org/2004/02/skos/core#"
      LABEL = "http://www.w3.org/2000/01/rdf-schema#label"
      STEM_TYPE = "https://www.prin-italia-antica.unifi.it#stemType"
      FORM_FEATURES = %w[case gender number person tense mood voice aspect degree verbFormMood].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "lexicon-itant",
        name: "Lexicon ItAnt — the languages of ancient Italy (DigItAnt, CNR-ILC/UniFI; OntoLex-Lemon)",
        license: "CC BY-NC-SA (class nc). README verbatim: \"Lexicon_ItAnt  is licensed under " \
                 "CC-BY-NC-SA\" (github.com/DigItAnt/Lexicon_ItAnt, no LICENSE file; verified " \
                 "2026-10-29). Credit DigItAnt (PRIN 2017, CNR-ILC + Università di Firenze)",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "lila-ttl",
        credit: "DigItAnt — Languages and Cultures of Ancient Italy (PRIN 2017; CNR-ILC + " \
                "Università di Firenze), Lexicon ItAnt v1.0"
      )

      def self.manifest = MANIFEST

      def self.content_kind = :dictionary

      def self.slug_for(language) = "itant-lexicon-#{language}"

      # One ref per accepted lexicon present in the newest lexicon file,
      # LANGUAGES order.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        relative = lexicon_file(workdir) or return
        path = File.expand_path(relative, workdir)
        present = lexicons(path).keys
        LANGUAGES.each_key do |language|
          next unless present.include?(language)

          slug = self.class.slug_for(language)
          yield Nabu::DocumentRef.new(source_id: manifest.id, id: "#{slug}:#{relative}", path: path,
                                      metadata: { "dictionary" => slug, "language" => language })
        end
      end

      def discovery_skips(workdir)
        notes = []
        rule = 0
        strays = 0
        ttl_files(workdir).each do |relative|
          next if relative == lexicon_file(workdir)

          if SKOS_FILE.match?(relative)
            rule += 1
            notes << "#{relative}: #{SKOS_NOTE}"
          elsif LEXICON_FILE.match?(relative)
            rule += 1
            notes << "#{relative}: superseded by #{lexicon_file(workdir)}"
          else
            strays += 1
            notes << "#{relative}: not a recognized Lexicon ItAnt file"
          end
        end
        if (relative = lexicon_file(workdir))
          lexicons(File.expand_path(relative, workdir)).each do |language, members|
            next if LANGUAGES.key?(language)

            if AUXILIARY.key?(language)
              rule += 1
              notes << "#{relative}: lexicon #{language} (#{members.size} members): #{AUXILIARY.fetch(language)} " \
                       "— its words ride the accepted entries as reflexes"
            else
              strays += 1
              notes << "#{relative}: lexicon #{language} (#{members.size} members): not a recognized language"
            end
          end
        end
        DiscoverySkips.new(skipped_by_rule: rule, unrecognized: strays, notes: notes)
      end

      def parse(document_ref)
        language = document_ref.metadata.fetch("language")
        graph = graph_for(document_ref.path)
        document = Nabu::DictionaryDocument.new(
          slug: document_ref.metadata.fetch("dictionary"), language: language,
          title: "Lexicon ItAnt — #{LANGUAGES.fetch(language)} (DigItAnt)", canonical_path: document_ref.path
        )
        context = Context.new(graph: graph, lexicon_of: lexicon_of(document_ref.path),
                              fields: semantic_fields(graph))
        lexicons(document_ref.path).fetch(language, []).each do |entry|
          next if graph.first(entry, LABEL).nil? # a dangling member (no statements) is no entry

          document << build_entry(context, entry, language)
        end
        document
      rescue Nabu::ValidationError, KeyError => e
        raise Nabu::ParseError, "lexicon-itant: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      Context = Data.define(:graph, :lexicon_of, :fields)

      private

      # Seam for tests (the house local-git pattern).
      def repo_url = REPO_URL

      def ttl_files(workdir)
        Dir.glob("*.ttl", base: workdir).select { |relative| File.file?(File.join(workdir, relative)) }.sort
      end

      # The newest lexicon_<major>_<minor>.ttl (older versions skip by rule).
      def lexicon_file(workdir)
        ttl_files(workdir).grep(LEXICON_FILE)
                          .max_by { |relative| relative.scan(/\d+/).map(&:to_i) }
      end

      # The file is parsed once per (path, size, mtime) — every lexicon
      # document reads the one graph.
      def graph_for(path)
        key = [path, File.size(path), File.mtime(path)]
        return @graph if @graph_key == key

        text = SourceRead.utf8_file(path, label: "lexicon-itant")
        @lexicons = nil
        @graph_key = key
        @graph = LilaTtlParser::Graph.new(LilaTtlParser.new.statements(text))
      end

      # lime:language → member IRIs (document order), first lexicon per language.
      def lexicons(path)
        graph = graph_for(path)
        @lexicons ||= graph.subjects_of_type("#{LIME}Lexicon").each_with_object({}) do |lexicon, map|
          language = graph.first(lexicon, "#{LIME}language") or next
          (map[language] ||= []).concat(graph.objects(lexicon, "#{LIME}entry"))
        end
      end

      # member IRI → its lexicon's language.
      def lexicon_of(path)
        lexicons(path).each_with_object({}) do |(language, members), map|
          members.each { |member| map[member] ||= language }
        end
      end

      # sense IRI → the Buck concept labels lexicalizing it.
      def semantic_fields(graph)
        graph.subjects_of_type("#{ONTOLEX}LexicalConcept").each_with_object({}) do |concept, map|
          label = graph.first(concept, "#{SKOS}prefLabel") or next
          graph.objects(concept, "#{ONTOLEX}lexicalizedSense").each { |sense| (map[sense] ||= []) << label }
        end
      end

      def build_entry(context, entry, language)
        graph = context.graph
        label = Nabu::Normalize.nfc(graph.first(entry, LABEL).strip)
        senses = graph.objects(entry, "#{ONTOLEX}sense")
        definitions = senses.filter_map { |sense| clean(graph.first(sense, "#{SKOS}definition")) }
        Nabu::DictionaryEntry.new(
          entry_id: Nabu::Normalize.nfc(local_name(entry)), key_raw: label, language: language,
          headword: label, headword_folded: fold(label, language) || local_name(entry).downcase,
          gloss: definitions.first,
          body: body_lines(context, entry, definitions).join("\n").then { |text| text.empty? ? label : text },
          reflexes: reflexes(context, entry),
          annotations: annotations(context, entry, senses)
        )
      end

      def body_lines(context, entry, definitions)
        graph = context.graph
        head = [pos(graph, entry), clean(graph.first(entry, STEM_TYPE))&.then { |stem| "stem #{stem}" }].compact
        lines = []
        lines << head.join(" · ") unless head.empty?
        definitions.each_with_index { |definition, index| lines << "#{index + 1}. #{definition}" }
        graph.objects(entry, "#{ONTOLEX}lexicalForm").each { |form| lines << form_line(graph, form) }
        lines.concat(etymology_lines(context, entry))
        cognates = cognate_words(context, entry).map { |language, word| "#{language} #{word}" }
        lines << "cognates: #{cognates.join('; ')}" unless cognates.empty?
        notes = graph.objects(entry, "#{SKOS}note").filter_map { |note| clean(note) }
        notes.each { |note| lines << "note: #{note}" }
        references = graph.objects(entry, "#{DCT}references").filter_map { |ref| reference(graph, ref) }.uniq
        lines << "references: #{references.join('; ')}" unless references.empty?
        lines.compact.map { |line| Nabu::Normalize.nfc(line) }
      end

      def form_line(graph, form)
        rep = clean(graph.first(form, "#{ONTOLEX}writtenRep")) or return nil
        features = FORM_FEATURES.filter_map do |feature|
          value = graph.first(form, "#{LEXINFO}#{feature}")
          value && local_name(value)
        end
        notes = graph.objects(form, "#{SKOS}note").filter_map { |note| clean(note) }
        ["form #{rep}", (features.join(" ") unless features.empty?), *notes].compact.join(" — ")
      end

      def etymology_lines(context, entry)
        each_link(context, entry).map do |type, source, word, language|
          origin = word ? "#{language || '?'} #{word}" : source
          "etymology: #{type} from #{origin}"
        end
      end

      # [link type, source IRI, source word (nil when unlabeled), source
      # lexicon language] per EtyLink of the entry's etymologies whose
      # source is set (upstream carries draft links with none).
      def each_link(context, entry)
        graph = context.graph
        graph.objects(entry, "#{ETY}etymology").flat_map do |etymology|
          graph.objects(etymology, "#{ETY}hasEtyLink").filter_map do |link|
            source = graph.first(link, "#{ETY}etySource") or next
            type = graph.first(link, "#{ETY}etyLinkType") || "link"
            [type, source, graph.first(source, LABEL)&.strip, context.lexicon_of[source]]
          end
        end
      end

      def cognate_words(context, entry)
        context.graph.objects(entry, "#{ETY}cognate").filter_map do |cognate|
          word = context.graph.first(cognate, LABEL) or next
          [context.lexicon_of[cognate] || "?", Nabu::Normalize.nfc(word.strip)]
        end
      end

      def reflexes(context, entry)
        links = each_link(context, entry).filter_map do |type, _source, word, language|
          next unless word && language

          relation = LINK_RELATIONS[type]
          reflex(language, word, relation: relation, borrowed: relation == "borrowed")
        end
        cognates = cognate_words(context, entry).filter_map do |language, word|
          reflex(language, word, relation: "cognate", borrowed: false) unless language == "?"
        end
        (links + cognates).uniq
      end

      def reflex(code, word, relation:, borrowed:)
        language = REFLEX_LANGUAGE.fetch(code, code)
        nfc = Nabu::Normalize.nfc(word)
        Nabu::DictionaryReflex.new(
          lang_code: code, language: language, word: nfc,
          word_folded: fold(nfc, language || code), borrowed: borrowed, relation: relation
        )
      end

      def annotations(context, entry, senses)
        fields = senses.flat_map { |sense| context.fields.fetch(sense, []) }.uniq
        { "pos" => pos(context.graph, entry), "semantic_field" => (fields unless fields.empty?) }
          .compact.transform_values { |value| value.is_a?(Array) ? value.map { Nabu::Normalize.nfc(_1) } : value }
      end

      def pos(graph, entry)
        graph.first(entry, "#{LEXINFO}partOfSpeech")&.then { |iri| local_name(iri) }
      end

      # "Contributor, Title (date)" for a bibliography node.
      def reference(graph, ref)
        title = clean(graph.first(ref, "#{DCT}title")) or return nil
        author = clean(graph.first(ref, "#{DCT}contributor"))
        date = clean(graph.first(ref, "#{DCT}date"))
        [author, title].compact.join(", ") + (date ? " (#{date})" : "")
      end

      def local_name(iri) = iri.sub(%r{\A.*[#/]}, "")

      # Literal → one display line: HTML tags dropped (LexO's rich-text
      # notes), whitespace collapsed; nil when nothing remains.
      def clean(text)
        return nil if text.nil?

        out = decode_entities(text.gsub(/<[^>]*>/, " ")).gsub(/[[:space:]]+/, " ").strip
        out.empty? ? nil : Nabu::Normalize.nfc(out)
      end

      # The rich-text notes carry HTML character references (de&#237;va&#237;,
      # &#160;); decoded so the body reads as text.
      def decode_entities(text)
        text.gsub(/&(#x\h+|#\d+|[a-z]+);/i) do |match|
          ref = Regexp.last_match(1)
          if ref.start_with?("#x", "#X") then ref[2..].to_i(16).chr(Encoding::UTF_8)
          elsif ref.start_with?("#") then ref[1..].to_i.chr(Encoding::UTF_8)
          else ENTITIES.fetch(ref.downcase, match)
          end
        end
      end

      # The lookup key: editorial brackets/parentheses and the
      # reconstruction asterisk dropped, then the house fold.
      def fold(text, language)
        bare = text.delete("[]<>{}()⸢⸣*").strip
        form = Nabu::Normalize.search_form(bare, language: language)
        form.empty? ? nil : form
      end
    end
  end
end
