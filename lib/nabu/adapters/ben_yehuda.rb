# frozen_string_literal: true

require "csv"

require_relative "../fetch/ben_yehuda_period_fetch"
require_relative "source_read"

module Nabu
  module Adapters
    # ben-yehuda: Project Ben-Yehuda's public-domain dump
    # (github.com/projectbenyehuda/public_domain_dump) — the volunteer
    # digital library of Hebrew literature — taken for its PRE-MODERN layer
    # only: the piyyut and Andalusian poetry canon and the medieval and
    # Renaissance Hebrew around it (Yannai, Eleazar birabbi Qillir, Yose ben
    # Yose; Shmuel HaNagid, Shlomo ibn Gabirol, Yehuda Halevi, Abraham and
    # Moshe ibn Ezra, Yehuda Alharizi, Immanuel of Rome, Shalom Shabazi …).
    #
    # == The ruled scope cut
    #
    # The owner's ruling: ONLY the works upstream's own period taxonomy files
    # in its two pre-modern bands enter — "עת עתיקה ופיוט" (antiquity and
    # piyyut, to 900 CE) and "ימי הביניים והרנסאנס" (the Middle Ages and the
    # Renaissance, 900–1700). Everything else in the dump — the Haskalah,
    # the Revival and modern Hebrew literature, the bulk of its 26,455
    # works — is skipped BY RULE and counted (discovery_skips, one
    # aggregated note), never silently dropped.
    #
    # == The band-membership route
    #
    # The dump carries no period: pseudocatalogue.csv is ID, path, title,
    # authors, translators, author_uris, translator_uris, original_language,
    # genre, source_edition, and the html variant's head names only title
    # and author (read 2026-11-18). The site's API serves the period but
    # refuses keyless calls ("key not found or disabled"). The public
    # author browse filters by the same period enum and needs no key, so
    # #fetch walks it once per sync (Nabu::BenYehudaPeriodFetch) and
    # materializes periods.json at the canonical root — DECLARED in
    # materialized_paths. A work is in band when its dump directory
    # (txt/p<id>/, the site's authority id) is a band author. That
    # directory is the person the HEBREW text belongs to: translations sit
    # under their translator (p161 holds the Arabic poems Halevi put into
    # Hebrew, p223 Ibn Tibbon's Kuzari, p606 Shmuel Shullam's 16th-c.
    # Contra Apionem) — so the band judges the Hebrew, as it should. A sync
    # with the site down keeps the held sidecar (noted); with none held it
    # fails before cloning.
    #
    # == Upstream's delivery grains
    #
    # The dump serves each work three ways, one directory per author:
    # txt/ (plain text WITH nikud) — TAKEN; txt_stripped/ (the same text
    # with the pointing removed) and html/ (the same text as HTML) —
    # rejected, derivative renderings of the pointed text; the release
    # zips of the three trees — the same bytes. No epub/pdf in the dump
    # (the site renders those on demand). The fetch's sparse cone never
    # materializes the rejected trees nor any out-of-band author
    # directory; a rejected-variant file found on disk is skipped by rule.
    #
    # == Reconciliation (the plan; census 2026-11-18 at tag 2026-03)
    #
    # The site lists 13 ancient + 202 medieval authors (its period menu
    # counts 597 + 5,994 = 6,591 works; the browse's per-author counts sum
    # to 6,624 — they count every role). The dump at 2026-03: 26,455
    # catalogue rows under 949 author directories (1,203 distinct author
    # strings); IN BAND 206 directories / 6,043 works (ancient 9 / 84,
    # medieval 197 / 5,959). The residue to explain at first sync: 9 band
    # authors hold no dump directory — "אנונימוס (פייטן)" (the anonymous
    # paytan, 578 site works: the bulk of the ancient band lives on the
    # site only), Aristotle, Marcus Aurelius and Philo (the site credits
    # them, their Hebrew sits elsewhere or not in the dump) and five
    # one-work medieval authors; and per-author site/dump count drift
    # (Halevi 586/578, Ibn Gabirol 662/669, …). Expected first sync: 6,043
    # documents, ~20,412 catalogued works skipped by rule; the exact
    # numbers go here once the real sync reports them.
    #
    # == Identity and passages
    #
    # Document = one manifestation, urn:nabu:ben-yehuda:m<ID> (the
    # catalogue's own ID, stable across author-directory moves). Each txt
    # file is: line 1 the title (→ metadata; the catalogue title is the
    # document title), a tab line, the text, and upstream's closing credit
    # line ("את הטקסט[ים] לעיל הפיקו מתנדבי פרויקט בן־יהודה …" + the
    # read URL) — boilerplate, stripped, its URL kept as read_url.
    #
    # The passage is upstream's own BLANK-LINE BLOCK (whitespace-only lines
    # separate), urn …:m<ID>:<n>. The edition's layout makes that the
    # honest grain at every scale: the Andalusian and piyyut texts set every
    # verse (bayit, hemistichs split by " / ") as its own block, so a
    # passage is one verse; where upstream runs lines together without a
    # blank (strophic modern-style layout) the block is the stanza; in
    # prose the block is the paragraph. A superscription ("לאחד הסדרים
    # שבפרשת נח") is upstream text and stays a passage. A block that is a
    # bare UNPOINTED section numeral (Hebrew letters in numeral order — "א",
    # "יא", "טו", "קכ" — or digits) is the poem's section label: it mints
    # no passage and rides the following passages as annotation "section".
    # A block with no letter or digit at all (a stray point — m34421 carries
    # a lone rafe, U+05BF, on a line of its own) mints no passage either;
    # the document counts them in metadata stray_blocks.
    #
    # == Language and the NFC exemption
    #
    # Every document is `hbo`: the house code for pre-modern Hebrew, and the
    # one Normalize::NFC_EXEMPT_LANGUAGES names — the txt/ pointing ships in
    # a mark order NFC would reorder (non-NFC lines in every pointed fixture
    # file), so the text is stored byte-verbatim; search still folds
    # through NFC. The medieval band stages onto heb:med
    # (config/lect_facet_rules.yml, the period facet); the ancient band
    # stays bare hbo (no Byzantine-piyyut stage exists — the sefaria
    # liturgy precedent).
    #
    # == Axes (aggressive mining)
    #
    # - date — the band as a composition-era envelope ({not_before,
    #   not_after, raw = the band label, class composition}): the period of
    #   the person whose Hebrew it is. Coarse by upstream's own grain
    #   (DECLARED): the dump carries no per-work or per-author dates.
    # - genre — the catalogue's genre is a leaked i18n key ("Translation
    #   missing: he.poetry"); the key ("poetry") is upstream's genre enum
    #   (the API's own values) and rides genre (kind_map.yml folds it), the
    #   raw string genre_raw.
    # - author / translator / their Wikidata URIs, original_language,
    #   source_edition (the print the volunteers transcribed — free prose,
    #   kept verbatim, not parsed into place/date: DECLARED), the band
    #   facet, the author facet, the site's browse name, the dump release
    #   (VERSION).
    # - places — the dump names no place (unplaced).
    #
    # == License
    #
    # LICENSE verbatim: "The data files in this repository are in the public
    # domain, so you are free to make any use of them, and do not need to
    # ask for permission. If you would like to give credit, please credit
    # "Project Ben-Yehuda volunteers", and include a link to the site." —
    # class open; the credit is requested, not required, and is carried
    # anyway.
    #
    # == fetch
    #
    # The band walk first, then GitFetch PINNED to release tag 2026-03 (the
    # tenth release, 2026-03-07; commit 5e4277fe) with a sparse cone of the
    # catalogue, LICENSE, README.md, VERSION and the band authors' txt/
    # directories only (the full repo is ~880 MB; a re-pin is an owner
    # decision), then the sidecar lands (rewritten only when the band lists
    # change).
    class BenYehuda < Nabu::Adapter
      REPO_URL = "https://github.com/projectbenyehuda/public_domain_dump"
      RELEASE_TAG = "2026-03"
      URN_PREFIX = "urn:nabu:ben-yehuda:"
      LANGUAGE = "hbo"

      SIDECAR = BenYehudaPeriodFetch::SIDECAR
      CATALOGUE = "pseudocatalogue.csv"
      VERSION_FILE = "VERSION"
      TXT_DIR = "txt"
      REJECTED_VARIANTS = {
        "txt_stripped" => "the same text with its pointing removed — a derivative of the taken txt/",
        "html" => "the same text rendered as HTML — a derivative of the taken txt/"
      }.freeze

      # Root files the cone carries beside the band directories.
      CONE_FILES = %W[/#{CATALOGUE} /LICENSE /README.md /#{VERSION_FILE}].freeze

      CATALOGUE_PATH = %r{\A/p(\d+)/m(\d+)\z}
      TXT_FILE = /\Am(\d+)\.txt\z/
      FOOTER = /\Aאת הטקסט\[ים\] לעיל הפיקו מתנדבי פרויקט בן־יהודה/
      READ_URL = %r{https://benyehuda\.org/read/\d+}
      GENRE_KEY = /\ATranslation missing: he\.([a-z_]+)\z/

      # A bare section numeral: Hebrew letters in numeral order (hundreds,
      # tens, units; the 15/16 forms טו/טז), or digits, an optional geresh
      # or trailing period — never pointed text.
      NUMERAL = /\A(?=[א-ת\d])(?:ת*[קרש]?(?:[יכלמנסעפצ]?[א-ט]?|טו|טז)|\d{1,4})['׳"״]?\.?\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "ben-yehuda",
        name: "Project Ben-Yehuda — the public-domain dump, pre-modern layer (piyyut, Andalusian and " \
              "medieval-to-Renaissance Hebrew)",
        license: "Public domain (LICENSE, verbatim: \"The data files in this repository are in the public " \
                 "domain, so you are free to make any use of them, and do not need to ask for permission. " \
                 "If you would like to give credit, please credit \"Project Ben-Yehuda volunteers\", and " \
                 "include a link to the site.\")",
        license_class: "open",
        upstream_url: REPO_URL,
        parser_family: "ben-yehuda-txt",
        credit: "Project Ben-Yehuda volunteers — https://benyehuda.org"
      )

      Scan = Data.define(:refs, :skipped_by_rule, :notes, :unrecognized)

      def self.manifest = MANIFEST

      # Each parse reads its own file; the discover-time metadata rides the ref.
      def self.parallel_parse? = true

      def self.materialized_paths = [SIDECAR]

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        scan(workdir).refs.each(&block)
      end

      def discovery_skips(workdir)
        result = scan(workdir)
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: result.skipped_by_rule,
                                          unrecognized: result.unrecognized.size,
                                          notes: result.notes + result.unrecognized)
      end

      def parse(document_ref)
        lines = SourceRead.utf8_file(document_ref.path, label: "ben-yehuda txt").split("\n", -1)
        blocks = blocks(lines.drop(1))
        read_url = footer_url!(blocks)
        stray = blocks.count { |block| block.none? { |line| line.match?(/[\p{L}\p{N}]/) } }
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: document_ref.metadata.fetch("title"),
          canonical_path: document_ref.path,
          metadata: document_ref.metadata.fetch("document")
                                .merge("read_url" => read_url, "stray_blocks" => stray.zero? ? nil : stray).compact
        )
        add_passages(document, blocks)
        raise ParseError, "#{document_ref.path}: no text below the title" if document.empty?

        document
      end

      def fetch(workdir, progress: nil, force: false)
        periods, period_note = band_lists(workdir, progress)
        report = git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                            ref: RELEASE_TAG, sparse: cone(periods))
        written = !BenYehudaPeriodFetch.write!(workdir, periods).nil?
        notes = [band_note(periods, written, period_note), report.notes].compact.join("; ")
        Nabu::FetchReport.new(sha: report.sha, fetched_at: report.fetched_at, notes: notes)
      end

      private

      # Seams for tests (the house local-git pattern; WebMock answers the site).
      def repo_url = REPO_URL

      def period_http = BenYehudaPeriodFetch.default_http

      # [payload, note] — a fresh walk, else the held sidecar (noted), else
      # a FetchError before anything is cloned.
      def band_lists(workdir, progress)
        fresh = BenYehudaPeriodFetch.new(http: period_http, progress: progress).payload(retrieved: Date.today)
        [fresh, nil]
      rescue BenYehudaPeriodFetch::Error => e
        held = BenYehudaPeriodFetch.read(workdir)
        raise FetchError, "ben-yehuda: the period band walk failed and no #{SIDECAR} is held: #{e.message}" unless held

        [held, "the band walk failed (#{e.message}) — held #{SIDECAR} kept"]
      end

      def cone(periods)
        CONE_FILES + periods.fetch("authors").keys.map { |id| "/#{TXT_DIR}/p#{id}/" }
      end

      def band_note(periods, written, period_note)
        counts = periods.fetch("bands").map { |band, info| "#{info['authors']} #{band}" }.join(" + ")
        state = period_note || (written ? "#{SIDECAR} updated" : "#{SIDECAR} unchanged")
        "period bands: #{counts} authors (#{state})"
      end

      # -- discovery

      # One walk: the sidecar names the band authors, the catalogue names
      # every work; each catalogued work is a ref (in band, file present),
      # a counted skip (out of band) or an unrecognized gap (in band, file
      # missing). Files the catalogue never names, and the rejected variant
      # trees, are censused from disk.
      def scan(workdir)
        periods = BenYehudaPeriodFetch.read(workdir)
        catalogue_path = File.join(workdir, CATALOGUE)
        unless periods && File.file?(catalogue_path)
          missing = periods ? CATALOGUE : SIDECAR
          fetched = Dir.exist?(workdir) && !Dir.empty?(workdir)
          note = fetched ? ["#{missing} absent — no band cut can be made (fetch materializes it)"] : []
          return Scan.new(refs: [], skipped_by_rule: 0, notes: [], unrecognized: note)
        end

        build_scan(workdir, periods, catalogue(catalogue_path))
      end

      def build_scan(workdir, periods, rows)
        authors = periods.fetch("authors")
        bands = periods.fetch("bands")
        release = release(workdir)
        refs = []
        unrecognized = []
        out_of_band = Hash.new(0)
        rows.each do |mid, row|
          pid = row.fetch(:pid)
          unless authors.key?(pid)
            out_of_band[pid] += 1
            next
          end

          path = File.join(workdir, TXT_DIR, "p#{pid}", "m#{mid}.txt")
          unless File.file?(path)
            unrecognized << "#{TXT_DIR}/p#{pid}/m#{mid}.txt: catalogued in band but absent from the tree"
            next
          end
          refs << ref(path, mid, row, authors.fetch(pid), bands, release)
        end
        unrecognized.concat(uncatalogued(workdir, rows))
        skipped, notes = skip_census(workdir, out_of_band)
        Scan.new(refs: refs.sort_by(&:id), skipped_by_rule: skipped, notes: notes, unrecognized: unrecognized)
      end

      def skip_census(workdir, out_of_band)
        notes = []
        skipped = out_of_band.values.sum
        unless out_of_band.empty?
          notes << "#{skipped} catalogued work#{'s' unless skipped == 1} under #{out_of_band.size} author " \
                   "director#{out_of_band.size == 1 ? 'y' : 'ies'} outside upstream's two pre-modern period " \
                   "bands (the ruled cut: ancient + piyyut, middle ages + renaissance) — skipped by rule"
        end
        REJECTED_VARIANTS.each do |dir, why|
          count = Dir.glob(File.join(workdir, dir, "**", "*")).count { |path| File.file?(path) }
          next if count.zero?

          skipped += count
          notes << "#{dir}/: #{count} file#{'s' unless count == 1} — #{why}; skipped by rule"
        end
        [skipped, notes]
      end

      # txt files on disk the catalogue does not list (in-band or not).
      def uncatalogued(workdir, rows)
        Dir.glob(File.join(workdir, TXT_DIR, "p*", "*")).filter_map do |path|
          mid = File.basename(path)[TXT_FILE, 1]
          next if mid && rows.key?(mid)

          "#{path.delete_prefix("#{workdir}/")}: no catalogue row names this file"
        end
      end

      # {mid => row hash}, the catalogue's own path split into p/m ids.
      def catalogue(path)
        table = CSV.parse(SourceRead.utf8_file(path, label: "ben-yehuda catalogue"), headers: true)
        table.each_with_object({}) do |row, map|
          match = row["path"].to_s.match(CATALOGUE_PATH) or next
          next unless match[2] == row["ID"].to_s

          map[match[2]] = row.to_h.transform_keys(&:to_s).merge(pid: match[1])
        end
      rescue CSV::MalformedCSVError => e
        raise FetchError, "#{path}: unreadable catalogue: #{e.message}"
      end

      def release(workdir)
        path = File.join(workdir, VERSION_FILE)
        File.file?(path) ? SourceRead.utf8_file(path, label: "ben-yehuda VERSION").strip : nil
      end

      def ref(path, mid, row, author, bands, release)
        band = author.fetch("band")
        info = bands.fetch(band)
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{URN_PREFIX}m#{mid}", path: File.expand_path(path),
          metadata: { "band" => band, "title" => text(row["title"]) || "m#{mid}",
                      "document" => document_metadata(mid, row, author, band, info, release) }
        )
      end

      def document_metadata(mid, row, author, band, info, release)
        authors = text(row["authors"])
        genre_raw = text(row["genre"])
        {
          "benyehuda_id" => Integer(mid, 10), "author_dir" => "p#{row.fetch(:pid)}",
          "author" => authors, "translator" => text(row["translators"]),
          "author_uris" => text(row["author_uris"]), "translator_uris" => text(row["translator_uris"]),
          "original_language" => text(row["original_language"]),
          "genre" => genre_raw&.[](GENRE_KEY, 1) || genre_raw, "genre_raw" => genre_raw,
          "source_edition" => text(row["source_edition"]),
          "band" => band, "site_author" => author["name"], "dump_release" => release,
          "date" => { "not_before" => info["not_before"], "not_after" => info["not_after"],
                      "raw" => info["label"], "class" => "composition" },
          "facets" => { "period" => { "value" => band, "raw" => info["label"] },
                        "author" => authors && { "values" => [authors] } }.compact
        }.compact
      end

      def text(value)
        stripped = value.to_s.strip
        stripped.empty? ? nil : Normalize.nfc(stripped)
      end

      # -- parsing

      # Runs of non-blank lines (each stripped), split on whitespace-only lines.
      def blocks(lines)
        lines.map(&:strip)
             .chunk_while { |a, b| !a.empty? && !b.empty? }
             .reject { |chunk| chunk.first.empty? }
      end

      # Strips upstream's closing credit block; returns its read URL.
      def footer_url!(blocks)
        return nil unless blocks.last&.first&.match?(FOOTER)

        blocks.pop.join(" ")[READ_URL]
      end

      def add_passages(document, blocks)
        section = nil
        blocks.each do |block|
          if block.size == 1 && section_label?(block.first)
            section = block.first
            next
          end
          next unless block.any? { |line| line.match?(/[\p{L}\p{N}]/) }

          annotations = section ? { "section" => section } : {}
          document << Nabu::Passage.new(urn: "#{document.urn}:#{document.size + 1}", language: LANGUAGE,
                                        text: SourceRead.nfc(block.join("\n"), language: LANGUAGE),
                                        sequence: document.size, annotations: annotations)
        end
      end

      def section_label?(line)
        !line.match?(/\p{Mn}/) && line.match?(NUMERAL)
      end
    end
  end
end
