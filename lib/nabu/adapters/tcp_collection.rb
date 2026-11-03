# frozen_string_literal: true

require_relative "tcp_xml_parser"
require_relative "eebo_tcp"
require_relative "tcp_box_fetch"
require_relative "source_read"

module Nabu
  module Adapters
    # The shared shape of the TCP's two smaller collections (Evans-TCP,
    # ECCO-TCP): the EEBO-TCP adapter's judgments over the same P4 <ETS>
    # schema, composed rather than inherited — the tcp-xml family parses,
    # EeboTcp's imprint-date molds, imprint-place reading, CC0 marker and
    # LANGUSAGE aliases judge, TcpBoxFetch acquires. A subclass names its
    # manifest, its Fetch (a TcpBoxFetch with the collection's channel) and
    # the typed header IDNOs it mines.
    #
    #   document urn  urn:nabu:<slug>:<TCPID>         (…:evans-tcp:N31062)
    #   passage urn   <document-urn>:<div-path>.<unit>
    #
    # == Identity
    #
    # The filename stem (".p4.xml" stripped) IS the TCP id, and <IDG ID>
    # equals it on every file of both collections (Evans ×5,012, ECCO
    # ×3,101 — 0 mismatches, census 2026-11-03);
    # IDG rides metadata as the crosscheck.
    #
    # == The released / unedited classes (TcpBoxFetch class note)
    #
    # Both are ingested by default — the TCP's own 4,977-text Evans count
    # (evans_pub_dates.txt) already includes 113 of the 148 unedited texts,
    # and the unedited files carry the same CC0 waiver. Each document
    # carries its class as metadata "tcp_class"; `classes:` in the registry
    # narrows the scope, never a code change.
    #
    # == Delivery grains (the fixture README enumerates them)
    #
    # Upstream serves every text three ways — P4 XML (taken), P3 SGML and
    # Oxford P5 XML (the same texts re-encoded; never fetched) — plus
    # catalogue sidecars. A file under texts/ that is not a *.p4.xml (a P5
    # or SGML copy dropped beside its P4 twin) is skipped BY RULE and
    # counted in discovery_skips, never parsed as a second document.
    #
    # == Dating
    #
    # The BIBLFULL imprint <DATE> through EeboTcp's censused molds, then
    # the later-print molds below for what those leave raw-only: the
    # American and Georgian imprint styles ("in the year 1790.", "1792.
    # Price 8d.", "May 6, 1798.", "1777 - 1801."). Uncertainty marks (?,
    # ca.) stay raw-only exactly as in EEBO; bounds are never invented.
    #
    # == Language
    #
    # Per document from LANGUSAGE through EeboTcp's codemap aliases (eng →
    # en); any other MARC code rides verbatim (ECCO: one fre, one wel of
    # 3,101 files), save a censused slip a subclass names in
    # LANGUAGE_ERRATA.
    class TcpCollection < Nabu::Adapter
      LANGUAGE = "en"
      CLASSES = TcpBoxFetch::CLASSES
      TEXT_SUFFIX = /\.p4\.xml\z/i

      # The rejected grains a texts/ unit dir can carry, by extension.
      REJECTED_GRAINS = { /\.p5\.xml\z/i => "Oxford P5 XML", /\.sgm\z/i => "P3 SGML" }.freeze

      # Typed header IDNOs mined onto metadata: TYPE => key. Lists keep
      # every value in order; singles take the first.
      IDNO_LISTS = {}.freeze
      IDNO_SINGLES = {}.freeze

      # Censused LANGUSAGE slips: TCP id => the claim the text itself makes
      # (a subclass names its own, each with its census).
      LANGUAGE_ERRATA = {}.freeze

      def self.fetch_class = self::Fetch

      def self.urn_prefix = "urn:nabu:#{manifest.id}:"

      # Parallel replay (audited): #parse streams one file through a fresh
      # TcpXmlParser — no state crosses refs.
      def self.parallel_parse? = true

      # The eebo-tcp posture: a Box folder has no git repo — a
      # liveness-only HEAD of the shared folder.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "TCP Box folder", zip_url: fetch_class.shared_url,
          metadata_url: nil, state_subdir: "", state_file: fetch_class.state_file,
          liveness_only: true
        )]
      end

      def initialize(classes: CLASSES, delay: Nabu::EeboTcpFetch::DELAY)
        super()
        unless classes.is_a?(Array) && !classes.empty? && (classes - CLASSES).empty?
          raise ValidationError, "#{manifest.id} classes must be a non-empty subset of " \
                                 "#{CLASSES.join('/')}, got #{classes.inspect}"
        end

        @classes = CLASSES & classes
        @delay = delay
      end

      attr_reader :classes

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        unit_files(workdir).grep(TEXT_SUFFIX)
                           .map { |path| ref_for(path) }
                           .sort_by(&:id).each(&block)
      end

      # The rejected-grain census: a P5/SGML twin under texts/ skips by
      # rule (named); any other stray file is unrecognized.
      def discovery_skips(workdir)
        others = unit_files(workdir).grep_v(TEXT_SUFFIX)
        rejected, strays = others.partition { |path| rejected_grain(path) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: rejected.size, unrecognized: strays.size,
          notes: rejected.map { |path| "#{rejected_grain(path)} copy, not the P4 text: #{relative(workdir, path)}" } +
                 strays.map { |path| "unrecognized file under texts/: #{relative(workdir, path)}" }
        )
      end

      def parse(document_ref)
        klass = document_ref.metadata["tcp_class"]
        idnos = header_idnos(document_ref.path)
        TcpXmlParser.new.parse(
          document_ref.path,
          urn: document_ref.id, language: LANGUAGE,
          language_mapper: lambda { |header|
            self.class::LANGUAGE_ERRATA[document_ref.id.delete_prefix(self.class.urn_prefix)] || langusage_claim(header)
          },
          license_mapper: ->(availability) { availability&.include?(EeboTcp::CC0_MARKER) ? "open" : "restricted" },
          notes: true, # the prints' own marginalia ride "notes" (the eebo-tcp call)
          metadata_mapper: lambda { |header|
            dated = { "tcp_class" => klass, "date" => self.class.imprint_envelope(header["source_date"]) }
            dated.compact.merge(EeboTcp.imprint_place(header["source_pub_place"])).merge(idnos)
          }
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = self.class.fetch_class.sync!(
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          classes: @classes, delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::EeboTcpFetch::Error => e
        raise Nabu::FetchError, "#{manifest.id} fetch failed into #{workdir}: #{e.message}"
      end

      # -- dating (class note) -------------------------------------------------

      # EeboTcp's envelope, widened by the later-print molds where EEBO's
      # left only the raw string.
      def self.imprint_envelope(raw)
        envelope = EeboTcp.imprint_envelope(raw)
        return envelope if envelope.nil? || envelope.key?("not_before")

        bounds = later_print_bounds(envelope["raw"])
        return envelope unless bounds

        { "not_before" => bounds[0], "not_after" => bounds[1], "raw" => envelope["raw"] }
      end

      # "1777 - 1801." / "[1785 - 1807]" — the spaced range.
      SPACED_RANGE = /\A\[?(\d{4})\s+-\s+(\d{4})\]?\.?\z/
      # A plausible print year standing alone in the statement.
      FOUR_DIGITS = /(?<!\d)\d{4}(?!\d)/
      PRINT_YEAR = /\A1[4-8]\d\d\z/

      # Read only when no uncertainty mark is present: the spaced range,
      # else a statement carrying exactly ONE four-digit number that is a
      # plausible print year ("in the year 1790.", "1792. Price 8d.",
      # "May 6, 1798.", "--1794--"); two numbers (a corrected or ranged
      # pair the EEBO molds declined) stay raw-only.
      def self.later_print_bounds(text)
        return nil if EeboTcp::UNCERTAIN.match?(text)

        if (match = SPACED_RANGE.match(text))
          first = Integer(match[1], 10)
          last = Integer(match[2], 10)
          return last >= first ? [first, last] : nil
        end
        years = text.scan(FOUR_DIGITS)
        return nil unless years.size == 1 && PRINT_YEAR.match?(years.first)

        year = Integer(years.first, 10)
        [year, year]
      end

      private

      def unit_files(workdir)
        @classes.flat_map do |klass|
          Dir.glob(File.join(workdir, TcpBoxFetch::TEXTS_DIR, klass, "*", "*"))
             .reject { |path| File.basename(path).start_with?(".") || !File.file?(path) }
        end
      end

      def ref_for(path)
        Nabu::DocumentRef.new(
          source_id: manifest.id,
          id: "#{self.class.urn_prefix}#{File.basename(path).sub(TEXT_SUFFIX, '')}",
          path: File.expand_path(path),
          metadata: { "filename" => File.basename(path), "tcp_class" => path.split(File::SEPARATOR)[-3] }
        )
      end

      def rejected_grain(path)
        REJECTED_GRAINS.find { |pattern, _label| pattern.match?(path) }&.last
      end

      def relative(workdir, path)
        path.delete_prefix("#{File.expand_path(workdir)}/").delete_prefix("#{workdir}/")
      end

      # The typed header IDNOs (IDNO_LISTS / IDNO_SINGLES) the tcp-xml
      # family does not capture — a scan of the <HEADER> (read through the
      # SourceRead belt; a bad byte quarantines the document)
      # (declared: the family's own capture stays untouched, so the held
      # eebo-tcp stamp does not move; folding this into the family is the
      # follow-on whenever that stamp is dirty anyway).
      def header_idnos(path)
        lists = self.class::IDNO_LISTS
        singles = self.class::IDNO_SINGLES
        return {} if lists.empty? && singles.empty?

        head = SourceRead.utf8_file(path, label: manifest.id).split("</HEADER>", 2).first
        found = Hash.new { |hash, key| hash[key] = [] }
        head.scan(%r{<IDNO TYPE="([^"]+)">([^<]*)</IDNO>}) do |type, value|
          text = Nabu::Normalize.nfc(value.gsub(/[[:space:]]+/, " ").strip)
          found[type] << text unless text.empty?
        end
        lists.filter_map { |type, key| [key, found[type]] unless found[type].empty? }.to_h
             .merge(singles.filter_map { |type, key| [key, found[type].first] unless found[type].empty? }.to_h)
      end

      def langusage_claim(header)
        usage = header["language_usage"] or return nil
        code = usage.split(";").first.to_s.split("=").first.to_s.strip
        return nil if code.empty? || !code.match?(/\A[a-z]{2,3}\z/)

        EeboTcp::LANGUAGE_ALIASES.fetch(code, code)
      end

      def fetch_notes(result)
        base = "Box folder walked (#{result.zips_listed} zips listed, #{result.zips_fetched} " \
               "fetched, #{result.zips_cached} unchanged; #{result.texts} texts on disk; " \
               "classes: #{result.phases.join('+')})"
        [base, attic_notes(result.atticked)].compact.join("; ")
      end
    end
  end
end
