# frozen_string_literal: true

require "nokogiri"
require "uri"

require_relative "../errors"
require_relative "../normalize"

module Nabu
  module Adapters
    # The NDL Search bib-record family behind the ndl-kotenseki join: the
    # 国立国会図書館サーチ SRU interface (searchRetrieve, recordSchema
    # dcndl — the richest record shape: NDC / NDLC classification,
    # authority-form creators with life-years and authority URIs, W3CDTF
    # issued years) queried for many digital-collection PIDs at once with
    # one CQL OR (`anywhere="info:ndljp/pid/<pid>" OR …`). A record belongs
    # to a PID when it links the digital-collection item
    # (https://dl.ndl.go.jp/pid/<pid>) — never by a looser mention.
    #
    # Pure functions: the paced crawl, ledger and sidecar placement live in
    # NdlKotenseki#fetch; parse reads the sidecar back through .read.
    module NdlSearchBib
      SRU_URL = "https://ndlsearch.ndl.go.jp/api/sru"
      # The interface's page cap; a batch of PIDs answering more records
      # pages through startRecord.
      MAX_RECORDS = 200

      SRW = "http://www.loc.gov/zing/srw/"
      NS = {
        "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
        "dc" => "http://purl.org/dc/elements/1.1/",
        "dcterms" => "http://purl.org/dc/terms/",
        "dcndl" => "http://ndl.go.jp/dcndl/terms/",
        "foaf" => "http://xmlns.com/foaf/0.1/"
      }.freeze
      W3CDTF = "http://purl.org/dc/terms/W3CDTF"
      NDLBIBID = "http://ndl.go.jp/dcndl/terms/NDLBibID"
      # The digital-collection unknown-date placeholder (the census'
      # DATE_SENTINEL — the same bibliography's "1000") mints no year.
      DATE_SENTINEL = 1000

      # One searchRetrieve page: the hit total, the records' RDF strings
      # (recordData, unescaped — upstream's bytes for each record) and the
      # next start position when the answer is partial.
      Page = Data.define(:total, :records, :next_position)

      # A creator's trailing life span: "1801-1880", "-1880", "1801-",
      # "774-835", "1797?-" (a "?" keeps the year verbatim, never typed).
      LIFE = /\A(?<born>\d{3,4})?(?<bq>\?)?-(?<died>\d{3,4})?(?<dq>\?)?\z/

      module_function

      def query_url(pids, start: 1)
        query = pids.map { |pid| %(anywhere="info:ndljp/pid/#{pid}") }.join(" OR ")
        params = [["operation", "searchRetrieve"], ["version", "1.2"], ["recordSchema", "dcndl"],
                  ["maximumRecords", MAX_RECORDS.to_s], ["startRecord", start.to_s], ["query", query]]
        "#{SRU_URL}?#{params.map { |key, value| "#{key}=#{encode(value)}" }.join('&')}"
      end

      def encode(value) = URI.encode_www_form_component(value).gsub("+", "%20")

      # An SRU answer → Page. A diagnostic, or anything that is not a
      # searchRetrieveResponse, is a FetchError (the crawl is resumable).
      def page(body)
        doc = Nokogiri::XML(body.to_s.dup.force_encoding(Encoding::UTF_8))
        root = doc.root
        unless root&.name == "searchRetrieveResponse" && root.namespace&.href == SRW
          raise Nabu::FetchError, "NDL Search SRU: not a searchRetrieveResponse (#{body.to_s[0, 80].inspect})"
        end

        message = root.at_xpath(".//srw:diagnostics//*[local-name()='message']", "srw" => SRW)
        raise Nabu::FetchError, "NDL Search SRU diagnostic: #{message.text.strip}" if message

        Page.new(total: Integer(root.at_xpath("srw:numberOfRecords", "srw" => SRW)&.text.to_s.strip, 10),
                 records: root.xpath("srw:records/srw:record/srw:recordData", "srw" => SRW).map(&:text),
                 next_position: root.at_xpath("srw:nextRecordPosition", "srw" => SRW)&.text&.then do |text|
                   Integer(text.strip, 10)
                 end)
      rescue ArgumentError, TypeError => e
        raise Nabu::FetchError, "NDL Search SRU: unreadable answer (#{e.message})"
      end

      def records_for(pid, records)
        link = %r{dl\.ndl\.go\.jp/pid/#{Regexp.escape(pid.to_s)}"}
        records.grep(link)
      end

      # The per-PID sidecar: the PID's records verbatim inside one wrapper
      # element (canonical bytes; parse reads them back with .read).
      def sidecar(pid, records)
        body = records.map(&:strip).join("\n")
        %(<?xml version="1.0" encoding="UTF-8"?>\n<ndl-bib pid="#{pid}">\n#{body}\n</ndl-bib>\n)
      end

      # A sidecar → the join's fields (absent keys = no claim):
      # "records" [{category, bib_id}], "ndc"/"ndlc" codes verbatim,
      # "creators" (authority form, life-years split by .creator_name,
      # reading, authority URI), "issued" years, "date_prose", and the
      # publishers' "publication_places" verbatim.
      def read(path)
        doc = Nokogiri::XML(File.read(path, encoding: "UTF-8"), &:strict)
        records = doc.root.element_children
        raise Nabu::ParseError, "#{path}: no bib record in the sidecar" if records.empty?

        compact(records.map { |rdf| record_fields(rdf) }.reduce { |merged, fields| merge(merged, fields) })
      rescue Nokogiri::XML::SyntaxError, Errno::ENOENT => e
        raise Nabu::ParseError, "#{path}: unreadable bib sidecar: #{e.message}"
      end

      def record_fields(rdf)
        {
          "records" => [{ "category" => text(rdf.at_xpath(".//dcndl:bibRecordCategory", NS)),
                          "bib_id" => text(rdf.at_xpath(".//dcterms:identifier[@rdf:datatype='#{NDLBIBID}']",
                                                        NS)) }.compact],
          "ndc" => classification(rdf, "NDC", "ndc"),
          "ndlc" => classification(rdf, "NDLC", "ndlc"),
          "creators" => rdf.xpath(".//dcterms:creator/foaf:Agent", NS).map { |agent| creator(agent) },
          "issued" => issued_years(rdf.xpath(".//dcndl:BibResource/dcterms:issued[@rdf:datatype='#{W3CDTF}']",
                                             NS).map { |node| node.text.strip }),
          "date_prose" => text(rdf.at_xpath(".//dcndl:BibResource/dcterms:date", NS)),
          "publication_places" => rdf.xpath(".//dcterms:publisher/foaf:Agent/dcndl:location", NS)
                                     .filter_map { |node| text(node) }
        }
      end

      # Codes verbatim from both shapes the records use: a typed
      # dc:subject (datatype …/NDC, …/NDC9, …/NDLC) and an id.ndl.go.jp
      # class URI on dcterms:subject.
      def classification(rdf, scheme, uri_segment)
        typed = rdf.xpath(".//dc:subject[@rdf:datatype]", NS).select do |node|
          node.attribute_with_ns("datatype", NS["rdf"]).value.match?(%r{/#{scheme}\d*\z})
        end
        uris = rdf.xpath(".//dcterms:subject/@rdf:resource", NS)
                  .filter_map { |attr| attr.value[%r{id\.ndl\.go\.jp/class/#{uri_segment}\d*/(.+)\z}, 1] }
        (typed.filter_map { |node| text(node) } + uris.map { |code| Normalize.nfc(code) }).uniq
      end

      def creator(agent)
        entry = creator_name(agent.at_xpath("foaf:name", NS)&.text.to_s)
        reading = text(agent.at_xpath("dcndl:transcription", NS))
        entry["reading"] = reading if reading
        authority = agent.attribute_with_ns("about", NS["rdf"])&.value
        entry["authority"] = authority if authority
        entry
      end

      # "近藤, 芳樹, 1801-1880" → name + the verbatim life span + typed
      # born/died where certain. Anything else after the last comma (a
      # floruit era "明和頃", a generation mark) keeps the name whole.
      def creator_name(raw)
        value = Normalize.nfc(raw.strip)
        head, comma, tail = value.rpartition(",")
        life = tail.strip
        match = LIFE.match(life) unless comma.empty?
        return { "name" => value } unless match && (match[:born] || match[:died])

        entry = { "name" => head.strip, "life" => life }
        entry["born"] = Integer(match[:born], 10) if match[:born] && !match[:bq]
        entry["died"] = Integer(match[:died], 10) if match[:died] && !match[:dq]
        entry
      end

      def issued_years(values)
        values.filter_map { |value| value[/\A(\d{4})/, 1] }
              .map { |year| Integer(year, 10) }
              .reject { |year| year == DATE_SENTINEL }.uniq
      end

      def text(node)
        value = node&.text.to_s.strip
        value.empty? ? nil : Normalize.nfc(value)
      end

      def merge(left, right)
        left.merge(right) do |key, a, b|
          key == "date_prose" ? (a || b) : (Array(a) + Array(b)).uniq
        end
      end

      def compact(fields)
        fields.reject { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      end
    end
  end
end
