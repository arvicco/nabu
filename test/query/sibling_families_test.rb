# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Query
  # Nabu::Query::SiblingFamilies (P34-0): the registry-declared work-pattern
  # compiler behind `--parallel`. A source row's `siblings:` key declares the
  # variant-suffix grammar its adapter mints; the compiler turns those
  # declarations into the ONE generic matcher Query::Parallel consults —
  # retiring the per-source frozen regex constants (each new sibling shape
  # used to be an owner repro + a code rider: P29, P30, P32).
  class SiblingFamiliesTest < Minitest::Test
    # -- variant families -----------------------------------------------------

    def test_literal_tail_strips_and_bare_work_matches_itself
      families = families_for({ "damaskini" => ["-en"] })

      match = families.match("urn:nabu:damaskini:veles--trojanskata-en")
      assert_equal "urn:nabu:damaskini:veles--trojanskata", match.work
      assert_equal :variant, match.family

      bare = families.match("urn:nabu:damaskini:veles--trojanskata")
      assert_equal "urn:nabu:damaskini:veles--trojanskata", bare.work,
                   "hyphen-rich stems split ONLY at the declared literal tail"
    end

    def test_alternation_tail_covers_every_declared_variant
      families = families_for({ "itant" => ["-(eng|ita|dipl)"] })

      %w[-eng -ita -dipl].each do |tail|
        match = families.match("urn:nabu:itant:oscan-2#{tail}")
        assert_equal "urn:nabu:itant:oscan-2", match.work, "#{tail} must strip"
      end
      assert_equal "urn:nabu:itant:oscan-2", families.match("urn:nabu:itant:oscan-2").work
    end

    def test_open_grammar_tail_the_oracc_shape
      families = families_for({ "oracc" => ["-[a-z]+"] })

      match = families.match("urn:nabu:oracc:saao-saa01:P224395-en")
      assert_equal "urn:nabu:oracc:saao-saa01:P224395", match.work,
                   "the hyphen-rich project segment never splits — only the terminal variant run"
      assert_equal "urn:nabu:oracc:saao-saa01:P224395",
                   families.match("urn:nabu:oracc:saao-saa01:P224395").work
    end

    def test_multi_segment_tail_the_freising_shape
      families = families_for({ "freising" => ["-[a-z-]+"] })

      assert_equal "urn:nabu:freising:bs1", families.match("urn:nabu:freising:bs1-tr-eng").work
      assert_equal "urn:nabu:freising:bs1", families.match("urn:nabu:freising:bs1").work
    end

    def test_multiple_literal_tails_the_isicily_shape
      families = families_for({ "isicily" => ["-en", "-it", "-translit"] })

      %w[-en -it -translit].each do |tail|
        assert_equal "urn:nabu:isicily:isic000006",
                     families.match("urn:nabu:isicily:isic000006#{tail}").work
      end
      assert_equal "urn:nabu:isicily:isic000006",
                   families.match("urn:nabu:isicily:isic000006").work
    end

    def test_undeclared_namespaces_have_no_family
      families = families_for({ "damaskini" => ["-en"] })

      assert_nil families.match("urn:nabu:ddbdp:aegyptus:89:240"),
                 "papyri and treebanks keep no work notion"
      assert_nil families.match("urn:nabu:suttacentral:mn1-en"),
                 "an undeclared sibling-minting source stays invisible until its row declares"
    end

    # -- the CTS dotted-version form ------------------------------------------

    def test_cts_declaration_matches_the_dotted_edition_form
      families = families_for({}, cts: true)

      match = families.match("urn:cts:greekLit:tlg0012.tlg001.perseus-grc2")
      assert_equal "urn:cts:greekLit:tlg0012.tlg001", match.work
      assert_equal :cts, match.family
      assert_nil families.match("urn:cts:greekLit:tlg0012.tlg001"),
                 "a bare CTS work is not a document urn — editions are dotted"
    end

    def test_without_the_cts_declaration_cts_urns_have_no_family
      families = families_for({ "damaskini" => ["-en"] })
      assert_nil families.match("urn:cts:greekLit:tlg0012.tlg001.perseus-grc2")
    end

    # -- the shipped registry (the migration guard) ---------------------------

    # The ten frozen work patterns retired at P34-0 must all be reproduced by
    # the SHIPPED config/sources.yml declarations — a yaml edit that silently
    # drops a family fails HERE, not in a live --parallel session.
    def test_shipped_registry_declares_every_retired_family
      families = Nabu::Query::SiblingFamilies.default

      {
        # CTS (P7-4)
        "urn:cts:greekLit:tg1.w1.perseus-eng10" => ["urn:cts:greekLit:tg1.w1", :cts],
        # ORACC (P13-4)
        "urn:nabu:oracc:saao-saa01:P224395-en" => ["urn:nabu:oracc:saao-saa01:P224395", :variant],
        # Freising (P13-11)
        "urn:nabu:freising:bs1-tr-eng" => ["urn:nabu:freising:bs1", :variant],
        # Damaskini (P23-1)
        "urn:nabu:damaskini:veles--trojanskata-en" => ["urn:nabu:damaskini:veles--trojanskata", :variant],
        # SuttaCentral (P26-1)
        "urn:nabu:suttacentral:dhp21-32-en" => ["urn:nabu:suttacentral:dhp21-32", :variant],
        # TLA-HF (P28-2)
        "urn:nabu:tla-hf:late-egyptian-v19-de" => ["urn:nabu:tla-hf:late-egyptian-v19", :variant],
        # AES (P28-0)
        "urn:nabu:aes:tuebingerstelen:3F5KGKNJINFHNBIWJMSXWDMV4Q-de" =>
          ["urn:nabu:aes:tuebingerstelen:3F5KGKNJINFHNBIWJMSXWDMV4Q", :variant],
        # RIIG (P25-1, wired at P30 review)
        "urn:nabu:riig:all-01-01-fr" => ["urn:nabu:riig:all-01-01", :variant],
        # OpenEtruscan (P29-0, wired at P30 review)
        "urn:nabu:open-etruscan:cr-2.20-en" => ["urn:nabu:open-etruscan:cr-2.20", :variant],
        # Corpus ItAnt (P29-2, wired at P30 review)
        "urn:nabu:itant:oscan-2-dipl" => ["urn:nabu:itant:oscan-2", :variant],
        # ETCSL (P31-5)
        "urn:nabu:etcsl:1.8.2.1-en" => ["urn:nabu:etcsl:1.8.2.1", :variant],
        # I.Sicily (P34-0 — the newly declared eleventh family)
        "urn:nabu:isicily:isic000006-translit" => ["urn:nabu:isicily:isic000006", :variant]
      }.each do |urn, (work, family)|
        match = families.match(urn)
        refute_nil match, "the shipped registry must declare a family for #{urn}"
        assert_equal work, match.work, urn
        assert_equal family, match.family, urn
      end
    end

    private

    # Compile families from an in-memory registry shaped like sources.yml.
    def families_for(variants, cts: false)
      yaml = +""
      yaml << "perseus-greek:\n  adapter: Nabu::Adapters::Perseus\n  siblings: cts\n" if cts
      variants.each do |slug, tails|
        yaml << "#{slug}:\n  adapter: Some::Adapter\n  siblings: [#{tails.map(&:inspect).join(', ')}]\n"
      end
      registry = Dir.mktmpdir do |dir|
        path = File.join(dir, "sources.yml")
        File.write(path, yaml)
        break Nabu::SourceRegistry.load(path)
      end
      Nabu::Query::SiblingFamilies.from_registry(registry)
    end
  end
end
