# frozen_string_literal: true

require "nokogiri"
require_relative "epidoc_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # formulae-open — the public-domain charter editions of the Formulae –
    # Litterae – Chartae project (Akademie der Wissenschaften in Hamburg /
    # Universität Hamburg; github.com/Formulae-Litterae-Chartae/formulae-open,
    # Zenodo DOI 10.5281/zenodo.10082515): older printed editions of early
    # medieval charters, OCR hand-corrected and encoded one charter per TEI
    # file for the project's Werkstatt. README verbatim: "the texts used in
    # the Formulae - Litterae - Chartae Werkstatt … that are in the public
    # domain. This includes older editions of early medieval charters as
    # well as the E-Lexicon entries."
    #
    # == Layout and the parser family (composition probed, 2026-11-08)
    #
    # CapiTainS v3: every textgroup and work directory carries a
    # __capitains__.xml catalog (NOT Perseus' v2 __cts__.xml), and the tree
    # is two OR three levels deep — data/<collection>/<work>/<file> for most,
    # data/<collection>/<sub-collection>/<work>/<file> for the Marmoutier and
    # Anjou cartularies (594 work directories). Filenames are
    # <collection>.<work>.<lang><nnn>.xml; urns urn:cts:formulae:<same>. The
    # Perseus repo walker therefore does not compose (fixed depth, v2
    # catalogs, perseus-<lang> slugs), but its parser family does: every
    # charter declares one CTS cRefPattern n="charta" and cites its text by
    # div[@type="textpart"][@subtype="charta"][@n] inside
    # div[@type="edition"], which is exactly what EpidocParser reads. A
    # charter is one passage (5,118 of 5,207 files); a dossier copied as
    # several pieces carries 2–7 charta divs (89 files), each its own passage.
    # The <head> inside a charta div is the cartulary's own rubric
    # ("COMMUTATIO INTER UUALDONEM EPISCOPUM …") and stays in the text.
    #
    # == Grains (census at 2ce73416, 2023-11-08 — HEAD on 2026-11-08)
    #
    # The document = ONE LATIN EDITION FILE (`lat<nnn>`). Every edition of a
    # work is taken: lat002–lat004 (37 files) are the printed edition's own
    # a/b/c pieces ("Nr. 1019a" / "Nr. 1019b"), distinct charters, never
    # revisions. Skipped by rule, each counted in #discovery_skips:
    #
    # - the E-Lexicon (data/elexicon, 259 German entry files, 289 catalog
    #   editions — 30 alias entries point at another entry's file): the
    #   project's dictionary of charter vocabulary, a modern German
    #   reference work, not a charter. Rejected by textgroup, whatever its
    #   licence (every entry is CC BY 4.0);
    # - (the 6 luzern charters, Schiess 1933, carried no per-file grant —
    #   only upstream's "to be filled in" placeholder — and skipped until
    #   ruled 2026-11-12: they now admit under the whole deposit's CC BY,
    #   DEPOSIT_LICENCES below; any other unlicensed file still skips —
    #   no grant is no grant, the pta law);
    # - regest-only records (37: langobardisch_1 12, hersfeld 11,
    #   marmoutier_manceau 9, freising 2, three singletons): the printed
    #   edition gives only a summary (a lost charter, or a register note —
    #   "Aus dem liber censualium in Wolfenbüttel."), so the charta div is
    #   empty and there is no Latin text to serve. DECLARED: their regest,
    #   dating and issuing place are not ingested — a document needs a
    #   passage; a regest layer is a future look.
    #
    # A file that is neither a recognizable edition file nor a catalog is
    # counted unrecognized (none upstream).
    #
    # Reconciliation against upstream's own index (the readable editions the
    # __capitains__.xml catalogs list, 5,496): 5,207 Latin edition files +
    # 289 E-Lexicon catalog editions (259 files) = 5,496. Through the
    # adapter over the 2ce73416 clone (2026-11-08; luzern ruling applied
    # 2026-11-12): 5,170 accepted (5,164 per-file-licensed + the 6
    # deposit-licensed luzern) + 37 regest-only + 259 E-Lexicon
    # files = the 5,466 TEI files under data/, residue 0.
    #
    # == The licence law (per document)
    #
    # The licence varies per file: each TEI's publicationStmt <licence
    # @target> is read and classed (LICENCE_CLASSES) — never a collection
    # list. Census over the 5,207 Latin files: CC BY 4.0 5,096 (→ the
    # source class, attribution; 5,059 accepted); CC BY-NC-ND 4.0 105 (the
    # eudes 34 and marmoutier_pour_le_perche 71 collections, all accepted →
    # license_override "nc", the house class for NC-ND, kept by the same
    # ruling — the project's own per-file choice, not a digitizer's
    # pretension); none 6 (luzern, deposit-licensed above). An UNKNOWN target stops discovery loudly
    # (Nabu::FetchError): a new grant is classed deliberately, never guessed.
    #
    # == Dedupe (checked 2026-11-08)
    #
    # openmgh holds 13 MGH Diplomata volumes but NOT DD Karol. 1 (Mühlbacher
    # 1906): formulae-open's karl_der_grosse (266 Charlemagne diplomas),
    # karlmann_mgh (12) and ludwig_der_juengere (28) are new to the library,
    # as is every charter collection here (no other held source is a
    # charter corpus but bfm's Old French charters, corpus-gysseling's
    # Middle Dutch ones and the UD LLCT2 Lucca treebank — none of these
    # editions). If openmgh ever adds DD Karol. 1 the two must dedupe by
    # Mühlbacher number. langobardisch_1 (Schiaparelli, CDL 1929) would
    # overlap a Zenodo CDL TEI deposit that is not held.
    #
    # == The text policy
    #
    # Freising's Bitterauf edition abbreviates a repeated formula by
    # cross-reference ("Unde —possideat aevis temporibus (= 748)"); the
    # project encodes that as <choice><abbr> (the printed text) beside an
    # <expan> it supplied from the referenced charter (293 choices). The
    # printed edition is the canonical text, so <expan> contributes nothing
    # (EpidocParser apparatus:) — the supplied formula would otherwise
    # count twice across the corpus. Every other inline element (<w>, the
    # <seg function="Invocatio|Publicatio|…"> diplomatic-formula spans on
    # 2,327 files, tables) flattens to its text. DECLARED: the <seg
    # function> formula layer is not mined in this pass — a passage
    # annotation lane for it is future work, the text is unchanged by it.
    #
    # == The axes (the aggressive-mining policy)
    #
    # - date: the edition's dateline (<front><dateline>), its <date> children
    #   typed by the project (when / notBefore+notAfter); the envelope over
    #   every dated child → metadata "date" {not_before, not_after, raw}
    #   (MetadataDates :structured, class-less: the charter's own date), raw
    #   = the printed dating words ("[880-899]", "Vor 1084", "Sans date"):
    #   4,983 of the 5,164 accepted charters. An open notBefore-only date
    #   or an empty <date/> mints no bound (181); the print year then
    #   projects as the edition-class fallback.
    # - place: the edition's issuing place (front div subtype
    #   "ausstellungsort", 1,984 accepted charters, verbatim: "Cannstadt")
    #   → "place".
    #   The imprint's pubPlace is the PRINTER's city and is not recorded;
    #   nor is the textgroup catalog's dc:coverage ("St. Gallen", "Anjou"),
    #   the ARCHIVE's region — a collection label the "collection" id
    #   already carries, never a charter's origin (DECLARED coarseness).
    # - kind: the TEI's own <text type="charta"> → "genre" (kind_map folds).
    # - regest: the edition's (German/French) summary, verbatim.
    # - lineage: the collection (textgroup id + its catalog title), the
    #   printed edition (monogr title, editors, imprint year as
    #   "source_date", the d-nb/BnF URI), the CTS ids.
    class FormulaeOpen < Nabu::Adapter
      NAMESPACE = "formulae"
      LANGUAGE = "lat"

      MANIFEST = Nabu::SourceManifest.new(
        id: "formulae-open",
        name: "Formulae – Litterae – Chartae: formulae-open (early medieval charters)",
        license: "Per-document Creative Commons licence, each file's own teiHeader <licence> " \
                 "(\"Distributed under a Creative Commons Attribution 4.0 International License.\"; " \
                 "Zenodo record 10.5281/zenodo.10082515 cc-by-4.0): CC BY 4.0 → attribution; " \
                 "CC BY-NC-ND 4.0 (eudes, marmoutier_pour_le_perche) → license_override nc; " \
                 "files without a licence are never ingested. Cite Formulae – Litterae – Chartae " \
                 "(Akademie der Wissenschaften in Hamburg / Universität Hamburg) and each printed edition",
        license_class: "attribution",
        upstream_url: "https://github.com/Formulae-Litterae-Chartae/formulae-open",
        parser_family: "epidoc"
      )

      # Every licence target upstream ships (census above) → its class.
      LICENCE_CLASSES = {
        "https://creativecommons.org/licenses/by/4.0/" => "attribution",
        "https://creativecommons.org/licenses/by-nc-nd/4.0/" => "nc"
      }.freeze

      # Textgroups whose files carry NO per-file grant but whose WHOLE
      # Zenodo deposit is licensed: the luzern six (Schiess 1933) sit in
      # the deposit recorded cc-by-4.0 (10.5281/zenodo.10082515) while
      # their <availability> holds upstream's "to be filled in when a
      # decision is made by the team" placeholder. Ruled 2026-11-12: the
      # deposit is upstream's own grant over the entire set, so these
      # admit under the deposit licence with the basis declared — any
      # OTHER unlicensed file still skips (no grant is no grant).
      DEPOSIT_LICENCES = {
        "luzern" => "https://creativecommons.org/licenses/by/4.0/"
      }.freeze
      DEPOSIT_BASIS = "deposit licence (Zenodo 10.5281/zenodo.10082515; per-file availability " \
                      "is an upstream placeholder)"

      # Textgroups rejected as a whole grain, with the note's label.
      REJECTED_TEXTGROUPS = {
        "elexicon" => "E-Lexicon entr%s (elexicon — the project's German dictionary of charter " \
                      "vocabulary, not a charter)"
      }.freeze

      # The printed abbreviation stays; the project's supplied expansion
      # leaves (the text policy above).
      APPARATUS = %w[expan].freeze

      EDITION_FILE = /\A(?<textgroup>[^.]+)\.(?<work>[^.]+)\.(?<edition>(?<lang>[a-z]{3})\d{3})\.xml\z/
      CATALOG = "__capitains__.xml"
      private_constant :EDITION_FILE, :CATALOG

      Candidate = Data.define(:textgroup, :work, :edition, :language, :path) do
        def name = "#{textgroup}.#{work}.#{edition}"
      end
      private_constant :Candidate

      def self.manifest
        MANIFEST
      end

      def manifest
        MANIFEST
      end

      # Clone/update the repo through the shared non-destructive git path
      # (Nabu::GitFetch: fetch objects → breaker → attic → ff-merge).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: manifest.upstream_url, workdir: workdir, progress: progress, force: force)
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        census(workdir)[:accepted].map { |candidate| document_ref(candidate) }.sort_by(&:id).each(&block)
      end

      def parse(document_ref)
        document = EpidocParser.new.parse(
          document_ref.path, urn: document_ref.id, language: LANGUAGE,
                             title: document_ref.metadata["title"], apparatus: APPARATUS
        )
        copy = Nabu::Document.new(urn: document.urn, language: document.language, title: document.title,
                                  canonical_path: document.canonical_path,
                                  metadata: charter_metadata(document_ref),
                                  license_override: document_ref.metadata["license_override"])
        document.passages.each { |passage| copy << passage }
        copy
      end

      def discovery_skips(workdir)
        result = census(workdir)
        notes = result[:skipped].sort.map do |reason, names|
          "#{names.size} #{skip_label(reason, names.size)}: #{names.sort.first(5).join(', ')}" \
            "#{', …' if names.size > 5}"
        end
        unless result[:unrecognized].empty?
          notes << "#{result[:unrecognized].size} unrecognized file(s) under data/: " \
                   "#{result[:unrecognized].sort.first(5).join(', ')}"
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: result[:skipped].values.sum(&:size),
                                          unrecognized: result[:unrecognized].size, notes: notes)
      end

      private

      def skip_label(reason, count)
        case reason
        when :unlicensed then "unlicensed file#{'s' unless count == 1} (no <licence> in the header)"
        when :language then "non-Latin edition file#{'s' unless count == 1}"
        when :textless
          "regest-only record#{'s' unless count == 1} (the edition prints a summary, no Latin text: " \
          "empty charta div)"
        else format(REJECTED_TEXTGROUPS.fetch(reason.to_s), count == 1 ? "y" : "ies")
        end
      end

      def census(workdir)
        @census ||= {}
        @census[workdir] ||= classify(workdir)
      end

      def classify(workdir)
        result = { accepted: [], skipped: Hash.new { |hash, key| hash[key] = [] }, unrecognized: [] }
        Dir.glob(File.join(workdir, "data", "**", "*.xml")).each do |path|
          next if File.basename(path) == CATALOG

          candidate = candidate_for(workdir, path)
          next result[:unrecognized] << relative(workdir, path) unless candidate

          reason = skip_reason(candidate)
          reason ? result[:skipped][reason] << candidate.name : result[:accepted] << candidate
        end
        result
      end

      # Ordered: the rejected grain first (whatever its licence), then the
      # language, then no grant at all, then the regest-only record.
      def skip_reason(candidate)
        return candidate.textgroup.to_sym if REJECTED_TEXTGROUPS.key?(candidate.textgroup)
        return :language unless candidate.language == LANGUAGE
        return :unlicensed if licence_target(candidate.path).nil? && !DEPOSIT_LICENCES.key?(candidate.textgroup)
        return :textless if peek(candidate.path).textless

        nil
      end

      def candidate_for(workdir, path)
        match = EDITION_FILE.match(Nabu::Normalize.nfc(File.basename(path))) or return nil
        collection = relative(workdir, path).split("/")[1]
        return nil unless collection && Nabu::Normalize.nfc(collection) == match[:textgroup]

        Candidate.new(textgroup: match[:textgroup], work: match[:work], edition: match[:edition],
                      language: match[:lang], path: File.expand_path(path))
      end

      def relative(workdir, path)
        Nabu::Normalize.nfc(path.delete_prefix(File.join(workdir, "")))
      end

      def document_ref(candidate)
        licence = licence_target(candidate.path)
        deposit = licence.nil? && DEPOSIT_LICENCES[candidate.textgroup]
        licence = deposit if deposit
        klass = LICENCE_CLASSES[licence]
        unless klass
          raise Nabu::FetchError, "#{candidate.path}: unrecognized licence #{licence.inspect} — class it in " \
                                  "FormulaeOpen::LICENCE_CLASSES before ingesting"
        end
        Nabu::DocumentRef.new(
          source_id: manifest.id,
          id: "urn:cts:#{NAMESPACE}:#{candidate.name}",
          path: candidate.path,
          metadata: {
            "title" => read_header(candidate.path)[:title] || candidate.name,
            "language" => LANGUAGE,
            "license" => licence,
            "license_basis" => (DEPOSIT_BASIS if deposit),
            "license_override" => (klass unless klass == manifest.license_class),
            "collection" => candidate.textgroup,
            "cts_textgroup" => candidate.textgroup,
            "cts_work" => "#{candidate.textgroup}.#{candidate.work}"
          }.compact
        )
      end

      # One cheap read per path, cached for the grain rules and the ref:
      # the publicationStmt <licence @target>, and whether the body carries
      # any text at all.
      Peek = Data.define(:licence, :textless)
      private_constant :Peek

      def peek(path)
        @peeks ||= {}
        @peeks[path] ||= begin
          text = SourceRead.utf8_file(path, label: "formulae-open edition")
          cut = text.index(BODY_START)
          head = cut ? text[0, cut] : text
          body = cut ? text[cut..] : ""
          Peek.new(licence: head[/<licence\b[^>]*\btarget="([^"]+)"/, 1],
                   textless: body.gsub(/<[^>]*>/, "").strip.empty?)
        end
      end

      def licence_target(path)
        peek(path).licence
      end

      # == Header + front reading
      #
      # Everything before <body> — the teiHeader and the <front> (regest,
      # issuing place, dateline). Files are small (largest 261 KB); the
      # slice is DOM-parsed on demand and never cached (5,164 documents).
      BODY_START = /<body[\s>]/
      private_constant :BODY_START

      def header_text(path)
        text = SourceRead.utf8_file(path, label: "formulae-open edition")
        cut = text.index(BODY_START)
        cut ? text[0, cut] : text
      end

      def read_header(path)
        doc = Nokogiri::XML(header_text(path))
        doc.remove_namespaces!
        monogr = doc.at_xpath("//sourceDesc//monogr")
        {
          title: clean(doc.at_xpath("//fileDesc/titleStmt/title")&.text),
          regest: clean(doc.at_xpath("//front/div[@subtype='regest']")&.text),
          place: clean(doc.at_xpath("//front/div[@subtype='ausstellungsort']")&.text),
          date: dateline_date(doc.at_xpath("//front/dateline")),
          genre: clean(doc.at_xpath("//text/@type")&.value),
          edition: monogr && clean((monogr.at_xpath("title[@type='main']") || monogr.at_xpath("title"))&.text),
          editors: monogr ? monogr.xpath("editor").filter_map { |node| clean(node.text) }.uniq : [],
          source_date: monogr && clean(monogr.at_xpath("imprint/date")&.text),
          source_uri: monogr && clean(monogr.at_xpath("idno[@type='URI']")&.text)
        }
      end

      def charter_metadata(document_ref)
        head = read_header(document_ref.path)
        base = document_ref.metadata.slice("license", "collection", "cts_textgroup", "cts_work")
        base.merge(
          "work" => head[:title],
          "collection_title" => collection_title(document_ref.path, document_ref.metadata["collection"]),
          "regest" => head[:regest],
          "date" => head[:date],
          "place" => head[:place],
          "genre" => head[:genre],
          "edition" => head[:edition],
          "editors" => (head[:editors] unless head[:editors].empty?),
          "source_date" => head[:source_date],
          "source_uri" => head[:source_uri]
        ).compact
      end

      # The envelope over every <date> child carrying a year: when, or the
      # notBefore/notAfter pair. An open single bound mints nothing (no
      # guessed other side); no bounded child → nil.
      YEAR = /\A(-?\d{1,4})(?:-\d{2}(?:-\d{2})?)?\z/
      private_constant :YEAR

      def dateline_date(dateline)
        return nil unless dateline

        spans = dateline.xpath("date").filter_map do |date|
          if (when_year = year(date["when"]))
            [when_year, when_year]
          else
            from = year(date["notBefore"])
            to = year(date["notAfter"])
            [from, to] if from && to
          end
        end
        return nil if spans.empty?

        raw = clean(dateline.text)
        { "not_before" => spans.map(&:first).min, "not_after" => spans.map(&:last).max, "raw" => raw }.compact
      end

      def year(value)
        match = YEAR.match(value.to_s.strip) or return nil

        Integer(match[1], 10)
      end

      # The textgroup catalog's dc:title (data/<collection>/__capitains__.xml).
      DC = { "dc" => "http://purl.org/dc/elements/1.1/", "cpt" => "http://purl.org/capitains/ns/1.0#" }.freeze
      private_constant :DC

      def collection_title(path, collection)
        dir = File.dirname(path)
        dir = File.dirname(dir) until File.basename(File.dirname(dir)) == "data" || dir == File.dirname(dir)
        @collection_titles ||= {}
        return @collection_titles[collection] if @collection_titles.key?(collection)

        catalog = File.join(dir, CATALOG)
        @collection_titles[collection] =
          if File.file?(catalog)
            doc = Nokogiri::XML(SourceRead.utf8_file(catalog, label: "formulae-open catalog"))
            clean(doc.at_xpath("/cpt:collection/dc:title", DC)&.text)
          end
      end

      def clean(text)
        return nil if text.nil?

        value = Nabu::Normalize.nfc(text.gsub(/[[:space:]]+/, " ").strip)
        value.empty? ? nil : value
      end
    end
  end
end
