# frozen_string_literal: true

require "uri"

require_relative "../file_fetch"
require_relative "ocaml_marshal_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # sigla (P142): SigLA — The Signs of Linear A: a paleographical
    # database (Ester Salgarella & Simon Castellan; sigla.phis.me). The
    # Linear A corpus as a sign-by-sign record: every inscription's sign
    # attestations, each classified (syllabogram in a word, logogram,
    # fraction, transaction sign, erasure) and read (transnumeration,
    # phonetic value, variant, certainty), with the word grouping, the
    # find-place, the ceramic-phase period, the dimensions and — on
    # sealed documents — the CMS seal reference. Footer, verbatim
    # (re-read 2026-10-22): "Dataset and drawings are available under
    # the CC BY-NC-SA 4.0 license." → license_class nc.
    #
    # == Delivery (probed 2026-10-22)
    #
    # The site is a static js_of_ocaml app; the WHOLE database ships as
    # ONE file, https://sigla.phis.me/database.js (2,516,528 bytes,
    # Last-Modified 2026-06-26, lighttpd ETag) — two JS variables,
    # `signs` and `data`, each a single-quoted JS literal holding a
    # quoted OCaml string literal whose every byte is a \\DDD decimal
    # escape: the bytes are an OCaml Marshal payload (small header). No
    # JSON/SQL export is served (database.json, data.json … answer 404;
    # the paper's "JSON database" is the import tool's intermediate, not
    # a published file) and no public repository exists. The other
    # grains — the per-document HTML render pages
    # (document/<id>/index.html), browse.html, the sign pages and the
    # tablet drawings — are VIEWS of this same database (and images),
    # never fetched: database.js is the one canonical artifact, pinned
    # by FileFetch's sha256.
    #
    # == The schema (decoded first-hand; field positions are OCaml's)
    #
    #   signs = {map: int → sign, series: ["AB"; "A"]}
    #   sign  = (series, number, Some (value, Some homophone)?,
    #            Some representative-drawing-ref?, Some latin-name?,
    #            [(variant, ref)], flag, Some (description, _)?,
    #            Some composition?)
    #   data  = {map: id → {document}}
    #   document = (meta, "document/<id>", [|words|], (px w, px h),
    #               [|attestations|])
    #   meta  = (typology, id, site, _, _, _, Some (w, h, d) cm?,
    #            Some period?, Some corpus-url?, Some seal?, _, _)
    #   seal  = (impressions, Some CMS ref?, Some motif?, Some URL?)
    #   attestation = (Some document, reading, number, role, flag4,
    #                  _, flag6, (x, y, w, h))
    #   reading = 0 unreadable (breakage) | 1 unclassified |
    #             ((sign, Some variant?), certain)
    #   role  = (InWord (position, word) | 0 logogram | 1 fraction |
    #            2 transaction sign | 3 erasure, flag)
    #   word  = (Some document, [attestations], (flag, flag), index)
    #
    # Every attestation carries its own full COPY of the sign record
    # (censused 2026-10-22: 4,756 read attestations, all identical to
    # the sign list's entry; 4 signs absent from the list ride bare), so
    # only `data` is decoded — the `signs` sign list (376 signs with
    # representative drawings, variants and descriptions) is a reference
    # table, not ingested here (a sign-card shelf is a later candidate).
    #
    # The role and reading constructors are pinned against the site's
    # own rendering of the same documents (document/ARKH 1a and HT 10a:
    # "Syllabogram / Logogram / Transaction sign / Fraction / Erasure",
    # "[?]" for an unread sign) and the help page's reading syntax.
    # Flags whose meaning neither the site nor the paper states (the
    # attestation's role/4th/6th flags, the word's flag pair) ride the
    # annotations RAW under "flags" — preserved, never interpreted.
    #
    # == Documents and passages
    #
    # One document per inscription (urn:nabu:sigla:<id> with spaces as
    # "_": ARKH_1a, HT_79+83, KN_Wc_<24a> — upstream's own GORILA-style
    # designations, verbatim otherwise). SigLA records NO line
    # structure (a sign's place is its bounding box on the drawing), so
    # the passage grain is upstream's own unit: the SIGN GROUP — each
    # word (its syllabograms joined with "-") and each standalone sign
    # (logogram, fraction, transaction sign, erasure), in the order of
    # upstream's attestation numbers (#1…#n, the site's own), cited by
    # the group's first attestation number (urn …:ARKH_1a:5 = the word
    # beginning at #5). A word interrupted by another sign (15 such in
    # the corpus) keeps all its signs; the interrupting sign is its own
    # passage. Sign-level data (number, standard name, value, role,
    # variant, certainty, composition, bounding box) rides the passage's
    # "signs" annotation. Numerals are NOT recorded by SigLA (a
    # palaeographic database of signs, not of quantities) — declared,
    # not lost here.
    #
    # Text rendering (our own, consistent): a syllabogram by its
    # phonetic value (homophones subscripted: ra₂), else its standard
    # name (AB118, A325); a logogram or fraction by its Latin name when
    # the sign list gives one (VIN, GRA, J), else its standard name
    # (AB16); a variant letter suffixes a standalone sign (VINb); an
    # uncertain reading takes SigLA's own "?" suffix (A01?); an
    # unreadable or unclassified sign is "?"; an erasure is bracketed
    # ⟦…⟧. Standard names are zero-padded like the site's (AB03).
    #
    # Rejected by rule (discovery_skips): documents with NO sign
    # attestation (15 in the 2026-10-22 census — catalogued, nothing to
    # read) and any rendered page grain found in the workdir.
    #
    # == Axes (aggressive mining)
    #
    # Period: the meta's ceramic-phase label (LM IB 640 · MM IIB 34 ·
    # MM IIIB 28 · MM II 19 · LM IA 18 · LM I 17 …) rides "period" and
    # bands through config/period_bands.yml's Aegean rows via
    # MetadataDates :period_label; "" mints nothing, "unknown"/"n/a"
    # ride verbatim and band nothing. Place: the site (Haghia Triada,
    # Khania, Phaistos …) as the "place" hash's ancient name, verbatim
    # (upstream's "GOURNIA"/"Gournia" casing split kept). Kind: the
    # typology facet ("object": Tablet, Nodule, Roundel, Libation
    # table …) folds in config/kind_map.yml. Dimensions, the seal (CMS
    # reference, motif, impression count, Arachne URL), the corpus URL
    # (upstream's "missing" sentinel mints nothing), the drawing's pixel
    # size and the site permalink ride as metadata.
    class Sigla < Nabu::Adapter
      BASE_URL = "https://sigla.phis.me"
      FILENAME = "database.js"
      DATABASE_URL = "#{BASE_URL}/#{FILENAME}".freeze
      URN_PREFIX = "urn:nabu:sigla:"
      LANGUAGE = "lab"

      MANIFEST = Nabu::SourceManifest.new(
        id: "sigla",
        name: "SigLA — The Signs of Linear A: a paleographical database (Salgarella & Castellan)",
        license: "Site footer, verbatim: \"Dataset and drawings are available under the CC BY-NC-SA 4.0 " \
                 "license.\" — © 2020- Ester Salgarella and Simon Castellan",
        license_class: "nc",
        upstream_url: DATABASE_URL,
        parser_family: "ocaml-marshal"
      )

      # The role constructors (constant constructors of the role variant,
      # in declaration order; the non-constant InWord is a block).
      ROLES = { 0 => "logogram", 1 => "fraction", 2 => "transaction", 3 => "erasure" }.freeze
      READING_STATUS = { 0 => "unreadable", 1 => "unclassified" }.freeze
      SUBSCRIPT = "₀₁₂₃₄₅₆₇₈₉"
      # Upstream's no-URL sentinel in the corpus-link field.
      MISSING = "missing"
      # The rendered-page grain (a view of the database, never fetched).
      PAGE_GRAIN = %r{\Adocument/[^/]+/index\.html\z}

      # The two JS variables → their raw Marshal bytes. Each value is
      # '"\\DDD\\DDD…"' — the JS literal's "\\" is one backslash, the
      # OCaml literal's \DDD one decimal byte; nothing else occurs (the
      # 2026-10-22 census), and anything else is refused, never guessed.
      JS_VARIABLE = /^var (\w+) = '"(.*)"';$/
      ESCAPED_BYTES = /\A(?:\\\\\d{3})*\z/

      # Group = one passage: the attestations it holds, in reading order.
      Group = Data.define(:kind, :attestations, :word)

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      # HEAD database.js: reachability + Last-Modified drift against the
      # .file-fetch.json pin. No license endpoint — the footer is re-read
      # at the real fetch (drift-on-refetch is the license watch).
      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: DATABASE_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # -- fetch -------------------------------------------------------------

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: DATABASE_URL, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "sigla fetch failed into #{workdir}: #{e.message}"
      end

      # -- discover ----------------------------------------------------------

      # One ref per inscription carrying at least one sign attestation,
      # in upstream's map (id) order. A workdir without database.js
      # yields nothing (the pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = database_path(workdir) or return
        database(path).fetch(:documents).each do |id, document|
          next if attestations(document).empty?

          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: urn_for(id),
            path: File.expand_path(path), metadata: { "id" => id }
          )
        end
      end

      def discovery_skips(workdir)
        empty = []
        if (path = database_path(workdir))
          database(path).fetch(:documents).each { |id, document| empty << id if attestations(document).empty? }
        end
        pages, strays = stray_files(workdir).partition { |rel| rel.match?(PAGE_GRAIN) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: empty.size + pages.size, unrecognized: strays.size,
          notes: empty.map { |id| "no sign attestation recorded: #{id}" } +
                 pages.map { |rel| "rendered page grain (a view of database.js), not ingested: #{rel}" } +
                 strays.map { |rel| "non-corpus file: #{rel}" }
        )
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        db = database(document_ref.path)
        id = document_ref.metadata.fetch("id")
        record = db.fetch(:documents).fetch(id) do
          raise Nabu::ParseError, "#{document_ref.path}: no SigLA document #{id.inspect}"
        end
        atts = attestations(record)
        raise Nabu::DocumentSkipped.new(reason: "no sign attestation") if atts.empty?

        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: SourceRead.nfc(id, language: LANGUAGE), metadata: metadata_for(record, atts)
        )
        groups(record, atts).each_with_index do |group, index|
          document << passage_for(document_ref.id, group, index)
        end
        document
      end

      private

      def database_path(workdir)
        path = File.join(workdir, FILENAME)
        File.file?(path) ? path : nil
      end

      def urn_for(id) = "#{URN_PREFIX}#{SourceRead.nfc(id, language: LANGUAGE).tr(' ', '_')}"

      # The decoded database, memoized per file identity (path + size +
      # mtime): one decode serves discover and every parse.
      def database(path)
        stat = File.stat(path)
        key = [File.expand_path(path), stat.size, stat.mtime.to_r]
        return @database if @database_key == key

        @database_key = key
        @database = decode_database(path)
      end

      def decode_database(path)
        data = OcamlMarshalParser.decode(js_payloads(SourceRead.utf8_file(path, label: "sigla database.js"),
                                                     path).fetch("data"))
        { documents: OcamlMarshalParser.map_entries(data[0]).to_h { |id, wrapper| [id, wrapper[0]] } }
      rescue KeyError => e
        raise Nabu::ParseError, "#{path}: SigLA database.js lacks a payload (#{e.message})"
      end

      # The JS variables' raw Marshal bytes (see #js_payloads).
      def js_payloads(text, path)
        text.scan(JS_VARIABLE).to_h do |name, body|
          unless body.match?(ESCAPED_BYTES)
            raise Nabu::ParseError, "#{path}: SigLA variable #{name} is not a pure \\\\DDD byte literal"
          end

          [name, body.scan(/\d{3}/).map(&:to_i).pack("C*")]
        end
      end

      def attestations(document) = document[4].fields

      # -- the passage grain -------------------------------------------------

      # Words (upstream's word list, each in its own sign order) and the
      # standalone signs, ordered by their first attestation number.
      def groups(document, atts)
        words = document[2].fields.map do |word|
          members = OcamlMarshalParser.list_items(word[1])
          Group.new(kind: "word", attestations: members, word: word)
        end
        # The word lists hold their own copies of the attestations (not
        # shared pointers), so membership keys on upstream's number.
        in_word = words.flat_map(&:attestations).to_h { |att| [att[2], true] }
        singles = atts.reject { |att| in_word.key?(att[2]) }.map do |att|
          Group.new(kind: role_of(att), attestations: [att], word: nil)
        end
        (words + singles).sort_by { |group| group.attestations.map { |att| att[2] }.min }
      end

      def passage_for(doc_urn, group, index)
        signs = group.attestations.map { |att| sign_annotation(att) }
        text = if group.kind == "word"
                 signs.map { |sign| sign["reading"] }.join("-")
               else
                 signs.first["reading"]
               end
        annotations = { "kind" => group.kind, "signs" => signs }
        if group.word
          annotations["word_index"] = group.word[3]
          annotations["flags"] = { "word" => group.word[2].fields }
        end
        Nabu::Passage.new(
          urn: "#{doc_urn}:#{group.attestations.map { |att| att[2] }.min}",
          language: LANGUAGE, text: SourceRead.nfc(text, language: LANGUAGE),
          sequence: index + 1, annotations: annotations
        )
      end

      def role_of(att)
        role = att[3][0]
        return "syllabogram" if role.is_a?(OcamlMarshalParser::Block)

        ROLES.fetch(role) { raise Nabu::ParseError, "unknown SigLA role constructor #{role.inspect}" }
      end

      # One attestation → its annotation hash (lean: only present keys).
      def sign_annotation(att)
        role = role_of(att)
        out = { "n" => att[2], "role" => role }
        reading = att[1]
        if reading.is_a?(OcamlMarshalParser::Block)
          read_sign!(out, reading, role)
        else
          out["status"] = READING_STATUS.fetch(reading) { raise Nabu::ParseError, "unknown SigLA reading #{reading}" }
          out["reading"] = "?"
        end
        out["reading"] = "⟦#{out['reading']}⟧" if role == "erasure"
        out["bbox"] = att[7].fields
        flags = { "role" => att[3][1], "f4" => att[4], "f5" => att[5], "f6" => att[6] }.reject { |_, v| v.zero? }
        out["flags"] = flags unless flags.empty?
        out
      end

      def read_sign!(out, reading, role)
        record, variant = reading[0].fields
        variant = OcamlMarshalParser.option(variant)
        name = standard_name(record)
        value = phonetic_value(record)
        latin = OcamlMarshalParser.option(record[4])
        latin = nil if latin == "num" # the abstract-number sign's marker, not a name
        composition = OcamlMarshalParser.option(record[8])
        out["sign"] = name
        out["value"] = value if value
        out["latin"] = latin if latin
        out["variant"] = variant if variant
        out["composition"] = composition.strip if composition
        token = if role == "syllabogram" then value || name
                else "#{latin || name}#{variant}"
                end
        certain = reading[1] == 1
        out["certain"] = false unless certain
        out["reading"] = certain ? token : "#{token}?"
      end

      def standard_name(record) = format("%<series>s%<number>02d", series: record[0], number: record[1])

      def phonetic_value(record)
        pair = OcamlMarshalParser.option(record[2]) or return nil
        base, homophone = pair.fields
        homophone = OcamlMarshalParser.option(homophone)
        homophone ? base + homophone.to_s.tr("0-9", SUBSCRIPT) : base
      end

      # -- metadata ----------------------------------------------------------

      def metadata_for(document, atts)
        meta = document[0]
        site = clean(meta[2])
        object = clean(meta[0])
        {
          "sigla_id" => clean(meta[1]),
          "object" => object,
          "site" => site,
          "place" => site && { "ancient" => site },
          "period" => clean(OcamlMarshalParser.option(meta[7])),
          "dimensions_cm" => OcamlMarshalParser.option(meta[6])&.fields,
          "corpus_url" => corpus_url(meta[8]),
          "seal" => seal_for(meta[9]),
          "drawing_px" => document[3].fields,
          "permalink" => "#{BASE_URL}/#{document[1].split('/').map { |seg| URI.encode_uri_component(seg) }.join('/')}/",
          "sign_count" => atts.size,
          "word_count" => document[2].size,
          "facets" => { "object" => object, "site" => site }.compact.transform_values { |v| { "values" => [v] } }
        }.compact
      end

      def corpus_url(field)
        url = clean(OcamlMarshalParser.option(field))
        url == MISSING ? nil : url
      end

      def seal_for(field)
        seal = OcamlMarshalParser.option(field) or return nil
        impressions, cms, motif, url = seal.fields
        { "impressions" => impressions, "cms" => clean(OcamlMarshalParser.option(cms)),
          "motif" => clean(OcamlMarshalParser.option(motif)),
          "url" => clean(OcamlMarshalParser.option(url)) }.compact
      end

      def clean(value)
        return nil unless value.is_a?(String)

        text = value.gsub(/[[:space:]]+/, " ").strip
        text.empty? ? nil : SourceRead.nfc(text, language: LANGUAGE)
      end

      # Files beside database.js that are not the fetch's own (dot-files
      # — the FileFetch state, the attic — and a README are exempt).
      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .reject { |path| File.basename(path).start_with?(".") }
           .map { |path| path.delete_prefix("#{workdir}/") }
           .reject { |rel| [FILENAME, "README.md", "manifest.yml"].include?(rel) }
           .sort
      end
    end
  end
end
