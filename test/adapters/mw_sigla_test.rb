# frozen_string_literal: true

require "test_helper"

module Adapters
  # The MW sigla → GRETIL crosswalk (Nabu::Adapters::MwSigla): siglum
  # recognition, the four tiers, and the per-work citation templates that
  # carry a printed MW reference onto a GRETIL passage citation.
  class MwSiglaTest < Minitest::Test
    SIGLA = Nabu::Adapters::MwSigla

    # -- Manusmṛti / Aṣṭādhyāyī at passage grain ----------------------------------

    # GRETIL's sa_manusmRti now parses at verse grain (lg xml:id Manu_A.V →
    # "A.V") and sa_pANini-aSTAdhyAyI at sūtra grain ("|| PS_A,P.S ||" →
    # "A,P.S"), so MW's two most-cited held śāstras resolve to passages.
    def test_manusmrti_citations_normalize_to_the_gretil_verse_shape
      assert_equal ["urn:nabu:gretil:sa_manusmRti", "2.54"], SIGLA.resolve("Mn. ii, 54")
      assert_equal ["urn:nabu:gretil:sa_manusmRti", "8.120"], SIGLA.resolve("Mn. viii, 120")
      assert_equal :passage, SIGLA.classify("Mn. xii, 9")
    end

    def test_astadhyayi_citations_normalize_to_the_gretil_sutra_shape
      assert_equal ["urn:nabu:gretil:sa_pANini-aSTAdhyAyI", "7,4.3"], SIGLA.resolve("Pāṇ. vii, 4, 3")
      assert_equal ["urn:nabu:gretil:sa_pANini-aSTAdhyAyI", "6,2.161"], SIGLA.resolve("Pāṇ. vi, 2, 161")
    end

    # A bare siglum (3,609 "Mn." and 683 "Pāṇ." upstream) names the work, not
    # a passage: document grain, honestly.
    def test_bare_and_partial_references_stay_document_grain
      assert_equal ["urn:nabu:gretil:sa_manusmRti", nil], SIGLA.resolve("Mn.")
      assert_equal ["urn:nabu:gretil:sa_manusmRti", nil], SIGLA.resolve("Mn. viii")
      assert_equal ["urn:nabu:gretil:sa_manusmRti", nil], SIGLA.resolve("Mn. viii f.")
      assert_equal :document, SIGLA.classify("Pāṇ.")
    end

    # -- tail shapes the print actually carries ------------------------------------

    # A sentence-final period rides inside the <ls> on ~1 in 4 numbered
    # citations ("Mn. viii, 120." — 202 of the viii-book alone).
    def test_a_trailing_period_does_not_demote_a_citation
      assert_equal "6,2.193", SIGLA.resolve("Pāṇ. vi, 2, 193.").last
      assert_equal "8.120", SIGLA.resolve("Mn. viii, 120.").last
    end

    # The @n restoration joins the elided context with a SPACE, and upstream's
    # @n sometimes stops before its comma (<ls n="Pāṇ. iv, 3">5</ls> →
    # "Pāṇ. iv, 3 5"; <ls n="Pāṇ. iv">2, 3</ls> → "Pāṇ. iv 2, 3").
    def test_restored_labels_without_the_elided_comma_still_normalize
      assert_equal "4,3.5", SIGLA.resolve("Pāṇ. iv, 3 5").last
      assert_equal "4,2.3", SIGLA.resolve("Pāṇ. iv 2, 3").last
    end
  end
end
