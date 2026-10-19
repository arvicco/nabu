# frozen_string_literal: true

require "digest"
require "fileutils"

require_relative "../store/timeline_builder/itkc_catalog_records"

module Nabu
  module Adapters
    # itkc-catalog — the 한국고전종합DB 서지 (bibliographic) catalog of the
    # Institute for the Translation of Korean Classics, registered as a
    # FEATURE MODULE: discover mints NO documents; the held records feed
    # the timeline's author-era lane (Store::TimelineBuilder::
    # ItkcAuthorDates), which dates okhc's klc munjip records (652,405 —
    # the 한국문집총간 mass) and the held itkc fascicles by their author's
    # attested life years. Reader + band rules:
    # Store::TimelineBuilder::ItkcCatalogRecords.
    #
    # == The channel
    #
    # The ITKC OpenAPI search endpoint, keyless, no account or session
    # (https://db.itkc.or.kr/openapi/search, its own help page
    # db.itkc.or.kr/etc/openAPI?type=page2): each 서지 section answers the
    # whole catalog to an empty keyword, paged by start/rows, the server
    # capping rows at 1000 (a rows=1300 request answered 1000, verified
    # 2026-10-19). Three sections, 5 requests in all at 1 req/s:
    # MO_SJ 한국문집총간 (1,259 works — exactly the 1,259 munjip ids the okhc
    # klc slice carries), GO_SJ 고전원문 (257), KP_SJ 한국고전총간 (24).
    # Each response page is held verbatim at <section>/<start>.xml — the
    # API's own bytes, nothing synthesized beside them. A fetch is
    # all-or-nothing: every page must parse, name its section and carry
    # exactly the records its offset promises before anything is written;
    # a section that would lose more than the mass-deletion threshold of
    # its held records trips the breaker (force overrides); a page the new
    # census no longer reaches moves to the attic, never deleted.
    #
    # == Terms (read first-hand 2026-10-19 — recorded verbatim)
    #
    # - The OpenAPI page (db.itkc.or.kr/etc/openAPI?type=page1): "한국고전
    #   종합DB에서 제공하는 고전번역서, 한국문집총간, 조선왕조실록 등 전통
    #   고전자료에 대한 검색 결과를 전달하는 API를 제공합니다. 소중한 국가
    #   정보화자원을 외부에서 이용하여 다양한 부가 서비스를 만드실 수
    #   있습니다." — no license instrument beyond that invitation.
    # - The institute's 저작권정책 (itkc.or.kr, menuId=112, 최종 수정일
    #   2021-07-29) covers "모든 콘텐츠(웹문서, 첨부파일, DB정보 등)":
    #   unauthorized reproduction and distribution prohibited in principle;
    #   any use earning revenue needs prior agreement; source credit always.
    # - The data.go.kr dataset 3074298 (한국고전번역원_한국문집총간_20240830,
    #   CSV, no login) carries "이용허락범위 제한 없음" — but holds only
    #   연번 + 제목 (1,251 dataset titles, no ids, no authors, no years), so
    #   it cannot carry this join; the same 저자/생년/몰년/원문간행년 fields
    #   DO ride, under that open grant, in the 서지 sidecars of the itkc
    #   source's data.go.kr munjip datasets (ITKC_MO_1250A.xml).
    # What Nabu derives here is facts — an author's birth and death years
    # as a date band on a held document — never the catalog's text or
    # structure redistributed. Class nc (the policy's no-revenue clause)
    # until the institute is asked; the derived bands ride the target
    # documents' own license classes.
    class ItkcCatalog < Nabu::Adapter
      RECORDS = Nabu::Store::TimelineBuilder::ItkcCatalogRecords
      API_URL = "https://db.itkc.or.kr/openapi/search"
      SECTIONS = RECORDS::SECTIONS
      # The server's own cap on rows (verified 2026-10-19).
      PAGE_ROWS = 1000
      # One request per second — the polite pace for an institute's live
      # search service; the whole catalog is 5 requests.
      DELAY = 1.0
      PAGE_NAME = "%04d.xml"

      MANIFEST = Nabu::SourceManifest.new(
        id: RECORDS::SLUG,
        name: "ITKC 한국고전종합DB 서지 catalog — author-era instrument (OpenAPI MO/GO/KP 서지)",
        license: "ITKC OpenAPI (db.itkc.or.kr/etc/openAPI, read 2026-10-19): \"소중한 " \
                 "국가정보화자원을 외부에서 이용하여 다양한 부가 서비스를 만드실 수 있습니다\" — " \
                 "no further instrument; the institute's 저작권정책 (2021-07-29) reserves DB " \
                 "content against redistribution and revenue use. Facts only are derived (author " \
                 "birth/death years as date bands). The data.go.kr munjip list (dataset 3074298) " \
                 "is 이용허락범위 제한 없음 but carries titles only. Class nc pending the institute's word",
        license_class: "nc",
        upstream_url: "https://db.itkc.or.kr/etc/openAPI?type=page1",
        parser_family: "itkc-openapi-xml"
      )

      def self.manifest
        MANIFEST
      end

      # A crawl-style fetcher with no state file: HEAD the endpoint for
      # reachability; drift honestly reads unknown (the kitab posture).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "openapi MO_SJ", zip_url: page_url("MO_SJ", 0, PAGE_ROWS), metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      def self.page_url(section, start, rows)
        "#{API_URL}?secId=#{section}&start=#{start}&rows=#{rows}"
      end

      def initialize(delay: DELAY, page_rows: PAGE_ROWS, http: Nabu::ZipFetch.default_http,
                     sleeper: ->(seconds) { sleep(seconds) })
        super()
        @delay = delay
        @page_rows = page_rows
        @http = http
        @sleeper = sleeper
        @requests = 0
      end

      # A feature module mints no documents (the cigs/cbdb shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: itkc-catalog is a bibliographic instrument, not a text " \
                          "source — its records band the okhc/itkc timelines; parse is unreachable"
      end

      def fetch(workdir, progress: nil, force: false)
        fetched = SECTIONS.to_h { |section| [section, fetch_section(section, progress)] }
        fetched.each { |section, pages| guard_shrink!(workdir, section, pages, force: force) }
        atticked = fetched.flat_map { |section, pages| write_section!(workdir, section, pages) }
        counts = fetched.map { |section, pages| "#{section} #{pages.sum { |page| page[:count] }}" }
        notes = ["#{counts.join(' · ')} records (#{@requests} requests)", attic_notes(atticked)]
        FetchReport.new(sha: catalog_sha(fetched), fetched_at: Time.now, notes: notes.compact.join("; "))
      end

      private

      # Every page of one section, validated, in memory: [{start:, body:, count:}].
      def fetch_section(section, progress)
        pages = []
        start = 0
        total = nil
        loop do
          body = get(self.class.page_url(section, start, @page_rows))
          page = read_page(section, start, body)
          total ||= page.total
          expected = (total - start).clamp(0, @page_rows)
          unless page.records.size == expected
            raise Nabu::FetchError, "itkc-catalog #{section} start #{start}: #{page.records.size} of " \
                                    "#{expected} records answered (totalCount #{total}) — refused"
          end
          pages << { start: start, body: body, count: page.records.size }
          progress&.call("itkc-catalog #{section}: #{start + page.records.size}/#{total}\n")
          start += @page_rows
          break if start >= total
        end
        pages
      end

      def read_page(section, start, body)
        page = RECORDS.parse_page(body)
        return page if page.section == section && page.start == start && page.total.positive?

        raise Nabu::FetchError, "itkc-catalog #{section} start #{start}: the answer names " \
                                "#{page.section.inspect} start #{page.start}, totalCount #{page.total} — refused"
      rescue Nabu::ParseError => e
        raise Nabu::FetchError, "itkc-catalog #{section} start #{start}: #{e.message}"
      end

      def get(url)
        @sleeper.call(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        response, = Nabu::RedirectFollow.get(url, http: @http, error: Nabu::FetchError,
                                                  headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      end

      # The section-grain mass-deletion breaker: the held records of one
      # section against the fetched census.
      def guard_shrink!(workdir, section, pages, force:)
        return if force

        held = RECORDS.page_paths(workdir)
                      .select { |path| File.basename(File.dirname(path)) == section }
                      .sum { |path| RECORDS.parse_page(File.read(path)).records.size }
        fetched = pages.sum { |page| page[:count] }
        lost = held - fetched
        return if lost <= MASS_DELETION_THRESHOLD * held

        raise SyncAborted.new(existing_count: held, would_withdraw_count: lost,
                              threshold: MASS_DELETION_THRESHOLD)
      rescue Nabu::ParseError
        nil # an unreadable held page is replaced, never a reason to refuse
      end

      # Write the section's pages (tmp + rename each); a held page the new
      # census no longer names moves to the attic. Returns the atticked
      # pages' workdir-relative paths.
      def write_section!(workdir, section, pages)
        dir = File.join(workdir, section)
        FileUtils.mkdir_p(dir)
        names = pages.map do |page|
          name = format(PAGE_NAME, page[:start])
          File.binwrite(File.join(dir, "#{name}.tmp"), page[:body])
          File.rename(File.join(dir, "#{name}.tmp"), File.join(dir, name))
          name
        end
        stale = Dir.children(dir).sort.select { |name| name.end_with?(".xml") } - names
        stale.each do |name|
          attic = File.join(workdir, ATTIC_DIRNAME, section)
          FileUtils.mkdir_p(attic)
          File.rename(File.join(dir, name), File.join(attic, name))
        end
        stale.map { |name| File.join(section, name) }
      end

      def catalog_sha(fetched)
        digest = Digest::SHA256.new
        fetched.each_value { |pages| pages.each { |page| digest << page[:body] } }
        digest.hexdigest
      end
    end
  end
end
