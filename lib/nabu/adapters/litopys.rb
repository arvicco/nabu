# frozen_string_literal: true

require_relative "../litopys_fetch"
require_relative "litopys_html_parser"
require_relative "litopys_glossary_lane"

module Nabu
  module Adapters
    # Izbornyk (litopys.org.ua) — the PD-EDITION SUBSET (P117 / Q106, 02-
    # sources row 252). The site is a large hand-keyed library of East
    # Slavic sources, but most of it is keyed from SOVIET-ERA editions
    # whose editorial layer (text preparation, normalization, apparatus) is
    # not ours to take even where the medieval text is ancient. So the
    # packet IS the per-text edition triage, recorded below as TRIAGE —
    # every text the two shelves offer, each with the edition statement
    # the page itself carries (verbatim), the verdict, and the reasoning.
    #
    # == The rule (EDITION_TAINT_POST_1930 — the ru-wikisource shape)
    #
    # A text is admitted only when BOTH layers are public domain: the text
    # layer (the medieval work) and the EDITION layer the site keyed from.
    # An edition statement naming any year after 1930 excludes the text —
    # the ru-wikisource precedent's cut-off, applied to the page's own
    # "[За виданням: …]" statement. A facsimile reprint does not launder a
    # Soviet keying source (the Fedorov primers ride Soviet facsimiles, the
    # «Лексис» rides Німчук's 1964 text preparation). The rule is checked
    # twice: at census (TRIAGE, pinned by the suite) and again at discover
    # time against the fetched bytes (a page whose statement drifted to a
    # post-1930 edition is skipped, never parsed).
    #
    # == Admitted (census 2026-10-11)
    #
    # The Ipatiev chronicle, COMPLETE — ipatlet/ipat01–41.htm, stlb. 1–938:
    # ПСРЛ т. 2, Ипатьевская летопись, 2nd ed., СПб. 1908 (Imperial
    # Archaeographic Commission, ed. A. A. Shakhmatov, †1920). Text layer:
    # the Ipatiev codex (c. 1425) — PD. Edition layer: the 1908 print —
    # PD (a 1908 Imperial-Russian publication; its editor died 1920). The
    # site also credits the 1998 Moscow reprint, a PHOTOGRAPHIC reprint
    # that adds no text layer — its new foreword (Б. Клосс, ipatdod01)
    # stays out.
    #
    # Three glossaries from the «Лексикони» shelf (the dictionary lane,
    # LitopysGlossaryLane): «Лексисъ съ толкованіемъ словенскихъ мовъ
    # просто» (Амфілохій's publication, Чтения ОИДР 1884, кн. 2 — named on
    # the page; the site's page images are the 1884 typesetting), «Рѣчь
    # жидовьскаго языка» (the 1282 Novgorod Kormchaya onomasticon) and
    # «Тлъкованїє неудобь познаваемомъ … речемь» (1431) — these two pages
    # name no edition, but the page images they were keyed from are
    # pre-reform typesetting and the editor's own apparatus is in pre-1918
    # orthography ("…повторяется въ подлинникѣ", "Симъ словомъ прерывается
    # Канцлерскій списокъ") — a pre-1918 edition layer over a medieval
    # text, both PD. Everything else on the shelf is excluded by the rule.
    #
    # == Passages, dating, places (the aggressive-mining policy)
    #
    # Document = one site page (a run of the 1908 edition's columns);
    # passage = one COLUMN (стлб.) — the edition's own citation unit,
    # cited "urn:nabu:litopys:ipatNN:<column>" (a column broken across two
    # pages yields a passage on each — 26 such, the page grain keeps urns
    # unique). Per passage: the site's annal-year keys (AM + AD), the
    # Ipatiev-codex folio breaks, the 1908 apparatus — variant readings
    # (Хлебниковский/Погодинский lists) and notes — and the site's
    # bracketed references, all as annotations; the text carries only the
    # edition's text. Per document: the svod section (the site's own
    # three-part division), its column range, the annal span, and an
    # ATTRIBUTED composition-era band + compilation locus per section
    # (standard philology, declared as such: the Повѣсть in its 1110s
    # redaction at Kyiv, the Kievan svod of 1198–1200 at Kyiv/Vydubychi,
    # the Galician-Volhynian svod compiled 1260s–1290s in Galicia-
    # Volhynia) → MetadataDates :era_band_key + the place lane.
    #
    # Language orv throughout — DELIBERATELY COARSE, declared: the codex
    # spans the PVL's 11th–12th-c. language to the 13th-c. Galician-
    # Volhynian narrative (orv:early is the named stage candidate).
    class Litopys < Nabu::Adapter
      SLUG = "litopys"
      LANGUAGE = "orv"
      URN_PREFIX = "urn:nabu:litopys:"
      CHRONICLE_DIR = "ipatlet"
      CHRONICLE_PAGE = /\Aipat(\d\d)\.htm\z/
      EDITION_YEAR = "1908"

      CREDIT = "Ізборник (litopys.org.ua / izbornyk.org.ua) — scanning and keying by «Максим» " \
               "and the Izbornyk volunteers; texts after ПСРЛ т. 2 (СПб., 1908) and the " \
               "19th-c. glossary publications named per text"

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Izbornyk (litopys.org.ua) — the PD-edition subset: the Ipatiev chronicle + glossaries",
        license: "Public domain, per text — no license exists to cite: the site states none, and " \
                 "only texts whose text layer AND edition layer are both PD are taken (the " \
                 "Ipatiev chronicle after ПСРЛ т. 2, СПб. 1908; three glossaries after 19th-c. " \
                 "publications). The per-text PD basis rides each document/dictionary. Credit " \
                 "the site (Izbornyk, litopys.org.ua)",
        license_class: "open",
        upstream_url: "http://litopys.org.ua/",
        parser_family: "litopys-html",
        credit: CREDIT
      )

      TriageEntry = Data.define(:path, :title, :statement, :verdict, :basis)

      PD_1908 = "ПСРЛ т. 2 (2nd ed., СПб. 1908, Imperial Archaeographic Commission, ed. A. A. " \
                "Shakhmatov †1920): text layer = the Ipatiev codex (c. 1425), PD; edition layer = " \
                "the 1908 print, PD. The site's 1998 Moscow reprint is photographic — no new text layer"

      # The page's own edition statement, verbatim (where the page carries one).
      TRIAGE = [
        *(1..41).map do |n|
          TriageEntry.new(path: format("ipatlet/ipat%02d.htm", n),
                          title: "Літопис руський за Іпатським списком (ПСРЛ, Т. II, 1908) — page #{n}",
                          statement: "ПСРЛ. — Т. 2. Ипатьевская летопись. — СПб., 1908.",
                          verdict: :admitted_chronicle, basis: PD_1908)
        end,
        TriageEntry.new(path: "zyzlex/zyz100.htm",
                        title: "«Лексисъ съ толкованіемъ словенскихъ мовъ просто»",
                        statement: "Амфілохієва публікація: «Чтения в Обществе истории и древностей " \
                                   "российских при Московском университете», кн. вторая, апрель — " \
                                   "июнь. II. Материалы историко-литературные, М., 1884.",
                        verdict: :admitted_glossary,
                        basis: "text layer: a 16th–17th-c. glossary in a 1581 Ostroh Bible, PD; edition " \
                               "layer: archim. Amfilokhii's 1884 publication (Чтения ОИДР), PD"),
        TriageEntry.new(path: "zyzlex/zyz101.htm",
                        title: "«Рѣчь жидовьскаго языка, преложена на Роускую…» (1282)",
                        statement: nil, verdict: :admitted_glossary,
                        basis: "text layer: the 1282 Novgorod Kormchaya onomasticon, PD; edition layer: " \
                               "unnamed on the page, but its page image is pre-reform typesetting and " \
                               "the editor's apparatus is in pre-1918 orthography — pre-1918, PD"),
        TriageEntry.new(path: "zyzlex/zyz102.htm",
                        title: "«Тлъкованїє неудобь познаваемомъ въ писаныхъ речемь» (1431)",
                        statement: nil, verdict: :admitted_glossary,
                        basis: "text layer: a 1431 glossary, PD; edition layer: unnamed on the page, but " \
                               "its page image is pre-reform typesetting and the editor's note («Симъ " \
                               "словомъ прерывается Канцлерскій списокъ») is pre-1918 orthography — PD"),
        # --- the «Лексикони» shelf: excluded by EDITION_TAINT_POST_1930 ---
        TriageEntry.new(path: "fedorovych/bf.htm", title: "Іван Федорович. Буквар (Львів, 1574)",
                        statement: "Факсимільне видання: Буквар Івана Федорова. — Київ: \"Дніпро\", 1975 " \
                                   "(1-е вид. 1964); Иван Федоров. [Азбука]. — Москва: \"Просвещение\", 1974.",
                        verdict: :edition_tainted, basis: "Soviet facsimile editions 1964/1974/1975"),
        TriageEntry.new(path: "fedorovych2/cf.htm", title: "Іван Федорович. Азбука (Острог, 1578)",
                        statement: "За факсимільним виданням: Азбука Ивана Федорова. — М.: \"Книга\", 1983.",
                        verdict: :edition_tainted, basis: "Soviet facsimile edition 1983"),
        TriageEntry.new(path: "zyzgram/zy.htm", title: "Лаврентій Зизаній. Граматика словенська (Вільно, 1596)",
                        statement: "КИЇВ «НАУКОВА ДУМКА» (Пам’ятки української мови) 1980",
                        verdict: :edition_tainted, basis: "Пам’ятки української мови series, 1980"),
        TriageEntry.new(path: "zyzlex/zyz.htm",
                        title: "Лаврентій Зизаній. Лексис (Вільно, 1596) + Синоніма славеноросская",
                        statement: "Лексис Лаврентія Зизанія. Синоніма славеноросская / Підг. текстів " \
                                   "пам'яток і вступ. ст. В. В. Німчука. — К.: Наукова думка, 1964. — 259 с.",
                        verdict: :edition_tainted,
                        basis: "Німчук's 1964 text preparation (covers the Лексис text zyz99, the Синоніма " \
                               "zyz70–73 and the page images zyz02–68)"),
        TriageEntry.new(path: "smotrgram/sm.htm",
                        title: "Мелетій Смотрицький. Граматика (Єв’є, 1619)",
                        statement: "КИЇВ «НАУКОВА ДУМКА» (Пам’ятки української мови) 1979",
                        verdict: :edition_tainted, basis: "Пам’ятки української мови series, 1979"),
        TriageEntry.new(path: "berlex/be.htm", title: "Памво Беринда. Лексикон словенороський (Київ, 1627)",
                        statement: "Лексикон словенороський Памви Беринди / Підг. тексту і вступ. ст. " \
                                   "В. В. Німчука. — К., 1961. — 271 с.",
                        verdict: :edition_tainted, basis: "Німчук's 1961 text preparation"),
        TriageEntry.new(path: "verbbuk/ver.htm", title: "Тимофій Вербицький. Буквар (Київ, 1627)",
                        statement: "За виданням: Буквар Тимофія Вербицького 1627. — Київ, 1995. — 36 с.",
                        verdict: :edition_tainted, basis: "a 1995 edition"),
        TriageEntry.new(path: "uzhgram/uz.htm", title: "Іван Ужевич. Граматика слов’янська (1643; 1645)",
                        statement: "за вид. «Граматика слов’янська І.Ужевича. Київ — 1970. Пам’ятки " \
                                   "української мови XVII ст.»",
                        verdict: :edition_tainted, basis: "Пам’ятки української мови series, 1970"),
        TriageEntry.new(path: "uzhgram/uzp.htm", title: "Переклад Паризького рукопису (Ужевич)",
                        statement: "Пам’ятки української мови XVII ст. ВИДАВНИЦТВО «НАУКОВА ДУМКА» КИЇВ — 1970",
                        verdict: :edition_tainted, basis: "a 1970 modern translation"),
        TriageEntry.new(path: "stsl/stsl.htm", title: "Східнослов’янські граматики XVI—XVII ст. (збірка статей)",
                        statement: "Східнослов’янські граматики XVI-XVII ст. Київ, 1982.",
                        verdict: :edition_tainted, basis: "1982 scholarship, not a text"),
        TriageEntry.new(path: "nimchuk/nim.htm", title: "Василь Німчук. Мовознавство на Україні в XIV—XVII ст.",
                        statement: "Василь Німчук. Мовознавство на Україні в XIV—XVII ст. Київ, 1985.",
                        verdict: :edition_tainted, basis: "1985 scholarship, not a text"),
        # --- the chronicle's appendix pages (ipat.htm's "додатки"): not the chronicle ---
        TriageEntry.new(path: "ipatlet/ipatdod01.htm",
                        title: "Б. Клосс. Передмова до московського репринтного видання 1998 року",
                        statement: "ПРЕДИСЛОВИЕ К ИЗДАНИЮ 1998 г.", verdict: :edition_tainted,
                        basis: "the 1998 reprint's new foreword (B. Kloss)"),
        TriageEntry.new(path: "ipatlet/ipatdod02.htm",
                        title: "О. Шахматов. Передмова до санкт-петербурзького видання 1908 року",
                        statement: nil, verdict: :apparatus,
                        basis: "the 1908 editor's foreword (PD) — editorial prose, not the chronicle"),
        *%w[03 04 05 06 07 08 09].map do |n|
          TriageEntry.new(path: "ipatlet/ipatdod#{n}.htm",
                          title: "ПСРЛ т. 2 apparatus page ipatdod#{n} (errata / Єрмолаївський variants / " \
                                 "marginalia / notes)",
                          statement: nil, verdict: :apparatus,
                          basis: "1908 back-matter apparatus — a widening candidate, not the chronicle text")
        end,
        TriageEntry.new(path: "ipatlet/ipatdod12.htm", title: "Швидкий перехід по тексту (ipatdod12)",
                        statement: nil, verdict: :apparatus, basis: "the site's navigation index — no text"),
        *%w[10 11].map do |n|
          TriageEntry.new(path: "ipatlet/ipatdod#{n}.htm",
                          title: "Іменний / Географічний покажчик (ipatdod#{n})",
                          statement: nil, verdict: :apparatus,
                          basis: "modern Ukrainian-language indexes of unstated origin — not the 1908 layer")
        end
      ].freeze

      ADMITTED_CHRONICLE = TRIAGE.select { |entry| entry.verdict == :admitted_chronicle }.map(&:path).freeze
      ADMITTED_GLOSSARIES = TRIAGE.select { |entry| entry.verdict == :admitted_glossary }.map(&:path).freeze
      FETCH_PAGES = (ADMITTED_CHRONICLE + ADMITTED_GLOSSARIES).freeze

      # One upstream anchor mislabeled outright (census 2026-10-11): ipat05
      # carries <p class=Mber id="st58">58</p> between columns 91 and 93.
      MARKER_ERRATA = { "ipat05.htm" => { 58 => 92 } }.freeze

      # The site's own three-part division of the codex (ipat.htm), with
      # the ATTRIBUTED composition era + compilation locus (standard
      # philology — declared, never upstream's claim).
      Section = Data.define(:pages, :name, :band, :band_raw, :place)
      SECTIONS = [
        Section.new(pages: 1..12, name: "Повѣсть временныхъ лѣтъ", band: [1110, 1118],
                    band_raw: "Повѣсть временныхъ лѣтъ — the 1110s redaction (attributed)", place: "Kyiv"),
        Section.new(pages: 13..30, name: "Кіевскій лѣтописный сводъ", band: [1198, 1200],
                    band_raw: "Кіевскій сводъ — compiled 1198–1200 (attributed)", place: "Kyiv"),
        Section.new(pages: 31..41, name: "Галицко-Волынскій лѣтописный сводъ", band: [1260, 1292],
                    band_raw: "Галицко-Волынскій сводъ — compiled 1260s–1290s (attributed)",
                    place: "Galicia-Volhynia")
      ].freeze

      WITNESS = "Ипатьевский список (БАН 16.4.4), c. 1425"

      def self.manifest = MANIFEST

      def self.dictionary_lane = LitopysGlossaryLane.new

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "litopys.org.ua ipat.htm", zip_url: "http://litopys.org.ua/ipatlet/ipat.htm",
          metadata_url: nil, state_subdir: "", state_file: Nabu::LitopysFetch::STATE_FILE,
          liveness_only: true
        )]
      end

      def self.tainted?(statement) = LitopysHtmlParser.tainted?(statement)

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        chronicle_pages(workdir).reject { |path| drifted?(path) }.each do |path|
          stem = File.basename(path, ".htm")
          yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{stem}", path: File.expand_path(path),
                                      metadata: { "page" => stem })
        end
      end

      def discovery_skips(workdir)
        drifted = chronicle_pages(workdir).select { |path| drifted?(path) }
        known = (FETCH_PAGES.map { |rel| File.join(workdir, rel) } + chronicle_pages(workdir)).to_set
        strays = Dir.glob("**/*.htm", base: workdir).reject { |rel| known.include?(File.join(workdir, rel)) }
        notes = drifted.map do |path|
          "#{File.basename(path)}: edition statement no longer names the 1908 print (EDITION_TAINT_POST_1930)"
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: drifted.size, unrecognized: strays.size,
                                          notes: notes + strays.map { |rel| "non-corpus file: #{rel}" })
      end

      def parse(document_ref)
        name = File.basename(document_ref.path)
        page = LitopysHtmlParser.chronicle(File.binread(document_ref.path),
                                           path: document_ref.path, errata: MARKER_ERRATA.fetch(name, {}))
        raise Nabu::ParseError, "#{SLUG}: #{name}: edition statement is not the 1908 print" unless edition_ok?(page)
        raise Nabu::ParseError, "#{SLUG}: #{name}: no text columns" if page.columns.empty?

        section = section_for(name)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(page, section), metadata: page_metadata(page, section)
        )
        page.columns.each_with_index do |column, sequence|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{column.number}", language: LANGUAGE,
            text: column.paragraphs.join("\n"), sequence: sequence, annotations: column_annotations(column)
          )
        end
        document
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::LitopysFetch.sync!(
          pages: FETCH_PAGES, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          delay: fetch_delay,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        notes = [attic_notes(result.atticked),
                 ("served by the izbornyk.org.ua mirror: #{result.mirrored.join(', ')}" unless result.mirrored.empty?)]
                .compact
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes.empty? ? nil : notes.join("; "))
      rescue Nabu::LitopysFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      # Seam for tests (the politeness pause between GETs).
      def fetch_delay = Nabu::LitopysFetch::DELAY

      private

      def chronicle_pages(workdir)
        Dir.glob(File.join(workdir, CHRONICLE_DIR, "ipat*.htm"))
           .select { |path| File.basename(path).match?(CHRONICLE_PAGE) }.sort
      end

      # The discover-time re-check of the rule against the fetched bytes: the
      # p.Vary_cent statement must still name the 1908 print and no later year.
      def drifted?(path)
        statement = LitopysHtmlParser.decode(File.binread(path), path: path)[%r{<p class=Vary_cent>(.*?)</p>}m, 1]
        statement.nil? || !statement.include?(EDITION_YEAR) || LitopysHtmlParser.tainted?(statement)
      rescue Nabu::ParseError
        true
      end

      def edition_ok?(page)
        page.statement.include?(EDITION_YEAR) && !LitopysHtmlParser.tainted?(page.statement)
      end

      def section_for(name)
        number = Integer(name[CHRONICLE_PAGE, 1], 10)
        SECTIONS.find { |section| section.pages.cover?(number) } or
          raise Nabu::ParseError, "#{SLUG}: #{name}: page outside the censused 41"
      end

      def page_metadata(page, section)
        years = page.columns.flat_map(&:years)
        metadata = {
          "edition" => page.statement, "pd_basis" => PD_1908, "witness" => WITNESS,
          "section" => section.name, "columns" => "#{page.first_column}–#{page.last_column}",
          "era_band" => { "not_before" => section.band.first, "not_after" => section.band.last,
                          "raw" => section.band_raw },
          "place" => section.place
        }
        unless years.empty?
          metadata["annals"] = { "am_first" => years.first["am"], "am_last" => years.last["am"],
                                 "ad_first" => years.first["ad"], "ad_last" => years.last["ad"] }
        end
        metadata
      end

      def title_for(page, section)
        years = page.columns.flat_map(&:years)
        ads = years.map { |year| year["ad"] }.uniq
        span = ads.empty? ? "" : " [#{[ads.first, ads.last].uniq.join('–')}]"
        "Ипатьевская летопись (ПСРЛ II, 1908) — #{section.name}, стлб. " \
          "#{page.first_column}–#{page.last_column}#{span}"
      end

      def column_annotations(column)
        {
          "column" => column.number, "annal_years" => column.years, "folios" => column.folios,
          "marks" => column.marks, "variants" => column.variants, "notes" => column.notes
        }.reject { |_key, value| value.respond_to?(:empty?) && value.empty? }
      end
    end
  end
end
