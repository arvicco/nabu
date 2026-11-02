# frozen_string_literal: true

require_relative "definitions_json_shelf"

module Nabu
  module Adapters
    # Zoëga: Geir T. Zoëga, A Concise Dictionary of Old Icelandic (Oxford:
    # Clarendon Press, 1910) — the student's abridgement of Cleasby-
    # Vigfusson aimed at the saga prose, in Sampo Silvennoinen's JSON
    # edition (github.com/stscoundrel/old-icelandic-zoega). Stands BESIDE
    # the cleasby-vigfusson shelf, deliberately unmerged (the
    # LSJ-beside-Lewis-Short precedent: two witnesses, one fold).
    #
    # Stored language non, the cleasby-vigfusson stance (declared coarse:
    # the book says Old Icelandic, isl:old; the shelf claims the anchor).
    #
    # == Upstream / grains (verified 2026-11-02)
    #
    # The repo (pushed 2024-05-25) serves json/zoega.json (4,291,377 B,
    # markup kept) — ACCEPTED — and json/zoega-no-markup.json (3,952,588
    # B) — REJECTED by rule, the lossy twin; the rest is the Node.js
    # package. Census through the house parser: 29,951 entries (README:
    # "29 000+ Old Icelandic words"; no exact upstream total), 1 homograph
    # word numbered, 0 non-NFC, 2,428 without an italic English gloss.
    # Transcription provenance is not stated upstream.
    #
    # == License
    #
    # LICENSE, verbatim: "MIT License / Copyright (c) 2020 Sampo
    # Silvennoinen"; the README: "published in 1910 by Geir Zoëga, which
    # leads to there being many public domain versions of the book
    # available." Zoëga died in 1917 → the text is public domain; the
    # edition's MIT notice travels with copies → license_class
    # "attribution" (the house MIT precedent).
    class Zoega < DefinitionsJsonShelf
      MANIFEST = Nabu::SourceManifest.new(
        id: "zoega",
        name: "Zoëga, A Concise Dictionary of Old Icelandic (1910) — stscoundrel JSON edition",
        license: "MIT (verbatim LICENSE: \"MIT License / Copyright (c) 2020 Sampo Silvennoinen\"); " \
                 "the 1910 text is public domain",
        license_class: "attribution",
        upstream_url: "https://github.com/stscoundrel/old-icelandic-zoega",
        parser_family: "definitions-json"
      )

      JSON_PATH = "json/zoega.json"
      REJECTED_PATHS = {
        "json/zoega-no-markup.json" => "the same records with the book's markup stripped (lossy twin)"
      }.freeze
      DICTIONARY_SLUG = "zoega"
      LANGUAGE = "non"
      TITLE = "A Concise Dictionary of Old Icelandic (Zoëga 1910)"
    end
  end
end
