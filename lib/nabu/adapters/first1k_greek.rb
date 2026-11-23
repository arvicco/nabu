# frozen_string_literal: true

require_relative "perseus"

module Nabu
  module Adapters
    # The First1KGreek adapter (architecture §3, packet P3-2): OpenGreekAndLatin's
    # First1KGreek corpus ships the *identical* CapiTainS/EpiDoc repo layout as
    # PerseusDL — data/<tg>/<work>/<tg>.<work>.<edition>.xml, dual __cts__.xml,
    # CTS refsDecl editions — so this is a thin SUBCLASS of Perseus rather than a
    # copy. It inherits discover/parse/fetch and the __cts__.xml title/urn
    # resolution wholesale, overriding exactly two things:
    #
    #   1. The manifest — a different source (id, name, upstream_url, license).
    #   2. The original-language edition-slug rule (#edition_slug_pattern).
    #
    # == Why subclass, not share a module
    #
    # Perseus already generalized the original-language selection into a single
    # data-driven method (#edition_slug_pattern) and made its class/instance
    # manifest methods overridable — it was written to be extended (its own
    # latinLit sibling is a one-line subclass). First1KGreek is greekLit only
    # (NAMESPACE stays "greekLit", so urns and the "grc" language tag come for
    # free), differing solely in slug family and identity. Subclassing captures
    # exactly that delta; a shared module would have to re-thread the namespace
    # plumbing Perseus already owns.
    #
    # == The edition-slug difference (the whole reason this class exists)
    #
    # Perseus editions are uniformly perseus-grcN. First1KGreek's are NOT: the
    # same corpus mixes 1st1K-grcN (dominant), opp-grcN, even perseus-grcN, and
    # letter-suffixed versions (1st1K-grc1a). So the acceptance rule ignores the
    # slug family entirely and matches ANY `…-grc<version>` tail; translations
    # (…-eng*, …-ger*, …-lat*, …-mul*, …-cop*) lack "-grc" and are skipped
    # unless the registry opts the source into translations (then eng, lat,
    # ger and cop editions are served — see TRANSLATION_TAGS below).
    # Highest-version-per-work selection is inherited unchanged — Perseus's
    # #version_key already orders numeric-then-letter (grc2 < grc2a).
    class First1kGreek < Perseus
      # First1KGreek is Greek only; the CTS namespace never shifts.
      NAMESPACE = "greekLit"

      # CC BY-SA 4.0 (repo-level) → license_class "attribution".
      MANIFEST = Nabu::SourceManifest.new(
        id: "first1k-greek",
        name: "Open Greek and Latin — First1KGreek",
        license: "CC BY-SA 4.0",
        license_class: "attribution",
        upstream_url: "https://github.com/OpenGreekAndLatin/First1KGreek",
        parser_family: "epidoc"
      )

      def self.manifest
        MANIFEST
      end

      def manifest
        MANIFEST
      end

      # Translation editions (translations: true) parse their body like the
      # eng ones — div[@type="translation"], edition-typed fallback — and
      # carry the cross-source translation-sibling marker (metadata "kind"),
      # which keeps them out of random original draws and the timeline. The
      # grc originals parse exactly as before.
      def parse(document_ref)
        language = document_ref.metadata["language"]
        return super if language == LANGUAGES.fetch(NAMESPACE)

        document = EpidocParser.new.parse(
          document_ref.path, urn: document_ref.id, language: language,
                             title: document_ref.metadata["title"],
                             division_types: TRANSLATION_DIVISION_TYPES
        )
        with_metadata(document, edition_metadata(document_ref).merge("kind" => "translation"))
      end

      # The translation-tag editions whose body is NOT a
      # translation or an edition (an editor's preface or index, typed
      # commentary upstream): skipped by rule at discover, named here.
      def discovery_skips(workdir)
        return super unless @translations

        skipped = apparatus_candidates(workdir).map { |candidate| File.basename(candidate.path, ".xml") }.sort
        notes = []
        unless skipped.empty?
          notes << "#{skipped.size} commentary-bodied translation-tag editions (apparatus, not " \
                   "translations): #{skipped.join(', ')}"
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped.size, notes: notes)
      end

      private

      # == The non-English translation editions (translations: true)
      #
      # Beyond the ~45 English editions, the repo ships 33 modern- and
      # ancient-language editions of its Greek works under other edition
      # tags (census 2026-10-19): 21 -lat, 7 -ger, 4 -mul, 1 -cop. They pair
      # with their Greek work EXACTLY through the CTS urn — same
      # <tg>.<work>, a different edition token — so the registry's `cts`
      # sibling family serves them to `--parallel` with no new machinery.
      # The passage language comes from the edition tag (TRANSLATION_TAGS):
      # lat → lat, ger → deu, cop → cop. What they are, honestly:
      # - translation-typed bodies (15): medieval and early-modern Latin
      #   versions (Sextus, Ptolemy's Geography in three printed Latin
      #   translations, Porphyry's Isagoge in Boethius' Latin, Origen's
      #   Matthew commentaries), a German Enoch, the Sahidic Coptic Mark;
      # - edition-typed bodies (11, plus one -mul index): the work's text where the Greek is lost
      #   or secondary — the Latin Acta Archelai, Themistius' paraphrases
      #   (Latin via Hebrew), Bonwetsch's German Methodius (from Old
      #   Slavonic), Gressmann's German Theophania (from Syriac), the Latin
      #   Alexias; served through the inherited edition-typed fallback;
      # - commentary-typed bodies (6): Diels' three Latin prefaces and sign
      #   key to the Anonymus Londinensis, and three -mul indices.
      #   Apparatus, not a text of the work: -mul is never accepted by slug,
      #   and a commentary-bodied lat/ger/cop file is skipped by rule at
      #   discover (#apparatus_candidates, censused in #discovery_skips).
      # Highest-version-per-work-and-language selection is inherited: the
      # three Latin Ptolemy translations (opp-lat4/9/10) yield lat10, the
      # version paired with the highest Greek edition (opp-grc10), exactly
      # as the superseded Greek editions yield to it. Every non-grc edition
      # carries metadata "kind" => "translation" — upstream's own catalog
      # (__cts__.xml) lists the Latin and German files as ti:translation of
      # the Greek work even where the body is typed edition. 24 documents
      # land (3,608 passages, census 2026-10-19).
      TRANSLATION_TAGS = { "eng" => "eng", "lat" => "lat", "ger" => "deu", "cop" => "cop" }.freeze

      # Body division types that make a non-English tag a servable text.
      SERVED_BODY_TYPES = TRANSLATION_DIVISION_TYPES
      private_constant :TRANSLATION_TAGS, :SERVED_BODY_TYPES

      # One more tag family than the eng-only base: the edition token's
      # language tag (:tag) + version (:version).
      def translation_slug_pattern
        /-(?<tag>#{TRANSLATION_TAGS.keys.join('|')})(?<version>\d+[a-z]?)\z/
      end

      def classify_edition(slug)
        match = slug.match(edition_slug_pattern)
        return [match[:version], LANGUAGES.fetch(NAMESPACE)] if match
        return nil unless @translations

        match = slug.match(translation_slug_pattern)
        match && [match[:version], TRANSLATION_TAGS.fetch(match[:tag])]
      end

      # The inherited candidates minus the apparatus files.
      def candidates(workdir)
        super.reject { |candidate| apparatus?(candidate) }
      end

      # The apparatus files the walk drops (the discovery census).
      def apparatus_candidates(workdir)
        Perseus.instance_method(:candidates).bind_call(self, workdir).select { |candidate| apparatus?(candidate) }
      end

      # A translation-tag candidate (any language but the Greek original)
      # whose body division is not a translation or an edition. English is
      # held to the same rule: the corpus's two commentary-bodied eng files
      # (tlg0527.tlg048 1st1K-eng1a notes / 1st1K-eng1b appendix, typed
      # ti:commentary in upstream's own __cts__.xml) would otherwise enter
      # the highest-version selection and displace the real translation
      # (see #translation_slug_pattern's note below). Census 2026-11-23:
      # 43 eng bodies typed translation, those 2 typed commentary, none
      # edition — so the rule moves exactly that one work. A file whose body
      # division cannot be read at all is NOT proven apparatus: it stays a
      # candidate, and its parse quarantines it visibly instead of a silent
      # skip.
      def apparatus?(candidate)
        return false if candidate.language == LANGUAGES.fetch(NAMESPACE)

        body_type = body_division_type(candidate.path)
        !body_type.nil? && !SERVED_BODY_TYPES.include?(body_type)
      end

      # The @type of the first <div> inside <body>, read with a streaming
      # Reader that stops there (some of these files run past 1 MB).
      def body_division_type(path)
        in_body = false
        File.open(path, "r") do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

            name = node.name.split(":").last
            in_body = true if name == "body"
            return node.attribute("type") if in_body && name == "div"
          end
        end
        nil
      rescue Nokogiri::XML::SyntaxError
        nil
      end

      # Accept any original-language Greek edition regardless of slug family:
      # 1st1K-grc1, opp-grc2, perseus-grc19, plus letter-suffixed versions
      # (1st1K-grc1a). Only the `-grc<version>` tail matters; the leading family
      # segment is free. The :version capture feeds the inherited
      # highest-version selection (Perseus#version_key).
      def edition_slug_pattern
        /-grc(?<version>\d+[a-z]?)\z/
      end

      # The English slug history (the -eng tag of #translation_slug_pattern
      # above). First1KGreek's eng editions are NOT the
      # uniform perseus-eng<n> the base class matches: the ~45 upstream eng
      # files are dominantly 1st1K-eng<n>, with an opp-eng<n> and letter-suffixed
      # versions (1st1K-eng1a/1b). So — exactly mirroring #edition_slug_pattern's
      # family-agnostic shape — accept ANY `-eng<version>` tail; the leading
      # family segment is free. The :version capture feeds the inherited
      # highest-version-per-work selection (Perseus#version_key).
      #
      # tlg0527.tlg048 (Ottley's Isaiah) ships three eng slugs — 1st1K-eng1
      # (the real translation, a div[@type="translation"]), 1st1K-eng1a (a
      # div[@type="commentary"] subtype=notes) and 1st1K-eng1b (a
      # div[@type="commentary"] subtype=appendix). Before the apparatus rule
      # covered English, version_key picked the highest (eng1b), whose
      # commentary body yields zero passages, so the work quarantined and its
      # translation never landed. The two commentary files are now skipped
      # by rule at discover (#apparatus?, censused in #discovery_skips) and
      # eng1 is the work's English edition. No "edition"-typed eng file
      # exists in the corpus (the base fallback stays inert for eng).
    end
  end
end
