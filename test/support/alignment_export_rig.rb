# frozen_string_literal: true

require "json"
require "tmpdir"

# The alignment-hub rig the align and collation export tests share: an
# in-memory catalog + fulltext, a proiel-citation registry over seeded
# witness sentences, the ref index built. Real MARK 2.3 / 2.4 texts (the
# collation golden's PROIEL and Vulgate Latin, the PROIEL and SBLGNT Greek)
# with the token shapes the treebanks store: PROIEL positional
# `morphology` + `lemma`, UD `feats`, and a bare form-only token.
# Including classes also include StoreTestDB (support files load
# alphabetically, so this module cannot name it at load time).
module AlignmentExportRig
  GREEK_PROIEL = "καὶ ἔρχονται φέροντες πρὸς αὐτὸν παραλυτικὸν αἰρόμενον ὑπὸ τεσσάρων."
  GREEK_SBLGNT = "καὶ ἔρχονται ⸂φέροντες πρὸς αὐτὸν παραλυτικὸν⸃ αἰρόμενον ὑπὸ τεσσάρων."
  LATIN_PROIEL = "et venerunt ferentes ad eum paralyticum qui a quattuor portabatur"
  LATIN_VULGATE = "Et venerunt ad eum ferentes paralyticum, qui a quatuor portabatur."

  def rig_setup
    @catalog = store_test_db
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    @sources = {}
  end

  def rig_teardown
    @fulltext.disconnect
  end

  def rig_source(slug, license_class)
    @sources[slug] ||= Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter",
                                                  license_class: license_class)
  end

  # One witness sentence; +tokens+ default to one form-only token per word.
  def seed_witness(urn, slug:, license:, language:, text:, ref: "MARK 2.3", tokens: nil)
    source = rig_source(slug, license)
    unless @catalog[:documents].where(urn: urn).get(:id)
      @catalog[:documents].insert(source_id: source.id, urn: urn, title: urn.split(":").last, language: language,
                                  content_sha256: "x", revision: 1, withdrawn: false)
    end
    doc_id = @catalog[:documents].where(urn: urn).get(:id)
    seq = @catalog[:passages].where(document_id: doc_id).count
    tokens ||= text.split.map { |form| { "form" => form } }
    tokens = tokens.map { |token| { "citation_part" => ref }.merge(token) }
    @catalog[:passages].insert(document_id: doc_id, urn: "#{urn}:s#{seq}", sequence: seq, language: language,
                               text: text, text_normalized: text, content_sha256: "x", revision: 1,
                               withdrawn: false,
                               annotations_json: JSON.generate("citation" => ref, "tokens" => tokens))
  end

  def rig_registry(entries)
    rows = entries.map { |urn, label| "    - document: #{urn}\n      label: #{label}" }
    yaml = "nt:\n  title: \"New Testament (parallel witnesses)\"\n  witnesses:\n#{rows.join("\n")}\n"
    registry = Dir.mktmpdir do |dir|
      path = File.join(dir, "alignments.yml")
      File.write(path, yaml)
      Nabu::AlignmentRegistry.load(path)
    end
    Nabu::Store::AlignmentIndexer.rebuild!(catalog: @catalog, fulltext: @fulltext, registry: registry)
    registry
  end

  # The four-witness NT layout: Greek PROIEL (positional morphology), Latin
  # PROIEL (UD feats), SBLGNT and the Vulgate (form-only), MARK 2.3 + a
  # Greek/Latin-PROIEL-only MARK 2.4.
  def seed_nt
    greek = [{ "form" => "καὶ", "lemma" => "καί", "morphology" => "---------n" },
             { "form" => "ἔρχονται", "lemma" => "ἔρχομαι", "morphology" => "3ppimd---i" }]
    latin = [{ "form" => "et", "lemma" => "et", "feats" => "" },
             { "form" => "venerunt", "lemma" => "venio", "feats" => "Mood=Ind|Number=Plur|Person=3|Tense=Past" }]
    seed_witness("urn:nabu:proiel:greek-nt", slug: "proiel", license: "nc", language: "grc", text: GREEK_PROIEL,
                                             tokens: greek)
    seed_witness("urn:nabu:proiel:latin-nt", slug: "proiel", license: "nc", language: "lat", text: LATIN_PROIEL,
                                             tokens: latin)
    seed_witness("urn:nabu:sblgnt:mark", slug: "sblgnt", license: "attribution", language: "grc",
                                         text: GREEK_SBLGNT)
    seed_witness("urn:nabu:vulgate:mark", slug: "vulgate", license: "open", language: "lat", text: LATIN_VULGATE)
    seed_witness("urn:nabu:proiel:greek-nt", slug: "proiel", license: "nc", language: "grc",
                                             text: "καὶ εἰσελθὼν", ref: "MARK 2.4")
    seed_witness("urn:nabu:proiel:latin-nt", slug: "proiel", license: "nc", language: "lat",
                                             text: "et ingressus", ref: "MARK 2.4")
    rig_registry([["urn:nabu:proiel:greek-nt", "greek-nt"], ["urn:nabu:proiel:latin-nt", "latin-nt"],
                  ["urn:nabu:sblgnt:mark", "sblgnt"], ["urn:nabu:vulgate:mark", "vulgate"]])
  end

  def table_rows(table)
    collected = []
    table.each_row { |row| collected << [table.columns.map(&:name).zip(row.values).to_h, row.draws] }
    collected
  end
end
