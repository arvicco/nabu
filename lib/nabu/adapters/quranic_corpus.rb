# frozen_string_literal: true

require_relative "quranic_corpus_parser"
require_relative "quranic_corpus_suras"
require_relative "source_read"

module Nabu
  module Adapters
    # The Quranic Arabic Corpus morphology, version 0.4 (Kais Dukes,
    # University of Leeds, 2011; corpus.quran.com): the whole Quran
    # segmented and annotated word by word — every word split into its
    # prefix, stem and suffix segments, each with its part-of-speech tag and
    # a feature string carrying lemma, root, verb form, aspect, mood, voice,
    # person/gender/number and case. The surface forms are the Tanzil
    # project's verified Uthmani text (version 1.0.2), written in extended
    # Buckwalter transliteration (ASCII). Language ara-Latn, lect ara:cla.
    #
    # == Upstream / grains (verified 2026-11-27)
    #
    # The corpus's own download (corpus.quran.com/download/) sits behind an
    # email form — not crossed. The file is carried verbatim, copyright
    # block intact, by the q-ran/quran Text-Fabric repository (sources/1.0/,
    # the source its own conversion reads); fetched raw at the pinned commit
    # 8abbbb2 (2019-03-14, the file's only commit there), byte-identical to
    # the master copy on 2026-11-27. ACCEPTED: quranic-corpus-morphology-
    # 0.4.txt — one ASCII TSV, 6,309,503 bytes, CRLF, a 57-line preamble
    # (the corpus's and Tanzil's copyright blocks + the LOCATION FORM TAG
    # FEATURES header) then 128,219 segment rows. Not fetched: the mirror's
    # other sources/1.0 files (the Tanzil uthmani / simple-min texts and
    # quran-data.xml metadata, two translations), its Text-Fabric tree, and
    # the corpus site's syntactic treebank. Anything beside the one file in
    # the workdir is counted unrecognized (#discovery_skips).
    #
    # == Grain: sura → document, verse → passage, segment → token
    #
    # The Quran's own citation units: one document per sura
    # (urn:nabu:quranic-corpus:<sura>, the sura number — the conventional
    # citation, unambiguous), one passage per verse cited by its number
    # (<doc-urn>:<verse>, so 2:255 is urn:nabu:quranic-corpus:2:255). The
    # passage text is upstream's FORM strings exactly as given: the
    # segments of a word concatenated, the words single-space joined, in
    # upstream's order — no transliteration to Arabic script, no cleanup
    # (the extended-Buckwalter Quranic marks such as "," and "[" stay; the
    # one form carrying a space, 37:130 "<ilo yaAsiyna", stays). The
    # segment is the token, because it is the corpus's own annotation unit:
    # 486 words hold two stems (2:3 mim~aA = min + maA), so no single
    # per-word lemma would be honest. Each token: "id" (sura:verse:word:
    # segment), "form" (may be "" — the 208 elided 1S suffix pronouns),
    # "tag", "features" (the whole feature string verbatim), and "lemma" /
    # "root" (the LEM: and ROOT: values verbatim, where upstream gives
    # them). Roots are written in Buckwalter letters, radicals unseparated
    # (rHm, Alh, $r*m) — 1,602 triliteral, 40 quadriliteral.
    #
    # Titles and the Meccan/Medinan label come from the Tanzil metadata
    # (QuranicCorpusSuras, cc-by), which also gives each sura's verse
    # count: a sura whose verses do not run 1..N is a ParseError.
    #
    # == Reconciliation (whole-file census, 2026-11-27)
    #
    # 114 suras, 6,236 verses (every sura contiguous from 1, equal to the
    # Tanzil count), 77,429 words, 128,219 segments (28,670 PREFIX, 77,915
    # STEM, 21,634 SUFFIX), 4,832 distinct LEM values, 1,642 distinct ROOT
    # values, 45 TAG values. The first sync must land exactly 114 documents
    # / 6,236 passages / 128,219 tokens, 0 skipped, 0 unrecognized.
    #
    # == License (the file's own header, verbatim)
    #
    # "Quranic Arabic Corpus (morphology, version 0.4) / Copyright (C) 2011
    # Kais Dukes / License: GNU General Public License … TERMS OF USE: -
    # Permission is granted to copy and distribute verbatim copies of this
    # file, but CHANGING IT IS NOT ALLOWED. - This annotation can be used in
    # any website or application, provided its source (the Quranic Arabic
    # Corpus) is clearly indicated, and a link is made to
    # http://corpus.quran.com to enable users to keep track of changes. -
    # This copyright notice shall be included in all verbatim copies of the
    # text, and shall be reproduced appropriately in all works derived from
    # or containing substantial portion of this file." The second block
    # covers the text the forms render: "Tanzil Quran Text (Uthmani,
    # version 1.0.2) / Copyright (C) 2008-2009 Tanzil.info / License:
    # Creative Commons BY-ND 3.0 Unported", with the same verbatim-only,
    # no-change, credit-and-link terms (link http://tanzil.info).
    #
    # Class research_private: the GPL label sits beside an explicit
    # no-change clause, and the underlying text is BY-ND; the stricter
    # reading governs, and the house classes no-derivatives material
    # research_private (the freising / tipitaka-lk precedent) — local
    # research use, never redistributed, never a dataset input. The stored
    # file is the fetched bytes, notice intact; the credit names the corpus
    # and Tanzil with their links.
    #
    # == fetch
    #
    # One FileFetch of the file at the pinned commit, sha256-verified
    # against FILE_SHA256 BEFORE the tree mutates (the med-headwords
    # choreography); a different file is refused loudly. Nothing is
    # materialized beside it. sync_policy manual.
    class QuranicCorpus < Nabu::Adapter
      FILENAME = "quranic-corpus-morphology-0.4.txt"
      COMMIT_SHA = "8abbbb2942f4479a8f314c04192d0c6f575ead15"
      FILE_URL = "https://raw.githubusercontent.com/q-ran/quran/#{COMMIT_SHA}/sources/1.0/#{FILENAME}".freeze
      FILE_SHA256 = "a1d12923815341face765083805d2148ed2d9f5cc3f7d6665219d887675d8c46"

      LANGUAGE = "ara-Latn"
      URN_PREFIX = "urn:nabu:quranic-corpus:"
      WORK = "Quran"

      # The data shapes the corpus and its mirror serve (the morphology
      # TSV, the Tanzil XML texts and metadata, zips) — what the discovery
      # census accounts for.
      CONTENT_PATTERN = /\.(?:txt|tsv|csv|xml|json|zip)\z/i

      MANIFEST = Nabu::SourceManifest.new(
        id: "quranic-corpus",
        name: "Quranic Arabic Corpus — morphology, version 0.4 (Kais Dukes, University of Leeds)",
        license: "The file's own terms, verbatim: \"Quranic Arabic Corpus (morphology, version 0.4) " \
                 "Copyright (C) 2011 Kais Dukes. License: GNU General Public License … Permission is " \
                 "granted to copy and distribute verbatim copies of this file, but CHANGING IT IS NOT " \
                 "ALLOWED. This annotation can be used in any website or application, provided its " \
                 "source (the Quranic Arabic Corpus) is clearly indicated, and a link is made to " \
                 "http://corpus.quran.com …\"; the word forms render the Tanzil Quran Text (Uthmani, " \
                 "version 1.0.2), \"Copyright (C) 2008-2009 Tanzil.info. License: Creative Commons " \
                 "BY-ND 3.0 Unported\", on the same verbatim-only terms. No-change → research_private: " \
                 "local research use only, never redistributed",
        license_class: "research_private",
        upstream_url: "http://corpus.quran.com",
        parser_family: "quranic-corpus-tsv",
        credit: "Quranic Arabic Corpus, morphology version 0.4, Kais Dukes (University of Leeds), " \
                "http://corpus.quran.com — on the Tanzil Quran Text (Uthmani 1.0.2), Tanzil.info, " \
                "http://tanzil.info"
      )

      def self.manifest = MANIFEST

      # The probe HEADs the pinned blob: reachability + drift vs the
      # .file-fetch.json pin.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: FILE_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # +sha256+ exists for the WebMock'd fetch tests — real syncs keep the
      # frozen pin.
      def initialize(sha256: FILE_SHA256)
        super()
        @sha256 = sha256
      end

      # One DocumentRef per sura, in sura order. The file is in location
      # order, so each sura is one contiguous line range; the range rides
      # the ref metadata so parse reads only its sura.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, FILENAME)
        return unless File.file?(path)

        sura_ranges(path).sort.each { |sura, (first, count)| yield sura_ref(path, sura, first, count) }
      end

      # Every content-shaped tree file (CONTENT_PATTERN) other than the
      # morphology file is unrecognized; fetch bookkeeping (state file,
      # attic) is not content.
      def discovery_skips(workdir)
        return DiscoverySkips.new unless File.directory?(workdir)

        strays = Dir.glob("**/*", File::FNM_DOTMATCH, base: workdir)
                    .select { |rel| File.file?(File.join(workdir, rel)) && CONTENT_PATTERN.match?(rel) }
                    .reject { |rel| bookkeeping?(rel) }.sort
        DiscoverySkips.new(unrecognized: strays.size,
                           notes: strays.map { |rel| "unexpected file beside the morphology file: #{rel}" })
      end

      def parse(document_ref)
        meta = document_ref.metadata
        sura = meta.fetch("sura")
        label = "quranic-corpus #{document_ref.id}"
        segments = sura_lines(document_ref.path, meta.fetch("first_line"), meta.fetch("lines"), label)
                   .map { |line| parser.segment(line, label: label) }
        stray = segments.find { |s| s.sura != sura }
        raise Nabu::ParseError, "#{label}: line range holds sura #{stray.sura}" if stray

        verses = segments.chunk_while { |a, b| a.verse == b.verse }.to_a
        check_verses!(sura, verses.map { |v| v.first.verse }, label)
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: meta.fetch("title"), metadata: document_metadata(sura))
        verses.each { |verse_segments| document << passage(document_ref.id, verse_segments, document.size) }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{label}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        fetch = FileFetch.new(url: FILE_URL, dir: workdir, filename: FILENAME,
                              attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        fetch.prepare!
        verify_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: attic_notes(fetch.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "quranic-corpus fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        @parser ||= QuranicCorpusParser.new
      end

      def passage(doc_urn, segments, sequence)
        Nabu::Passage.new(
          urn: "#{doc_urn}:#{segments.first.verse}", language: LANGUAGE,
          text: Normalize.nfc(parser.verse_text(segments)), sequence: sequence,
          annotations: { "tokens" => segments.map(&:token) }
        )
      end

      def document_metadata(sura)
        _verses, name, english, type = QuranicCorpusSuras::TABLE.fetch(sura)
        { "sura" => sura, "work" => WORK, "sura_name" => name, "sura_name_en" => english,
          "revelation_type" => type }
      end

      # The verses of +sura+ must run 1..N, N its Tanzil verse count.
      def check_verses!(sura, numbers, label)
        expected = QuranicCorpusSuras::TABLE.fetch(sura).first
        return if numbers == (1..expected).to_a

        raise Nabu::ParseError,
              "#{label}: sura #{sura}: verses #{numbers.first}..#{numbers.last}, expected 1..#{expected}"
      end

      def sura_ref(path, sura, first_line, lines)
        _verses, name, english, = QuranicCorpusSuras::TABLE.fetch(sura) do
          raise Nabu::ParseError, "quranic-corpus #{path}: sura #{sura} is not one of the 114"
        end
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{URN_PREFIX}#{sura}", path: File.expand_path(path),
          metadata: { "sura" => sura, "title" => "Sura #{sura} — #{name} (#{english})",
                      "first_line" => first_line, "lines" => lines }
        )
      end

      # {sura => [first line number (1-based), row count]}, the preamble
      # checked first. A sura that reappears after another is a ParseError
      # (the line-range plan relies on location order).
      def sura_ranges(path)
        ranges = {}
        preamble = []
        current = nil
        SourceRead.utf8_lines(path, label: "quranic-corpus").each_with_index do |line, index|
          next preamble << line unless parser.row?(line)

          parser.check_preamble!(preamble, label: path) if current.nil?
          sura = parser.sura_of(line, label: path)
          if sura != current
            raise Nabu::ParseError, "quranic-corpus #{path}: sura #{sura} is not contiguous" if ranges.key?(sura)
            raise Nabu::ParseError, "quranic-corpus #{path}: sura #{sura} follows sura #{current}" if current&.> sura

            ranges[sura] = [index + 1, 0]
            current = sura
          end
          ranges[sura][1] += 1
        end
        ranges
      end

      # The +count+ lines from line number +first+ (1-based) — streamed,
      # stopping once the sura's range is read.
      def sura_lines(path, first, count, label)
        lines = []
        SourceRead.utf8_lines(path, label: label).each_with_index do |line, index|
          break if lines.size == count

          lines << line if index + 1 >= first
        end
        raise Nabu::ParseError, "#{label}: lines #{first}+#{count} reach past the end of #{path}" if lines.size < count

        lines
      end

      def bookkeeping?(rel)
        [FILENAME, Nabu::FileFetch::STATE_FILE].include?(rel) || rel.split("/").first == ATTIC_DIRNAME
      end

      # A 304 repeats the stored pin (nothing touched); any fetched body
      # must be the pinned file.
      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @sha256

        raise Nabu::FetchError,
              "quranic-corpus: #{FILENAME} drifted — fetched sha256 #{fetch.sha} != pinned #{@sha256}; " \
              "the URL names commit #{COMMIT_SHA[0, 7]}, so review upstream before any re-pin"
      end
    end
  end
end
