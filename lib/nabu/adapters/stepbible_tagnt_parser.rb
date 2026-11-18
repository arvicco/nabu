# frozen_string_literal: true

module Nabu
  module Adapters
    # Parser for one TAGNT data file — STEPBible-Data's "Translators
    # Amalgamated Greek NT" (Tyndale House Cambridge / STEPBible.org), a
    # word-per-row tab-separated amalgam of the NA27/NA28, Tyndale House,
    # SBL, Tregelles, Byzantine (RP 2005), Westcott-Hort and TR (Scrivener
    # 1894) editions. A standalone, individually tested parser family the
    # StepbibleTagnt adapter composes.
    #
    # == The format (inspected first-hand, pinned commit 5de0a47f)
    #
    # After a long documentation header (license block, field descriptions,
    # the word-type abbreviations), each verse is a block:
    #
    #   # Mat.1.1<TAB>Βίβλος <TAB>γενέσεως <TAB>…        verse summary rows
    #   #_Translation<TAB>…  #_Word=Grammar<TAB>…  #_Significant variant…
    #   Word & Type<TAB>Greek<TAB>English translation<TAB>…   column header
    #   Mat.1.1#01=NKO<TAB>Βίβλος (Biblos)<TAB>[The] book<TAB>G0976=N-NSF<TAB>…
    #
    # Only the WORD ROWS are read: the "#"-prefixed summary rows restate the
    # same words ten to a line with their English and grammar (a derived
    # duplicate of the word rows — not ingested), and the column-header row
    # repeats per verse. A word row's 17 tab fields are:
    #
    #    0 ref=type    Mat.1.1#01=NKO — NRSV verse ref, an optional
    #                  differing-versification bracket ([KJV] / (NA) /
    #                  {other}: Mat.15.6{15.5}#01), word number, word type
    #    1 Greek       "Βίβλος (Biblos)" — the word (punctuation and the ¶
    #                  paragraph mark attached) + its transliteration
    #    2 English     the word's English translation
    #    3 dStrong=Grammar   G0976=N-NSF (a joined word: "A=x + B=y")
    #    4 Dictionary form=Gloss   βίβλος=book
    #    5 editions    NA28+NA27+Tyn+SBL+WH+Treg+TR+Byz (displacement marks
    #                  like "TR»2" verbatim)
    #    6 meaning variants   readings that alter the translation, with
    #                  their editions ("ἀπιστίαν (T=apistian) unbelief - …
    #                  in: TR+Byz")
    #    7 spelling variants  "Tyn+WH: Δαυεὶδ ; +TR: Δαβὶδ ;"
    #    8 Spanish  9 sub-meaning  10 conjoin  11 sStrong+instance
    #   12 alt Strongs
    #   13 variant note  "v …" (variant) / "^ …" (extra text, the note on
    #                  the last word of the run)
    #   14-16 empty in every row of the pinned files
    #
    # == What a parse yields
    #
    # One book = one document (the adapter picks the book; a file carries a
    # contiguous run of books). One NRSV verse = one passage, urn
    # <doc-urn>:<C>.<V> (the sblgnt shape); a word whose ref carries a
    # versification bracket stays in its NRSV verse and keeps the bracket in
    # its token "id". Passage text = the verse's words in row order, joined
    # by single spaces, VERBATIM (punctuation and ¶ included) — upstream's
    # own amalgamated verse, i.e. the union of every edition's words:
    # Mat 6:13's TR doxology and Mat 17:21 (absent from NA) are in the text
    # exactly as upstream prints them; which editions carry each word rides
    # the tokens.
    #
    # == The apparatus — the P7-5 "tokens" contract
    #
    # Every word row becomes a token: "id" (field 0's ref, brackets
    # verbatim), "form" (the Greek word with attached punctuation, ¶, ¬ and
    # editorial [[ ]] stripped — the lemma index's surface form; the text
    # keeps them), "translit", "type" (the word-type code: NKO, N(K)O, K,
    # k, KO, …), "editions" (field 5 verbatim), "strong" / "morph" (field
    # 3 split at "="; joined words keep the " + " join), "lemma" (field
    # 4's dictionary form — the FIRST headword of a multi-form entry like
    # "ἔπω, ἐρῶ, εἶπον", a trailing homograph mark "(2)" dropped; a joined
    # word whose entry names its parts, "οὐ=no + ἔτι=still", carries
    # "lemma_parts" instead — two lexemes, never one lemma key),
    # "lemma_gloss", "gloss" (the English), and when present
    # "meaning_variants", "spelling_variants", "note" — all verbatim, NFC.
    #
    # DECLARED-DEFERRED columns (no apparatus value; each is a tagging aid
    # for lining TAGNT up with other tagged Bibles): Spanish (8),
    # sub-meaning (9), conjoin links (10), sStrong+instance (11), alt
    # Strongs (12). They stay in canonical/ and can join the tokens later
    # without a re-fetch.
    class StepbibleTagntParser
      # Field 0 of a word row.
      WORD_REF = /\A(?<book>[1-3]?[A-Z][a-z]+)\.(?<chapter>\d+)\.(?<verse>\d+)
                  (?<alt>[\[({][\d.]+[\])}])?\#(?<n>\d+)=(?<type>\S+)\z/x

      # A line that LOOKS like a word row (book.chapter.verse lead) — one
      # that then fails WORD_REF is upstream drift, never skipped silently.
      ROW_LEAD = /\A[1-3]?[A-Z][a-z]+\.\d+\.\d+/

      # Field 1: the word and its transliteration in parentheses (upstream
      # sometimes sets two spaces before the parenthesis).
      GREEK = /\A(?<word>.+?)\s*\((?<translit>[^()]*)\)\s*\z/

      # Stripped from a word to make its token "form": , . · (U+0387) ;
      # (U+037E, NFC-folded to ";") ¶ ¬ and the editorial brackets. The
      # elision mark ᾽ (U+1FBD) is part of the word and stays.
      FORM_STRIP = /[,.·;;¶¬\[\]]/

      # Trailing homograph mark on a dictionary form: "ἰός (2)".
      HOMOGRAPH = /\s*\(\d+\)\z/

      MIN_FIELDS = 14

      # The book codes a file carries, in file order (unique). The
      # adapter's discover peek: a line scan, no row parsing.
      def books(path)
        found = []
        each_line(path) do |line|
          next unless (lead = line[ROW_LEAD])

          book = lead[/\A[1-3]?[A-Z][a-z]+/]
          found << book unless found.last == book || found.include?(book)
        end
        found
      end

      # Parse +book+'s word rows out of +path+ into a Document.
      def parse(path, book:, urn:, title:, language: "grc")
        document = Nabu::Document.new(urn: urn, language: language, title: title,
                                      canonical_path: File.expand_path(path),
                                      metadata: { "book" => book })
        verses(path, book).each do |key, rows|
          document << passage(urn, key, rows, language, document.size)
        end
        raise ParseError, "#{path}: no word rows for book #{book}" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: #{book}: #{e.message}"
      end

      private

      # Through the encoding belt (invalid bytes quarantine the book, never
      # abort the sync). The BOM stays on line 1 — header text, never a row.
      def each_line(path)
        return enum_for(:each_line, path) unless block_given?

        SourceRead.utf8_lines(path, label: "stepbible-tagnt") { |line| yield line.chomp }
      end

      # "C.V" => [[citation, fields, ref-match], …] in file order. Books are
      # contiguous upstream, so the scan stops at the first row of the next
      # book after +book+ was seen.
      def verses(path, book)
        verses = {}
        seen = false
        each_line(path).with_index(1) do |line, lineno|
          next unless line.match?(ROW_LEAD)

          fields = line.split("\t", -1)
          ref = WORD_REF.match(fields[0]) ||
                raise(ParseError, "#{path}:#{lineno}: unreadable word ref #{fields[0].inspect}")
          if ref[:book] != book
            break if seen

            next
          end
          seen = true
          if fields.size < MIN_FIELDS
            raise ParseError,
                  "#{path}:#{lineno}: #{fields.size} fields, expected >= #{MIN_FIELDS}"
          end

          key = "#{ref[:chapter]}.#{ref[:verse]}"
          (verses[key] ||= []) << [fields, ref, lineno]
        end
        verses
      end

      def passage(urn, key, rows, language, sequence)
        citation = "#{rows.first[1][:book]}.#{key}"
        tokens = rows.map { |fields, ref, lineno| token(fields, ref, lineno, citation) }
        Nabu::Passage.new(
          urn: "#{urn}:#{key}",
          language: language,
          text: Normalize.nfc(tokens.map { |t| t.delete("word") }.join(" ")),
          sequence: sequence,
          annotations: { "citation" => citation, "tokens" => tokens }
        )
      end

      def token(fields, ref, lineno, citation)
        greek = GREEK.match(fields[1]) ||
                raise(ParseError, "#{citation} (line #{lineno}): Greek field without transliteration: " \
                                  "#{fields[1].inspect}")
        word = Normalize.nfc(greek[:word].strip)
        strong, morph = pairs(fields[3])
        hash = {
          "word" => word, # consumed by the text join, never stored
          "id" => fields[0].split("=", 2).first,
          "form" => word.gsub(FORM_STRIP, "").strip,
          "translit" => greek[:translit].strip,
          "type" => ref[:type],
          "editions" => fields[5].strip,
          "strong" => strong.join(" + "),
          "morph" => morph.join(" + ")
        }.merge(lemma_fields(fields[4])).merge(
          "gloss" => fields[2].strip,
          "meaning_variants" => fields[6].strip,
          "spelling_variants" => fields[7].strip,
          "note" => fields[13].strip
        )
        hash.each_with_object({}) do |(k, v), out|
          next if v.nil? || v.empty?

          out[k] = v.is_a?(Array) ? v.map { |s| Normalize.nfc(s) } : Normalize.nfc(v)
        end
      end

      # "G0976=N-NSF" → [["G0976"], ["N-NSF"]]; a joined word
      # "G2532=CONJ + G1473=P-1NS" → [["G2532", "G1473"], ["CONJ", "P-1NS"]].
      def pairs(field)
        parts = field.strip.split(/\s+\+\s+/).map { |part| part.split("=", 2).map(&:strip) }
        [parts.map(&:first), parts.map { |p| p[1].to_s }]
      end

      # One dictionary entry ("βίβλος=book", "κἀγώ=and I") → "lemma" (the
      # first headword, homograph mark dropped) + "lemma_gloss". A joined
      # word whose entry names its parts ("οὐ=no + ἔτι=still") claims two
      # lexemes, never one lemma key: "lemma_parts" + the joined gloss.
      def lemma_fields(field)
        headwords, glosses = pairs(field)
        heads = headwords.map { |h| h.split(",").first.to_s.strip.sub(HOMOGRAPH, "") }
        gloss = glosses.join(" + ")
        return { "lemma" => heads.first, "lemma_gloss" => gloss } if heads.size == 1

        { "lemma_parts" => heads, "lemma_gloss" => gloss }
      end
    end
  end
end
