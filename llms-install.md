# Installing the Nabu demo MCP server (instructions for AI agents)

This file follows the `llms-install.md` convention: it is written for an
AI agent (Cline, Claude, Cursor, or any MCP-capable client) installing
the server on a user's machine.

## What you are installing

A self-contained demo of Nabu, a local research library of ancient-world
texts. The demo image bundles a frozen sample library and serves **14
MCP tools** over stdio (search, show, concordance, dictionary lookup,
etymology, parallels, and more). It needs no API keys, no configuration,
and no network at runtime.

## Requirement

Docker must be installed and running. Nothing else is needed.

## The one command

Every client starts the same server:

```
docker run -i --rm ghcr.io/arvicco/nabu-demo:1.8.0
```

The first run pulls the image; later runs start instantly. The `-i`
flag is required (MCP speaks over stdin/stdout).

## Per-client configuration

**Cline** — add to `cline_mcp_settings.json` under `mcpServers`:

```json
{
  "mcpServers": {
    "nabu": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "ghcr.io/arvicco/nabu-demo:1.8.0"]
    }
  }
}
```

**Claude Code**:

```
claude mcp add nabu -- docker run -i --rm ghcr.io/arvicco/nabu-demo:1.8.0
```

**Claude Desktop / Cursor / any generic MCP client** — the same
`mcpServers` JSON block as Cline, in that client's MCP settings file.

## Verifying the install

After the client connects, the server should list **14 tools**, all
prefixed `nabu_` (`nabu_search`, `nabu_show`, `nabu_define`,
`nabu_concord`, …). A good smoke test: call `nabu_search` with the
query `In the beginning God created` — it returns Genesis 1:1 from
the demo library (`urn:nabu:eng-web:gen:1.1`) with its parallel
witnesses one `nabu_align` call away.

## Troubleshooting

- **Server exits immediately**: the `-i` flag is missing, or Docker is
  not running.
- **Slow first start**: the initial `docker pull` downloads the image;
  subsequent starts are fast.
- **Tools time out on first call**: allow a few seconds after container
  start; the demo opens its bundled database on first use.

The full project (building your own library beyond the demo slice)
lives at <https://github.com/arvicco/nabu>; the project site is
<https://arvicco.github.io/nabu>.
