# frozen_string_literal: true

require_relative "bim_tsv_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # The BIM/SAHCOBA adapter: the historical Basque corpus of the BIM
    # ("Basque in the Making: A Historical Look at a European Language
    # Isolate", ANR) and SAHCOBA ("Syntactically Annotated Historical
    # Corpus in Basque", MICINN) projects — HiTZ, University of the Basque
    # Country (Estarrona, Etxeberria, Etxepare, Soraluze, Padilla-Moyano);
    # CLARIAH-EUS hdl:20.500.14614/43, doi:10.71845/hitz-32, issued
    # 2026-06-17. Fifteen works of Archaic and Old Basque, 1545–1782, as
    # machine-lemmatized and POS-tagged token streams (669,109 tokens):
    # Etxepare's Linguae Vasconum Primitiae (1545), the Lazarraga
    # manuscript (1560s), Leizarraga's New Testament (1571), Materra's
    # Doctrina christiana (1623), Beriain's mass treatise (1621), Axular's
    # Gero (1643), Kapanaga's catechism (1656), Tartas' Onsa hilceco bidia
    # (1666), Pouvreau's and Chourio's and Maister's translations of the
    # Imitation of Christ, Belapeire's Souletin catechism (1696), Otxoa de
    # Arin's Gipuzkoan doctrine (1713), Larramendi's Basque writings, and
    # an Avignon translation of Rodríguez's Ejercicio de perfección (1782).
    #
    # == Upstream and grains
    #
    # The CLARIAH-EUS item 20.500.14614/43 serves ONE bitstream,
    # BZENTROA-BIM.zip (2,926,904 bytes): a BZENTROA-BIM/ directory of 15
    # <Author>_automatikoa.tsv files (bim-tsv family — form, standardized
    # form, lemma, Basque POS, UPOS per line). THE DOCUMENT is each TSV
    # (one work). The item's LICENSE bundle (license.txt) is the
    # repository's deposit agreement, not text — not fetched. The sibling
    # item 20.500.14614/21 (doi:10.71845/hitz-17) is the search-interface
    # record (type toolService) and carries no files; the web application
    # (bim.ixa.eus) and its per-work metadata (period, dialect, author)
    # sit behind a browser challenge and are not an acquisition route.
    #
    # == Reconciliation (fixture-time census of the 2026-06-17 deposit)
    #
    # Upstream advertises "around one million words … 15th to mid-18th
    # centuries" (the record) and local.size.info 600,000 tokens; the zip
    # holds 15 works / 669,109 tokens. Accepted 15 documents of 15 files;
    # nothing skipped. Residue 0. (First real sync pending.)
    #
    # == The passage grain
    #
    # Derived by the declared rule in BimTsvParser: the source page where
    # the stream carries page markers (11 works → p.<label>), else the
    # sentence (Chourio, Etxepare, Larramendi, Leizarraga, Maister,
    # Pouvreau → s.<n>).
    #
    # == Identity
    #
    #   document urn  urn:nabu:bim-sahcoba:<author>  (the file stem's author,
    #                 lowercased: urn:nabu:bim-sahcoba:axular)
    #   passage urn   <document urn>:<citation>       (…:axular:p.3 · …:etxepare:s.12)
    #
    # == License
    #
    # CC BY 4.0 — the item record: dc.rights "Creative Commons -
    # Attribution 4.0 International (CC BY 4.0)", rights URI
    # creativecommons.org/licenses/by/4.0/, label PUB. Class attribution.
    #
    # == Axes (the aggressive-mining policy)
    #
    # The zip carries the author's surname as the file name and nothing
    # else; the works' identity therefore rides the curated WORKS table
    # below — title, and the imprint year and place READ from the title
    # page where the stream itself opens on one (Axular, Chourio, Lopez,
    # Maister, Materra, Otxoa, Tartas: date class "title page"), else the
    # standard philological attribution (Etxepare 1545, Leizarraga 1571,
    # Beriain 1621, Kapanaga 1656, Belapeire 1696, the Lazarraga
    # manuscript c. 1564–1567: raw marked "attributed"). Larramendi (a
    # modern selection of his letters, poems and sermons) and Pouvreau (a
    # manuscript translation the stream gives no date for) stay undated —
    # declared. Places: the imprint town only where the title page in the
    # stream names it. The dialect of each work (the standard attribution,
    # recorded as "dialect") rides as a facet — the lect lane's future
    # variety key. Language: Basque, bare eu (the Archaic / Old Basque
    # stages are a registry candidate, postures.yml). lemma_tier silver.
    #
    # == fetch / sync policy
    #
    # One public bitstream over HTTPS (Nabu::ZipFetch); a deposited version
    # is frozen → sync_policy manual.
    class BimSahcoba < Nabu::Adapter
      ZIP_URL = "https://clariah.hitz.eus/server/api/core/bitstreams/ca44acee-b541-458b-a917-fbf5eeb3f71d/content"
      URN_PREFIX = "urn:nabu:bim-sahcoba:"
      LANGUAGE = "eu"
      FILE_SUFFIX = "_automatikoa.tsv"

      # The 15 works, keyed by the file stem's author. "date" envelopes
      # carry their evidence in "raw"; "place" only where the stream's own
      # title page names the imprint town.
      WORKS = {
        "axular" => { "author" => "Pedro Agerre Azpilikueta (Axular)", "title" => "Gero",
                      "year" => 1643, "raw" => "title page: Bordelen, G. Milanges … M.dc.xliii",
                      "place" => "Bordeaux", "dialect" => "Labourdin" },
        "belapeire" => { "author" => "Athanase Belapeire", "title" => "Katexima labürra",
                         "year" => 1696, "raw" => "attributed (Pau 1696); the title page in the stream names " \
                                                  "Pau and the printer Jérôme Dupoux, no year",
                         "place" => "Pau", "dialect" => "Souletin" },
        "beriain" => { "author" => "Juan de Beriain",
                       "title" => "Tratado de cómo se ha de oír misa (Basque text)",
                       "year" => 1621, "raw" => "attributed (Pamplona 1621); the stream opens on the text, " \
                                                "no title page",
                       "dialect" => "Upper Navarrese" },
        "chourio" => { "author" => "Michel Chourio (translator)", "title" => "Jesu-Kristoren Imitazionea",
                       "year" => 1760, "raw" => "title page: Baionan, Paul Fauvet … M. Dcc. Lx. (this " \
                                                "edition; the translation first appeared in 1720)",
                       "place" => "Bayonne", "dialect" => "Labourdin" },
        "etxepare" => { "author" => "Bernard Etxepare", "title" => "Linguae Vasconum Primitiae",
                        "year" => 1545, "raw" => "attributed (Bordeaux 1545); the stream opens on the " \
                                                 "dedication, no title page",
                        "dialect" => "Lower Navarrese" },
        "kapanaga" => { "author" => "Martin Ochoa de Kapanaga",
                        "title" => "Exposición breve de la doctrina christiana (Basque text)",
                        "year" => 1656, "raw" => "attributed (Bilbao 1656); the stream opens on the preface",
                        "dialect" => "Biscayan" },
        "larramendi" => { "author" => "Manuel de Larramendi", "title" => "Euskal testuak (Basque writings)",
                          "dialect" => "Gipuzkoan" },
        "lazarraga" => { "author" => "Joan Perez de Lazarraga", "title" => "The Lazarraga manuscript",
                         "not_before" => 1564, "not_after" => 1567,
                         "raw" => "attributed (c. 1564–1567, the manuscript's dating); folios 1142r–1201r",
                         "dialect" => "Alavese" },
        "leizarraga" => { "author" => "Joanes Leizarraga", "title" => "Iesus Christ gure Iaunaren Testamentu berria",
                          "year" => 1571, "raw" => "attributed (La Rochelle 1571); the stream opens on the " \
                                                   "dedication to Jeanne d'Albret",
                          "dialect" => "Labourdin" },
        "lopez" => { "title" => "Giristhiño perfekzioniaren pratikaren pharte bat (Alonso Rodríguez, " \
                                "Ejercicio de perfección, a partial translation)",
                     "year" => 1782, "raw" => "title page: ( 1782 ); Avignonen, Antonio Aubanel … " \
                                              "M. Dc. Lxxxii [sic]",
                     "place" => "Avignon" },
        "maister" => { "author" => "Maister (translator)", "title" => "Jesü-Kristen Imitazionia",
                       "year" => 1757, "raw" => "title page: Pauben, G. Dugue eta J. Desbaratz … " \
                                                "M. Dcc. eta Lvii",
                       "place" => "Pau", "dialect" => "Souletin" },
        "materra" => { "author" => "Esteve Materra", "title" => "Dotrina kristiana (second impression)",
                       "year" => 1623, "raw" => "title page: Bordelen, Jacques Millanges … 1623",
                       "place" => "Bordeaux", "dialect" => "Labourdin" },
        "otxoa" => { "author" => "Josef Otxoa de Arin", "title" => "Doktrina kristianaren esplikazioa",
                     "year" => 1713, "raw" => "title page: Urte 1713 Donostian : Pedro de Ugarteren etxean",
                     "place" => "Donostia", "dialect" => "Gipuzkoan" },
        "pouvreau" => { "author" => "Silvain Pouvreau (translator)", "title" => "Jesusen imitazioneaz",
                        "dialect" => "Labourdin" },
        "tartas" => { "author" => "Ivan de Tartas", "title" => "Onsa hilzeko bidia",
                      "year" => 1666, "raw" => "title page: Orthezen, Jacques Rouyer … 1666",
                      "place" => "Orthez", "dialect" => "Souletin" }
      }.freeze

      # Each work's genre, the loop's reading of what the work IS (folded in
      # config/kind_map.yml): the standard literary-historical description,
      # never upstream metadata (the deposit carries none).
      GENRES = {
        "axular" => "ascetic treatise", "belapeire" => "catechism", "beriain" => "mass treatise",
        "chourio" => "devotional translation", "etxepare" => "poetry", "kapanaga" => "catechism",
        "larramendi" => "miscellany", "lazarraga" => "pastoral romance and verse",
        "leizarraga" => "scripture", "lopez" => "devotional translation", "maister" => "devotional translation",
        "materra" => "catechism", "otxoa" => "catechism", "pouvreau" => "devotional translation",
        "tartas" => "ascetic treatise"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "bim-sahcoba",
        name: "BIM/SAHCOBA — Syntactically Annotated Historical Corpus in Basque (HiTZ, University of the " \
              "Basque Country)",
        license: "CC BY 4.0 (CLARIAH-EUS item hdl:20.500.14614/43: \"Creative Commons - Attribution 4.0 " \
                 "International (CC BY 4.0)\"); credit BIM/SAHCOBA corpus, HiTZ (University of the Basque " \
                 "Country) — Estarrona, Etxeberria, Etxepare, Soraluze, Padilla-Moyano, doi:10.71845/hitz-32",
        license_class: "attribution",
        upstream_url: "https://hdl.handle.net/20.500.14614/43",
        parser_family: "bim-tsv"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "BZENTROA-BIM.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # One ref per <Author>_automatikoa.tsv, sorted by urn.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        tsv_paths(workdir).map { |path| ref(path) }.sort_by(&:id).each(&block)
      end

      # A TSV whose author the WORKS table does not know is unrecognized
      # (upstream added a work); anything else in the tree is not counted.
      def discovery_skips(workdir)
        unknown = tsv_paths(workdir).map { |path| stem(path) }.reject { |key| WORKS.key?(key) }.sort
        Nabu::Adapter::DiscoverySkips.new(unrecognized: unknown.size,
                                          notes: unknown.map { |key| "work without a WORKS row: #{key}" })
      end

      def parse(document_ref)
        text = SourceRead.utf8_file(document_ref.path, label: "bim-sahcoba")
        units = parser.units(text, label: document_ref.path)
        meta = document_ref.metadata
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE,
                                      canonical_path: document_ref.path,
                                      title: meta["title"] || meta["bim_file"], metadata: meta.except("title"))
        units.each_with_index do |unit, sequence|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{unit.citation}", language: LANGUAGE,
                                        text: unit.text, annotations: unit.annotations, sequence: sequence)
        end
        raise ParseError, "#{document_ref.path}: no tokens" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress, guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "bim-sahcoba fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        @parser ||= BimTsvParser.new
      end

      def tsv_paths(workdir)
        Dir.glob(File.join(workdir, "**", "*#{FILE_SUFFIX}"))
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
      end

      def stem(path)
        File.basename(path, FILE_SUFFIX).downcase
      end

      def ref(path)
        key = stem(path)
        Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{key}", path: File.expand_path(path),
                              metadata: ref_metadata(key, File.basename(path)))
      end

      def ref_metadata(key, file)
        work = WORKS.fetch(key, {})
        meta = { "language" => LANGUAGE, "bim_file" => file }.merge(work.slice("author", "title", "dialect"))
        meta["genre"] = GENRES[key] if GENRES.key?(key)
        if work["year"] || work["not_before"]
          meta["date"] = { "not_before" => work["not_before"] || work["year"],
                           "not_after" => work["not_after"] || work["year"], "raw" => work["raw"] }
        end
        if work["place"]
          meta["place"] = work["place"]
          meta["place_role"] = "imprint"
        end
        meta
      end
    end
  end
end
