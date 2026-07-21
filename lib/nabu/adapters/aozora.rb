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
      PD_FLAG = "なし"

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
            "translators" => person_names(rows, "翻訳者")
          }.compact
        }
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

      # The index rows, from the plain CSV (the fixture form) or the
      # upstream zip (unzip on read, the work-zip discipline). Upstream
      # ships the CSV UTF-8 with BOM.
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

      def unzip_index(zip)
        members = Shell.run("unzip", "-Z1", zip).split("\n").grep(/\.csv\z/i)
        unless members.size == 1
          raise Nabu::FetchError, "#{manifest.id}: expected one CSV in #{zip}, found #{members.inspect}"
        end

        Shell.run("unzip", "-p", zip, members.first).force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")
      rescue Shell::Error => e
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
