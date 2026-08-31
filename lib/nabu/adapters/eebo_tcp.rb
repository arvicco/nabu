# frozen_string_literal: true

require_relative "tcp_xml_parser"
require_relative "../eebo_tcp_fetch"

module Nabu
  module Adapters
    # EEBO-TCP (P83-1) — Early English Books Online, Text Creation
    # Partnership: 60,326 hand-keyed early-modern English texts (Phase I
    # 25,368 / Phase II 34,958; census 2026-08-26) in the P4 <ETS> schema
    # the tcp-xml family (TcpXmlParser, P82-2) was built for. The adapter
    # composes the family and owns none of it — CME proved the machinery,
    # EEBO is the wave it was proven FOR (100% parse success on the 3,325-
    # file scout sample, 0 errors).
    #
    # == Identity (the CME placeholder-IDG lesson, resolved the other way)
    #
    # The filename stem IS the TCP id — and unlike CME's shared placeholder
    # IDG, EEBO's <IDG ID> equals the filename stem on every one of the
    # 3,325 sampled files (0 mismatches, 0 missing; verified 2026-08-26),
    # corroborated by the per-phase ID lists the fetch lands beside texts/.
    # The filename stays the identity (the discover-without-parse rule);
    # IDG rides metadata verbatim as the crosscheck.
    #
    #   document urn  urn:nabu:eebo-tcp:<TCPID>          (…:eebo-tcp:A90004)
    #   passage urn   <document-urn>:<div-path>.<unit>   (…:eebo-tcp:A90004:d1.h1)
    #
    # == Wave scoping (№R-43, ruled 2026-08-26)
    #
    # `classes:` (the kanripo mold) scopes BOTH acquisition and discovery
    # to a phase subset — Phase I is the RULED wave-1 configuration
    # (option b; both phases the stated follow-on), widened by a
    # sources.yml edit, never a code change.
    #
    # == Language
    #
    # Per-document from the header's own LANGUSAGE (exactly one entry per
    # file, censused ×3,325): eng → `en` (the nabu-lects codemap alias) for
    # 97.6% of the corpus; the foreign-language minority (lat 1.4%, wel/
    # roa/frm/fre/dut/spa/iri/ita tails) claims its upstream MARC code
    # verbatim — an English-corpus claim over a Latin book would be false.
    # No LANGUSAGE → `en` (the corpus's own definition).
    #
    # == Dating (the P81 MetadataDates molds, parse-side)
    #
    # The BIBLFULL imprint <DATE> carries the print year; the censused
    # molds (2026-08-26, 3,325 files → 85.7% dated) parse ONLY the clean
    # shapes — plain/bracketed years, "[i.e. YYYY]" cataloguer corrections,
    # YYYY-YYYY ranges, OS/NS split years ("1681/2"), "Anno Dom. YYYY" —
    # into a {not_before, not_after, raw} envelope; uncertainty marks
    # (?, ca.) stay raw-only, bounds never invented. Projected through
    # TimelineBuilder::MetadataDates :structured.
    #
    # == License
    #
    # Uniform CC0: every sampled file's AVAILABILITY carries the TCP's CC0
    # 1.0 Public Domain Dedication (two statement variants, both explicit
    # dedications; availability present in 100% of files censused). The
    # license_mapper seam maps the dedication → open per document; a
    # STRANGER availability maps `restricted`, never silently open.
    class EeboTcp < Nabu::Adapter
      LANGUAGE = "en"
      URN_PREFIX = "urn:nabu:eebo-tcp:"

      # The nabu-lects codemap's own aliases for the censused LANGUSAGE
      # codes it maps; unmapped MARC codes ride verbatim (class note).
      LANGUAGE_ALIASES = { "eng" => "en", "spa" => "es", "ita" => "it" }.freeze

      # The wave scope vocabulary + the №R-43 RULED wave-1 default
      # (Phase I whole; both phases the stated follow-on).
      PHASES = Nabu::EeboTcpFetch::PHASES.keys.freeze
      DEFAULT_PHASES = %w[phase1].freeze

      # The CC0 dedication's stable core, shared by both statement
      # variants (censused ×3,325).
      CC0_MARKER = "CC0 1.0 Public Domain Dedication"

      MANIFEST = Nabu::SourceManifest.new(
        id: "eebo-tcp",
        name: "EEBO-TCP — Early English Books Online, Text Creation Partnership (Phases I–II)",
        license: "OPEN — uniform CC0 1.0 Public Domain Dedication, per-file AVAILABILITY verbatim " \
                 "(censused ×3,325 sampled files, 2026-08-26, both statement variants): \"the Text " \
                 "Creation Partnership has waived all copyright and related or neighboring rights " \
                 "to this keyboarded and encoded edition of the work described above, according to " \
                 "the terms of the CC0 1.0 Public Domain Dedication\". The waiver covers the " \
                 "transcriptions only, not the ProQuest page images (not fetched). The 2026-08-20 grant " \
                 "(P.F. Schaffner, TCP text manager, 2026-08-20) additionally covers the TCP files " \
                 "(\"free to use both the CME and the TCP files in any way you choose, and obtain " \
                 "them by any means convenient\").",
        license_class: "open",
        upstream_url: Nabu::EeboTcpFetch.shared_url,
        parser_family: "tcp-xml",
        credit: "Text Creation Partnership — EEBO-TCP: Early English Books Online (Phases I–II), " \
                "textcreationpartnership.org"
      )

      def self.manifest
        MANIFEST
      end

      # P11-2/P79-2: the Box shared folder has no git repo and the ledger
      # pins an aggregate sha the probe cannot diff URL-by-URL — a
      # liveness-only HEAD of the shared folder is the honest posture
      # (the cme/kitab mold).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "TCP Box folder",
          zip_url: Nabu::EeboTcpFetch.shared_url,
          metadata_url: nil, state_subdir: "",
          state_file: Nabu::EeboTcpFetch::STATE_FILE,
          liveness_only: true
        )]
      end

      # +classes+ is the phase scope (registry `classes:`, the kanripo
      # mold); +delay+ exists for the WebMock'd tests (0) — real syncs
      # keep the polite default.
      def initialize(classes: DEFAULT_PHASES, delay: Nabu::EeboTcpFetch::DELAY)
        super()
        unless classes.is_a?(Array) && !classes.empty? && (classes - PHASES).empty?
          raise ValidationError,
                "eebo-tcp classes must be a non-empty subset of #{PHASES.join('/')}, got #{classes.inspect}"
        end

        @phases = PHASES & classes # canonical order
        @delay = delay
      end

      attr_reader :phases

      # One DocumentRef per texts/<phase>/<stem>/<TCPID>.P4.xml within the
      # phase scope, urn = the TCP id (the filename stem), sorted by urn.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Delegate to the tcp-xml family: per-document language from
      # LANGUSAGE, the CC0 license mapping, and the imprint-date envelope +
      # phase riding metadata (class notes).
      def parse(document_ref)
        phase = document_ref.metadata["phase"]
        TcpXmlParser.new.parse(
          document_ref.path,
          urn: document_ref.id, language: LANGUAGE,
          language_mapper: ->(header) { langusage_claim(header) },
          license_mapper: ->(availability) { license_class(availability) },
          metadata_mapper: lambda { |header|
            { "phase" => phase, "date" => self.class.imprint_envelope(header["source_date"]) }.compact
          }
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The Box-folder acquisition (never in tests — WebMock blocks the
      # network): ~5 listing GETs + zip downloads (skip-if-unchanged), the
      # ID lists + DTD beside texts/, non-destructive (attic + breaker).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::EeboTcpFetch.sync!(
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          phases: @phases, delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::EeboTcpFetch::Error => e
        raise Nabu::FetchError, "eebo-tcp fetch failed into #{workdir}: #{e.message}"
      end

      # -- the imprint-date molds (fixture-backed; class note) ----------------

      # {not_before, not_after, raw} for a clean imprint year shape, {raw}
      # alone otherwise, nil when BIBLFULL carried no date at all.
      def self.imprint_envelope(raw)
        return nil if raw.nil?

        text = raw.gsub(/[[:space:]]+/, " ").strip
        return nil if text.empty?

        bounds = imprint_bounds(text)
        return { "raw" => text } unless bounds

        { "not_before" => bounds[0], "not_after" => bounds[1], "raw" => text }
      end

      # The cataloguer's correction is upstream's own claim and outranks
      # the misprinted year it corrects.
      CORRECTED = /\[\s*i\.?e\.?,?\s*(\d{4})/
      # Uncertainty marks: bounds never invented over "?" or "ca./c.".
      UNCERTAIN = /\?|\bca?\.|\bcirca\b/i
      PLAIN_YEAR = /\A(\d{4})\z/
      RANGE = %r{\A(\d{4})[-/](\d{1,4})\z}
      # "Anno Dom. 1617." — only when the string carries exactly one year.
      ANNO = /\bAnno(?:\s+Dom(?:ini)?\.?)?,?\s+(\d{4})\b/
      BRACKET_YEAR = /\[(\d{4})\]/

      def self.imprint_bounds(text)
        if (match = CORRECTED.match(text))
          year = Integer(match[1], 10)
          return [year, year]
        end
        return nil if UNCERTAIN.match?(text)

        core = text.delete("[]").sub(/\.\z/, "").strip
        if (match = PLAIN_YEAR.match(core))
          year = Integer(match[1], 10)
          return [year, year]
        end
        if (match = RANGE.match(core))
          first = Integer(match[1], 10)
          second = tail_year(first, match[2])
          return [first, second] if second && second >= first
        end
        if (match = ANNO.match(text)) && text.scan(/\d{4}/).size == 1
          year = Integer(match[1], 10)
          return [year, year]
        end
        if (match = BRACKET_YEAR.match(text))
          year = Integer(match[1], 10)
          return [year, year]
        end
        nil
      end

      # "1681/2" → 1682, "1699-1700" → 1700: a short tail completes from
      # the leading year's own digits.
      def self.tail_year(first, tail)
        return Integer(tail, 10) if tail.length == 4

        Integer(first.to_s[0, 4 - tail.length] + tail, 10)
      end

      private

      # -- discovery ----------------------------------------------------------

      def document_refs(workdir)
        @phases.flat_map { |phase| phase_refs(workdir, phase) }.sort_by(&:id)
      end

      def phase_refs(workdir, phase)
        Dir.glob(File.join(workdir, Nabu::EeboTcpFetch::TEXTS_DIR, phase, "*", "*.xml")).map do |path|
          name = File.basename(path)
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{tcp_id(name)}",
            path: File.expand_path(path),
            metadata: { "filename" => name, "phase" => phase }
          )
        end
      end

      # A90004.P4.xml → A90004 (upstream's uniform naming; a bare .xml
      # would still identify by its stem).
      def tcp_id(filename)
        File.basename(filename, ".xml").delete_suffix(".P4")
      end

      # -- the per-document judgments (parser seams) --------------------------

      # First LANGUSAGE id (exactly one per file, censused), through the
      # codemap aliases; a header without one falls back to the caller's
      # `en` (class note).
      def langusage_claim(header)
        usage = header["language_usage"] or return nil
        code = usage.split(";").first.to_s.split("=").first.to_s.strip
        return nil if code.empty? || !code.match?(/\A[a-z]{2,3}\z/)

        LANGUAGE_ALIASES.fetch(code, code)
      end

      # The CC0 dedication → open; anything else — absent or a stranger
      # statement — is restricted until a human reads it (never silently
      # open).
      def license_class(availability)
        availability&.include?(CC0_MARKER) ? "open" : "restricted"
      end

      def fetch_notes(result)
        base = "Box folder walked (#{result.zips_listed} zips listed, #{result.zips_fetched} " \
               "fetched, #{result.zips_cached} unchanged; #{result.texts} texts on disk; " \
               "phases: #{result.phases.join('+')})"
        [base, attic_notes(result.atticked)].compact.join("; ")
      end
    end
  end
end
