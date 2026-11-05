# frozen_string_literal: true

require "test_helper"
require "nabu/adapters/cgpg_title_genre"

# The cgpg kind fold's extraction half: a carved work's Latin title (the
# carve plan's own "title" field) → one keyword head, which
# config/kind_map.yml's cgpg section folds onto the ruled class list.
# Every title below is a real carve-plan title (open-greek-corpus
# corpus-2026-10-28.2, read 2026-11-05).
class CgpgTitleGenreTest < Minitest::Test
  def head(title) = Nabu::Adapters::CgpgTitleGenre.head(title)

  # The genre keyword is found ANYWHERE in the main title (before the
  # first parenthesis/bracket), spelling-normalized to one head.
  def test_a_genre_keyword_heads_the_title
    {
      "Epistulae vii genuinae (recensio media)" => "Epistulae",
      "Epistola (anti-Latin, on the procession of the Holy Spirit)" => "Epistulae",
      "Epistolae (I-XXIX; chapters of Eis tas aporias tes Theias Graphes)" => "Epistulae",
      "Epistula Tiberiani ad Trajanum de Christianis" => "Epistulae",
      "Homiliae" => "Homiliae",
      "Sermones in Deiparam" => "Sermones",
      "Carmen compunctorium (anacreonticum de extremo iudicio)" => "Carmina",
      "Poemata (PG 122 selection: In Canticum canticorum paraphrasis cum exegesi = poem 2; Versus de dogmate; " \
      "Synopsis canonum; Synopsis legum = poem 8, first pages only)" => "Poemata",
      "Versus in Leonem Philosophum (carmina de apostasia Leonis, cum responsione)" => "Versus",
      "Historia ecclesiastica, libri VIII-XIV (PG 146; books 1-7 and 15-18 are in PG 145/147, not served)" =>
        "Historia",
      "Epitome historiarum (lib. 1-12)" => "Historia",
      "Chronographia compendiaria" => "Chronographia",
      "Chronicon (continuatio) (redactio A) / Vitae imperatorum recentiorum" => "Chronicon",
      "Annales" => "Annales",
      "Basileiai (Regum libri quattuor)" => "Basileiai",
      "Commentarii in Octateuchum (catena-epitome, CPG 7430; as served: Genesis through Judges)" => "Commentarius",
      "Enarratio in Evangelium Joannis (complete across two volumes: PG123 John 1-7 + PG124 John 7:52-21:25)" =>
        "Enarratio",
      "Expositio in prophetam Habacuc" => "Expositio in",
      "Expositio in oracula Chaldaica + Expositio brevis dogmatum Chaldaicorum (the two Chaldaica of O'Meara's " \
      "Philosophica minora II, partial)" => "Expositio in",
      "Amphilochia, supplementum: fuller recensions of selected quaestiones" => "Amphilochia",
      "Oracula (cum vaticinio prosaico appendice)" => "Oracula",
      "Exapostilaria anastasima (cum theotokiis)" => "Exapostilaria",
      "Novellae constitutiones" => "Novellae",
      "Delectus legum compendiarius" => "Delectus",
      "Tomus synodicus contra Barlaam et Acindynum" => "Tomus",
      "Notitiae episcopatuum et documenta de praecedentia (Diatyposis Leonis; ps.-Epiphanii Ekthesis; " \
      "Notitia patriarchatuum; Ekthesis nea)" => "Notitiae",
      "Altera paraenesis ad Leonem filium" => "Paraenesis",
      "Institutio regia (Paideia basilike, ad Constantinum Ducam porphyrogenitum)" => "Institutio",
      "Characteres Gregorii Theologi, Basilii Magni, Chrysostomi et Gregorii Nysseni" => "Characteres",
      "Parastaseis syntomoi chronikai (with Peri theamaton section)" => "Parastaseis",
      "Quaestionum naturalium solutiones (anonymous compendium, Migne's title; akin to Symeon Seth)" =>
        "Quaestiones naturales",
      "Quaestiones et responsiones ad orthodoxos" => "Quaestiones",
      "Apologia secunda" => "Apologia",
      "Legatio sive Supplicatio pro Christianis" => "Legatio",
      "Antirrhetici contra Gregoram" => "Antirrhetici",
      "Dialogus cum Tryphone" => "Dialogus",
      "Vita Clementis Ohridensis (the long life, BHG 355)" => "Vita",
      "Encomium Gregorii Palamae" => "Encomium",
      "Occisorum Thessalonicae monodia" => "Monodia"
    }.each { |title, want| assert_equal want, head(title), title }
  end

  # Two-word heads outrank the one-word keyword at the same position.
  def test_a_compound_head_outranks_its_first_word
    assert_equal "Martyrium", head("Historia martyrii XV martyrum Tiberiopolitanorum (BHG 1199)")
    assert_equal "Fragmenta in", head("Fragmenta in epistulam ad Romanos (in catenis) [served text = full " \
                                      "ps.-Oecumenius catena commentary on Romans]")
    assert_equal "Fragmenta in", head("Fragmenta in Lucam (in catenis)")
  end

  # The earliest keyword in the title wins: the object a genre noun
  # governs never re-heads it.
  def test_the_earliest_keyword_wins
    assert_equal "Expositio in", head("Expositio in Epistolam ad Romanos (with prefixed hypothesis)")
    assert_equal "Epistulae", head("Epistula ecclesiae Smyrnensis de martyrio sancti Polycarpi")
    assert_equal "Laudatio", head("Ex laudatione martyris Demetrii narratio (on the 904 capture of Thessalonica)")
    assert_equal "Patria", head("De antiquitatibus Constantinopolitanis libri IV = Patria Constantinopoleos " \
                                "(Banduri's Anonymus; ends mid-book III)")
  end

  # Fragment / excerpt / preface words name a PART of a work: the genre
  # is the work's when the title names it, else the part word itself.
  def test_a_part_word_yields_to_the_genre_of_the_work_it_is_part_of
    assert_equal "Epistulae", head("Fragmenta ex epistolis (excerpts quoted in later writers; PG 5 fragment section)")
    assert_equal "Epistulae", head("Fragmentum synodicae epistulae (ad Victorem)")
    assert_equal "Apologia", head("Fragmentum apologiae (apud Eusebium, HE 4.3)")
    assert_equal "Vita", head("Excerpta e Vita S. Basilii iunioris (BHG 263)")
    assert_equal "Excerpta", head("Prooemium excerptorum de legationibus")
    assert_equal "Excerpta", head("Excerpta de legationibus")
    assert_equal "Fragmenta", head("Fragmenta")
    assert_equal "Fragmenta", head("Fragmentum ex libro de materia")
    assert_equal "Fragmenta", head("Fragmenta (ex libro adversus Marcionem, apud Eusebium HE 5.13)"),
                 "the parenthesis is never searched for the work a part belongs to"
    assert_equal "Fragmenta", head("Reliquiae plurium anonymorum (presbyterorum fragmenta)")
    assert_equal "Prooemium", head("Prooemium (to an exposition of the Psalms)")
    assert_equal "Commentarius",
                 head("Conclusion-fragment of a commentary on the Gospel of John (Jo 21:22-25 with account of John's " \
                      "death; supplement to the In Joannem)")
  end

  # A main title with no keyword consults its parenthesis for a GLOSS
  # only (homily, sermon, chronicle, history) — never for any other
  # keyword: "(chs. 33-70 of the dialogue)" or "(cum pinace et prooemio)"
  # describe the book, not its genre.
  def test_the_parenthesis_lends_only_a_genre_gloss
    assert_equal "Homiliae", head("Orationes (homiliae et panegyrici) I-XX (collectio Combefis)")
    assert_equal "Sermones", head("Oratio in venerationem crucis (mid-Lent sermon; conventional title)")
    assert_equal "Chronicon", head("De annis ab orbe condito (Chronicon breve, from Adam to 1453)")
    assert_equal "Historia", head("Scylitzes Continuatus (Migne: Joannes Scylitzes Curopalata, Excerpta ex " \
                                  "Breviario historico)")
    assert_equal "De sacramentis", head("De sacramentis (chs. 33-70 of the dialogue)")
    assert_equal "Tactica", head("Tactica (cum pinace et prooemio)")
  end

  # The Latin "In <book>" commentary title with no genre noun.
  def test_an_in_title_is_the_commentary_form
    assert_equal "In", head("In Proverbia (catena-epitome, CPG 7432; Procopian authorship of the epitome doubted)")
    assert_equal "In", head("In Mercurii Trismegisti Pimandrum (brief note)")
    assert_equal "Scholia", head("In libros Regum et Paralipomenon scholia (CPG 7431)")
    assert_equal "Commentarius", head("In Acta apostolorum commentarius alter (second text, with ΠΡΟΛΟΓΟΣ " \
                                      "ΘΕΟΦΥΛΑΚΤΟΥ; TEXTUS/ΕΡΜΗΝΕΙΑ alternation)")
  end

  # No keyword anywhere: the title (to its first clause break) IS the
  # head — a "De <topic>" treatise names a topic, so the map folds it
  # title by title.
  def test_a_keywordless_title_is_its_own_head
    assert_equal "De sacra liturgia", head("De sacra liturgia (chs. ~78-100 of the dialogue)")
    assert_equal "De sancto oleo", head("De sancto oleo / euchelaeo (chs. ~282-295 of the dialogue)")
    assert_equal "De cerimoniis aulae Byzantinae", head("De cerimoniis aulae Byzantinae (lib. 1.84-2.56)")
    assert_equal "Expositio de divino templo", head("Expositio de divino templo (sent to the pious in Crete)")
    assert_equal "Oratio in praesentationem Deiparae", head("Oratio in praesentationem Deiparae")
    assert_equal "Logos dialektikos",
                 head("Logos dialektikos / Oratio dialectica de pane mystico Graecorum et azymo Latinorum")
    assert_equal "Λόγοι δύο", head("Λόγοι δύο")
    assert_equal "Ad Autolycum", head("Ad Autolycum")
  end

  def test_an_empty_title_makes_no_claim
    assert_nil head(nil)
    assert_nil head("  ")
  end

  # The head is a single fragment for the kind fold: never carries the
  # fold's composite separators.
  def test_a_head_never_carries_the_fold_separators
    head = head("De fine et exsequiarum ordine (De ordine sepulturae; chs. ~359-373 of the dialogue)")
    assert_equal "De fine et exsequiarum ordine", head
    refute_match(/[|;]/, head)
  end
end
