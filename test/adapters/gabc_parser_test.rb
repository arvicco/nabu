# frozen_string_literal: true

require "test_helper"

module Adapters
  # The gabc family: the lyric text layer of a GABC (Gregorio) score and of
  # the TeX blocks GregoBase stores beside it. Every input below is a REAL
  # upstream value from the trimmed dump (test/fixtures/gregobase/README.md)
  # unless the test names it as a single GABC construct in isolation.
  class GabcParserTest < Minitest::Test
    Parser = Nabu::Adapters::GabcParser

    # -- the note layer --------------------------------------------------------

    def test_parenthesised_notes_clefs_and_bars_drop_and_syllables_rejoin
      # chant 17418, the hymn's first stanza (CRLF line breaks are source layout).
      gabc = "(c4) Ma(g)rí(hi)a(ih) ca(j)stis(ih) ó(g)scu(h)lis(i) (,)\r\nLam(g)bit(i) De(g)i(h) " \
             "ve(e)stí(f)gi(e)a,(d) (;)\r\n"
      assert_equal "María castis ósculis Lambit Dei vestígia,", Parser.text(gabc)
    end

    def test_nabc_pipes_live_inside_the_notes_and_never_reach_the_text
      # chant 14738: St Gall neumes after "|" in every note group; "*()" is the
      # printed intonation asterisk on an empty note group.
      gabc = "(c4)\r\nFA(f|vi)ctus(ghg|tohh) est(h|vihh) *()\r\nad(f|tahg)iú(g|vihg)tor(f|vihg) " \
             "me(f|vi)us(ef|peShg) De(g|vihi)us(fe|clhh) me(d|ta)us.(d|ta) (::)"
      assert_equal "FActus est * adiútor meus Deus meus.", Parser.text(gabc)
    end

    def test_vowel_centering_braces_and_clear_tags_keep_their_text
      # chant 507, the Alleluia's jubilus and the verse's last asterisk.
      assert_equal "ALlelúia.", Parser.text("(c4) AL(e)le(gg/higg'g/h_g)lú(gg/hig){ia}.(ggh//gjh/ihhg.) (::)")
      verse_end = "mi(hf)se(g)ri(h)cór(h!iwj)di(hg)a(g.) <clear>*(,) e(hf/gh!jjjg//jjjk)jus.(i.//gjh/ihhg.) (::)"
      assert_equal "misericórdia * ejus.", Parser.text(verse_end)
    end

    def test_style_tags_keep_their_text
      # chant 8761: the litany's bold/italic accent marks.
      gabc = "(c3) San(h)cte(h) Jo(h)án(h)nes(h) Ba(h)p<b>tí</b>(i)<b>s</b>ta,(g.) (,) o(g)<i>ra</i>(f) " \
             "<i>pro</i>(g) <b>no</b>(h)bis.(h.) (::)"
      assert_equal "Sancte Joánnes Baptísta, ora pro nobis.", Parser.text(gabc)
    end

    def test_special_characters_map_to_their_liturgical_signs
      # chant 13466: the versicle sign; "ij." is the printed repeat rubric.
      gabc = "(c4) AL(gh)le(fvED/ef/gf/hg)lu(fg~)ya.(g) *(;) <i>ij.</i>(hgjjvIH!kvJHhg.) (,) " \
             "(hvGFED/gv.fg!hvhg!jvIH/hg) <sp>V/</sp>.(::) Ve(gh)ri(fvED)ly(ef/gf!hvGFg) (;)"
      assert_equal "ALleluya. * ij. ℣. Verily", Parser.text(gabc)
      assert_equal "℟. ✠ ǽ æ œ́ œ",
                   Parser.text("<sp>R/</sp>.() <sp>+</sp>() <sp>'ae</sp>() <sp>ae</sp>() <sp>'oe</sp>() <sp>oe</sp>()")
    end

    def test_verbatim_tex_above_staff_text_translations_and_comments_drop
      # Single constructs: <v> is raw TeX for the typesetter, <alt> the text
      # printed above the staff, [..] the translation line under it, % a comment.
      assert_equal "SI culmen veri", Parser.text("SI(f) cul(g)men(h) <v>\\greheightstar</v>(,) ve(g)ri(h)")
      assert_equal "GLória,", Parser.text("(c4) <alt>Chorus :</alt>GLó(h)ri(g)a,(gh)")
      assert_equal "SAlve, Regína,", Parser.text("SAl[Hail]ve,[/](f) Re[Queen,](g)gí(h)na,[/](g)")
      assert_equal "Deus", Parser.text("De(f)us(g) (::)\r\n%E(h) u(h) o(g) u(h) a(f) e.(e)\r\n")
    end

    def test_the_euouae_differentia_is_text
      # chant 18115's closing differentia.
      assert_equal "E u o u a e.", Parser.text("E(j) u(j) o(i) u(j) a(h) e.(g) (::)\r\n")
    end

    def test_a_score_with_no_lyrics_extracts_to_empty
      assert_equal "", Parser.text("(c4)")
      assert_equal "", Parser.text("(c4) (hgjjvih!kvJHhg.) (,) (::)")
    end

    # -- the header ------------------------------------------------------------

    def test_header_splits_at_the_double_percent_line
      # chant 18115: an inline GABC header before the score.
      header, body = Parser.split_header("initial-style: 1;\r\n%%\r\n(c4)MI(g)rá(g)bi(f)le(fe)")
      assert_equal({ "initial-style" => "1" }, header)
      assert_equal "(c4)MI(g)rá(g)bi(f)le(fe)", body
    end

    def test_a_repeated_header_key_collects_its_values
      header, = Parser.split_header("name: X;\nannotation: Ant.;\nannotation: 7 a;\n%%\n(c4)")
      assert_equal({ "name" => "X", "annotation" => ["Ant.", "7 a"] }, header)
    end

    def test_a_body_without_a_header_returns_an_empty_header
      assert_equal [{}, "(c4) A(f)"], Parser.split_header("(c4) A(f)")
    end

    # -- the TeX blocks ----------------------------------------------------------

    def test_layout_only_tex_extracts_to_empty
      # chant 507's first element and its versicle annotation.
      assert_equal "", Parser.tex_text("\\grechangedim{linepunctummorashift}{-0.02 cm}{scalable}\r\n" \
                                       "\\gresetclivisalignment{never}\r\n\\grechangedim{largerspace}" \
                                       "{0.12581 cm plus 0.01822 cm minus 0.00911 cm}{scalable}")
      assert_equal "", Parser.tex_text("\\greannotation{\\small \\textbf{\\Vbar .}}")
    end

    def test_tex_markup_keeps_its_text
      # chant 8761's tex_verses, and a hymn stanza's drop initial.
      assert_equal "Sancte Joseph, ora pro nobis.",
                   Parser.tex_text("Sancte \\textbf{Jo}seph, o\\textit{ra pro} \\textbf{no}bis.")
      assert_equal "Per te sciámus da Patrem, noscámus",
                   Parser.tex_text("\\noindent\\frot{P}er te sciámus da Patrem, \\\\\r\nnoscámus\\\\")
      assert_equal "℣. Benedicámus ℟. Laudémus † et",
                   Parser.tex_text("\\Vbar . Benedicámus\\\\\r\n\\Rbar . Laudémus $\\dag$ et")
      assert_equal "2. Laudáte eum in virtútibus ejus : * laudáte",
                   Parser.tex_text("2.~Laudáte eum in virtútibus {\\bf e}jus~:~* laudáte")
    end

    def test_tex_accent_commands_compose_onto_their_letter
      # chant 4674's tex_verses stanza (NFC composition is the adapter's job).
      text = Parser.tex_text("\\noindent 2. Tu fabric\\'ator \\'omnium\\\\\ndiscrétor atque témporum,\\\\")
      assert_equal "2. Tu fabricátor ómnium discrétor atque témporum,", Nabu::Normalize.nfc(text)
      assert_equal "Iésu", Nabu::Normalize.nfc(Parser.tex_text("I\\'{e}su"))
      # chant 9895: the accent over a ligature.
      assert_equal "Et pǽnitens cor", Nabu::Normalize.nfc(Parser.tex_text("Et p\\'{æ}nitens cor"))
    end

    def test_tabbing_environments_keep_their_cells_text
      # chant 457's litany, one tabbing row (the hyphens are upstream's syllabification).
      tex = "\\vspace{-23pt}\r\n\\begin{tabbing}\r\n\\hspace*{.55cm}\\=\\hspace*{4.6cm}\\= \\kill\r\n" \
            "\\> Sancta De- i ~ {\\bf Gé}nitrix, \\> o-{\\it ra} \\> {\\it pro} \\> no-bis.\\\\\r\n" \
            "\\> Sancte \\qquad \\quad {\\bf Mí}chael, \\> o-{\\it ra}\r\n\\end{tabbing}"
      assert_equal "Sancta De- i Génitrix, o-ra pro no-bis. Sancte Míchael, o-ra", Parser.tex_text(tex)
    end

    def test_tex_stanzas_split_at_blank_lines
      tex = "Linguam refraenans témperet,\\\\\nNe litis horror ínsonet:\\\\\n\nSint pura cordis íntima,\\\\\n"
      assert_equal ["Linguam refraenans témperet,\\\\\nNe litis horror ínsonet:\\\\", "Sint pura cordis íntima,\\\\"],
                   Parser.tex_stanzas(tex)
    end

    # -- the verses block --------------------------------------------------------

    def test_verse_chunks_split_at_verse_numbers
      verses = "2. Os,(e) lin(g)gua(gh) (::)\r\n\r\n3. Prae(e)sta,(g) Pa(gh)ter(h) (::)\r\nA(ded)men.(cd..) (::)"
      chunks = Parser.verse_chunks(verses)
      assert_equal 2, chunks.size
      assert_equal(["2. Os, lingua", "3. Praesta, Pater Amen."], chunks.map { |c| Parser.text(c) })
    end

    def test_an_unnumbered_verses_block_is_one_chunk
      # chant 17418's doxology stanza.
      verses = "2.  De(g)o(hi) Pa(ih)tri(j) sit(ih) gló(g)ri(h)a,(i) (,)\nA(ded)men.(cd) (::) \n"
      assert_equal 1, Parser.verse_chunks(verses).size
      assert_equal ["Rè(d)spi(c)ce(d) (::)"], Parser.verse_chunks("Rè(d)spi(c)ce(d) (::)\n\n")
    end
  end
end
