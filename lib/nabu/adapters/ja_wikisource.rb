# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"

require_relative "../wiki_fetch"
require_relative "../zip_fetch"
require_relative "../redirect_follow"
require_relative "../normalize"

module Nabu
  module Adapters
    # ja-wikisource (P109-1, Q90 under №R-74): the Japanese Wikisource
    # premodern shelf — the ERA CATEGORY CONE (census 2026-09-29, in
    # .docs/p109-plan.md): every ns-0 page reachable from the eight era
    # categories 飛鳥…江戸 within CATEGORY_DEPTH, 867 pages at census.
    # Hosted texts are PD; the transcription layer is CC BY-SA 4.0
    # (wiki footer verbatim) → attribution, credit the contributors.
    #
    # == The three page classes (censused over the full cone)
    #
    # - DIRECT TEXT (760 pages, 6.6 MB): parsed. Two modes, detected
    #   per page: the structured per-poem block grammar (万葉集 —
    #   [歌番号]/[題詞]/[原文]/[訓読]/[仮名] blocks; 原文 man'yōgana IS
    #   the text, language ojp, kundoku/kana riding annotations) and
    #   prose (paragraph grain, language jpn; bare dan numbers become
    #   sections; ruby {{r|漢字|よみ}} keeps its base text; iteration-
    #   mark templates render their character; editorial {{smaller|
    #   〔…〕}} glosses strip — a modern apparatus, not the text).
    # - {{versions}} SHELLS (29): edition disambiguation pages — no
    #   text; skip-by-rule.
    # - <pages index> SHELLS (78): ProofreadPage scan transclusions
    #   whose text lives in the Page: namespace. Since P111-2 the
    #   fetch EXPANDS them: the tag's from/to (or include=) range
    #   enumerates Page:<index>/<n> titles, their wikitexts land in
    #   the envelope's "pages" map (revid-pinned), and the parse
    #   joins them offline with the <noinclude> furniture stripped.
    #   A payload-less shell (stale tree) still skips by rule.
    # - DISPATCHER SHELLS (232 censused): parameterized sibling
    #   transclusions ({{:親|サブページ名={{SUBPAGENAME}}}},
    #   {{:親|ボディー=1|巻=…}}) — the content renders from another
    #   page's template machinery, so plain inlining (the zh piece
    #   mold) cannot resolve them. Since P111-2 the fetch calls
    #   action=expandtemplates (title = the shell's own title, so
    #   BASEPAGENAME/SUBPAGENAME resolve) and stores the expanded
    #   wikitext in the envelope ("expanded", content-sha-pinned —
    #   no revid exists for a server-side expansion). The parse
    #   strips the rendered furniture (nav divs, TOC self-links,
    #   templatestyles, ruby readings) and keeps the text; heading
    #   links back to the parent's TOC anchors become section
    #   annotations. A shell whose expansion yields no prose still
    #   skips by rule.
    #
    # == №R-74 (the ruled Wikisource posture)
    #
    # Premodern-cone ingest, any transcription status; each page's
    # stated base edition rides verbatim in metadata "base_edition"
    # (the 底本 line where present, else the title's edition
    # parenthetical, else the honest "unstated"). The era categories
    # a page carries ride as metadata "eras" and band the grade-2 era
    # date envelope ("era_band" → MetadataDates :era_band_key,
    # precision "era" — an era attribution, never a typed date).
    #
    # == Fetch (the WikiFetch mold, category-cone shaped)
    #
    # Stage 1 walks the era categories (categorymembers, subcategories
    # to depth 2) into a title → era-set map; stage 2 fetches the
    # titles' revisions in 50-title batches and writes one envelope
    # per page: pages/<pageid>.json (title/pageid/ns/revid/timestamp/
    # wikitext verbatim + "eras"). NON-DESTRUCTIVE by construction: a
    # page that leaves the cone upstream is simply kept. The pin is
    # the sha256 of the pageid → revid map.
    class JaWikisource < Nabu::Adapter
      LANGUAGE = "jpn"
      MANYO_LANGUAGE = "ojp"
      API_URL = "https://ja.wikisource.org/w/api.php"
      STATE_FILE = ".ja-wikisource-fetch.json"
      PAGES_DIRNAME = "pages"
      CATEGORY_DEPTH = 2
      URN_PREFIX = "urn:nabu:ja-wikisource:"

      # The premodern era cone (census 2026-09-29) with each era's
      # conventional CE band — the grade-2 era envelope.
      ERA_CATEGORIES = {
        "飛鳥時代" => [538, 710],
        "奈良時代" => [710, 794],
        "平安時代" => [794, 1185],
        "鎌倉時代" => [1185, 1333],
        "南北朝時代" => [1336, 1392],
        "室町時代" => [1336, 1573],
        "安土桃山時代" => [1573, 1603],
        "江戸時代" => [1603, 1868]
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "ja-wikisource",
        name: "Japanese Wikisource — the premodern era cone (飛鳥–江戸)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (ja.wikisource.org footer verbatim, verified 2026-09-29) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://ja.wikisource.org/",
        parser_family: "ja-wikisource",
        credit: "Japanese Wikisource (ja.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "api.php", zip_url: "#{API_URL}?action=query&meta=siteinfo&format=json",
          metadata_url: nil, state_subdir: ".", state_file: STATE_FILE
        )]
      end

      def initialize(delay: Nabu::WikiFetch::DELAY, http: Nabu::ZipFetch.default_http)
        super()
        @delay = delay
        @http = http
        @requests = 0
      end

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever
      # deletes, so there is no breaker to override.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        eras_by_title = walk_categories(progress)
        progress&.call("Era cone: #{eras_by_title.size} page(s) across #{ERA_CATEGORIES.size} eras\n")
        revids = fetch_pages!(workdir, eras_by_title, progress)
        expand_shells!(workdir, revids, progress)
        # Keys are Integer pageids AND "pageid:…" expansion-pin Strings —
        # stringify before sorting (the zh mixed-sort lesson).
        sha = Digest::SHA256.hexdigest(JSON.generate(revids.transform_keys(&:to_s).sort.to_h))
        write_state!(workdir, sha)
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now,
                              notes: "pages: #{revids.size} of #{eras_by_title.size} cone titles, revid-pinned")
      end

      # -- the shell expansions (P111-2, Q109-1) -----------------------------

      # A <pages index> tag's attribute region (quoted and bare attrs, with
      # or without the self-closing slash).
      PAGES_TAG = %r{<pages\s+([^>]*?)/?\s*>}i

      # Every Page:-namespace title a shell's <pages> tag(s) transclude,
      # in reading order: index + from/to range, or the include= list.
      def self.pages_tag_titles(wikitext)
        wikitext.scan(PAGES_TAG).flat_map do |(attrs)|
          index = attrs[/index\s*=\s*"([^"]+)"/i, 1] || attrs[/index\s*=\s*(\S+)/i, 1]
          next [] unless index

          # MediaWiki normalizes underscores to spaces in titles — the api
          # returns (and the envelope stores) the normalized form, so the
          # lookup must build it (the 芭蕉俳句全集 first-sync quarantine).
          index = index.tr("_", " ")
          pages_tag_numbers(attrs).map { |n| "Page:#{index}/#{n}" }
        end
      end

      def self.pages_tag_numbers(attrs)
        from = attrs[/from\s*=\s*"?(\d+)"?/i, 1]
        to = attrs[/to\s*=\s*"?(\d+)"?/i, 1]
        return (from.to_i..to.to_i).to_a if from && to

        spec = attrs[/include\s*=\s*"?([\d,-]+)"?/i, 1] or return []
        spec.split(",").flat_map do |part|
          first, last = part.split("-")
          last ? (first.to_i..last.to_i).to_a : [first.to_i]
        end
      end

      # -- discover ----------------------------------------------------------

      # One ref per DIRECT-TEXT envelope; versions and <pages index>
      # shells are the skip-by-rule census.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        envelope_paths(workdir).each do |path|
          envelope = read_envelope(path)
          next unless page_class(envelope) == :text

          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{envelope.fetch('pageid')}",
            path: File.expand_path(path), metadata: { "title" => envelope.fetch("title") }
          )
        end
      end

      def discovery_skips(workdir)
        skipped = envelope_paths(workdir).count { |path| page_class(read_envelope(path)) != :text }
        strays = stray_files(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: skipped,
          unrecognized: strays.size,
          notes: (if skipped.positive?
                    ["#{skipped} shell page(s) — {{versions}}/<pages index>/" \
                     "sibling-transclusion (no hosted text)"]
                  else
                    []
                  end) +
                 strays.map { |rel| "non-corpus file: #{rel}" }
        )
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        envelope = read_envelope(document_ref.path)
        wikitext = envelope.fetch("wikitext")
        raise ParseError, "#{document_ref.id}: a shell page reached parse (stale ref?)" unless
          page_class(envelope) == :text

        if page_payloads?(envelope)
          pages_index_document(document_ref, envelope)
        elsif envelope["expanded"].is_a?(String)
          expanded_document(document_ref, envelope)
        elsif manyo_blocks?(wikitext)
          manyo_document(document_ref, envelope, wikitext)
        else
          prose_document(document_ref, envelope, wikitext)
        end
      end

      # The section-marker sentinel strip_expanded plants for heading links
      # (mold B): ASCII, never occurs in hosted text.
      SECTION_MARKER = "@@nabu-section@@"

      # The 万葉集 block grammar (P109-1 census: [歌番号] fields).
      MANYO_BLOCK = /^\[歌番号\]/
      MANYO_FIELD = /^\[(歌番号|題詞|原文|訓読|仮名|左注|校異|事項)\](.*)$/

      private

      # -- fetch internals ---------------------------------------------------

      def walk_categories(progress)
        eras_by_title = Hash.new { |hash, key| hash[key] = [] }
        ERA_CATEGORIES.each_key do |era|
          seen = {}
          queue = [["カテゴリ:#{era}", 0]]
          until queue.empty?
            category, depth = queue.shift
            next if seen.key?(category)

            seen[category] = true
            category_members(category).each do |member|
              if member["ns"] == 0 # rubocop:disable Style/NumericPredicate
                eras_by_title[member.fetch("title")] << era
              elsif member["ns"] == 14 && depth < CATEGORY_DEPTH
                queue << [member.fetch("title"), depth + 1]
              end
            end
          end
          progress&.call("#{era}: cone at #{eras_by_title.size} page(s)\n")
        end
        eras_by_title.transform_values { |eras| eras.uniq.sort_by { |era| ERA_CATEGORIES.keys.index(era) } }
      end

      def category_members(category)
        members = []
        continue = {}
        loop do
          payload = get_json("action" => "query", "format" => "json", "list" => "categorymembers",
                             "cmtitle" => category, "cmlimit" => "500", **continue)
          members.concat(payload.dig("query", "categorymembers") || [])
          token = payload.dig("continue", "cmcontinue") or break

          continue = { "cmcontinue" => token }
        end
        members
      end

      def fetch_pages!(workdir, eras_by_title, progress)
        revids = {}
        titles = eras_by_title.keys.sort
        titles.each_slice(Nabu::WikiFetch::CONTENT_BATCH).with_index do |batch, index|
          progress&.call("Fetching batch #{index + 1} (#{batch.size} page(s))…\n")
          pages_payload(batch).each do |page|
            revision = page.dig("revisions", 0) or next
            revids[page.fetch("pageid")] =
              write_envelope!(workdir, page, revision, eras_by_title.fetch(page.fetch("title")))
          end
        end
        revids
      end

      def pages_payload(batch)
        payload = get_json("action" => "query", "format" => "json", "prop" => "revisions",
                           "rvprop" => "content|ids|timestamp", "rvslots" => "main",
                           "titles" => batch.join("|"))
        (payload.dig("query", "pages") || {}).values.reject { |page| page.key?("missing") }
      end

      def write_envelope!(workdir, page, revision, eras)
        envelope = {
          "title" => page.fetch("title"), "pageid" => page.fetch("pageid"), "ns" => page["ns"] || 0,
          "revid" => revision["revid"], "timestamp" => revision["timestamp"],
          "eras" => eras, "wikitext" => revision.dig("slots", "main", "*").to_s
        }
        dir = File.join(workdir, PAGES_DIRNAME)
        FileUtils.mkdir_p(dir)
        target = File.join(dir, "#{envelope.fetch('pageid')}.json")
        File.binwrite("#{target}.tmp", "#{JSON.pretty_generate(envelope)}\n")
        File.rename("#{target}.tmp", target)
        envelope["revid"]
      end

      # P111-2: the second fetch pass — every shell envelope gains its
      # expansion payload (class note). Runs after fetch_pages! rewrote the
      # envelopes, so payloads are always re-derived against the current
      # revision; a shell that stops being a shell upstream simply takes
      # the ordinary path next time.
      def expand_shells!(workdir, revids, progress)
        paged = 0
        expanded = 0
        envelope_paths(workdir).each do |path|
          envelope = JSON.parse(File.read(path))
          wikitext = envelope.fetch("wikitext")
          next if wikitext.match?(/\{\{\s*versions/i) || manyo_blocks?(wikitext)

          if wikitext.match?(/<pages\s+index/i)
            paged += expand_pages_shell!(path, envelope, revids)
          elsif prose_paragraphs(wikitext).empty?
            expanded += expand_dispatcher_shell!(path, envelope, revids)
          end
        end
        progress&.call("Shell expansion: #{paged} <pages index> + #{expanded} dispatcher shell(s)\n")
      end

      def expand_pages_shell!(path, envelope, revids)
        titles = self.class.pages_tag_titles(envelope.fetch("wikitext"))
        return 0 if titles.empty?

        payloads = {}
        titles.each_slice(Nabu::WikiFetch::CONTENT_BATCH) do |batch|
          pages_payload(batch).each do |page|
            revision = page.dig("revisions", 0) or next

            revids["#{envelope.fetch('pageid')}:#{page.fetch('title')}"] = revision["revid"]
            payloads[page.fetch("title")] = revision.dig("slots", "main", "*").to_s
          end
        end
        return 0 if payloads.empty?

        rewrite_envelope!(path, envelope.merge("pages" => payloads))
        1
      end

      def expand_dispatcher_shell!(path, envelope, revids)
        payload = get_json("action" => "expandtemplates", "format" => "json", "prop" => "wikitext",
                           "title" => envelope.fetch("title"), "text" => envelope.fetch("wikitext"))
        text = payload.dig("expandtemplates", "wikitext").to_s
        return 0 if text.strip.empty?

        # No revid exists for a server-side expansion — the pin is the
        # expanded content itself, so a target-page edit re-syncs the shell.
        revids["#{envelope.fetch('pageid')}:expanded"] = Digest::SHA256.hexdigest(text)[0, 16]
        rewrite_envelope!(path, envelope.merge("expanded" => text))
        1
      end

      def rewrite_envelope!(path, envelope)
        File.binwrite("#{path}.tmp", "#{JSON.pretty_generate(envelope)}\n")
        File.rename("#{path}.tmp", path)
      end

      def write_state!(workdir, sha)
        FileUtils.mkdir_p(workdir)
        state = { "last_modified" => nil, "sha256" => sha, "url" => API_URL }
        File.write(File.join(workdir, STATE_FILE), JSON.pretty_generate(state))
      end

      def get_json(params)
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        url = "#{API_URL}?#{URI.encode_www_form(params)}"
        response, = Nabu::RedirectFollow.get(url, http: @http, error: Nabu::FetchError,
                                                  headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        payload = JSON.parse(response.body.to_s)
        raise Nabu::FetchError, "api.php error: #{payload['error']}" if payload.key?("error")

        payload
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "api.php returned unparseable JSON: #{e.message}"
      end

      # -- discovery internals -----------------------------------------------

      def envelope_paths(workdir)
        Dir.glob(File.join(workdir, PAGES_DIRNAME, "*.json"))
      end

      def read_envelope(path)
        @envelopes ||= {}
        @envelopes[path] ||= begin
          envelope = JSON.parse(File.read(path))
          raise ParseError, "#{path}: page envelope has no wikitext" unless envelope["wikitext"].is_a?(String)

          envelope
        end
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable page envelope: #{e.message}"
      end

      def page_class(envelope)
        wikitext = envelope.fetch("wikitext")
        return :versions if wikitext.match?(/\{\{\s*versions/i)
        # P111-2: a shell whose fetch landed an expansion payload IS a text
        # page now; a payload-less one (stale tree, empty expansion) keeps
        # skipping by rule, never quarantines.
        return page_payloads?(envelope) ? :text : :pages_index if wikitext.match?(/<pages\s+index/i)
        return :text if manyo_blocks?(wikitext)

        if prose_paragraphs(wikitext).empty?
          return :text unless expanded_paragraphs(envelope).empty?

          return :shell
        end

        :text
      end

      def page_payloads?(envelope)
        envelope["pages"].is_a?(Hash) && !envelope["pages"].empty?
      end

      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .reject { |path| File.basename(path).start_with?(".") }
           .grep_v(%r{/#{PAGES_DIRNAME}/[^/]+\.json\z})
           .reject { |path| File.basename(path).downcase == "readme.md" }
           .map { |path| path.delete_prefix("#{workdir}/") }
           .sort
      end

      # -- parse internals ---------------------------------------------------

      def manyo_blocks?(wikitext) = wikitext.match?(MANYO_BLOCK)

      def document_for(document_ref, envelope, language:)
        Nabu::Document.new(
          urn: document_ref.id, language: language,
          title: Nabu::Normalize.nfc(envelope.fetch("title")),
          canonical_path: document_ref.path,
          metadata: document_metadata(envelope)
        )
      end

      def document_metadata(envelope)
        wikitext = envelope.fetch("wikitext")
        eras = Array(envelope["eras"])
        {
          "eras" => (eras unless eras.empty?),
          "era_band" => era_band(eras),
          "base_edition" => base_edition(envelope),
          "textquality" => wikitext[/\{\{Textquality\|(\d+%?)\}\}/i, 1]
        }.compact
      end

      # The grade-2 era envelope over every era category the page
      # carries (multi-era pages span; the raw names the claim).
      def era_band(eras)
        bands = eras.filter_map { |era| ERA_CATEGORIES[era] }
        return nil if bands.empty?

        { "not_before" => bands.map(&:first).min, "not_after" => bands.map(&:last).max,
          "raw" => eras.join("・") }
      end

      # №R-74: the stated base edition, verbatim — the 底本 line, else
      # the title's edition parenthetical, else the honest "unstated".
      def base_edition(envelope)
        line = envelope.fetch("wikitext")[/底本[:：]\s*(.+)/, 1]
        return Nabu::Normalize.nfc(strip_inline_templates(line).strip) if line

        parenthetical = envelope.fetch("title")[/\(([^)]+)\)\s*\z/, 1]
        parenthetical ? Nabu::Normalize.nfc(parenthetical) : "unstated"
      end

      # -- prose mode --------------------------------------------------------

      def prose_document(document_ref, envelope, wikitext)
        document = document_for(document_ref, envelope, language: LANGUAGE)
        append_prose!(document, document_ref, prose_paragraphs(wikitext))
        raise ParseError, "#{document_ref.id}: no prose extracted" if document.empty?

        document
      end

      def append_prose!(document, document_ref, paragraphs)
        section = nil
        sequence = 0
        paragraphs.each do |paragraph|
          if paragraph.match?(/\A\d+\z/)
            section = paragraph
            next
          end

          sequence += 1
          annotations = section ? { "section" => section } : {}
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{sequence}", language: LANGUAGE,
            text: paragraph, sequence: sequence, annotations: annotations
          )
        end
      end

      # -- the <pages index> expansion (P111-2, mold A) ----------------------

      # The shell's Page:-namespace payloads join in tag order with a SINGLE
      # newline — MediaWiki's own transclusion seam, so a sentence wrapped
      # across scan pages stays one paragraph (the prose pipeline collapses
      # inner newlines) and real blank-line breaks still split. The Page-ns
      # <noinclude> regions (pagequality headers, running footers) are
      # furniture, never text.
      def pages_index_document(document_ref, envelope)
        document = document_for(document_ref, envelope, language: LANGUAGE)
        pages = envelope.fetch("pages")
        body = self.class.pages_tag_titles(envelope.fetch("wikitext"))
                   .filter_map { |title| pages[title] }
                   .map { |text| text.gsub(%r{<noinclude>.*?</noinclude>}m, "") }
                   .join("\n")
        append_prose!(document, document_ref, prose_paragraphs(body))
        raise ParseError, "#{document_ref.id}: no prose extracted from the Page: payloads" if document.empty?

        document
      end

      # -- the dispatcher-shell expansion (P111-2, mold B) -------------------

      def expanded_document(document_ref, envelope)
        document = document_for(document_ref, envelope, language: LANGUAGE)
        section = nil
        sequence = 0
        expanded_paragraphs(envelope).each do |paragraph|
          if paragraph.start_with?(SECTION_MARKER)
            section = paragraph.delete_prefix(SECTION_MARKER).strip
            next
          end

          sequence += 1
          annotations = section ? { "section" => section } : {}
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{sequence}", language: LANGUAGE,
            text: paragraph, sequence: sequence, annotations: annotations
          )
        end
        raise ParseError, "#{document_ref.id}: no prose extracted from the expansion" if document.empty?

        document
      end

      def expanded_paragraphs(envelope)
        text = envelope["expanded"]
        return [] unless text.is_a?(String)

        @expanded_paragraphs ||= {}
        @expanded_paragraphs[envelope.fetch("pageid")] ||=
          strip_expanded(text, envelope.fetch("title"))
      end

      # The rendered-furniture strip for expandtemplates output (censused
      # over the live shells, 2026-09-30): nav divs by id, TOC self-links,
      # heading links back to the parent's TOC anchors (→ section markers),
      # templatestyles/indicator/inputbox machinery, ruby readings (<rt>/
      # <rp> drop, base text stays), link-only furniture paragraphs (the
      # volume lists). Div boundaries become paragraph breaks — the
      # expansion carries no blank-line structure of its own.
      def strip_expanded(text, title)
        body = text.gsub("&#x23;", "#").gsub("&nbsp;", " ").gsub("&#32;", " ")
                   .gsub(/__[A-Z]+__/, "")
                   .gsub(%r{<templatestyles[^>]*/?>}i, "")
                   .gsub(/<!--.*?-->/m, "")
                   # 【…[https://dl.ndl.go.jp/… NDLJP:n]…】 scan-page markers
                   # (the transcription's source-image anchors) are furniture
                   .gsub(/【[^【】]*\[https?:[^\]]*\][^【】]*】/, "")
        body = remove_balanced_div(body, 'id="navigationHeader"')
        body = remove_balanced_div(body, 'id="navigationNotes"')
        body = body.gsub(%r{<indicator[^>]*>.*?</indicator>}mi, "")
                   .gsub(%r{<inputbox>.*?</inputbox>}mi, "")
                   .gsub(%r{<r[tp][^>]*>.*?</r[tp]>}mi, "")
        body = body.gsub(/\[\[[^\[\]|]*#目次-[^\[\]|]*\|([^\[\]]*)\]\]/) do
          label = ::Regexp.last_match(1).gsub(%r{</?[a-z][^>]*>}i, "").strip
          "\n\n#{SECTION_MARKER}#{label}\n\n"
        end
        body = body.gsub(/\[\[#{Regexp.escape(title)}#[^\[\]]*\]\]/, "")
                   .gsub(/\[\[(?:category|file|image|special):[^\[\]]*\]\]/i, "")
                   .gsub(%r{</?div[^>]*>}i, "\n\n")
        body.split(/\n{2,}/)
            .reject { |paragraph| link_only_paragraph?(paragraph) }
            .map { |paragraph| finish_expanded_paragraph(paragraph) }
            .reject(&:empty?)
      end

      # Remove the <div> region whose opening tag carries +needle+, div
      # nesting respected (the navigationNotes block nests empty divs) —
      # regexes cannot balance, so this walks tag by tag.
      def remove_balanced_div(text, needle)
        open_at = text.enum_for(:scan, /<div[^>]*>/i)
                      .find { ::Regexp.last_match(0).include?(needle) } &&
                  ::Regexp.last_match.begin(0)
        return text if open_at.nil?

        depth = 0
        scanner = text[open_at..].enum_for(:scan, %r{<div[^>]*>|</div>}i)
        scanner.each do
          match = ::Regexp.last_match
          depth += match[0].start_with?("</") ? -1 : 1
          if depth.zero?
            close_at = open_at + match.end(0)
            return text[...open_at] + text[close_at..]
          end
        end
        text # unbalanced markup: leave it, the tag strip degrades gracefully
      end

      # A paragraph that is nothing but links, punctuation and whitespace is
      # navigation furniture (prev/next rows, volume lists), never text.
      def link_only_paragraph?(paragraph)
        return false unless paragraph.include?("[[")

        paragraph.gsub(/\[\[[^\[\]]*\]\]/, "")
                 .gsub(%r{</?[a-z][^>]*>}i, "")
                 .gsub(/[[:punct:][:space:]←→・]/, "")
                 .empty?
      end

      def finish_expanded_paragraph(paragraph)
        cleaned = paragraph.gsub(/\[https?:[^\]\s]*\s+([^\]]*)\]/) { ::Regexp.last_match(1) }
                           .gsub(/\[https?:[^\]\s]*\]/, "")
                           .gsub(/\[\[([^\]|]*\|)?([^\]]*)\]\]/) { ::Regexp.last_match(2) }
                           .gsub(%r{</?[a-z][^>]*>}i, "")
                           .gsub("​", "")
                           .gsub(/\s*\n\s*/, "")
                           .strip
        Nabu::Normalize.nfc(cleaned)
      end

      def prose_paragraphs(wikitext)
        body = strip_header_templates(wikitext)
        body = strip_inline_templates(body)
        body = body.gsub(/\[\[Category:[^\]]*\]\]/i, "")
                   .gsub(/\[\[([^\]|]*\|)?([^\]]*)\]\]/) { ::Regexp.last_match(2) }
                   .gsub(/<!--.*?-->/m, "")
                   .gsub(%r{</?[a-z][^>]*>}i, "")
        body.split(/\n{2,}/)
            .map { |paragraph| Nabu::Normalize.nfc(paragraph.gsub(/\s*\n\s*/, "").strip) }
            .reject(&:empty?)
      end

      # Top-of-page braced blocks ({{header}}, {{other versions}}) and
      # bottom furniture ({{PD-…}}, {{DEFAULTSORT}}) — brace-balanced
      # removal of every {{…}} that fills a whole line region.
      def strip_header_templates(wikitext)
        wikitext.gsub(/^\{\{(?:[^{}]|\{\{[^{}]*\}\})*\}\}\s*$/m, "")
      end

      # Inline template policy (censused over the cone): ruby keeps the
      # base text; iteration-mark templates render their character;
      # editorial {{smaller|〔…〕}} glosses strip (modern apparatus);
      # any other inline template renders its LAST argument (the
      # display form by MediaWiki convention), or nothing when bare.
      def strip_inline_templates(text)
        result = text.to_s
        3.times do # nested templates resolve inside-out
          result = result.gsub(/\{\{([^{}]*)\}\}/) do
            body = ::Regexp.last_match(1)
            name, *args = body.split("|")
            name = name.to_s.strip
            case name
            when "r", "ruby", "ルビ" then args.first.to_s
            # {{*|やけイ}} is a marginal variant note (校異 apparatus) on the
            # Page:-namespace scans — modern-edition machinery, never text.
            when "smaller", "*" then ""
            else
              name.match?(/\A[〱〲〳〴〵]\z/) ? name : args.last.to_s
            end
          end
        end
        result
      end

      # -- the 万葉集 block grammar ------------------------------------------

      def manyo_document(document_ref, envelope, wikitext)
        document = document_for(document_ref, envelope, language: MANYO_LANGUAGE)
        sequence = 0
        seen = Hash.new(0)
        wikitext.split(/^(?=\[歌番号\])/).each do |block|
          fields = manyo_fields(block)
          # The corpus's own poem id VERBATIM — variant verses carry
          # their own letter suffix ("03/0235S", the 或本歌 beside
          # 03/0235; stripping it collides URNs, censused live on
          # 万葉集/第三巻). Any residual repeat takes the house :b2
          # positional disambiguator (the rem/ddbdp precedent).
          number = fields["歌番号"].to_s[%r{[0-9A-Za-z/]+}]
          original = fields["原文"]
          next if number.nil? || original.nil? || original.empty?

          seen[number] += 1
          number = "#{number}:b#{seen[number]}" if seen[number] > 1
          sequence += 1
          document << manyo_passage(document_ref, number, original, fields, sequence)
        end
        raise ParseError, "#{document_ref.id}: no 歌 blocks extracted" if document.empty?

        document
      end

      def manyo_fields(block)
        fields = {}
        block.each_line do |line|
          match = MANYO_FIELD.match(line) or next
          value = match[2].gsub(%r{</?[a-z][^>]*>}i, "").strip
          fields[match[1]] = Nabu::Normalize.nfc(value)
        end
        fields
      end

      def manyo_passage(document_ref, number, original, fields, sequence)
        annotations = {
          "kundoku" => fields["訓読"],
          "kana" => fields["仮名"],
          "heading" => fields["題詞"],
          "left_note" => (fields["左注"] unless fields["左注"].to_s == "なし")
        }.compact.reject { |_, value| value.empty? }
        Nabu::Passage.new(
          urn: "#{document_ref.id}:#{number}", language: MANYO_LANGUAGE,
          text: original, sequence: sequence, annotations: annotations
        )
      end
    end
  end
end
