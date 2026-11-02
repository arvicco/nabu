# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

require_relative "ganjoor_sqlite_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # Ganjoor (ganjoor.net) — the Persian poetry reference library: the
    # classical poets from Rudaki and Ferdowsi through Saʿdi, Rumi and
    # Hafez to the Safavid and Qajar divans, digitized, proofread and
    # published by the Ganjoor project, and shipped whole as ONE SQLite
    # database in the desktop application's GitHub release. This adapter
    # takes the CLASSICAL CONE of it (below).
    #
    # == Upstream's delivery grains (census 2026-11-02, release 1405-07-03)
    #
    # The release zip (ganjoor-db-14050703.zip, 120,291,780 B) holds one
    # member, ganjoor.s3db (360,688,640 B): 281 poets · 2,511 cats (the
    # work/section tree) · 140,497 poems · 3,223,069 verse rows (one per
    # hemistich or paragraph) — schema in GanjoorSqliteParser.
    # - poem → THE DOCUMENT GRAIN: urn:nabu:ganjoor:<poet slug>:<poem id>
    #   (Ganjoor's own poem id — the site's id too — under the poet's URL
    #   slug from the root cat: hafez, saadi, moulavi …).
    # - verse rows → grouped into the PASSAGE grain, the couplet (bayt —
    #   the unit Ganjoor counts and cites), plus band couplets, single
    #   lines and prose paragraphs; passage urn <doc>:<ordinal>.
    # - poet / cat rows → mined into document metadata, never documents.
    # - comment rows (position 5, 1,710) → document metadata "comments",
    #   never passages (editorial notes, not text).
    # - the desktop app's fav/gil/poemsnd/sndsync tables → empty in the
    #   release; gver → the schema version. Never read.
    # - the site's poets endpoint (api.ganjoor.net/api/ganjoor/poets, 243
    #   records) → fetched beside the database as api/poets.json: the
    #   database carries NO dates or places for its poets; the endpoint
    #   carries lunar-Hijri birth/death years (all 243), birth/death places
    #   and coordinates — and is the site's own list of PUBLISHED poets.
    #
    # == The classical cone: discovery rules (each counted, never silent)
    #
    # 1. unpublished — the poem's poet has no endpoint record: 41 poets,
    #    5,178 poems (the 20th-century and contemporary poets in the 500s
    #    and 600s, Hedayat, the modern Persian Avesta and Qurʾān
    #    renderings — no URLs either: the site does not serve them).
    # 2. modern tail — the poet died in or after MODERN_FROM_AH = 1324 AH
    #    (1906 CE, the Constitutional Revolution — the conventional start
    #    of modern Persian literature): 28 poets, 9,144 poems, out this
    #    phase because their underlying author rights are the remaining
    #    caution. Everything accepted died 120+ years ago. A poet record
    #    without a death year would be modern by default (none exists).
    # 3. no text — a poem with no non-blank, non-comment verse row: 10.
    # Reconciliation: 126,165 accepted + 5,178 + 9,144 + 10 = 140,497, the
    # release's poem row count exactly; 212 accepted poets + 28 modern + 3
    # endpoint poets absent from the (older) release = the 243 records.
    # Expected first sync: 126,165 documents / 1,453,355 passages.
    # Upstream's headline "1,528,993 bayts" (ganjoor.net/vazn, 2026-10-31)
    # counts the whole published site, modern poets included.
    #
    # == Language
    #
    # fas (the house code; the codemap folds it onto the registry's fa
    # anchor — the registry holds no Persian stages yet, so the bare code
    # is the honest claim). A poem under a section whose label names
    # Arabic (اشعار عربی, قصاید و قطعات عربی, نامه‌های عربی …; never a
    # mulammaʿ — macaronic — section) is ara. Declared COARSE: the few
    # dozen Turkic, Kurdish, Gilaki and fahlavi (dialect) sections stay
    # fas — their labels are mined (section_path) but no code is guessed.
    # Text is NFC at this boundary — upstream's vocalized Arabic carries
    # shadda+vowel in non-NFC order.
    #
    # == Mined axes
    #
    # Dating: the poet's life from the endpoint — CE(birth AH)..CE(death
    # AH) by the house tabular conversion (OpenitiDates.ce_year), class
    # composition (the diccas author-life precedent; upstream's own
    # validBirthDate/validDeathDate=false marks an approximate year "c."
    # in raw). An inconsistent record (birth after death — one poet)
    # keeps only the death bound. Places: the poet's DEATH place (name +
    # coordinates when non-zero) — where the poet worked, the openiti
    # died/resided stance; the birth place rides metadata as biography.
    # Kind: the poem's own section label (metadata "form": غزلیات,
    # رباعیات, قصاید …) folds through config/kind_map.yml. The poet's long
    # biography (poet.description) is NOT copied onto 126k documents —
    # it is per-poet prose, not an axis; the dossier and the site carry it.
    #
    # == License
    #
    # Redistribution and reuse granted by the site operator by email,
    # 2026-11-02: "Redistribution of ganjoor contents is permitted and
    # ganjoor data is free to reuse." → class attribution; Ganjoor is
    # credited as the digitizer on every surface (manifest credit).
    #
    # == fetch / sync policy
    #
    # The release zip is PINNED (URL + sha256): GitHub release assets are
    # immutable, a new Ganjoor release is an adapter edit (bump both), and
    # a body missing the pin refuses before the tree mutates. ZipFetch
    # streams it (the OpenITI mode) and unpacks ganjoor.s3db into the
    # workdir root; the poets endpoint lands via FileFetch under api/
    # (kept out of the zip's tree swap). Both arms prepare before either
    # tree changes. The workdir is not a git tree, so nothing needs a
    # materialized_paths declaration (the openiti zip+sidecar shape).
    # sync_policy manual.
    class Ganjoor < Nabu::Adapter
      RELEASE_URL = "https://github.com/ganjoor/desktop/releases/download/v3.1/ganjoor-db-14050703.zip"
      RELEASE_SHA256 = "cfd74499d8397b197d67433d1a92d7676a3fb09057e5eaf85dd42ec8c6878802"
      POETS_URL = "https://api.ganjoor.net/api/ganjoor/poets"
      DB_FILENAME = "ganjoor.s3db"
      API_DIRNAME = "api"
      POETS_FILENAME = "poets.json"
      URN_PREFIX = "urn:nabu:ganjoor:"
      LANGUAGE = "fas"
      ARABIC = "ara"
      MODERN_FROM_AH = 1324
      ARABIC_SECTION = /عربی/
      MACARONIC_SECTION = /ملمع/
      BREADCRUMB = " » "

      MANIFEST = Nabu::SourceManifest.new(
        id: "ganjoor",
        name: "Ganjoor — the Persian poetry library (classical poets)",
        license: "Reuse and redistribution granted by the site operator (ganjoor.net), permission granted " \
                 "by email, 2026-11-02: \"Redistribution of ganjoor contents is permitted and ganjoor data is " \
                 "free to reuse.\" Credit Ganjoor (ganjoor.net) as the digitizer",
        license_class: "attribution",
        upstream_url: "https://ganjoor.net",
        parser_family: "ganjoor-sqlite",
        credit: "Ganjoor (ganjoor.net) — digitization and proofreading"
      )

      def self.manifest = MANIFEST

      # HEAD the pinned release asset for reachability; the endpoint
      # snapshot's Last-Modified pin rides its own state file.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "ganjoor-db release", zip_url: RELEASE_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # -- the rules (class methods so tests pin each one) ------------------

      # The modern tail: died in/after MODERN_FROM_AH, or undated.
      def self.modern?(record)
        death = record["deathYearInLHijri"]
        death.nil? || death >= MODERN_FROM_AH
      end

      # The poet's life as the :structured date hash, class composition.
      def self.life_date(record)
        birth = record["birthYearInLHijri"]
        death = record["deathYearInLHijri"]
        return nil if death.nil? && birth.nil?

        consistent = birth && death && birth <= death
        { "not_before" => (consistent || death.nil?) && birth ? ce(birth) : nil,
          "not_after" => death && ce(death),
          "raw" => life_raw(record),
          "class" => "composition" }.compact
      end

      def self.life_raw(record)
        parts = [["b.", record["birthYearInLHijri"], record["validBirthDate"]],
                 ["d.", record["deathYearInLHijri"], record["validDeathDate"]]]
        life = parts.filter_map { |label, year, valid| year && "#{label} #{'c. ' unless valid}#{year} AH" }
        "poet #{life.join(' – ')} (ganjoor.net poets list)"
      end

      def self.ce(year_ah) = Nabu::Store::TimelineBuilder::OpenitiDates.ce_year(year_ah)

      def initialize(release_sha256: RELEASE_SHA256)
        super()
        @release_sha256 = release_sha256
      end

      # -- discovery --------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        census(workdir)&.fetch(:accepted)&.each(&block)
      end

      def discovery_skips(workdir)
        result = census(workdir)
        return unfetched_skips(workdir) if result.nil?

        notes = result[:skipped].map do |(rule, poet), poems|
          "#{rule}: #{poet}: #{poems.size} poem#{'s' unless poems.size == 1}" \
            "#{" (#{poems.first(5).join(', ')}#{' …' if poems.size > 5})" if rule == 'no text'}"
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: result[:skipped].sum { |_, poems| poems.size },
                                          unrecognized: 0, notes: notes)
      end

      def parse(document_ref)
        reader = reader_for(document_ref.path)
        poem_id = document_ref.metadata.fetch("poem_id")
        poem = reader.poem(poem_id) or raise ParseError, "#{document_ref.path}: no poem #{poem_id}"
        record = reader.record(poem_id)
        build_document(document_ref, poem, record, reader.cat_path(poem.cat_id))
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      # -- fetch ------------------------------------------------------------

      def fetch(workdir, progress: nil, force: false)
        zip = Nabu::ZipFetch.new(url: RELEASE_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
                                 progress: progress, stream: true, keep: [API_DIRNAME])
        poets = Nabu::FileFetch.new(url: POETS_URL, dir: File.join(workdir, API_DIRNAME), filename: POETS_FILENAME,
                                    attic_dir: File.join(workdir, ATTIC_DIRNAME, API_DIRNAME), progress: progress)
        begin
          zip.prepare!
          verify_pin!(zip)
          poets.prepare!
          guard_mass_deletion!(workdir, zip.doomed_paths + poets.doomed_paths, force: force)
          zip.complete!
          poets.complete!
        ensure
          zip.cleanup!
        end
        Nabu::FetchReport.new(sha: zip.sha, fetched_at: Time.now, notes: fetch_notes(zip, poets))
      rescue ZipFetch::Error, FileFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "ganjoor fetch failed into #{workdir}: #{e.message}"
      end

      private

      # -- the census (one pass, memoized per workdir state) -----------------

      # nil before a fetch (no database or no poets snapshot); else
      # { accepted: [DocumentRef…] in poem id order,
      #   skipped: { [rule, "poet (id)…"] => [poem ids] } }.
      def census(workdir)
        db = File.join(workdir, DB_FILENAME)
        snapshot = File.join(workdir, API_DIRNAME, POETS_FILENAME)
        return nil unless File.file?(db) && File.file?(snapshot)

        key = [File.expand_path(db), File.mtime(db), File.size(db), File.mtime(snapshot), File.size(snapshot)]
        return @census if @census_key == key

        @census = run_census(reader_for(db), published_poets(snapshot), db)
        @census_key = key
        @census
      end

      def run_census(reader, published, db)
        accepted = []
        skipped = Hash.new { |hash, k| hash[k] = [] }
        with_text = reader.poem_ids_with_text
        reader.each_poem do |poem|
          poet = reader.poet_for_cat(poem.cat_id)
          rule = skip_rule(poet, published, with_text, poem)
          if rule
            skipped[[rule, poet_label(poet, published)]] << poem.id
          else
            accepted << poem_ref(reader, poem, poet, published.fetch(poet.id), db)
          end
        end
        { accepted: accepted, skipped: skipped }
      end

      def skip_rule(poet, published, with_text, poem)
        record = poet && published[poet.id]
        return "unpublished (no ganjoor.net poets-list record)" if record.nil?
        return "modern tail (died #{record['deathYearInLHijri']} AH ≥ #{MODERN_FROM_AH} AH)" if
          self.class.modern?(record)
        return "no text" unless with_text.include?(poem.id)

        nil
      end

      def poet_label(poet, published)
        return "poet-less cat" if poet.nil?

        record = published[poet.id]
        death = record && record["deathYearInLHijri"]
        "#{poet.name} (#{poet.id})#{", d. #{death} AH" if death}"
      end

      def poem_ref(reader, poem, poet, record, db)
        slug = poet_slug(reader, poet, record) or
          raise ParseError, "#{db}: poet #{poet.id} has no URL slug"
        Nabu::DocumentRef.new(
          source_id: MANIFEST.id, id: "#{URN_PREFIX}#{slug}:#{poem.id}", path: File.expand_path(db),
          metadata: { "poem_id" => poem.id, "poet_id" => poet.id, "poet_slug" => slug }
        )
      end

      # The poet's URL slug: the root cat's URL tail (https://ganjoor.net/hafez),
      # else the endpoint's fullUrl (/hafez).
      def poet_slug(reader, poet, record)
        url = reader.cats[poet.cat_id]&.url.to_s
        slug = url[%r{\Ahttps?://ganjoor\.net/([^/]+)\z}, 1] || record["fullUrl"].to_s.delete_prefix("/")
        slug.empty? || slug.include?("/") ? nil : slug
      end

      # id => endpoint record. A snapshot that is not a list of records is
      # upstream drift: loud.
      def published_poets(path)
        list = JSON.parse(SourceRead.utf8_file(path, label: MANIFEST.id))
        unless list.is_a?(Array) && list.all? { |rec| rec.is_a?(Hash) && rec["id"].is_a?(Integer) }
          raise ParseError, "#{path}: the poets snapshot is not a list of poet records"
        end

        list.to_h { |rec| [rec["id"], rec] }
      rescue JSON::ParserError => e
        raise ParseError, "#{path}: malformed poets snapshot: #{e.message}"
      end

      def unfetched_skips(workdir)
        db = File.join(workdir, DB_FILENAME)
        return Nabu::Adapter::DiscoverySkips.new unless File.file?(db)

        count = reader_for(db).each_poem.count
        Nabu::Adapter::DiscoverySkips.new(
          unrecognized: count,
          notes: ["#{count} poems unaccounted: #{API_DIRNAME}/#{POETS_FILENAME} (the poets snapshot) is missing"]
        )
      end

      # One read-only handle per database file (re-opened when it changes).
      def reader_for(path)
        key = [File.expand_path(path), File.mtime(path), File.size(path)]
        return @reader if @reader_key == key

        @reader&.close
        @reader_key = key
        @reader = GanjoorSqliteParser.new(path)
      end

      # The poets snapshot beside the database, re-read when it changes.
      def snapshot_for(document_ref)
        path = File.join(File.dirname(document_ref.path), API_DIRNAME, POETS_FILENAME)
        key = [path, File.mtime(path), File.size(path)]
        return @snapshot if @snapshot_key == key

        @snapshot_key = key
        @snapshot = published_poets(path)
      end

      # -- the document -----------------------------------------------------

      def build_document(document_ref, poem, record, path)
        poet_record = snapshot_for(document_ref).fetch(document_ref.metadata.fetch("poet_id"))
        sections = path.drop(1).map { |cat| Normalize.nfc(cat.text.to_s.strip) }
        language = sections.any? { |label| arabic_section?(label) } ? ARABIC : LANGUAGE
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, canonical_path: document_ref.path,
          title: [Normalize.nfc(path.first.text.to_s.strip), *sections, Normalize.nfc(poem.title.to_s.strip)]
                 .reject(&:empty?).join(BREADCRUMB),
          metadata: document_metadata(document_ref, poem, record, sections, path, poet_record)
        )
        record.units.each_with_index do |unit, index|
          document << passage(document_ref.id, unit, index, language, document.size)
        end
        raise ParseError, "#{document_ref.id}: no text units" if document.empty?

        document
      end

      def arabic_section?(label) = label.match?(ARABIC_SECTION) && !label.match?(MACARONIC_SECTION)

      def passage(urn, unit, index, language, sequence)
        lines = unit.lines.map { |line| Normalize.nfc(line) }
        annotations = if unit.form == :prose
                        { "kind" => "prose" }
                      else
                        { "kind" => "verse", "form" => unit.form.to_s, "hemistichs" => lines }
                      end
        Nabu::Passage.new(urn: "#{urn}:#{index + 1}", language: language, text: lines.join(" "),
                          annotations: annotations.merge("vorder" => unit.vorders.first), sequence: sequence)
      end

      def document_metadata(document_ref, poem, record, sections, path, poet_record)
        poet = path.first
        {
          "poem_id" => poem.id,
          "url" => poem.url,
          "poet" => Normalize.nfc(poet.text.to_s.strip),
          "poet_full_name" => poet_record["name"] && Normalize.nfc(poet_record["name"].strip),
          "poet_id" => document_ref.metadata.fetch("poet_id"),
          "poet_slug" => document_ref.metadata.fetch("poet_slug"),
          "poet_birth_ah" => poet_record["birthYearInLHijri"],
          "poet_death_ah" => poet_record["deathYearInLHijri"],
          "poet_birth_place" => presence(poet_record["birthPlace"]),
          "poet_death_place" => presence(poet_record["deathPlace"]),
          "work" => sections.first,
          "section_path" => sections,
          "form" => sections.last,
          "text_form" => text_form(record.units),
          "comments" => record.comments.empty? ? nil : record.comments.map { |c| Normalize.nfc(c) },
          "date" => self.class.life_date(poet_record),
          "place" => death_place(poet_record)
        }.compact
      end

      def text_form(units)
        prose, verse = units.partition { |unit| unit.form == :prose }
        return "prose" if verse.empty?

        prose.empty? ? "verse" : "mixed"
      end

      # The toponym-list place shape (the iedc reader): the death place,
      # with coordinates only when the endpoint gives a real pair.
      def death_place(record)
        name = presence(record["deathPlace"]) or return nil

        topo = { "name" => name, "role" => "poet's death place" }
        lat = record["deathPlaceLatitude"]
        lon = record["deathPlaceLongitude"]
        topo.merge!("latitude" => lat, "longitude" => lon) if lat.is_a?(Numeric) && lon.is_a?(Numeric) &&
                                                              !(lat.zero? && lon.zero?)
        [topo]
      end

      def presence(value)
        text = value.to_s.strip
        text.empty? ? nil : Normalize.nfc(text)
      end

      def verify_pin!(zip)
        return if zip.not_modified? || zip.sha == @release_sha256

        raise Nabu::FetchError, "ganjoor: the release zip misses its sha256 pin (got #{zip.sha}, pinned " \
                                "#{@release_sha256}) — refused; a new Ganjoor release is an adapter edit " \
                                "(re-pin RELEASE_URL + RELEASE_SHA256)"
      end

      def fetch_notes(zip, poets)
        [zip.not_modified? ? "release zip not modified (304)" : "#{File.basename(RELEASE_URL)} sha256 pin verified",
         poets.not_modified? ? "poets list not modified (304)" : "poets list snapshot #{poets.sha}",
         attic_notes(zip.atticked + poets.atticked)].compact.join("; ")
      end
    end
  end
end
