# frozen_string_literal: true

require "nokogiri"

require_relative "dharma_epidoc_parser"
require_relative "../timeline"

module Nabu
  module Adapters
    # DHARMA Task Force B — the South Asian epigraphy estate (P118-2): every
    # inscription-edition `tfb-*` repo on github.com/erc-dharma composed into
    # ONE source. Early Inscriptions of Āndhradeśa (EIAD, Prakrit/Sanskrit),
    # Kanaganahalli (Prakrit), Early Western Deccan, Andrew Ollett's
    # Sātavāhana inscriptions data, the Telugu corpus, Kalyāṇa Cālukya
    # (Kannada/Sanskrit), Vengī Cālukya (Sanskrit/Telugu), Maitraka, the
    # Bengal charters and dedications, Dakṣiṇa Kosala, Somavaṁśin, Bādāmi
    # Cālukya and the small dynastic corpora (Arakan, Bhaumakara,
    # Nalodbhava, Nandodbhava, Parivrājaka, Śailodbhava, Tuṅga).
    #
    # Scope (live census 2026-10-11, `gh api orgs/erc-dharma/repos`): 25
    # tfb-* repos. OUT: tfb-ec-epigraphy (Epigraphia Carnatica volumes — a
    # different parser shape) and four repos carrying no edition XML yet
    # (tfb-gangaeast: docx only; tfb-licchavi / tfb-rastrakuta /
    # tfb-visnukundin: an empty xml-provisional/) — a later census adds
    # them to REPOS when editions land.
    #
    # == Identity
    #
    #   urn:nabu:dharma-deccan:<file stem sans "DHARMA_">
    #     (…:INSEIAD00001, …:INSVengiCalukya00099; Ollett's files carry
    #      no prefix: …:Am499, …:N10)
    #   passage: the dharma-epidoc grain — <urn>:<line n> | <urn>:<lg n>.<l n>
    #
    # Stems are unique across all 20 repos (census: 1,713 editions, zero
    # collisions); discover still guards it — a later collision keeps the
    # first repo's file (REPOS order) and censuses the rest as skips.
    #
    # == Parse (the dharma-epidoc family)
    #
    # The family's walk (DharmaEpidocParser) over a pre-pruned DOM: Ollett
    # nests <div type="commentary"> INSIDE 26 editions, and the walk would
    # mint its English prose as Sanskrit text — editorial divs
    # (commentary/translation/apparatus/bibliography) are removed from the
    # edition before the walk. That orchestration is the parser's own
    # #parse, re-composed here on a DOM; the five SEA siblings keep calling
    # the parser unchanged.
    #
    # Languages: per-repo measured allowlists (REPOS[:languages], the
    # full-estate census of every minted xml:lang) plus censused tag dirt
    # (REPOS[:aliases]). Anything else — "unknown-Latn", "und", lang-less
    # editions in these multilingual repos — quarantines loudly.
    #
    # == License
    #
    # The file's OWN <licence> (fileDesc/publicationStmt) governs, its
    # @target recorded verbatim: CC BY-SA 4.0 on the DHARMA files (CC BY
    # 4.0 on some), CC BY 3.0 on 20 of Ollett's. A licence-less file — 433
    # of Ollett's 453 — falls back on its repo's LICENCE.txt (CC BY 4.0,
    # "Attribution 4.0 International"), recorded per document as such
    # (metadata license_basis), never silently. A licence-less file in a
    # repo WITHOUT a LICENCE.txt quarantines (no grant). An EIAD edition's
    # sourceDesc <licence> (the 2017 EIAD edition's CC BY 3.0) rides as
    # license_source_edition. Every variant is class `attribution`.
    #
    # == Mined axes (the aggressive-mining policy)
    #
    # - origDate (Ollett: 367 of 453 dated) → metadata "date" {not_before,
    #   not_after (signed years), raw, precision, cert, evidence} — only
    #   cal:gregorian (the in-text cal:regnal <date>s are regnal years,
    #   never CE).
    # - origPlace (Ollett: 452) → "place" (the placeName), "place_key"
    #   (Ollett's pl: key), "orig_place_text" (the findspot prose).
    # - Vengī Cālukya's own metadata table (DHARMA_mdt_VengiCalukya_v01 -
    #   Text.tsv, fetched in the cone): "Date range CE" / "Date CE" + "Date
    #   evidence" → "date" for 107 texts.
    # - editors (fileDesc/titleStmt editor + respStmt names), maturity
    #   (edition @rendition), repo.
    # DECLARED COARSENESS: the DHARMA working files carry NO origDate or
    # origPlace (census: zero across 1,260 DHARMA_ editions); their titles'
    # date prose is not an extractor. EIAD's inventory comment block
    # ("Original locality") is unstructured XML comment text — not mined.
    # Vengī's conglomerateArtefact.tsv names findspots but carries no text
    # identifier (its text-id column is empty), so a place join would be an
    # inference — deferred. Kanaganahalli's inventory and Śailodbhava's
    # list are .xlsx/.docx (outside the cone; no reader in the budget).
    class DharmaDeccan < Nabu::Adapter
      SLUG = "dharma-deccan"
      ORG_URL = "https://github.com/erc-dharma"
      FILE_PREFIX = "DHARMA_"
      SAN = %w[san-Latn].freeze
      PRA_SAN = %w[pra-Latn san-Latn].freeze

      # The roster (alphabetical — the fetch and collision order). :dir is
      # the edition directory ("" = repo root); :languages the measured
      # minted-code census; :aliases censused tag dirt; :ollett marks the
      # prefix-less Sātavāhana data; :tsv a repo metadata table in the cone.
      REPOS = {
        "tfb-arakan-epigraphy" => { dir: "xml-provisional", languages: SAN },
        "tfb-badamicalukya-epigraphy" => { dir: "xml-provisional", languages: SAN },
        "tfb-bengalcharters-epigraphy" => { dir: "texts", languages: SAN },
        "tfb-bengalded-epigraphy" => { dir: "texts/xml", languages: SAN },
        "tfb-bhaumakara-epigraphy" => { dir: "xml-provisional", languages: SAN },
        "tfb-daksinakosala-epigraphy" => { dir: "texts", languages: SAN },
        "tfb-earlywesterndeccan-epigraphy" => { dir: "xml", languages: PRA_SAN },
        # EIAD 57 tags a ROMANIZED edition "pra-Brah" (its text is Latin
        # transliteration): the held surface is Latin either way (the
        # dharma-javanese-texts "kaw-ban" precedent).
        "tfb-eiad-epigraphy" => { dir: "texts/xml", languages: PRA_SAN,
                                  aliases: { "pra-Brah" => "pra-Latn" } },
        "tfb-kalyanacalukya-epigraphy" => { dir: "xml-provisional", languages: %w[kan-Latn san-Latn] },
        "tfb-kanaganahalli-epigraphy" => { dir: "xml", languages: PRA_SAN },
        "tfb-maitraka-epigraphy" => { dir: "xml-provisional", languages: SAN },
        "tfb-nalodbhava-epigraphy" => { dir: "", languages: SAN },
        "tfb-nandodbhava-epigraphy" => { dir: "", languages: SAN },
        "tfb-parivrajaka-epigraphy" => { dir: "texts/xml", languages: SAN },
        "tfb-sailodbhava-epigraphy" => { dir: "xml", languages: SAN },
        "tfb-satavahana-epigraphy" => { dir: "satavahana-inscriptions-data_Ollett", languages: PRA_SAN,
                                        ollett: true },
        "tfb-somavamsin-epigraphy" => { dir: "texts", languages: SAN },
        # Telugu 18 tags one romanized face bare "tel" (the "kaw-Latin" class).
        "tfb-telugu-epigraphy" => { dir: "texts", languages: %w[tel-Latn san-Latn],
                                    aliases: { "tel" => "tel-Latn" } },
        "tfb-tunga-epigraphy" => { dir: "", languages: SAN },
        "tfb-vengicalukya-epigraphy" => { dir: "xml", languages: %w[san-Latn tel-Latn],
                                          tsv: "DHARMA_mdt_VengiCalukya_v01 - Text.tsv" }
      }.freeze

      # Ollett's data dir also holds an editor (nXML) locating-rules file.
      OLLETT_NON_EDITIONS = %w[schemas.xml].freeze
      DHARMA_EDITION = /\ADHARMA_INS[A-Za-z]+\d+(?:-[A-Za-z0-9]+)?\z/
      EDITORIAL_DIVS = %w[commentary translation apparatus bibliography].freeze
      REPO_LICENCE = "https://creativecommons.org/licenses/by/4.0/"
      REPO_LICENCE_BASIS = "repo LICENCE.txt (CC BY 4.0; no in-file <licence>)"
      TSV_YEAR_RANGE = /\A(\d{1,4})-(\d{1,4})\z/
      TSV_YEAR = /\A(\d{1,4})(?:-\d{2}){0,2}\z/

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "DHARMA Task Force B — South Asian inscriptions (Deccan, Āndhra, Karnataka, " \
                "Odisha, Bengal, Gujarat)",
          license: "per-file <licence> governs, recorded verbatim (CC BY-SA 4.0 / CC BY 4.0 / " \
                   "CC BY 3.0); licence-less files fall back on their repo's LICENCE.txt " \
                   "(CC BY 4.0), recorded per document; class attribution throughout",
          license_class: "attribution",
          upstream_url: ORG_URL,
          parser_family: "dharma-epidoc",
          credit: "DHARMA — Task Force B epigraphic corpora (ERC no. 809994, EFEO/CNRS; erc-dharma " \
                  "on GitHub), incl. Early Inscriptions of Āndhradeśa (Baums, Griffiths, Strauch, " \
                  "Tournier) and Andrew Ollett's Sātavāhana inscriptions data. Cite the corpus and " \
                  "its editors wherever used."
        )
      end

      def self.upstream_repo_urls
        REPOS.keys.map { |name| "#{ORG_URL}/#{name}" }
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        candidates(workdir).first.each(&block)
      end

      def discovery_skips(workdir)
        _, skipped = candidates(workdir)
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped.size, unrecognized: 0, notes: skipped)
      end

      def parse(document_ref)
        path = document_ref.path
        repo = document_ref.metadata.fetch("repo")
        config = repos.fetch(repo)
        doc = Nokogiri::XML(File.read(path, encoding: "UTF-8"), &:noblanks)
        doc.remove_namespaces!
        result = walk(doc, path, config)
        metadata = header_metadata(doc, path, repo, config, document_ref.metadata["stem"])
        metadata["maturity"] = result[:maturity] if result[:maturity]
        document = Nabu::Document.new(
          urn: document_ref.id, language: result.fetch(:language), canonical_path: path,
          title: result[:title] || document_ref.metadata["stem"], metadata: metadata
        )
        result.fetch(:units).each_with_index do |unit, index|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{unit.key}", language: unit.language, text: unit.text,
            sequence: index, annotations: unit.met ? { "met" => unit.met } : {}
          )
        end
        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The UD compose pattern: every repo's objects first, ONE breaker
      # verdict over all their deletions, then every merge.
      def fetch(workdir, progress: nil, force: false)
        pulls = repos.keys.to_h do |name|
          [name, Nabu::GitFetch.new(
            repo_url: repo_url(name), dir: File.join(workdir, name),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, name), progress: progress,
            sparse: sparse_paths(name)
          )]
        end
        pulls.each_value(&:prepare!)
        guard_mass_deletion!(workdir, pulls.values.flat_map(&:doomed_paths), force: force)
        pulls.each_value(&:complete!)
        shas = pulls.transform_values(&:head_sha)
        Nabu::FetchReport.new(sha: shas.values.last, fetched_at: Time.now,
                              notes: fetch_notes(shas, pulls),
                              repos: shas.to_h { |name, sha| [repo_url(name), sha] })
      rescue Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      # Seams for tests (the house local-git pattern).
      def repos = REPOS

      def repo_url(name) = "#{ORG_URL}/#{name}"

      # The sparse cone: the edition dir + grant/README (+ the metadata
      # table). Root-layout repos clone whole (tiny; a cone of named dirs
      # would materialize nothing — the dharma-pyu first-sync lesson).
      def sparse_paths(name)
        config = repos.fetch(name)
        return nil if config[:dir].empty?

        [config[:dir], "README.md", "LICENCE.txt", config[:tsv]].compact
      end

      def fetch_notes(shas, pulls)
        notes = shas.map { |name, sha| "#{name}=#{sha[0, 12]}" }.join(" ")
        atticked = pulls.values.sum { |pull| pull.atticked.size }
        atticked.positive? ? "#{notes} · atticked #{atticked} upstream-deleted file(s)" : notes
      end

      # [refs sorted by urn, skip notes]. Repo order decides a collision.
      def candidates(workdir)
        refs = {}
        skipped = []
        repos.each do |repo, config|
          Dir.glob(File.join(workdir, repo, config[:dir], "*.xml")).sort.each do |path| # rubocop:disable Lint/RedundantDirGlobSort -- explicit urn-order guarantee (the dharma_base habit)
            name = File.basename(path)
            unless edition_file?(name, config)
              skipped << "#{repo}/#{name}: not an edition file"
              next
            end
            stem = Nabu::Normalize.nfc(File.basename(path, ".xml"))
            urn = "urn:nabu:#{SLUG}:#{stem.delete_prefix(FILE_PREFIX)}"
            if refs.key?(urn)
              skipped << "#{repo}/#{name}: stem collision with #{refs[urn].metadata['repo']}"
              next
            end
            refs[urn] = Nabu::DocumentRef.new(source_id: SLUG, id: urn, path: File.expand_path(path),
                                              metadata: { "stem" => stem, "repo" => repo })
          end
        end
        [refs.values.sort_by(&:id), skipped]
      end

      def edition_file?(name, config)
        return !OLLETT_NON_EDITIONS.include?(name) if config[:ollett]

        File.basename(name, ".xml").match?(DHARMA_EDITION) && !name.end_with?("-test.xml")
      end

      # DharmaEpidocParser#parse's orchestration on a pruned DOM (class note).
      def walk(doc, path, config)
        parser = DharmaEpidocParser
        edition = doc.at_xpath('//body//div[@type="edition"]') or
          raise Nabu::ParseError, "#{File.basename(path)}: no edition div"
        edition.xpath(".//div[#{EDITORIAL_DIVS.map { |t| "@type='#{t}'" }.join(' or ')}]").each(&:remove)

        checker = parser.language_checker(config[:languages], config.fetch(:aliases, {}), path)
        state = parser::WalkState.new(checker: checker,
                                      paragraph_mode: !edition.at_xpath(".//lb[not(ancestor::lg)]"))
        edition_lang = parser.lang_of(edition) || edition.xpath(".//div").filter_map { |d| parser.lang_of(d) }.first
        parser.walk_edition(edition, state, parser::Walkctx.new(edition_lang, [], nil))
        state.flush!
        units = state.units
        raise Nabu::ParseError, "#{File.basename(path)}: edition has no citable text" if units.empty?

        { language: checker.call(edition_lang || units.first.language), units: units,
          title: parser.presence(parser.text_of(doc.at_xpath("//teiHeader//titleStmt/title"))),
          maturity: edition["rendition"]&.[](/maturity:(\d+)/, 1) }
      end

      def header_metadata(doc, path, repo, config, stem)
        meta = { "repo" => repo }.merge(licence(doc, path, repo))
        source_grant = doc.at_xpath("//sourceDesc//availability/licence")
        meta["license_source_edition"] = grant_value(source_grant) if source_grant
        editors = editors(doc)
        meta["editors"] = editors unless editors.empty?
        date = orig_date(doc) || tsv_date(path, repo, config, stem)
        meta["date"] = date if date
        meta.merge(orig_place(doc))
      end

      def licence(doc, path, repo)
        own = doc.at_xpath("/TEI/teiHeader/fileDesc/publicationStmt/availability/licence")
        return { "license" => grant_value(own), "license_basis" => "in-file" } if own

        licence_txt = File.join(repo_root(path, repo), "LICENCE.txt")
        unless File.file?(licence_txt)
          raise Nabu::ParseError, "#{File.basename(path)}: no licence — no in-file <licence> and no " \
                                  "#{repo}/LICENCE.txt to fall back on"
        end
        first_line = File.foreach(licence_txt).map(&:strip).find { |line| !line.empty? }
        unless first_line == "Attribution 4.0 International"
          raise Nabu::ParseError, "#{File.basename(path)}: #{repo}/LICENCE.txt is not the censused " \
                                  "CC BY 4.0 (#{first_line.inspect}) — classify it before ingesting"
        end
        { "license" => REPO_LICENCE, "license_basis" => REPO_LICENCE_BASIS }
      end

      def grant_value(node)
        node["target"] || DharmaEpidocParser.clean(node.text)
      end

      # The live repo root for a file — attic copies (<workdir>/.attic/<repo>/…)
      # resolve to the live tree, where the LICENCE.txt and metadata live.
      def repo_root(path, repo)
        depth = repos.fetch(repo)[:dir].split("/").size
        root = depth.times.reduce(File.dirname(path)) { |dir, _| File.dirname(dir) }
        parent = File.dirname(root)
        File.basename(parent) == ATTIC_DIRNAME ? File.join(File.dirname(parent), repo) : root
      end

      def editors(doc)
        doc.xpath("/TEI/teiHeader/fileDesc/titleStmt/editor | " \
                  "/TEI/teiHeader/fileDesc/titleStmt/respStmt/persName | " \
                  "/TEI/teiHeader/fileDesc/titleStmt/respStmt/name").filter_map do |node|
          forename = node.at_xpath(".//forename")&.text
          surname = node.at_xpath(".//surname")&.text
          name = forename || surname ? [forename, surname].compact.join(" ") : node.text
          DharmaEpidocParser.presence(DharmaEpidocParser.clean(name))
        end.uniq
      end

      def orig_date(doc)
        node = doc.at_xpath("//origin/origDate") or return nil
        return nil unless [nil, "cal:gregorian"].include?(node["datingMethod"])

        date = {}
        begin
          not_before = Nabu::Timeline.parse_year(node["notBefore-custom"] || node["notBefore"] ||
                                                 node["when-custom"] || node["when"])
          not_after = Nabu::Timeline.parse_year(node["notAfter-custom"] || node["notAfter"] ||
                                                node["when-custom"] || node["when"])
          date["not_before"] = not_before if not_before
          date["not_after"] = not_after if not_after
        rescue Nabu::Timeline::InvalidYear
          nil # bounds dropped; the raw claim still rides
        end
        { "raw" => DharmaEpidocParser.clean(node.text), "precision" => node["precision"],
          "cert" => node["cert"], "evidence" => node["evidence"] }.each do |key, value|
          date[key] = value if DharmaEpidocParser.presence(value)
        end
        date.empty? ? nil : date
      end

      def orig_place(doc)
        node = doc.at_xpath("//origin/origPlace") or return {}
        name = node.at_xpath(".//placeName")
        {
          "place" => name && DharmaEpidocParser.presence(DharmaEpidocParser.clean(name.text)),
          "place_key" => name&.[]("key"),
          "orig_place_text" => DharmaEpidocParser.presence(DharmaEpidocParser.clean(node.text))
        }.compact
      end

      # The repo's own metadata table (Vengī Cālukya), keyed by the text id
      # (the stem sans DHARMA_). Its "Date range CE"/"Date CE" are CE years.
      def tsv_date(path, repo, config, stem)
        return nil unless config[:tsv]

        row = tsv_rows(File.join(repo_root(path, repo), config[:tsv]))[stem.delete_prefix(FILE_PREFIX)]
        return nil unless row

        raw = [row["Date range CE"], row["Date CE"]].find { |value| !value.to_s.empty? } or return nil
        bounds = if (match = TSV_YEAR_RANGE.match(raw)) then [match[1], match[2]]
                 elsif (match = TSV_YEAR.match(raw)) then [match[1], match[1]]
                 end
        date = bounds ? { "not_before" => Integer(bounds[0], 10), "not_after" => Integer(bounds[1], 10) } : {}
        date["raw"] = raw
        { "evidence" => row["Date evidence"], "cert" => row["Date certainty"],
          "precision" => row["Date precision"] }.each { |key, value| date[key] = value unless value.to_s.empty? }
        date.merge("basis" => config[:tsv])
      end

      # text id => { field => value }. Rows: field-group banners, the
      # "Fields" header row, the "Description of the fields" row, then data.
      def tsv_rows(tsv_path)
        @tsv_rows ||= {}
        @tsv_rows[tsv_path] ||= read_tsv(tsv_path)
      end

      def read_tsv(tsv_path)
        return {} unless File.file?(tsv_path)

        rows = File.readlines(tsv_path, chomp: true, encoding: "UTF-8")
                   .map { |line| line.split("\t", -1).map { |cell| Nabu::Normalize.nfc(cell.strip) } }
        header = rows.find { |cells| cells[1] == "Fields" }
        id_index = header&.index("Identifier of the text")
        return {} unless id_index

        rows.each_with_object({}) do |cells, map|
          id = cells[id_index]
          map[id] = header.zip(cells).to_h if id&.start_with?("INS")
        end
      end
    end
  end
end
