# frozen_string_literal: true

require "stringio"

require_relative "conllu_parser"

module Nabu
  module Adapters
    # The Damaskini adapter (P23-1; clarin-si-survey pick #1): the Annotated
    # Corpus of Pre-Standardized Balkan Slavic Literature 1.1 (Škrabal et al.;
    # CLARIN.SI hdl 11356/1441) — 23 gold-annotated samples of "damaskini"
    # and other Balkan Slavic manuscripts and prints, 15th–19th c., 6,036
    # sentences / 53,257 tokens on the Church-Slavonic-to-Bulgarian
    # continuum; ~10 of the samples are independent witnesses of Euthymius
    # of Tarnovo's *Life of St. Petka*. Annotation is manual (gold): lemma,
    # custom MULTEXT-East MSD (the msd-bg-dam spec) in XPOS, UD dependency
    # relations, and a sentence-level English translation (`# text_en`,
    # 100% coverage — censused at fixture time).
    #
    # == Identity (FROZEN minting)
    #
    # The corpus is ONE CoNLL-U file with 23 `# newdoc id` blocks. One
    # document per newdoc: urn = urn:nabu:damaskini:<newdoc-id> lowercased
    # (upstream's own ids; only xrulev--za-sv-Paraskeva carries case, and
    # ids are unique case-insensitively). sent_ids are CORPUS-continuous
    # ("<newdoc-id>.<n>"; berlinski ends at 453, ioan starts at 454) — the
    # passage citation is the numeric tail, upstream's own sentence number
    # (…:veles--trojanskata:5601). English siblings are -en documents
    # (…:<doc-id>-en:<n>, the ORACC/Freising variant pattern), minted from
    # the same parse when the registry opts in (`translations: true`).
    # Minting is frozen once used (standing rule).
    #
    # == License
    #
    # CC BY-SA 4.0. Verbatim, the CLARIN.SI deposit record (dc.rights):
    # "Creative Commons - Attribution-ShareAlike 4.0 International
    # (CC BY-SA 4.0)", rights URI creativecommons.org/licenses/by-sa/4.0/,
    # access label PUB. license_class "attribution", MCP-safe. (v1.0 =
    # hdl 11356/1368 was GPL-3 and is superseded; 1.1's grant governs.)
    # Attribution: Annotated Corpus of Pre-Standardized Balkan Slavic
    # Literature, CLARIN.SI. See test/fixtures/damaskini/README.md.
    #
    # == Language (the honest verdict)
    #
    # The deposit is tagged `bul, mkd` COLLECTIVELY; neither data file
    # machine-tags a per-document language. The corpus's own philological
    # description classifies every source by Norm — Church Slavonic (Vel.s.,
    # Vuković 1536, Kiev d.), simple Bulgarian (14 sources),
    # Slavenobulgarian (5), standard Bulgarian (Nedělnik 1856) — and states
    # (fn. 7) that the glottonym "Bulgarian" is used "for historical
    # reasons - the included sources do not use 'Macedonian' or 'Serbian'".
    # DOCS therefore maps Norm → language: chu for the three Church
    # Slavonic witnesses, bul for the rest; Norm and dialectal Origin
    # (Macedonia/Rhodopes/Serbia-Torlak/West/East Bulgaria — the
    # description's other axis) ride as document facets, so the Macedonian
    # and Serbian-area witnesses stay findable without minting a language
    # claim the corpus itself does not make. A newdoc id missing from DOCS
    # is a ParseError (quarantine), never a guessed language.
    #
    # == Document metadata: the TSV headers
    #
    # The companion TSV bitstream carries one file per document (filename =
    # newdoc id verbatim) whose free-text header block holds the manuscript
    # name, "place, date" (with honest question marks — "Pleven?"; date
    # shapes censused: 1791 · 1580s · 1650-1670s · 17th · XV c. ·
    # "19th (post 1817)"; xrulev's year rides in an edition line), an
    # optional scribe line, locus/edition references, and the chapter
    # title. TsvHeader reads that block (anchored on the `text` column-
    # header row); dates feed Store::AxisBuilder::DamaskiniDates. The TSV
    # TOKEN layers (accented | Cyrillic | diplomatic orthography, folio
    # anchors, chunk divisions, cross-text refs) are deliberately NOT
    # ingested here: column layouts vary per file and five files disagree
    # with the CoNLL-U by 1–3 sentences — a phase-2 alignment job
    # (backlog P23-1), not a rider. A document whose TSV sibling is
    # missing is a ParseError — silent metadata loss is never a shrug.
    #
    # == fetch / sync policy
    #
    # TWO zip bitstreams over HTTPS (Nabu::ZipFetch two-phase, the ORACC
    # multi-zip choreography; DSpace bitstream URLs, auth-free) into
    # <workdir>/conllu and <workdir>/tsv. The deposit is a frozen v1.1
    # (2021-07-02) → sync_policy: manual, enabled: false until the
    # owner-fired first real sync. The probe HEADs both bitstreams; the
    # license lives on the record page, so the probe's license row
    # honestly reads unchecked.
    class Damaskini < Nabu::Adapter
      BITSTREAM_BASE = "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1441"
      # Upstream really spells "CoNNL-U" (sic) in the bitstream filename.
      CONLLU_ZIP_URL = "#{BITSTREAM_BASE}/Damaskini.CoNNL-U.zip".freeze
      TSV_ZIP_URL = "#{BITSTREAM_BASE}/Damaskini.TSV.zip".freeze

      ZIPS = { "conllu" => CONLLU_ZIP_URL, "tsv" => TSV_ZIP_URL }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "damaskini",
        name: "Damaskini — Annotated Corpus of Pre-Standardized Balkan Slavic Literature 1.1 (CLARIN.SI)",
        license: "CC BY-SA 4.0 (verbatim deposit record hdl 11356/1441: \"Creative Commons - " \
                 "Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\", access PUB)",
        license_class: "attribution",
        upstream_url: CONLLU_ZIP_URL,
        parser_family: "conllu"
      )

      URN_PREFIX = "urn:nabu:damaskini:"

      # The corpus's own per-source classification (philological description
      # PDF, deposit bitstream; see the class note and the fixture README).
      # language: Norm → chu (Church Slavonic) / bul (all Bulgarian norms).
      # norm/origin: [facet value, the description's phrase verbatim].
      # nbkm370 is absent from the description's Origin lists — honest nil.
      # FROZEN against upstream v1.1: an id not listed here quarantines.
      DOCS = {
        "berlinski--slovo-petki" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                      origin: ["east-bulgaria", "East Bulgaria"] },
        "ioan--zitie-petky" => { language: "bul", norm: %w[slavenobulgarian Slavenobulgarian],
                                 origin: ["west-bulgaria", "West Bulgaria"] },
        "jankul--oci-na-sinai" => { language: "bul", norm: %w[slavenobulgarian Slavenobulgarian],
                                    origin: ["west-bulgaria", "West Bulgaria"] },
        "kievski--zitie-marie-egyptenini" => { language: "chu", norm: ["church-slavonic", "Church Slavonic"],
                                               origin: %w[macedonia Macedonia] },
        "krcovski--daniil" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                origin: %w[macedonia Macedonia] },
        "ljubljanski--zitie-petki" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                        origin: ["east-bulgaria", "East Bulgaria"] },
        "loveski--neopivati-se" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                     origin: ["east-bulgaria", "East Bulgaria"] },
        "nbkm328--pricta-taisie" => { language: "bul", norm: %w[slavenobulgarian Slavenobulgarian],
                                      origin: ["west-bulgaria", "West Bulgaria"] },
        "nbkm370--predislovie" => { language: "bul", norm: %w[slavenobulgarian Slavenobulgarian],
                                    origin: nil },
        "nbkm728--zitie-paraskeva" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                        origin: %w[macedonia Macedonia] },
        "nbkm1064--ziuveenitu-na-petka" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                             origin: ["east-bulgaria", "East Bulgaria"] },
        "nbkm1069--slovo-radi-orisanie" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                             origin: ["east-bulgaria", "East Bulgaria"] },
        "nbkm1081--slovo-danaila" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                       origin: ["east-bulgaria", "East Bulgaria"] },
        "nbkm1423--st-antun-et-al" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                        origin: %w[rhodopes Rhodopes] },
        "nedelnik1806--skazanie-paraskevy" => { language: "bul", norm: %w[slavenobulgarian Slavenobulgarian],
                                                origin: ["west-bulgaria", "West Bulgaria"] },
        "pps--slovesa-iosifa-i-paraskevi" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                               origin: ["west-bulgaria", "West Bulgaria"] },
        "raikovski--daniil" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                 origin: %w[rhodopes Rhodopes] },
        "svd--zitie-marii-egyptenicy" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                           origin: ["east-bulgaria", "East Bulgaria"] },
        "temski--slovo-o-nakazanii" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                         origin: ["serbia-torlak", "Serbia or Torlak area"] },
        "tixonravovski--zitie-petky" => { language: "bul", norm: ["simple-bulgarian", "simple Bulgarian"],
                                          origin: ["east-bulgaria", "East Bulgaria"] },
        "veles--trojanskata" => { language: "chu", norm: ["church-slavonic", "Church Slavonic"],
                                  origin: %w[macedonia Macedonia] },
        "vukovic--zitie-petky" => { language: "chu", norm: ["church-slavonic", "Church Slavonic"],
                                    origin: ["serbia-torlak", "Serbia or Torlak area"] },
        "xrulev--za-sv-Paraskeva" => { language: "bul", norm: ["standard-bulgarian", "standard Bulgarian"],
                                       origin: ["east-bulgaria", "East Bulgaria"] }
      }.freeze

      # Reads one TSV file's free-text header block (everything above the
      # `text` column-header row): manuscript/source name (first line), an
      # optional "place, date" line (or a bare date/century), an optional
      # scribe line (the line right after the date, when it is neither a
      # locus/edition reference nor the closing title line), the title (the
      # last otherwise-unclassified line), and the leftover locus/edition
      # lines joined into +notes+. All 23 upstream headers were censused
      # against these rules at fixture time (see the fixture README);
      # anything unparsed stays raw in +notes+ — never guessed, never lost.
      module TsvHeader
        Header = Data.define(:source_name, :place, :date_raw, :not_before, :not_after,
                             :scribe, :title, :notes)

        # A locus/edition-reference line: folio spans ("l. 179r-185v",
        # "268v-270v (Cyr.)", "p. 25-46"), sigla ("S2: …"), edition cites
        # ("ed. T. Xrulev 1856").
        LOCUS = /\A(?:l\.|ll\.|p\.|pp\.|S\d|ed\.|\d)/
        # The corpus spans 1401–1900; a bare year anywhere in a header line
        # (the xrulev fallback) must look like that.
        YEAR = /\b(1[4-9]\d\d)\b/

        ROMAN = { "I" => 1, "V" => 5, "X" => 10 }.freeze

        module_function

        def read(path)
          lines = header_lines(path)
          source_name = lines.first
          rest = lines.drop(1)
          place, date_raw, bounds, date_index = find_date(rest)
          used = [date_index].compact
          scribe = scribe_at(rest, date_index, used)
          title = title_at(rest, used)
          bounds ||= fallback_year(rest)
          Header.new(
            source_name: source_name, place: place, date_raw: date_raw || bounds&.last&.to_s,
            not_before: bounds&.first, not_after: bounds&.last, scribe: scribe, title: title,
            notes: notes_from(rest, used)
          )
        end

        # The censused date shapes, tried in order: point year, decade,
        # decade range, year range, "Nth (post YYYY)", "Nth", roman century.
        # Each lambda maps its MatchData to [not_before, not_after].
        DATE_SHAPES = {
          /\A(\d{4})\z/ => ->(m) { [m[1].to_i, m[1].to_i] },
          /\A(\d{4})s\z/ => ->(m) { [m[1].to_i, m[1].to_i + 9] },
          /\A(\d{4})-(\d{4})s\z/ => ->(m) { [m[1].to_i, m[2].to_i + 9] },
          /\A(\d{4})-(\d{4})\z/ => ->(m) { [m[1].to_i, m[2].to_i] },
          /\A(\d{1,2})th\s*\(post\s*(\d{4})\)\z/ => ->(m) { [m[2].to_i, m[1].to_i * 100] },
          /\A(\d{1,2})th\z/ => ->(m) { century_bounds(m[1].to_i) },
          /\A([IVX]+)\s*c\.\z/ => ->(m) { century_bounds(roman(m[1])) }
        }.freeze

        # [not_before, not_after] for the corpus's censused date shapes, or
        # nil for a line that is not a date.
        def parse_date(text)
          stripped = text.strip
          DATE_SHAPES.each do |pattern, bounds|
            match = pattern.match(stripped) or next
            return bounds.call(match)
          end
          nil
        end

        def century_bounds(century)
          [((century - 1) * 100) + 1, century * 100]
        end

        def roman(numeral)
          total = 0
          previous = 0
          numeral.chars.reverse_each do |char|
            value = ROMAN.fetch(char)
            total += value < previous ? -value : value
            previous = value if value > previous
          end
          total
        end

        # First cells of the lines above the `text` column-header row,
        # stripped, blanks dropped. A file without that row is not a
        # Damaskini TSV — damage, not a rule.
        def header_lines(path)
          lines = []
          File.foreach(path, encoding: "UTF-8") do |line|
            first = line.chomp.split("\t", 2).first.to_s.strip
            return lines if first == "text"

            lines << first unless first.empty?
          end
          raise Nabu::ParseError, "#{path}: no `text` column-header row — not a Damaskini TSV"
        end

        # [place, date_raw, bounds, index] from the first line that parses
        # as a date, bare ("XV c.") or after a "place, " prefix. All nils
        # when no line does (xrulev — the fallback_year path).
        def find_date(rest)
          rest.each_with_index do |line, index|
            if (bounds = parse_date(line))
              return [nil, line, bounds, index]
            end

            match = /\A(?<place>.+?),\s*(?<date>.+)\z/.match(line) or next
            bounds = parse_date(match[:date]) or next
            return [match[:place], match[:date], bounds, index]
          end
          [nil, nil, nil, nil]
        end

        def scribe_at(rest, date_index, used)
          return nil if date_index.nil?

          index = date_index + 1
          line = rest[index]
          return nil if line.nil? || LOCUS.match?(line) || index == rest.size - 1

          used << index
          line
        end

        def title_at(rest, used)
          index = rest.size - 1
          return nil if index.negative? || used.include?(index) || LOCUS.match?(rest[index])

          used << index
          rest[index]
        end

        def fallback_year(rest)
          rest.each do |line|
            match = YEAR.match(line) or next
            return [match[1].to_i, match[1].to_i]
          end
          nil
        end

        def notes_from(rest, used)
          leftovers = rest.each_with_index.reject { |_line, index| used.include?(index) }
          return nil if leftovers.empty?

          leftovers.map(&:first).join(" · ")
        end
      end

      def self.manifest
        MANIFEST
      end

      # The probe HEADs both zip bitstreams: reachability + Last-Modified
      # drift vs each tree's .zip-fetch.json pin. metadata_url nil: the
      # license lives on the record page (see class note).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        ZIPS.map do |subdir, url|
          Nabu::Adapter::HttpProbeTarget.new(
            label: File.basename(url), zip_url: url, metadata_url: nil,
            state_subdir: subdir, state_file: Nabu::ZipFetch::STATE_FILE
          )
        end
      end

      # +translations+: when true (the registry row's posture — text_en
      # coverage is 100%), discover also yields one -en sibling ref per
      # document, parsed from the same newdoc slice.
      def initialize(translations: false)
        super()
        @translations = translations
      end

      # One DocumentRef per `# newdoc id` block of the corpus CoNLL-U file
      # (plus -en siblings when opted in), sorted by urn. A workdir without
      # the file yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Originals go to the ConlluParser over the document's newdoc slice
      # (citation = the numeric sent_id tail); -en refs (metadata "kind" =>
      # "translation") mint one English passage per `# text_en` sentence.
      def parse(document_ref)
        newdoc = document_ref.metadata.fetch("newdoc")
        info = DOCS.fetch(newdoc) do
          raise ParseError, "#{document_ref.path}: newdoc id #{newdoc.inspect} is not in the " \
                            "frozen v1.1 classification map — census upstream before ingesting"
        end
        slice = newdoc_slice(document_ref.path, newdoc)
        header = read_header(document_ref)
        if document_ref.metadata["kind"] == "translation"
          parse_translation(document_ref, slice, header)
        else
          parse_original(document_ref, slice, header, info)
        end
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download + unpack the two upstream zips via the shared ZipFetch
      # two-phase choreography (both staged, the mass-deletion breaker sees
      # the whole set, then both trees swap in). No network in tests:
      # WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        fetches = zip_fetches(workdir, progress)
        begin
          fetches.each_value(&:prepare!)
          guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
          fetches.each_value(&:complete!)
        ensure
          fetches.each_value(&:cleanup!)
        end
        report(fetches)
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "damaskini fetch failed into #{workdir}: #{e.message}"
      end

      private

      def zip_fetches(workdir, progress)
        ZIPS.to_h do |subdir, url|
          [subdir, Nabu::ZipFetch.new(
            url: url, dir: File.join(workdir, subdir),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir), progress: progress
          )]
        end
      end

      def report(fetches)
        shas = fetches.transform_values(&:sha)
        notes = shas.map { |subdir, sha| "#{subdir}=#{sha[0, 12]}" }.join(" ")
        atticked = fetches.values.sum { |fetch| fetch.atticked.size }
        notes = "#{notes} · atticked #{atticked} upstream-deleted file(s)" if atticked.positive?
        Nabu::FetchReport.new(
          sha: shas.fetch("conllu"), fetched_at: Time.now, notes: notes,
          repos: ZIPS.to_h { |subdir, url| [url, shas.fetch(subdir)] }
        )
      end

      def document_refs(workdir)
        conllu = conllu_path(workdir) or return []
        newdoc_ids(conllu).flat_map do |newdoc|
          original_ref(workdir, conllu, newdoc)
        end.sort_by(&:id)
      end

      def original_ref(workdir, conllu, newdoc)
        urn = "#{URN_PREFIX}#{newdoc.downcase}"
        tsv = tsv_path(workdir, newdoc)
        title = ref_title(tsv, newdoc)
        metadata = { "newdoc" => newdoc, "language" => DOCS.dig(newdoc, :language),
                     "title" => title, "tsv" => tsv }.compact
        refs = [Nabu::DocumentRef.new(source_id: manifest.id, id: urn, path: conllu,
                                      metadata: metadata)]
        if @translations
          refs << Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{urn}-en", path: conllu,
            metadata: metadata.merge("kind" => "translation", "language" => "eng",
                                     "title" => "#{title} — English translation")
          )
        end
        refs
      end

      def conllu_path(workdir)
        Dir.glob(File.join(workdir, "conllu", "**", "damaskini.conllu")).first
      end

      def tsv_path(workdir, newdoc)
        Dir.glob(File.join(workdir, "tsv", "**", "#{newdoc}.txt")).first
      end

      def ref_title(tsv, newdoc)
        return newdoc if tsv.nil?

        header = TsvHeader.read(tsv)
        base = header.title || header.source_name
        suffix = [header.title ? header.source_name : nil, header.date_raw].compact.join(", ")
        suffix.empty? ? base : "#{base} — #{suffix}"
      end

      # The `# newdoc id` lines of the corpus file, in document order — one
      # cheap streaming pass, no sentence parsing.
      def newdoc_ids(conllu)
        ids = []
        File.foreach(conllu, encoding: "UTF-8") do |line|
          ids << line.chomp.delete_prefix("# newdoc id = ") if line.start_with?("# newdoc id = ")
        end
        ids
      end

      # The lines of one newdoc block (its `# newdoc id` line through the
      # line before the next one), as an in-memory string for the streaming
      # parser. A block absent from the file is damage, not a rule.
      def newdoc_slice(conllu, newdoc)
        slice = +""
        inside = false
        File.foreach(conllu, encoding: "UTF-8") do |line|
          if line.start_with?("# newdoc id = ")
            break if inside

            inside = line.chomp == "# newdoc id = #{newdoc}"
            next
          end
          slice << line if inside
        end
        raise ParseError, "#{conllu}: newdoc id #{newdoc.inspect} not found" if slice.empty?

        slice
      end

      # The TSV sibling's header. Missing TSV = silent loss of the
      # date/place/scribe/title layer — damage, never a shrug.
      def read_header(document_ref)
        tsv = document_ref.metadata["tsv"]
        if tsv.nil? || !File.exist?(tsv)
          raise ParseError, "#{document_ref.id}: TSV sibling #{document_ref.metadata['newdoc']}.txt " \
                            "is missing — the header metadata layer would be silently lost"
        end
        TsvHeader.read(tsv)
      end

      def parse_original(document_ref, slice, header, info)
        newdoc = document_ref.metadata.fetch("newdoc")
        ConlluParser.new.parse(
          StringIO.new(slice),
          urn: document_ref.id, language: info.fetch(:language),
          title: document_ref.metadata["title"], canonical_path: document_ref.path,
          metadata: document_metadata(header, info),
          citation: ->(sent_id) { sent_id.delete_prefix("#{newdoc}.") }
        )
      end

      def document_metadata(header, info)
        facets = { "norm" => facet(info[:norm]) }
        facets["origin"] = facet(info[:origin]) if info[:origin]
        {
          "source_name" => header.source_name, "place" => header.place,
          "date" => header.date_raw, "scribe" => header.scribe, "locus" => header.notes,
          "facets" => facets
        }.compact
      end

      def facet(pair)
        { "value" => pair[0], "raw" => pair[1] }
      end

      # One English passage per `# text_en` sentence of the slice, cited by
      # the same numeric tail as its original — the Query::Parallel
      # verse-pair contract. Sentences without a translation (none in v1.1,
      # censused) are skipped honestly.
      def parse_translation(document_ref, slice, _header)
        newdoc = document_ref.metadata.fetch("newdoc")
        document = Nabu::Document.new(
          urn: document_ref.id, language: "eng", title: document_ref.metadata["title"],
          canonical_path: document_ref.path, metadata: { "kind" => "translation" }
        )
        each_text_en(slice, newdoc) do |cite, text, sequence|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{cite}", language: "eng",
            text: Normalize.nfc(text), sequence: sequence
          )
        end
        raise ParseError, "#{document_ref.id}: no text_en sentences in the newdoc slice" if document.empty?

        document
      end

      def each_text_en(slice, newdoc)
        cite = nil
        sequence = 0
        slice.each_line do |line|
          if line.start_with?("# sent_id = ")
            cite = line.chomp.delete_prefix("# sent_id = ").delete_prefix("#{newdoc}.")
          elsif line.start_with?("# text_en = ") && cite
            text = line.chomp.delete_prefix("# text_en = ")
            next if text.empty?

            yield cite, text, sequence
            sequence += 1
          end
        end
      end
    end
  end
end
