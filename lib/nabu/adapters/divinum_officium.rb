# frozen_string_literal: true

require_relative "divinum_officium_parser"

module Nabu
  module Adapters
    # Divinum Officium — the Tridentine Latin Office and Mass
    # (github.com/DivinumOfficium/divinum-officium; the data files behind
    # divinumofficium.com). The Roman Breviary and Missal in their pre-1970
    # forms — the Tridentine/1570 structure as printed in the 1888 Ratisbon
    # Breviarium Romanum, with the Divino Afflatu (1911), 1955 and 1960
    # rubrical states, the Monastic, Cistercian and Dominican uses, local
    # propers (Rome, the Bavarian dioceses, Brazil, the Netherlands), the
    # Martyrology, the Rule of St Benedict and a Cistercian necrology — as
    # one data tree per language, digitized and adapted by the late Laszlo
    # Kiss and continued by the Divinum Officium Project. The repo is the
    # canonical asset (the website is only its renderer).
    #
    # == Upstream's delivery grains (census 2026-11-04, master @85183a9b)
    #
    # The data live under web/www/horas/ (the Office) and web/www/missa/
    # (the Mass), one directory per language:
    # - horas/Latin/** — 3,962 files (3,961 .txt + one empty extensionless
    #   stray, Sancti/aliquibus locis/09-04-BMVDivPastMatr, a 1-byte
    #   duplicate of its .txt sibling) and missa/Latin/** — 1,063 .txt:
    #   THE DOCUMENT GRAIN, one document per file. Of the 5,024 .txt,
    #   1,021 are inclusion stubs with no own text (a whole-file "@Commune/
    #   C10" inheritance, or sections that are all @-references / Rank /
    #   Rule / Name data — the Monastic, Cistercian and Dominican overlays
    #   above all): SKIPPED BY RULE at discovery, censused. 4,003 documents
    #   (26,381 passages) remain.
    # - the vernacular trees — horas: Bohemice 1,657 · Cesky-Schaller 33 ·
    #   Dansk 219 · Deutsch 1,055 · English 2,010 · Espanol 1,804 · Francais
    #   1,651 · Hebrew 220 · Italiano 1,832 · Magyar 1,252 · Magyar-Kaldi
    #   196 · Nederlands 847 · Polski 2,063 · Polski-Newer 152 · Portugues
    #   1,095 · Ukrainian 26 · Vietnamice 225; missa: Bohemice 247 ·
    #   Cesky-Schaller 218 · Dansk 22 · Deutsch 557 · English 951 · Espanol
    #   1,057 · Francais 957 · Italiano 943 · Magyar 901 · Nederlands 979 ·
    #   Polski 707 · Portugues 567 · Ukrainian 112 · Vietnamice 7: REJECTED
    #   (LATIN ONLY). Upstream's own credits page (web/www/horas/Help/
    #   credits.html) documents the translations as taken from modern
    #   editions and sites "with the permission" of their owners (the
    #   Martyrology, the English hymns), "used by permission of the
    #   copyright holder" (Polski-Newer), with sources undocumented ("Laszlo
    #   left behind no documentation of his sources of the Sancta Missa
    #   English translation"), and of the Bute English breviary scans:
    #   "The same collection also has a set of the same books without the
    #   quoted permission and apparently copyrighted." — none of that
    #   reaches the public-domain statement's "liturgical texts". Outside
    #   the sparse cone; one specimen pinned (horas/English).
    # - horas/Latin-gabc/** (4,809) — the Gregorian chant scores (gabc
    #   notation over the Latin text): REJECTED (a notation grain, not the
    #   text; the credits name the Liber Antiphonarius 1949 / Antiphonale
    #   Monasticum 1934 and GregoBase transcriptions). Specimen pinned.
    # - horas/Latin-Bea/** (170) — the alternative Pius XII (Bea, 1945)
    #   psalter: REJECTED (a twentieth-century Latin translation, the
    #   Pontifical Biblical Institute's — a modern authored text the
    #   public-domain statement does not obviously cover; held for a
    #   ruling, never guessed in). Specimen pinned.
    # - horas/Ordinarium/*.txt (6) — the hour-assembly templates ("#Psalmi",
    #   "$Pater noster", conditional directives): REJECTED (program
    #   scripts, not text — the Mass's own Ordo files under missa/Latin
    #   carry their text and are accepted). Specimen pinned.
    # - horas/Help/** (108) — the site's help/credits pages: REJECTED;
    #   credits.html alone rides the cone as the license evidence.
    # - the top-level site files of horas/ (14) and missa/ (13): .setup /
    #   .dialog config, ruler.txt, sundaytable.txt, images: REJECTED.
    # Reconciliation (the orchestrator's first-sync check): upstream
    # advertises no count; the census IS the claim — 5,025 Latin-tree
    # files = 4,003 accepted + 1,021 stubs + 1 stray, both skipped by rule
    # (+ credits.html, skipped by rule: 1,023 in a live sparse checkout);
    # the rejected trees never materialize (sparse cone) and are counted
    # by rule only where a workdir carries them (the fixture specimens).
    #
    # == Format and grains — see DivinumOfficiumParser (file-local;
    #    @-references preserved verbatim, never resolved)
    #
    # Layout per tree: Psalterium/Psalmorum → :verses (one passage per
    # verse); Necrologium → :necrology (one passage per day); everything
    # else → :sections (one passage per [section]).
    #
    # == Identity (FROZEN minting)
    #
    # Document: urn:nabu:divinum-officium:<book>/<path in the Latin tree,
    # no .txt, spaces → "_"> (no upstream file name carries "_", so the
    # fold is reversible) — urn:nabu:divinum-officium:horas/Sancti/01-21,
    # …:missa/Sancti/01-21, …:horas/Sancti/aliquibus_locis/09-04-RosaV.
    # Passage: <doc>:<section key> (…:horas/Sancti/01-21:Lectio4, a
    # repeated section …:Rank~2), <doc>:<verse> for the psalter
    # (…:horas/Psalterium/Psalmorum/Psalm1:1.3a), <doc>:<day> for the
    # necrology.
    #
    # == Mined axes
    #
    # From the path: book (horas/missa), book_part (Tempora · Sancti ·
    # Commune · Psalterium · Psalmorum · Martyrologium · Necrologium ·
    # Regula · Appendix · Ordo — the use suffix stripped), use (the Cist /
    # M / OP suffix → Cistercian / Monastic / Dominican; the unsuffixed
    # Tempora/Sancti/Commune and the Mass propers are the Roman use; the
    # Psalter, Martyrology, Rule, Necrology, Appendix and Ordo carry no use
    # claim — deliberately coarse), subcollection (the sub-directory chain:
    # "Bavaria/Passaviensis", "Urbis", "aliquibus locis", "Votiva",
    # "Psalmorum"), local_calendar (that chain under Tempora/Sancti/Commune,
    # the votive offices excepted — the facet region), day
    # (the file's own calendar code: "01-21", "Adv1-0", "C6-1"). PLACE:
    # a local-calendar directory names the jurisdiction whose proper the
    # file is (LOCAL_CALENDARS — Rome, Bavaria and four of its dioceses,
    # Brazil, the Netherlands, Groningen, Utrecht) → "place", the deepest
    # named segment (310 documents; the place_only timeline lane);
    # "aliquibus locis" ("in some places") names none.
    # From the text: title ([Officium], else the [Rank] line's own name),
    # rank (every variant whole) + rank_class (the unconditioned class:
    # "Duplex", "Semiduplex", "Duplex I classis"…), rule, inherits,
    # reference_sections. DATING: none — no file carries a date of
    # composition; the rubrical years in the conditionals (rubrica 1955,
    # 1960) name regimes, not texts, and the necrology's "Anno 1746" years
    # date the deaths it commemorates (passage "entry_years"), so the
    # source is undatable (postures.yml).
    #
    # == Text and language
    #
    # Language lat for every document. Upstream quirk, declared: the Latin
    # tree carries a little English — ~32 of 26,381 passages in 16 files
    # (heuristic census 2026-11-04): 20 are rubrics in three Mass ordinaries
    # (OrdoA, OrdoOP, Ordo67 — "The priest pours wine …"), the rest stray
    # English lessons in the propers — kept as upstream ships them.
    # Encoding: all 5,024 files valid UTF-8 (no BOM; 4 Brasilia files
    # CRLF — stripped); upstream's deprecated Windows-1252 form quarantines
    # loudly (ParseError) rather than guessing.
    #
    # == License
    #
    # Repo LICENSE: "MIT License … Copyright (c) 2026 Divinum Officium"
    # (the code and data files). The credits page, verbatim: "The code and
    # data are freely available to anyone at the Divinum Officium GitHub
    # repository, and licensed under the MIT License. All liturgical texts
    # within this site are, to the best of our knowledge, from the public
    # domain. No special permission is needed to utilize any of our
    # content." → class open (the Latin liturgical texts are public
    # domain; the MIT notice rides the manifest as credit).
    class DivinumOfficium < Nabu::Adapter
      REPO_URL = "https://github.com/DivinumOfficium/divinum-officium"
      URN_PREFIX = "urn:nabu:divinum-officium:"
      WWW = "web/www"
      BOOKS = %w[horas missa].freeze
      LATIN = "Latin"

      # The sparse cone (GitFetch no-cone patterns, anchored): the two
      # Latin trees + the license evidence. Every other language tree,
      # the chant and Bea trees, the templates, the site code stay upstream.
      SPARSE_CONE = [
        "/web/www/horas/Latin/", "/web/www/missa/Latin/",
        "/LICENSE", "/README.md", "/web/www/horas/Help/credits.html"
      ].freeze

      VERNACULAR = %w[
        Bohemice Cesky-Schaller Dansk Deutsch English Espanol Francais Hebrew Italiano Magyar
        Magyar-Kaldi Nederlands Polski Polski-Newer Portugues Ukrainian Vietnamice
      ].freeze
      REJECTED_TREES = {
        "Latin-gabc" => "the Gregorian chant scores (gabc notation) — a notation grain, not the text",
        "Latin-Bea" => "the Pius XII (Bea, 1945) psalter — a modern authored Latin translation, " \
                       "outside the public-domain statement's evident scope",
        "Ordinarium" => "the hour-assembly templates — program scripts, not text",
        "Help" => "the site's help and credits pages (credits.html is the license evidence)"
      }.freeze
      VERNACULAR_RULE = "a vernacular translation tree — LATIN ONLY: the credits page documents the " \
                        "translations as permission-based or of undocumented source, outside the " \
                        "public-domain statement"

      STUB_RULE = "an inclusion stub — no own text (every section an @-reference or Rank/Rule/Name data)"

      USES = { "M" => "Monastic", "Cist" => "Cistercian", "OP" => "Dominican" }.freeze
      USE_PARTS = /\A(?<part>Tempora|Sancti|Commune)(?<use>Cist|M|OP)?\z/
      # Local-calendar directories → the jurisdiction they name (Latin
      # directory name → the place's modern name).
      LOCAL_CALENDARS = {
        "Urbis" => "Rome", "Bavaria" => "Bavaria", "Monacensis" => "Munich",
        "Passaviensis" => "Passau", "Ratisbonensis" => "Regensburg", "Spirensis" => "Speyer",
        "Brasilia" => "Brazil", "Neerlandia" => "Netherlands", "Groningen" => "Groningen",
        "Ultrajectum" => "Utrecht"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "divinum-officium",
        name: "Divinum Officium — the Tridentine Latin Office and Mass (Breviarium and Missale Romanum)",
        license: "Public domain texts (credits page, verbatim: \"The code and data are freely available " \
                 "to anyone at the Divinum Officium GitHub repository, and licensed under the MIT License. " \
                 "All liturgical texts within this site are, to the best of our knowledge, from the public " \
                 "domain. No special permission is needed to utilize any of our content.\"); repo LICENSE: " \
                 "MIT License, Copyright (c) 2026 Divinum Officium. Latin trees only — the vernacular " \
                 "translations are excluded.",
        license_class: "open",
        upstream_url: REPO_URL,
        parser_family: "divinum-officium-txt",
        credit: "Divinum Officium Project (after Laszlo Kiss), github.com/DivinumOfficium/divinum-officium — MIT"
      )

      def self.manifest = MANIFEST

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        census(workdir).each do |entry|
          next unless entry[:accepted]

          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: entry[:urn], path: entry[:path], metadata: entry[:metadata]
          )
        end
      end

      def discovery_skips(workdir)
        entries = census(workdir)
        notes = entries.filter_map { |entry| "#{entry[:rel]}: #{entry[:skip]}" if entry[:skip] }
        unrecognized = entries.filter_map { |entry| "#{entry[:rel]}: #{entry[:stray]}" if entry[:stray] }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: unrecognized.size,
                                          notes: notes + unrecognized)
      end

      def parse(document_ref)
        meta = document_ref.metadata
        DivinumOfficiumParser.new.parse(
          document_ref.path, urn: document_ref.id, layout: meta.fetch("layout").to_sym,
                             metadata: meta.except("layout"),
                             fallback_title: document_ref.id.delete_prefix(URN_PREFIX).tr("_", " ")
        )
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, sparse: SPARSE_CONE)
      end

      # The path → metadata reading (public: tests pin each rule).
      # +book+ "horas"/"missa", +rel+ the path inside the Latin tree.
      def self.path_metadata(book, rel)
        parts = rel.split("/")
        top = parts.first
        subdirs = parts[1...-1]
        use_match = USE_PARTS.match(top)
        part = use_match ? use_match[:part] : top
        part = "Psalmorum" if top == "Psalterium" && subdirs.first == "Psalmorum"
        use = if use_match then USES.fetch(use_match[:use], "Roman")
              elsif book == "missa" && %w[Tempora Sancti Commune].include?(top) then "Roman"
              end
        place = subdirs.reverse.find { |dir| LOCAL_CALENDARS.key?(dir) }
        calendar = subdirs.join("/") if use_match && !subdirs.empty? && subdirs.first != "Votiva"
        {
          "book" => book, "book_part" => part, "use" => use,
          "subcollection" => subdirs.empty? ? nil : subdirs.join("/"),
          "local_calendar" => calendar,
          "place" => place && LOCAL_CALENDARS[place],
          "day" => File.basename(rel, ".txt"),
          "file" => "#{WWW}/#{book}/#{LATIN}/#{rel}"
        }.compact
      end

      def self.layout_for(rel)
        if rel.start_with?("Psalterium/Psalmorum/") then :verses
        elsif rel.start_with?("Necrologium/") then :necrology
        else :sections
        end
      end

      private

      # Test seam (the house pattern): fetch tests point this at a local rig.
      def repo_url
        REPO_URL
      end

      # One entry per file under web/www/{horas,missa}: accepted (with
      # urn/path/metadata), skipped by rule (skip:), or a stray (stray:).
      def census(workdir)
        BOOKS.flat_map do |book|
          base = File.join(workdir, WWW, book)
          Dir.glob("**/*", base: base).sort.filter_map do |rel|
            path = File.join(base, rel)
            next unless File.file?(path)

            classify(book, rel, File.expand_path(path))
          end
        end
      end

      def classify(book, rel, path)
        tree, inner = rel.split("/", 2)
        shown = "#{WWW}/#{book}/#{rel}"
        return { rel: shown, skip: "a top-level site file (config, image, table) — not liturgical text" } if inner.nil?
        return latin(book, inner, path, shown) if tree == LATIN
        return { rel: shown, skip: VERNACULAR_RULE } if VERNACULAR.include?(tree)
        return { rel: shown, skip: REJECTED_TREES[tree] } if REJECTED_TREES.key?(tree)

        { rel: shown, stray: "a tree no rule names (a new language or data tree upstream?)" }
      end

      def latin(book, inner, path, shown)
        unless inner.end_with?(".txt")
          return { rel: shown, skip: "not a .txt data file (the empty extensionless stray beside its .txt)" }
        end

        layout = self.class.layout_for(inner)
        return { rel: shown, skip: STUB_RULE } unless DivinumOfficiumParser.own_text?(path, layout: layout)

        {
          rel: shown, accepted: true, path: path,
          urn: "#{URN_PREFIX}#{book}/#{inner.delete_suffix('.txt').tr(' ', '_')}",
          metadata: self.class.path_metadata(book, inner).merge("layout" => layout.to_s)
        }
      end
    end
  end
end
