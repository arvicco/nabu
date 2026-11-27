# frozen_string_literal: true

require_relative "hab_edoc_mets"
require_relative "hab_edoc_tei_parser"
require_relative "../fetch/hab_edoc_fetch"

module Nabu
  module Adapters
    # The Herzog August Bibliothek Wolfenbüttel's digital editions —
    # the Editiones Electronicae Guelferbytanae (2003–2017), the
    # Wolfenbütteler Digitale Editionen (2014–) and the project editions
    # the library hosts in its Wolfenbütteler Digitale Bibliothek
    # (diglib.hab.de/edoc/): hand-keyed TEI transcriptions of early
    # modern prints and manuscripts, 1460s–1752 — Hans Sachs's
    # Wittenbergisch Nachtigall (1523), Kaempfer's Amoenitates exoticae
    # (1712), Lipsius and Orsini on libraries, Dasypodius's
    # Latin-German dictionary, the Paesi novamente retrovati and its
    # German Newe unbekanthe landte, Sebald Heyden's school colloquies
    # in fifteen printings, Sibylla Schwarz's poems (1650), a 16th-c.
    # cookbook, the Lüne convent's letters, Fonteny's sonnet emblems —
    # and, by the per-edition review, Grimmelshausen's works, Lessing's
    # translations, Serranus's dictionary (1538), Christian II of
    # Anhalt-Bernburg's diaries (1621–1656), Bahnsen's and Duchess
    # Sibylla's letters, Hainhofer's travel reports, a Middle Low German
    # psalter, Rist's song books, Hartlieb, Tuberinus, a Latin sermon
    # manuscript, and the FMG's letters of musicians (1800–2000).
    #
    # == Upstream / grains (census 2026-11-27)
    #
    # No complete list exists upstream (HabEdocFetch: sitemap.xml stops
    # at ed000229, the HAB's "Digitale Editionen" page links 54
    # editions); the census walked the ids. ed000001–ed000300 plus the
    # sitemap's two suffixed ids: 256 answer with a METS manifest — 255
    # on the id walk (ed000001 … ed000284) plus ed000086_neu, a
    # reorganized copy of ed000086 the walk never reaches — the rest 404
    # or carry no METS, among them the old HTML-only
    # editions (ed000004 Vilnius colloquy, ed000005 Kircher's letters:
    # transcription.htm pages, no TEI) and the library's databases
    # (Lutherdatenbank, Leichenpredigten …). Grains:
    #
    # - ACCEPTED: a TRANSCRIPT — a TEI file the edition's METS lists under
    #   the WDB transcript name (HabEdocMets::TRANSCRIPT_NAME). Document =
    #   one transcript file: an edition is usually one (urn:nabu:
    #   hab-edoc:ed000238), but several hold one transcript per witness or
    #   part — the Paesi's Italian and German prints, Heyden's fifteen
    #   printings, Dasypodius's alphabet parts, the Lüne and Hanisius
    #   letters — each its own text (urn:nabu:hab-edoc:ed000267:
    #   Augsburg_1530, …:ed000248:Brief001-D; the token is the file name
    #   with the "tei-transcript" stem cut). Passage = page (the parser).
    # - ACCEPTED per edition: an OWN-NAME TEXT — a transcription the METS
    #   keeps under its own name beside the edition's introductions and
    #   registers, selected by the edition's reviewed rule (EDITIONS
    #   :texts — its fileGrp, a file-name pattern, or both: Christian II's
    #   1621_11.xml, Bahnsen's briefe/0001.xml, Lessing's *_ue.xml, the
    #   Hainhofer reports "texts/München 1603.xml" → urn:nabu:hab-edoc:
    #   ed000251:Munchen-1603). Same document and passage grain.
    # - HELD, never a document: an FMG letter's DESCRIPTION file
    #   (ed000249, <stem>_tei-msDesc_fmg.xml) — the letter's language and
    #   correspondents are read from it (the transcript states neither).
    # - REJECTED, skipped by rule: an edition whose METS lists no
    #   transcript and that the review admitted no rule for (200 of the
    #   walk's 255 — 184 records with a tei-introduction only, most of
    #   them the Theatrum repertory's facsimile records, and the
    #   introduction/bibliography-only project records); an edition held
    #   back by EDITIONS with its reason (the review's 18: Rubens, the
    #   Magdeburg Centuries, Karlstadt, Opitz, the Fruchtbringende
    #   Gesellschaft letters, Controversia et Confessio … — mostly texts
    #   whose language no file states); listed files an edition holds
    #   back by rule (EDITIONS :held — Lessing's _org originals); a listed
    #   transcript upstream does not serve (404 at fetch, recorded in the
    #   fetch state); a part file superseded by the edition's whole
    #   transcript (ed000223); a letter without a listed description, or
    #   whose description states no textLang; a transcript under an
    #   unusable rights statement (the licence law).
    # - UNRECOGNIZED: an edition with transcripts that EDITIONS does not
    #   know (new upstream — census it, then add the row), a listed
    #   transcript or description neither held nor recorded missing (a
    #   fetch hole), an unknown licence target, rights label or
    #   description textLang.
    #
    # Reconciliation (2026-11-27, the first sync): 25 editions list 550
    # transcripts; 3 editions held back (70 files: ed000132 1, ed000239 2,
    # ed000249 67), ed000008's whole-dictionary tei-transcript.xml 404s
    # (its five alphabet parts are served), ed000223's 7 parts superseded
    # by its whole — 472 documents, 308 skipped by rule (230
    # transcript-less editions + 70 + 1 + 7), as synced.
    #
    # The per-edition review (2026-11-27, every own-name edition censused
    # from the held METS and sampled, 65 requests): 12 editions admitted
    # by a rule, 517 own-name texts listed — ed000133 Grimmelshausen 32
    # (2 under the METS label "Benutzungsordnung" → skipped by the
    # licence law: 30), ed000146 Lessing 71 _ue (83 _org held back by
    # rule), ed000215 Serranus 24, ed000228 Christian II 338, ed000233
    # Bahnsen 21, ed000235 the psalter 1, ed000244 Rist 14, ed000251
    # Hainhofer 7, ed000269 Duchess Sibylla 6, ed000271, 275, 276 one
    # each; and ed000249's 67 FMG letters admitted through their
    # descriptions (65 listed; 2 — orgeni-a-002-1/-2 — without one,
    # skipped by rule). Expected after the next sync: 472 + 580 = 1,052
    # documents if every listed file is served and every description
    # states a mapped textLang; 316 skipped by rule (200 transcript-less
    # editions + 18 reviewed held-back editions + ed000132 1 + ed000239 2
    # + ed000146 83 + ed000133 2 + ed000249 2 + ed000008 1 + ed000223 7).
    #
    # == The licence law (per transcript)
    #
    # 1. The transcript's own teiHeader <licence @target> wins (LICENCE_CLASSES:
    #    CC BY / BY-SA → attribution, CC0 → open, via license_override).
    #    Where the TEI and the METS disagree the TEI is the file's own
    #    statement (ed000278: TEI CC0, METS label CC BY-SA 4.0; ed000238:
    #    target CC BY 4.0, text "CC BY SA 3.0" — the target is read).
    # 2. Else the edition's METS rights statement for the file (HabEdocMets):
    #    "CC BY-SA 3.0"/"4.0" → attribution; "rights restricted" and
    #    "Benutzungsordnung" (the image terms) → skipped by rule.
    # 3. Else the SITE DEFAULT, classed attribution on the HAB's statement
    #    (https://www.hab.de/digitale-editionen/, read 2026-11-27): the
    #    library hosts edition projects "die ... ihre Ergebnisse frei,
    #    bevorzugt unter einer CC BY-SA Lizenz, im Internet publizieren
    #    möchten" — and its own METS template's default segment is CC
    #    BY-SA 3.0. The transcripts in this class carry only the
    #    template's "(c) Herzog August Bibliothek Wolfenbüttel" line or
    #    nothing (ed000081, 226, 236, 241, 243, 247 by the census); each
    #    one's metadata says "license_basis" => "site default".
    # Census: no WDB-named transcript carries a restrictive statement; two
    # Grimmelshausen texts carry the METS label "Benutzungsordnung"
    # (simpli/transcript_b1.xml, calender/transcript_vor.xml) → skipped.
    # The availability line status="restricted" + "copyright information"
    # (?link=012) is the WDB template's boilerplate on transcripts of every
    # basis (Hans Sachs's beside his CC BY licence) — never read as a
    # statement; the licence law reads <licence> and the METS label only.
    #
    # == Language (the EDITIONS table — declared, never guessed)
    #
    # The headers do not state the text language usably: TEI/@xml:lang is
    # the header's language ("deu" on Conring's Latin poems), langUsage
    # lists every language a commentary mentions (Kaempfer's 25). So each
    # edition's language is declared below from what the text IS, with
    # per-file rules where an edition mixes (the Paesi's -nul German
    # print; the Lüne letters' own file-name language letter, D/DL →
    # Middle Low German, L/LD → Latin; Gabrias's Greek half). Upstream's
    # textLang/langUsage ride metadata. One exception, read never guessed:
    # the FMG letters (ed000249) are each in their own language, which
    # only the letter's description file states (msContents textLang
    # @mainLang — the census read fr, en, de against the letters
    # themselves); no description or no textLang → skipped by rule.
    #
    # == Mined metadata (the aggressive-mining rule)
    #
    # Author (EDITIONS override > sourceDesc author > titleStmt author —
    # the override where the header's author is the encoder), the print's
    # date as an EDITION-class date (the imprint year; a manuscript's
    # origDate or a letter's dated correspDesc rides class-less), the
    # imprint place and printer, shelfmark, sender/addressee, keywords,
    # the edition's METS title, the licence statement and its basis. The
    # review's editions add: the date their file's own title names where
    # nothing else dates them (EDITIONS date: :title — Christian II's
    # months, Bahnsen's letters, Hainhofer's journeys; class-less, basis
    # "title"); an FMG letter's description facts (sender, addressee,
    # sending place and date, shelfmark, the description's letter title);
    # and EDITIONS :drop removes mined fields that are a template
    # placeholder or the wrong thing (a register sourceDesc's stray
    # imprint, a holding library as pubPlace).
    #
    # == fetch
    #
    # HabEdocFetch: the METS id walk + every admitted file (HabEdoc.holdings:
    # transcripts, own-name texts, letter descriptions), 1 request per
    # second, ~300 METS + ~480 transcripts at the first sync (≈ 15–20
    # minutes with the server's latency); later syncs re-walk the METS and
    # fetch only new files (the review's admission: 649 — 517 own-name
    # texts, 67 FMG letters, 65 descriptions). The mirror is upstream's
    # own tree — nothing materialized beside it but the fetch state file.
    class HabEdoc < Nabu::Adapter
      SLUG = "hab-edoc"
      URN_PREFIX = "urn:nabu:hab-edoc:"

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Herzog August Bibliothek Wolfenbüttel — digital editions (Editiones Electronicae " \
              "Guelferbytanae, Wolfenbütteler Digitale Editionen)",
        license: "Per transcript: the TEI header's own <licence> (CC BY 4.0, CC BY-SA 3.0 DE / 4.0 → " \
                 "attribution; CC0 1.0 → open), else the edition's METS rights statement (\"CC BY-SA " \
                 "3.0\"), else the site's stated default — https://www.hab.de/digitale-editionen/: " \
                 "editions published \"frei, bevorzugt unter einer CC BY-SA Lizenz\". Restricted " \
                 "statements are skipped. Credit the Herzog August Bibliothek Wolfenbüttel and each " \
                 "edition's editors.",
        license_class: "attribution",
        upstream_url: "https://diglib.hab.de/edoc/",
        parser_family: "hab-edoc-tei",
        credit: "Herzog August Bibliothek Wolfenbüttel, Wolfenbütteler Digitale Bibliothek — the " \
                "edition named on each document (diglib.hab.de/edoc/<id>/start.htm)"
      )

      LICENCE_CLASSES = {
        %r{creativecommons\.org/licenses/by-sa/} => "attribution",
        %r{creativecommons\.org/licenses/by/} => "attribution",
        %r{creativecommons\.org/publicdomain/zero/} => "open",
        %r{creativecommons\.org/licenses/by-nc} => "nc"
      }.freeze
      METS_RIGHTS = { /\ACC BY-SA \d/ => "attribution" }.freeze
      METS_UNUSABLE = ["rights restricted", "Benutzungsordnung"].freeze
      SITE_DEFAULT = "https://www.hab.de/digitale-editionen/: \"frei, bevorzugt unter einer CC BY-SA " \
                     "Lizenz\" (the HAB's statement for the editions it hosts)"

      # The census, per edition: :language (the text's), :files (basename
      # pattern → language), :author (where the header's is the
      # encoder's or garbled), :whole (the one transcript that supersedes
      # the edition's part files), :skip (held back — why). The per-edition
      # review of the own-name editions adds: :texts (the METS rule for
      # texts kept under their own names — {group:, pattern:}, see
      # HabEdocMets#transcripts), :held (href pattern → why: listed texts
      # held back by rule, counted), :companion ([transcript suffix,
      # description suffix] — the letter's language is read from its
      # description file), :token (:dir — the directory names the text;
      # :none — the edition's one text is the edition URN), :dropped
      # (editors' elements dropped from the text), :drop (mined metadata
      # keys that are template placeholders or the wrong thing), :date
      # (:title — the date the file's own title names).
      EDITIONS = {
        "ed000001" => { language: "lat" }, # Lipsius, De bibliothecis syntagma (Greek quotations inside)
        "ed000008" => { language: "lat" }, # Dasypodius, Dictionarium Latinogermanicum (Latin lemmata)
        "ed000081" => { language: "lat" }, # Kaempfer, Amoenitatum exoticarum fasciculi V (Lemgo 1712)
        "ed000082" => { language: "de" }, # the 1539 book inventory of Elisabeth von Calenberg
        "ed000083" => { skip: "the Rubens sources (362 files): each body div states its xml:lang, but the " \
                              "bodies set the editors' German translation beside the source text " \
                              "(archivalien/epitaph_jan_rubens: a lat div, then a deu div) and the Codex " \
                              "diplomaticus Rubenianus volumes (cdr/) switch language chapter by chapter " \
                              "— needs a div-level language and translation rule" },
        "ed000086" => { skip: "the Magdeburg Centuries' correspondence (154 letters): Latin and German " \
                              "letters, and no file states its language (TEI/@xml:lang is the header's; " \
                              "no textLang, no langUsage)" },
        "ed000132" => { skip: "the Theatrum repertory's METS lists tei-transcript-pnr.xml — ed000145's " \
                              "file name, copied into its template — and serves no such file (404)" },
        "ed000133" => { language: "de", texts: { group: "transcription" }, token: :dir, # Grimmelshausen's
                        author: "Hans Jakob Christoffel von Grimmelshausen" }, # works (*/transcript*.xml)
        "ed000145" => { language: "it", files: { /-nul\.xml\z/ => "de" } }, # Paesi (Vicenza 1507) / Newe
        #                                    unbekanthe landte (Nürnberg 1508)
        "ed000146" => { language: "de", # Lessing's translations: the *_ue.xml files are his German text
                        texts: { group: "transcription", pattern: /(?:_ue|\Alaw_ermunterung)\.xml\z/ },
                        #                    law_ermunterung.xml is the _ue half by its METS file ID
                        #                    (edoc_ed000146_fg_law_ermunterung_ue)
                        held: { /_org\.xml\z/ => "the originals Lessing translated (*_org.xml: French, " \
                                                 "English, Italian, Spanish …), no file stating its language" } },
        "ed000166" => { language: "fr" }, # Fonteny, Livre d'enigmes (ed. Strasser)
        "ed000211" => { skip: "Controversia et Confessio 8: the source texts (*/edition*.xml) are separable " \
                              "from the editors' einleitung.xml by name, but Latin and German texts mix " \
                              "and no file states its language" },
        "ed000212" => { skip: "a modern catalogue of the Breslau funeral sermons (katalogeintrag divs) — " \
                              "not a source text" },
        "ed000213" => { skip: "the Fruchtbringende Gesellschaft letters 1617–1626: each letter file " \
                              "wraps the letter in the editors' summary, source description and " \
                              "commentary divs, and no file states its language" },
        "ed000214" => { skip: "the Fruchtbringende Gesellschaft letters 1637–1638: each letter file wraps " \
                              "the letter in the editors' summary, source description and commentary " \
                              "divs, and no file states its language" },
        "ed000215" => { language: "lat", texts: { group: "transcription" } }, # Serranus, Dictionarium
        #                                    Latinogermanicum (Nürnberg 1538): Latin lemmata, part_*.xml
        "ed000216" => { skip: "the Karlstadt critical edition (75 texts, 1507–1518): Latin and German " \
                              "works, and no file states its language" },
        "ed000217" => { skip: "the Fruchtbringende Gesellschaft letters 1630–1636: each letter file wraps " \
                              "the letter in the editors' summary, source description and commentary " \
                              "divs, and no file states its language" },
        "ed000218" => { skip: "the Fruchtbringende Gesellschaft letters 1639–1640: each letter file wraps " \
                              "the letter in the editors' summary, source description and commentary " \
                              "divs, and no file states its language" },
        "ed000223" => { language: "de", whole: "tei-transcript-mwb.xml" }, # Millinger's Weltbeschreibung
        "ed000226" => { language: "lat" }, # Conring, Musae errantes (Helmstedt 1708)
        "ed000227" => { skip: "the religious peace treaties: originals in Czech, Latin, German, French, " \
                              "Polish … beside the editors' German translations (*_dt.xml), and no file " \
                              "states its language" },
        "ed000228" => { language: "de", texts: { group: "transcription" }, # Christian II of Anhalt-Bernburg's
                        author: "Christian II. von Anhalt-Bernburg", # diaries, one file per month
                        dropped: %w[index], #                 the editors' place/regest/subject index
                        drop: %w[date place printer source_title shelfmark source_bibl], # the sourceDesc is
                        date: :title }, #                     the edition's person/place register, not a print
        "ed000232" => { language: "de" }, # Millinger's sermon notes
        "ed000233" => { language: "de", texts: { pattern: %r{\Abriefe/\d{4}\.xml\z} }, # Bahnsen's letters to
                        dropped: %w[head], date: :title }, #  Duke August (1660s); <head> is the editors' label
        "ed000234" => { skip: "Controversia et Confessio, the Augsburg Interim reactions: the texts " \
                              "(*/text.xml) are separable from einleitung.xml and titel.xml by name, but " \
                              "German, Latin and an English text mix and no file states its language" },
        "ed000235" => { language: "gml", texts: { group: "transcription" }, token: :none, # the Middle Low
                        drop: %w[edition_title] }, #          German psalter, Cod. Guelf. 81.10 Aug. 2°
        #                                    (the METS title is the template's "Autor und Titel")
        "ed000236" => { language: "gml", author: "Andreas de Escobar" }, # Modus confitendi, Middle
        #                                    Low German ("mndt" — the edition's own title)
        "ed000238" => { language: "de" }, # Hans Sachs, Die Wittenbergisch Nachtigall (1523)
        "ed000239" => { skip: "upstream's own header titles the transcripts \"Arndt-Projekt Test2\" — " \
                              "a test conversion of Book 1's opening, not the edition text" },
        "ed000241" => { language: "de" }, # Balthasar Staindl, Kochbuch
        "ed000243" => { language: "de", author: "Benigna von Solms-Laubach" }, # mütterliche Vermahnungen
        "ed000244" => { language: "de", texts: { group: "transcription" }, author: "Johann Rist" }, # the
        #                                    Katechismus-Andachten and the Seelenparadies, the print's parts
        "ed000245" => { language: "de" }, # Joseph Furttenbach, kupffer radier kunst
        "ed000246" => { skip: "Controversia et Confessio, the adiaphora controversy: the texts " \
                              "(*/text.xml) are separable from einleitung.xml by name, but German and " \
                              "Latin texts mix and no file states its language" },
        "ed000247" => { language: "lat", author: "Fulvio Orsini" }, # De bibliothecis commentarium
        "ed000248" => { language: "gml", files: { /-L[A-Z]*_tei-transcript\.xml\z/ => "lat" } }, # Lüne
        "ed000249" => { companion: %w[_tei-transcript.xml _tei-msDesc_fmg.xml] }, # the FMG letters
        #                                    (1800–2000): German, French, English — each letter's
        #                                    language from its description's textLang
        "ed000251" => { language: "de", texts: { group: "transcription" }, date: :title }, # Hainhofer's
        #                                    travel reports ("München 1603")
        "ed000253" => { language: "lat", author: "Johann Schwartzkopf" }, # Bibliotheca Augusta
        "ed000257" => { skip: "the Opitz works: Latin pieces inside the German-works edition " \
                              "(Band_II/Band_II_1/II_1_50.xml, a Latin funeral oration), the editors' " \
                              "print descriptions open each file, the Band V files are page-less HTML " \
                              "conversions, and the volume front matter (I_00, V_titelei, V_einleitung) " \
                              "is the modern edition's" },
        "ed000258" => { language: "fr" }, # Fonteny, Livre d'enigmes (ed. Fragonard)
        "ed000266" => { language: "lat", files: { /_grc\.xml\z/ => "grc" } }, # Gabrias, Tetrasticha (1524)
        "ed000267" => { language: "lat", author: "Sebald Heyden" }, # Formulae puerilium colloquiorum
        "ed000269" => { language: "de", texts: { group: "transcription" } }, # Duchess Sibylla's letters
        #                                    to Johann Valentin Andreae (1643)
        "ed000271" => { language: "lat", texts: { group: "transcription" }, token: :none, # Liber modorum,
                        drop: %w[author header_author] }, #   Cod. Guelf. 957 Helmst. (the header author is
        #                                    the template's "[Name des Autors]")
        "ed000275" => { language: "de", texts: { group: "transcription" }, token: :none }, # Tuberinus,
        #                                    Historie von Simon zu Trient (Trient 1475)
        "ed000276" => { language: "de", texts: { group: "transcription" }, token: :none, # Hartlieb, Buch
                        drop: %w[place] }, #                  aller verbotenen Kunst (the pubPlace is the
        #                                    holding library; upstream's langUsage says gmh)
        "ed000277" => { skip: "the file is a modern German translation of Burckhard's Latin Historia " \
                              "Bibliothecae Augustae (\"Vorrede an den wohlwollenden Leser\"), not the " \
                              "source text" },
        "ed000278" => { language: "de" }, # Sibylla Schwarz, Deutsche Poëtische Gedichte (Danzig 1650)
        "ed000279" => { language: "lat", author: "Daniel Klesch" }, # letters to David Hanisius
        "ed000280" => { skip: "Hainhofer's Großes Stammbuch: the METS lists texts/xxx.xml, a template " \
                              "placeholder upstream does not serve (404)" },
        "ed000282" => { skip: "a placeholder copy of ed000280 (texts/xxx.xml, not served)" },
        "ed000283" => { skip: "a placeholder copy of ed000280 (texts/xxx.xml, not served)" },
        "ed000284" => { skip: "a placeholder copy of ed000280 (texts/xxx.xml, not served)" }
      }.freeze

      # The FMG descriptions' textLang @mainLang → the bare code (the
      # census read de, fr, en); anything else is unrecognized until mapped.
      DESCRIPTION_LANGUAGES = { "de" => "de", "fr" => "fr", "en" => "en", "it" => "it" }.freeze

      STEM = /[-_]?tei-transcri(?:ption|pt)[-_]?/
      YEAR = /(?<!\d)(1\d{3})(?!\d)/

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "edition ed000238 METS", zip_url: HabEdocFetch.mets_url("ed000238"), metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # Is +href+ of edition +id+ a transcript the shelf holds? (The fetch
      # crawls exactly these.)
      def self.wanted?(id, href)
        entry = EDITIONS[id] or return false
        return false if entry[:skip]
        return false if entry.fetch(:held, {}).any? { |pattern, _| pattern.match?(href) }
        return File.basename(href) == entry[:whole] if entry[:whole]

        true
      end

      # Every file of edition +id+ the shelf holds, by its METS: the
      # transcripts (WDB-named, plus the edition's own-name texts) and, for
      # an edition read through letter descriptions, each transcript's
      # description the METS lists. (The fetch crawls these, +wanted?+
      # filtering.)
      def self.holdings(id, mets)
        texts = mets.transcripts(EDITIONS.dig(id, :texts)).map(&:href)
        descriptions = texts.filter_map { |href| companion_href(id, href) }.select { |c| mets.xml_files.include?(c) }
        texts + descriptions
      end

      # The description file a letter transcript's name implies (nil when
      # the edition reads none).
      def self.companion_href(id, href)
        from, to = EDITIONS.dig(id, :companion)
        return nil unless from && href.end_with?(from)

        "#{href.delete_suffix(from)}#{to}"
      end

      # Token = the file name, its WDB stem cut ("tei-transcript_Augsburg_1530"
      # → "Augsburg_1530"); :dir editions prefix the directory
      # ("simpli/transcript_b1" → "simpli_b1"); :none editions' one text IS
      # the edition. Accents fold ("München 1603" → "Munchen-1603"; every
      # name the WDB-named editions use is ASCII, so their URNs stand).
      def self.urn(id, href)
        token = case EDITIONS.dig(id, :token)
                when :none then ""
                when :dir then dir_token(href)
                else File.basename(href, ".xml").sub(STEM, "")
                end
        token = token.unicode_normalize(:nfd).gsub(/\p{Mn}/, "")
        token.empty? ? "#{URN_PREFIX}#{id}" : "#{URN_PREFIX}#{id}:#{token.gsub(/[^0-9A-Za-z_.-]/, '-')}"
      end

      def self.dir_token(href)
        parts = [File.dirname(href), File.basename(href, ".xml").sub(/\Atranscript_?/, "")]
        parts.reject { |part| part.empty? || part == "." }.join("_")
      end

      def self.language(id, href)
        entry = EDITIONS.fetch(id)
        rule = entry.fetch(:files, {}).find { |pattern, _| pattern.match?(File.basename(href)) }
        rule ? rule.last : entry.fetch(:language)
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        census(workdir).fetch(:accepted).each(&block)
      end

      def discovery_skips(workdir)
        result = census(workdir)
        DiscoverySkips.new(skipped_by_rule: result[:skipped].sum { |entry| entry[:count] },
                           unrecognized: result[:holes].size,
                           notes: result[:holes] + result[:skipped].map { |entry| entry[:note] })
      end

      def parse(document_ref)
        meta = document_ref.metadata
        id = meta.fetch("edition")
        description = meta["description"] && parser.description(
          File.join(document_ref.path.delete_suffix(meta.fetch("file")), meta["description"])
        )
        parser.parse(document_ref.path, urn: document_ref.id, language: meta.fetch("language"),
                                        license_override: meta["license_override"],
                                        dropped: EDITIONS.fetch(id).fetch(:dropped, [])) do |header|
          document_metadata(description ? description.merge(header) : header, meta, id)
        end
      end

      def fetch(workdir, progress: nil, force: false)
        result = HabEdocFetch.sync!(
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          files: ->(id, mets) { self.class.holdings(id, mets) },
          want: ->(id, href) { self.class.wanted?(id, href) },
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        missing = result.missing.values.sum(&:size)
        notes = "#{result.editions} edition METS · #{result.fetched} transcripts fetched · " \
                "#{result.cached} cached · #{missing} listed but not served (404)"
        notes += " · #{attic_notes(result.atticked)}" unless result.atticked.empty?
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes)
      rescue HabEdocFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser = @parser ||= HabEdocTeiParser.new

      # { accepted: [DocumentRef], skipped: [{count:, note:}], holes: [note] }
      # over the held editions, in id order.
      def census(workdir)
        result = { accepted: [], skipped: [], holes: [] }
        return result unless File.directory?(workdir)

        missing = HabEdocFetch.state(workdir).fetch("missing", {})
        Dir.children(workdir).grep(HabEdocFetch::EDITION_ID).sort.each do |id|
          classify_edition(workdir, id, missing.fetch(id, []), result)
        end
        result
      end

      def classify_edition(workdir, id, missing, result)
        dir = File.join(workdir, id)
        mets_path = File.join(dir, HabEdocFetch::METS_FILENAME)
        mets = File.file?(mets_path) ? HabEdocMets.read(mets_path) : nil
        entry = EDITIONS[id]
        transcripts = mets ? mets.transcripts(entry&.dig(:texts)) : held_transcripts(dir, entry)
        if transcripts.empty? && !entry&.dig(:skip)
          others = mets ? mets.xml_files.size : 0
          return skip(result, "#{id}: no TEI transcript in the edition's METS (#{others} other XML " \
                              "file(s): introduction, registers, a project tree) — not this shelf's grain")
        end

        unless entry
          return result[:holes] << "#{id}: #{transcripts.size} transcript(s) listed, but the edition " \
                                   "is not in HabEdoc::EDITIONS — census it (language, licence) and add the row"
        end
        return skip_edition(result, id, transcripts.size, entry[:skip]) if entry[:skip]

        skip_held_files(result, id, mets, entry)
        transcripts.each { |transcript| classify_file(workdir, id, transcript, mets, missing, result) }
      end

      # A held-back edition counts its listed transcripts, or 1 when the
      # review held back an edition the transcript name never reached.
      def skip_edition(result, id, listed, reason)
        return skip(result, "#{id}: held back — #{reason}") if listed.zero?

        skip(result, "#{id}: held back (#{listed} transcript(s)) — #{reason}", count: listed)
      end

      def skip_held_files(result, id, mets, entry)
        entry.fetch(:held, {}).each do |pattern, reason|
          count = mets ? mets.xml_files.count { |href| pattern.match?(href) } : 0
          skip(result, "#{id}: #{count} file(s) held back — #{reason}", count: count) if count.positive?
        end
      end

      def classify_file(workdir, id, transcript, mets, missing, result)
        href = transcript.href
        unless self.class.wanted?(id, href)
          return skip(result, "#{id}/#{href}: a part of the edition's whole transcript " \
                              "(#{EDITIONS[id][:whole]}) — held whole")
        end
        description = description_for(workdir, id, href, mets, missing) if EDITIONS[id][:companion]
        return result[:holes] << description[:hole] if description&.dig(:hole)
        return skip(result, description[:skip]) if description&.dig(:skip)

        path = File.join(workdir, id, href)
        return unless held?(path, "#{id}/#{href}", missing.include?(href), result)

        licence = licence_for(path, transcript)
        return result[:holes] << "#{id}/#{href}: #{licence[:unknown]}" if licence[:unknown]
        return skip(result, "#{id}/#{href}: #{licence[:skip]}") if licence[:skip]

        result[:accepted] << ref_for(id, href, path, licence, mets, description)
      end

      # A listed file on disk → true; else a 404 the fetch recorded (skip)
      # or a fetch hole.
      def held?(path, label, recorded_missing, result)
        return true if File.file?(path)

        if recorded_missing
          skip(result, "#{label}: listed in the METS, not served upstream (404)")
        else
          result[:holes] << "#{label}: listed in the METS but not held — a fetch hole"
        end
        false
      end

      # The letter's language from its own description file:
      # {href:, language:} | {skip:} | {hole:}.
      def description_for(workdir, id, href, mets, missing)
        companion = self.class.companion_href(id, href)
        unless companion && mets&.xml_files&.include?(companion)
          return { skip: "#{id}/#{href}: no description file listed in the METS — no per-letter language reading" }
        end

        path = File.join(workdir, id, companion)
        unless File.file?(path)
          return { skip: "#{id}/#{companion}: listed in the METS, not served upstream (404)" } \
            if missing.include?(companion)

          return { hole: "#{id}/#{companion}: listed in the METS but not held — a fetch hole" }
        end
        code = parser.description(path)["text_lang"]
        return { skip: "#{id}/#{href}: its description states no textLang — no per-letter language reading" } \
          unless code

        language = DESCRIPTION_LANGUAGES[code] or
          return { hole: "#{id}/#{companion}: unrecognized textLang #{code.inspect} — map it in " \
                         "HabEdoc::DESCRIPTION_LANGUAGES" }
        { href: companion, language: language }
      end

      def skip(result, note, count: 1)
        result[:skipped] << { count: count, note: note }
      end

      # An attic edition dir carries no METS: its transcript-named files
      # (and the files its own-name pattern names).
      def held_transcripts(dir, entry)
        pattern = entry&.dig(:texts, :pattern)
        held = Dir.glob("**/*.xml", base: dir).sort.select do |rel|
          HabEdocMets.transcript_name?(rel) || pattern&.match?(rel)
        end
        held.map { |rel| HabEdocMets::Transcript.new(href: rel, rights: []) }
      end

      def licence_for(path, transcript)
        header = parser.header(path)
        target = header["licence_target"]
        if target
          klass = LICENCE_CLASSES.find { |pattern, _| pattern.match?(target) }&.last
          return { unknown: "unrecognized licence target #{target.inspect} — class it in LICENCE_CLASSES" } \
            unless klass

          return { klass: klass, basis: "the transcript's TEI licence", statement: target }
        end
        mets_licence(transcript.rights)
      end

      def mets_licence(labels)
        return { klass: "attribution", basis: "site default", statement: SITE_DEFAULT } if labels.empty?

        unusable = labels & METS_UNUSABLE
        return { skip: "the edition's METS rights statement is #{unusable.first.inspect}" } unless unusable.empty?

        label = labels.first
        klass = METS_RIGHTS.find { |pattern, _| pattern.match?(label) }&.last
        return { unknown: "unrecognized METS rights label #{label.inspect}" } unless klass

        { klass: klass, basis: "the edition's METS rights statement", statement: label }
      end

      def ref_for(id, href, path, licence, mets, description)
        language = description ? description[:language] : self.class.language(id, href)
        Nabu::DocumentRef.new(
          source_id: SLUG, id: self.class.urn(id, href), path: File.expand_path(path),
          metadata: { "edition" => id, "file" => href, "language" => language,
                      "description" => description&.dig(:href),
                      "edition_title" => mets&.title, "license" => licence[:statement],
                      "license_basis" => licence[:basis],
                      "license_override" => licence[:klass] == MANIFEST.license_class ? nil : licence[:klass] }.compact
        )
      end

      def document_metadata(header, meta, id)
        out = mined_metadata(header, meta, EDITIONS.fetch(id), id)
        EDITIONS.fetch(id).fetch(:drop, []).each { |key| out.delete(key) }
        out["date"] ||= title_date(header["title"]) if EDITIONS.fetch(id)[:date] == :title
        out.reject { |_k, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
      end

      # The date the file's own title names ("Brief Nr. 1, vom 4. April
      # 1660", "München 1603") → class-less, basis "title".
      def title_date(title)
        years = title.to_s.scan(YEAR).flatten.map(&:to_i)
        return nil if years.empty?

        { "not_before" => years.min, "not_after" => years.max, "raw" => title, "basis" => "title" }
      end

      def mined_metadata(header, meta, entry, id)
        out = header.except("source_date", "letter_date", "header_author", "source_author", "licence_target")
        out["edition"] = id
        out["file"] = meta["file"]
        out["description"] = meta["description"]
        out["edition_title"] = meta["edition_title"]
        out["start_url"] = "https://diglib.hab.de/edoc/#{id}/start.htm"
        out["author"] = entry[:author] || header["source_author"] || header["header_author"]
        out["header_author"] = header["header_author"] if out["author"] != header["header_author"]
        out["license"] = meta["license"]
        out["license_basis"] = meta["license_basis"]
        out["date"] = date_for(header)
        out["place"] = header["pub_place"] || header["orig_place"] || header["sent_place"]
        out.reject { |_k, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
      end

      # The print's imprint year → class edition; a manuscript's origDate
      # or a letter's own date → the document's date, class-less.
      def date_for(header)
        reading = header["source_date"] || header["letter_date"] or return nil

        date = reading.slice("not_before", "not_after", "raw")
        date["basis"] = reading["basis"]
        date["class"] = "edition" if reading["basis"] == "imprint"
        date
      end
    end
  end
end
