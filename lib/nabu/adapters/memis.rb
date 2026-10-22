# frozen_string_literal: true

require "nokogiri"

require_relative "source_read"

module Nabu
  module Adapters
    # MEMIS — Epigrafski korpus srednjeveških in zgodnje novoveških napisov
    # na Slovenskem / the Epigraphic corpus of Medieval and Early Modern
    # inscriptions in Slovenia, v1.0 (Gregor Pobežin, ZRC SAZU Inštitut za
    # kulturno zgodovino; TEI by Tomaž Erjavec; CLARIN.SI handle
    # 11356/1376, issued 2020-12-06). 51 Latin inscriptions of the
    # Slovenian coast — 49 from Koper (Iustinopolis), 2 from Piran —
    # transcribed in situ with abbreviations and ligatures expanded,
    # translated into Slovene, and described (object, material, condition,
    # layout, find-spot, holding, bibliography) in TEI msDesc.
    #
    # == Grains (the README's enumeration)
    #
    # Upstream serves ONE file, MEMIS.xml (the deposit's only bitstream).
    # Inside it: the teiHeader; <front>, the corpus introduction (prose —
    # skipped by rule, counted); and <body>, 51 <div type="inscription">
    # — the accepted grain, ONE document each (urn:nabu:memis:<n>). The
    # document key is the div's @n (1–51, unique), NOT the msIdentifier
    # idno: upstream reuses I-1-002 on inscriptions 2, 21 and 26 (a
    # copy-paste residue), so idno rides verbatim as metadata only.
    #
    # == Passages: the inscribed line
    #
    # Each <lb n> in a transcription <ab> opens a passage cited by its
    # number; an inscription with two transcribed sides/fields (4, 38 —
    # upstream titles them "Stran A/B", "A: …/B: …") cites side then line
    # (A.1, B.3), the <title> riding as the passage's "section". The text
    # is the editor's READING: <expan>/<ex> (upstream writes only the
    # unwritten letters inside them — "D<expan>ominus</expan>"), <corr>
    # and <supplied> read through; <gap> → "[…]"; <add>, <abbr>, <c> and
    # the name/date/unclear/damage wrappers keep their text; <title> and
    # <note> never enter the line. The "diplomatic" annotation is the same
    # line without the editor's expansions, corrections and supplements —
    # what the stone shows. A line opened by <lb break="no"/> continues a
    # word and carries "break" => "no". A transcription that is only an
    # ellipsis (inscription 32's Greek <ab>, an unfilled placeholder)
    # mints nothing and is counted in "placeholder_transcriptions"; a line
    # upstream opens but leaves empty (30's line 12, 40's doubled <lb
    # n="2"/>) mints nothing and is listed in "empty_lines". Census of
    # v1.0: 476 transcription lines → 473 passages (the Greek placeholder
    # + those two), all Latin.
    # Language: the ab/div xml:lang ("la" → lat; upstream's "gr" → grc).
    #
    # == Mined axes
    #
    # Dating: the typed <origDate> (Slovene prose) is parsed
    # conservatively into the MetadataDates :structured shape — a year
    # ("1269"), a day date ("29. 8. 1578"), a split year ("1581/2" →
    # 1581–1582), circa/uncertain years ("ok. 1670", "1591?" — the year,
    # the qualifier kept in raw), a century or half-century ("2. pol. 15.
    # stol." → 1451–1500, "1.-2. stol. po Kr." → 1–200). "?" and absence
    # mint no date (orig_date keeps the raw). Census of v1.0: 49 of 51
    # dated, 1 CE to 1740 — wider than the deposit's own "1222 to the
    # middle of the 17th century" (21 and 22 are Roman stelae dated by the
    # object; 19 and 51 are 18th-century). Dates written IN the text
    # (<date> inside the transcription: "MCCLXIX", "1222") ride verbatim
    # as text_dates, never converted — inscription 50's text says MCCCXXX
    # while its origDate says 1430; both are kept, neither corrected.
    # Places: <origPlace> verbatim ("Iustinopolis (Koper)", "Piran") is
    # the place claim; settlement/repository/provenance (found/observed)
    # are present locations, metadata only. Kind: the Slovene heading
    # ("Napis za …", "Posvetilo …") and the objectType ride as facets,
    # folded in config/kind_map.yml.
    #
    # == License (verified 2026-10-22)
    #
    # The deposit's DC.rights and the file's own <availability>: "This
    # work is licenced under the Attribution-ShareAlike 4.0 International
    # (CC BY-SA 4.0)" → attribution.
    class Memis < Nabu::Adapter
      HANDLE_URL = "http://hdl.handle.net/11356/1376"
      BITSTREAM_URL = "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1376/MEMIS.xml" \
                      "?sequence=3&isAllowed=y"
      FILENAME = "MEMIS.xml"
      URN_PREFIX = "urn:nabu:memis:"
      LANGUAGE = "lat"
      TEI = { "t" => "http://www.tei-c.org/ns/1.0" }.freeze
      LANGUAGES = { "la" => "lat", "gr" => "grc", "grc" => "grc" }.freeze
      GAP_MARKER = "[…]"
      # Editorial additions: in the reading, out of the diplomatic line.
      EDITORIAL = %w[expan ex corr supplied].freeze
      # Never part of an inscribed line.
      APPARATUS = %w[title note].freeze
      PLACEHOLDER = /\A[.…\s]*\z/
      # origDate shapes (Slovene prose): a year with optional circa/day prefix,
      # "/2" split year and "?" doubt; a half-century; a century or range.
      YEAR = %r{\A(?:ok\.\s*)?(?:\d{1,2}\.\s*\d{1,2}\.\s*)?(\d{3,4})(?:/(\d{1,2}))?\??\z}
      HALF_CENTURY = /\A([12])\.\s*pol\.\s*(\d{1,2})\.\s*stol\.\z/
      CENTURIES = /\A(\d{1,2})\.(?:\s*-\s*(\d{1,2})\.)?\s*stol\.(?:\s*po\s*Kr\.)?\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "memis",
        name: "MEMIS — Epigraphic corpus of Medieval and Early Modern inscriptions in Slovenia 1.0 " \
              "(Pobežin, ZRC SAZU)",
        license: "CC BY-SA 4.0 — the file's <availability>, verbatim: \"This work is licenced under the " \
                 "Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\"; CLARIN.SI deposit " \
                 "http://hdl.handle.net/11356/1376 (Gregor Pobežin, ZRC SAZU)",
        license_class: "attribution",
        upstream_url: HANDLE_URL,
        parser_family: "memis-tei"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      # HEAD the bitstream: reachability + Last-Modified drift against the
      # .file-fetch.json pin.
      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: BITSTREAM_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: BITSTREAM_URL, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "memis fetch failed into #{workdir}: #{e.message}"
      end

      # One ref per inscription div, in file order. A workdir without the
      # file yields nothing (the pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = corpus_path(workdir) or return
        inscriptions(path).each do |div|
          number = div["n"].to_s.strip
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{number}",
            path: File.expand_path(path), metadata: { "n" => number }
          )
        end
      end

      def discovery_skips(workdir)
        front = 0
        if (path = corpus_path(workdir))
          front = document(path).xpath("/t:TEI/t:text/t:front", TEI).size
        end
        strays = stray_files(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: front, unrecognized: strays.size,
          notes: Array.new(front, "edition front matter (the corpus introduction, prose), not an inscription: " \
                                  "<front>") +
                 strays.map { |rel| "non-corpus file: #{rel}" }
        )
      end

      def parse(document_ref)
        number = document_ref.metadata.fetch("n")
        div = inscriptions(document_ref.path).find { |node| node["n"].to_s.strip == number } or
          raise Nabu::ParseError, "#{document_ref.path}: no MEMIS inscription n=#{number.inspect}"
        sides, placeholders = transcriptions(div)
        cited = sides.each_with_index.flat_map do |(ab, language), index|
          prefix = sides.size > 1 ? "#{('A'.ord + index).chr}." : ""
          section = clean(ab.at_xpath("t:title", TEI)&.text)
          lines(ab, document_ref.id).map { |line| ["#{prefix}#{line[:n]}", line, language, section] }
        end
        empty, minted = cited.partition { |(_cite, line)| line[:text].empty? }
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: clean(div.at_xpath("t:head", TEI)&.text),
          metadata: metadata_for(div, placeholders).merge(empty_lines(empty))
        )
        minted.each_with_index do |(cite, line, language, section), index|
          document << passage(document_ref.id, cite, line, language, section, index + 1)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "memis: #{document_ref.id}: #{e.message}"
      end

      private

      def corpus_path(workdir)
        path = File.join(workdir, FILENAME)
        File.file?(path) ? path : nil
      end

      # The parsed TEI, memoized per file identity (path + size + mtime):
      # one parse serves discover and every document.
      def document(path)
        stat = File.stat(path)
        key = [path, stat.size, stat.mtime.to_r]
        return @document if @document_key == key

        text = SourceRead.utf8_file(path, label: "memis")
        @document_key = key
        @document = Nokogiri::XML(text) { |config| config.strict.nonet }
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "memis: malformed XML at #{path}: #{e.message}"
      end

      def inscriptions(path)
        document(path).xpath("/t:TEI/t:text/t:body/t:div[@type='inscription']", TEI)
      end

      # The transcription <ab>s with their language, placeholders dropped
      # (and counted). Upstream's transcription div is typed "transcr" (and
      # "trans" on inscription 1).
      def transcriptions(div)
        abs = div.xpath("t:div[@type='transcr' or @type='trans']//t:ab", TEI)
        kept, placeholders = abs.partition { |ab| !placeholder?(ab) }
        [kept.map { |ab| [ab, language_of(ab)] }, placeholders.size]
      end

      def placeholder?(block)
        text = block.xpath(".//text()[not(ancestor::t:title) and not(ancestor::t:note)]", TEI).map(&:text).join
        text.match?(PLACEHOLDER)
      end

      def language_of(block)
        code = block.at_xpath("ancestor-or-self::*[@xml:lang][1]/@xml:lang").to_s
        code = "la" if code.empty? || code == "sl" # the inscription div's xml:lang is the edition's (sl)
        LANGUAGES.fetch(code) { raise Nabu::ParseError, "memis: unmapped transcription language #{code.inspect}" }
      end

      # -- the line walk ------------------------------------------------------------

      def lines(block, urn)
        state = { lines: [], current: nil, urn: urn }
        walk(block, state, editorial: false)
        state[:lines].map do |line|
          line.merge(text: squash(line[:reading]), diplomatic: squash(line[:diplomatic]))
        end
      end

      def walk(node, state, editorial:)
        node.children.each do |child|
          if child.text?
            emit(state, child.text, editorial: editorial)
          elsif child.element?
            element(child, state, editorial: editorial)
          end
        end
      end

      def element(child, state, editorial:)
        name = child.name
        case name
        when "lb" then open_line(child, state)
        when "gap" then emit(state, GAP_MARKER, editorial: false)
        when "note"
          state[:current][:notes] << clean(child.text) if state[:current]
        when *APPARATUS then nil
        when *EDITORIAL then walk(child, state, editorial: true)
        else walk(child, state, editorial: editorial)
        end
      end

      def open_line(break_node, state)
        number = break_node["n"].to_s.strip
        raise Nabu::ParseError, "memis: #{state[:urn]}: a transcription <lb/> without @n" if number.empty?

        state[:current] = { n: number, break: break_node["break"], reading: +"", diplomatic: +"", notes: [] }
        state[:lines] << state[:current]
      end

      def emit(state, text, editorial:)
        if state[:current].nil?
          return if text.strip.empty?

          raise Nabu::ParseError, "memis: #{state[:urn]}: transcription text before the first <lb/>"
        end
        state[:current][:reading] << text
        state[:current][:diplomatic] << text unless editorial
      end

      def passage(urn, cite, line, language, section, sequence)
        annotations = { "diplomatic" => line[:diplomatic] }
        annotations["break"] = line[:break] if line[:break]
        annotations["section"] = section if section
        annotations["notes"] = line[:notes] unless line[:notes].empty?
        Nabu::Passage.new(
          urn: "#{urn}:#{cite}", language: language, sequence: sequence,
          text: SourceRead.nfc(line[:text], language: language), annotations: annotations
        )
      end

      def squash(text) = text.gsub(/[[:space:]]+/, " ").strip

      # Lines upstream opens but leaves empty (inscription 30's blank line
      # 12; inscription 40's doubled <lb n="2"/>) mint nothing — counted.
      def empty_lines(empty)
        empty.empty? ? {} : { "empty_lines" => empty.map(&:first) }
      end

      # -- metadata -------------------------------------------------------------------

      def metadata_for(div, placeholders)
        ms = div.at_xpath(".//t:msDesc", TEI)
        heading = clean(div.at_xpath("t:head", TEI)&.text)
        object = field(ms, ".//t:objectType")
        orig_date = field(ms, ".//t:origDate")
        orig_place = field(ms, ".//t:origPlace")
        {
          "inscription" => div["n"].to_s.strip,
          "idno" => field(ms, ".//t:msIdentifier/t:idno"),
          "country" => field(ms, ".//t:msIdentifier/t:country"),
          "settlement" => field(ms, ".//t:msIdentifier/t:settlement"),
          "repository" => field(ms, ".//t:msIdentifier/t:repository"),
          "object_type" => object,
          "material" => field(ms, ".//t:material"),
          "condition" => field(ms, ".//t:condition"),
          "layout" => field(ms, ".//t:layout"),
          "orig_place" => orig_place,
          "place" => orig_place,
          "orig_date" => orig_date,
          "date" => orig_date && date_for(orig_date),
          "text_dates" => text_dates(div),
          "provenance" => provenance(ms),
          "bibliography" => bibliography(ms),
          "translation_sl" => translation(div),
          "placeholder_transcriptions" => placeholders.zero? ? nil : placeholders,
          "facets" => { "heading" => heading, "object" => object }.compact.transform_values { |v| { "values" => [v] } }
        }.compact.reject { |_, value| value.respond_to?(:empty?) && value.empty? }
      end

      def field(scope, xpath)
        return nil if scope.nil?

        clean(scope.at_xpath(xpath, TEI)&.text)
      end

      def provenance(desc)
        return nil if desc.nil?

        pairs = desc.xpath(".//t:provenance", TEI).to_h { |node| [node["type"].to_s, clean(node.text)] }
        pairs.reject { |key, value| key.empty? || value.nil? }
      end

      def bibliography(desc)
        return nil if desc.nil?

        desc.xpath(".//t:listBibl/t:bibl", TEI).filter_map { |bibl| clean(bibl.text) }
      end

      def text_dates(div)
        div.xpath("t:div[@type='transcr' or @type='trans']//t:ab//t:date", TEI).filter_map { |node| clean(node.text) }
      end

      # The translation prose, footnotes stripped.
      def translation(div)
        node = div.at_xpath("t:div[@type='translation']", TEI) or return nil
        copy = node.dup
        copy.xpath(".//t:note | ./t:head", TEI).each(&:remove)
        clean(copy.text)
      end

      def clean(value)
        return nil if value.nil?

        text = value.gsub(/[[:space:]]+/, " ").strip
        text.empty? ? nil : Nabu::Normalize.nfc(text)
      end

      # -- origDate (Slovene prose) → the structured envelope --------------------------

      def date_for(raw)
        bounds = date_bounds(raw.strip) or return nil
        { "not_before" => bounds.first, "not_after" => bounds.last, "raw" => raw }
      end

      def date_bounds(raw)
        if (m = YEAR.match(raw))
          year = m[1].to_i
          return [year, year] unless m[2]

          tail = m[2]
          [year, (year.to_s[0...-tail.size] + tail).to_i]
        elsif (m = HALF_CENTURY.match(raw))
          base = (m[2].to_i - 1) * 100
          m[1] == "1" ? [base + 1, base + 50] : [base + 51, base + 100]
        elsif (m = CENTURIES.match(raw))
          [((m[1].to_i - 1) * 100) + 1, (m[2] || m[1]).to_i * 100]
        end
      end

      # Files beside MEMIS.xml that are not the fetch's own (dot-files —
      # the FileFetch state, the attic — and a README are exempt).
      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .reject { |path| File.basename(path).start_with?(".") }
           .map { |path| path.delete_prefix("#{workdir}/") }
           .reject { |rel| [FILENAME, "README.md", "manifest.yml"].include?(rel) }
           .sort
      end
    end
  end
end
