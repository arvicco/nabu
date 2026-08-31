# frozen_string_literal: true

require_relative "titus_osco_umbrian_parser"

module Nabu
  module Adapters
    # TITUS Osco-Umbrian Corpus (P90-2) — the Sabellic inscriptions as served
    # by TITUS (J. W. Goethe-Universität Frankfurt, Prof. Jost Gippert): the
    # Tabulae Iguvinae complete (the only complete digital edition of the
    # Iguvine Tables) plus the Oscan and minor-dialect inscriptions, text
    # entry J. Gippert (Frankfurt 1991) and V. Slunečko (Praha 1995), with
    # Gippert's synoptical arrangement of the original scripts.
    #
    # == The grant (by email, 2026-08-31) and the credit duty
    #
    # Fetched under the owner's PERSONAL grant extending the Avestan terms
    # verbatim: one-time download, local use only, no redistribution, TITUS
    # and the editors credited wherever displayed. Same two mechanisms as
    # titus-avestan: `grant_required: true` guards the fetch right;
    # license_class `nc` + the manifest +credit+ line carry the display duty.
    #
    # == Shape (see Nabu::Adapters::TitusOscoUmbrianParser)
    #
    # One PAGE is one document; inscription LINES are the passages, each the
    # edition's unified Latin transliteration with the original-script lane
    # (native Italic / Latin capitals / Greek) riding as the "original"
    # annotation. The language claim is the edition's own lane split —
    # Umbrian-type lanes mint `xum`, Oscan-type `osc` (deliberately coarse:
    # minor Sabellic dialects ride their nearest lane; the posture records
    # this).
    class TitusOscoUmbrian < Nabu::Adapter
      SLUG = "titus-osco-umbrian"
      PARSER_FAMILY = "titus_osco_umbrian"

      ENTRY_URL = "https://titus.uni-frankfurt.de/texte/etcs/ital/oskumb/oskum.htm"

      LICENSE = "personal grant, Gippert (by email, 2026-08-31, extending the 2026-07-23 " \
                "Avestan terms): non-commercial local use; TITUS and the editors " \
                "clearly indicated wherever displayed"

      CREDIT = "TITUS (J. Gippert, Frankfurt) — Osco-Umbrian corpus, text entry " \
               "J. Gippert / V. Slunečko, synoptical script arrangement J. Gippert."

      # Numbered text pages (oskum001.htm …); the frameset oskum.htm is not one.
      PAGE_GLOB = "oskum*.htm"
      PAGE_RE = /\Aoskum\d+\.htm\z/

      # Monument groups the edition titles itself (h2 "Type:"); only the one
      # name certain from the edition's own subtitle is expanded — raw tokens
      # otherwise (never invent upstream vocabulary).
      TYPE_NAMES = { "IT" => "Tabulae Iguvinae" }.freeze

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "TITUS Osco-Umbrian Corpus",
          license: LICENSE,
          license_class: "nc",
          upstream_url: ENTRY_URL,
          parser_family: PARSER_FAMILY,
          credit: CREDIT
        )
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "oskum.htm entry", zip_url: ENTRY_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::TitusFetch::STATE_FILE
        )]
      end

      # One DocumentRef per fetched text page (ref.id IS the document urn).
      def discover(workdir)
        Dir.glob(File.join(workdir, PAGE_GLOB)).filter_map do |path|
          name = File.basename(path)
          next unless name.match?(PAGE_RE)

          stem = name.delete_suffix(".htm")
          Nabu::DocumentRef.new(source_id: SLUG, id: document_urn(stem), path: path,
                                metadata: { "page" => stem })
        end
      end

      # Parse one page into a Document of inscription-line Passages. A page
      # with content but no keyable lines, or whose lanes vote two languages
      # across sections, quarantines whole (ParseError) — never served with
      # a hole or a false language claim.
      def parse(document_ref)
        html = File.read(document_ref.path, encoding: "UTF-8")
        sections = TitusOscoUmbrianParser.parse(html)
        raise Nabu::ParseError, "titus-osco-umbrian: no text sections in #{document_ref.path}" if sections.empty?

        language = page_language(sections, document_ref.path)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, canonical_path: document_ref.path,
          title: title_for(document_ref.metadata["page"], sections)
        )
        seen = Hash.new(0)
        sections.each_with_index do |section, sequence|
          citation = citation_for(section)
          occurrence = (seen[citation] += 1)
          document << Nabu::Passage.new(
            urn: passage_urn(document_ref.id, citation, occurrence),
            language: section.language, text: section.text, sequence: sequence,
            annotations: section_annotations(section, occurrence)
          )
        end
        document
      end

      # Polite sequential page walk from the frameset (owner-run; never in
      # tests). Same TitusFetch machinery as the Avestan corpus, steered by
      # this corpus's page pattern.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::TitusFetch.sync!(
          entry_url: ENTRY_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          page_re: PAGE_RE, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue Nabu::TitusFetch::Error => e
        raise Nabu::FetchError, "titus-osco-umbrian fetch failed into #{workdir}: #{e.message}"
      end

      private

      # The page's one language claim: the unanimous section vote. The
      # edition keeps monuments (and so pages) single-lane; a mixed page is
      # a structural surprise worth a loud quarantine, not a guess.
      def page_language(sections, path)
        votes = sections.map(&:language).uniq
        return votes.first if votes.size == 1

        raise Nabu::ParseError,
              "titus-osco-umbrian: #{path} mixes language lanes #{votes.inspect} — one page, one claim"
      end

      def document_urn(stem)
        "urn:nabu:#{SLUG}:#{stem}"
      end

      # The dotted citation: the anchor's non-empty components (the doubled
      # underscore's empty level drops here) — "IT.Ia.1", "BaI.POMP-2.1".
      def citation_for(section)
        section.components.reject(&:empty?).join(".")
      end

      def passage_urn(document_urn, citation, occurrence)
        tail = occurrence > 1 ? "#{citation}##{occurrence}" : citation
        "#{document_urn}:#{tail}"
      end

      def section_annotations(section, occurrence)
        comps = section.components.reject(&:empty?)
        annotations = { "monument" => comps[0] }
        annotations["inscription"] = comps[1] if comps[1]
        annotations["line"] = comps.last if comps.size > 2 && comps.last.match?(/\A\d+\z/)
        annotations["alphabet"] = section.alphabet if section.alphabet
        annotations["original"] = section.original if section.original
        annotations["repetition"] = occurrence if occurrence > 1
        annotations
      end

      def title_for(stem, sections)
        comps = sections.first.components.reject(&:empty?)
        monument = TYPE_NAMES.fetch(comps[0], comps[0])
        label = [monument, comps[1]].compact.join(" ")
        "Osco-Umbrian Corpus — #{label} (#{stem})"
      end
    end
  end
end
