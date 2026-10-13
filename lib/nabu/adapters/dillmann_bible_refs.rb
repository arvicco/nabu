# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Adapters
    # The Dillmann → Bible crosswalk (P123-1): the Lexicon linguae
    # aethiopicae cites scripture as <ref cRef="Gen." loc="2,17">; this
    # module resolves the book sigla onto the HELD Bible witnesses — the
    # Gǝʿǝz books themselves (betamasaheft-works, verse-grained
    # chapter.verse passages) and, for the New Testament books not held in
    # Gǝʿǝz, the parallel-Bible hub's SBLGNT witness (urn:nabu:sblgnt:*,
    # the `nt` work's Greek column — NT chapter/verse numbering is the
    # shared Stephanus scheme). Everything else carries verbatim (cts_work
    # nil): the MwSigla house pattern, resolve or carry, never guess.
    #
    # == The census (2026-10-13, the full 13,727-entry tree, read-only)
    #
    # 8,594 entries carry 92,835 <ref cRef> references over 708 distinct
    # sigla. Each Gǝʿǝz book was validated EMPIRICALLY against the live
    # catalog: where a reference directly follows its quoted Gǝʿǝz
    # (<foreign xml:lang="gez">), the quotation's folded words were looked
    # up in the cited verse and anywhere in the book. "exact/located"
    # below = quotations found AT the cited verse over those found
    # anywhere in the book.
    #
    # - :verse — exact/located >= 75%: chapter,verse resolves to the
    #   passage (a held verse the edition lacks falls back to the book at
    #   query time, the document-urn rule).
    # - :book — the book identity is proven (its quotations sit in the
    #   book) but the edition's versification diverges from Dillmann's
    #   (Jeremiah's LXX order, Job, Proverbs …) or the reference is
    #   chapter-only (Jubilees): document grain, never a wrong verse.
    # - unlisted — not held in Gǝʿǝz at verse grain, or the census refuted
    #   the candidate edition (4 Esr. vs the held Apocalypse of Ezra: 0
    #   exact; 1/2 Esr. vs the held Ezra books: 0 exact): verbatim.
    module DillmannBibleRefs
      Book = Data.define(:urn, :grain, :single_chapter)

      GEEZ = "urn:nabu:betamasaheft-works:"
      SBLGNT = "urn:nabu:sblgnt:"

      def self.geez(id, grain = :verse) = Book.new(urn: "#{GEEZ}#{id}", grain: grain, single_chapter: false)

      def self.nt(id, single_chapter: false)
        Book.new(urn: "#{SBLGNT}#{id}", grain: :verse,
                 single_chapter: single_chapter)
      end

      # cRef (whitespace-collapsed) => Book. Comments: reference count,
      # then exact/located for the Gǝʿǝz witnesses.
      BOOKS = {
        "Gen." => geez("LIT1546Genesi"),          # 3,933  431/469
        "Ex." => geez("LIT1367Exodus"),           # 3,309  364/399
        "Lev." => geez("LIT1793Leviti"),          # 1,744  159/176
        "Num." => geez("LIT2075Number"),          # 1,375  150/167
        "Deut." => geez("LIT2637Deuteronomy"),    # 1,481  144/155
        "Jos." => geez("LIT1696Joshua"),          #   671   50/54
        "Jud." => geez("LIT1700Judges"),          #   941   85/89
        "Ruth" => geez("LIT2229RuthBo"),          #   389   59/59
        "1 Reg." => geez("LIT2697Sam"),           # 1,629  215/244 (1 Samuel = Ethiopic 1 Kings)
        "2 Reg." => geez("LIT2698Sam"),           #   806   86/99
        "3 Reg." => geez("LIT2699Kings"),         #   750  106/126
        "4 Reg." => geez("LIT2700Kings"),         #   671  117/126
        "1 Par." => geez("LIT3499Chroni"),        #   572  118/150
        "2 Par." => geez("LIT3500Chroni"),        #   710  134/175
        "Esth." => geez("LIT1362Esther", :book),  #   389    1/103 — versification diverges
        "Judith" => geez("LIT1701Judith"),        #   996  200/248
        "Tob." => geez("LIT2473TobitB", :book),   #   544  110/153 — below the bar
        "Job" => geez("LIT1688Job", :book),       # 3,186  378/791 — versification diverges
        "Ps." => geez("LIT2000Mazmur"),           # 4,233  343/361
        "Prov." => geez("LIT3927Messale", :book), # 2,032  160/461 — versification diverges
        "Koh." => geez("LIT1320Eccles"),          #   890  118/146
        "Sap." => geez("LIT2516Wisdom", :book),   #   869   25/158 — versification diverges
        "Sir." => geez("LIT2358Sirach"),          # 4,970  1,790/1,916
        "Jes." => geez("LIT1672Isaiah"),          # 5,377  1,091/1,316
        "Jer." => geez("LIT1685Bookof", :book),   # 3,527  411/873 — LXX/Hebrew order diverges
        "Thren." => geez("LIT1753Lament"),        #   525  113/129
        "Bar." => geez("LIT1202Bookof"),          #    72   20/21
        "Hez." => geez("LIT5802EzekII"),          # 2,263  563/623
        "Dan." => geez("LIT3529Daniel"),          #   932  173/192
        "Hos." => geez("LIT3144Hosea", :book),    #   260   57/82 — below the bar
        "Joel" => geez("LIT1689Joel", :book),     #   190   16/35 — versification diverges
        "Am." => geez("LIT3145Amos"),             #   289   48/57
        "Jon." => geez("LIT1694Jonah"),           #   107   34/39
        "Mich." => geez("LIT3146Micah"),          #   222   43/54
        "Nah." => geez("LIT2057Bookof"),          #   145   26/34
        "Hab." => geez("LIT1567Bookof"),          #   104   13/15
        "Zeph." => geez("LIT3148Zephan"),         #    92   18/21
        "Hagg." => geez("LIT3149Haggai", :book),  #    69   10/16 — below the bar
        "Zach." => geez("LIT3150Zechar"),         #   400   74/86
        "Mal." => geez("LIT3151Malachi"),         #   150   31/34
        "Hen." => geez("LIT1340EnochE", :book),   # 2,526  0/337 — held edition partial (108 passages)
        "Kuf." => geez("LIT1697Jubilees", :book), # 2,548  2,536 chapter-only references
        "Matth." => geez("LIT2709Matthew"),       # 3,832  292/348
        "Marc." => geez("LIT2711Mark"),           # 1,095   95/103
        "Luc." => geez("LIT2713Luke"),            # 1,756  125/155
        "Joh." => geez("LIT2715John"),            # 1,171  104/117
        "Jac." => geez("LIT3512Epistle"),         #   424   43/43 James
        "1 Petr." => geez("LIT3507Epistle"),      #   329   32/35
        "2 Petr." => geez("LIT3508Epistle"),      #   175   21/22
        # -- the hub's SBLGNT column: NT books not held in Gǝʿǝz ----------
        "Act." => nt("acts"),                     # 1,193
        "Rom." => nt("rom"),                      # 1,287
        "1 Cor." => nt("1cor"),                   #   596
        "2 Cor." => nt("2cor"),                   #   338
        "Gal." => nt("gal"),                      #   176
        "Eph." => nt("eph"),                      #   231
        "Phil." => nt("phil"),                    #   232
        "Col." => nt("col"),                      #   127
        "1 Thess." => nt("1thess"),               #   174
        "2 Thess." => nt("2thess"),               #    54
        "1 Tim." => nt("1tim"),                   #   313
        "2 Tim." => nt("2tim"),                   #   163
        "Tit." => nt("titus"),                    #   134
        "Philem." => nt("phlm", single_chapter: true), # 22
        "Hebr." => nt("heb"),                     #   683
        "1 Joh." => nt("1john"),                  #   198
        "2 Joh." => nt("2john", single_chapter: true),  # 15
        "3 Joh." => nt("3john", single_chapter: true),  # 16
        "Judae" => nt("jude", single_chapter: true),    # 80
        "Apoc." => nt("rev") # 1,052
      }.freeze

      # "9,24", "12.", "10,2-4" (a range cites its first verse).
      CHAPTER_VERSE = /\A(?<chapter>\d+)\s*,\s*(?<verse>\d+)(?:\s*[-–]\s*\d+)?\.?\z/
      BARE_NUMBER = /\A(?<n>\d+)\.?\z/

      module_function

      # One DictionaryCitation per <ref cRef> under +node+ (the entry),
      # document order. Label/urn_raw: the ref's display text verbatim
      # (whitespace collapsed, NFC), falling back to "cRef loc".
      def citations(node)
        node.xpath(".//*[local-name()='ref'][@cRef]").filter_map do |ref|
          siglum = collapse(ref["cRef"])
          loc = collapse(ref["loc"].to_s)
          label = Nabu::Normalize.nfc(presence(collapse(ref.text)) || "#{siglum} #{loc}".strip)
          next if label.empty?

          cts_work, citation = resolve(siglum, loc)
          Nabu::DictionaryCitation.new(urn_raw: label, cts_work: cts_work, citation: citation, label: label)
        end
      end

      # [cts_work, citation] — [nil, nil] for an unheld book.
      def resolve(siglum, loc)
        book = BOOKS[siglum]
        return [nil, nil] if book.nil?
        return [book.urn, nil] if book.grain == :book

        [book.urn, verse_citation(book, loc)]
      end

      def verse_citation(book, loc)
        if (match = CHAPTER_VERSE.match(loc))
          "#{match[:chapter].to_i}.#{match[:verse].to_i}"
        elsif book.single_chapter && (match = BARE_NUMBER.match(loc))
          "1.#{match[:n].to_i}"
        end
      end

      def collapse(text) = text.to_s.gsub(/\s+/, " ").strip

      def presence(text) = text.empty? ? nil : text
    end
  end
end
