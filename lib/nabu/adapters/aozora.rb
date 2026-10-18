# frozen_string_literal: true

require "csv"
require_relative "aozora_ruby_parser"

module Nabu
  module Adapters
    # Aozora Bunko 青空文庫 (P38-3) — the Japanese public-domain library:
    # 17,831 works (P38-0 survey census), of which 17,343 are copyright-
    # expired (作品著作権フラグ=なし) and ~17,488 PD works carry a plain-text
    # file. Upstream is the aozorabunko GitHub mirror: a 22.8 GB repo whose
    # TEXT is only ~210 MB of per-work zips under
    # cards/<authorID>/files/<workID>_ruby_<hash>.zip — hence the sparse
    # GitFetch cone below. Canonical = the zips (unzipped on read by the
    # aozora-ruby parser family) + the machine index.
    #
    # == Scope: D38-a (owner ruling 2026-07-21) — PD text only
    #
    # Discovery is driven by the index CSV (index_pages/
    # list_person_all_extended_utf8.csv, upstream-zipped — both forms read),
    # one row per person×work, deduped to unique works (作品ID). A work is
    # discovered iff 作品著作権フラグ=なし AND it has a text-file URL; the
    # 488 in-copyright works are EXCLUDED BY DISCOVERY BEFORE ANY FILE
    # ACCESS (skip-by-rule, censused in discovery_skips — their zips sit in
    # the license-blind sparse cone but are never opened). A PD work whose
    # zip is MISSING from the checkout is loud at parse (quarantine), never
    # a silent skip.
    #
    # ATTIC HONESTY: discovery is index-driven, and the attic holds no
    # index — so a work upstream scraps (zip atticked, index row gone) is
    # NOT rediscovered from the attic; its bytes are preserved there and its
    # catalog rows follow the normal withdrawal path (text retained, never
    # deleted). Reconciling atticked zips against historical index rows is a
    # future decision, journaled in the P38-3 report — not guessed here.
    #
    # == Index metadata (the aggressive-mining law)
    #
    # Per work, beyond title/orthography/NDC: "persons" (every person row,
    # role verbatim, ref "aozora:<人物ID>" into the "aozora" person-index
    # slice the same index derives — Nabu::AozoraPersons), "authors"/
    # "translators" names and "author_ids"/"translator_ids" refs (the facet
    # lane), "original_title" (原題, translations), "first_published"
    # (初出 verbatim) and "date" — 初出's year(s) as class composition, else
    # the 底本 first-edition year as class edition (#work_date).
    #
    # == Identity (FROZEN minting)
    #
    # Document per work: urn:nabu:aozora:<作品ID> (zero-padded upstream id,
    # e.g. 056078). Passages: <doc-urn>:<n> ordinals at the parser's
    # one-passage-per-body-line grain (see AozoraRubyParser). ref.id is the
    # document urn; the zip path is resolved from the row's own 図書カードURL
    # author-id segment + text-URL basename.
    #
    # == License (取り扱い規準, aozora.gr.jp/guide/kijyunn.html, P38-0)
    #
    # PD works, verbatim: 「ファイルは、有償・無償であるかを問わず、自由に
    # 複製・再配布・共有することができます。」 — public domain → class open
    # (the vulgate precedent; the survey's "public_domain" label maps to the
    # registry's open class). Aozora asks that title/author/translator and
    # the 底本 provenance be kept intact — the parser carries the colophon
    # as document metadata, and the manifest records the request.
    class Aozora < Nabu::Adapter
      REPO_URL = "https://github.com/aozorabunko/aozorabunko"
      URN_PREFIX = "urn:nabu:aozora:"

      # The sparse text cone (GitFetch P26-0 glob patterns, pinned in
      # git_fetch_test): the per-work text zips (ruby + no-ruby variants) and
      # the zipped machine index — ~210 MB of a 22.8 GB repo. Card pages,
      # per-work XHTML, .ebk binaries and site HTML never materialize. The
      # cone is LICENSE-BLIND (it fetches in-copyright zips too); the D38-a
      # exclusion lives in discovery, which never opens them.
      SPARSE_CONE = [
        "cards/*/files/*_ruby_*.zip",
        "cards/*/files/*_txt_*.zip",
        "index_pages/list_person_all_extended_utf8.zip"
      ].freeze

      INDEX_DIR = "index_pages"
      INDEX_CSV = "list_person_all_extended_utf8.csv"
      INDEX_ZIP = "list_person_all_extended_utf8.zip"

      # A work's text-zip basename, upstream's own grammar
      # (<workID>_ruby_<hash>.zip / <workID>_txt_<hash>.zip).
      TEXT_ZIP = /\A\d+_(?:ruby|txt)_\d+\.zip\z/
      CARD_URL_AUTHOR = %r{/cards/(?<author>\d+)/card}

      # Index columns (the 55-column header, P38-0 survey §1).
      COL_WORK_ID = "作品ID"
      COL_TITLE = "作品名"
      COL_NDC = "分類番号"
      COL_ORTHOGRAPHY = "文字遣い種別"
      COL_COPYRIGHT = "作品著作権フラグ"
      COL_CARD_URL = "図書カードURL"
      COL_SURNAME = "姓"
      COL_GIVEN = "名"
      COL_ROLE = "役割フラグ"
      COL_TEXT_URL = "テキストファイルURL"
      COL_ENCODING = "テキストファイル符号化方式"
      COL_PERSON_ID = "人物ID"
      COL_ORIGINAL_TITLE = "原題"
      COL_FIRST_PUBLISHED = "初出"
      COL_BASE_EDITION_YEAR = "底本初版発行年1"
      PD_FLAG = "なし"
      PERSON_REF_PREFIX = "aozora:"

      # Index date grammar (#publication_years). Japanese era → the
      # Gregorian year before its first year (明治1 = 1868); 元年 is year 1.
      ERA_BASE = { "明治" => 1867, "大正" => 1911, "昭和" => 1925, "平成" => 1988, "令和" => 2018 }.freeze
      WESTERN_YEAR = /(\d{4})\s*(?:[（(]|年)/
      ERA_YEAR = /(明治|大正|昭和|平成|令和)\s*(\d{1,2}|元)年/

      MANIFEST = Nabu::SourceManifest.new(
        id: "aozora",
        name: "Aozora Bunko 青空文庫 — Japanese public-domain library (ruby-annotated text)",
        license: "Public domain (copyright-expired works only, 作品著作権フラグ=なし; D38-a). " \
                 "取り扱い規準 verbatim: 「ファイルは、有償・無償であるかを問わず、自由に複製・" \
                 "再配布・共有することができます。」 Attribution requested, not required: keep " \
                 "title/author/translator and the 底本 (base-text) colophon intact — carried as " \
                 "document metadata. In-copyright works (=あり) are excluded from discovery.",
        license_class: "open",
        upstream_url: REPO_URL,
        parser_family: "aozora-ruby"
      )

      def self.manifest
        MANIFEST
      end

      # The index's person columns (人物ID + names + life dates) project
      # into the "aozora" person-index slice at sync and rebuild
      # (Nabu::AozoraPersons; the ElephantinePersons mold).
      def self.person_index_producer? = true

      def self.person_index_producer(catalog:)
        Nabu::AozoraPersons::Producer.new(catalog: catalog)
      end

      # One ref per unique PD work with a text file, sorted by work id
      # (D38-a: the in-copyright exclusion happens HERE, before any file
      # access). No index (the attic case, or an unsynced dir) = no refs.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        works(workdir).each do |work|
          next unless discoverable?(work)

          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{work[:id]}",
            path: work[:zip_path], metadata: work[:metadata]
          )
        end
      end

      # The census (P11-7): index works excluded by rule (in-copyright, or
      # no text file) are benign skips; a text zip ON DISK that no index row
      # accounts for is unrecognized — loud.
      def discovery_skips(workdir)
        all = works(workdir)
        skipped = all.count { |work| !discoverable?(work) }
        indexed = all.filter_map { |work| work[:zip_path] }.to_set
        strays = disk_zips(workdir).reject { |path| indexed.include?(path) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: skipped, unrecognized: strays.size,
          notes: strays.map { |path| "text zip with no index row: #{path}" }
        )
      end

      def parse(document_ref)
        unless File.file?(document_ref.path)
          raise Nabu::ParseError,
                "#{document_ref.id} (#{document_ref.metadata['index_title']}): PD work's text zip " \
                "missing from the sparse checkout: #{document_ref.path}"
        end

        AozoraRubyParser.new.parse(
          document_ref.path, urn: document_ref.id, metadata: document_ref.metadata
        )
      end

      # Sparse non-destructive clone/pull (attic + mass-deletion breaker
      # via the shared git path). Upstream is pushed continuously; re-syncs
      # are owner-fired (sync_policy manual).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_CONE)
      end

      # The index rows, from the plain CSV (the fixture form) or the
      # upstream zip (unzip on read, the work-zip discipline). Upstream
      # ships the CSV UTF-8 with BOM. Public: Nabu::AozoraPersons reads
      # the person columns of the same rows.
      def index_rows(workdir)
        csv = File.join(workdir, INDEX_DIR, INDEX_CSV)
        zip = File.join(workdir, INDEX_DIR, INDEX_ZIP)
        content =
          if File.file?(csv)
            File.read(csv, encoding: "bom|utf-8")
          elsif File.file?(zip)
            unzip_index(zip)
          end
        return [] if content.nil?

        CSV.parse(content, headers: true).map(&:to_h)
      rescue CSV::MalformedCSVError => e
        raise Nabu::FetchError, "#{manifest.id}: malformed index CSV under #{workdir}: #{e.message}"
      end

      # [earliest, latest] Gregorian year an index date string states, or
      # nil. The censused grammar: "1927（昭和2）年1月号" (the Gregorian
      # year before its era gloss, full- or half-width parentheses),
      # "1903年", a bare "1913", serial runs "1934（昭和9）年10月～1935
      # （昭和10）年12月" (both ends join the envelope), and era-only
      # "昭和15年2月8日" (converted exactly — the era year is the claim).
      def self.publication_years(text)
        text = text.to_s.strip
        years = text.scan(WESTERN_YEAR).flatten.map { |year| Integer(year, 10) }
        years = [Integer(text, 10)] if years.empty? && text.match?(/\A\d{4}\z/)
        if years.empty?
          years = text.scan(ERA_YEAR).map { |era, n| ERA_BASE.fetch(era) + (n == "元" ? 1 : Integer(n, 10)) }
        end
        return nil if years.empty?

        years.minmax
      end

      private

      # Test seam (the house pattern): fetch tests point this at a local rig.
      def repo_url
        REPO_URL
      end

      # -- the index ------------------------------------------------------------

      # Unique works from the person×work index, in work-id order. Each:
      # { id:, zip_path: (nil when unmappable), metadata: }.
      def works(workdir)
        rows = index_rows(workdir)
        return [] if rows.empty?

        rows.group_by { |row| row[COL_WORK_ID] }
            .reject { |id, _| id.nil? }
            .sort
            .map { |id, group| build_work(workdir, id, group) }
      end

      def discoverable?(work)
        work[:pd] && !work[:zip_path].nil?
      end

      def build_work(workdir, id, rows)
        first = rows.first
        zip = text_zip_path(workdir, first)
        {
          id: id, pd: first[COL_COPYRIGHT] == PD_FLAG, zip_path: zip,
          metadata: {
            "work_id" => id,
            "index_title" => first[COL_TITLE],
            "orthography" => first[COL_ORTHOGRAPHY],
            "card_url" => first[COL_CARD_URL],
            "ndc" => first[COL_NDC],
            "authors" => person_names(rows, "著者"),
            "translators" => person_names(rows, "翻訳者"),
            "persons" => persons(rows),
            "author_ids" => person_refs(rows, "著者"),
            "translator_ids" => person_refs(rows, "翻訳者"),
            "original_title" => presence(first[COL_ORIGINAL_TITLE]&.strip),
            "first_published" => presence(first[COL_FIRST_PUBLISHED]&.strip),
            "date" => work_date(first),
            # Upstream's own per-file charset declaration (parser honors it,
            # defaults CP932); carried only when non-empty (blank = CP932).
            "file_encoding" => presence(first[COL_ENCODING])
          }.compact
        }
      end

      # Every person row of the work, index order: {"ref" =>
      # "aozora:<人物ID>" (the "aozora" person-index slice — Nabu::
      # AozoraPersons; the prefix is OUR namespace), "name" (姓 名),
      # "role" (役割フラグ verbatim: 著者 / 翻訳者 / 編者 / 校訂者 /
      # その他)}.
      def persons(rows)
        list = rows.filter_map do |row|
          id = row[COL_PERSON_ID].to_s.strip
          next if id.empty?

          { "ref" => "#{PERSON_REF_PREFIX}#{id}", "name" => person_name(row),
            "role" => presence(row[COL_ROLE].to_s.strip) }.compact
        end
        list.empty? ? nil : list
      end

      def person_refs(rows, role)
        refs = rows.select { |row| row[COL_ROLE] == role }
                   .map { |row| row[COL_PERSON_ID].to_s.strip }.reject(&:empty?)
                   .map { |id| "#{PERSON_REF_PREFIX}#{id}" }.uniq
        refs.empty? ? nil : refs
      end

      # The work's dating claim (MetadataDates :structured): 初出 — the
      # work's FIRST PUBLICATION (10,679 of 17,831 works) — dates the
      # work itself, class composition (for a translation, the
      # translation's own first appearance); without one, the 底本's first
      # edition year (底本初版発行年1) is the print year of the edition the
      # text follows, class edition (the Perseus imprint-year precedent).
      # Strings naming no year ("不詳", a bare magazine title) mint nothing.
      def work_date(row)
        [[COL_FIRST_PUBLISHED, "composition"], [COL_BASE_EDITION_YEAR, "edition"]].each do |column, klass|
          raw = row[column].to_s.strip
          years = self.class.publication_years(raw) or next

          return { "not_before" => years.first, "not_after" => years.last, "raw" => raw, "class" => klass }
        end
        nil
      end

      def person_name(row)
        [row[COL_SURNAME], row[COL_GIVEN]].compact.map(&:strip).reject(&:empty?).join(" ")
      end

      def presence(value)
        value unless value.nil? || value.empty?
      end

      def person_names(rows, role)
        names = rows.select { |row| row[COL_ROLE] == role }
                    .map { |row| [row[COL_SURNAME], row[COL_GIVEN]].compact.reject(&:empty?).join(" ") }
                    .reject(&:empty?)
        names.empty? ? nil : names
      end

      # cards/<authorID>/files/<zip basename>: authorID from the row's own
      # 図書カードURL path, basename from the text-file URL. nil when the row
      # has no text URL or an off-grammar one (censused, never guessed).
      def text_zip_path(workdir, row)
        text_url = row[COL_TEXT_URL]
        return nil if text_url.nil? || text_url.empty?

        author = row[COL_CARD_URL].to_s[CARD_URL_AUTHOR, :author]
        basename = File.basename(text_url)
        return nil unless author && TEXT_ZIP.match?(basename)

        File.expand_path(File.join(workdir, "cards", author, "files", basename))
      end

      def unzip_index(zip)
        # In-process via Nabu::ZipReader (P39-3, the same subprocess removal as
        # the work zips). Member names are handled as BINARY and matched
        # byte-wise (/\u2026/n) \u2014 the P38-i1 rule (never decode them). The index
        # member is ASCII today, but the same discipline applies uniformly.
        reader = Nabu::ZipReader.new(File.binread(zip))
        members = reader.entries.select { |entry| entry.name.match?(/\.csv\z/in) }
        unless members.size == 1
          raise Nabu::FetchError, "#{manifest.id}: expected one CSV in #{zip}, found #{members.map(&:name).inspect}"
        end

        reader.extract(members.first).force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")
      rescue Nabu::ZipReader::Error, SystemCallError => e
        raise Nabu::FetchError, "#{manifest.id}: unreadable index zip #{zip} (#{e.message})"
      end

      def disk_zips(workdir)
        Dir.glob(File.join(workdir, "cards", "*", "files", "*.zip"))
           .select { |path| TEXT_ZIP.match?(File.basename(path)) }
           .map { |path| File.expand_path(path) }
           .sort
      end
    end
  end
end
