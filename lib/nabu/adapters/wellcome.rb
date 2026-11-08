# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "zlib"

require_relative "../redirect_follow"
require_relative "../zip_fetch"
require_relative "../zip_reader"
require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # wellcome: the Wellcome Collection's digitised printed books — the
    # library of the Wellcome Historical Medical Museum: early-modern
    # medicine, pharmacy, alchemy, natural philosophy, the academic
    # disputations of the European medical faculties — over the keyless
    # per-volume full-text zips at api.wellcomecollection.org/text/v1/
    # <bnumber>.zip (the IIIF manifest's own "Complete text as zip file"
    # rendering). Public Domain Mark per catalogue location licence and
    # manifest rights (http://creativecommons.org/publicdomain/mark/1.0/).
    #
    # == The census (the catalogue snapshot)
    #
    # The catalogue's own daily snapshot (CENSUS_URL, works.json.gz,
    # ~530 MB, one work per JSON line) is held whole in canonical and
    # derived into census.tsv (a declared materialization): one row per
    # DIGITISED bnumber (the b-number in the work's iiif-presentation
    # location URL — a work may carry two digitised copies) of every work
    # with workType "a" (Books) whose every iiif-presentation location is
    # licensed "pdm" (a mixed pdm/cc-by-nc work is out — 28 censused)
    # and whose production dates read a print year ≤ CENSUS_CEILING (the
    # source's whole PD-books horizon; later eras widen the cone, never
    # the census). The snapshot is refreshed every CENSUS_MAX_AGE_DAYS
    # (a conditional GET on its ETag; 304 keeps the held dump).
    #
    # Census through this adapter's own derivation over the 2026-11-08
    # snapshot (~10 s): 126,537 digitised bnumbers / 126,350 works ≤1899
    # in scope, 31,883 bnumbers / 31,740 works in the cone — against the
    # catalogue API's own counts (survey 2026-11) of 126,426 PDM works
    # ≤1899 and 31,839 PDM works ≤1799. The derivation reads the year from
    # the production-date LABELS (the dump carries no typed range), so the
    # residue is the label shapes no rule reads (French Republican "An
    # VI", "[date of publication not identified]", a blank label).
    #
    # == The cone — era 1, pre-1800 only, Latin-led
    #
    # The crawl takes only the CONE: census rows whose print year opens
    # ≤ CONE_CEILING (1799). Order: the Latin volumes (primary language
    # lat) first, then the Greek (grc, and MARC gre — see LANGUAGE_MAP),
    # then the rest of the cone; within each group by print year
    # ascending, then bnumber. A cone widening (the ≤1899 Latin/Greek/
    # Hebrew/Arabic wave the survey names) is a constant change here —
    # a phase decision, never automatic.
    #
    # == The paced, resumable crawl (the ndl-kotenseki mould)
    #
    # ETIQUETTE: iiif.wellcomecollection.org/robots.txt says "Crawl-delay:
    # 30 / Request-rate: 1/30s"; the api host serves no robots.txt, but the
    # text zips are the same digitisation service, so the crawl honours ONE
    # request per DELAY (30 s) there too. Never lower. The census GET goes
    # to data.wellcomecollection.org (the S3 snapshot) and is not paced.
    #
    # Per sync: up to SLICE bnumbers of the cone order that are neither
    # held (zips/<bnumber>.zip on disk is done) nor ledgered. Every
    # refusal class is ledgered in .wellcome-crawl.json and NEVER retried
    # blindly (a re-census may deliberately clear a class — a phase
    # decision): "missing" (HTTP 404 "No text resource found" — the
    # volume is digitised but has no OCR text — see DEFERRED_DIGCODES),
    # "denied" (401/403/410), "empty" (a zip whose members carry no
    # letter — real: some digearly zips hold one 0-byte member),
    # "malformed" (a 200 whose body is not a readable zip) and
    # "timeout-stuck" (TIMEOUT_ATTEMPTS timeouts with backoff — the NDL
    # timeout-wedge fix). A 429 beyond RedirectFollow's one Retry-After
    # pause STOPS the slice cleanly (ledger written, the next sync
    # resumes); any other failure stays fatal — the crawl is resumable.
    # The ledger also carries the position ("done" — the held bnumbers —
    # and the cone size), so a reader sees where the crawl stands without
    # walking the tree.
    #
    # == Documents and passages
    #
    # Document = VOLUME: one member .txt of a held zip (a single-volume
    # work's zip holds <bnumber>.txt; a multi-part work's holds
    # <bnumber>_0001.txt, _0002 … — the IIIF manifestation ids), urn
    # urn:nabu:wellcome:<member basename>. The zip is kept verbatim (the
    # upstream bytes) and read through SourceRead at parse.
    #
    # PASSAGE GRAIN — DECLARED: upstream's text is ONE unbroken stream per
    # volume (no page breaks, no line terminators — censused 2026-11-08 on
    # b33275154: 1,294,416 bytes on a single line; the per-volume raw text
    # endpoint answers the identical bytes). Per-page text exists only as
    # one ALTO/annotation GET per canvas — 636 requests for that one
    # volume, 5 h at the etiquette pace — so the page is out of reach. The
    # passage is a fixed-size SEGMENT: ~SEGMENT_CHARS characters (about one
    # printed page — b33275154 averages 2,035 characters per canvas), words
    # packed greedily up to the size and cut only at whitespace (a run longer
    # than the size — OCR noise — is hard-cut), cited by its ordinal
    # (…:b33275154_0001:12), its character offset in the volume in
    # annotations. Deterministic over the held bytes, so urns are stable;
    # NOT a page — the segment never claims one. Letterless segments skip
    # by rule (counted in metadata).
    #
    # Every document carries text_nature "machine-ocr" (the OCR is
    # uncorrected: long-s noise, garbage title leaves) and the catalogue
    # permalink.
    #
    # == Axes
    #
    # Language: the catalogue's languages field (MARC 21 codes), the FIRST
    # listed as the volume's claim, every code in metadata; ISO 639-2/B
    # bibliographic codes map to the 639-3 tag (LANGUAGE_MAP); a work with
    # no language field claims "und" (285 cone volumes). Date: the
    # production date labels → a print-year envelope, date_class EDITION
    # (the catalogue records the print's date; no field marks original
    # composition separately, so no composition claim is made — the
    # staging law excludes edition dates by design). Place: the first
    # production place label (brackets stripped), every label in "places".
    # Genres and subjects facet verbatim (genres fold in kind_map.yml);
    # contributors facet as author.
    class Wellcome < Nabu::Adapter
      CENSUS_URL = "https://data.wellcomecollection.org/catalogue/v2/works.json.gz"
      CENSUS_DUMP = "works.json.gz"
      CENSUS_TSV = "census.tsv"
      CENSUS_STATE = ".wellcome-census.json"
      ZIPS_DIRNAME = "zips"
      LEDGER_FILE = ".wellcome-crawl.json"
      ZIP_URL = "https://api.wellcomecollection.org/text/v1/%s.zip"
      WORK_URL = "https://wellcomecollection.org/works/%s"
      MANIFEST_URL = "https://iiif.wellcomecollection.org/presentation/v3/%s"
      URN_PREFIX = "urn:nabu:wellcome:"

      # The etiquette: one request per 30 s on the text host (the IIIF
      # host's robots Request-rate, honoured on its sibling). Never lower.
      DELAY = 30.0
      # Bnumbers per sync — one slice of the multi-phase crawl: 240 × 30 s
      # = 2 h of paced requests (+ the ~530 MB census download on the
      # first run and at each refresh). The whole cone (31,883 bnumbers)
      # is ~11 days of pace (8.3 before the deferred tail) — a
      # multi-phase crawl by construction.
      SLICE = 240
      # Days before the held catalogue snapshot is re-checked (a
      # conditional GET on its ETag).
      CENSUS_MAX_AGE_DAYS = 30

      TIMEOUT_ATTEMPTS = 3
      TIMEOUT_BACKOFF = 30.0
      STUCK = "timeout-stuck"
      LEDGER_CLASSES = ["missing", "denied", "empty", "malformed", STUCK].freeze
      TIMEOUT_PATTERN = /transport error for .*(timeout|timed out|execution expired)/i

      # The census scope and the era-1 cone (see the header).
      CENSUS_CEILING = 1899
      CONE_CEILING = 1799
      # The cone's lead groups, in crawl order; everything else follows.
      CONE_LEADS = [%w[lat], %w[grc gre]].freeze
      # Digitisation programmes (the catalogue's wellcome-digcode
      # identifier) whose volumes the text service answers 404: the
      # ProQuest Early European Books scans. Yield sample 2026-11-08 (41
      # paced GETs over the order's head and across the cone): all 19
      # digproquest volumes answered 404 "No text resource found", all 22
      # others (digukmhl, digearly, uncoded) served their zip — 3 of them
      # a 0-byte member. 7,952 of the 31,883 cone bnumbers (4,865 of them
      # Latin — every incunable in the cone) carry it; at the pace they
      # are a 66-hour 404 desert, so they are DEFERRED to the cone's tail
      # in the same order — never dropped: the phase that reaches them
      # re-samples first.
      DEFERRED_DIGCODES = %w[digproquest].freeze
      # Print years outside this window are not print years: Hijri dates
      # catalogued beside their CE conversion ("1302 [1886]"), typos
      # ("1791-1082"), the French Republican "An X = 1082 [i.e. 1802]".
      PRINT_FLOOR = 1450
      PRINT_SANITY = 2030

      # The catalogue's own no-place statements (RDA "[Place of publication
      # not identified]", the older "S.l." / sine loco) — they name no place.
      NO_PLACE = /not identified|\As\.\s*l\b|sine loco/i

      SEGMENT_CHARS = 2000
      MEMBER = /\A(b\d{7}[\dx])(?:_(\d{4}))?\.txt\z/
      BNUMBER = /\Ab\d{7}[\dx]\z/

      # ISO 639-2/B (bibliographic) → 639-3: the catalogue speaks MARC 21
      # language codes. Every other censused code (lat, eng, ita, spa, por,
      # swe, heb, dan, ara, rus, syc, urd, ota, frm, gmh, ang, pol, yid,
      # bre, goh, enm …) is already the 639-3 tag and passes through.
      # MARC gre is "Greek, Modern (1453- )"; legacy records coded Greek of
      # every period gre, and in the ≤1799 cone the 28 gre-first rows are
      # Galen, Dioscorides, Paul of Aegina, Nicander — ancient Greek texts
      # in Renaissance editions, so a cone print's gre claims grc
      # (declared); after the cone it is ell.
      LANGUAGE_MAP = {
        "fre" => "fra", "ger" => "deu", "dut" => "nld", "per" => "fas", "cze" => "ces",
        "arm" => "hye", "ice" => "isl", "chi" => "zho", "wel" => "cym", "alb" => "sqi",
        "bur" => "mya", "geo" => "kat", "mac" => "mkd", "mao" => "mri", "may" => "msa",
        "rum" => "ron", "slo" => "slk", "tib" => "bod", "baq" => "eus", "gre" => "ell"
      }.freeze
      UNDETERMINED = "und"

      # census.tsv columns (pid-first, the ndl-kotenseki shape).
      CENSUS_COLUMNS = %w[bnumber work_id title languages not_before not_after dates places publishers
                          production contributors genres subjects physical digcodes].freeze
      CENSUS_HEADER = CENSUS_COLUMNS.join("\t").freeze
      LIST_SEPARATOR = "||"

      OCR_NOTE = "Wellcome Collection's uncorrected OCR full text (the IIIF 'Complete text as zip " \
                 "file' rendering): one unbroken stream per volume, no page breaks — passages are " \
                 "fixed-size segments cut at whitespace, never pages"

      MANIFEST = Nabu::SourceManifest.new(
        id: "wellcome",
        name: "Wellcome Collection — digitised printed books, OCR full text (pre-1800 cone)",
        license: "Public Domain Mark 1.0 (catalogue location licence \"pdm\"; IIIF manifest rights " \
                 "http://creativecommons.org/publicdomain/mark/1.0/). Credit: Wellcome Collection; " \
                 "the text is Wellcome's uncorrected OCR, not an edition. Catalogue metadata from the " \
                 "Wellcome Collection catalogue snapshot (data.wellcomecollection.org, CC0)",
        license_class: "open",
        upstream_url: "https://wellcomecollection.org/collections",
        parser_family: "wellcome-text-zip"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "catalogue snapshot", zip_url: CENSUS_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # census.tsv is derived beside the upstream snapshot at fetch.
      def self.materialized_paths = [CENSUS_TSV]

      def initialize(delay: DELAY, slice: SLICE, http: Nabu::ZipFetch.default_http,
                     timeout_backoff: TIMEOUT_BACKOFF, clock: -> { Time.now })
        super()
        @delay = delay
        @slice = slice
        @timeout_backoff = timeout_backoff
        @http = http
        @clock = clock
        @requests = 0
      end

      # -- the year reading (public: the census derivation and the tests) ----

      # Every print year one production date label states. An "i.e."
      # correction answers alone ("1650 [i.e. 1651]" → 1651); otherwise
      # every 4-digit year inside [PRINT_FLOOR, PRINT_SANITY] (the Hijri
      # year beside its CE bracket drops by range). Without an Arabic year:
      # a Roman-numeral year ("M.DCC.XLV" → 1745), then a decade/century
      # mark ("[188?]" → 1880–1889, "17--" / "[18-?]" → the century).
      def self.label_years(label)
        text = label.to_s
        corrected = text.scan(/i\.\s*e\.?,?\s*\[?(\d{4})(?!\d)/i).flatten
        digits = corrected.empty? ? text.scan(/(?<!\d)(\d{4})(?!\d)/).flatten : corrected
        years = digits.map { |year| Integer(year, 10) }.select { |year| print_year?(year) }
        return years unless years.empty? && corrected.empty?

        roman_years(text).then { |found| found.empty? ? partial_years(text) : found }
      end

      def self.print_year?(year) = year.between?(PRINT_FLOOR, PRINT_SANITY)

      ROMAN = { "M" => 1000, "D" => 500, "C" => 100, "L" => 50, "X" => 10, "V" => 5, "I" => 1 }.freeze
      ROMAN_TOKEN = /(?<![A-Za-z])M[MDCLXVI.\s]*[MDCLXVI](?![a-z])/

      def self.roman_years(text)
        text.scan(ROMAN_TOKEN).filter_map do |token|
          value = roman_value(token.gsub(/[^MDCLXVI]/, ""))
          value if value && print_year?(value)
        end
      end

      def self.roman_value(letters)
        values = letters.chars.map { |char| ROMAN.fetch(char) }
        total = values.each_with_index.sum do |value, index|
          following = values[index + 1]
          following && following > value ? -value : value
        end
        roman_string(total) == letters ? total : nil
      end

      def self.roman_string(number)
        [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"], [50, "L"],
         [40, "XL"], [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]].each_with_object(+"") do |(value, mark), out|
          while number >= value
            out << mark
            number -= value
          end
        end
      end

      def self.partial_years(text)
        if (decade = text[/(?<!\d)(1[4-9]\d)[-?](?!\d)/, 1])
          base = Integer(decade, 10) * 10
          return [base, base + 9]
        end
        century = text[/(?<!\d)(1[4-9])(?:--|-\?)/, 1]
        return [] unless century

        base = Integer(century, 10) * 100
        [base, base + 99]
      end

      # The volume's language claim from the catalogue's code list (first
      # code; MARC → 639-3; gre → grc for a cone print — see LANGUAGE_MAP).
      def self.language_for(codes, not_before:)
        code = Array(codes).first.to_s.strip
        return UNDETERMINED if code.empty?
        return "grc" if code == "gre" && not_before && not_before <= CONE_CEILING

        LANGUAGE_MAP.fetch(code, code)
      end

      # The cone's crawl group: 0 Latin, 1 Greek, 2 the rest.
      def self.cone_group(codes)
        first = Array(codes).first.to_s
        CONE_LEADS.index { |lead| lead.include?(first) } || CONE_LEADS.size
      end

      # The census rows of the cone, in crawl order (see the header) —
      # bnumbers, deduplicated.
      def self.cone_order(table)
        rows = table.each_value.select do |row|
          year = row["not_before"].to_s
          !year.empty? && Integer(year, 10) <= CONE_CEILING
        end
        rows.sort_by { |row| cone_key(row) }.map { |row| row["bnumber"] }.uniq
      end

      def self.cone_key(row)
        [deferred?(row) ? 1 : 0, cone_group(row["languages"].to_s.split(",")), Integer(row["not_before"], 10),
         row["bnumber"]]
      end

      # A census row whose digitisation programme serves no text (see
      # DEFERRED_DIGCODES) waits at the cone's tail.
      def self.deferred?(row) = row["digcodes"].to_s.split(",").intersect?(DEFERRED_DIGCODES)

      # The volume text's segments: [[ordinal, offset, text], …] — see the
      # header. Greedy whitespace packing: words (with the whitespace
      # between them, verbatim) fill a segment up to +size+ characters; a
      # single run longer than +size+ (OCR noise) is hard-cut. +offset+ is
      # the segment's first character in the volume. One linear pass over
      # the words — never character indexing into the (multi-MB, multibyte)
      # string, which is O(n) per access. Ordinals count every segment, the
      # letterless included, so a skipped one leaves an honest gap.
      def self.segments(text, size: SEGMENT_CHARS)
        out = []
        current = nil
        start = 0
        offset = 0
        text.scan(/(\s*)(\S+)/) do |space, word|
          position = offset + space.length
          offset = position + word.length
          if current && current.length + space.length + word.length <= size
            current << space << word
            next
          end
          out << [out.size + 1, start, current] if current
          current, start = hard_cut(word, position, size, out)
        end
        out << [out.size + 1, start, current] if current
        out
      end

      # Emits the full +size+ pieces of an over-long +word+ into +out+;
      # returns the remainder as the new open segment [text, offset].
      def self.hard_cut(word, position, size, out)
        while word.length > size
          out << [out.size + 1, position, word[0, size]]
          word = word[size..]
          position += size
        end
        [+word, position]
      end

      # The derived census.tsv as {bnumber => {column => value}} ({} when
      # absent).
      def self.census_table(path)
        return {} unless File.file?(path)

        header = nil
        SourceRead.utf8_lines(path, label: "wellcome census").each_with_object({}) do |line, rows|
          values = line.chomp.split("\t", -1)
          (header = values) && next if header.nil?

          rows[values[0]] = header.zip(values).to_h
        end
      end

      # One catalogue work (a parsed dump line) → its census rows (one per
      # digitised bnumber), or [] when the work is out of the census scope.
      def self.census_rows(work)
        return [] unless work["type"] == "Work" && work.dig("workType", "id") == "a"

        locations = Array(work["items"]).flat_map { |item| Array(item["locations"]) }
                                        .select { |loc| loc.dig("locationType", "id") == "iiif-presentation" }
        return [] if locations.empty? || locations.any? { |loc| loc.dig("license", "id") != "pdm" }

        events = Array(work["production"])
        labels = events.flat_map { |event| Array(event["dates"]).map { |date| date["label"].to_s } }
        years = labels.flat_map { |label| label_years(label) }
        return [] if years.empty? || years.min > CENSUS_CEILING

        bnumbers = locations.filter_map { |loc| loc["url"].to_s[%r{/(b\d{7}[\dx])(?:\b|_)}, 1] }.uniq
        row = census_fields(work, events, labels, years)
        bnumbers.map { |bnumber| [bnumber, *row] }
      end

      # One TSV cell from a list of catalogue values (tabs/newlines folded,
      # blanks dropped, ||-joined).
      def self.tsv_cell(values)
        values.map { |value| value.to_s.tr("\t\n\r", "   ").strip }.reject(&:empty?).join(LIST_SEPARATOR)
      end

      def self.census_fields(work, events, labels, years)
        join = method(:tsv_cell)
        [
          work["id"].to_s, join.call([work["title"]]),
          Array(work["languages"]).map { |lang| lang["id"] }.join(","),
          years.min.to_s, years.max.to_s, join.call(labels),
          join.call(events.flat_map { |event| Array(event["places"]).map { |place| place["label"] } }),
          join.call(events.flat_map { |event| Array(event["agents"]).map { |agent| agent["label"] } }),
          join.call(events.map { |event| event["label"] }),
          join.call(Array(work["contributors"]).map { |contributor| contributor.dig("agent", "label") }),
          join.call(Array(work["genres"]).map { |genre| genre["label"] }),
          join.call(Array(work["subjects"]).map { |subject| subject["label"] }),
          join.call([work["physicalDescription"]]),
          Array(work["identifiers"]).select { |id| id.dig("identifierType", "id") == "wellcome-digcode" }
                                    .map { |id| id["value"] }.join(",")
        ]
      end

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever deletes.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        ensure_census!(workdir, progress)
        order = self.class.cone_order(census(workdir))
        ledger = read_ledger(workdir)
        tally = crawl_slice!(workdir, order, ledger, progress)
        held = held_bnumbers(workdir)
        write_ledger!(workdir, ledger, held: held, cone: order.size)
        notes = crawl_notes(held, order, ledger, tally)
        progress&.call("#{notes}\n")
        Nabu::FetchReport.new(sha: crawl_sha(workdir, held, ledger), fetched_at: @clock.call, notes: notes)
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        zip_paths(workdir).each do |path|
          members(path).each do |member|
            volume = File.basename(member, ".txt")
            yield Nabu::DocumentRef.new(
              source_id: MANIFEST.id, id: "#{URN_PREFIX}#{volume}", path: File.expand_path(path),
              metadata: { "bnumber" => File.basename(path, ".zip"), "member" => member }
            )
          end
        end
      end

      def discovery_skips(workdir)
        notes = []
        rule = 0
        unreadable = 0
        zip_paths(workdir).each do |path|
          entries = zip_entries(path)
          if entries.nil?
            unreadable += 1
            notes << "unreadable zip: #{path.delete_prefix("#{workdir}/")}"
            next
          end
          entries.each do |name, size|
            reason = if !name.match?(MEMBER) then "non-volume zip member"
                     elsif size.zero? then "empty volume text (upstream serves a 0-byte member)"
                     end
            next unless reason

            rule += 1
            notes << "#{reason} skipped by rule: #{File.basename(path)}:#{name}"
          end
        end
        strays = stray_files(workdir)
        notes.concat(strays.map { |rel| "non-corpus file: #{rel}" })
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: rule, unrecognized: strays.size + unreadable, notes: notes)
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        member = document_ref.metadata.fetch("member")
        bnumber = document_ref.metadata.fetch("bnumber")
        text = volume_text(document_ref.path, member)
        row = census_row(File.dirname(document_ref.path, 2), bnumber)
        not_before = row["not_before"].to_s.empty? ? nil : Integer(row["not_before"], 10)
        language = self.class.language_for(row["languages"].to_s.split(","), not_before: not_before)
        volumes = member_count(document_ref.path)
        passages, skipped = segment_passages(document_ref.id, text, language)
        raise Nabu::ParseError, "#{document_ref.path}:#{member}: no segment with letters" if passages.empty?

        document = Nabu::Document.new(
          urn: document_ref.id, language: language, canonical_path: document_ref.path,
          title: title_for(row, member, volumes),
          metadata: metadata_for(bnumber, member, row, not_before, volumes, text, skipped)
        )
        passages.each { |passage| document << passage }
        document
      end

      private

      # -- census internals --------------------------------------------------

      def ensure_census!(workdir, progress)
        dump = File.join(workdir, CENSUS_DUMP)
        state = read_json(File.join(workdir, CENSUS_STATE))
        refreshed = if !File.file?(dump)
                      download_census!(workdir, progress, etag: nil)
                    elsif census_stale?(state)
                      download_census!(workdir, progress, etag: state["etag"])
                    else
                      false
                    end
        tsv = File.join(workdir, CENSUS_TSV)
        derive_census!(dump, tsv, progress) if refreshed || !File.file?(tsv) || !census_current?(tsv)
      end

      def census_stale?(state)
        fetched = state["fetched_at"].to_s
        return true if fetched.empty?

        (@clock.call - Time.iso8601(fetched)) > CENSUS_MAX_AGE_DAYS * 86_400
      rescue ArgumentError
        true
      end

      # Streams the snapshot to <dump>.part (never held in memory), then
      # renames. Returns true when new bytes landed, false on a 304.
      def download_census!(workdir, progress, etag:)
        dump = File.join(workdir, CENSUS_DUMP)
        part = "#{dump}.part"
        progress&.call("Checking the catalogue snapshot (#{CENSUS_URL})…\n")
        headers = { "User-Agent" => Nabu::WikiFetch::USER_AGENT }
        headers["If-None-Match"] = etag if etag
        response = stream_census(part, headers)
        if response.status == 304
          FileUtils.rm_f(part)
          write_census_state!(workdir, response, dump)
          return false
        end
        File.rename(part, dump)
        write_census_state!(workdir, response, dump)
        true
      ensure
        FileUtils.rm_f(part) if part && File.exist?(part)
      end

      # The GET, its body streamed chunk by chunk into +part+ (a write
      # handle — the per-hop sink truncates, so a redirect hop's body never
      # pollutes the artifact; a transport that ignores on_data buffers,
      # and the body is written whole).
      def stream_census(part, headers)
        file = File.new(part, "wb")
        sink = lambda do
          file.truncate(0)
          file.rewind
          proc { |chunk, _received| file.write(chunk) }
        end
        response, = Nabu::RedirectFollow.get(CENSUS_URL, http: @http, error: Nabu::FetchError,
                                                         headers: headers, accept: [200, 304], stream: sink)
        file.write(response.body.to_s.b) if response.status == 200 && file.pos.zero?
        response
      ensure
        file&.close
      end

      def write_census_state!(workdir, response, dump)
        state = { "url" => CENSUS_URL, "etag" => response.headers["etag"],
                  "last_modified" => response.headers["last-modified"],
                  "fetched_at" => @clock.call.utc.iso8601, "bytes" => File.size(dump) }
        previous = read_json(File.join(workdir, CENSUS_STATE))
        state["etag"] ||= previous["etag"]
        state["last_modified"] ||= previous["last_modified"]
        File.write(File.join(workdir, CENSUS_STATE), JSON.pretty_generate(state.compact))
      end

      def census_current?(tsv)
        SourceRead.utf8_lines(tsv, label: "wellcome census").first.to_s.chomp == CENSUS_HEADER
      end

      # Streams the gzipped JSON-lines snapshot; only lines naming an
      # iiif-presentation location AND a pdm licence are parsed at all.
      def derive_census!(dump, tsv, progress)
        progress&.call("Deriving the census from #{CENSUS_DUMP}…\n")
        lines = [CENSUS_HEADER]
        each_dump_line(dump) do |line|
          next unless line.include?('"iiif-presentation"') && line.include?('"pdm"')

          self.class.census_rows(JSON.parse(line)).each { |row| lines << row.join("\t") }
        end
        rows = lines.size - 1
        File.write("#{tsv}.tmp", "#{lines.join("\n")}\n")
        File.rename("#{tsv}.tmp", tsv)
        @census = nil
        progress&.call("census: #{rows} digitised PDM volume(s) ≤#{CENSUS_CEILING}\n")
      rescue JSON::ParserError, Zlib::Error => e
        FileUtils.rm_f("#{tsv}.tmp")
        raise Nabu::FetchError, "#{MANIFEST.id}: unreadable catalogue snapshot: #{e.message}"
      end

      def each_dump_line(dump, &)
        Zlib::GzipReader.open(dump) do |gz|
          gz.each_line do |line|
            yield SourceRead.utf8(line, label: "wellcome catalogue snapshot line")
          end
        end
      rescue Nabu::ParseError => e
        raise Nabu::FetchError, e.message
      end

      def census(workdir)
        @census ||= {}
        @census[workdir] ||= self.class.census_table(File.join(workdir, CENSUS_TSV))
      end

      def census_row(workdir, bnumber) = census(workdir)[bnumber] || {}

      # -- crawl internals ---------------------------------------------------

      def crawl_slice!(workdir, order, ledger, progress)
        skip = LEDGER_CLASSES.flat_map { |key| ledger.fetch(key, []) }.to_set
        tally = Hash.new(0)
        tally[:stuck_list] = []
        attempted = 0
        order.each do |bnumber|
          break if attempted >= @slice
          next if skip.include?(bnumber) || File.file?(zip_path(workdir, bnumber))

          attempted += 1
          outcome = fetch_with_retries!(workdir, bnumber, progress)
          if outcome == :rate_limited
            tally[:rate_limited] = true
            break
          end

          record_outcome!(ledger, tally, bnumber, outcome)
          progress&.call("crawl: #{attempted}/#{@slice} — +#{tally[:ok]} held, #{tally[:missing]} missing…\n") if
            (attempted % 20).zero?
        end
        tally
      ensure
        write_ledger!(workdir, ledger, held: held_bnumbers(workdir), cone: order.size) if ledger
      end

      def record_outcome!(ledger, tally, bnumber, outcome)
        tally[outcome] += 1
        return if outcome == :ok

        klass = outcome == :timeout ? STUCK : outcome.to_s
        (ledger[klass] ||= []) << bnumber
        tally[:stuck_list] << bnumber if outcome == :timeout
      end

      def fetch_with_retries!(workdir, bnumber, progress)
        TIMEOUT_ATTEMPTS.times do |attempt|
          outcome = fetch_zip!(workdir, bnumber)
          return outcome unless outcome == :timeout
          break if attempt == TIMEOUT_ATTEMPTS - 1

          progress&.call("crawl: #{bnumber} timed out (attempt #{attempt + 1}/#{TIMEOUT_ATTEMPTS}), retrying…\n")
          backoff = @timeout_backoff * (2**attempt)
          sleep(backoff) if backoff.positive?
        end
        progress&.call("crawl: #{bnumber} timed out #{TIMEOUT_ATTEMPTS}× — ledgered #{STUCK}\n")
        :timeout
      end

      # One paced GET → :ok (zip held) / :missing / :denied / :empty /
      # :malformed / :timeout / :rate_limited.
      def fetch_zip!(workdir, bnumber)
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        response, = Nabu::RedirectFollow.get(format(ZIP_URL, bnumber),
                                             http: @http, error: Nabu::FetchError,
                                             headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        body = response.body.to_s.b
        verdict = zip_verdict(body)
        return verdict unless verdict == :ok

        target = zip_path(workdir, bnumber)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite("#{target}.part", body)
        File.rename("#{target}.part", target)
        :ok
      rescue Nabu::FetchError => e
        return :timeout if e.message.match?(TIMEOUT_PATTERN)
        return :missing if e.message.match?(/HTTP 404\b/)
        return :denied if e.message.match?(/HTTP (?:401|403|410)\b/)
        return :rate_limited if e.message.match?(/HTTP 429\b/)

        raise
      end

      def zip_verdict(body)
        zip = Nabu::ZipReader.new(body)
        texts = zip.entries.select { |entry| entry.name.match?(MEMBER) }
        return :malformed if texts.empty?

        lettered = texts.any? do |entry|
          SourceRead.utf8_member(zip, entry, label: "wellcome zip").match?(/\p{L}/)
        rescue Nabu::ParseError
          false
        end
        lettered ? :ok : :empty
      rescue Nabu::ZipReader::Error
        :malformed
      end

      def crawl_notes(held, order, ledger, tally)
        ledgered = LEDGER_CLASSES.sum { |key| ledger.fetch(key, []).size }
        stuck = tally[:stuck_list]
        notes = "crawl at #{held.size}/#{order.size} cone volume(s) held, #{ledgered} ledgered " \
                "(+#{tally[:ok]} this sync; #{tally[:missing]} missing text, #{tally[:denied]} denied, " \
                "#{tally[:empty]} empty, #{tally[:malformed]} malformed, #{stuck.size} stuck on timeout" \
                "#{" (#{stuck.join(', ')})" unless stuck.empty?})"
        notes += "; STOPPED on HTTP 429 (rate-limited) — the next sync resumes" if tally[:rate_limited]
        notes
      end

      def zip_path(workdir, bnumber) = File.join(workdir, ZIPS_DIRNAME, "#{bnumber}.zip")

      def zip_paths(workdir)
        Dir.glob(File.join(workdir, ZIPS_DIRNAME, "*.zip"))
           .select { |path| File.basename(path, ".zip").match?(BNUMBER) }.sort
      end

      def held_bnumbers(workdir) = zip_paths(workdir).map { |path| File.basename(path, ".zip") }

      def read_ledger(workdir)
        blank = LEDGER_CLASSES.to_h { |key| [key, []] }
        stored = read_json(File.join(workdir, LEDGER_FILE))
        blank.merge(stored.slice(*LEDGER_CLASSES))
      end

      # The ledger: the refusal classes (sorted, unique) + the position.
      def write_ledger!(workdir, ledger, held:, cone:)
        payload = LEDGER_CLASSES.to_h { |key| [key, ledger.fetch(key, []).uniq.sort] }
        payload["position"] = { "cone" => cone, "done" => held.size,
                                "ledgered" => LEDGER_CLASSES.sum { |key| payload[key].size } }
        payload["done"] = held
        File.write(File.join(workdir, LEDGER_FILE), JSON.pretty_generate(payload))
      end

      def read_json(path)
        return {} unless File.file?(path)

        JSON.parse(SourceRead.utf8_file(path, label: "wellcome state"))
      rescue JSON::ParserError, Nabu::ParseError
        {}
      end

      # The crawl identity: the census bytes, the held zips, the ledgered
      # classes (the position block is derived, never identity).
      def crawl_sha(workdir, held, ledger)
        tsv = File.join(workdir, CENSUS_TSV)
        census = File.file?(tsv) ? Digest::SHA256.file(tsv).hexdigest : ""
        parts = [census, held, LEDGER_CLASSES.map { |key| ledger.fetch(key, []).uniq.sort }]
        Digest::SHA256.hexdigest(JSON.generate(parts))
      end

      # -- discovery/parse internals -----------------------------------------

      # [[member name, uncompressed size], …] from the central directory,
      # or nil for an unreadable zip.
      def zip_entries(path)
        SourceRead.zip_file(path).entries.map do |entry|
          [entry.name.b.dup.force_encoding(Encoding::UTF_8).scrub, entry.uncompressed_size]
        end
      rescue Nabu::ZipReader::Error
        nil
      end

      # The volume members that carry text (a 0-byte member skips by rule).
      def members(path)
        Array(zip_entries(path)).select { |name, size| name.match?(MEMBER) && size.positive? }.map(&:first).sort
      end

      def member_count(path) = members(path).size

      def volume_text(path, member)
        zip = SourceRead.zip_file(path)
        entry = zip.entries.find { |candidate| candidate.name.b == member.b }
        raise Nabu::ParseError, "#{path}: no member #{member}" unless entry

        SourceRead.utf8_member(zip, entry, label: path)
      rescue Nabu::ZipReader::Error => e
        raise Nabu::ParseError, "#{path}: unreadable zip: #{e.message}"
      end

      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .reject { |path| File.basename(path).start_with?(".") }
           .grep_v(%r{/#{ZIPS_DIRNAME}/b\d{7}[\dx]\.zip\z})
           .reject { |path| [CENSUS_DUMP, CENSUS_TSV].include?(File.basename(path)) }
           .map { |path| path.delete_prefix("#{workdir}/") }
           .reject { |rel| ["README.md", "manifest.yml"].include?(rel) } # the fixture sentinel's (the sigla precedent)
           .sort
      end

      def title_for(row, member, volumes)
        title = row["title"].to_s.strip
        title = File.basename(member, ".txt") if title.empty?
        volume = member[MEMBER, 2]
        title = "#{title} — volume #{Integer(volume, 10)}" if volume && volumes > 1
        Normalize.nfc(title)
      end

      # [passages for the segments with letters, the letterless count].
      def segment_passages(urn, text, language)
        skipped = 0
        passages = []
        self.class.segments(text).each do |ordinal, offset, segment|
          segment = SourceRead.nfc(segment, language: language)
          next skipped += 1 unless segment.match?(/\p{L}/)

          passages << Nabu::Passage.new(
            urn: "#{urn}:#{ordinal}", language: language, text: segment,
            sequence: passages.size + 1,
            annotations: { "segment" => ordinal, "offset" => offset }
          )
        end
        [passages, skipped]
      end

      def list(row, key)
        values = row[key].to_s.split(LIST_SEPARATOR).map { |value| Normalize.nfc(value.strip) }
        values.reject(&:empty?)
      end

      def metadata_for(bnumber, member, row, not_before, volumes, text, skipped)
        metadata = {
          "text_nature" => "machine-ocr", "ocr_note" => OCR_NOTE,
          "bnumber" => bnumber, "volume" => File.basename(member, ".txt"), "volumes_in_zip" => volumes,
          "manifest" => format(MANIFEST_URL, bnumber), "text_chars" => text.length,
          "segments_letterless" => skipped
        }
        metadata["permalink"] = format(WORK_URL, row["work_id"]) unless row["work_id"].to_s.empty?
        metadata["work_id"] = row["work_id"] unless row["work_id"].to_s.empty?
        metadata["digcodes"] = row["digcodes"].split(",") unless row["digcodes"].to_s.empty?
        codes = row["languages"].to_s.split(",")
        unless codes.empty?
          metadata["languages_marc"] = codes
          metadata["languages"] = codes.map { |code| self.class.language_for([code], not_before: not_before) }.uniq
        end
        metadata["physical"] = Normalize.nfc(row["physical"]) unless row["physical"].to_s.empty?
        %w[production publishers contributors].each do |key|
          metadata[key] = list(row, key) unless list(row, key).empty?
        end
        add_axes!(metadata, row, not_before)
        facets = facets_for(row)
        metadata["facets"] = facets unless facets.empty?
        metadata
      end

      # The print-year envelope (class edition) and the imprint place.
      def add_axes!(metadata, row, not_before)
        if not_before
          metadata["date"] = { "not_before" => not_before, "not_after" => Integer(row["not_after"], 10),
                               "raw" => list(row, "dates").join(" | "), "class" => "edition" }
        end
        places = list(row, "places")
        return if places.empty?

        metadata["places"] = places
        first = places.first.delete("[]").sub(/[\s:;,.]+\z/, "").strip
        metadata["place"] = first unless first.empty? || first.match?(NO_PLACE)
      end

      def facets_for(row)
        { "genre" => "genres", "subject" => "subjects",
          "author" => "contributors" }.each_with_object({}) do |(facet, column), out|
          values = list(row, column).uniq
          out[facet] = { "values" => values } unless values.empty?
        end
      end
    end
  end
end
