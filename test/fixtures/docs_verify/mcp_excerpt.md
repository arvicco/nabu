# The MCP server — talking to the corpus

## 2. The fourteen tools

Every passage in every response carries **urn**, **language**, and
## 3. Registration — Claude Code

### Project scope (this repo — nothing to do)

This repo ships **`.mcp.json`** in its root:

```json
{
  "mcpServers": {
    "nabu": {
      "command": "bundle",
      "args": ["exec", "bin/nabu", "mcp"]
    }
  }
}
```

Open Claude Code with this repo as the working directory and the `nabu` server
is offered automatically (Claude Code asks once whether to trust project-scoped
servers). The command is run from the repo root, so `bundle` finds the Gemfile
and `bin/nabu` resolves. Nothing else is required.

### User scope (nabu tools in every project)

To have the tools everywhere — not just when your cwd is this repo — add a
user-scoped server. The catch: `bundle` needs *this repo's* Gemfile, but a
user-scoped server is spawned without the repo as its working directory. Pin the
Gemfile with an **absolute** `BUNDLE_GEMFILE` and give `bin/nabu` an absolute
path so neither depends on cwd:

```bash
claude mcp add --scope user nabu \
  --env BUNDLE_GEMFILE=/Users/vb/Dev/nabu/Gemfile \
  -- bundle exec /Users/vb/Dev/nabu/bin/nabu mcp
```
## 4. Registration — Claude Desktop

Claude Desktop reads `~/Library/Application Support/Claude/claude_desktop_config.json`
(macOS). It is spawned with no useful cwd, so use absolute paths, exactly as for
user scope:

```json
{
  "mcpServers": {
    "nabu": {
      "command": "bundle",
      "args": ["exec", "/Users/vb/Dev/nabu/bin/nabu", "mcp"],
      "env": {
        "BUNDLE_GEMFILE": "/Users/vb/Dev/nabu/Gemfile"
      }
    }
  }
}
```
### Agent frameworks — LangChain, LlamaIndex

Any framework with an MCP stdio client can load the tools. The examples
below start the public demo image, pinned to its released tag, so they run
with nothing but Docker installed; to use your own library, swap the
command for the `bundle exec … bin/nabu mcp` form above.

LangChain (`pip install langchain-mcp-adapters`):

```python
import asyncio
from langchain_mcp_adapters.client import MultiServerMCPClient

async def main():
    client = MultiServerMCPClient({
        "nabu": {
            "command": "docker",
            "args": ["run", "-i", "--rm", "ghcr.io/arvicco/nabu-demo:1.8.0"],
            "transport": "stdio",
        }
    })
    tools = await client.get_tools()  # LangChain tools, ready for an agent
    print([tool.name for tool in tools])

asyncio.run(main())
```
