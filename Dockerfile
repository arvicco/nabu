# syntax=docker/dockerfile:1
#
# The nabu MCP server image — two targets from one Dockerfile.
#
# DEFAULT target (`docker build .`): code + config only, no library. Boots
# the read-only MCP server (bin/nabu mcp) for directory introspection
# checks. Without a synced library the server still starts: every tool
# answers with an honest missing-catalog note, so initialize/tools/list
# work in a sandbox. A real library needs the host's db/ and canonical/
# mounted in.
#
# `demo` target: the same image plus a PREBUILT demo library slice baked
# in at /demo — a small open/attribution-only starter set (sources,
# license classes and sizes in /demo/demo-census.json), so a fresh
# container answers real questions with no mounts. The slice is built
# OUTSIDE docker, never during `docker build` (it runs real syncs):
#
#   bundle exec rake demo:build              # → tmp/demo (DEMO_OUT overrides)
#   docker build --target demo --build-context demo-slice=tmp/demo -t nabu-mcp:demo .
#
# The slice arrives through the named build context `demo-slice`
# (BuildKit, dockerfile syntax 1.4+), so
# the main context's .dockerignore (which keeps tmp/ out of the plain
# image) does not apply to it. Building the target without that context
# fails loudly rather than shipping an empty demo.
#
# Running it (stdio is the default; HTTP for hosted deployments):
#
#   docker run -i --rm nabu-mcp:demo                                  # stdio
#   docker run --rm -p 8080:8080 nabu-mcp:demo bin/nabu mcp --http    # POST http://localhost:8080/mcp
#
# PORT sets the HTTP port (default 8080); the image binds 0.0.0.0
# (NABU_MCP_HOST) since the container boundary is the network edge.
FROM ruby:3.3 AS base
RUN apt-get update -qq && apt-get install -y --no-install-recommends libsqlite3-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
ENV NABU_MCP_HOST=0.0.0.0

FROM base AS demo
# `demo-slice` is the named build context, deliberately not a stage here:
# without --build-context the COPY fails (BuildKit tries to resolve it as
# an image), and a context that is not a finished slice fails the check.
COPY --from=demo-slice / /demo/
RUN test -f /demo/demo-census.json || \
    { echo "not a finished demo slice: run rake demo:build, pass --build-context demo-slice=tmp/demo" >&2; exit 1; }
# The two variables that point the server at the slice (Nabu::DemoBuild).
ENV NABU_ROOT=/demo NABU_CONFIG=/demo/config/nabu.yml
# OCI labels: source links the GHCR package to the repo; the
# io.modelcontextprotocol.server.name label is how the official MCP
# Registry verifies ownership of an OCI package (it must equal the
# server name in server.json). Licenses states the CODE license; the
# baked data carries per-source open licenses, see /demo/demo-census.json.
LABEL org.opencontainers.image.source="https://github.com/arvicco/nabu" \
      org.opencontainers.image.description="Nabu demo: an ancient-text research library slice behind an MCP server (stdio + streamable HTTP). Code MIT; baked data per-source open licenses (demo-census.json). Full library is a local build." \
      org.opencontainers.image.licenses="MIT" \
      io.modelcontextprotocol.server.name="io.github.arvicco/nabu-demo"
CMD ["bin/nabu", "mcp"]

# The default target stays last: `docker build .` builds the plain image.
FROM base AS plain
CMD ["bin/nabu", "mcp"]
