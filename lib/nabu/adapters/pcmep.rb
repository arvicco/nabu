# frozen_string_literal: true

require "stringio"
require_relative "../manual_drop"
require_relative "../zip_reader"
require_relative "penn_psd_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # PCMEP — the Parsed Corpus of Middle English Poetry (Richard
    # Zimmermann; pcmep.net, release Nov 2025): 57 Middle English poems,
    # c. 1150–1420, 235,439 words (the site's own Text Information table),
    # hand-parsed in the annotation scheme of its sister corpus PPCME2 —
    # The Grave and the Worcester Body and Soul, Poema Morale, the Proverbs
    # of Alfred, The Owl and the Nightingale, the Bestiary, King Horn,
    # Havelok, Kyng Alisaunder, Sir Orfeo, Amis and Amiloun, Laurence
    # Minot, Wynnere and Wastoure, the Siege of Jerusalem, Hoccleve's
    # Letter of Cupid. Built to close the c. 1250–1350 gap in the parsed
    # English prose record with the verse of the same period.
    #
    # == Upstream's delivery grains
    #
    # The release is ONE zip (PCMEP_Nov2025.zip, 1.3 MB) of Penn-bracketed
    # text files, one per poem, named "<band>.<text code>.psd"
    # (M1a.TheGrave.psd, M1b.AssumpVirg.psd — the site's per-text page
    # gives the same "File name" and its poem_name key is the text code).
    # - "<band>.<code>.psd" members → THE DOCUMENT GRAIN,
    #   urn:nabu:pcmep:<text code>. The band is NOT in the urn: it is a
    #   dating claim the maintainer may revise between releases, the text
    #   code is the citation key every tree's (ID <code>,<ref>) carries.
    # - macOS archiver litter (__MACOSX/, .DS_Store) → skipped by rule.
    # - anything else (a readme, sibling .pos/.txt/.out views if a release
    #   ever ships them) → counted UNRECOGNIZED with its member name until
    #   reviewed; never dropped silently.
    # The zip's directory layout is not pinned (the samples were cut from
    # a text extraction): members are matched on their BASENAME, so a flat
    # zip and one wrapped in a release directory both discover.
    # Reconciliation target for the first sync: 57 documents = the 57
    # rows of https://pcmep.net/texts.php; passages = the sum of the
    # per-text pages' "Token count" (Penn "token" = one tree).
    #
    # == Grain: one passage per tree (the sibling Penn sources' call)
    #
    # HeliPaD and PPCHY mint one passage per tree block; PCMEP does the
    # same. A tree is the corpus's own citation unit (the ID ref), its
    # syntax annotation is meaningless cut at a verse line, and the verse
    # lineation survives positionally: every (LB ||) leaf — upstream's
    # verse-line break — rides the tokens lane as {"code" => "LB"} (the
    # HeliPaD <R_n> shape) and leaves the surface text.
    #
    # == Text: the :ppche profile plus two PCMEP conventions
    #
    # The atoms are forms only (no fused lemma), the PPCHE scheme, so the
    # family's :ppche profile parses them; urn tails are the ID after the
    # comma ("TheGrave,1.1" → 1.1; "AssumpVirg,111.2.1" → 111.2.1 — the
    # site's per-text "ID" field documents the ref shape per poem). On top
    # of the parsed document this adapter applies, adapter-locally (the
    # family profile stays byte-frozen for HeliPaD/PPCHY):
    # - the PPCME2 character escapes, decoded in the surface and token
    #   forms: +t/+T þ/Þ, +d/+D ð/Ð, +g/+G ȝ/Ȝ, +a/+A æ/Æ (all but +G/+A
    #   attested in the samples); any other "+x" stays verbatim. The tree
    #   annotation and CODE comments keep upstream's escapes verbatim.
    # - the (LB ||) line breaks, moved from the surface to the code lane.
    # Traces and empties (*T*-1, *ICH*-1, *exp*, *con*, 0) are silent, and
    # (CODE {COMMENT:…}) editorial notes (emendations — the site's note 2
    # on PCMEP vs PPCME2) ride the tokens lane, never the text — both the
    # family's own behaviour. Upstream lines end in CRLF; the reader's
    # whitespace skip absorbs CR, tested on CRLF-built input.
    #
    # == Mined axes
    #
    # The files carry one axis-shaped field: the period band in the file
    # name. The site's periodization table (https://pcmep.net/) defines
    # M1a 1150–1200, M1b 1200–1250, M2a 1250–1300, M2b 1300–1350, M3
    # 1350–1420 (M1 and M2 being the Helsinki/PPCME2 parent periods), the
    # band of the text's estimated date of COMPOSITION (per-text page:
    # "PCMEP period"). Minted as metadata "period" (verbatim) and "date"
    # (:structured bounds). The per-text suggested year, dialect of
    # composition, manuscript, manuscript dialect and date, and genre/
    # subject keywords are published ONLY on the website's per-text pages
    # (textdetails.php), not in the zip — not mined here (see the source's
    # postures for the candidates).
    #
    # == License (research_private)
    #
    # Delivered by the maintainer by email, 2026-11-23, under the
    # pcmep.net download terms (verbatim in MANIFEST.license): research
    # use, no commercial use, no redistribution without the creators'
    # consent, citation required. The repo is public, so no corpus bytes
    # enter git: fixtures live under the gitignored local/fixtures/pcmep/.
    #
    # == Acquisition — the Manual Adapter pattern (ruling Dp-a)
    #
    # The download page is password-gated (credentials issued by the
    # maintainer), failing the automation bar: the owner drops the release
    # as pcmep.zip into incoming/pcmep/. The ZIP itself is the canonical
    # asset — discover/parse read its members in-process (ZipReader), so
    # nothing is materialized beside it and the plain-tree identity hashes
    # every byte (no materialized_paths to declare). See docs/manual/
    # pcmep.md. The maintainer invites a check for a newer release every
    # other year.
    class Pcmep < Nabu::Adapter
      SLUG = "pcmep"
      ZIP_NAME = "pcmep.zip"
      LANGUAGE = "enm"
      URN_PREFIX = "urn:nabu:pcmep:"
      # "<band>.<text code>.psd" — the band is M + a period digit + an
      # optional sub-period letter.
      MEMBER = /\A(M\d[a-z]?)\.([A-Za-z0-9_-]+)\.psd\z/
      ARCHIVER_LITTER = %r{(?:\A|/)(?:__MACOSX/|\.DS_Store\z)}

      # The site's periodization table (home page), verbatim spans.
      BANDS = {
        "M1a" => [1150, 1200], "M1b" => [1200, 1250], "M2a" => [1250, 1300],
        "M2b" => [1300, 1350], "M3" => [1350, 1420],
        "M1" => [1150, 1250], "M2" => [1250, 1350]
      }.freeze

      # The PPCME2 character escapes.
      ESCAPES = { "t" => "þ", "T" => "Þ", "d" => "ð", "D" => "Ð",
                  "g" => "ȝ", "G" => "Ȝ", "a" => "æ", "A" => "Æ" }.freeze
      ESCAPE = /\+([tTdDgGaA])/
      LINE_BREAK = "||"
      private_constant :MEMBER, :ARCHIVER_LITTER, :ESCAPE, :LINE_BREAK

      TERMS = "(1) The copy-right of the text editions used as the basis for the electronic text files " \
              "must not be violated. (2) The copy-right of the annotations remains with the creators of " \
              "the Parsed Corpus of Middle English Poetry. (3) The PCMEP will not be used direclty or " \
              "indirectly for any commercial purposes. (4) The corpus must not be re-distributed without " \
              "the consent of the creators of the Parsed Corpus of Middle English Poetry. (5) There is no " \
              "guarantee that the annotations are correct. The creators of the Parsed Corpus of Middle " \
              "English Poetry are not responsible for inaccurate statements that result from using the " \
              "corpus. (6) All research publications that use the Parsed Corpus of Middle English Poetry " \
              "must cite the corpus appropriately."

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "PCMEP — Parsed Corpus of Middle English Poetry (Zimmermann)",
        license: "pcmep.net download terms, verbatim (https://pcmep.net/download.php): \"#{TERMS}\" " \
                 "Release PCMEP_Nov2025.zip delivered by the maintainer by email, 2026-11-23 → local " \
                 "research ingest only, never redistributed",
        license_class: "research_private",
        upstream_url: "https://pcmep.net/download.php",
        parser_family: "penn-psd",
        credit: "Richard Zimmermann, The Parsed Corpus of Middle English Poetry (PCMEP), pcmep.net"
      )

      def self.manifest = MANIFEST

      # No unattended upstream to probe (password-gated download).
      def self.upstream_repo_urls = []

      # The acquisition contract the instruction card renders (the
      # docs/manual companion echoes it verbatim — the guard test pins it).
      def self.manual_acquisition
        @manual_acquisition ||= ManualDrop::Spec.new(
          slug: SLUG,
          upstream_url: MANIFEST.upstream_url,
          steps: [
            "Take the release archive the maintainer delivered by email on 2026-11-23 " \
            "(PCMEP_Nov2025.zip, 1.3 MB) — for a later release, download it from the pcmep.net " \
            "Download page with the username and password the maintainer issues on request " \
            "(a personal identity act — never an automated agent)",
            "Do not unpack it — the zip itself is the canonical asset",
            "Save it as #{ZIP_NAME} and drop it as listed below"
          ],
          files: [
            ManualDrop::FileSpec.new(
              name: ZIP_NAME,
              description: "the PCMEP release zip of <band>.<text>.psd files (research_private — never " \
                           "redistributed)",
              required: true, sniff: ->(path) { zip_complaint(path) }
            )
          ],
          refresh_hint: "The maintainer publishes new releases occasionally (check pcmep.net every other " \
                        "year); drop the new zip under the same name — the held one is atticked."
        )
      end

      # incoming/<slug>/ sits beside canonical/ (ruling Dp-a).
      def self.drop_dir(workdir)
        File.expand_path(File.join("..", "..", "incoming", SLUG), workdir)
      end

      # A readable ZIP carrying at least one band-prefixed .psd member;
      # a saved login page or a truncated download is not. One sentence.
      def self.zip_complaint(path)
        reader = SourceRead.zip_file(path)
        return nil if reader.entries.any? { |entry| member_match(entry.name) }

        "no period-band .psd members (M1a.<text>.psd …) — is this the PCMEP release?"
      rescue Nabu::ZipReader::Error, SystemCallError
        "not a readable ZIP archive (a saved login page or a truncated download?)"
      end

      # [band, text code] for a band-prefixed .psd member name, else nil.
      def self.member_match(name)
        name = name.b.dup.force_encoding(Encoding::UTF_8).scrub
        match = MEMBER.match(File.basename(name))
        match && !name.match?(ARCHIVER_LITTER) ? [match[1], match[2]] : nil
      end

      # The :structured date for a band, or nil for a band the site's
      # table does not define (never a guess).
      def self.band_date(band)
        span = BANDS[band] or return nil

        { "not_before" => span[0], "not_after" => span[1], "raw" => band }
      end

      def self.decode(text) = text.gsub(ESCAPE) { ESCAPES.fetch(Regexp.last_match(1)) }

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        result = Nabu::ManualDrop.sync!(
          spec: self.class.manual_acquisition, drop_dir: self.class.drop_dir(workdir),
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "already up to date (held manual ingest)" : nil)
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        zip = zip_path(workdir) or return
        accepted(zip).sort_by { |(_, code), _| code }.each do |(band, code), entry|
          block.call(Nabu::DocumentRef.new(
                       source_id: SLUG, id: "#{URN_PREFIX}#{code}", path: File.expand_path(zip),
                       metadata: { "member" => entry.name.b.dup.force_encoding(Encoding::UTF_8),
                                   "period" => band, "code" => code }
                     ))
        end
      end

      def discovery_skips(workdir)
        zip = zip_path(workdir) or return DiscoverySkips.new
        names = reader_for(zip).entries.map { |e| e.name.b.dup.force_encoding(Encoding::UTF_8).scrub }
        rest = names.reject { |name| name.end_with?("/") || self.class.member_match(name) }
        litter, unknown = rest.partition { |name| name.match?(ARCHIVER_LITTER) }
        notes = litter.map { |name| "#{name}: macOS archiver litter" } +
                unknown.map { |name| "#{name}: not a <band>.<text>.psd member — unrecognized, review" }
        DiscoverySkips.new(skipped_by_rule: litter.size, unrecognized: unknown.size, notes: notes)
      end

      def parse(document_ref)
        reader = reader_for(document_ref.path)
        member = document_ref.metadata.fetch("member")
        entry = reader.entries.find { |e| e.name.b == member.b } or
          raise ParseError, "#{member}: member vanished between discover and parse"

        text = SourceRead.utf8_member(reader, entry, label: document_ref.path)
        parsed = PennPsdParser.new.parse(
          StringIO.new(text), urn: document_ref.id, language: LANGUAGE, title: document_ref.metadata["code"],
                              canonical_path: document_ref.path, conventions: :ppche,
                              metadata: document_metadata(document_ref)
        )
        decoded(parsed)
      rescue Nabu::ZipReader::Error => e
        raise ParseError, "#{document_ref.id}: #{e.message}"
      end

      private

      def accepted(zip)
        reader_for(zip).entries.filter_map do |entry|
          match = self.class.member_match(entry.name)
          [match, entry] if match
        end
      end

      def document_metadata(document_ref)
        band = document_ref.metadata.fetch("period")
        { "file" => document_ref.metadata.fetch("member"), "period" => band,
          "date" => self.class.band_date(band) }.compact
      end

      # The parsed document with the PCMEP conventions applied (class
      # notes): escapes decoded, (LB ||) moved from surface to code lane.
      def decoded(parsed)
        document = Nabu::Document.new(urn: parsed.urn, language: parsed.language, title: parsed.title,
                                      canonical_path: parsed.canonical_path, metadata: parsed.metadata)
        parsed.each do |passage|
          text = surface(passage.text)
          next if text.empty?

          annotations = passage.annotations.merge("tokens" => passage.annotations.fetch("tokens").map { |t| token(t) })
          document << Nabu::Passage.new(urn: passage.urn, language: passage.language, text: text,
                                        sequence: passage.sequence, annotations: annotations)
        end
        raise ParseError, "#{parsed.canonical_path}: #{parsed.urn}: every tree was surface-empty" if document.empty?

        document
      end

      def token(token)
        return { "code" => "LB" } if token["pos"] == "LB" && token["form"] == LINE_BREAK
        return token unless token["form"]

        token.merge("form" => self.class.decode(token["form"]))
      end

      # Drop the "||" words; punctuation the family glued onto one
      # ("||," — closing punctuation attaches leftward) re-attaches to the
      # word before it.
      def surface(text)
        words = []
        text.split.each do |word|
          next words << word unless word.start_with?(LINE_BREAK)

          rest = word.delete_prefix(LINE_BREAK)
          next if rest.empty?

          words.empty? ? words << rest : words[-1] += rest
        end
        self.class.decode(words.join(" "))
      end

      def zip_path(workdir)
        direct = File.join(workdir, ZIP_NAME)
        return direct if File.file?(direct)

        Dir.glob(File.join(workdir, "*.zip")).min
      end

      def reader_for(zip)
        (@readers ||= {})[zip] ||= SourceRead.zip_file(zip)
      end
    end
  end
end
