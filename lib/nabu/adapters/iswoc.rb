# frozen_string_literal: true

require_relative "proiel"

module Nabu
  module Adapters
    # The ISWOC adapter (packet P12-1): the ISWOC Treebank (Information
    # Structure and Word Order Change in Germanic and Romance; Bech & Eide,
    # University of Oslo) ships the *identical* PROIEL 2.1 XML as
    # proiel/torot — one flat directory of per-source *.xml files — so this is
    # the TOROT pattern over again (manifest override, everything else
    # inherited) plus exactly ONE new behavior: the Old English language
    # filter. The repo carries five OE texts (wscp, æls, apt, chrona, or —
    # the corpus's first Old English, ~29,406 gold tokens) alongside one Old
    # French and nine medieval Spanish/Portuguese chronicles that are outside
    # this corpus's scope; #document_refs keeps only <source language="ang">,
    # judged from the header the inherited discover already peeks — never
    # from filenames (docs/oe-survey.md; owner-approved plan in backlog
    # P12-1).
    #
    # == Shared urn:nabu:proiel: namespace (TOROT precedent)
    #
    # ISWOC documents mint under the inherited urn:nabu:proiel:<source-id>
    # namespace: same treebank family, same PROIEL id-space by upstream
    # convention (ids wscp/æls/apt/chrona/or are disjoint from proiel's and
    # torot's), and the P11-3 alignment hub's prepared OE Mark line keys on
    # urn:nabu:proiel:wscp. See Torot's header for the full argument; the
    # loader's (source_id, urn) keying contains any convention break. Two
    # id-shape firsts land here: æls is the corpus's first non-ASCII source
    # id (urn:nabu:proiel:æls, NFC — æ is a single codepoint) and or is two
    # letters; both are used verbatim, never transliterated.
    #
    # == License
    #
    # CC BY-NC-SA 3.0 (US) — the repo README ("freely available under a
    # Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License") and
    # every per-source <source>/<license> header agree; no LICENSE file.
    # license_class "nc", exactly like its proiel/torot siblings. Cite as:
    # Bech, Kristin and Kristine Eide. 2014. The ISWOC corpus. Department of
    # Literature, Area Studies and European Languages, University of Oslo.
    #
    # == fetch / sync policy
    #
    # Single upstream repo, so the inherited clone/ff-only-pull fetch applies
    # verbatim — pinned to the ORIGINAL iswoc/iswoc-treebank, which is
    # GitHub-archived (read-only) at its final commit 574c81c (2023-05-02):
    # genuinely frozen, hence sync_policy: frozen (config/sources.yml), the
    # proiel-treebank precedent. NOTE FOR THE FUTURE: releases moved to
    # syntacticus/syntacticus-treebank-data (per the README), but as of
    # 2026-07 that repo's HEAD *predates* the original's final commit and
    # bundles proiel/ + torot/ + menotec/ subtrees. If it is ever adopted as
    # upstream, discovery MUST scope to its iswoc/ subdirectory — the sibling
    # subtrees are the same data already synced by the Proiel and Torot
    # adapters (double-load hazard, docs/oe-survey.md).
    class Iswoc < Proiel
      # CC BY-NC-SA 3.0 (US) → license_class "nc".
      MANIFEST = Nabu::SourceManifest.new(
        id: "iswoc",
        name: "ISWOC Treebank — Old English texts",
        license: "CC BY-NC-SA 3.0 (per-source headers; repo README, no LICENSE file)",
        license_class: "nc",
        upstream_url: "https://github.com/iswoc/iswoc-treebank",
        parser_family: "proiel"
      )

      # The corpus-scope filter: keep only Old English sources.
      LANGUAGE = "ang"

      def self.manifest
        MANIFEST
      end

      private

      # The ang filter — the one behavior added over the TOROT pattern. The
      # inherited document_refs already peeked each file's <source> header, so
      # scoping to Old English is a metadata select, never a filename match
      # (the Romance texts carry the same PROIEL shape and would parse fine;
      # they are excluded because they are out of corpus scope, not broken).
      def document_refs(workdir)
        super.select { |ref| ref.metadata["language"] == LANGUAGE }
      end
    end
  end
end
