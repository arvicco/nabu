# frozen_string_literal: true

require "digest"
require "nokogiri"
require_relative "source_read"
require_relative "titus_levels_parser"

module Nabu
  module Adapters
    # The shared body of the multi-edition TITUS adapters read by the
    # titus_levels parser family (titus-old-lithuanian, titus-old-albanian,
    # titus-old-frisian): the titus-pahlavi shape — one TitusFetch walk per
    # edition into canonical/<slug>/<edition>/, one PAGE per document,
    # passages at the family's unit grain (Nabu::Adapters::TitusLevelsParser)
    # — with each concrete adapter supplying its constants:
    #
    #   SLUG, LANGUAGE, NAME (the manifest name), TITLE (the document title
    #   prefix), BASE_URL, EDITIONS ({id => Edition}), LANES (the language's
    #   lane vocabulary), LICENSE, CREDIT.
    #
    # An Edition's +date+ / +place+ carry only what an upstream page states
    # (a title-page imprint, the edition header's own year) — read at the
    # fixture census, never supplied from scholarship; nil is no claim.
    # +work+ is the kind_map key (default: the edition id).
    class TitusLevelsAdapter < Nabu::Adapter
      PARSER_FAMILY = "titus_levels"

      Edition = Data.define(:path, :prefix, :name, :editors, :credit_name, :date, :place, :lanes) do
        def initialize(path:, prefix:, name:, editors:, credit_name:, date: nil, place: nil, lanes: nil)
          super
        end

        def page_re = /\A#{Regexp.escape(prefix)}\d+\.htm\z/
      end

      # Header spans mined into document metadata (an edition's first page
      # carries them; continuation pages honestly carry none).
      HEADER_SPANS = { "title" => "page_title", "textdescr" => "data_entry", "bibliogr" => "bibliography" }.freeze

      def self.manifest
        Nabu::SourceManifest.new(
          id: self::SLUG, name: self::NAME, license: self::LICENSE, license_class: "nc",
          upstream_url: entry_url(self::EDITIONS.values.first), parser_family: PARSER_FAMILY,
          credit: self::CREDIT
        )
      end

      def self.entry_url(edition) = "#{self::BASE_URL}#{edition.path}"

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        self::EDITIONS.map do |id, edition|
          Nabu::Adapter::HttpProbeTarget.new(
            label: "#{id} entry", zip_url: entry_url(edition), metadata_url: nil,
            state_subdir: id, state_file: Nabu::TitusFetch::STATE_FILE
          )
        end
      end

      # +editions+ narrows the walk (tests); +delay+ is TitusFetch's pause.
      def initialize(editions: self.class::EDITIONS, delay: Nabu::TitusFetch::DELAY)
        super()
        @editions = editions
        @delay = delay
      end

      # One DocumentRef per text page carrying a run of the edition's
      # language; pages without one (an edition's notes pages) skip by rule.
      def discover(workdir)
        text_pages(workdir).filter_map do |id, stem, path|
          next unless language_lane?(id, path)

          Nabu::DocumentRef.new(source_id: slug, id: document_urn(id, stem), path: path,
                                metadata: { "edition" => id, "page" => stem })
        end
      end

      def discovery_skips(workdir)
        skipped = text_pages(workdir).count { |id, _stem, path| !language_lane?(id, path) }
        notes = skipped.positive? ? ["#{skipped} page(s) carry no #{self.class::NAME} text lane — notes pages"] : []
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: 0, notes: notes)
      end

      # Parse one page into a Document of unit Passages. A page whose
      # language lanes key no unit is a structural failure (ParseError).
      def parse(document_ref)
        html = read(document_ref.path)
        edition_id = document_ref.metadata.fetch("edition")
        edition = self.class::EDITIONS.fetch(edition_id)
        units = TitusLevelsParser.parse(html, lanes: lanes_for(edition), label: slug)
        raise Nabu::ParseError, "#{slug}: no text units in #{document_ref.path}" if units.empty?

        stem = document_ref.metadata["page"]
        document = Nabu::Document.new(
          urn: document_ref.id, language: self.class::LANGUAGE, canonical_path: document_ref.path,
          title: "#{self.class::TITLE} — #{edition.name} (#{stem})",
          metadata: document_metadata(edition_id, edition, html)
        )
        seen = Hash.new(0)
        units.each_with_index do |unit, sequence|
          occurrence = (seen[unit.anchor] += 1)
          document << Nabu::Passage.new(
            urn: passage_urn(document_ref.id, unit.anchor, occurrence), language: self.class::LANGUAGE,
            text: unit.text, sequence: sequence, annotations: unit_annotations(unit, occurrence)
          )
        end
        document
      end

      # One polite TitusFetch walk per edition (owner-run; never in tests).
      def fetch(workdir, progress: nil, force: false)
        shas = []
        atticked = []
        @editions.each do |id, edition|
          result = Nabu::TitusFetch.sync!(
            entry_url: self.class.entry_url(edition), dir: File.join(workdir, id),
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
        raise Nabu::FetchError, "#{slug} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def slug = self.class::SLUG

      def read(path) = Nabu::Adapters::SourceRead.utf8_file(path, label: slug, repair: :severed_tags)

      def lanes_for(edition) = edition.lanes || self.class::LANES

      # [edition id, page stem, path] for every numbered text page.
      def text_pages(workdir)
        @editions.flat_map do |id, edition|
          Dir.glob(File.join(workdir, id, "#{edition.prefix}*.htm")).filter_map do |path|
            name = File.basename(path)
            [id, name.delete_suffix(".htm"), path] if name.match?(edition.page_re)
          end
        end
      end

      # The byte needle; an unreadable page counts as text so parse
      # quarantines it loudly instead of discovery hiding it.
      def language_lane?(edition_id, path)
        read(path).match?(lanes_for(@editions.fetch(edition_id)).needle)
      rescue Nabu::ParseError
        true
      end

      def document_urn(edition_id, stem) = "urn:nabu:#{slug}:#{edition_id}.#{stem}"

      # A re-anchored unit keys its repeat by occurrence (the titus family's
      # P43-i2 shape) — real text, never merged, never dropped.
      def passage_urn(document_urn, anchor, occurrence)
        tail = occurrence > 1 ? "#{anchor}##{occurrence}" : anchor
        "#{document_urn}:#{tail}"
      end

      def unit_annotations(unit, occurrence)
        annotations = { "unit" => unit.label }
        annotations.merge!(unit.location)
        annotations.merge!(unit.others)
        annotations.merge!(unit.extras)
        annotations["repetition"] = occurrence if occurrence > 1
        annotations
      end

      # Edition identity, the kind key, the header's own statements, and the
      # date/place the edition's pages state.
      def document_metadata(edition_id, edition, html)
        metadata = { "edition" => edition_id, "edition_name" => edition.name, "editors" => edition.editors,
                     "work" => work_for(edition_id, html) }
        doc = Nokogiri::HTML(html)
        HEADER_SPANS.each do |span_id, key|
          parts = doc.css(%(span[id="#{span_id}"])).map { |span| TitusLevelsParser.clean(span.text) }
          text = parts.reject(&:empty?).join(" … ")
          metadata[key] = text unless text.empty?
        end
        metadata["date"] = edition.date if edition.date
        metadata["place"] = edition.place if edition.place
        metadata
      end

      # The kind_map key — the edition (one work per edition); a collection
      # edition overrides it.
      def work_for(edition_id, _html) = edition_id
    end
  end
end
