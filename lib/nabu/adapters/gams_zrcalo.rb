# frozen_string_literal: true

require "nokogiri"

require_relative "../file_fetch"

module Nabu
  module Adapters
    # gams-zrcalo (02-sources row 244): the GAMS digital edition of
    # *Zrcalo člověčaskago spasenja* — the Croatian Glagolitic Speculum
    # humanae salvationis written in 1445 by the deacon Luka (Vatican,
    # Borg. illirico 9), translated from the Old Czech *Zrcadlo človečieho
    # spasenie* (itself from the Latin Speculum). Semi-diplomatic
    # transcription by Martina Kramarić (IHJJ; print edition Zagreb 2019),
    # TEI by ZIM-ACDH Graz (Gerlinde Schneider), GAMS PID o:speculum.01.
    #
    # License: the TEI's own availability, verbatim: <licence n="text"
    # target="https://creativecommons.org/licenses/by/4.0">Creative
    # Commons BY 4.0</licence> (the context page links the same) →
    # attribution. Credit: Kramarić & Schneider, GAMS / Universität Graz.
    #
    # == Shape
    #
    # ONE file (FileFetch of the TEI_SOURCE datastream, 509 KB) → one
    # document, urn:nabu:gams-zrcalo:speculum. The body holds the Zrcalo
    # proper (ff. 1r–81v: the foreword + chapters 1–42, with the lacunae
    # the edition notes — the rest of 7/start of 8, 24–26, most of 27);
    # the codex's four shorter pieces (ff. 81v–95v) are catalogued in the
    # msDesc but not transcribed, so they mint nothing. Passages: each
    # chapter's <head> and each <p>, cited <chapter>.head / <chapter>.<n>
    # (the chapter key is the integer in div@n — "Chapter 24", "35." —
    # or "foreword"; n is the p's position in its div, since five p carry
    # no @n). The work title head (the outer div) cites "title".
    #
    # == The reading text — the WITNESS as written, declared
    #
    # Line breaks: <lb/> is a space, <lb break="no"/> joins the word
    # halves (the edition's own hyphenation flag; pretty-print whitespace
    # around it is dropped). <choice><sic>/<corr>: the text keeps the
    # manuscript's SIC (canonical means canonical); every editor's
    # correction rides in annotations "corrections" [{sic, corr}].
    # <supplied> (editor-restored letters, mostly mid-word) and <surplus>
    # (scribal double-writing, marked) stay in the text as transcribed;
    # <del> (struck by the scribe) leaves it; <add> (the scribe's
    # marginal/interlinear additions) stays; <note> (editorial
    # footnotes) moves to annotations "notes" (a note standing between
    # paragraphs — the chapter-24 lacuna — rides metadata "div_notes",
    # keyed by chapter). <pb n> sets the folio
    # (annotations "folio", the passage's starting folio) and <cb n> the
    # column; neither is text.
    #
    # == Script and lect (declared)
    #
    # The codex is GLAGOLITIC (scriptDesc); the edition is a Latin-script
    # transliteration — the Glagolitic original is not carried (metadata
    # script_original). textLang mainLang="hr" otherLangs="chu" ("mostly
    # Old Croatian with some elements of Old Church Slavonic Croatian
    # redaction, and traces of Old Czech") → language hrv (the
    # hr-wikisource code, codemap hrv → hr); the chu:csl/cro elements are
    # recorded in metadata text_languages, never split out.
    #
    # == Axes
    #
    # date — origDate 1445 (the colophon's own "1445. měseca maja na 19.
    # dan"), {not_before, not_after, raw}. Place: upstream's origPlace
    # says "place of origin unknown" — no place minted (the colophon
    # names the commissioning priest's Vrbnik, not the writing place;
    # declared, never inferred); the custody chain rides as provenance.
    class GamsZrcalo < Nabu::Adapter
      TEI_URL = "https://gams.uni-graz.at/o:speculum.01/TEI_SOURCE"
      FILENAME = "speculum.01.xml"
      URN = "urn:nabu:gams-zrcalo:speculum"
      LANGUAGE = "hrv"

      MANIFEST = Nabu::SourceManifest.new(
        id: "gams-zrcalo",
        name: "Zrcalo člověčaskago spasenja (1445) — GAMS digital edition (Kramarić & Schneider, Graz)",
        license: "CC BY 4.0 (the TEI availability verbatim: <licence n=\"text\" " \
                 "target=\"https://creativecommons.org/licenses/by/4.0\">Creative Commons BY 4.0</licence>); " \
                 "credit Martina Kramarić & Gerlinde Schneider, GAMS / Universität Graz",
        license_class: "attribution",
        upstream_url: "https://gams.uni-graz.at/speculum",
        parser_family: "gams-speculum-tei"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: TEI_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, FILENAME)
        return unless File.file?(path)

        block.call(Nabu::DocumentRef.new(source_id: MANIFEST.id, id: URN, path: File.expand_path(path), metadata: {}))
      end

      def parse(document_ref)
        doc = Nokogiri::XML(File.read(document_ref.path), &:strict)
        doc.remove_namespaces!
        document = Document.new(
          urn: document_ref.id, language: LANGUAGE, title: title(doc),
          canonical_path: document_ref.path, metadata: header_metadata(doc)
        )
        Reader.new(document, document_ref.id).read(doc.at_xpath("//text/body"))
        raise ParseError, "#{document_ref.path}: no passages in the body" if document.empty?

        document
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{document_ref.path}: malformed XML: #{e.message}"
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: TEI_URL, dir: workdir, filename: FILENAME, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress, guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        notes = [result.not_modified ? "not modified (304)" : "TEI fetched", attic_notes(result.atticked)]
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes.compact.join("; "))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "gams-zrcalo fetch failed into #{workdir}: #{e.message}"
      end

      # The body walk (recursive, document order): one passage per head / p, the witness reading text
      # with folio/column state carried across blocks in document order.
      class Reader
        # The chapter key: the integer in div@n ("Chapter 24", "35."), else
        # the slugged label ("Foreword" → foreword); the outer div → title.
        def self.div_key(div)
          n = div["n"].to_s
          return "title" if n.empty?

          n[/\d+/] || n.downcase.gsub(/[^a-z0-9]+/, "-")
        end

        def initialize(document, urn)
          @document = document
          @urn = urn
          @folio = nil
          @column = nil
        end

        def read(body)
          return if body.nil?

          body.element_children.each { |child| child.name == "div" ? read_div(child) : track_breaks(child) }
        end

        private

        def read_div(div)
          key = self.class.div_key(div)
          position = 0
          div.element_children.each do |child|
            case child.name
            when "head" then emit(child, "#{key}.head", "head")
            when "p"
              position += 1
              emit(child, "#{key}.#{position}", "p")
            when "div" then read_div(child) # nested: recursion keeps document order
            else track_breaks(child)
            end
          end
        end

        def emit(block, citation, unit)
          state = { text: +"", join: false, corrections: [], notes: [], folio: @folio, column: @column }
          walk(block, state)
          text = state[:text].gsub(/[[:space:]]+/, " ").strip
          return if text.empty?

          @document << Passage.new(
            urn: "#{@urn}:#{citation}", language: LANGUAGE, text: Normalize.nfc(text),
            sequence: @document.size, annotations: annotations(unit, state)
          )
        end

        def annotations(unit, state)
          {
            "unit" => unit,
            "folio" => state[:folio],
            "column" => state[:column],
            "corrections" => (state[:corrections] unless state[:corrections].empty?),
            "notes" => (state[:notes] unless state[:notes].empty?)
          }.compact
        end

        def walk(node, state)
          node.children.each do |child|
            if child.text?
              append(state, child.text)
            elsif child.element?
              element(child, state)
            end
          end
        end

        def element(child, state)
          case child.name
          when "lb" then line_break(child, state)
          when "pb", "cb" then page_break(child, state)
          when "choice" then choice(child, state)
          when "note" then state[:notes] << Normalize.nfc(child.text.gsub(/[[:space:]]+/, " ").strip)
          when "del" then nil
          else walk(child, state)
          end
        end

        def line_break(node, state)
          if node["break"] == "no"
            state[:text].rstrip!
            state[:join] = true
          else
            append(state, " ")
          end
        end

        def page_break(node, state)
          if node.name == "pb"
            @folio = node["n"]
            state[:folio] = @folio if state[:text].strip.empty?
          else
            @column = node["n"]
            state[:column] = @column if state[:text].strip.empty?
          end
        end

        def choice(node, state)
          sic = node.at_xpath("sic")
          corr = node.at_xpath("corr")
          walk(sic, state) if sic
          return unless sic && corr

          state[:corrections] << { "sic" => Normalize.nfc(sic.text.strip), "corr" => Normalize.nfc(corr.text.strip) }
        end

        def track_breaks(node)
          node.xpath("descendant-or-self::pb | descendant-or-self::cb").each do |brk|
            brk.name == "pb" ? @folio = brk["n"] : @column = brk["n"]
          end
        end

        # Text joins verbatim, except right after a break="no" line end:
        # the pretty-print whitespace there belongs to neither half.
        def append(state, text)
          if state[:join]
            stripped = text.lstrip
            return if stripped.empty?

            state[:join] = false
            text = stripped
          end
          state[:text] << text
        end
      end

      private

      def title(doc)
        main = doc.at_xpath("//msItem[@n='1']/title[@lang='hr']")&.text&.strip
        main = doc.at_xpath("//titleStmt/title")&.text&.strip if main.nil? || main.empty?
        main && Normalize.nfc(main.gsub(/[[:space:]]+/, " "))
      end

      def header_metadata(doc)
        text_lang = doc.at_xpath("//msItem/textLang")
        date = doc.at_xpath("//origDate/date")
        squash = ->(node) { node && Normalize.nfc(node.text.gsub(/[[:space:]]+/, " ").strip) }
        {
          "date" => date_envelope(date),
          "shelfmark" => squash.call(doc.at_xpath("//msIdentifier/idno")),
          "repository" => squash.call(doc.at_xpath("//msIdentifier/institution")),
          "settlement" => squash.call(doc.at_xpath("//msIdentifier/settlement")),
          "script_original" => squash.call(doc.at_xpath("//scriptDesc//p")),
          "text_languages" => text_lang && [text_lang["mainLang"], *text_lang["otherLangs"].to_s.split].compact,
          "text_languages_note" => squash.call(text_lang),
          "orig_place" => squash.call(doc.at_xpath("//origPlace/placeName")),
          "provenance" => squash.call(doc.at_xpath("//history/provenance")),
          "edition" => "semi-diplomatic Latin-script transliteration (GAMS o:speculum.01)",
          "editors" => doc.xpath("//editionStmt/editor").map { |e| squash.call(e) },
          "gams_pid" => doc.at_xpath("//publicationStmt/idno[@type='PID']")&.text&.strip,
          "edition_date" => doc.at_xpath("//publicationStmt/date")&.[]("when"),
          "div_notes" => div_notes(doc, squash)
        }.compact
      end

      # Editorial notes standing between paragraphs (the chapter-24
      # lacuna note) belong to no passage — they ride the document,
      # keyed by chapter.
      def div_notes(doc, squash)
        notes = doc.xpath("//body//div/note").map do |note|
          { "chapter" => Reader.div_key(note.parent), "note" => squash.call(note) }
        end
        notes.empty? ? nil : notes
      end

      def date_envelope(node)
        year = node&.[]("when").to_s[/\A\d{4}/]
        return nil unless year

        { "not_before" => year.to_i, "not_after" => year.to_i, "raw" => node.text.strip }
      end
    end
  end
end
