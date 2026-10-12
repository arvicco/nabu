# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"

require_relative "slavic_wikisource"
require_relative "../normalize"

module Nabu
  module Adapters
    # ban-wikisource — the Balinese Wikisource lontar corpus
    # (ban.wikisource.org): palm-leaf manuscripts transcribed leaf by leaf
    # in Balinese script on ProofreadPage, MANUSCRIPT-DIRECT — the
    # Page-namespace text is keyed from the photographed leaf itself (no
    # printed edition stands between manuscript and transcription), so the
    # house wikisource edition-taint concern is satisfied by construction
    # for every Index this adapter admits.
    #
    # == Provenance (pre-check, 2026-10-12)
    #
    # The bulk of the transcriptions arrived by import: "Palmleaf Bot"
    # (global account, operator Lautgesetz; bot task "Creation of Index
    # pages corresponding to Balinese lontar files on commons … in
    # connection with project grant") wrote them on Multilingual Wikisource
    # with the edit summary "update content from Palmleaf.org" (57,528
    # edits there), and they reached ban.wikisource in July 2021 by
    # Special:Import ("Importing from mulws"). palmleaf.org is the PanLex /
    # Internet Archive transcription wiki the Wikimedia project grant
    # "PanLex/Balinese palm-leaf transcription platform on Wikisource"
    # (status selected; goal G1 "Wikisource will contain existing Balinese
    # content from palmleaf.org") moved onto Wikisource. palmleaf.org's
    # own terms are the SAME licence: its rightsinfo reads "Creative
    # Commons Attribution-ShareAlike" and its footer "User contributions
    # are available under Creative Commons Attribution-ShareAlike unless
    # otherwise noted" (linking CC BY-SA 4.0). No conflicting upstream
    # terms → the site licence governs: ban.wikisource rightsinfo
    # "Creative Commons Attribution-Share Alike 4.0"
    # (https://creativecommons.org/licenses/by-sa/4.0/deed.ban). The leaf
    # photographs are Internet Archive's Balinese Digital Library scans on
    # Commons ({{IA|…}} sources, {{PD-IDNoCopyright}}) plus local
    # campaign photographs ({{self|cc-by-sa-4.0}}) — mined per document.
    #
    # == Shape (the house wikisource kit, ProofreadPage-shaped)
    #
    # Built on the SlavicWikisource base for its fetch machinery — the
    # revid-pinned api.php GETs, the URL_BYTE_CAP/CONTINUE_RESERVE batch
    # slicing, the continuation-merged revisions|categories payload, the
    # envelope/stray census. The rendered-HTML family is NOT needed: the
    # Page-namespace wikitext IS the transcription (no transclusion to
    # resolve). Document = one Index (one manuscript scan); passage = one
    # Page-namespace page, its manuscript lines kept as "\n"-joined lines,
    # leaf markers ("[᭕᭖ 56B]", "[depan]") lifted into the "leaves"
    # annotation, the ProofreadPage quality level (0–4) recorded per page —
    # the proofread/validated ratchet is metadata, never a filter.
    #
    # == Fetch (one envelope per transcribed Index: pages/<index pageid>.json)
    #
    # 1. Page-namespace listing (generator=allpages + prop=info: title,
    #    pageid, lastrevid) grouped by Index name;
    # 2. the Index pages that own Page-namespace pages (revisions|
    #    categories); untranscribed Indexes are counted, never enveloped;
    # 3. every main-namespace work page (the <pages index=…> transclusions
    #    carry the cone classification: Lontar Basa Kawi, the Gedong Kirtya
    #    classes, the holding collections);
    # 4. Page-namespace wikitext for ADMITTED Indexes only — delta against
    #    the held envelope's revids (an unchanged page costs nothing);
    # 5. the Commons File page of each admitted scan (IA identifier,
    #    licence templates, Commons categories).
    # NON-DESTRUCTIVE: a page that vanishes upstream stays in its envelope.
    #
    # == The rules (discovery_skips names and counts each)
    #
    # - redirect: the Index is a redirect (renamed scans);
    # - printed edition, year-bearing (EXCLUSION RULE, written): an Index
    #   OUTSIDE the censused manuscript-scan families whose Year= names a
    #   year — printed books and modern studies (1918–2013 at census:
    #   Balai Bahasa / Departemen Pendidikan dan Kebudayaan geguritan
    #   editions with their analyses, the 1994 Sutasoma alih aksara,
    #   dictionaries, modern fiction and poetry); the same rule catches any
    #   Year= before CAMPAIGN_FLOOR on a family Index (none at census —
    #   the family Indexes' Year= is the 2017–2021 photography campaign);
    # - printed edition, undated: an Index outside the families with no
    #   Year= (2 at census: repository-sourced Balai Bahasa printings);
    # - no text: an admitted Index whose pages carry no transcription.
    class BanWikisource < SlavicWikisource
      API_URL = "https://ban.wikisource.org/w/api.php"
      COMMONS_API_URL = "https://commons.wikimedia.org/w/api.php"
      STATE_FILE = ".ban-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:ban-wikisource:"

      PAGE_NS = 250
      INDEX_NS = 252
      MAIN_NS = 0
      LIST_LIMIT = "500"

      # The censused manuscript-scan families (2026-10-12), by Index file
      # name: the Internet Archive Balinese Digital Library + village
      # collection scans ("Bali-lontar-…", 1,255 transcribed), the Tojan
      # campaign photographs, Wikisource Loves Manuscripts (WM ID …), the
      # UNHI campaign (WS UNHI …), and Leiden University Libraries'
      # Oriental manuscripts ("… Or. NNNN").
      MANUSCRIPT_FAMILIES = [
        /\ABali-lontar-/i, /\ALontar Tojan - /, /\AWM ID /, /\AWikisource Loves Manuscripts /,
        /\AWS UNHI /, /\bOr\. ?\d/, /\(UNHI\)\z/
      ].freeze
      # Family Indexes state the photography/upload campaign year in Year=
      # (2017–2021 at census); a Year= before this floor is a print date.
      CAMPAIGN_FLOOR = 2017

      REDIRECT = /\A\s*#\s*(?:redirect|alih)\b/i
      YEAR = /(?<!\d)(1[5-9]\d\d|20\d\d)(?!\d)/

      # Index Language= values (case-insensitive) → the base code. The
      # census: ban-bali 601 · ban 715 · ban-Bali 30 over the transcribed
      # Indexes. Anything else quarantines LOUDLY at parse.
      INDEX_LANGUAGES = { "ban" => "ban", "ban-bali" => "ban" }.freeze

      # The work-category language claims (main-namespace categories on the
      # pages that transclude an Index) — they refine the Index's blanket
      # Language=ban: the Kawi lontars. A work set claiming two languages
      # (Basa Bali + Basa Kawi: 7 geguritan at census) falls back to the
      # Index's Language= with both claims named in language_basis.
      LANGUAGE_CATEGORIES = {
        "Lontar Basa Kawi" => "kaw", "Lontar Basa Bali" => "ban", "Lontar Basa Sasak" => "sas"
      }.freeze

      GEDONG_KIRTYA = /\A(.+) ring Klasifikasi Gedong Kirtya\z/

      # Holding-collection categories (census): the village/griya
      # collections and institutional holdings the scans come from.
      COLLECTION_CATEGORIES = [
        "Lontar Balai Bahasa Bali", "Lontar ring Balai Bahasa Bali", "Naskah Balai Bahasa Bali",
        "Balai Bahasa Bali", "Lontar Kemenuh", "Lontar Leiden", "Naskah Leiden", "Lontar Pusdok",
        "Lontar ring Perpustakaan Kantor Dokumentasi Budaya Bali", "Lontar Sawan", "Lontar Semarajaya",
        "Lontar Sukawati", "Lontar Tojan", "Lontar Tojan WILMA", "Lontar Wanagiri",
        "Lontar ring Gedong Kirtya", "WikiSami UNHI"
      ].freeze

      # Genre categories (census, Index + work pages).
      GENRE_CATEGORIES = [
        "Babad", "Bang Bungalan", "Carcan", "Gaguritan", "Geguritan", "Kakawin", "Kawisesan",
        "Kidung", "Puja", "Tatwa", "Usada", "Wariga", "Satua", "Dongeng"
      ].freeze

      # A whole-line leaf marker: the transcriber's leaf number and side
      # ("[᭕᭖ 56B]", "[12A]") or the leaf-face words (depan/belakang = front/
      # back, awal/akhir = first/last).
      LEAF_MARKER = /\A\[\s*(?:\p{Nd}[\p{Nd}\s]*[AaBb]?|depan|belakang|awal|akhir)\s*\]\z/i
      QUALITY = /<pagequality\s+level="(\d)"(?:\s+user="([^"]*)")?/
      PAGES_TAG = %r{<pages\b[^>]*?\bindex\s*=\s*(?:"([^"]+)"|'([^']+)'|(\S+?))(?=[\s>/])}i

      RULE_NOTES = {
        redirect: "redirect Index page(s) (renamed scans)",
        printed_dated: "printed edition(s) excluded by the year rule (Index Year= names a publication " \
                       "year outside the manuscript-scan families, or before #{CAMPAIGN_FLOOR})",
        printed: "printed edition(s) outside the manuscript-scan families (no Year=)",
        no_text: "manuscript Index(es) whose pages carry no transcription"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "ban-wikisource",
        name: "Balinese Wikisource — the lontar (palm-leaf manuscript) transcriptions",
        license: "Creative Commons Attribution-Share Alike 4.0 (ban.wikisource.org api.php rightsinfo " \
                 "verbatim, https://creativecommons.org/licenses/by-sa/4.0/deed.ban, verified 2026-10-12); " \
                 "the palmleaf.org imports came under the same terms (\"User contributions are available " \
                 "under Creative Commons Attribution-ShareAlike unless otherwise noted\") → attribution",
        license_class: "attribution",
        upstream_url: "https://ban.wikisource.org/",
        parser_family: "wikisource-proofreadpage",
        credit: "Balinese Wikisource (ban.wikisource.org) contributors and the palmleaf.org (PanLex / " \
                "Internet Archive) transcribers, CC BY-SA 4.0; leaf images Internet Archive Balinese " \
                "Digital Library via Wikimedia Commons"
      )

      def self.manifest = MANIFEST

      # -- the rules (public: the tests exercise them directly) ---------------

      # The Index's rule class from its envelope: a RULE_NOTES key or :text.
      def index_class(envelope)
        wikitext = envelope.fetch("wikitext")
        return :redirect if wikitext.match?(REDIRECT)

        printed = printed_class(index_name(envelope.fetch("title")), wikitext)
        return printed if printed

        page_passages(envelope).empty? ? :no_text : :text
      end

      def printed_class(name, wikitext)
        year = index_field(wikitext, "Year").to_s[YEAR, 1]
        family = MANUSCRIPT_FAMILIES.any? { |pattern| name.match?(pattern) }
        return :printed_dated if year && (!family || Integer(year, 10) < CAMPAIGN_FLOOR)
        return :printed unless family

        nil
      end

      # -- fetch -------------------------------------------------------------

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        pages_by_index = list_pages(progress)
        indexes = fetch_indexes(pages_by_index.keys, progress)
        works = fetch_works(progress)
        pins = {}
        indexes.each do |page|
          name = index_name(page.fetch("title"))
          envelope = index_envelope(page, pages_by_index.fetch(name), works.fetch(name, []))
          fill_manuscript!(workdir, envelope, pages_by_index.fetch(name), progress) if admitted?(envelope)
          pins[envelope.fetch("pageid")] = pin_of(envelope)
          write_envelope_file!(workdir, envelope)
        end
        attach_scans!(workdir, indexes, progress).each { |pageid, revid| pins[pageid] += ",scan:#{revid}" }
        sha = Digest::SHA256.hexdigest(JSON.generate(pins.transform_keys(&:to_s).sort.to_h))
        write_state!(workdir, sha)
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now,
                              notes: "indexes: #{indexes.size} transcribed (of #{pages_by_index.size} Page-ns " \
                                     "groups), revid-pinned")
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        envelope_paths(workdir).sort.each do |path|
          envelope = read_envelope(path)
          next unless index_class(envelope) == :text

          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{envelope.fetch('pageid')}",
            path: File.expand_path(path), metadata: { "title" => envelope.fetch("title") }
          )
        end
      end

      def discovery_skips(workdir)
        classes = Hash.new(0)
        envelope_paths(workdir).each do |path|
          klass = index_class(read_envelope(path))
          classes[klass] += 1 unless klass == :text
        end
        strays = stray_files(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: classes.values.sum,
          unrecognized: strays.size,
          notes: RULE_NOTES.filter_map { |klass, note| "#{classes[klass]} #{note}" if classes[klass].positive? } +
                 strays.map { |rel| "non-corpus file: #{rel}" }
        )
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        envelope = read_envelope(document_ref.path)
        klass = index_class(envelope)
        raise ParseError, "#{document_ref.id}: a #{klass} Index reached parse (stale ref?)" unless klass == :text

        passages = page_passages(envelope)
        language = document_language(envelope, passages)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language,
          title: field_value(envelope["wikitext"], "Title") || Nabu::Normalize.nfc(index_name(envelope["title"])),
          canonical_path: document_ref.path,
          metadata: document_metadata(envelope, passages, language)
        )
        passages.each_with_index do |passage, index|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{passage[:page]}", language: language,
                                        text: passage[:text], sequence: index + 1,
                                        annotations: passage[:annotations])
        end
        document
      end

      private

      # -- the transcription -------------------------------------------------

      # The admitted Index's pages as passage hashes, page order: page
      # number (the "/N" suffix; a single-image Index is page 1), cleaned
      # text, quality/leaves annotations. Pages with no text drop.
      def page_passages(envelope)
        @page_passages ||= {}
        @page_passages[envelope.fetch("pageid")] ||= Array(envelope["pages"])
                                                     .map { |page| page_passage(page) }
                                                     .compact.sort_by { |passage| passage[:page] }
      end

      def page_passage(page)
        wikitext = page.fetch("wikitext")
        quality = wikitext[QUALITY, 1]
        lines, leaves = body_lines(wikitext)
        return nil if lines.empty?

        annotations = { "page" => page_number(page.fetch("title")),
                        "quality" => quality && Integer(quality, 10),
                        "leaves" => (leaves unless leaves.empty?) }.compact
        { page: page_number(page.fetch("title")), text: Nabu::Normalize.nfc(lines.join("\n")),
          annotations: annotations, quality: quality, quality_user: wikitext[QUALITY, 2] }
      end

      # The page body's manuscript lines and its leaf markers. The
      # <noinclude> header (pagequality) and footer drop; <br> and newlines
      # are line breaks; wikitable rows/cell markers, simple wrapper
      # templates ({{c|…}}) and HTML tags reduce to their text; refs drop.
      def body_lines(wikitext)
        body = wikitext.gsub(%r{<noinclude>.*?</noinclude>}m, "").gsub(/<!--.*?-->/m, "")
                       .gsub(%r{<ref[^>]*/>}m, "").gsub(%r{<ref[^>]*>.*?</ref>}m, "")
                       .gsub(%r{<br\s*/?>}i, "\n")
        body = unwrap_templates(body).gsub(%r{</?[a-zA-Z][^>]*>}, "").gsub("&nbsp;", " ")
        leaves = []
        lines = body.split("\n").filter_map do |raw|
          line = table_cell(raw).strip
          next nil if line.empty?

          if line.match?(LEAF_MARKER)
            leaves << line[1..-2].strip.gsub(/\s+/, " ")
            next nil
          end
          line
        end
        [lines, leaves]
      end

      # {{c|X}} / {{center|X}} / {{ts|…}} … → the last positional argument
      # (table-style templates carry none and vanish).
      def unwrap_templates(text)
        3.times do
          text = text.gsub(/\{\{([^{}]*)\}\}/) do
            name, *args = ::Regexp.last_match(1).split("|").map(&:strip)
            next "" if name.casecmp?("ts")

            args.grep_v(/\A[^=\s]+=/).last.to_s
          end
        end
        text
      end

      # Wikitable furniture: "{|…", "|}", "|-…" lines vanish; a cell's
      # leading "|"/"||"/"!" marker strips.
      def table_cell(line)
        stripped = line.strip
        return "" if stripped.start_with?("{|", "|}", "|-")

        stripped.sub(/\A[|!]+/, "")
      end

      def page_number(title)
        title[%r{/(\d+)\z}, 1].then { |number| number ? Integer(number, 10) : 1 }
      end

      # -- language + metadata -------------------------------------------------

      # Index Language= (quarantine on an unknown value), refined by the
      # works' language categories; the script subtag measured over the
      # held text (Balinese block vs Latin letters).
      def document_language(envelope, passages)
        field = index_field(envelope.fetch("wikitext"), "Language").to_s.strip
        base = INDEX_LANGUAGES[field.downcase] or
          raise ParseError, "#{envelope.fetch('title')}: unknown Index Language= #{field.inspect} (quarantined)"

        claims = work_language_claims(envelope)
        "#{claims.size == 1 ? claims.first : base}-#{script_of(passages)}"
      end

      def work_language_claims(envelope)
        work_categories(envelope).filter_map { |category| LANGUAGE_CATEGORIES[category] }.uniq.sort
      end

      def script_of(passages)
        text = passages.map { |passage| passage[:text] }.join
        text.scan(/\p{Balinese}/).size >= text.scan(/\p{Latin}/).size ? "Bali" : "Latn"
      end

      def document_metadata(envelope, passages, language)
        wikitext = envelope.fetch("wikitext")
        index_cats = categories_of(envelope["categories"])
        work_cats = work_categories(envelope)
        all_cats = (index_cats + work_cats).uniq
        {
          "index" => Nabu::Normalize.nfc(envelope.fetch("title")),
          "index_revid" => envelope["revid"],
          "language_field" => index_field(wikitext, "Language").to_s.strip,
          "language_basis" => language_basis(envelope),
          "script" => language.split("-").last,
          "address" => field_value(wikitext, "Address"),
          "author" => field_value(wikitext, "Author"),
          "editor" => field_value(wikitext, "Editor"),
          "publisher" => field_value(wikitext, "Publisher"),
          "index_year" => field_value(wikitext, "Year"),
          "index_categories" => (index_cats unless index_cats.empty?),
          "works" => (works_titles(envelope) unless works_titles(envelope).empty?),
          "work_categories" => (work_cats unless work_cats.empty?),
          "genre" => list_or_nil(all_cats & GENRE_CATEGORIES),
          "collection" => list_or_nil(all_cats & COLLECTION_CATEGORIES),
          "gedong_kirtya_class" => list_or_nil(all_cats.filter_map { |c| c[GEDONG_KIRTYA, 1] }),
          "quality" => quality_census(passages),
          "pages_upstream" => envelope["page_count"],
          "palmleaf_bot_pages" => passages.count { |passage| passage[:quality_user] == "Palmleaf Bot" },
          "scan" => scan_metadata(envelope["scan"])
        }.compact
      end

      # Where the document language came from: one work language category,
      # or the Index's Language= — also when the works' categories CONFLICT
      # (Basa Bali beside Basa Kawi, the geguritan census), both named.
      def language_basis(envelope)
        claims = work_categories(envelope).select { |category| LANGUAGE_CATEGORIES.key?(category) }
        return "work category: #{claims.first}" if claims.size == 1
        return "Index Language= (conflicting work categories: #{claims.sort.join(' / ')})" if claims.size > 1

        "Index Language="
      end

      # Page counts per ProofreadPage level ("0".."4"; 3 = proofread,
      # 4 = validated) over the held passages.
      def quality_census(passages)
        passages.each_with_object(Hash.new(0)) { |passage, counts| counts[passage[:quality] || "unstated"] += 1 }
                .sort.to_h
      end

      def scan_metadata(scan)
        return nil if scan.nil?

        wikitext = scan["wikitext"].to_s
        {
          "file" => Nabu::Normalize.nfc(scan.fetch("title")),
          "ia_identifier" => wikitext[/\{\{\s*IA\s*\|\s*([^|}]+?)\s*\}\}/, 1],
          "shelfmark" => wikitext[/Shelfmark:\s*([^<|\n]+?)\s*(?:<br|\||\n)/, 1],
          "file_date" => commons_field(wikitext, "date"),
          "file_source" => commons_field(wikitext, "source"),
          "licenses" => list_or_nil(licence_templates(wikitext)),
          "commons_categories" => list_or_nil(categories_of(scan["categories"]))
        }.compact
      end

      # A one-line |field= of the Commons {{Information}} block, verbatim
      # (the FILE's date — the photograph/scan, never the manuscript).
      def commons_field(wikitext, field)
        value = wikitext[/^\|\s*#{field}\s*=([^\n]*)$/, 1].to_s.strip
        value.empty? ? nil : Nabu::Normalize.nfc(value)
      end

      # The Commons licence section's templates verbatim ({{PD-IDNoCopyright}},
      # {{self|cc-by-sa-4.0}} …).
      def licence_templates(wikitext)
        section = wikitext[/\{\{\s*int:license-header\s*\}\}\s*=+(.*)\z/mi, 1].to_s
        section.scan(/\{\{\s*([^{}]+?)\s*\}\}/).flatten.map { |template| template.gsub(/\s+/, " ") }
      end

      def works_titles(envelope)
        Array(envelope["works"]).map { |work| Nabu::Normalize.nfc(work.fetch("title")) }
      end

      def work_categories(envelope)
        Array(envelope["works"]).flat_map { |work| categories_of(work["categories"]) }.uniq
      end

      # Category titles without their namespace prefix, NFC; the
      # ProofreadPage/maintenance trackers ("Index …") drop.
      def categories_of(categories)
        Array(categories).map { |category| Nabu::Normalize.nfc(category.sub(/\A[^:]+:/, "")) }
                         .grep_v(/\AIndex\b/).uniq
      end

      def list_or_nil(list) = list.empty? ? nil : list.sort

      def field_value(wikitext, field)
        value = display_text(index_field(wikitext, field).to_s)
        value.empty? ? nil : Nabu::Normalize.nfc(value)
      end

      # A |Field= value of the Index template, up to the next top-level
      # |Field= line or the closing braces; nil when absent.
      def index_field(wikitext, field)
        match = wikitext.match(/^\|\s*#{Regexp.escape(field)}\s*=(.*?)(?=^\|\s*[^|=\n]+=|^\}\}|\z)/m)
        match && match[1].strip
      end

      def display_text(value)
        unwrap_templates(value).gsub(/\[\[(?:[^\[\]|]*\|)?([^\[\]]*)\]\]/) { ::Regexp.last_match(1) }
                               .gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
      end

      def index_name(title) = title.split(":", 2).last.to_s

      # -- fetch internals ---------------------------------------------------

      def admitted?(envelope)
        !envelope.fetch("wikitext").match?(REDIRECT) &&
          printed_class(index_name(envelope.fetch("title")), envelope.fetch("wikitext")).nil?
      end

      # Stage 1: every Page-namespace page (title/pageid/lastrevid),
      # grouped by the Index it belongs to.
      def list_pages(progress)
        grouped = Hash.new { |hash, key| hash[key] = [] }
        list_namespace(PAGE_NS).each do |page|
          grouped[page_index_name(page.fetch("title"))] << page
        end
        progress&.call("Page namespace: #{grouped.values.sum(&:size)} page(s) over #{grouped.size} Index name(s)\n")
        grouped
      end

      def page_index_name(title)
        name = index_name(title)
        name.match?(%r{\.(?:pdf|djvu|tiff?)/\d+\z}i) ? name.sub(%r{/\d+\z}, "") : name
      end

      def list_namespace(namespace, extra = {})
        pages = []
        continue = {}
        loop do
          payload = get_json("action" => "query", "format" => "json", "generator" => "allpages",
                             "gapnamespace" => namespace.to_s, "gaplimit" => LIST_LIMIT, "prop" => "info",
                             **extra, **continue)
          pages.concat((payload.dig("query", "pages") || {}).values)
          continue = payload["continue"] or break
        end
        pages
      end

      # Stage 2: the Index pages that own Page-namespace pages.
      def fetch_indexes(names, progress)
        titles = names.map { |name| "#{index_prefix}#{name}" }
        progress&.call("Index pages: #{titles.size}\n")
        title_batches(titles.sort).flat_map { |batch| pages_payload(batch) }
                                  .select { |page| page.dig("revisions", 0) }
      end

      def index_prefix = @index_prefix ||= "#{namespace_name(INDEX_NS)}:"

      def namespace_name(namespace)
        @namespaces ||= get_json("action" => "query", "format" => "json", "meta" => "siteinfo",
                                 "siprop" => "namespaces").dig("query", "namespaces")
        @namespaces.fetch(namespace.to_s).fetch("*")
      end

      # Stage 3: every main-namespace work page → { Index name => [work] }.
      def fetch_works(progress)
        titles = list_namespace(MAIN_NS, "gapfilterredir" => "nonredirects").map { |page| page.fetch("title") }
        progress&.call("Work pages: #{titles.size}\n")
        by_index = Hash.new { |hash, key| hash[key] = [] }
        title_batches(titles.sort).each do |batch|
          pages_payload(batch).each do |page|
            wikitext = page.dig("revisions", 0, "slots", "main", "*").to_s
            work = { "title" => page.fetch("title"), "pageid" => page.fetch("pageid"),
                     "revid" => page.dig("revisions", 0, "revid"), "categories" => page["categories"].sort }
            wikitext.scan(PAGES_TAG).map { |captures| captures.compact.first.tr("_", " ") }.uniq.each do |name|
              by_index[name] << work
            end
          end
        end
        by_index
      end

      def index_envelope(page, listed, works)
        revision = page.dig("revisions", 0)
        {
          "title" => page.fetch("title"), "pageid" => page.fetch("pageid"), "ns" => INDEX_NS,
          "revid" => revision["revid"], "timestamp" => revision["timestamp"],
          "categories" => page["categories"].sort, "page_count" => listed.size,
          "works" => works.sort_by { |work| work.fetch("title") },
          "wikitext" => revision.dig("slots", "main", "*").to_s
        }
      end

      # Stage 4: the admitted Index's Page-namespace wikitext, delta
      # against the held envelope; held pages upstream no longer lists stay.
      def fill_manuscript!(workdir, envelope, listed, progress)
        held = held_pages(workdir, envelope.fetch("pageid"))
        stale = listed.reject { |page| held[page.fetch("title")]&.fetch("revid") == page["lastrevid"] }
        fresh = {}
        title_batches(stale.map { |page| page.fetch("title") }.sort).each do |batch|
          pages_payload(batch).each do |page|
            revision = page.dig("revisions", 0) or next

            fresh[page.fetch("title")] = { "title" => page.fetch("title"), "pageid" => page.fetch("pageid"),
                                           "revid" => revision["revid"], "timestamp" => revision["timestamp"],
                                           "wikitext" => revision.dig("slots", "main", "*").to_s }
          end
        end
        progress&.call("#{envelope.fetch('title')}: #{fresh.size} page(s) fetched, #{held.size} held\n") if
          fresh.any?
        envelope["pages"] = held.merge(fresh).values.sort_by do |page|
          [page_number(page.fetch("title")),
           page.fetch("title")]
        end
      end

      def held_pages(workdir, pageid)
        path = File.join(workdir, PAGES_DIRNAME, "#{pageid}.json")
        return {} unless File.file?(path)

        Array(JSON.parse(File.read(path))["pages"]).to_h { |page| [page.fetch("title"), page] }
      rescue JSON::ParserError
        {}
      end

      # Stage 5: the admitted scans' Commons File pages, merged into their
      # envelopes (rewritten with the scan block).
      def attach_scans!(workdir, indexes, progress)
        admitted = indexes.filter_map do |page|
          envelope = JSON.parse(File.read(File.join(workdir, PAGES_DIRNAME, "#{page.fetch('pageid')}.json")))
          envelope if admitted?(envelope)
        end
        by_file = admitted.to_h { |envelope| ["File:#{index_name(envelope.fetch('title'))}", envelope] }
        progress&.call("Commons scans: #{by_file.size}\n")
        scan_revids = {}
        title_batches(by_file.keys.sort).each do |batch|
          commons_payload(batch).each do |page|
            envelope = by_file[page.fetch("title")] or next
            revision = page.dig("revisions", 0) or next

            envelope["scan"] = { "title" => page.fetch("title"), "revid" => revision["revid"],
                                 "categories" => page["categories"].sort,
                                 "wikitext" => revision.dig("slots", "main", "*").to_s }
            write_envelope_file!(workdir, envelope)
            scan_revids[envelope.fetch("pageid")] = revision["revid"]
          end
        end
        scan_revids
      end

      def commons_payload(batch)
        @api_url = COMMONS_API_URL
        pages_payload(batch)
      ensure
        @api_url = nil
      end

      def pin_of(envelope)
        [envelope["revid"], *Array(envelope["works"]).map { |work| work["revid"] },
         *Array(envelope["pages"]).map { |page| page["revid"] }].join(",")
      end

      def write_envelope_file!(workdir, envelope)
        dir = File.join(workdir, PAGES_DIRNAME)
        FileUtils.mkdir_p(dir)
        target = File.join(dir, "#{envelope.fetch('pageid')}.json")
        File.binwrite("#{target}.tmp", "#{JSON.pretty_generate(envelope)}\n")
        File.rename("#{target}.tmp", target)
      end

      # The batch sizer's URL, pointed at Commons while a scan batch runs.
      def api_url(params) = "#{@api_url || API_URL}?#{URI.encode_www_form(params)}"

      # The base's throttled, UA-identified GET, routed through #api_url
      # (the base builds from API_URL alone; the Commons stage needs the
      # second endpoint).
      def get_json(params)
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        response, = Nabu::RedirectFollow.get(api_url(params), http: @http, error: Nabu::FetchError,
                                                              headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        payload = JSON.parse(response.body.to_s)
        raise Nabu::FetchError, "api.php error: #{payload['error']}" if payload.key?("error")

        payload
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "api.php returned unparseable JSON: #{e.message}"
      end

      # Whole-envelope memo per path (discover classifies, parse re-reads).
      def read_envelope(path)
        return @envelope.last if @envelope&.first == path

        envelope = JSON.parse(File.read(path))
        raise ParseError, "#{path}: Index envelope has no wikitext" unless envelope["wikitext"].is_a?(String)

        @envelope = [path, envelope]
        envelope
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable Index envelope: #{e.message}"
      end
    end
  end
end
