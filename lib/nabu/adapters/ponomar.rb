# frozen_string_literal: true

require "nokogiri"
require_relative "source_read"

module Nabu
  module Adapters
    # ponomar — the Church Slavonic service texts of Ponomar, the Orthodox
    # liturgics suite of Aleksandr Andreev and others
    # (github.com/typiconman/ponomar). Ponomar assembles the services of
    # any day from small text files; this source takes the Church Slavonic
    # files under Ponomar/languages/cu/xml/Services/ — the kit for the
    # Hours (First, Third, Sixth, Ninth, the Typika, the Royal and Paschal
    # Hours): the fixed prayers and responses (Trisagion, Our Father, the
    # Creed, "O Heavenly King", the prayers of the Hours, of St Ephrem and
    # of St Basil), the troparia and kontakia of the weekday and Sunday
    # Octoechos cycle and of Lent, the theotokia, the rubric words, and the
    # service titles.
    #
    # == Format (inspected first-hand, master 0af645f, 2026-08-17)
    #
    # Each file is a tiny XML record (UTF-8, 14 with a BOM), no DTD and no
    # namespace: a root COMMONPRAYER / TROPARION / KONTAKION holding one
    # <TEXT Value="…"/> (the text, hard-wrapped inside the attribute) and
    # at most one <HEADER Value="…"/> (the rubric title — "Тропа́рь
    # прⷣте́чи, гла́съ в҃"; once an English editor's note instead:
    # "This is not necessarily the correct spelling."). XML comments carry
    # editors' notes ("This is an archaic version of the Troparion as it
    # commemorates the Emperor."). The orthography is the Synodal Church
    # Cyrillic of the printed service books — titla (U+0483, the letter
    # titla U+2DE0–2DFF), accents, psili (U+0486), ѿ, ꙋ, ѧ, ѣ, і, ѵ, ѳ, ѡ.
    # The Hours' own source files credit http://orthlib.ru for the text.
    #
    # == Delivery grains (the whole Services tree, 347 files)
    #
    # Upstream serves, under Services/: CommonPrayers/ (fixed texts, 111;
    # its TROPARION/ 56 and KONTAKION/ 61 subtrees — the weekday × tone
    # Octoechos troparia/kontakia SUN1…SAT8 plus the Lenten MTTL/WFL/SatL
    # sets), Command/ (14 rubric words: "покло́нъ", "(гла́съ а҃)"), Text/
    # (21 service titles, the Paschal Hours rubric, source credits),
    # Octoecheos/Tone 0–7/ (56 TONE schedules) and Var/ (28 assembly
    # templates). Document = file (urn:nabu:ponomar:cu:<path with / → .>,
    # case kept: …:cu:CommonPrayers.TROPARION.TUES7); passage = each
    # non-blank TEXT (one per file in practice, cited 1). SKIPPED BY RULE
    # (counted in discovery_skips, a real specimen of each pinned in the
    # fixture): TONE schedules and SERVICE/SERVICES templates (directives,
    # no text), blank TEXT records, English placeholder stubs ("Church
    # Slavonic Text is placed here."), source-credit records (a URL), and
    # the program's window captions ("Пономарь: Ча́съ тре́тїй"). Anything
    # else (another root, a non-XML file) is UNRECOGNIZED, never silent.
    #
    # Reconciliation (census through the adapter over master 0af645f,
    # 2026-11-04): upstream's git tree lists 347 files under Services/
    # (the only count it advertises) = 246 accepted (CommonPrayers 106,
    # TROPARION 56, KONTAKION 61, Command 14, Text 9; one passage each,
    # 157 distinct texts — the weekday hymns repeat across the eight
    # Octoechos weeks, kept as upstream addresses them) + 101 skipped by
    # rule (56 TONE + 28 templates + 4 placeholders + 3 blank + 5 source
    # credits + 5 captions), 0 unrecognized.
    #
    # NOT taken (outside the sparse cone, never fetched): the other
    # languages' Services trees (el, en, fr, zh, ar, la), cu/xml/lives/
    # (3,041 commemoration files — Russian-language lives plus troparia/
    # kontakia for 581 commemorations: a recorded widening candidate),
    # the menaion day indexes cu/xml/01–12, the Elizabeth Bible text
    # (cu/bible/elis), cu/ru (civil-script renderings), icons, the Java
    # and Perl program code.
    #
    # == Text, language, axes
    #
    # Text = the TEXT attribute, whitespace runs collapsed to one space
    # (the hard-wraps are layout; XML attribute normalization already
    # turns them into spaces), NFC at the boundary — the files carry
    # decomposed и + U+0300 and і + U+0308 on 199 attributes, which NFC
    # composes (chu is not NFC-exempt). Language chu; config/
    # lect_overrides.yml resolves it to chu:ncs, the registry's New Church
    # Slavonic (Synodal) stage — these are the post-Nikonian service books
    # in modern liturgical use. Title = the Cyrillic HEADER, else the
    # text's incipit; the English HEADER rides as editorial_note.
    # Mined per document: service_part (TROPARION / KONTAKION / the
    # top folder — the kind fold key, config/kind_map.yml), tone (the
    # header's own "гла́съ X", Cyrillic numeral a҃–и҃ → 1–8), weekday +
    # octoechos_tone (from the file name SUN1…SAT8: the weekday and the
    # Octoechos week whose Hours take the text — the hymn's own tone is
    # the header's), upstream_name (Ponomar's English id: HeavenlyKing),
    # upstream_path, upstream_comments. Undated (the asset carries no
    # date; received tradition in modern Synodal redaction), unplaced.
    #
    # == License (read first-hand 2026-11-04)
    #
    # GPL-3.0: the repo's LICENSE is the GNU GPL v3 text, and README.md:
    # "Copyright 2006-2018 Aleksandr Andreev and others. Ponomar is free
    # software: you can redistribute it and/or modify it under the terms
    # of the GNU General Public License as published by the Free Software
    # Foundation, either version 3 of the License, or (at your option)
    # any later version." The text files carry no license of their own;
    # the repo-wide grant covers them. Carriage: GPL permits verbatim
    # redistribution with the license and source named; any redistributed
    # derivative of the files stays under GPL — a copyleft obligation of
    # the same shape as CC BY-SA/GFDL, which the house classes
    # `attribution` (the emmo/ptg/wiktionary precedent), so this source is
    # `attribution`, the license string naming GPL-3.0-or-later.
    class Ponomar < Nabu::Adapter
      SLUG = "ponomar"
      URN_PREFIX = "urn:nabu:ponomar:cu:"
      LANGUAGE = "chu"
      REPO_URL = "https://github.com/typiconman/ponomar"
      SERVICES_DIR = "Ponomar/languages/cu/xml/Services"
      SPARSE_PATHS = ["/#{SERVICES_DIR}/", "/LICENSE", "/README.md"].freeze

      TEXT_ROOTS = %w[COMMONPRAYER TROPARION KONTAKION].freeze
      HYMN_FOLDERS = %w[TROPARION KONTAKION].freeze
      PLACEHOLDER = /\AChurch Slavonic Text (?:is placed|comes) here\.?\z/
      SOURCE_CREDIT = %r{\Ahttps?://}
      CAPTION = /\AПономарь:/
      WEEKDAYS = { "SUN" => "Sunday", "MON" => "Monday", "TUES" => "Tuesday", "WED" => "Wednesday",
                   "THUR" => "Thursday", "FRI" => "Friday", "SAT" => "Saturday" }.freeze
      WEEKDAY_FILE = /\A(#{WEEKDAYS.keys.join('|')})([1-8])\z/
      TONE_NUMERALS = { "а" => 1, "в" => 2, "г" => 3, "д" => 4, "е" => 5, "ѕ" => 6, "з" => 7, "и" => 8 }.freeze
      TONE = /гла́?съ\s+([#{TONE_NUMERALS.keys.join}])҃/i
      INCIPIT_WORDS = 6

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Ponomar — Church Slavonic service texts (the Hours kit)",
        license: "GPL-3.0-or-later — README.md verbatim: \"Copyright 2006-2018 Aleksandr Andreev and others. " \
                 "Ponomar is free software: you can redistribute it and/or modify it under the terms of the GNU " \
                 "General Public License as published by the Free Software Foundation, either version 3 of the " \
                 "License, or (at your option) any later version.\" (LICENSE: the GNU GPL v3 text; read " \
                 "2026-11-04). Carried verbatim with the license and source named.",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "ponomar-xml",
        credit: "Ponomar, © 2006-2018 Aleksandr Andreev and others, github.com/typiconman/ponomar (GPL-3.0)."
      )

      Record = Data.define(:root, :header, :texts, :comments)

      def self.manifest = MANIFEST

      # "Тропа́рь, гла́съ а҃" → 1; nil when the header names no tone.
      def self.tone(header)
        match = TONE.match(Normalize.nfc(header.to_s)) or return nil

        TONE_NUMERALS.fetch(match[1].downcase)
      end

      # The first INCIPIT_WORDS words, "…" when the text runs on.
      def self.incipit(text)
        words = text.split
        head = words.first(INCIPIT_WORDS).join(" ")
        words.size > INCIPIT_WORDS ? "#{head}…" : head
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        classified(workdir).each do |path, (verdict, _note)|
          next unless verdict == :accept

          relpath = relative(workdir, path)
          stem = Normalize.nfc(relpath.delete_suffix(".xml").tr("/", "."))
          yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{stem}", path: path,
                                      metadata: { "upstream_path" => Normalize.nfc(relpath) })
        end
      end

      def discovery_skips(workdir)
        notes = []
        unrecognized = []
        classified(workdir).each do |path, (verdict, note)|
          line = "#{relative(workdir, path)}: #{note}"
          case verdict
          when :skip then notes << line
          when :unknown then unrecognized << line
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: unrecognized.size,
                                          notes: notes + unrecognized)
      end

      def parse(document_ref)
        record = read_record(document_ref.path)
        raise Nabu::ParseError, "#{document_ref.path}: not a text record" unless record && accepted?(record)

        relpath = document_ref.metadata.fetch("upstream_path")
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: title(record), metadata: document_metadata(record, relpath))
        record.texts.reject(&:empty?).each_with_index do |text, index|
          document << Nabu::Passage.new(urn: "#{document.urn}:#{index + 1}", language: LANGUAGE,
                                        text: text, sequence: index + 1)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, sparse: SPARSE_PATHS)
      end

      private

      # Split out so the fetch test can point a singleton at a local repo.
      def repo_url = REPO_URL

      def services_root(workdir) = File.join(workdir, SERVICES_DIR)

      def relative(workdir, path) = path.delete_prefix("#{File.expand_path(services_root(workdir))}/")

      # [[absolute path, [verdict, note]]] over every file in the Services
      # tree, sorted by path.
      def classified(workdir)
        root = services_root(workdir)
        return [] unless Dir.exist?(root)

        files = Dir.glob(File.join(root, "**", "*")).select { |path| File.file?(path) }
        files.map { |path| File.expand_path(path) }.sort.map { |path| [path, classify(path)] }
      end

      def classify(path)
        return [:unknown, "not an XML file — unrecognized member of the Services tree"] unless path.end_with?(".xml")

        record = read_record(path)
        return [:unknown, "unparseable — unrecognized member of the Services tree"] unless record

        case record.root
        when "TONE"
          [:skip, "an Octoechos schedule (which troparion/kontakion each Hour takes, by weekday and tone) — " \
                  "directives, no text of its own"]
        when "SERVICE", "SERVICES"
          [:skip, "an assembly template (the Hours engine's GET/GETID directives) — no text of its own"]
        when *TEXT_ROOTS then classify_text(record)
        else [:unknown, "root <#{record.root}> — unrecognized record type"]
        end
      end

      def classify_text(record)
        texts = record.texts.reject(&:empty?)
        return [:skip, "no text (a blank TEXT record)"] if texts.empty?
        return [:skip, "an English placeholder stub (#{texts.first.inspect}) — no Church Slavonic yet"] if
          texts.all? { |text| PLACEHOLDER.match?(text) }
        return [:skip, "a source credit (#{texts.first}) — provenance, not text"] if
          texts.all? { |text| SOURCE_CREDIT.match?(text) }
        return [:skip, "the program's window caption (#{texts.first.inspect}) — software chrome"] if
          texts.all? { |text| CAPTION.match?(text) }

        [:accept, nil]
      end

      def accepted?(record) = TEXT_ROOTS.include?(record.root) && classify_text(record).first == :accept

      def read_record(path)
        xml = SourceRead.utf8_file(path, label: "ponomar").delete_prefix("﻿")
        doc = Nokogiri::XML(xml)
        return nil unless doc.root && doc.errors.none? { |e| e.level >= 2 }

        Record.new(root: doc.root.name,
                   header: clean(doc.at_xpath("//HEADER")&.[]("Value")),
                   texts: doc.xpath("//TEXT").map { |node| clean(node["Value"]) },
                   comments: doc.xpath("//comment()").map { |node| clean(node.text) }.reject(&:empty?))
      end

      def clean(value) = Normalize.nfc(value.to_s.gsub(/\s+/, " ").strip)

      def cyrillic?(text) = text.match?(/\p{Cyrillic}/)

      def title(record)
        header = record.header
        return header if cyrillic?(header)

        self.class.incipit(record.texts.reject(&:empty?).first)
      end

      def document_metadata(record, relpath)
        folders = relpath.split("/")[0..-2]
        name = File.basename(relpath, ".xml")
        header = record.header
        weekday = HYMN_FOLDERS.intersect?(folders) ? WEEKDAY_FILE.match(name) : nil
        {
          "service_part" => (folders & HYMN_FOLDERS).first || folders.first,
          "upstream_path" => relpath, "upstream_name" => name,
          "header" => (header if cyrillic?(header)),
          "editorial_note" => (header unless header.empty? || cyrillic?(header)),
          "tone" => self.class.tone(header),
          "weekday" => weekday ? WEEKDAYS.fetch(weekday[1]) : nil,
          "octoechos_tone" => weekday ? Integer(weekday[2], 10) : nil,
          "upstream_comments" => (record.comments unless record.comments.empty?)
        }.compact.transform_values { |value| value.is_a?(String) ? Normalize.nfc(value) : value }
      end
    end
  end
end
