# frozen_string_literal: true

require "json"
require "digest"
require "uri"
require "fileutils"

module Nabu
  module Adapters
    # DPRR — the Digital Prosopography of the Roman Republic (King's
    # College London, AHRC-funded; Mouritsen, Robb, Bradley et al.),
    # registered as a person-authority MODULE (the cbdb shape — zero
    # document rows): the attested members of the Republican elite, from
    # Broughton's Magistrates of the Roman Republic, Rüpke's Fasti
    # Sacerdotum and Zmeskal's Adfinitas, with names, filiation, sex,
    # life-era windows, dated life events, offices and kinship.
    #
    # == The channel (read 2026-10-27)
    #
    # DPRR publishes its data as Linked Open Data: an rdf4j triple store
    # behind a public SPARQL endpoint (romanrepublic.ac.uk/rdf/endpoint/).
    # There is no bulk file. Fetch sends two SELECTs — one row per
    # :Person (4,876 at the read; ids run 1–5,684 with gaps) and every
    # person-attached :DateInformation (1,917) — asking for
    # application/sparql-results+json, and lands both answers byte-verbatim
    # (stdlib JSON reads them; no RDF library needed). The answers are
    # ORDERed, so an unchanged store answers identical bytes and the
    # combined sha pins the state. Offices (PostAssertion), status
    # (StatusAssertion) and kinship (RelationshipAssertion) are NOT
    # fetched: the person index has no office or kinship lane — declared
    # scope, queryable at the endpoint the day a ruling wants them.
    #
    # == License (verified on the live site 2026-10-27)
    #
    # The RDF documentation footer: "Copyright 2017 John Bradley, King's
    # College London … This work is licensed under a Creative Commons
    # Attribution-NonCommercial 4.0 International License", and every RDF
    # serialization the server emits opens "This data is Copyright 2017
    # King's College London (All rights reserved), and is made available
    # under the Creative Commons License 'Attribution-NonCommercial 4.0
    # International (CC BY-NC 4.0)'". The website chrome's "© King's
    # College London. All rights reserved." covers the pages, not the data
    # channel. Class nc; held verbatim for local research, nothing exported.
    class Dprr < Nabu::Adapter
      ENDPOINT = "https://romanrepublic.ac.uk/rdf/endpoint/"
      DOC_URL = "https://romanrepublic.ac.uk/rdf/doc/"
      ACCEPT = "application/sparql-results+json"

      PERSONS_FILE = "persons.json"
      DATES_FILE = "dates.json"
      STATE_FILE = ".dprr-fetch.json"

      PREFIX = "PREFIX : <http://romanrepublic.ac.uk/rdf/ontology#> "

      PERSONS_QUERY = "#{PREFIX}SELECT ?person ?id ?dprrId ?name ?praenomen ?praenomenAbbr ?nomen " \
                      "?cognomen ?otherNames ?filiation ?sex ?eraFrom ?eraTo ?highestOffice WHERE { " \
                      "?person a :Person ; :hasID ?id ; :hasDprrID ?dprrId ; :hasName ?name ; " \
                      ":hasNomen ?nomen ; :isSex ?sex ; :hasEraFrom ?eraFrom ; :hasEraTo ?eraTo . " \
                      "OPTIONAL { ?person :hasPraenomen ?pr . ?pr :hasName ?praenomen ; " \
                      ":Abbreviation ?praenomenAbbr } " \
                      "OPTIONAL { ?person :hasCognomen ?cognomen } " \
                      "OPTIONAL { ?person :hasOtherNames ?otherNames } " \
                      "OPTIONAL { ?person :hasFiliation ?filiation } " \
                      "OPTIONAL { ?person :hasHighestOffice ?highestOffice } } ORDER BY ?id".freeze

      DATES_QUERY = "#{PREFIX}SELECT ?date ?person ?type ?value ?interval ?uncertain WHERE { " \
                    "?date a :DateInformation ; :isAboutPerson ?person ; :hasDateType ?type ; " \
                    ":hasValue ?value . OPTIONAL { ?date :hasDateInterval ?interval } " \
                    "OPTIONAL { ?date :isUncertain ?uncertain } } ORDER BY ?date".freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "dprr",
        name: "DPRR — Digital Prosopography of the Roman Republic (person authority)",
        license: "CC BY-NC 4.0 (King's College London; the RDF documentation footer and every RDF " \
                 "serialization's header verbatim, verified on the live site 2026-10-27)",
        license_class: "nc",
        upstream_url: "https://romanrepublic.ac.uk/",
        parser_family: "dprr-sparql"
      )

      def self.manifest
        MANIFEST
      end

      # No zip, no Last-Modified: the endpoint itself 500s a bare HEAD, so
      # the probe HEADs the documentation page for reachability only.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "rdf/doc", zip_url: DOC_URL, metadata_url: nil,
          state_subdir: "", state_file: STATE_FILE, liveness_only: true
        )]
      end

      def self.person_index_producer? = true

      def self.person_index_producer(catalog:)
        Nabu::DprrPersons::Producer.new(catalog: catalog)
      end

      # A feature module mints no documents (the cbdb shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: dprr is a person authority, not a text source — " \
                          "parse is unreachable"
      end

      # Both SELECTs → validated → written only after both answers check
      # out (a half-landed pair never replaces a good one).
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        progress&.call("Querying #{ENDPOINT} (persons, dates)…\n")
        persons = select!(PERSONS_QUERY, label: "persons")
        dates = select!(DATES_QUERY, label: "dates")
        count = JSON.parse(persons).dig("results", "bindings").size
        raise Nabu::FetchError, "dprr: the persons answer holds zero persons — refused" if count.zero?

        File.write(File.join(workdir, PERSONS_FILE), persons)
        File.write(File.join(workdir, DATES_FILE), dates)
        sha = Digest::SHA256.hexdigest(persons + dates)
        File.write(File.join(workdir, STATE_FILE),
                   JSON.pretty_generate("endpoint" => ENDPOINT, "sha256" => sha, "persons" => count,
                                        "fetched_at" => Time.now.utc.iso8601))
        FetchReport.new(sha: sha, fetched_at: Time.now, notes: "#{count} persons (SPARQL answers verbatim)")
      end

      private

      def select!(query, label:)
        url = "#{ENDPOINT}?query=#{URI.encode_www_form_component(query)}"
        response, = Nabu::RedirectFollow.get(url, http: Nabu::ZipFetch.default_http,
                                                  error: Nabu::FetchError, headers: { "Accept" => ACCEPT })
        body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
        parsed = JSON.parse(body)
        raise JSON::ParserError, "no results.bindings" unless parsed.dig("results", "bindings").is_a?(Array)

        body
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "dprr: the #{label} answer is not a SPARQL results document (#{e.message})"
      end
    end
  end
end
