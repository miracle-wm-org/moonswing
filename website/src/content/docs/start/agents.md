---
title: AI agents (MCP)
description: Point Claude, an OpenAI model or an open-source model at your desktop with moonswing-mcp, and ask it to arrange your windows and drive the shell.
sidebar:
  order: 4
---

Moonswing comes with an [MCP](https://modelcontextprotocol.io) server, `moonswing-mcp`.
Point an AI agent at it and you can ask in plain language: *"put Firefox and the
terminal side by side on workspace 2"*, *"what's on my todo board?"*, *"remind me
in 20 minutes to take the bread out"*, *"switch to the Dracula theme"*, *"look at
my screen and tell me why that build failed"*.

It works with any client that speaks MCP. This page covers Claude, OpenAI's models
and open-source models run locally.

## What it can do

The server has about forty tools in five groups:

| Group | What it reaches | Needs |
|---|---|---|
| `wm_*` | Windows, workspaces and screens: list them, focus, move, resize, float, fullscreen, close, set the layout, or send any [miracle-wm command](https://wiki.miracle-wm.org/develop/ipc/commands/) the way `miraclemsg` would | miracle-wm's IPC socket (sway and i3 work too) |
| `shell_*` | The launcher and the other shortcut actions, the overview and Settings pages, themes, finding and launching apps, screenshots, notifications and do-not-disturb, timers, volume | Moonswing running |
| `todo_*`, `note_*` | The overview's kanban board and sticky notes | Moonswing running |
| `media_*` | What's playing, and play, pause and skip, in any MPRIS player | Nothing extra |

`shell_send_notification` uses the standard notification interface, so it works with
any notification daemon. `moonswing-mcp --list-tools` prints the full list.

The window-manager tools talk to the compositor directly, so they work even if the
shell is not running. The shell tools talk to Moonswing over the session bus
(`org.moonswing.Shell`), which has to be switched on in Moonswing's config. It is on
by default; see [Agent Control](../../configuration/overlays/#agent-control).

## Getting the server

**Snap:** the server comes with the snap as `moonswing.mcp`. Use that wherever this
page says `moonswing-mcp`.

**From source:** `make install` builds it and installs `moonswing-mcp` next to
`moonswing`. To build only the server:

```bash
dart build cli -t bin/moonswing_mcp.dart -o build/mcp
```

That gives you `build/mcp/bundle/bin/moonswing_mcp`. Keep the whole `bundle/`
directory together, because the binary loads its code from `bundle/lib/`.

Check that it runs:

```bash
moonswing-mcp --list-tools
```

### How clients start it

Most clients start the server for you and talk to it over stdin and stdout. That is
the default, and there is nothing to configure. A few clients can only connect to a
URL. For those, run the server yourself:

```bash
moonswing-mcp --http 8765
```

It then serves `http://127.0.0.1:8765/mcp` ([Streamable
HTTP](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports)).
See [Security](#security) before you make it reachable from anywhere but this machine.

### Options

| Option | |
|---|---|
| `--read-only` | Only offer tools that change nothing: listing, status, screenshots. A good way to start. |
| `--only wm,shell` | Only offer these groups (`wm`, `shell`, `todo`, `note`, `media`). Small models do much better with fewer tools to choose from. |
| `--allow-exec` | Let the model run any command line through the window manager's `exec`. Off by default; see [Security](#security). |
| `--http [HOST:]PORT` | Serve over HTTP instead of stdio. |
| `--token TOKEN` | Require `Authorization: Bearer TOKEN` over HTTP. You can also set `MOONSWING_MCP_TOKEN`. |
| `--wm-socket PATH` | Path to the compositor's IPC socket, if the server can't find it. |

## Claude

### Claude Code

```bash
claude mcp add --scope user moonswing -- moonswing-mcp
```

`--scope user` makes the server available in every project. Run `/mcp` in a session
to check that it connected. Then ask, for example: *"Tile my two terminals
side by side and move Slack to workspace 9."*

To add options, put them after the command:

```bash
claude mcp add --scope user moonswing -- moonswing-mcp --only wm,shell
```

To connect to a server you started with `--http`:

```bash
claude mcp add --transport http moonswing http://127.0.0.1:8765/mcp
```

### Claude Desktop and other config-file clients

Many clients read the same JSON shape: Claude Desktop, Cursor, LM Studio, Cline and
others. Claude Desktop keeps it in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "moonswing": {
      "command": "moonswing-mcp",
      "args": []
    }
  }
}
```

Claude Desktop is not officially released for Linux. Use this if you run it some
other way, or with any client that reads this format.

### Your own code

The [Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk) runs the same
agent loop as Claude Code from Python or TypeScript. Give it the server the same
way, as a stdio server whose command is `moonswing-mcp`. Its MCP tools show up as
`mcp__moonswing__<tool>`, and they have to be allowed like any other tool.

## OpenAI

### Codex CLI

```bash
codex mcp add moonswing -- moonswing-mcp
```

Or add it to `~/.codex/config.toml` yourself:

```toml
[mcp_servers.moonswing]
command = "moonswing-mcp"
args = ["--only", "wm,shell,todo"]
```

### The Agents SDK (Python)

The [OpenAI Agents SDK](https://openai.github.io/openai-agents-python/mcp/) starts
the server over stdio and gives its tools to the agent:

```python
import asyncio
from agents import Agent, Runner
from agents.mcp import MCPServerStdio

async def main():
    async with MCPServerStdio(
        name="moonswing",
        params={"command": "moonswing-mcp", "args": []},
        cache_tools_list=True,
    ) as desktop:
        agent = Agent(
            name="Desktop assistant",
            instructions="You arrange the user's windows and run their desktop.",
            mcp_servers=[desktop],
        )
        result = await Runner.run(
            agent, "Move every terminal to workspace 3 and tile them."
        )
        print(result.final_output)

asyncio.run(main())
```

### The Responses API and ChatGPT

OpenAI's hosted MCP support (the `mcp` tool in the Responses API, and connectors in
ChatGPT's developer mode) calls the server **from OpenAI's servers**. Your machine
would have to accept connections from the internet, through a tunnel to
`moonswing-mcp --http` with a `--token`. That lets anyone who has the URL and token
control your desktop. If you do it anyway, set `require_approval` to `"always"`, use
`--read-only` if you can, and shut the tunnel down afterwards. The Agents SDK above
does the same job without any of this, because the server runs on your machine.

## Open-source models

The server doesn't care which model is behind the client. What matters is that the
**model was trained for tool calling**: recent Qwen, Llama 3.1+, Mistral, gpt-oss
and similar models work. Small models get confused by forty tools, so start with
`--only wm` or `--only wm,shell` and add groups as you go.

### LM Studio

LM Studio reads MCP servers from `~/.lmstudio/mcp.json` (edit it from the Program
tab, under *Install › Edit mcp.json*):

```json
{
  "mcpServers": {
    "moonswing": {
      "command": "moonswing-mcp",
      "args": ["--only", "wm,shell"]
    }
  }
}
```

### Ollama

Ollama runs models but is not an MCP client itself, so you need a client in front of
it. Two that work:

- **The OpenAI Agents SDK, pointed at Ollama.** Ollama serves an OpenAI-compatible
  API, so the [Agents SDK example](#the-agents-sdk-python) works unchanged once the
  agent is given a local model:

  ```python
  from openai import AsyncOpenAI
  from agents import Agent, OpenAIChatCompletionsModel, set_tracing_disabled

  set_tracing_disabled(True)  # tracing uploads to OpenAI; nothing to send it to
  local = OpenAIChatCompletionsModel(
      model="qwen3:8b",
      openai_client=AsyncOpenAI(base_url="http://localhost:11434/v1", api_key="ollama"),
  )
  agent = Agent(name="Desktop assistant", model=local, mcp_servers=[desktop])
  ```

  This works the same for llama.cpp's `llama-server`, vLLM, or any other server
  with an OpenAI-compatible `/v1` endpoint. Change `base_url` to point at it.

- **A terminal chat client** such as
  [`ollmcp`](https://github.com/jonigl/mcp-client-for-ollama) or
  [`mcphost`](https://github.com/mark3labs/mcphost). Both read the `mcpServers`
  JSON shown [above](#claude-desktop-and-other-config-file-clients); check each
  one's README for its current flags.

### Open WebUI

Open WebUI connects to MCP servers over HTTP. Run `moonswing-mcp --http 8765
--token <a long random string>` and add `http://127.0.0.1:8765/mcp` as an MCP
(Streamable HTTP) tool server under *Settings › External Tools*, with the token as a
bearer token. If Open WebUI runs in a container, `127.0.0.1` is the container's own
address, not your machine's. Either run the server with `--http 0.0.0.0:8765` (which
requires the token) and use the host's address, or give the container host
networking.

Older versions only take OpenAPI tool servers. For those,
[`mcpo`](https://github.com/open-webui/mcpo) wraps the stdio server:
`uvx mcpo --port 8000 -- moonswing-mcp`.

### Goose and others

Any client that can start a command-line MCP server works the same way: the command
is `moonswing-mcp` and it takes no arguments unless you want the options. In
[Goose](https://block.github.io/goose/), that is *Add extension › Command-line
extension*.

## Tips for asking

- **Say what you want, not how.** *"Put the PDF on the left two-thirds and my notes
  on the right"* is enough. The model looks at the window list and works out the
  commands.
- **It can look at your screen.** `shell_screenshot` gives the model a picture of a
  screen, scaled to 1600 pixels wide by default. *"Look at my screen — which window
  is the error in?"* works with any model that accepts images.
- **Windows are referred to by number.** The ids in `wm_list_windows` are
  miracle-wm's container ids. They stay the same for as long as the window is open,
  so a long conversation can keep referring to "that window".
- **It can remind you.** *"Ping me in 25 minutes"* starts a timer
  (`shell_start_timer`) that rings and leaves a notification. *"Add 'renew passport'
  to my todo list for Friday"* puts a card on the board.

## Security

An agent connected to this server can do anything on your desktop that you can do
with the mouse and keyboard. Keep a few things in mind:

- **Prompt injection is the real risk.** A web page, email or file the agent reads
  can contain text written to steer it. With desktop tools available, that text could
  make it close your windows or read your screen. Use `--read-only` while you try
  things out, keep `exec` off (it is off by default), and use clients that ask
  before running a tool.
- **`exec` is off unless you turn it on.** Without `--allow-exec`, the server refuses
  `wm_exec` and any `exec` inside `wm_run_command`. Starting an installed app goes
  through `shell_launch_app`, which only launches desktop entries.
- **HTTP only listens on loopback by default.** The server refuses to listen anywhere
  else without a `--token`. It rejects browser requests from other websites (by
  checking the `Origin` header), so a page you visit cannot reach it.
- **Screenshots can be switched off** on their own with `[control] screenshots =
  false`. The whole interface can be switched off with `[control] enabled = false`,
  and then the shell answers nothing on the bus.

## Troubleshooting

- **"Moonswing is not running, or its control interface is switched off".** The
  shell isn't on the session bus. Check that it's running and that
  `[control] enabled` is not `false`. To test the bus directly:

  ```bash
  gdbus call --session --dest org.moonswing.Shell --object-path /org/moonswing/Shell --method org.moonswing.Shell1.GetStatus
  ```

- **"No window manager IPC socket was found".** The client started the server
  without your session's environment. The server looks for `MIRACLESOCK`, then
  `SWAYSOCK`/`I3SOCK`, then for a `miracle-ipc*.sock` or `sway-ipc*.sock` in
  `$XDG_RUNTIME_DIR`. If none of those works, pass `--wm-socket` with the path
  (`echo $MIRACLESOCK` in a terminal shows it), or set `MIRACLESOCK` in the
  client's server config (most clients take an `env` map).
- **A command came back with a parse error.** miracle-wm doesn't support every i3
  command. The error is passed back to the model, which usually tries something
  else.
- **The model picks the wrong tool, or none.** Give it fewer tools with `--only`, or
  use a bigger model. Tool calling is what small models are worst at.
