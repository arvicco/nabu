# frozen_string_literal: true

require "test_helper"

# PleiasTitleGenre — the French title → form-noun head extraction (the
# kind fold's mechanical half). Titles are real cone titles from the
# 2026-11-13 census of PleIAs/French-PD-Books (entities decoded).
class PleiasTitleGenreTest < Minitest::Test
  G = Nabu::Adapters::PleiasTitleGenre

  def test_royal_acts_head_in_their_period_spellings
    assert_equal "Édit", G.head("Édict du roy, pour la vente et allienation à faculté de rachapt perpetuel")
    assert_equal "Édit", G.head("Edict du Roy, portant des-union des quatre charges & qualitez de presidens")
    assert_equal "Déclaration", G.head("Declaration du roy sur le fait des monnoyes . Verifiée par arrest")
    assert_equal "Arrêt", G.head("Arrest de la cour de Parlement, portant defenses à toutes personnes")
    assert_equal "Coutume", G.head("Les coustumes générales des pays et duché de Bretagne")
  end

  def test_the_earliest_keyword_wins_and_compounds_beat_their_parts
    assert_equal "Lettres patentes",
                 G.head("Lettres patentes du roy, portant continuation aux ecclésiastiques … Avec règlement")
    assert_equal "Déclaration", G.head("Lettres de déclaration du Roy, portant permission à ses subjects")
    assert_equal "Tragi-comédie", G.head("Roxane, tragi-comédie")
    assert_equal "Oraison funèbre", G.head("Oraison funèbre de Louis XIII,... prononcée à Pontoise")
  end

  def test_the_form_word_anywhere_in_the_title_counts
    assert_equal "Comédie", G.head("Amphitryon , comédie, par J.-B. P. de Molière")
    assert_equal "Triolet", G.head("Triolets sur la jonction des princes, pour la deroute des Mazarins")
    assert_equal "Poème", G.head("L'Hiver de Versailles , poëme de Mademoiselle D. S. A.")
  end

  def test_topic_words_make_no_claim
    assert_nil G.head("Les oeuvres de Cornelius Tacitus et de Velleius Paterculus")
    assert_nil G.head("Histoire généalogique de la royale maison de Savoie")
    assert_nil G.head("Relation veritable du voyage que François Michel habitant de la ville")
    assert_nil G.head("")
    assert_nil G.head(nil)
  end
end
