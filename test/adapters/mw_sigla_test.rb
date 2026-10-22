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

    # -- the full works-and-authors key (config/mw_sigla.yml) -------------------------

    def test_the_full_871_row_key_loads_with_cdsl_ids_expansions_and_types
      assert_equal 871, SIGLA::KEY.values.sum(&:size)
      manu = SIGLA.key_rows("Mn.")
      assert_equal([%w[05:17 Manu-smṛti Title]], manu.map { |row| [row.id, row.expansion, row.type] })
      assert_equal "Literary category", SIGLA.key_rows("Kāv.").first.type
      assert_empty SIGLA.key_rows("Xyz.")
    end

    # Six sigla carry two expansions upstream — both rows kept, never one
    # picked.
    def test_ambiguous_sigla_keep_every_upstream_row
      assert_equal 2, SIGLA.key_rows("Ratnāv.").size
    end

    # The key's multi-word sigla are recognized whole: "Sāy. on AitBr." is
    # Sāyaṇa's commentary on the Aitareya-brāhmaṇa (a title), not the bare
    # authority label "Sāy."; edition-qualified MBh. sigla stay MBh.-shaped.
    def test_multi_word_keyed_sigla_are_recognized_whole
      assert_equal "Sāy. on AitBr.", SIGLA.siglum_of("Sāy. on AitBr.")
      assert_equal :unheld, SIGLA.classify("Sāy. on AitBr.")
      assert_equal "Sāy.", SIGLA.siglum_of("Sāy.")
      assert_equal "MBh. (ed. Bomb.)", SIGLA.siglum_of("MBh. (ed. Bomb.) iii, 13220")
    end

    # The key's edition-qualified sigla name a held work in an edition whose
    # numbering is not GRETIL's: the work resolves, the tail never does.
    # "Yājñ., Sch." is the Mitākṣarā, a file of its own.
    def test_edition_qualified_and_commentary_sigla_cross_walk_at_document_grain
      assert_equal ["urn:nabu:gretil:sa_rAmAyaNa", nil], SIGLA.resolve("R. (B.) ii, 14, 3")
      assert_equal ["urn:nabu:gretil:sa_rAmAyaNa", "2.014.003"], SIGLA.resolve("R. ii, 14, 3")
      assert_equal ["urn:nabu:gretil:sa_vijJAnezvara-mitAkSarA", nil], SIGLA.resolve("Yājñ., Sch.")
      assert_equal :unheld, SIGLA.classify("Hariv. (Langlois' transl.)"), "a translation, not the text"
    end

    # The two judgment layers live in the same config: every crosswalked
    # work and every authority label is itself a row of MW's key.
    def test_crosswalk_and_authority_layers_are_keyed_sigla
      assert_equal "urn:nabu:gretil:sa_Rgveda-edAufrecht", SIGLA::WORKS.fetch("RV.").urn
      assert_equal "%d.%03d.%02d", SIGLA::WORKS.fetch("RV.").format
      assert_nil SIGLA::WORKS.fetch("Hariv.").format
      (SIGLA::WORKS.keys + SIGLA::AUTHORITY).each do |siglum|
        refute_empty SIGLA.key_rows(siglum), "#{siglum} is not a row of MW's key"
      end
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
