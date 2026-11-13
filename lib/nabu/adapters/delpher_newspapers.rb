# frozen_string_literal: true

require "fileutils"

require_relative "delpher_didl_parser"
require_relative "../zip_fetch"

module Nabu
  module Adapters
    # delpher-newspapers — the Delpher open newspaper archive (Delpher open
    # krantenarchief) of the KB, the national library of the Netherlands:
    # the texts (uncorrected OCR — with the hand-corrected 17th-century
    # pages among them — ALTO, metadata) of every Delpher newspaper issue
    # from 14 June 1618 to 31 December 1879, as the KB offers them for
    # download in 23 period zips. Dutch above all, with the Republic's
    # French-language gazettes beside it (La gazette d'Amsterdam, Gazette de
    # Rotterdam, Nouvelles extraordinaires de divers endroits).
    #
    # == License (read 2026-11-13)
    #
    # - kb.nl/en/research-find/datasets/delpher-newspapers: "The Delpher
    #   newspapers comprise the texts (OCR, ALTO, XML) from all newspapers
    #   dating from 1618 to 1879. The archive is 111 GB and split into 23
    #   ZIP files. These newspapers are free of copyright and may be used
    #   without restrictions."
    # - delpher.nl/over-delpher/delpher-open-krantenarchief (Citeren en
    #   gebruiksvoorwaarden): "De dataset als geheel is vrijgegeven onder een
    #   CC-BY 4.0-licentie. … N.B: De teksten (OCR, ALTO) van losse
    #   krantenafleveringen vallen in het publieke domein, er rusten dus
    #   geen rechten meer op."
    # - every zip's README_newspapers_pd_<period>.txt: "The Delpher open
    #   newspaper archive has been released under the CC-BY 4.0 license. …
    #   Please note: The texts (OCR, ALTO) of individual newspapers editions
    #   and articles are in the public domain, free of copyrights."
    # Issue texts PD; the archive as a whole CC BY 4.0 → attribution class,
    # with the KB's own credit line (MANIFEST credit).
    #
    # == Delivery grains (enumerated 2026-11-13)
    #
    # Upstream serves, all from datasets.kb.nl behind the permanent
    # resolver.kb.nl/resolve?urn=DATA:kranten:<name> URLs:
    #
    # - 23 period ZIPS (ZIPS below: sizes from the 2026-11-13 HEADs, issue
    #   counts from upstream's own index, md5 where the archive page
    #   publishes one). Every zip has the same tree:
    #   <yyyy>/<mm>/<dd>/<issue folder>/ holding didl.xml (the issue's
    #   MPEG-21 DIDL: catalogue record, pages, articles), one
    #   <prefix>_<nnnn>_articletext.xml per ARTICLE and one
    #   <prefix>_<nnn>_alto.xml per PAGE; at the zip root
    #   index_kranten_pd_<period>.tsv (paper, date, zip, folder per issue),
    #   README_newspapers_pd_<period>.txt and LEESMIJ_kranten_pd_<period>.txt.
    #   Issue folders are DDD_ddd_<n>_mpeg21 (the Databank Digitale
    #   Dagbladen) or KRANTEN_<C>_<C>_<n>_mpeg21 (later Metamorfoze/KB
    #   digitization batches: MMKB08 in the 17th century); the folder name
    #   is the DIDL's record id (ddd:<n>:mpeg21 / <C>:<n>:mpeg21) — unique
    #   across the whole archive (370,016 index rows, 0 repeats).
    #   TAKEN, a cone at a time (CONE below).
    # - DOCUMENT = the ISSUE (one folder: didl.xml + its articletext files).
    #   The issue is fully reconstructable — the DIDL lists every article
    #   in order with its file, subject, title and pages — and it is the
    #   unit upstream identifies, dates and catalogues. PASSAGE = the
    #   ARTICLE (upstream marks them: articletext files, ordered by the
    #   DIDL), urn …:a0001; an article whose OCR is empty mints no passage
    #   (counted in metadata empty_articles).
    # - the ALTO page files — REJECTED, skipped by rule: word coordinates
    #   of the page scans, carrying the same OCR the articletext files
    #   carry by article (21,661 pages in the 16xx zip). A trimmed real
    #   page is pinned in the fixture.
    # - the zip-root index tsv / README / LEESMIJ — REJECTED as text,
    #   skipped by rule (furniture; the index's paper/date/folder facts are
    #   the DIDL's own fields).
    # - index_delpher_kranten_pd_v1-0_2020.zip (all 370,016 issues, 3.6 MB)
    #   and kranten_pd_voorbeeld.zip (the 5-issue sample) — REJECTED, never
    #   fetched: the per-zip index rides inside each zip; the sample
    #   duplicates issues the period zips serve.
    # - page scans (JP2) and issue PDFs — not in the archive; the DIDL
    #   names their resolver URLs, never fetched.
    #
    # == Reconciliation (the 16xx cone; central-directory census 2026-11-13)
    #
    # Upstream advertises 8,559 issues for 1618–1699 (the archive page and
    # the zip's README); the zip's central directory holds 114,046 members:
    # 8,559 issue folders (8,085 DDD + 474 MMKB08), each with exactly one
    # didl.xml and ≥ 1 articletext file (68,694 articles; median 7, max
    # 47), 21,661 ALTO pages, 3 root files, 15,129 directories. Discovery
    # therefore yields 8,559 refs; skipped by rule 21,661 ALTO + 3 root
    # files (+ the fetch pin); unrecognized 0. Decades: 1610s 11 · 1620s
    # 353 · 1630s 423 · 1640s 618 · 1650s 169 · 1660s 698 · 1670s 2,144 ·
    # 1680s 1,395 · 1690s 2,748. Papers (22 titles): Oprechte Haerlemsche
    # courant 4,025 · Amsterdamse courant 774 · Courante uyt Italien,
    # Duytslandt, &c. 744 · La gazette d'Amsterdam 676 · Gazette de
    # Rotterdam 411 · Tĳdinghe uyt verscheyde quartieren 401 · …
    #
    # == Axes (aggressive-mining law)
    #
    # - date (MetadataDates :structured) — dc:date, the issue's own day: a
    #   one-year envelope with the ISO day riding raw, no class (the print
    #   IS the text's publication; the house date classes are composition
    #   and edition only, and neither applies to a newspaper's own issue).
    # - place — the DIDL's dcterms:spatial xsi:type dcx:creation, the place
    #   of publication verbatim (Amsterdam, Haerlem, Rotterdam,
    #   's-Gravenhage, Groningen); the untyped spatial (Landelijk,
    #   Regionaal/lokaal — the paper's distribution scope) rides
    #   "distribution".
    # - kind — the whole source is the periodical press: kind_map
    #   source_kind periodical/newspaper. Article subjects (artikel,
    #   advertentie, familiebericht, …) ride each passage's annotations
    #   verbatim and project as the passage genre facet (facet_map.yml
    #   passage_fields) — a per-article claim, never the issue's kind; the
    #   per-issue tally in metadata "subjects" is declared a summary in
    #   Health::Invariants::MINING_EXEMPT.
    # - lect — dc:language per issue (ISO 639-1, any case) → the house code;
    #   an issue listing two languages (the bilingual Napoleonic-era
    #   Groningen sheet: fr + nl) claims the FIRST as upstream orders them,
    #   all riding "languages" (deliberately coarse: articles carry no
    #   language mark).
    # - paper, publisher, issue number, the title's run (dcterms:issued),
    #   its other names, PPN, the holding copy (dc:source — the 1618
    #   Courante is the Stockholm copy), the digitization collection, and
    #   per-page OCR confidence ride the metadata; paper and publisher
    #   project as facets (config/facet_map.yml).
    # - text_nature — "hand-corrected" when every page of the issue carries
    #   DIDL OCRConfidencelevel 1.00 (the Meertens Instituut correction
    #   project's pages: the 1618 Courante's ALTO header records "Manual
    #   correction ocr", 2015), else "machine-ocr" — an inference from the
    #   confidence value, declared here. Gothic-type pages OCR badly (the
    #   1631 MMKB08 Courante: confidence 0.33, unreadable) and ride as
    #   upstream gives them.
    #
    # == Fetch and storage
    #
    # One ZipFetch per cone zip (stream mode: the body goes to a staging
    # file, never memory; md5 minted on the fly and checked against the
    # archive page's published md5 before the tree changes), each unpacked
    # into canonical/delpher-newspapers/<zip stem>/ — so a widened cone
    # adds sibling dirs and never disturbs a landed one. Zips are fetched
    # in order, each prepared, guarded and completed before the next: a
    # failure leaves every earlier zip landed and pinned (its
    # Last-Modified answers 304 next time), i.e. the fetch resumes at the
    # ZIP grain; a dropped transfer inside one zip restarts that zip (no
    # byte-range resume — fine for the 0.4–1.1 GB early zips, a known
    # limit for the 5–14 GB 19th-century ones). The 16xx zip unpacks to
    # 5.3 GB (5,665,096,771 B, 114,046 members) — the ALTO pages are most
    # of it; the asset is kept whole (canonical means canonical).
    class DelpherNewspapers < Nabu::Adapter
      SLUG = "delpher-newspapers"
      URN_PREFIX = "urn:nabu:delpher-newspapers:"
      RESOLVER = "https://resolver.kb.nl/resolve?urn=DATA:kranten:"

      Zip = Data.define(:stem, :period, :issues, :bytes, :md5)

      # The archive, in upstream's order. Issue counts: the per-zip rows of
      # upstream's index_delpher_kranten_pd_v1-0_2020.tsv (they match the
      # archive page's stated counts where it states one).
      ZIPS = [
        Zip.new("kranten_pd_16xx", "1618–1699", 8_559, 1_072_874_824, "8a85d73a0ea97665614821ddb155a5e5"),
        Zip.new("kranten_pd_170x", "1700–1709", 4_260, 671_372_347, "693ae105593c978278978f1679232bb1"),
        Zip.new("kranten_pd_171x", "1710–1719", 2_392, 413_500_195, "d748f42a9b80145a5541ff30a74a836d"),
        Zip.new("kranten_pd_172x", "1720–1729", 5_583, 863_335_105, "9d0d9396b30e3ff07d9dd4af15530572"),
        Zip.new("kranten_pd_173x", "1730–1739", 5_932, 906_790_384, nil),
        Zip.new("kranten_pd_174x", "1740–1749", 6_850, 1_167_173_868, nil),
        Zip.new("kranten_pd_175x", "1750–1759", 6_362, 1_058_080_825, nil),
        Zip.new("kranten_pd_176x", "1760–1769", 8_936, 1_482_929_572, nil),
        Zip.new("kranten_pd_177x", "1770–1779", 9_482, 1_707_549_644, nil),
        Zip.new("kranten_pd_178x", "1780–1789", 12_151, 2_576_924_886, nil),
        Zip.new("kranten_pd_179x", "1790–1799", 15_718, 3_818_726_201, nil),
        Zip.new("kranten_pd_180x", "1800–1809", 16_553, 4_617_511_850, nil),
        Zip.new("kranten_pd_181x", "1810–1819", 19_272, 5_204_000_648, nil),
        Zip.new("kranten_pd_182x", "1820–1829", 24_125, 6_241_287_242, nil),
        Zip.new("kranten_pd_183x", "1830–1839", 37_283, 10_527_939_931, nil),
        Zip.new("kranten_pd_184x", "1840–1849", 37_897, 13_387_566_771, nil),
        Zip.new("kranten_pd_1850-4", "1850–1854", 20_773, 8_189_329_377, nil),
        Zip.new("kranten_pd_1855-9", "1855–1859", 22_521, 10_193_147_229, nil),
        Zip.new("kranten_pd_1860-4", "1860–1864", 25_141, 12_687_615_826, nil),
        Zip.new("kranten_pd_1865-9", "1865–1869", 27_362, 14_054_449_819, nil),
        Zip.new("kranten_pd_1870-4", "1870–1874", 24_171, 11_913_118_059, nil),
        Zip.new("kranten_pd_1875-6", "1875–1876", 9_781, 5_405_271_259, nil),
        Zip.new("kranten_pd_1877-9", "1877–1879", 18_912, 11_587_750_677, nil)
      ].freeze

      # The held cone — the 17th century first (the rarest material: the
      # earliest Dutch newspapers). Widening is one line per zip, an
      # adoption-time call (the 18th-century zips are 0.4–3.8 GB each).
      CONE = %w[kranten_pd_16xx].freeze

      ZIP_DIR = /\Akranten_pd_[0-9x-]+\z/
      DDD_FOLDER = /\ADDD_ddd_(\d+)_mpeg21\z/
      BATCH_FOLDER = /\AKRANTEN_([A-Z0-9]+)_\1_(\d+)_mpeg21\z/
      DIDL = "didl.xml"
      ALTO_FILE = /_alto\.xml\z/
      ARTICLE_FILE = /_articletext\.xml\z/
      ROOT_FURNITURE = {
        /\Aindex_kranten_pd_[0-9x-]+\.tsv\z/ => "the zip's issue index (paper, date, zip, folder per issue — " \
                                                "the DIDL's own fields)",
        /\AREADME_newspapers_pd_[0-9x-]+\.txt\z/ => "the zip's English readme",
        /\ALEESMIJ_kranten_pd_[0-9x-]+\.txt\z/ => "the zip's Dutch readme"
      }.freeze

      # dc:language (ISO 639-1) → the house code. Unknown codes quarantine
      # the issue loudly (a census gap, never a guess).
      LANGUAGES = { "nl" => "nld", "fr" => "fra", "de" => "deu", "en" => "eng", "la" => "lat", "it" => "ita",
                    "es" => "spa", "pt" => "por", "fy" => "fry", "ms" => "msa", "id" => "ind",
                    "pap" => "pap", "jv" => "jav" }.freeze

      CORRECTED = 1.0

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Delpher open newspaper archive 1618–1879 (KB, Nationale Bibliotheek van Nederland)",
        license: "Issue texts public domain; the archive as a whole CC BY 4.0. kb.nl dataset page, " \
                 "verbatim: \"These newspapers are free of copyright and may be used without restrictions.\" " \
                 "Delpher archive page: \"De dataset als geheel is vrijgegeven onder een CC-BY 4.0-licentie. " \
                 "… De teksten (OCR, ALTO) van losse krantenafleveringen vallen in het publieke domein\" " \
                 "(read 2026-11-13).",
        license_class: "attribution",
        upstream_url: "https://www.delpher.nl/over-delpher/delpher-open-krantenarchief/" \
                      "wat-zit-er-in-het-delpher-open-krantenarchief",
        parser_family: "delpher-didl",
        credit: "Delpher open newspaper archive (1.0), Creative Commons Attribution 4.0, The Hague, 2017 — " \
                "KB, Nationale Bibliotheek van Nederland."
      )

      def self.manifest = MANIFEST

      # Parallel replay (audited): #parse reads one issue folder — a pure
      # function of its files' bytes; no state crosses parses.
      def self.parallel_parse? = true

      def self.zip(stem) = ZIPS.find { |zip| zip.stem == stem } || raise(ArgumentError, "unknown zip #{stem}")

      def self.zip_url(stem) = "#{RESOLVER}#{stem}.zip"

      def self.materialized_paths = CONE.map { |stem| File.join(stem, Nabu::ZipFetch::STATE_FILE) }

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        CONE.map do |stem|
          Nabu::Adapter::HttpProbeTarget.new(label: "#{stem}.zip", zip_url: zip_url(stem), metadata_url: nil,
                                             state_subdir: stem, state_file: Nabu::ZipFetch::STATE_FILE)
        end
      end

      # The stable upstream id of an issue folder: the DIDL record id less
      # its :mpeg21 suffix ("ddd:010500649", "MMKB08:000213603"); nil for
      # any other name.
      def self.issue_id(folder)
        if (m = DDD_FOLDER.match(folder)) then "ddd:#{m[1]}"
        elsif (m = BATCH_FOLDER.match(folder)) then "#{m[1]}:#{m[2]}"
        end
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        issue_dirs(workdir).each do |zip, dir|
          id = self.class.issue_id(File.basename(dir))
          yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{id}", path: File.join(dir, DIDL),
                                      metadata: { "zip" => zip })
        end
      end

      def discovery_skips(workdir)
        return Nabu::Adapter::DiscoverySkips.new unless Dir.exist?(workdir)

        census = SkipCensus.new
        root = File.expand_path(workdir)
        Dir.glob("**/*", File::FNM_DOTMATCH, base: root).sort.each do |rel|
          next if rel.start_with?("#{ATTIC_DIRNAME}/") || rel == ATTIC_DIRNAME
          next unless File.file?(File.join(root, rel))

          classify(rel, root, census)
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: census.skipped, unrecognized: census.unrecognized.size,
                                          notes: census.notes + census.unrecognized)
      end

      def parse(document_ref)
        didl = document_ref.path
        dir = File.dirname(didl)
        id = self.class.issue_id(File.basename(dir)) or raise Nabu::ParseError, "#{dir}: not an issue folder"
        parser = DelpherDidlParser.new
        issue = parser.read(didl)
        unless issue.record_id == "#{id}:mpeg21"
          raise Nabu::ParseError, "#{didl}: DIDL record #{issue.record_id} does not match its folder (#{id})"
        end

        IssueBuilder.new(urn: "#{URN_PREFIX}#{id}", id: id, dir: dir, issue: issue, parser: parser,
                         zip: zip_of(dir)).call
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        reports = cone_zips.map { |zip| fetch_zip(workdir, zip, progress, force) }
        shas = reports.to_h { |stem, fetch| [self.class.zip_url(stem), fetch.sha] }
        notes = reports.map { |stem, fetch| zip_note(stem, fetch) }
        Nabu::FetchReport.new(sha: shas.values.last, fetched_at: Time.now, notes: notes.join("; "), repos: shas)
      rescue Nabu::ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def cone_zips = CONE.map { |stem| self.class.zip(stem) }

      def fetch_zip(workdir, zip, progress, force)
        dir = File.join(workdir, zip.stem)
        FileUtils.mkdir_p(dir)
        fetch = Nabu::ZipFetch.new(url: self.class.zip_url(zip.stem), dir: dir, progress: progress, stream: true,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME, zip.stem))
        begin
          fetch.prepare!
          verify_md5!(zip, fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        [zip.stem, fetch]
      end

      def verify_md5!(zip, fetch)
        return if fetch.not_modified? || zip.md5.nil? || fetch.md5 == zip.md5

        raise Nabu::FetchError, "#{zip.stem}.zip md5 #{fetch.md5} ≠ the archive page's published #{zip.md5}"
      end

      def zip_note(stem, fetch)
        state = fetch.not_modified? ? "not modified (304)" : "unpacked (sha256 #{fetch.sha})"
        ["#{stem}.zip #{state}", attic_notes(fetch.atticked)].compact.join(", ")
      end

      def issue_dirs(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.children(workdir).grep(ZIP_DIR).sort.flat_map do |zip|
          pattern = File.join(workdir, zip, "[0-9][0-9][0-9][0-9]", "[0-9][0-9]", "[0-9][0-9]", "*", DIDL)
          Dir.glob(pattern).filter_map do |didl|
            dir = File.dirname(didl)
            [zip, File.expand_path(dir)] if self.class.issue_id(File.basename(dir))
          end
        end
      end

      def zip_of(dir)
        parts = dir.split(File::SEPARATOR)
        parts[-5] if parts.size >= 5 && parts[-5].match?(ZIP_DIR)
      end

      # One canonical file's discovery fate.
      def classify(rel, root, census)
        parts = rel.split("/")
        if parts.size == 2 && parts.first.match?(ZIP_DIR)
          root_file(parts, census)
        elsif parts.size == 6 && parts.first.match?(ZIP_DIR) && self.class.issue_id(parts[4]) &&
              parts[1..3].all? { |part| part.match?(/\A\d+\z/) }
          issue_file(rel, parts, root, census)
        else
          census.unrecognized << "#{rel}: unrecognized member of the delpher-newspapers tree"
        end
      end

      def root_file(parts, census)
        zip, name = parts
        return census.skip(:pin, "#{zip}/#{name}: the zip fetcher's own state pin — not upstream content") if
          name == Nabu::ZipFetch::STATE_FILE

        rule = ROOT_FURNITURE.find { |pattern, _| name.match?(pattern) }
        return census.unrecognized << "#{zip}/#{name}: unrecognized file at the zip root" unless rule

        census.skip(:root, "#{zip}/#{name}: #{rule.last} — skipped by rule")
      end

      def issue_file(rel, parts, root, census)
        name = parts.last
        return if name == DIDL || (name.match?(ARTICLE_FILE) && File.file?(File.join(root, *parts[0..4], DIDL)))
        return census.alto(parts.first) if name.match?(ALTO_FILE)

        census.unrecognized << "#{rel}: unrecognized file in an issue folder"
      end

      # Tallies the skip rules; ALTO pages aggregate into one note per zip.
      class SkipCensus
        attr_reader :skipped, :unrecognized

        def initialize
          @skipped = 0
          @unrecognized = []
          @notes = []
          @alto = Hash.new(0)
        end

        def skip(_rule, note)
          @skipped += 1
          @notes << note
        end

        def alto(zip)
          @skipped += 1
          @alto[zip] += 1
        end

        def notes
          @notes + @alto.sort.map do |zip, count|
            "#{zip}: #{count} ALTO page file(s) — word coordinates of the page scans, the same OCR the " \
              "articletext files carry by article — skipped by rule"
          end
        end
      end

      # One issue → a Document: articles as passages, the DIDL record as
      # metadata (the class note's axes).
      class IssueBuilder
        def initialize(urn:, id:, dir:, issue:, parser:, zip:)
          @urn = urn
          @id = id
          @dir = dir
          @issue = issue
          @parser = parser
          @zip = zip
          @fields = issue.fields
        end

        def call
          language = language_code
          passages, empty, missing = article_passages(language)
          raise Nabu::ParseError, "#{@dir}: no article carries OCR text" if passages.empty?

          document = Nabu::Document.new(urn: @urn, language: language, canonical_path: File.join(@dir, DIDL),
                                        title: title, metadata: metadata(empty, missing))
          passages.each { |passage| document << passage }
          document
        end

        private

        def title
          [@fields["paper"], @fields["date"]].compact.join(", ").then { |t| t.empty? ? nil : t }
        end

        def language_code
          first = @fields["languages"].first
          raise Nabu::ParseError, "#{@dir}: the DIDL carries no dc:language" unless first

          LANGUAGES.fetch(first) { raise Nabu::ParseError, "#{@dir}: dc:language #{first.inspect} has no house code" }
        end

        # One passage per article with OCR text, in DIDL order; the
        # citations of the articles whose OCR is empty, and of the
        # articles upstream never carried text for (the 2017 zip's
        # packaging gaps, 4 issues in the 16xx cone: a DIDL article
        # entry without an articletext resource, or a named file absent
        # from the folder — the same user-visible outcome as empty OCR,
        # so both ride missing_articles instead of quarantining the
        # issue's present articles away; the dump is frozen upstream,
        # so no report can repair it).
        def article_passages(language)
          passages = []
          empty = []
          missing = []
          @issue.articles.each do |article|
            path = article_path(article)
            next missing << "a#{article.number}" unless path

            text = @parser.read_article(path)
            next empty << "a#{article.number}" if text.paragraphs.empty?

            passages << Nabu::Passage.new(urn: "#{@urn}:a#{article.number}", language: language,
                                          text: text.paragraphs.join("\n"), sequence: passages.size,
                                          annotations: annotations(article, text))
          end
          [passages, empty, missing]
        end

        # The article's on-disk text file, or nil when upstream carries
        # none (no resource in the DIDL, or the named member absent).
        def article_path(article)
          return nil unless article.file

          path = File.join(@dir, article.file)
          File.file?(path) ? path : nil
        end

        def annotations(article, text)
          { "article" => article.id, "subject" => article.subject, "title" => text.title || article.title,
            "pages" => article.pages }.reject { |_, value| value.nil? || value == [] }
        end

        def metadata(empty, missing)
          {
            "delpher_id" => @id, "record_id" => @issue.record_id,
            "resolver_url" => "http://resolver.kb.nl/resolve?urn=#{@issue.record_id}",
            "zip" => @zip, "paper" => @fields["paper"], "issue_date" => @fields["date"], "date" => date_hash,
            "place" => @fields["place"], "distribution" => @fields["distribution"],
            "publisher" => @fields["publisher"], "languages" => languages,
            "issue_number" => @fields["issue_number"], "temporal" => @fields["temporal"],
            "title_run" => @fields["title_run"], "alternative_titles" => @fields["alternative_titles"],
            "ppn" => @fields["ppn"], "holding" => @fields["holding"], "collections" => @fields["collections"],
            "years_digitized" => @fields["years_digitized"], **page_fields,
            "article_count" => @issue.articles.size, "subjects" => subjects,
            "empty_articles" => empty, "missing_articles" => missing,
            "unlisted_article_files" => unlisted_files
          }.reject { |_, value| value.nil? || value == [] || value == {} }
        end

        def date_hash
          raw = @fields["date"]
          year = raw && raw[/\A(\d{4})-\d\d-\d\d\z/, 1]
          return nil unless year

          { "not_before" => Integer(year, 10), "not_after" => Integer(year, 10), "raw" => raw,
            "basis" => "the issue's own date (DIDL dc:date)" }
        end

        def languages
          @fields["languages"].map { |code| LANGUAGES.fetch(code, code) }
        end

        def page_fields
          confidences = @issue.pages.map(&:ocr_confidence)
          corrected = !confidences.empty? && confidences.all? { |value| value == CORRECTED }
          { "page_count" => @issue.pages.size, "ocr_confidence" => (confidences unless confidences.all?(&:nil?)),
            "text_nature" => corrected ? "hand-corrected" : "machine-ocr" }
        end

        def subjects
          @issue.articles.filter_map(&:subject).tally.sort.to_h
        end

        def unlisted_files
          listed = @issue.articles.filter_map(&:file)
          Dir.children(@dir).grep(ARTICLE_FILE).sort - listed
        end
      end
    end
  end
end
