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
    # cookbook, the Lüne convent's letters, Fonteny's sonnet emblems.
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
    # - REJECTED, skipped by rule: an edition whose METS lists no
    #   transcript (230 of the walk's 255 — 184 records with a
    #   tei-introduction only, most of them the Theatrum repertory's
    #   facsimile records, and the editions whose transcription fileGrp
    #   uses its own file names: Rubens, Lessing's translations, the
    #   Magdeburg Centuries, Karlstadt, Christian II's diaries, Opitz,
    #   Serranus, Hartlieb … — those groups mix introductions into the
    #   texts, so each is a per-edition review left for its own packet); a listed
    #   transcript upstream does not serve (404 at fetch, recorded in the
    #   fetch state); a part file superseded by the edition's whole
    #   transcript (ed000223); an edition held back by EDITIONS (below);
    #   a transcript under an unusable rights statement (the licence law).
    # - UNRECOGNIZED: an edition with transcripts that EDITIONS does not
    #   know (new upstream — census it, then add the row), a listed
    #   transcript neither held nor recorded missing (a fetch hole), an
    #   unknown licence target or rights label.
    #
    # Reconciliation (2026-11-27): 25 editions list 550 transcripts; 3
    # editions are held back (70 files: ed000132 1, ed000239 2, ed000249
    # 67), ed000008's whole-dictionary tei-transcript.xml 404s (its five
    # alphabet parts are served), ed000223's 7 parts are superseded by
    # its whole — 472 documents expected at the first sync if every other
    # listed file is served (the census fetched one file per edition).
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
    # Census: no admitted transcript carries a restrictive statement.
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
    # textLang/langUsage ride metadata.
    #
    # == Mined metadata (the aggressive-mining rule)
    #
    # Author (EDITIONS override > sourceDesc author > titleStmt author —
    # the override where the header's author is the encoder), the print's
    # date as an EDITION-class date (the imprint year; a manuscript's
    # origDate or a letter's dated correspDesc rides class-less), the
    # imprint place and printer, shelfmark, sender/addressee, keywords,
    # the edition's METS title, the licence statement and its basis.
    #
    # == fetch
    #
    # HabEdocFetch: the METS id walk + every admitted transcript, 1 request
    # per second, ~300 METS + ~480 transcripts at the first sync (≈ 15–20
    # minutes with the server's latency); later syncs re-walk the METS and fetch only new
    # transcripts. The mirror is upstream's own tree — nothing
    # materialized beside it but the fetch state file.
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
      # the edition's part files), :skip (held back — why).
      EDITIONS = {
        "ed000001" => { language: "lat" }, # Lipsius, De bibliothecis syntagma (Greek quotations inside)
        "ed000008" => { language: "lat" }, # Dasypodius, Dictionarium Latinogermanicum (Latin lemmata)
        "ed000081" => { language: "lat" }, # Kaempfer, Amoenitatum exoticarum fasciculi V (Lemgo 1712)
        "ed000082" => { language: "de" }, # the 1539 book inventory of Elisabeth von Calenberg
        "ed000132" => { skip: "the Theatrum repertory's METS lists tei-transcript-pnr.xml — ed000145's " \
                              "file name, copied into its template — and serves no such file (404)" },
        "ed000145" => { language: "it", files: { /-nul\.xml\z/ => "de" } }, # Paesi (Vicenza 1507) / Newe
        #                                    unbekanthe landte (Nürnberg 1508)
        "ed000166" => { language: "fr" }, # Fonteny, Livre d'enigmes (ed. Strasser)
        "ed000223" => { language: "de", whole: "tei-transcript-mwb.xml" }, # Millinger's Weltbeschreibung
        "ed000226" => { language: "lat" }, # Conring, Musae errantes (Helmstedt 1708)
        "ed000232" => { language: "de" }, # Millinger's sermon notes
        "ed000236" => { language: "gml", author: "Andreas de Escobar" }, # Modus confitendi, Middle
        #                                    Low German ("mndt" — the edition's own title)
        "ed000238" => { language: "de" }, # Hans Sachs, Die Wittenbergisch Nachtigall (1523)
        "ed000239" => { skip: "upstream's own header titles the transcripts \"Arndt-Projekt Test2\" — " \
                              "a test conversion of Book 1's opening, not the edition text" },
        "ed000241" => { language: "de" }, # Balthasar Staindl, Kochbuch
        "ed000243" => { language: "de", author: "Benigna von Solms-Laubach" }, # mütterliche Vermahnungen
        "ed000245" => { language: "de" }, # Joseph Furttenbach, kupffer radier kunst
        "ed000247" => { language: "lat", author: "Fulvio Orsini" }, # De bibliothecis commentarium
        "ed000248" => { language: "gml", files: { /-L[A-Z]*_tei-transcript\.xml\z/ => "lat" } }, # Lüne
        "ed000249" => { skip: "the FMG letters (1800–2000) carry no per-letter language and are " \
                              "multilingual (German, French, English) — held back until a per-letter " \
                              "language reading exists (CC0, admissible then)" },
        "ed000253" => { language: "lat", author: "Johann Schwartzkopf" }, # Bibliotheca Augusta
        "ed000258" => { language: "fr" }, # Fonteny, Livre d'enigmes (ed. Fragonard)
        "ed000266" => { language: "lat", files: { /_grc\.xml\z/ => "grc" } }, # Gabrias, Tetrasticha (1524)
        "ed000267" => { language: "lat", author: "Sebald Heyden" }, # Formulae puerilium colloquiorum
        "ed000278" => { language: "de" }, # Sibylla Schwarz, Deutsche Poëtische Gedichte (Danzig 1650)
        "ed000279" => { language: "lat", author: "Daniel Klesch" } # letters to David Hanisius
      }.freeze

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
        return File.basename(href) == entry[:whole] if entry[:whole]

        true
      end

      def self.urn(id, href)
        token = File.basename(href, ".xml").sub(/[-_]?tei-transcri(?:ption|pt)[-_]?/, "")
        token.empty? ? "#{URN_PREFIX}#{id}" : "#{URN_PREFIX}#{id}:#{token.gsub(/[^0-9A-Za-z_.-]/, '-')}"
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
        parser.parse(document_ref.path, urn: document_ref.id, language: meta.fetch("language"),
                                        license_override: meta["license_override"]) do |header|
          document_metadata(header, meta, id)
        end
      end

      def fetch(workdir, progress: nil, force: false)
        result = HabEdocFetch.sync!(
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
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
        transcripts = mets ? mets.transcripts : held_transcripts(dir)
        if transcripts.empty?
          others = mets ? mets.xml_files.size : 0
          return skip(result, "#{id}: no TEI transcript in the edition's METS (#{others} other XML " \
                              "file(s): introduction, registers, a project tree) — not this shelf's grain")
        end

        entry = EDITIONS[id]
        unless entry
          return result[:holes] << "#{id}: #{transcripts.size} transcript(s) listed, but the edition " \
                                   "is not in HabEdoc::EDITIONS — census it (language, licence) and add the row"
        end
        if entry[:skip]
          return skip(result, "#{id}: held back (#{transcripts.size} transcript(s)) — #{entry[:skip]}",
                      count: transcripts.size)
        end

        transcripts.each { |transcript| classify_file(workdir, id, transcript, mets, missing, result) }
      end

      def classify_file(workdir, id, transcript, mets, missing, result)
        href = transcript.href
        unless self.class.wanted?(id, href)
          return skip(result, "#{id}/#{href}: a part of the edition's whole transcript " \
                              "(#{EDITIONS[id][:whole]}) — held whole")
        end
        path = File.join(workdir, id, href)
        unless File.file?(path)
          return skip(result, "#{id}/#{href}: listed in the METS, not served upstream (404)") if missing.include?(href)

          return result[:holes] << "#{id}/#{href}: listed in the METS but not held — a fetch hole"
        end

        licence = licence_for(path, transcript)
        return result[:holes] << "#{id}/#{href}: #{licence[:unknown]}" if licence[:unknown]
        return skip(result, "#{id}/#{href}: #{licence[:skip]}") if licence[:skip]

        result[:accepted] << ref_for(id, href, path, licence, mets)
      end

      def skip(result, note, count: 1)
        result[:skipped] << { count: count, note: note }
      end

      # An attic edition dir carries no METS: its transcript-named files.
      def held_transcripts(dir)
        held = Dir.glob("**/*.xml", base: dir).sort.select { |rel| HabEdocMets.transcript_name?(rel) }
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

      def ref_for(id, href, path, licence, mets)
        Nabu::DocumentRef.new(
          source_id: SLUG, id: self.class.urn(id, href), path: File.expand_path(path),
          metadata: { "edition" => id, "file" => href, "language" => self.class.language(id, href),
                      "edition_title" => mets&.title, "license" => licence[:statement],
                      "license_basis" => licence[:basis],
                      "license_override" => licence[:klass] == MANIFEST.license_class ? nil : licence[:klass] }.compact
        )
      end

      def document_metadata(header, meta, id)
        entry = EDITIONS.fetch(id)
        out = header.except("source_date", "letter_date", "header_author", "source_author", "licence_target")
        out["edition"] = id
        out["file"] = meta["file"]
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
