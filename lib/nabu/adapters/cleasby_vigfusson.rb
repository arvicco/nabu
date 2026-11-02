# frozen_string_literal: true

require_relative "definitions_json_shelf"

module Nabu
  module Adapters
    # Cleasby-Vigfusson: Richard Cleasby and Gudbrand Vigfusson, An
    # Icelandic-English Dictionary (Oxford: Clarendon Press, 1874) — the
    # classic dictionary of the Old Norse-Icelandic literary language, in
    # Sampo Silvennoinen's JSON edition (github.com/stscoundrel/
    # cleasby-vigfusson-dictionary). The first Old Norse dictionary shelf,
    # for the held West Norse text (menota, menotec, rundata, the UD
    # Icelandic treebank).
    #
    # Stored language non — the registry's undivided Old Norse anchor.
    # Deliberately coarse (declared): the book is "Icelandic-English" and
    # its object is the Old Icelandic literary language (isl:old) with
    # Old Norwegian in its citations; a per-entry stage is not printed, so
    # the shelf claims the anchor.
    #
    # == Upstream / grains (verified 2026-11-02)
    #
    # The repo (pushed 2024-09-07) serves the dictionary twice under json/:
    # cleasby-vigfusson.json (11,742,655 B, the book's <strong>/<i> markup
    # kept) — ACCEPTED, the markup marks the English glosses — and
    # cleasby-vigfusson-no-markup.json (10,656,938 B, the same records with
    # the markup stripped) — REJECTED by rule, a lossy twin; the rest is
    # the Node.js package (src/, tests, package files). Census through the
    # house parser: 35,207 entries (README: "35 000+ Old Norse words";
    # upstream advertises no exact total), 7 homograph words numbered, 4
    # non-NFC records normalized, 2,748 without an italic English gloss.
    # Transcription provenance is not stated upstream.
    #
    # == License
    #
    # LICENSE, verbatim: "MIT License / Copyright (c) 2020 Sampo
    # Silvennoinen"; the README: "It was published in 1874, which leads to
    # there being many public domain versions of the book available." The
    # 1874 text is public domain by age, but the edition's MIT grant asks
    # for its notice to travel with copies → license_class "attribution"
    # (the house MIT precedent: bridging, corph, qieyun-restored).
    class CleasbyVigfusson < DefinitionsJsonShelf
      MANIFEST = Nabu::SourceManifest.new(
        id: "cleasby-vigfusson",
        name: "Cleasby-Vigfusson, An Icelandic-English Dictionary (1874) — stscoundrel JSON edition",
        license: "MIT (verbatim LICENSE: \"MIT License / Copyright (c) 2020 Sampo Silvennoinen\"); " \
                 "the 1874 text is public domain",
        license_class: "attribution",
        upstream_url: "https://github.com/stscoundrel/cleasby-vigfusson-dictionary",
        parser_family: "definitions-json"
      )

      JSON_PATH = "json/cleasby-vigfusson.json"
      REJECTED_PATHS = {
        "json/cleasby-vigfusson-no-markup.json" => "the same records with the book's markup stripped (lossy twin)"
      }.freeze
      DICTIONARY_SLUG = "cleasby-vigfusson"
      LANGUAGE = "non"
      TITLE = "An Icelandic-English Dictionary (Cleasby-Vigfusson 1874)"
    end
  end
end
