# frozen_string_literal: true

require "test_helper"

# BlbooksTitleGenre: the BL catalogue title → one form-noun head. Every
# title below is a real record title from the pre-1800 cone (census
# 2026-11-08), so the ladder is pinned against upstream's own spellings.
class BlbooksTitleGenreTest < Minitest::Test
  Genre = Nabu::Adapters::BlbooksTitleGenre

  HEADS = {
    "The Roman Actor; a tragædie [in five acts and in verse]" => "Tragedy",
    "Lingua: Or, the Combat of the Tongue and the five Senses for superiority. A pleasant Comœdie" => "Comedy",
    "The Renegado, a tragæcomedie [in five acts and in verse]" => "Tragicomedy",
    "The Emperour of the East. A Tragæ-Comedie [in five acts and in verse]" => "Tragicomedy",
    "The Deserving Favorite [A tragi-comedy.]" => "Tragicomedy",
    "North-ward Hoe. Sundry times acted by the children of Paules." => "Play",
    "Catiline his Conspiracy [A tragedy, in five acts and in verse.]" => "Play",
    "Cymon. A dramatic romance, etc [By David Garrick.]" => "Play",
    "Thomas and Sally: or, the Sailor's Return. A musical entertainment" => "Entertainment",
    "The Hero. A poetical epistle, respectfully addressed to Marquis Cornwallis" => "Poem",
    "Paradisus Amissa, poema heroicum, quod a Joanne Miltono Anglo Anglice scriptum" => "Poem",
    "The Poeticall Essayes of Sam. Danyel. Newly corrected and augmented" => "Poem",
    "Ro. vrbis excidium [In verse.]" => "Verse",
    "Atalanta. Canto 1 [Poems. By Robert Colvill.]" => "Poem",
    "A Collection of English, Scots, and Irish songs and other poetical pieces" => "Song",
    "An Essay on Criticism ... The sixth edition, corrected" => "Essay",
    "A Satyr against Vertue." => "Satire",
    "Love in Excess; or, the Fatal Enquiry. A novel" => "Novel"
  }.freeze

  def test_real_titles_head_by_the_ladder
    HEADS.each { |title, head| assert_equal head, Genre.head(title), title }
  end

  def test_a_title_without_a_form_word_makes_no_claim
    assert_nil Genre.head("Piutarchi Chaeronensis Regum  Imperatorum Apophthegmata")
    assert_nil Genre.head("Seianus his fall. L.P. Few MS. corrections [by the author?]")
    assert_nil Genre.head(nil)
  end
end
