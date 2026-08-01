# frozen_string_literal: true

require "json"

module Nabu
  module Adapters
    # Sefaria — the Targum shelf (P30-3) + the Rabbinic text core (P46-1)
    # + the midrash shelves (P55-3).
    # Sefaria-Export was RESTRUCTURED upstream: the git repo is a
    # lightweight monthly index (books.json, 19,705 version entries / 6,456
    # titles at the pinned 2026-07-02 generation) and the texts live in a
    # public ~26 GB GCS bucket that is never fetched wholesale. Scope is
    # the PINNED SHELF TABLE (SHELVES below): category-path prefixes,
    # per-shelf language rulings, and named-version fetch selection.
    #
    # == The shelves (owner-ratified wave 1, censused 2026-07-25)
    #
    # - targum (P30-3, FROZEN): every named version under Tanakh/Targum —
    #   Onkelos, Jonathan, the Writings targums, Neofiti, Jerusalem, Sheni.
    #   URNs and behavior byte-frozen (synced 2026-07-19).
    # - mishnah: Mishnah/Seder * — he: Vilna/Romm 1913 + Torat Emet 357 +
    #   Kaufmann MS (189 files); en: Kulp + SCT + Open Mishnah (149).
    # - bavli: Talmud/Bavli/Seder * — he: Wikisource Talmud Bavli (37
    #   tractates) + the Davidson nc lane (Aramaic ×37, Vocalized Aramaic
    #   ×37); en: SCT (36 partial) + Davidson English (×37; the lane's 38th,
    #   Yerushalmi Shekalim, rides the yerushalmi shelf below).
    # - bavli-minor: Talmud/Bavli/Minor Tractates — Vilna 1883 (14) +
    #   Cohen Soncino (14) + SCT (11).
    # - yerushalmi: Talmud/Yerushalmi/Seder * + the Guggenheimer Notes
    #   volume under /Commentary — Guggenheimer edition (he ×39) and
    #   translation (en ×40) + Davidson English Shekalim (whose FILE says
    #   license "unknown" — the per-file gate excludes it at discovery).
    #   Venice/Mechon-Mamre are not named versions → never fetched.
    # - tosefta: Tosefta/*/Seder * — he: the Lieberman codex-Vienna text
    #   (versionTitle carries upstream's own double "to", verbatim; ×33);
    #   en: SCT (×72).
    #
    # == The midrash shelves (P55-3 wave 2, censused 2026-07-31)
    #
    # - rabbah: Midrash/Aggadah/Midrash Rabbah EXACTLY (the Commentary
    #   sub-subtrees — Etz Yosef, Matnot Kehunah, Maharzu … — are out) —
    #   the ten classical collections: he Torat Emet ("Midrash Rabbah --
    #   TE" ×10, per-file MIXED licensing: some files PD, some "unknown" —
    #   the gate censuses); en The Sefaria Midrash Rabbah 2022 (×10,
    #   CC-BY) + SCT (×10). "Ruth Rabbah (Lerner)" duplicates the Ruth
    #   title → EXCLUDED_TITLES.
    # - midrash-halakhah: Midrash/Halakhah EXACTLY — the tannaitic halakhic
    #   midrashim (both Mekhiltas, Sifra, Sifrei Bamidbar/Devarim/Zuta,
    #   Midrash Tannaim): he principal editions ×6 (Sifra's only Hebrew,
    #   Venice 1545, says license "unknown" in its file → not named); en
    #   SCT ×6 + Silverstein ×4 + Lauterbach + Jaffee. The "Footnotes on
    #   Mekhilta DeRabbi Shimon Ben Yochai" apparatus title shares the
    #   Hoffman versionTitle → EXCLUDED_TITLES.
    # The FLAT Midrash/Aggadah bucket (Pesikta DeRav Kahana, Tanchuma,
    # Pirkei DeRabbi Eliezer … shelved beside Yalkut Shimoni, Otzar
    # Midrashim, Ein Yaakov, Legends of the Jews) is not category-separable
    # into classical midrash vs later anthology — out of wave 2; including
    # any of it is a title-level owner ruling.
    #
    # Commentary/Rishonim/Acharonim/Guides subtrees are out of every
    # shelf's category scope by rule.
    #
    # == fetch (the P30-3 index-driven shape, Nabu::SefariaFetch)
    #
    # GET the index, select the shelf table's NAMED versions (.shelf_entry?
    # — merged files and Tafsir Rasag never leave the bucket), GET exactly
    # those files (the wave is ~750 files / ~180 MB — SefariaFetch stages
    # to a tempdir spool, never in memory). The index rides in canonical so
    # the scope is reproducible; attic + mass-deletion breaker as
    # everywhere. The fetch pin is the index body's sha256.
    #
    # == Identity (FROZEN minting)
    #
    # Document per title/version. The targum shelf keeps its P30-3 urns:
    # urn:nabu:sefaria:<title-slug>:<versionTitle-slug>. Every later shelf
    # adds the upstream language-axis value as a segment —
    # urn:nabu:sefaria:<title-slug>:<he|en>:<versionTitle-slug> — because
    # the corpus holds 3 title/versionTitle pairs that appear in BOTH
    # language dirs (Ein Yaakov Glick, Otzar Midrashim NY 1915, Tosefta
    # Menachot Feuer). Passage per section: <doc-urn>:<citation> (daf.amud
    # on the Bavli shelves — SefariaJsonParser.daf_citation). Discovery is
    # GLOB-DRIVEN over the fetched version files — each file is
    # self-describing (title/versionTitle/license/categories ride beside
    # the text), so the attic rediscovers without an index. Minting is
    # frozen once used (standing rule).
    #
    # == THE LICENSE GATE (per-version, machine-readable)
    #
    # The index carries NO license field — the gate lives in each version
    # file. Pinned in tests:
    # - Public Domain / literal "PD" (the Kaufmann MS spelling; owner
    #   ruling D46-f) / CC0 → the source class (open); CC-BY/CC-BY-SA →
    #   license_override "attribution"; CC-BY-NC/CC-BY-NC-SA → "nc" (the
    #   P10-4 mechanics — the Davidson lane; nc documents are MCP-excluded
    #   downstream).
    # - "unknown" or an ABSENT field is not a grant → skipped by rule,
    #   censused, never a ref (known: one Kaufmann file — Pirkei Avot —
    #   and the Davidson Yerushalmi Shekalim English).
    # - merged.json files carry NO license field → NEVER ingested; the
    #   fetch selector also never downloads them.
    # - any OTHER license string stops discovery loudly (Nabu::FetchError).
    #
    # == Languages (per-shelf rulings; owner-ratified D46-e)
    #
    # Sefaria's site axis is he/en; each shelf rules what its columns
    # honestly are: targum he→arc (axis-keyed, the frozen P26-3/P30-3
    # ruling; Tafsir Rasag excluded by rule), mishnah + tosefta + the two
    # midrash shelves he→hbo (tannaitic/rabbinic Hebrew matrix),
    # bavli + bavli-minor + yerushalmi he→arc, en→eng everywhere. hbo and
    # arc are both NFC-EXEMPT (byte-verbatim — protects niqqud). The
    # post-Targum shelves key the ruling on the file's actualLanguage: the
    # corpus carries he-axis files in ar/yi and en-axis files in
    # de/fr/pt/es/ru/hu — an unmapped actualLanguage mints a ref that
    # QUARANTINES at parse (Nabu::ParseError, loud, journaled), never a
    # silently mislabeled document.
    class Sefaria < Nabu::Adapter
      INDEX_URL = "https://raw.githubusercontent.com/Sefaria/Sefaria-Export/master/books.json"

      MERGED_VERSION = "merged"

      # Titles excluded whole even inside shelf scope: Tafsir Rasag (in the
      # Targum category, not an Aramaic targum — see class note); the
      # Footnotes apparatus volume that shares the Hoffman Mekhilta
      # versionTitle; the Lerner critical edition that duplicates the Ruth
      # Rabbah title (its SCT translation would ride the shelf-wide SCT
      # naming otherwise).
      EXCLUDED_TITLES = ["Tafsir Rasag", "Footnotes on Mekhilta DeRabbi Shimon Ben Yochai",
                         "Ruth Rabbah (Lerner)"].freeze

      # Machine-readable license → our class enum. "unknown"/absent → nil
      # (skip by rule); any other unlisted string is a LOUD STOP.
      LICENSE_CLASSES = {
        "Public Domain" => "open",
        "PD" => "open", # the Kaufmann MS spelling — owner ruling D46-f
        "CC0" => "open",
        "CC-BY" => "attribution",
        "CC-BY-SA" => "attribution",
        "CC-BY-NC" => "nc",
        "CC-BY-NC-SA" => "nc"
      }.freeze
      NON_GRANTS = [nil, "unknown"].freeze

      URN_PREFIX = "urn:nabu:sefaria:"

      # One pinned shelf: +prefix+ the categories prefix; +division+ a
      # Regexp the category at +division_index+ must match (nil = whole
      # subtree — targum only); +languages+ the shelf's axis ruling;
      # +ruled_by+ :axis (targum — frozen) or :actual_language (D46-e);
      # +urn_axis+ whether urns carry the axis segment; +fetch_versions+
      # the named-version fetch selection per index axis (nil = every
      # named version — targum only).
      Shelf = Data.define(:id, :prefix, :division_index, :division, :languages,
                          :ruled_by, :urn_axis, :fetch_versions) do
        def categories?(categories)
          return false unless categories.is_a?(Array) && categories[0, prefix.size] == prefix

          division.nil? || categories[division_index].to_s.match?(division)
        end

        def fetch_version?(entry)
          fetch_versions.nil? || fetch_versions.fetch(entry["language"], []).include?(entry["versionTitle"])
        end
      end

      # THE PINNED SHELF TABLE (see the class note; census dry-run against
      # the pinned 2026-07-02 index: 118 targum + 634 open-lane + 112
      # Davidson-nc wave-1 files; wave 2 adds 48 midrash files — 30 rabbah
      # + 18 midrash-halakhah, censused 2026-07-31). Named versions are
      # index versionTitles VERBATIM — including upstream's double "to" in
      # the Lieberman Tosefta and its filing of Lauterbach's Mekhilta
      # translation under Mekhilta DeRabbi Shimon Ben Yochai.
      SHELVES = [
        Shelf.new(id: "targum", prefix: %w[Tanakh Targum], division_index: nil, division: nil,
                  languages: { "he" => "arc", "en" => "eng" }, ruled_by: :axis, urn_axis: false,
                  fetch_versions: nil),
        Shelf.new(id: "mishnah", prefix: %w[Mishnah], division_index: 1, division: /\ASeder\b/,
                  languages: { "he" => "hbo", "en" => "eng" }, ruled_by: :actual_language, urn_axis: true,
                  fetch_versions: {
                    "Hebrew" => ["Mishnah, ed. Romm, Vilna 1913", "Torat Emet 357",
                                 "Mishnah based on the Kaufmann manuscript, edited by Dan Be'eri"],
                    "English" => ["Mishnah Yomit by Dr. Joshua Kulp", "Sefaria Community Translation",
                                  "Open Mishnah"]
                  }),
        Shelf.new(id: "bavli", prefix: %w[Talmud Bavli], division_index: 2, division: /\ASeder\b/,
                  languages: { "he" => "arc", "en" => "eng" }, ruled_by: :actual_language, urn_axis: true,
                  fetch_versions: {
                    "Hebrew" => ["Wikisource Talmud Bavli", "William Davidson Edition - Aramaic",
                                 "William Davidson Edition - Vocalized Aramaic"],
                    "English" => ["Sefaria Community Translation", "William Davidson Edition - English"]
                  }),
        Shelf.new(id: "bavli-minor", prefix: %w[Talmud Bavli], division_index: 2,
                  division: /\AMinor Tractates\z/,
                  languages: { "he" => "arc", "en" => "eng" }, ruled_by: :actual_language, urn_axis: true,
                  fetch_versions: {
                    "Hebrew" => ["Talmud Bavli, Vilna 1883 ed."],
                    "English" => ["The Minor Tractates of the Talmud, trans. A. Cohen, London " \
                                  "Soncino Press, 1965", "Sefaria Community Translation"]
                  }),
        Shelf.new(id: "yerushalmi", prefix: %w[Talmud Yerushalmi], division_index: 2,
                  division: /\ASeder\b|\ACommentary\z/,
                  languages: { "he" => "arc", "en" => "eng" }, ruled_by: :actual_language, urn_axis: true,
                  fetch_versions: {
                    "Hebrew" => ["The Jerusalem Talmud, edition by Heinrich W. Guggenheimer. " \
                                 "Berlin, De Gruyter, 1999-2015"],
                    "English" => ["The Jerusalem Talmud, translation and commentary by Heinrich W. " \
                                  "Guggenheimer. Berlin, De Gruyter, 1999-2015",
                                  "William Davidson Edition - English"]
                  }),
        Shelf.new(id: "tosefta", prefix: %w[Tosefta], division_index: 2, division: /\ASeder\b/,
                  languages: { "he" => "hbo", "en" => "eng" }, ruled_by: :actual_language, urn_axis: true,
                  fetch_versions: {
                    "Hebrew" => ["The Tosefta according to to codex Vienna. Third Augmented " \
                                 "Edition, JTS 2001"],
                    "English" => ["Sefaria Community Translation"]
                  }),
        # THE P55-3 MIDRASH WAVE (wave 2). Both shelves scope to their EXACT
        # category path — /\A\z/ pins "no level past the prefix", which is
        # what keeps the Commentary subtrees out. The flat Midrash/Aggadah
        # bucket (Pesikta, Tanchuma, Pirkei DeRabbi Eliezer … beside Yalkut
        # Shimoni, Otzar Midrashim, Ein Yaakov, Legends of the Jews) is NOT
        # category-separable into classical vs later — out of wave 2 by
        # rule; cutting it needs a title-level owner ruling.
        Shelf.new(id: "rabbah", prefix: ["Midrash", "Aggadah", "Midrash Rabbah"], division_index: 3,
                  division: /\A\z/,
                  languages: { "he" => "hbo", "en" => "eng" }, ruled_by: :actual_language, urn_axis: true,
                  fetch_versions: {
                    "Hebrew" => ["Midrash Rabbah -- TE"],
                    "English" => ["The Sefaria Midrash Rabbah, 2022", "Sefaria Community Translation"]
                  }),
        Shelf.new(id: "midrash-halakhah", prefix: %w[Midrash Halakhah], division_index: 2,
                  division: /\A\z/,
                  languages: { "he" => "hbo", "en" => "eng" }, ruled_by: :actual_language, urn_axis: true,
                  fetch_versions: {
                    # Sifra's only Hebrew version (Venice 1545) says license
                    # "unknown" IN ITS FILE — known-unknown versions are not
                    # named (the Yerushalmi Venice rule): Sifra rides
                    # English-only until upstream licenses the Hebrew.
                    "Hebrew" => ["Mechilta de-Rabbi Simon b. Jochai, Dr. D. Hoffman, Frankfurt 1905",
                                 "Beeri Edition, Koren, Jerusalem, 2019", "Wikisource",
                                 "Sifre on Deuteronomy, ed. Dr. Louis Finkelstein. JTS, 1969",
                                 "Leipzig, 1917", "Berlin, 1908"],
                    "English" => ["Sefaria Community Translation", "Lauterbach",
                                  "Mechilta, translated by Rabbi Shraga Silverstein",
                                  "Sifra by Rabbi Shraga Silverstein",
                                  "Sifrei by Rabbi Shraga Silverstein",
                                  "Trans. by Marty Jaffee, 2015"]
                  })
      ].freeze

      # One discovery walk's yield: refs for licensed named versions, the
      # rule-skip count, and unrecognized notes for unreadable files.
      ScanResult = Data.define(:refs, :skipped, :notes)

      MANIFEST = Nabu::SourceManifest.new(
        id: "sefaria",
        name: "Sefaria — Targum shelf + Rabbinic core (Mishnah, Bavli, Minor Tractates, Yerushalmi, " \
              "Tosefta) + Midrash (Rabbah, halakhic midrashim)",
        license: "Per NAMED version, machine-readable \"license\" field in each version file (the index " \
                 "carries none): PD (both spellings)/CC0 -> open, CC-BY/CC-BY-SA -> attribution override, " \
                 "CC-BY-NC(-SA) -> nc override (the Davidson lane; MCP-excluded); \"unknown\"/absent -> " \
                 "never ingested; merged.json carries no license field and is never fetched or ingested",
        license_class: "open",
        upstream_url: "https://github.com/Sefaria/Sefaria-Export",
        parser_family: "sefaria-json"
      )

      def self.manifest
        MANIFEST
      end

      # The shelf whose scope covers these categories (nil = off-shelf).
      # bavli/bavli-minor share a prefix and split on the division pattern,
      # so first-match is unambiguous.
      def self.shelf_for(categories)
        SHELVES.find { |shelf| shelf.categories?(categories) }
      end

      # The fetch selector: NAMED versions of the shelf table only. Kept a
      # class method so tests pin the scope rule without a network shape.
      def self.shelf_entry?(entry)
        return false unless entry["json_url"].is_a?(String)
        return false if entry["versionTitle"] == MERGED_VERSION || EXCLUDED_TITLES.include?(entry["title"])

        shelf = shelf_for(entry["categories"])
        !shelf.nil? && shelf.fetch_version?(entry)
      end

      # One DocumentRef per licensed named version file under json/, sorted
      # by urn. A workdir without the tree yields nothing (the day-one
      # pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        scan(workdir).refs.sort_by(&:id).each(&block)
      end

      # P11-7 discovery census: merged files, non-grant licenses ("unknown"/
      # absent), excluded titles and off-shelf categories are explicit rule
      # skips; a version file that does not parse as JSON is unrecognized —
      # loud, a fetch defect.
      def discovery_skips(workdir)
        result = scan(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: result.skipped, unrecognized: result.notes.size, notes: result.notes
        )
      end

      def parse(document_ref)
        metadata = document_ref.metadata
        if (unmapped = metadata["unmapped_language"])
          raise ParseError,
                "#{document_ref.path}: unmapped actualLanguage #{unmapped.inspect} on the " \
                "#{metadata['shelf']} shelf — excluded loudly by rule (owner ruling D46-e); " \
                "extending Sefaria::SHELVES is an owner decision"
        end

        SefariaJsonParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: metadata.fetch("language"),
          metadata: document_metadata(metadata),
          license_override: metadata["license_override"]
        )
      end

      def fetch(workdir, progress: nil, force: false)
        result = SefariaFetch.sync!(
          index_url: index_url, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          select: self.class.method(:shelf_entry?), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue SefariaFetch::Error => e
        raise FetchError, "sefaria fetch failed: #{e.message}"
      end

      private

      # Split out so tests can point a singleton at a stubbed index (the
      # house pattern), keeping fetch off the network.
      def index_url
        INDEX_URL
      end

      def fetch_notes(result)
        notes = ["#{result.downloaded} file(s) downloaded"]
        notes << attic_notes(result.atticked) unless result.atticked.empty?
        notes.join("; ")
      end

      # One walk of json/**/*.json (see ScanResult).
      def scan(workdir)
        refs = []
        skipped = 0
        notes = []
        Dir.glob(File.join(workdir, "json", "**", "*.json")).each do |path|
          data = read_version(path)
          shelf = data && self.class.shelf_for(data["categories"])
          if data.nil?
            notes << "#{relative(workdir, path)}: not a JSON version object (fetch defect?)"
          elsif skip_by_rule?(data, shelf)
            skipped += 1
          else
            refs << ref_for(path, data, shelf)
          end
        end
        ScanResult.new(refs: refs, skipped: skipped, notes: notes)
      end

      def read_version(path)
        parsed = JSON.parse(File.read(path))
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end

      # merged files, excluded titles, off-shelf categories, and versions
      # without a machine-readable grant. An unmapped license STRING is not
      # a skip — it stops discovery loudly (see the class note); the gate
      # only rests where the metadata genuinely carries no grant.
      def skip_by_rule?(data, shelf)
        return true if data["versionTitle"] == MERGED_VERSION || data.key?("versions")
        return true if EXCLUDED_TITLES.include?(data["title"]) || shelf.nil?

        NON_GRANTS.include?(data["license"])
      end

      def ref_for(path, data, shelf)
        license_class = license_class!(path, data)
        language, unmapped = resolve_language(path, data, shelf)
        Nabu::DocumentRef.new(
          source_id: manifest.id,
          id: urn(data, shelf),
          path: File.expand_path(path),
          metadata: {
            "language" => language,
            "unmapped_language" => unmapped,
            "shelf" => shelf.id,
            "license_override" => license_class == manifest.license_class ? nil : license_class,
            "title" => data["title"],
            "version_title" => data["versionTitle"],
            "license" => data["license"],
            "categories" => data["categories"],
            "he_title" => data["heTitle"],
            "version_source" => data["versionSource"]
          }.compact
        )
      end

      def urn(data, shelf)
        segments = [SefariaJsonParser.slug(data["title"])]
        segments << SefariaJsonParser.slug(data["language"]) if shelf.urn_axis
        segments << SefariaJsonParser.slug(data["versionTitle"])
        "#{URN_PREFIX}#{segments.join(':')}"
      end

      def license_class!(path, data)
        LICENSE_CLASSES.fetch(data["license"]) do
          raise Nabu::FetchError,
                "sefaria: #{path}: unrecognized license #{data['license'].inspect} — map it in " \
                "Sefaria::LICENSE_CLASSES (owner decision) before syncing"
        end
      end

      # [nabu language, unmapped ruling key]. The targum shelf keys its
      # ruling on the site axis (frozen P30-3 behavior — unmapped stops
      # discovery loudly); later shelves key on actualLanguage (falling
      # back to the axis when absent) and defer the loud stop to parse so
      # ONE odd file quarantines instead of killing the sync (D46-e).
      def resolve_language(path, data, shelf)
        key = shelf.ruled_by == :axis ? data["language"] : data["actualLanguage"] || data["language"]
        language = shelf.languages[key]
        if language.nil? && shelf.ruled_by == :axis
          raise Nabu::FetchError,
                "sefaria: #{path}: unknown upstream language #{data['language'].inspect} — the shelf " \
                "ruling maps he->arc and en->eng only (owner decision before syncing anything else)"
        end

        language.nil? ? [nil, key.to_s] : [language, nil]
      end

      def relative(workdir, path)
        File.expand_path(path).delete_prefix("#{File.expand_path(workdir)}#{File::SEPARATOR}")
      end

      # Document-level metadata: shelf provenance verbatim plus the
      # subshelf/division facets — the two category levels past the shelf's
      # prefix (targum: ["Tanakh", "Targum", <subshelf>, <division?>], the
      # P30-3 shape byte-unchanged; mishnah: [<seder>]; bavli/yerushalmi:
      # [<seder>]; tosefta: [<edition>, <seder>]).
      def document_metadata(metadata)
        categories = metadata["categories"] || []
        base = self.class.shelf_for(categories)&.prefix&.size || 2
        facets = { "subshelf" => facet(categories[base]), "division" => facet(categories[base + 1]) }.compact
        {
          "title" => metadata["title"],
          "version_title" => metadata["version_title"],
          "license" => metadata["license"],
          "categories" => categories.empty? ? nil : categories,
          "he_title" => metadata["he_title"],
          "version_source" => metadata["version_source"],
          "facets" => facets.empty? ? nil : facets
        }.compact
      end

      def facet(value)
        value.nil? ? nil : { "value" => SefariaJsonParser.slug(value), "raw" => value }
      end
    end
  end
end
