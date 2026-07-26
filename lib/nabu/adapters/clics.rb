# frozen_string_literal: true

require "digest"

require_relative "clics_gml_parser"
require_relative "../normalize"

module Nabu
  module Adapters
    # CLICS³ — the Database of Cross-Linguistic Colexifications (Rzymski,
    # Tresoldi et al. 2019; clics.clld.org), P46-6: which meanings share a
    # word, measured across ~3,000 language varieties. The etym desk's
    # semantic-shift compass beside WOLD's loanword flows: when a Latin
    # gloss and a Greek gloss colexify across 30 families, a proposed
    # semantic development in an etymology stops being hand-waving.
    #
    # == Scope: the aggregate network, argued (the packet's honesty clause)
    #
    # Upstream distributes (a) a 90 MB sqlite with ~540K per-variety
    # colexification statements and (b) the released NETWORK artifacts —
    # nodes = Concepticon-linked concepts, edges = colexification pairs
    # weighted by family/variety/word counts, WITH the per-edge family
    # list. This shelf ingests (b) at its published grain
    # (clics3-network.gml, the 3-families-threshold network: 2,919 nodes /
    # 4,228 edges): the family-aware pair network IS the research surface;
    # the per-variety word lists behind it stay upstream (their bulk —
    # Words/wofam attribute strings — is recognized and skipped by name in
    # the parser). Scoped, stated, revisitable if per-variety grain ever
    # earns its own surface.
    #
    # == Surface: one dictionary (slug clics, language mul)
    #
    # One entry per EDGE-BEARING concept node (an isolated node has no
    # colexification content — the iecor no-members-no-entry rule),
    # entry_id = the node's Concepticon id (upstream-stable), headword =
    # the Concepticon gloss verbatim ("EARTH (SOIL)"), gloss = the
    # semantic field, body = the attestation census plus one ↔ line per
    # partner (strongest FamilyWeight first) with the family list
    # verbatim. `mul` (ISO 639-2 "multiple languages") is the honest
    # collective for cross-linguistic concepts — the iecor `ine` argument
    # one level up. No reflex rows: the aggregate grain carries no word
    # forms.
    #
    # == Upstream artifact: the tagged release blob, sha-pinned
    #
    # clics3-network.gml.zip is CHECKED INTO the clics/clics3 repo at tag
    # v1.1 — a raw URL at a tag is a stable git blob (byte-stable, unlike
    # generated zipballs), so it takes the iecor hard-pin posture:
    # ZipFetch + RELEASE_SHA256 verified between download and any tree
    # mutation. A new CLICS release is a new tag: owner re-pins URL + sha.
    #
    # == License (README at v1.1, verified 2026-07-26)
    #
    # "This data is licensed under CC BY 4.0" → attribution. Cite:
    # Rzymski, Tresoldi et al. 2019, The Database of Cross-Linguistic
    # Colexifications, reproducible analysis of cross-linguistic
    # polysemies (DOI 10.17613/5awv-6w15).
    class Clics < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "clics",
        name: "CLICS³ — Database of Cross-Linguistic Colexifications (aggregate network, v1.1)",
        license: "CC BY 4.0 (repo README verbatim: \"This data is licensed under CC BY 4.0\"; " \
                 "cite Rzymski, Tresoldi et al. 2019, The Database of Cross-Linguistic " \
                 "Colexifications, DOI 10.17613/5awv-6w15)",
        license_class: "attribution",
        upstream_url: "https://github.com/clics/clics3",
        parser_family: "clics-gml"
      )

      # The released network artifact, checked into the repo at tag v1.1
      # (12,181,049 B; unzips to graphs/network-3-families.gml, 67 MB).
      ARTIFACT_URL = "https://raw.githubusercontent.com/clics/clics3/v1.1/clics3-network.gml.zip"

      # sha256 of the artifact zip, pinned from the 2026-07-26 download. A
      # tagged git blob never changes: a mismatch is corruption or a
      # force-pushed tag, never a routine update.
      RELEASE_SHA256 = "c4b2069b65a06ada8513ee107e398ca41d0f56ba00fa77919755e80a236ccf7d"

      DICTIONARY_SLUG = "clics"
      DICTIONARY_LANGUAGE = "mul"
      TITLE = "CLICS³ — cross-linguistic colexification network (Rzymski, Tresoldi et al. 2019)"
      GML_FILE = "network-3-families.gml"

      def self.manifest
        MANIFEST
      end

      def self.content_kind = :dictionary

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "clics3-network.gml.zip", zip_url: ARTIFACT_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the release sha (tests; a future owner re-pin drill).
      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
      end

      # One DocumentRef for the one network file, wherever the unpack put
      # it (ZipFetch flattens the zip's single graphs/ top dir onto the
      # workdir; the fixture keeps graphs/ — both discover identically).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        gml = Dir.glob(File.join(workdir, "**", GML_FILE)).min
        return unless gml

        yield Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{DICTIONARY_SLUG}:network",
          path: File.expand_path(gml), metadata: {}
        )
      end

      def parse(document_ref)
        result = ClicsGmlParser.new.read(document_ref.path)
        by_id = result.nodes.to_h { |node| [node.id, node] }
        edges = Hash.new { |hash, key| hash[key] = [] }
        result.edges.each do |edge|
          edges[edge.source] << [edge, edge.target]
          edges[edge.target] << [edge, edge.source]
        end
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: DICTIONARY_LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        result.nodes.each do |node|
          partners = edges[node.id]
          next if partners.empty? # an isolated node has no colexification content

          document << build_entry(node, partners, by_id)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "clics: #{document_ref.id}: #{e.message}"
      end

      # ZipFetch with the phases driven by hand so the sha pin is checked
      # BETWEEN download and any tree mutation (the iecor choreography).
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ARTIFACT_URL, dir: workdir,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: fetch_notes(fetch))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "clics fetch failed into #{workdir}: #{e.message}"
      end

      private

      def build_entry(node, partners, by_id)
        gloss = Nabu::Normalize.nfc(node.gloss)
        folded = Nabu::Normalize.search_form(gloss, language: DICTIONARY_LANGUAGE)
        Nabu::DictionaryEntry.new(
          entry_id: node.concepticon_id, key_raw: node.gloss, language: DICTIONARY_LANGUAGE,
          headword: gloss,
          headword_folded: folded.strip.empty? ? node.concepticon_id : folded,
          gloss: node.semantic_field && Nabu::Normalize.nfc(node.semantic_field),
          body: body_text(node, partners, by_id)
        )
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "clics: concept #{node.concepticon_id.inspect}: #{e.message}"
      end

      def body_text(node, partners, by_id)
        lines = [headline(node), census_line(node)]
        sorted = partners.sort_by do |edge, partner_id|
          [-edge.family_weight.to_i, by_id[partner_id]&.gloss.to_s]
        end
        sorted.each { |edge, partner_id| lines.concat(edge_lines(edge, by_id[partner_id])) }
        Nabu::Normalize.nfc(lines.compact.join("\n"))
      end

      def headline(node)
        facets = [node.semantic_field && "semantic field: #{node.semantic_field}",
                  node.category && "category: #{node.category}"].compact
        suffix = facets.empty? ? "" : " (#{facets.join('; ')})"
        "CLICS³ concept #{node.concepticon_id} — #{node.gloss}#{suffix}"
      end

      def census_line(node)
        return nil unless node.language_frequency

        "attested in #{node.language_frequency} varieties / #{node.family_frequency} families / " \
          "#{node.word_frequency} words"
      end

      def edge_lines(edge, partner)
        return [] unless partner # a dangling endpoint would be upstream damage; parser guards ids

        line = "↔ #{partner.gloss} (Concepticon #{partner.concepticon_id}) — " \
               "#{edge.family_weight} families / #{edge.language_weight} varieties / " \
               "#{edge.word_weight} words"
        lines = [line]
        lines << "  families: #{edge.families.join('; ')}" unless edge.families.empty?
        lines
      end

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "clics: downloaded artifact misses the release sha256 pin (expected #{@pin}, got " \
              "#{fetch.sha}) — a tagged git blob never changes, so this is corruption or a " \
              "force-pushed tag; verify #{ARTIFACT_URL} and re-pin RELEASE_SHA256 only after " \
              "reading the release"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "v1.1 artifact sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end
    end
  end
end
