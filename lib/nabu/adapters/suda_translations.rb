# frozen_string_literal: true

require_relative "../manual_drop"
require_relative "../zip_reader"
require_relative "sol_entry_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # Suda On Line — the English translations of the Suda (the SOL,
    # stoa.org / cs.uky.edu/~raphael/sol): the collaborative translation
    # of the 10th-century Byzantine lexicon-encyclopedia, entry by entry,
    # with notes, bibliography, keywords and a full translator/vetter
    # history. The Greek it translates is held as the First1K Suda
    # (urn:cts:greekLit:tlg9010.tlg001.1st1K-grc1).
    #
    # == Acquisition (ManualDrop — docs/manual/suda-translations.md)
    #
    # The SOL serves entries only through its search CGI; there is no
    # bulk download. The SOL's maintainer exported the whole database as
    # `solEntries.zip` (one saved CGI answer per Adler number, 2025-07-24)
    # and supplied it for this library by email, 2026-11-02. That zip IS
    # the canonical asset: `nabu sync suda-translations` takes it from
    # incoming/suda-translations/, validates it (zip magic + the
    # sol-entries/ tree), moves it into canonical/suda-translations/ with
    # the sha-stamped `.manual-fetch.json`, and every parse reads the zip
    # itself (Nabu::ZipReader — nothing is extracted, nothing
    # materialized). A fresher export drops the same way.
    #
    # == Grains, identity, census (the full export, 2026-11-02)
    #
    # 31,371 files: 31,341 entry pages · 27 letter index pages (skipped
    # by rule) · 2 "no matches" pages (epsilon/4079 — listed in its index
    # — and tau/1316; skipped inside their letter documents, named in
    # metadata) · 1 mis-keyed query page in a misspelled directory
    # (omicrioniota/8, which answered 27 records; skipped by rule). The
    # indexes list 31,342 entry files = 31,341 + epsilon/4079, so
    # accepted + skipped account for everything the export serves. Every
    # entry carries vetting status "high".
    #
    # Document = one Adler letter (27: the 24 letters + αι ει οι, the
    # export's own directories), urn:nabu:suda-translations:<sol letter>;
    # passage = one entry, urn …:<letter>:<n>, sequence n, text = the
    # English translation. Annotations carry the Adler citation ("ν 27"),
    # SOL's own key ("nu,27"), the Greek headword(s) (betacode decoded),
    # the translated headword, SOL's Greek Original (decoded; the "#"
    # placeholder omitted), notes, references, web addresses, keywords,
    # translator + date and the vetting history. The Greek Original rides
    # as an annotation, never as text: the passage is the translation.
    #
    # == Alignment keying
    #
    # FIRST1K_CHAPTERS is the observed First1K chapter label per letter
    # (book.chapter: Latin capitals for A/B/E, "Aι", "Ο255" — upstream's
    # own labels); each passage of a mapped letter carries
    # "first1k_candidate" (book.chapter.n). The First1K edition lacks ten
    # letters and splits some sections (1a/1b), so the candidate is a
    # join key for the alignment work to verify, never a claimed edge.
    #
    # == License
    #
    # The SOL home page: "All our entries, including translations and
    # annotations, are covered by a Creative Commons
    # 'Attribution-NonCommerical-ShareAlike License'"; the rights page
    # links CC BY-NC-SA 1.0 and asks credit to the SOL and the
    # translator(s) (read 2026-11-02) → nc. Every passage names its
    # translator.
    class SudaTranslations < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "suda-translations",
        name: "Suda On Line — English translations of the Suda",
        license: "CC BY-NC-SA 1.0 — the SOL's statement: \"All our entries, including translations " \
                 "and annotations, are covered by a Creative Commons 'Attribution-NonCommercial-" \
                 "ShareAlike License'\"; credit the Suda On Line and the translator(s). The entry " \
                 "export supplied by the SOL's maintainer by email, 2026-11-02",
        license_class: "nc",
        upstream_url: "https://www.cs.uky.edu/~raphael/sol/sol-html/",
        parser_family: "sol-html"
      )

      SLUG = "suda-translations"
      ARCHIVE = "solEntries.zip"
      ROOT = "sol-entries"
      LANGUAGE = "en"
      FIRST1K_URN = "urn:cts:greekLit:tlg9010.tlg001.1st1K-grc1"

      # SOL's letter spelling → the Adler letter (Adler's 24 + the
      # antistoichic diphthong sections αι ει οι).
      LETTERS = {
        "alpha" => "α", "beta" => "β", "gamma" => "γ", "delta" => "δ", "alphaiota" => "αι",
        "epsilon" => "ε", "zeta" => "ζ", "epsiloniota" => "ει", "eta" => "η", "theta" => "θ",
        "iota" => "ι", "kappa" => "κ", "lambda" => "λ", "mu" => "μ", "nu" => "ν", "xi" => "ξ",
        "omicron" => "ο", "omicroniota" => "οι", "pi" => "π", "rho" => "ρ", "sigma" => "σ",
        "tau" => "τ", "upsilon" => "υ", "phi" => "φ", "chi" => "χ", "psi" => "ψ", "omega" => "ω"
      }.freeze

      # The First1K Suda's own book.chapter labels (census of the held
      # edition, 2026-11-02); letters it lacks are absent.
      FIRST1K_CHAPTERS = {
        "alpha" => "1.A", "beta" => "1.B", "gamma" => "1.Γ", "delta" => "2.Δ", "alphaiota" => "2.Aι",
        "epsilon" => "2.E", "kappa" => "3.Κ", "lambda" => "3.Λ", "mu" => "3.Μ", "nu" => "3.Ν",
        "xi" => "3.Ξ", "omicron" => "3.Ο255", "omega" => "3.Ω", "pi" => "4.Π", "rho" => "4.Ρ",
        "sigma" => "4.Σ", "tau" => "4.Τ"
      }.freeze

      ENTRY_MEMBER = %r{\A#{ROOT}/([a-z]+)/(\d+)\z}
      INDEX_MEMBER = %r{\A#{ROOT}/[a-z]+\.html\z}

      def self.manifest = MANIFEST

      # A ManualDrop source has no fetch URL to drift against; the probe
      # HEADs the SOL site for liveness only.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "suda on line", zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      def self.drop_dir(workdir)
        File.expand_path(File.join("..", "..", "incoming", SLUG), workdir)
      end

      def self.manual_acquisition
        @manual_acquisition ||= ManualDrop::Spec.new(
          slug: SLUG,
          upstream_url: "supplied by the Suda On Line's maintainer by email (no bulk download exists; " \
                        "the site is #{MANIFEST.upstream_url})",
          steps: [
            "Obtain the SOL entry export (solEntries.zip) from the SOL's maintainers",
            "Save it as received — no re-zipping"
          ],
          files: [
            ManualDrop::FileSpec.new(
              name: ARCHIVE,
              description: "the SOL entry export: sol-entries/<letter>/<adler number> pages",
              required: true, sniff: ->(path) { zip_complaint(path) }
            )
          ],
          refresh_hint: "A fresher export drops the same way; the sha pin makes an identical " \
                        "re-drop a no-op."
        )
      end

      def self.zip_complaint(path)
        reader = open_zip(path)
        return nil if reader.entries.any? { |e| e.name.b.match?(ENTRY_MEMBER) }

        "no #{ROOT}/<letter>/<n> entry pages inside"
      rescue Nabu::ZipReader::Error => e
        "not a readable zip (#{e.message})"
      end

      # The archive through the belt's zip reader (the members are
      # UTF-8-checked through SourceRead.utf8_member at extraction).
      def self.open_zip(path) = SourceRead.zip_file(path)

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        result = Nabu::ManualDrop.sync!(
          spec: self.class.manual_acquisition, drop_dir: self.class.drop_dir(workdir),
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "already up to date (held manual ingest)" : nil)
      end

      # One ref per Adler letter present in the export, in sorted order.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        zip = File.join(workdir, ARCHIVE)
        return unless File.file?(zip)

        entry_members(zip).keys.sort.each do |letter|
          block.call(Nabu::DocumentRef.new(
                       source_id: SLUG, id: "urn:nabu:#{SLUG}:#{letter}",
                       path: File.expand_path(zip), metadata: { "letter" => letter }
                     ))
        end
      end

      # Index pages and non-letter directories (the misspelled
      # omicrioniota/) skip by rule; any other member is unrecognized.
      def discovery_skips(workdir)
        zip = File.join(workdir, ARCHIVE)
        return Nabu::Adapter::DiscoverySkips.new unless File.file?(zip)

        indexes = []
        off_letter = []
        stray = []
        reader_for(zip).entries.each do |entry|
          name = entry.name.b.dup.force_encoding(Encoding::UTF_8)
          next if name.end_with?("/")

          if name.match?(INDEX_MEMBER) then indexes << name
          elsif (m = ENTRY_MEMBER.match(name)) then off_letter << name unless LETTERS.key?(m[1])
          else stray << name
          end
        end
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: indexes.size + off_letter.size, unrecognized: stray.size,
          notes: off_letter.map { |n| "not an Adler letter directory (mis-keyed query page): #{n}" } +
                 stray.map { |n| "unrecognized export member: #{n}" }
        )
      end

      def parse(document_ref)
        letter = document_ref.metadata.fetch("letter")
        members = entry_members(document_ref.path).fetch(letter) do
          raise Nabu::ParseError, "#{document_ref.id}: letter vanished between discover and parse"
        end
        reader = reader_for(document_ref.path)
        skipped = []
        entries = members.sort_by(&:first).filter_map do |number, entry|
          html = SourceRead.utf8_member(reader, entry, label: document_ref.path)
          parsed = SolEntryParser.parse(html)
          unless parsed.letter == letter && parsed.number == number
            raise Nabu::ParseError, "#{entry.name}: page says #{parsed.letter},#{parsed.number}"
          end
          raise SolEntryParser::NoRecord, "empty translation" if parsed.translation.nil?

          parsed
        rescue SolEntryParser::NoRecord => e
          skipped << { "file" => entry.name.b.dup.force_encoding(Encoding::UTF_8), "reason" => e.message }
          nil
        end
        document = build_document(document_ref, letter, entries.size, skipped)
        entries.each { |e| document << build_passage(document_ref.id, letter, e) }
        document
      rescue Nabu::ZipReader::Error, Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.id}: #{e.message}"
      end

      private

      # {letter => [[n, ZipReader::Entry], …]} over the Adler-letter
      # entry members.
      def entry_members(zip)
        @entry_members ||= {}
        @entry_members[zip] ||= reader_for(zip).entries.each_with_object({}) do |entry, by_letter|
          m = ENTRY_MEMBER.match(entry.name.b.dup.force_encoding(Encoding::UTF_8)) or next
          next unless LETTERS.key?(m[1])

          (by_letter[m[1]] ||= []) << [Integer(m[2], 10), entry]
        end
      end

      def reader_for(zip)
        @readers ||= {}
        @readers[zip] ||= self.class.open_zip(zip)
      end

      def build_document(document_ref, letter, count, skipped)
        adler = LETTERS.fetch(letter)
        Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE,
          title: "Suda On Line: English translations, Adler #{adler}",
          canonical_path: document_ref.path,
          metadata: {
            "adler_letter" => adler, "sol_letter" => letter,
            "translated_from" => "grc", "translation_of" => FIRST1K_URN,
            "first1k_chapter" => FIRST1K_CHAPTERS[letter],
            "entry_count" => count, "skipped_entries" => (skipped unless skipped.empty?),
            "text_nature" => "modern English translation with notes (Suda On Line)"
          }.compact
        )
      end

      def build_passage(doc_urn, letter, entry)
        chapter = FIRST1K_CHAPTERS[letter]
        annotations = {
          "adler" => "#{LETTERS.fetch(letter)} #{entry.number}",
          "sol_key" => "#{letter},#{entry.number}",
          "first1k_candidate" => chapter && "#{chapter}.#{entry.number}",
          "headword" => entry.headword,
          "translated_headword" => entry.translated_headword,
          "greek_original" => entry.greek_original,
          "notes" => entry.notes,
          "references" => entry.references,
          "web_addresses" => entry.web_addresses,
          "keywords" => entry.keywords,
          "translator" => entry.translator,
          "translated_at" => entry.translated_at,
          "vetters" => entry.vetters,
          "vetting_status" => entry.vetting_status
        }.reject { |_, v| v.nil? || v == "" || v == [] }
        Nabu::Passage.new(
          urn: "#{doc_urn}:#{entry.number}", language: LANGUAGE,
          text: entry.translation, sequence: entry.number, annotations: annotations
        )
      end
    end
  end
end
