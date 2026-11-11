# Security policy

## Reporting a vulnerability

Report suspected vulnerabilities in Nabu, the published demo image
(`ghcr.io/arvicco/nabu-demo`), or the MCP server by email to
**arvicco@nabu.ac**. Please do not open a public issue for a
security report.

You can expect an acknowledgement within a few days. Please include
enough detail to reproduce the problem (version or image tag,
steps, expected vs observed behavior).

## Scope

The demo image runs fully offline: the MCP server reads a baked
SQLite slice and makes no network requests at runtime. Reports about
the library's fetch pipeline (which does talk to upstream sources)
are equally welcome.

## Supported versions

The latest released demo image tag and the current `main` branch.
