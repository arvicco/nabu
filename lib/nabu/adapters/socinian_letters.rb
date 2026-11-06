# frozen_string_literal: true

require "csv"

require_relative "socinian_tei_parser"
require_relative "source_read"
require_relative "../zip_fetch"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # socinian-letters — Die sozinianischen Briefwechsel (the Socinian
    # correspondence; Akademie der Wissenschaften und der Literatur Mainz
    # with the Johannes a Lasco Bibliothek Emden, ed. Kęstutis Daugirdas and
    # Andreas Kuczera; DFG project 324518514; sozinianer.de): the letters of
    # the Socinians (the Polish Brethren — the antitrinitarian Ecclesia minor
    # of Raków) and their correspondents, 1545–1744 — Fausto and Lelio
    # Sozzini, Valentin Schmalz, Martin Ruarus, and above all Stanisław
    # Lubieniecki's comet correspondence of the 1660s (Hevelius, Heinsius,
    # Oldenburg, the Theatrum cometicum). The data dump lives in the public
    # GitLab project adwmainz/digicademy/sbw/csv-data-dump.
    #
    # == Shape (censused 2026-11-05 over the main branch at commit 5d91807, the
    # folder zip's own comment)
    #
    # data/xml/letters/: 2,217 teiCorpus files LETTER_<id>.xml, one per
    # letter — the cover letter (TEI n=cover_letter) with its witnesses (the
    # edition's reference_witness + 0–3 further prints/manuscripts) and 0–7
    # attachments (TEI n=attachment, each with its own witnesses): 2,217
    # cover letters, 470 attachment occurrences (439 distinct), 2,687
    # reference witnesses, 644 further witnesses (SocinianTeiParser's class
    # note has the layout and the text rendering).
    #
    # Delivery grains: the letters folder zip (TAKEN — the one text
    # artifact); its letter files (document = file, keyed by the cover
    # TEI's xml:id); the text blocks of the chosen witness (passage = block);
    # data/csv/indices.csv (TAKEN as a lookup register, FileFetch — persons'
    # GND and life dates, places' GeoNames; never text); data/xml/texts/
    # (2,689 single-TEI files — the same components unbundled: REJECTED, never
    # fetched, every one rides inside a letters/ file); data/cmif/ (the CMIF
    # export of the same correspDesc — REJECTED, the register join carries the
    # same refs); data/json/, csv letters/relations/corresp tables, beacon/
    # (derived views of the same TEI — REJECTED, never fetched).
    #
    # Reconciliation (through the adapter over the whole zip, 2026-11-05):
    # upstream's own count is the folder's 2,217 files (the tree listing's
    # X-Total) — 1,870 accepted + 347 skipped by rule (metadata-only: no
    # witness of the cover or of any attachment it holds carries transcribed
    # text — revisionDesc "Metadaten publikationsbereit" without a
    # transcription) = 2,217. The two state pins (.zip-fetch.json,
    # data/csv/.file-fetch.json) and the register skip by rule too.
    #
    # == The witness rule (deliberate, recorded per document)
    #
    # A component's text is its reference_witness (upstream's own designation
    # of the edition's base text) — unless that witness carries no
    # transcription while another does (3 cover letters: the base print
    # recorded, its text transcribed from a second print), then the first
    # transcribed witness in document order. metadata "witness" names the id,
    # "witness_basis" the rule that chose it. Further witnesses are never
    # passages (they repeat the letter).
    #
    # == The document grain: the cover letter plus the attachments it HOLDS
    #
    # Attachments repeat across files (a letter forwarded as another's
    # enclosure; one enclosure sent twice). Deduped by TEI id at discover
    # time over the whole tree (DocumentRef metadata "held_elsewhere"):
    # an attachment whose id is itself a cover letter (56) is held by its OWN
    # letter file when that file carries it transcribed; otherwise by the
    # first file (sorted by name) carrying it transcribed; every other
    # carrier lists it in "attachments" with "held_in" = the holder's urn.
    #
    # == License (read 2026-11-05 in the files themselves)
    #
    # Per TEI: every header carries availability/licence. Over the 2,217
    # files: CC BY 4.0 on the corpus and component headers and on 2,594
    # reference witnesses; CC BY-SA 3.0 ("This file is licensed under the
    # terms of the Creative-Commons-License CC BY-SA 3.0") on 93 reference
    # witnesses and 186 further witnesses — transcriptions taken over from
    # earlier digital editions. Both → attribution. The CHOSEN witness's own
    # licence is the document's (metadata "license" / "license_url"); a
    # witness under any other licence quarantines.
    #
    # == Axes
    #
    # Dates: the cover's correspAction[sent]/date (@when; @from/@to;
    # @notBefore/@notAfter — 2,180 of 2,217) → the year envelope, class
    # composition (the writing date, the emmo stance); else the received
    # date as a terminus ante quem (not_after only). Places: the sent
    # placeName (2,054) joined through indices.csv by its key → the
    # register's label + its GeoNames URL (1,940 linked); the received place
    # rides place_received(_ref). Persons: correspDesc persNames → the
    # register's label, GND, life dates ("correspondents"; author =
    # sender, recipient). Kind: the reference witness's #sbw classCode
    # (Brief, Brief/Briefexzerpt, …) → document_type, folded in
    # config/kind_map.yml. Lect: the witness langUsage ident (lat, fra, deu,
    # pol, ita; upstream's "Niederländisch" → nld) per component; a block
    # wholly inside one <foreign xml:lang> takes that language.
    #
    # == Fetch
    #
    # Two arms, both prepared before either tree mutates (the openiti
    # shape): ZipFetch of the GitLab folder archive (the single top dir
    # csv-data-dump-main-data-xml-letters/ strips, so the tree lands as
    # upstream's data/xml/letters/), keeping data/csv/ out of its sweep; and
    # FileFetch of the raw indices.csv into data/csv/. Both land upstream's
    # own paths in a plain (non-git) tree that hashes whole, so nothing needs
    # a materialized_paths declaration. GitLab serves no Last-Modified on
    # either URL: each sync re-downloads (13 MB + 1 MB) and the sha pins
    # detect change.
    class SocinianLetters < Nabu::Adapter
      SLUG = "socinian-letters"
      URN_PREFIX = "urn:nabu:socinian-letters:"
      PROJECT_URL = "https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump"
      ZIP_URL = "#{PROJECT_URL}/-/archive/main/csv-data-dump-main.zip?path=data/xml/letters".freeze
      INDICES_URL = "#{PROJECT_URL}/-/raw/main/data/csv/indices.csv".freeze
      SITE_ID_URL = "https://sozinianer.de/id/"
      LETTERS_DIR = File.join("data", "xml", "letters")
      CSV_DIR = File.join("data", "csv")
      INDICES_FILE = "indices.csv"
      LETTER_FILE = /\ALETTER_.+\.xml\z/

      DEFAULT_LANGUAGE = "lat"
      # Upstream's langUsage idents are ISO 639-2/3 codes except one German
      # language NAME (18 witnesses) — transcribed onto its code.
      LANGUAGE_NAMES = { "Niederländisch" => "nld" }.freeze

      LICENCES = {
        "https://creativecommons.org/licenses/by/4.0/" => "CC BY 4.0",
        "https://creativecommons.org/licenses/by-sa/3.0/" => "CC BY-SA 3.0"
      }.freeze

      REFERENCE = "reference_witness"
      FALLBACK_BASIS = "first transcribed witness (reference witness untranscribed)"
      ANONYMOUS = %w[NN N.N. N. N.].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Die sozinianischen Briefwechsel — the Socinian correspondence (AdW Mainz)",
        license: "Per-TEI Creative Commons licence, each witness header's own availability/licence: " \
                 "CC BY 4.0 (\"Creative Commons Attribution 4.0 International (CC-BY 4.0)\" — the corpus and " \
                 "component headers and 2,594 reference witnesses) and CC BY-SA 3.0 (\"This file is licensed " \
                 "under the terms of the Creative-Commons-License CC BY-SA 3.0\" — 93 reference witnesses); " \
                 "the chosen witness's licence rides each document (read 2026-11-05).",
        license_class: "attribution",
        upstream_url: PROJECT_URL,
        parser_family: "socinian-tei",
        credit: "Zwischen Theologie, frühmoderner Naturwissenschaft und politischer Korrespondenz: Die " \
                "sozinianischen Briefwechsel, hg. von Kęstutis Daugirdas und Andreas Kuczera (Akademie der " \
                "Wissenschaften und der Literatur Mainz / Johannes a Lasco Bibliothek Emden), sozinianer.de."
      )

      # One letter file's discover-time census: its cover id and its
      # attachments' [id, transcribed?] pairs; +error+ when it would not parse
      # (the ref is still yielded so parse quarantines it honestly).
      Entry = Data.define(:path, :name, :cover_id, :cover_transcribed, :attachments, :error)
      # The tree's plan: accepted entries with their held-elsewhere maps, the
      # metadata-only file names, the duplicate-cover file names.
      Plan = Data.define(:accepted, :metadata_only, :duplicates)

      def self.manifest = MANIFEST

      # Parallel replay (audited): #parse reads one file plus the memoized
      # register (a pure function of its bytes); the cross-file attachment
      # plan rides each ref's metadata from discover.
      def self.parallel_parse? = true

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(label: "letters folder zip", zip_url: ZIP_URL, metadata_url: nil,
                                            state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE),
         Nabu::Adapter::HttpProbeTarget.new(label: INDICES_FILE, zip_url: INDICES_URL, metadata_url: nil,
                                            state_subdir: CSV_DIR, state_file: Nabu::FileFetch::STATE_FILE)]
      end

      # An upstream langUsage ident → the house language code, nil for blank.
      def self.language_code(ident)
        value = ident.to_s.strip
        return nil if value.empty?

        LANGUAGE_NAMES.fetch(value, value)
      end

      # The witness rule (class note): [witness, basis] or [nil, nil].
      def self.choose_witness(component)
        witnesses = component.witnesses
        reference = witnesses.find { |w| w.designation == REFERENCE }
        return [reference, REFERENCE] if reference&.transcribed?

        fallback = witnesses.find { |w| !w.equal?(reference) && w.transcribed? }
        return [fallback, FALLBACK_BASIS] if fallback

        reference ? [reference, REFERENCE] : [witnesses.first, witnesses.first && "first witness"]
      end

      def self.transcribed?(component) = choose_witness(component).first&.transcribed? || false

      # [cover, *attachments] in document order; an attachment repeated
      # inside ONE file (2 files carry a duplicate enclosure TEI) is held once,
      # by its first occurrence.
      def self.ordered_components(result)
        cover = result.components.find { |c| c.role == "cover_letter" } || result.components.first
        [cover, *result.components.select { |c| c.role == "attachment" && !c.equal?(cover) }.uniq(&:id)]
      end

      def initialize
        super
        @plans = {}
        @registers = {}
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        plan(workdir).accepted.each do |entry, held_elsewhere|
          yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{entry.cover_id}", path: entry.path,
                                      metadata: { "held_elsewhere" => held_elsewhere })
        end
      end

      def discovery_skips(workdir)
        return Nabu::Adapter::DiscoverySkips.new unless Dir.exist?(workdir)

        current = plan(workdir)
        notes = current.metadata_only.map do |name|
          "#{name}: metadata only — neither the cover letter nor any attachment it holds has a transcribed witness"
        end
        unrecognized = current.duplicates.map { |name| "#{name}: repeats another file's cover-letter id" }
        stray_files(workdir).each do |rel|
          if (note = rule_note(rel))
            notes << note
          else
            unrecognized << "#{rel}: unrecognized member of the socinian-letters tree"
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: unrecognized.size,
                                          notes: notes + unrecognized)
      end

      def parse(document_ref)
        result = SocinianTeiParser.new.parse(document_ref.path)
        LetterBuilder.new(adapter: self.class, ref: document_ref, result: result,
                          register: register_for(document_ref.path)).document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        @plans.clear
        zip = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
                                 progress: progress, keep: [CSV_DIR])
        csv = Nabu::FileFetch.new(url: INDICES_URL, dir: File.join(workdir, CSV_DIR), filename: INDICES_FILE,
                                  attic_dir: File.join(workdir, ATTIC_DIRNAME, CSV_DIR), progress: progress)
        begin
          zip.prepare!
          csv.prepare!
          guard_mass_deletion!(workdir, zip.doomed_paths + csv.doomed_paths, force: force)
          zip.complete!
          csv.complete!
        ensure
          zip.cleanup!
        end
        Nabu::FetchReport.new(sha: zip.sha, fetched_at: Time.now, notes: fetch_notes(zip, csv))
      rescue Nabu::ZipFetch::Error, Nabu::FileFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def fetch_notes(zip, csv)
        [zip.not_modified? ? "letters zip not modified (304)" : "letters folder zip unpacked (sha256 #{zip.sha})",
         csv.not_modified? ? "indices.csv not modified (304)" : "indices.csv landed (sha256 #{csv.sha})",
         attic_notes(zip.atticked + csv.atticked)].compact.join("; ")
      end

      # -- the discover-time plan ----------------------------------------------

      def plan(workdir)
        @plans[File.expand_path(workdir)] ||= build_plan(letter_paths(workdir).map { |path| census(path) })
      end

      def letter_paths(workdir)
        dir = File.join(workdir, LETTERS_DIR)
        return [] unless Dir.exist?(dir)

        Dir.children(dir).grep(LETTER_FILE).sort.map { |name| File.expand_path(File.join(dir, name)) }
      end

      def census(path)
        name = File.basename(path)
        result = SocinianTeiParser.new.parse(path)
        cover, *attachments = self.class.ordered_components(result)
        Entry.new(path: path, name: name, cover_id: cover.id, cover_transcribed: self.class.transcribed?(cover),
                  attachments: attachments.map { |a| [a.id, self.class.transcribed?(a)] }, error: nil)
      rescue Nabu::ParseError => e
        Entry.new(path: path, name: name, cover_id: name.delete_prefix("LETTER_").delete_suffix(".xml"),
                  cover_transcribed: true, attachments: [], error: e.message)
      end

      def build_plan(entries)
        unique, duplicates = dedupe_covers(entries)
        owners = attachment_owners(unique)
        accepted = []
        metadata_only = []
        unique.each do |entry|
          held_elsewhere = entry.attachments.filter_map do |id, _|
            owner = owners.fetch(id)
            [id, "#{URN_PREFIX}#{owner}"] unless owner == entry.cover_id
          end.to_h
          if entry.cover_transcribed || entry.attachments.any? { |id, done| done && !held_elsewhere.key?(id) }
            accepted << [entry, held_elsewhere]
          else
            metadata_only << entry.name
          end
        end
        Plan.new(accepted: accepted.sort_by { |entry, _| entry.cover_id }, metadata_only: metadata_only,
                 duplicates: duplicates)
      end

      def dedupe_covers(entries)
        seen = {}
        duplicates = []
        entries.each do |entry|
          if seen.key?(entry.cover_id)
            duplicates << entry.name
          else
            seen[entry.cover_id] = entry
          end
        end
        [seen.values, duplicates]
      end

      # attachment id → the cover id of the file that holds it (class note).
      def attachment_owners(entries)
        covers = entries.to_h { |entry| [entry.cover_id, entry] }
        carriers = Hash.new { |hash, key| hash[key] = [] }
        entries.each { |entry| entry.attachments.each { |id, done| carriers[id] << [entry, done] } }
        carriers.to_h do |id, list|
          own = covers[id]
          owner = if own&.cover_transcribed then own
                  elsif (hit = list.find { |_entry, done| done }) then hit.first
                  else own || list.first.first
                  end
          [id, owner.cover_id]
        end
      end

      # -- discovery accounting for the non-letter files -------------------------

      def stray_files(workdir)
        root = File.expand_path(workdir)
        Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).filter_map do |path|
          next unless File.file?(path)

          rel = path.delete_prefix("#{root}/")
          next if rel.start_with?("#{ATTIC_DIRNAME}/")
          next if File.dirname(rel) == LETTERS_DIR && File.basename(rel).match?(LETTER_FILE)

          rel
        end.sort
      end

      def rule_note(rel)
        case rel
        when Nabu::ZipFetch::STATE_FILE then "#{rel}: the zip fetcher's own state pin — not upstream content"
        when File.join(CSV_DIR, Nabu::FileFetch::STATE_FILE)
          "#{rel}: the register fetcher's own state pin — not upstream content"
        when File.join(CSV_DIR, INDICES_FILE)
          "#{rel}: the edition's persons/places/terms register — read as lookups (GND, GeoNames, life dates), not text"
        end
      end

      # -- the register --------------------------------------------------------

      # data/csv/indices.csv beside the letter's own tree (the attic's copy for
      # an attic ref — absent there means names without refs, never a guess).
      def register_for(path)
        csv = File.expand_path(File.join(File.dirname(path), "..", "..", "csv", INDICES_FILE))
        @registers[csv] ||= IndicesRegister.load(csv)
      end

      # indices.csv: entry rows (Personenregister / Ortsregister / …) keyed by
      # sbw_id, with their n:1 altName and normdata (URL) rows.
      class IndicesRegister
        Entry = Data.define(:label, :index, :birth, :death, :urls) do
          def gnd = urls.find { |url| url.include?("d-nb.info/gnd/") }
          def geonames = urls.find { |url| url.include?("geonames.org/") }
        end

        def self.load(path)
          return new({}) unless File.file?(path)

          rows = CSV.parse(SourceRead.utf8_file(path, label: "socinian-letters register"), headers: false)
          rows.shift
          new(index(rows))
        rescue CSV::MalformedCSVError => e
          raise Nabu::ParseError, "#{path}: malformed register CSV: #{e.message}"
        end

        def self.index(rows)
          entries = {}
          urls = Hash.new { |hash, key| hash[key] = [] }
          rows.each do |row|
            key, index = row.first(2)
            next if key.nil?

            case index
            when "normdata" then urls[key] << row.last.to_s.strip unless row.last.to_s.strip.empty?
            when "altName" then nil
            else entries[key] = [row[2], index, row[6], row[7]]
            end
          end
          entries.to_h do |key, (label, index, birth, death)|
            [key, Entry.new(label: blank(label), index: index, birth: blank(birth), death: blank(death),
                            urls: urls[key])]
          end
        end

        def self.blank(value) = value.to_s.strip.empty? ? nil : Normalize.nfc(value.strip)

        def initialize(entries)
          @entries = entries
        end

        def [](key) = key && @entries[key]
      end

      # One parsed letter file → its Nabu::Document (the class note's rules).
      class LetterBuilder
        def initialize(adapter:, ref:, result:, register:)
          @adapter = adapter
          @ref = ref
          @result = result
          @register = register
          @held_elsewhere = ref.metadata.fetch("held_elsewhere", {})
        end

        def document
          cover, *attachments = @adapter.ordered_components(@result)
          held = [cover, *attachments.reject { |a| @held_elsewhere.key?(a.id) }]
          chosen = held.to_h { |component| [component, @adapter.choose_witness(component)] }
          contributing = held.select { |component| chosen[component].first&.transcribed? }
          if contributing.empty?
            raise Nabu::DocumentSkipped.new("#{@ref.path}: no held component carries a transcribed witness",
                                            reason: "metadata-only")
          end

          contributing.each { |component| verify_licence!(component, chosen[component].first) }
          languages = held.to_h { |component| [component, component_language(chosen[component].first)] }
          doc_language = languages[cover] || contributing.filter_map { |c| languages[c] }.first || DEFAULT_LANGUAGE
          document = Nabu::Document.new(
            urn: @ref.id, language: doc_language, canonical_path: @ref.path,
            title: nfc(cover.title || @result.title),
            metadata: metadata(cover, attachments, chosen, contributing, languages, doc_language)
          )
          add_passages(document, contributing, chosen, languages, doc_language)
          document
        end

        private

        def verify_licence!(component, witness)
          return if LICENCES.key?(witness.licence_target)

          raise Nabu::ParseError, "#{@ref.path}: #{component.id} witness #{witness.id} licence " \
                                  "#{witness.licence_target.inspect} is none of #{LICENCES.keys.join(', ')}"
        end

        def component_language(witness)
          witness&.languages&.filter_map { |ident| @adapter.language_code(ident) }&.first
        end

        # -- passages ----------------------------------------------------------

        def add_passages(document, contributing, chosen, languages, doc_language)
          sequence = 0
          contributing.each do |component|
            cover = component.role != "attachment"
            base = languages[component] || doc_language
            chosen[component].first.blocks.each_with_index do |block, index|
              sequence += 1
              citation = cover ? (index + 1).to_s : "#{component.id}.#{index + 1}"
              document << Nabu::Passage.new(
                urn: "#{document.urn}:#{citation}", sequence: sequence, text: nfc(block.text),
                language: @adapter.language_code(block.language) || base,
                annotations: annotations(block, component, cover)
              )
            end
          end
        end

        def annotations(block, component, cover)
          deep_nfc({
            "component" => cover ? "cover_letter" : "attachment",
            "component_id" => (component.id unless cover), "block" => block.tag, "page" => block.page,
            "page_breaks" => presence(block.page_breaks), "persons" => presence(block.persons),
            "places" => presence(block.places), "notes" => presence(block.notes),
            "foreign" => presence(block.foreign)
          }.compact)
        end

        # -- metadata ----------------------------------------------------------

        def metadata(cover, attachments, chosen, contributing, languages, doc_language)
          witness, basis = chosen[cover]
          sent = action(cover, "sent")
          received = action(cover, "received")
          sent_place = place(sent)
          received_place = place(received)
          senders = correspondents(sent, "sent")
          recipients = correspondents(received, "received")
          deep_nfc({
            "sbw_id" => cover.id, "url" => "#{SITE_ID_URL}#{cover.id}",
            "date" => date(sent, received),
            "place" => sent_place&.dig(0), "place_ref" => sent_place&.dig(1),
            "place_raw" => sent_place&.dig(2), "place_role" => sent_place && "sent",
            "place_received" => received_place&.dig(0), "place_received_ref" => received_place&.dig(1),
            "author" => names(senders), "author_ref" => refs(senders),
            "recipient" => names(recipients), "recipient_ref" => refs(recipients),
            "correspondents" => presence(senders + recipients),
            "document_type" => witness&.class_code, "dwds_class" => witness&.dwds_class,
            "witness" => witness&.id, "witness_basis" => basis, "witness_medium" => witness&.medium,
            "witness_source" => witness&.source, "witnesses" => cover.witnesses.size,
            "editorial_status" => presence(witness&.revisions&.uniq || []),
            "languages" => contributing.filter_map { |c| languages[c] || doc_language }.uniq,
            "license" => contributing.map { |c| LICENCES.fetch(chosen[c].first.licence_target) }.uniq,
            "license_url" => contributing.map { |c| chosen[c].first.licence_target }.uniq,
            "attachments" => presence(attachments.map { |a| attachment_row(a, chosen) })
          }.compact)
        end

        def attachment_row(component, chosen)
          witness = (chosen[component] || @adapter.choose_witness(component)).first
          {
            "id" => component.id, "title" => component.title, "type" => witness&.class_code,
            "transcribed" => witness&.transcribed? || false,
            "held_in" => @held_elsewhere.fetch(component.id, "here")
          }.compact
        end

        def action(component, type) = component.actions.find { |a| a.type == type }

        # [label, geonames url, header spelling when it differs] for the
        # action's first place, nil when it names none.
        def place(action)
          spot = action&.places&.first or return nil
          entry = @register[spot["key"]]
          label = entry&.label || spot["name"]
          [label, entry&.geonames, (spot["name"] unless spot["name"] == label)]
        end

        def correspondents(action, role)
          (action&.persons || []).map do |person|
            entry = @register[person["key"]]
            { "role" => role, "name" => entry&.label || person["name"], "key" => person["key"],
              "cert" => person["cert"], "gnd" => entry&.gnd, "birth" => entry&.birth,
              "death" => entry&.death }.compact
          end
        end

        def named(list) = list.reject { |c| ANONYMOUS.include?(c["name"]) }

        def names(list)
          joined = named(list).map { |c| c["name"] }.uniq.join("; ")
          joined.empty? ? nil : joined
        end

        def refs(list)
          joined = named(list).filter_map { |c| c["gnd"] }.uniq.join(" ")
          joined.empty? ? nil : joined
        end

        # The sent date's year envelope (class composition); else the
        # received date as a terminus ante quem.
        def date(sent, received)
          if (stated = sent&.date) && (bounds = envelope(stated)).any?
            return { "not_before" => bounds[0], "not_after" => bounds[1], "raw" => raw(stated),
                     "class" => "composition", "cert" => stated["cert"] }.compact
          end
          stated = received&.date or return nil
          bounds = envelope(stated)
          upper = bounds[1] || bounds[0] or return nil
          { "not_after" => upper, "raw" => "received #{raw(stated)}", "basis" => "received",
            "class" => "composition" }
        end

        def envelope(date)
          low = year(date["when"] || date["from"] || date["notBefore"])
          high = year(date["when"] || date["to"] || date["notAfter"])
          [low, high].compact.empty? ? [] : [low, high]
        end

        def year(value)
          match = value.to_s.match(/\A(-?\d{4})/) or return nil
          Integer(match[1], 10)
        end

        def raw(date)
          date["when"] || [date["from"] || date["notBefore"], date["to"] || date["notAfter"]].join("/")
        end

        def presence(list) = list.nil? || list.empty? ? nil : list

        def nfc(value) = value && Normalize.nfc(value)

        def deep_nfc(value)
          case value
          when String then Normalize.nfc(value)
          when Hash then value.transform_values { |v| deep_nfc(v) }
          when Array then value.map { |v| deep_nfc(v) }
          else value
          end
        end
      end
    end
  end
end
