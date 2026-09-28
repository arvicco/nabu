# frozen_string_literal: true

require "nokogiri"
require_relative "../scripta_bulgarica_fetch"

module Nabu
  module Adapters
    # Scripta Bulgarica (P107-8 — Q100): the BAS Institute for
    # Literature's portal of Old and Middle Bulgarian written monuments —
    # ~125 full source texts (inscriptions, charters, chronicles,
    # homiletic and hagiographic literature, 11th–18th c.) in Unicode
    # Cyrillic with combining diacritics preserved, each page naming the
    # PRINTED EDITION it was keyed from (the per-text provenance layer).
    # Snapshot-first by design: the upstream is a Drupal 7 on PHP 5.5
    # over plain HTTP — the mirror in canonical/ IS the insurance copy
    # (survey 2026-09-28).
    #
    # == The Drupal field contract (fixture-verified 2026-09-28)
    #
    #   field-name-body                        → the source TEXT
    #   field-name-field-manuscript-transcript → the edition citation
    #   field-name-field-author                → author (where named)
    #   (field-terms etc. → further metadata; never passages)
    #
    # == Identity / passages
    #
    # urn:nabu:scripta-bulgarica:<slug> (the site's own stable slug);
    # one passage per block-level element of the body field, sequence-
    # cited (:p1, :p2 …) — the pages carry no finer native citation.
    #
    # == Language (declared whole-source posture)
    #
    # bul, deliberately coarse: the corpus spans Old Bulgarian
    # inscriptions through Middle Bulgarian charters and 18th-c.
    # chronicle copies; the chu-recension refinement per text is a
    # recorded future lect look, never silently faked.
    #
    # == License — nc, verbatim in Bulgarian
    #
    # /bg/content/usloviya-za-polzvane: «Свободен достъп при условията
    # на лиценз Creative Commons (Creative Commons
    # Attribution-NonCommercial-ShareAlike 2.0 Generic licensе).»
    class ScriptaBulgarica < Nabu::Adapter
      BASE_URL = "http://scripta-bulgarica.eu"
      URN_PREFIX = "urn:nabu:scripta-bulgarica:"
      LANGUAGE = "bul"
      TITLE_SUFFIX = /\s*\|\s*Scripta Bulgarica\s*\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "scripta-bulgarica",
        name: "Scripta Bulgarica — Old/Middle Bulgarian written monuments (BAS)",
        license: "CC BY-NC-SA 2.0, stated verbatim in Bulgarian on the site's terms page " \
                 "(/bg/content/usloviya-za-polzvane): \"Свободен достъп при условията на лиценз " \
                 "Creative Commons (Creative Commons Attribution-NonCommercial-ShareAlike 2.0 " \
                 "Generic licensе).\" Credit Scripta Bulgarica (scripta-bulgarica.eu; BAS " \
                 "Institute for Literature) and each text's printed edition as recorded",
        license_class: "nc",
        upstream_url: BASE_URL,
        parser_family: "scripta-bulgarica-html"
      )

      def self.manifest = MANIFEST

      # One DocumentRef per mirrored source page; pager sidecars
      # (manuscript-N.html) are infrastructure, never documents.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        dir = File.join(workdir, ScriptaBulgaricaFetch::RECORD_DIR)
        return unless Dir.exist?(dir)

        Dir.children(dir).sort.filter_map do |name|
          slug = name.delete_suffix(".html")
          next unless name.end_with?(".html")

          Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{slug}",
                                path: File.join(dir, name), metadata: { "slug" => slug })
        end.each(&block)
      end

      def parse(document_ref)
        html = Nokogiri::HTML(File.read(document_ref.path, encoding: "UTF-8"))
        body = html.at_css(".field-name-body .field-items") or
          raise Nabu::ParseError, "#{document_ref.path}: no field-name-body — reshaped page?"

        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE,
          canonical_path: document_ref.path,
          title: page_title(html), metadata: metadata_for(html, document_ref)
        )
        sequence = 0
        body.css("p, div.field-item > text()").each do |node|
          text = Normalize.nfc(node.text.gsub(/\s+/, " ").strip)
          next if text.empty?

          sequence += 1
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:p#{sequence}", language: LANGUAGE,
            text: text, sequence: sequence
          )
        end
        # A body without <p> grain (bare text) still yields its one passage.
        if sequence.zero?
          text = Normalize.nfc(body.text.gsub(/\s+/, " ").strip)
          unless text.empty?
            document << Nabu::Passage.new(urn: "#{document_ref.id}:p1", language: LANGUAGE,
                                          text: text, sequence: 1)
          end
        end
        document
      end

      def fetch(workdir, progress: nil, force: false)
        result = ScriptaBulgaricaFetch.sync!(
          base_url: BASE_URL, dir: workdir,
          attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now,
                              notes: "#{result.records} texts listed · #{result.fetched} fetched · " \
                                     "#{result.cached} cached · #{result.missing.size} missing")
      rescue ScriptaBulgaricaFetch::Error => e
        raise Nabu::FetchError, "scripta-bulgarica fetch failed into #{workdir}: #{e.message}"
      end

      private

      def page_title(html)
        raw = html.at_css("title")&.text.to_s.sub(TITLE_SUFFIX, "").strip
        raw.empty? ? nil : Normalize.nfc(raw)
      end

      # The provenance block: the edition citation verbatim (the layer
      # the license credit names), author and terms where present.
      def metadata_for(html, document_ref)
        meta = { "slug" => document_ref.metadata["slug"] }
        edition = field_text(html, "field-name-field-manuscript-transcript")
        meta["edition"] = edition if edition
        author = field_text(html, "field-name-field-author")
        meta["author"] = author if author
        terms = field_text(html, "field-name-field-terms")
        meta["terms"] = terms if terms
        meta
      end

      def field_text(html, klass)
        node = html.at_css(".#{klass} .field-items") or return nil
        text = Normalize.nfc(node.text.gsub(/\s+/, " ").strip)
        text.empty? ? nil : text
      end
    end
  end
end
