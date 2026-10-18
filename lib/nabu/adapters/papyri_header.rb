# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Header mining for the Papyri adapter (the aggressive-mining law):
    # what idp.data asserts ABOUT each document beyond its text, read at
    # parse into document metadata. Two record shapes, both small files
    # read by DOM (namespaces stripped):
    #
    # == The DCLP header (the literary file's own teiHeader)
    #
    # - "date" — the origDate envelope (min of every lower candidate, max
    #   of every upper; a `when` point feeds both — the HGV timeline's
    #   policy), signed years via Nabu::Timeline, raw = the first
    #   origDate's display text. "unbekannt" or a year-0 tripwire mints no
    #   date (absence, never a guess). MetadataDates projects it (shape
    #   :structured) onto the timeline like the sibling HGV rows.
    # - "place" — {"ancient" => origPlace verbatim ("Found: Oxyrhynchos
    #   (Oxyrhynchites, Egypt); written: Egypt" — the HGV lane's verbatim
    #   origPlace stance), "ref" => the Trismegistos/Pleiades URLs of the
    #   FINDSPOT provenance's settlement and nome placeNames, settlement
    #   first} — the `found` provenance (9,140 at the 2026-10-18 census)
    #   is the artifact's place; the `composed` one (where it was written)
    #   is usually coarser ("Egypt") and is read only when no findspot is
    #   given. The region tier never claims.
    # - "keywords" — every textClass term verbatim, deduped in upstream
    #   order (literature/classical/prose/christian/poetry…; typed
    #   culture/religion/overview/description terms alike). Deliberate
    #   coarseness: they ride metadata only — the kind lane's one-rule-
    #   per-source contract already spends papyri-ddbdp's rule on the HGV
    #   walk, so a DCLP kind fold is its own future rule.
    #
    # == The HGV record beside a DDbDP text (HGV_meta_EpiDoc/)
    #
    # Joined by the edition's own HGV idno(s) (multi-text editions list
    # several, space-separated) at HGV_meta_EpiDoc/HGV<n/1000+1>/<id>.xml.
    # The origin date, place and leading keyword term are the timeline
    # and kind lanes' (a canonical walk at build) and are NOT repeated
    # here; parse adds what no lane read:
    # - "persons" — sender→addressee parties from the LATER keyword terms
    #   ("Apollonios an Zenon": 9,003 "X an Y" later terms in 8,732
    #   records at the census; the leading term is the text type). Each
    #   party: {"name" verbatim, "role" sender|addressee, "term" — the
    #   upstream phrase it came from}. HGV's unnamed-party placeholder
    #   ("NN", "N.N.") is no person; a document-act noun on the left
    #   ("Eingabe an den Strategen", "Lieferung (Öl) an …" — 271 later
    #   terms) names the act, not a sender, so only its addressee rides.
    # - "archive" — each "Gehört zum … Archiv/Dossier" commentary phrase
    #   (4,853 records; "Zenon - Archiv", "Archiv des Strategen
    #   Apollonios", "Dossier des Einnehmers Georgios"), verbatim up to the
    #   sentence end. "Gehört zu P.Strasb. IX 883 a" (a join, not an
    #   archive) never matches.
    # - "mentioned_dates" — every <date type="mentioned"> (11,141 in 5,088
    #   records): {"ref" (the line, "Z. 5"), "when" (verbatim ISO, when
    #   given), "not_before"/"not_after" signed years, "raw"}. A date the
    #   text MENTIONS is never the document's date: it stays out of the
    #   timeline (whose primary-row ranking would let an earlier mentioned
    #   date masquerade as the origin) and rides as its own labeled class.
    module PapyriHeader
      # Provenance placeName tiers that claim: the settlement (no
      # subtype) and its nome — the same tiers the HGV timeline lane takes.
      SETTLEMENT = nil
      NOME = "nome"

      UNNAMED = /\AN\.?\s?N\.?(?:\s*\(\?\))?\z/

      # Left-hand sides of "X an Y" later terms that name a document act
      # or commodity, not a sender (the 2026-10-18 census of later terms
      # whose left side opens with HGV's own text-type vocabulary).
      ACT_NOUNS = %w[
        Anordnung Anweisung Antrag Arbeit Auftrag Aufforderung Befehl Bitte Brief
        Eingabe Enteuxis Erklärung Frage Geld Getreide Hypomnema Kopie Lieferung
        Petition Schenkung Schreiben Wein Zahlung Zahlungen Zuteilung
      ].freeze

      ARCHIVE = /Gehört zu[mr]?\s+((?:(?!\.\s|;).)*?(?:Archiv|Dossier)(?:(?!\.\s|;).)*)/

      HGV_DIR = "HGV_meta_EpiDoc"

      module_function

      # -- DCLP ------------------------------------------------------------

      def dclp(path)
        doc = load(path)
        metadata = {}
        date = envelope(doc.xpath("//origin/origDate"))
        metadata["date"] = date if date
        place = dclp_place(doc)
        metadata["place"] = place if place
        keywords = doc.xpath("//textClass/keywords/term").filter_map { |term| text(term) }.uniq
        metadata["keywords"] = keywords unless keywords.empty?
        metadata
      end

      def dclp_place(doc)
        name = text(doc.at_xpath("//origin/origPlace"))
        provenance = doc.at_xpath("//provenance[@type='found']") || doc.at_xpath("//provenance")
        ref = provenance && tier_refs(provenance)
        return nil if name.nil? && ref.nil?

        { "ancient" => name, "ref" => ref }.compact
      end

      # Settlement refs, then nome refs, URL tokens deduped; nil if none.
      def tier_refs(provenance)
        places = provenance.xpath(".//placeName[@ref]")
        ordered = places.select { |p| p["subtype"] == SETTLEMENT } + places.select { |p| p["subtype"] == NOME }
        tokens = ordered.flat_map { |p| p["ref"].to_s.split(/\s+/) }.reject(&:empty?).uniq
        tokens.empty? ? nil : tokens.join(" ")
      end

      # {"not_before","not_after","raw"} across the origDate nodes, or nil.
      def envelope(dates)
        lowers = []
        uppers = []
        raw = nil
        dates.each do |node|
          point = Timeline.parse_year(node["when"])
          lower = Timeline.parse_year(node["notBefore"])
          upper = Timeline.parse_year(node["notAfter"])
          next if point.nil? && lower.nil? && upper.nil?

          lowers.push(*[point, lower].compact)
          uppers.push(*[point, upper].compact)
          raw ||= text(node)
        end
        return nil if lowers.empty? && uppers.empty?

        { "not_before" => lowers.min, "not_after" => uppers.max, "raw" => raw }
      rescue Timeline::InvalidYear
        nil
      end

      # -- HGV ---------------------------------------------------------------

      # The HGV records of +hgv_ids+ (the edition's HGV idno, possibly
      # several space-separated) under +workdir+; absent files skip.
      def hgv_paths(workdir, hgv_ids)
        hgv_ids.to_s.split(/\s+/).filter_map do |id|
          number = id[/\A\d+/] or next
          path = File.join(workdir, HGV_DIR, "HGV#{(Integer(number, 10) / 1000) + 1}", "#{id}.xml")
          path if File.file?(path)
        end
      end

      def hgv(paths)
        persons = []
        archives = []
        mentioned = []
        paths.each do |path|
          doc = load(path)
          persons.concat(keyword_persons(doc.xpath("//keywords[@scheme='hgv']/term").filter_map { |t| text(t) }))
          archives.concat(archive_names(doc))
          mentioned.concat(mentioned_dates(doc))
        end
        { "persons" => persons.uniq, "archive" => archives.uniq, "mentioned_dates" => mentioned.uniq }
          .reject { |_, value| value.empty? }
      end

      # Sender/addressee parties from the terms AFTER the leading one.
      def keyword_persons(terms)
        terms.drop(1).flat_map do |term|
          match = term.match(/\A(.+?) an (.+)\z/) or next []

          sender = match[1].strip
          addressee = match[2].strip
          parties = []
          parties << party(sender, "sender", term) unless unnamed?(sender) || act?(sender)
          parties << party(addressee, "addressee", term) unless unnamed?(addressee)
          parties
        end.uniq
      end

      def party(name, role, term) = { "name" => name, "role" => role, "term" => term }

      def unnamed?(side) = side.match?(UNNAMED)

      def act?(side) = ACT_NOUNS.include?(side[/\A[^\s(]+/])

      def archive_names(doc)
        prose = doc.xpath("//div[@type='commentary']").map(&:text).join(" ").gsub(/\s+/, " ")
        prose.scan(ARCHIVE).map { |(name)| Nabu::Normalize.nfc(name.strip.sub(/\.\z/, "")) }.uniq
      end

      def mentioned_dates(doc)
        doc.xpath("//date[@type='mentioned']").filter_map do |node|
          mentioned_date(node)
        rescue Timeline::InvalidYear
          nil
        end
      end

      def mentioned_date(node)
        point = Timeline.parse_year(node["when"])
        lower = Timeline.parse_year(node["notBefore"]) || point
        upper = Timeline.parse_year(node["notAfter"]) || point
        return nil if lower.nil? && upper.nil?

        { "ref" => text(node.parent&.at_xpath("ref")), "when" => node["when"],
          "not_before" => lower, "not_after" => upper, "raw" => text(node) }.compact
      end

      # -- shared --------------------------------------------------------------

      def load(path)
        doc = Nokogiri::XML(File.read(path))
        doc.remove_namespaces!
        doc
      end

      # NFC, whitespace-collapsed text of +node+, or nil when blank.
      def text(node)
        return nil if node.nil?

        folded = node.text.to_s.strip.gsub(/\s+/, " ")
        folded.empty? ? nil : Nabu::Normalize.nfc(folded)
      end
    end
  end
end
