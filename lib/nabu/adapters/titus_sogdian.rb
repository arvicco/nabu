# frozen_string_literal: true

require "digest"
require_relative "titus_pahlavi_parser"
require_relative "titus_sogdian_parser"

module Nabu
  module Adapters
    # TITUS Sogdian — the two Sogdian corpora TITUS hosts as retrievable
    # text (J. W. Goethe-Universität Frankfurt, Prof. Jost Gippert):
    #
    #   sogdnswc  "Sogdian Corpus (NSW), arranged by texts" — N. Sims-
    #             Williams's corpus (data entry and the 2005 text revision
    #             N. Sims-Williams; TITUS version J. Gippert): 29 texts on
    #             392 pages (TITUS's own per-text index, censused
    #             2026-10-10) — the Christian texts (Syriac script), the
    #             Manichaean-script corpus (BBB, the Berlin/London/Paris
    #             fragments), the Buddhist texts, the Mug documents, the
    #             Ancient Letters, the Upper Indus inscriptions.
    #   sogdmor   "Sogdian Texts, ed. by Morano" — the Stellung-Jesu hymns
    #             (Waldschmidt-Lentz i, pp. 93–94; prepared for TITUS by
    #             E. Morano): ONE page reachable from the frameset.
    #
    # Deliberately OUT: the Sogdian letters page TITUS's text index links
    # on depts.washington.edu (not TITUS-hosted, not covered by the grant),
    # and sogdmor/sogdm002.htm — a 2001 manuscript-ordered layout of the
    # same hymn the frameset no longer reaches (no "Next part" leads to it;
    # the walk IS the map).
    #
    # == The grant (by email, 2026-10-06) and the credit duty
    #
    # Fetched under the owner's PERSONAL grant (Gippert): the Middle Iranian
    # families on TITUS "to whatever extent TITUS hosts them as retrievable
    # text" — ONE retrieval per corpus, local personal research use only, no
    # redistribution, TITUS and the editors credited wherever displayed. The
    # titus-avestan mechanisms verbatim: `grant_required: true` guards the
    # fetch right; license_class `nc` + the manifest +credit+ line carry the
    # display duty (each document's "editors" metadata names its corpus's).
    #
    # == Shape (see Nabu::Adapters::TitusSogdianParser)
    #
    # canonical/titus-sogdian/<edition>/<prefix>NNN.htm — one subdir per
    # TITUS corpus. One PAGE is one document; the passage is the manuscript
    # LINE. A text's opening page (its `<!Level 1>` "Text:" header with the
    # title / edition block) often carries no text row at all: such
    # HEADER-ONLY pages skip by rule (censused in discovery_skips), and
    # their header block rides every following page of that text as
    # `text_*` metadata (discover walks the pages in order; the text
    # context is the latest Level-1 page).
    #
    # == Mined metadata (the №R-70 aggressive-mining law)
    #
    # Per passage: every header value in force (text / chapter / paragraph,
    # manuscript, new_manuscript, page_of_manuscript, line_of_manuscript,
    # editor_edition, item_of_edition, page_of_edition), the TITUS anchor,
    # the script, and a FINDSPOT — DELIBERATELY coarse and declared: only
    # the Berlin find-signature site sigla censused on the live pages (D
    # Qočo, B Bulayïq; the titus-tocharian-a table) and the Upper Indus
    # chapter toponyms TITUS's own index lists resolve; any other siglum or
    # chapter mints no place (the raw values still ride). The pages carry
    # no dating (only TITUS data-entry dates) — undatable is honest.
    class TitusSogdian < Nabu::Adapter
      SLUG = "titus-sogdian"
      LANGUAGE = "sog"
      PARSER_FAMILY = "titus_sogdian"

      BASE_URL = "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/sogd/"

      # One TITUS corpus: +path+ the frameset under BASE_URL, +prefix+ its
      # page-file stem, +name+ TITUS's own corpus title, +editors+ the
      # data-entry/edition statement (the pages' own textdescr block),
      # +credit_name+ the short form the source credit line carries.
      Edition = Data.define(:path, :prefix, :name, :editors, :credit_name) do
        def entry_url = "#{BASE_URL}#{path}"
        def page_re = /\A#{Regexp.escape(prefix)}\d+\.htm\z/
      end

      EDITIONS = {
        "sogdnswc" => Edition.new(path: "sogdnswc/sogdn.htm", prefix: "sogdn",
                                  name: "Sogdian Corpus (NSW), arranged by texts",
                                  editors: "N. Sims-Williams (data entry and text revision); " \
                                           "TITUS version J. Gippert (Frankfurt)",
                                  credit_name: "Sims-Williams"),
        "sogdmor" => Edition.new(path: "sogdmor/sogdm.htm", prefix: "sogdm",
                                 name: "Sogdian Texts, ed. by Morano",
                                 editors: "E. Morano; TITUS version J. Gippert (Frankfurt)",
                                 credit_name: "Morano")
      }.freeze

      LICENSE = "personal grant, Gippert (by email, 2026-10-06): one retrieval, local personal " \
                "research use only, no redistribution; TITUS and the editors clearly indicated " \
                "wherever displayed"

      CREDIT = "TITUS (J. Gippert, Frankfurt) — Sogdian corpora: the Sogdian Corpus arranged by " \
               "texts (data entry and text revision N. Sims-Williams) and the Stellung-Jesu " \
               "hymns ed. E. Morano (each document names its corpus's editors)."

      # Berlin Turfan find-signature SITE sigla (T_<expedition>_<siglum>_…)
      # → findspot; census-complete for the sampled pages (T_II_D_II_169,
      # T_II_B_30). Unknown sigla mint nothing.
      SITE_SIGLA = { "D" => "Qočo", "B" => "Bulayïq" }.freeze

      # The "Upp.Ind." text's chapters that ARE toponyms (TITUS's own
      # per-text index, 2026-10-10); DP / 80TBI / China mint nothing.
      UPPER_INDUS_TEXT = "Upp.Ind."
      CHAPTER_PLACES = { "UI" => "Upper Indus", "Shatial" => "Shatial", "Ladakh" => "Ladakh",
                         "Bugut" => "Bugut", "Sevrey" => "Sevrey", "Qarashahr" => "Qarashahr",
                         "Qumtura" => "Qumtura", "Ili" => "Ili" }.freeze

      # A page naming any lane-shaped span (the parser classifies or
      # quarantines it) is a content page; the rest are header-only.
      LANE_NEEDLE = /<span id=(?!(?:h|n|nc|voc)\d+>)[a-z]+\d+>/i

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "TITUS Sogdian Corpora",
          license: LICENSE,
          license_class: "nc",
          upstream_url: EDITIONS.fetch("sogdnswc").entry_url,
          parser_family: PARSER_FAMILY,
          credit: CREDIT
        )
      end

      # Each corpus's frameset entry stands for it — HEAD it for liveness;
      # its TitusFetch state file (url + sha) feeds the drift lane.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        EDITIONS.map do |id, edition|
          Nabu::Adapter::HttpProbeTarget.new(
            label: "#{id} entry", zip_url: edition.entry_url, metadata_url: nil,
            state_subdir: id, state_file: Nabu::TitusFetch::STATE_FILE
          )
        end
      end

      # The findspot a passage's context names, or nil (see SITE_SIGLA /
      # CHAPTER_PLACES — declared coarse).
      def self.findspot_for(context, text:)
        if text == UPPER_INDUS_TEXT && (place = CHAPTER_PLACES[context["chapter"]])
          return place
        end

        signature = context["manuscript"].to_s
        return nil unless signature.start_with?("T_")

        SITE_SIGLA[signature.split("_")[2]]
      end

      def initialize(editions: EDITIONS, delay: Nabu::TitusFetch::DELAY)
        super()
        @editions = editions
        @delay = delay
      end

      # One DocumentRef per content page (ref.id IS the document urn), each
      # carrying its text context (the latest Level-1 page before it).
      def discover(workdir)
        walk_pages(workdir).reject { |page| page[:header_only] }.map do |page|
          metadata = { "edition" => page[:edition], "page" => page[:stem] }
          metadata["text"] = page[:text] if page[:text]
          metadata["text_page"] = page[:text_page] if page[:text_page]
          Nabu::DocumentRef.new(source_id: SLUG, id: document_urn(page[:edition], page[:stem]),
                                path: page[:path], metadata: metadata)
        end
      end

      def discovery_skips(workdir)
        skipped = walk_pages(workdir).count { |page| page[:header_only] }
        notes = if skipped.positive?
                  ["#{skipped} header-only page(s) skipped — a text's title/edition block, no text row " \
                   "(carried into its pages' text_* metadata)"]
                else
                  []
                end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: 0, notes: notes)
      end

      # Parse one page into a Document of manuscript-line Passages. A
      # content page with no text row is a structural failure (ParseError).
      def parse(document_ref)
        html = TitusPahlaviParser.read_page(document_ref.path)
        page = TitusSogdianParser.parse(html)
        raise Nabu::ParseError, "#{SLUG}: no text lines in #{document_ref.path}" if page.sections.empty?

        edition = EDITIONS.fetch(document_ref.metadata.fetch("edition"))
        metadata = document_metadata(document_ref, edition, page)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(document_ref, edition), metadata: metadata
        )
        seen = Hash.new(0)
        page.sections.each_with_index do |section, sequence|
          occurrence = (seen[section.key] += 1)
          document << Nabu::Passage.new(
            urn: passage_urn(document_ref.id, section.key, occurrence), language: section.language,
            text: section.text, sequence: sequence,
            annotations: section_annotations(section, occurrence, text: document_ref.metadata["text"])
          )
        end
        document
      end

      # One polite TitusFetch walk per corpus (owner-run; never in tests —
      # WebMock blocks the network), each into its own subdir with its own
      # page pattern, state file and attic subtree. Pages already on disk
      # are never re-fetched (the grant's ONE retrieval). The source pin is
      # the sha256 over the per-corpus page-set pins.
      def fetch(workdir, progress: nil, force: false)
        shas = []
        atticked = []
        @editions.each do |id, edition|
          result = Nabu::TitusFetch.sync!(
            entry_url: edition.entry_url, dir: File.join(workdir, id),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, id), page_re: edition.page_re,
            delay: @delay, progress: progress,
            guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
          )
          shas << "#{id}:#{result.sha}"
          atticked.concat(result.atticked)
        end
        FetchReport.new(sha: Digest::SHA256.hexdigest(shas.join("\n")), fetched_at: Time.now,
                        notes: attic_notes(atticked))
      rescue Nabu::TitusFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      # Every numbered page of every corpus in page order, with its text
      # context and the header-only flag (a cheap byte needle).
      def walk_pages(workdir)
        @editions.flat_map do |id, edition|
          text = nil
          text_page = nil
          numbered_pages(workdir, id, edition).map do |stem, path|
            bytes = File.binread(path).force_encoding(Encoding::UTF_8).scrub
            if (level_one = TitusSogdianParser.level_one(bytes))
              text = level_one
              text_page = stem
            end
            { edition: id, stem: stem, path: path, text: text, text_page: text_page,
              header_only: !LANE_NEEDLE.match?(bytes) }
          end
        end
      end

      def numbered_pages(workdir, id, edition)
        pages = Dir.glob(File.join(workdir, id, "#{edition.prefix}*.htm")).filter_map do |path|
          name = File.basename(path)
          [name.delete_suffix(".htm"), path] if name.match?(edition.page_re)
        end
        pages.sort_by { |stem, _path| stem[/\d+\z/].to_i }
      end

      def document_urn(edition_id, stem)
        "urn:nabu:#{SLUG}:#{edition_id}.#{stem}"
      end

      # A key the page repeats (a line split by a mid-line header, a
      # re-numbered fragment) keys as `<key>#<occurrence>` in document
      # order with an honest "occurrence" annotation — never merged.
      def passage_urn(document_urn, key, occurrence)
        tail = occurrence > 1 ? "#{key}##{occurrence}" : key
        "#{document_urn}:#{tail}"
      end

      def section_annotations(section, occurrence, text:)
        annotations = section.context.dup
        annotations["titus_anchor"] = section.anchor unless section.anchor.empty?
        annotations["script"] = section.scripts.join("+") unless section.scripts.empty?
        section.embedded.each { |language, run| annotations["embedded_#{language}"] = run }
        findspot = self.class.findspot_for(section.context, text: text)
        annotations["findspot"] = findspot if findspot
        annotations["occurrence"] = occurrence if occurrence > 1
        annotations
      end

      # Corpus identity + the text context + the page's own header block;
      # the text page's block rides as text_* when it is another page.
      def document_metadata(document_ref, edition, page)
        metadata = { "edition" => document_ref.metadata.fetch("edition"), "edition_name" => edition.name,
                     "editors" => edition.editors }
        text = document_ref.metadata["text"]
        metadata["text"] = text if text
        text_page = document_ref.metadata["text_page"]
        if text_page && text_page != document_ref.metadata["page"]
          text_header(document_ref.path, text_page).each { |key, value| metadata["text_#{key}"] = value }
        end
        metadata.merge!(page.header)
        scripts = page.sections.flat_map(&:scripts).uniq.sort
        metadata["scripts"] = scripts unless scripts.empty?
        metadata
      end

      # The header block of the text's opening page (a sibling file in the
      # same corpus directory); absent (a partial tree) → nothing.
      def text_header(path, text_page)
        sibling = File.join(File.dirname(path), "#{text_page}.htm")
        return {} unless File.file?(sibling)

        TitusSogdianParser.header_block(Nokogiri::HTML(TitusPahlaviParser.read_page(sibling)))
      end

      def title_for(document_ref, edition)
        text = document_ref.metadata["text"]
        label = text ? "#{edition.name}: #{text}" : edition.name
        "Sogdian — #{label} (#{document_ref.metadata['page']})"
      end
    end
  end
end
