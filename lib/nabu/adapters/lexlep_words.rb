# frozen_string_literal: true

require "json"

require_relative "wiki_template_parser"
require_relative "lexlep"
require_relative "../wiki_fetch"
require_relative "../normalize"

module Nabu
  module Adapters
    # The LexLep dictionary adapter (P29-3): the wiki's Word pages — its
    # "Dictionary of Attested Forms", the etymological lexicon of the
    # language remains documented in the inscriptions — as the Lepontic /
    # Cisalpine Gaulish dictionary shelf row. Census via api.php
    # categoryinfo 2026-07-18: 628 Word pages (the packet brief's "202"
    # was the MORPHEME category — the morphemic lexicon, journaled v2).
    #
    # A SIBLING source of `lexlep`, not the same slug: content_kind is a
    # closed per-adapter routing (:passages OR :dictionary, architecture
    # §11 — the aes/aed and mw/mw-sigla precedent), so the wiki's two
    # content grains are two registry rows sharing the WikiFetch +
    # WikiTemplateParser machinery and one licensing posture (see
    # Adapters::Lexlep for all license layers verbatim; class nc,
    # relabel-on-reply).
    #
    # == The entry shape
    #
    # entry_id/key_raw/headword = the page title verbatim — LexLep titles
    # ARE the attested forms, Leiden markers and all ("aes", ")ae?(",
    # "a?"); entry language = the page's own language param (Cisalpine
    # Gaulish → xcg, Celtic → cel, unknown → und — per-entry, the honest
    # grain; the shelf's cover language is xlp (Lepontic)). The body
    # carries the template's grammatical lanes (type, stem class, number/
    # case/gender, morphemic and phonemic analyses flattened from their
    # {{m}}/{{p}} templates) and the scrubbed Commentary — where the
    # etymology prose lives ("*ai̯ > ae, abbreviation of a longer name
    # like *Aesonios? (Lejeune 1971: 126)"). gloss = the meaning param.
    class LexlepWords < Nabu::Adapter
      WORD_CATEGORY = "Word"
      CATEGORIES = [WORD_CATEGORY].freeze

      DICTIONARY_SLUG = "lexlep-words"
      LANGUAGE = "xlp" # Lepontic (ISO 639-3 xlp; "lep" is Lepcha — review-pinned)
      TITLE = "Lexicon Leponticum — Dictionary of Attested Forms"

      # The grammatical params rendered into the body, in display order.
      GRAMMAR_PARAMS = [
        ["type_word", nil], ["stem_class", "stem class"], ["number", nil],
        ["case", nil], ["gender", nil], ["field_semantic", "semantic field"]
      ].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "lexlep-words",
        name: "Lexicon Leponticum — Dictionary of Attested Forms (Univ. Vienna)",
        license: Lexlep::MANIFEST.license,
        license_class: "nc",
        upstream_url: "https://lexlep.univie.ac.at",
        parser_family: "wiki-template"
      )

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild load
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "api.php", zip_url: "#{Lexlep::API_URL}?action=query&meta=siteinfo&format=json",
          metadata_url: nil, state_subdir: ".", state_file: Nabu::WikiFetch::STATE_FILE
        )]
      end

      def initialize(delay: Nabu::WikiFetch::DELAY)
        super()
        @delay = delay
      end

      # One ref per Word page, sorted — id "lexlep-words:<title>" (titles
      # are the wiki's unique page names; stable across syncs).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, Nabu::WikiFetch::PAGES_DIRNAME, WORD_CATEGORY, "*.json"))
           .map { |path| word_ref(File.expand_path(path)) }
           .sort_by(&:id)
           .each(&block)
      end

      def parse(document_ref)
        envelope = read_envelope(document_ref.path)
        params = parser.template_params(envelope["wikitext"], "word")
        raise ParseError, "#{document_ref.path}: no {{word}} template block" if params.nil?

        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE, title: TITLE, canonical_path: document_ref.path
        )
        document << build_entry(envelope.fetch("title"), envelope["wikitext"], params)
        document
      rescue ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::WikiFetch.sync!(
          api_url: Lexlep::API_URL, categories: CATEGORIES,
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(
          sha: result.sha, fetched_at: Time.now,
          notes: "pages: #{result.fetched} fetched, #{result.cached} cached (#{result.member_count} words)",
          repos: { Lexlep::API_URL => result.sha }
        )
      rescue Nabu::WikiFetch::Error => e
        raise Nabu::FetchError, "lexlep-words fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        @parser ||= WikiTemplateParser.new
      end

      def word_ref(path)
        title = Nabu::WikiFetch.decode_title(File.basename(path, ".json"))
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{title}", path: path,
          metadata: { "dictionary" => DICTIONARY_SLUG }
        )
      end

      def read_envelope(path)
        envelope = JSON.parse(File.read(path))
        raise ParseError, "#{path}: page envelope has no wikitext" unless envelope["wikitext"].is_a?(String)

        envelope
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable page envelope: #{e.message}"
      end

      def build_entry(title, wikitext, params)
        headword = Nabu::Normalize.nfc(title)
        language = entry_language(params)
        Nabu::DictionaryEntry.new(
          entry_id: headword, key_raw: headword, language: language,
          headword: headword, headword_folded: folded(headword, language),
          gloss: gloss(params), body: body(headword, wikitext, params)
        )
      end

      def entry_language(params)
        Lexlep::LANGUAGE_MAP.fetch(params["language"].to_s.strip, "und")
      end

      # The conventions-§9 fold; a marker-only title that folds away keeps
      # its verbatim form as the lookup key (never an empty fold).
      def folded(headword, language)
        folded = Nabu::Normalize.search_form(headword, language: language)
        folded.empty? ? headword : folded
      end

      # The meaning param, unwrapped only when the WHOLE value sits in one
      # pair of matching quotes ("'gift' (?)" keeps its inner marks).
      def gloss(params)
        value = present(params["meaning"]) or return nil
        Nabu::Normalize.nfc(value.gsub(/\A(["'])(.*)\1\z/m, '\2').strip)
      end

      def body(headword, wikitext, params)
        lines = [grammar_line(params), language_line(params),
                 analysis_line(params, "analysis_morphemic", "Morphemic analysis"),
                 analysis_line(params, "analysis_phonemic", "Phonemic analysis"),
                 meaning_line(params), commentary(wikitext)].compact
        lines.empty? ? headword : Nabu::Normalize.nfc(lines.join("\n"))
      end

      def grammar_line(params)
        parts = GRAMMAR_PARAMS.filter_map do |key, label|
          value = present(params[key]) or next
          label ? "#{label}: #{value}" : value
        end
        parts.empty? ? nil : parts.join(" · ")
      end

      def language_line(params)
        value = present(params["language"]) or return nil
        adaptation = present(params["language_adaptation"])
        adaptation ? "Language: #{value} (adapted from #{adaptation})" : "Language: #{value}"
      end

      def analysis_line(params, key, label)
        raw = present(params[key]) or return nil
        flattened = parser.plain(raw)
        flattened.empty? || flattened == "unknown" ? nil : "#{label}: #{flattened}"
      end

      def meaning_line(params)
        value = present(params["meaning"]) or return nil
        "Meaning: #{value}"
      end

      def commentary(wikitext)
        section = parser.section(wikitext, "Commentary") or return nil
        scrubbed = parser.plain(section)
        scrubbed.empty? ? nil : scrubbed
      end

      def present(value)
        value = value.to_s.strip
        value.empty? || value == WikiTemplateParser::UNKNOWN ? nil : value
      end
    end
  end
end
