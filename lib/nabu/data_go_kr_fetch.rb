# frozen_string_literal: true

require "json"

module Nabu
  # The data.go.kr acquisition choreography (P78-1 — resolved live
  # 2026-08-18, .docs/p78-plan.md §Acquisition): the Korean open-data
  # portal serves its file datasets from a stable public endpoint, no
  # login, no captcha — but the terminal atchFileId BUMPS on every
  # upstream file replacement, so the RESOLUTION, not the id, is the
  # contract. Three steps, mirroring the portal's own JS
  # (script_fileDetail.js fn_fileDataDown → script_cmmFunction.js
  # fn_fileDataDownload):
  #
  #   1. GET /data/<data_pk>/fileData.do — the dataset page; the download
  #      button's onclick carries the uddi detail key.
  #   2. GET /tcs/dss/selectFileDataDownload.do?publicDataPk=<data_pk>&
  #      publicDataDetailPk=<uddi>&fileDetailSn=1 — JSON whose top-level
  #      atchFileId names the current file.
  #   3. The zip lives at /cmm/cmm/fileDownload.do?atchFileId=<id>&
  #      fileDetailSn=<sn> — returned as the resolved URL for ZipFetch
  #      to run its normal choreography against.
  #
  # There IS a check-limit/captcha lane in the portal JS — never
  # triggered live; a resolution that comes back file-less raises
  # loudly rather than fetching an HTML page as a corpus (an EMPTY
  # atchFileId yields a 2,682-byte page, measured).
  module DataGoKrFetch
    PORTAL = "https://www.data.go.kr"

    module_function

    # The current direct-download URL for file dataset +data_pk+.
    def resolve(data_pk, http: Nabu::ZipFetch.default_http)
      uddi = detail_key(data_pk, http)
      atch_file_id, file_detail_sn = file_id(data_pk, uddi, http)
      "#{PORTAL}/cmm/cmm/fileDownload.do?atchFileId=#{atch_file_id}&fileDetailSn=#{file_detail_sn}"
    end

    def detail_key(data_pk, http)
      page = get!(http, "#{PORTAL}/data/#{data_pk}/fileData.do", data_pk)
      match = page.match(/fn_fileDataDown\('#{Regexp.escape(data_pk)}',\s*'(uddi:[^']+)'/)
      match or raise Nabu::FetchError,
                     "data.go.kr #{data_pk}: no download button on the dataset page — " \
                     "the portal shape changed or the dataset moved"
      match[1]
    end

    def file_id(data_pk, uddi, http)
      url = "#{PORTAL}/tcs/dss/selectFileDataDownload.do" \
            "?publicDataPk=#{data_pk}&publicDataDetailPk=#{uddi}&fileDetailSn=1"
      body = get!(http, url, data_pk)
      json = JSON.parse(body)
      id = json["atchFileId"]
      if json["status"] != true || id.nil? || id.empty?
        raise Nabu::FetchError, "data.go.kr #{data_pk}: file resolution refused " \
                                "(status #{json['status'].inspect}, error #{json['error'].inspect})"
      end
      [id, json["fileDetailSn"] || "1"]
    rescue JSON::ParserError
      raise Nabu::FetchError, "data.go.kr #{data_pk}: file resolution answered non-JSON (portal shape changed?)"
    end

    def get!(http, url, data_pk)
      response = http.get(url)
      raise Nabu::FetchError, "data.go.kr #{data_pk}: HTTP #{response.status} for #{url}" unless response.status == 200

      response.body.to_s
    end
  end
end
