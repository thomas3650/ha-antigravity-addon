# HA Antigravity

Runs Google Antigravity CLI (`agy`) with Remote Control in a Home Assistant
add-on, as an always-on personal assistant.

## Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store → ⋮ → Repositories** and add:

   ```text
   https://github.com/thomas3650/ha-antigravity-addon#release
   ```

2. Install **HA Antigravity** and start it.
3. Open the **Antigravity** panel in the sidebar (Ingress).
4. Click **Chat** to open the assistant's terminal, or **Shell** for a login
   shell as the `antigravity` user.
5. On first start, before you have logged in, the chat terminal prints
   instructions to run `agy` and follow the Google OAuth link. Open the URL
   in a browser, paste the authorization code back into the terminal, then
   type `/exit` so the add-on starts the always-on Remote Control session.
   Credentials persist in `/data/home/.gemini/antigravity-cli/` across
   restarts and updates.

## Options

| Option | Default | What it does |
|---|---|---|
| `session_name` | `Home` | Hostname shown in Antigravity Remote Control (`cliRemoteControlHostname`). |
| `repo_url` | *(empty)* | Git repository holding the assistant's workspace (`AGENTS.md`, `.agents/`, `jobs/`). Supports HTTPS or SSH (with `deploy_key`). |
| `repo_path` | `assistant` | Subfolder inside `repo_url` to publish as `/data/workspace/assistant`. Optional `<repo_path>/sync-includes.json` may list validated relative `{from, to}` files/folders in the same repo to include at sync time. |
| `deploy_key` | *(empty)* | Read-only SSH private key (no passphrase) for cloning a private `repo_url`. |
| `chat_model` | *(empty)* | Optional Antigravity model ID for interactive chat (e.g. `claude-opus-5-5-medium`). |
| `job_model` | *(empty)* | Optional Antigravity model ID for unattended runs (e.g. `gemini-3.8-flash-high`). |
| `extra_packages` | `[]` | Extra apt packages installed on startup. |
| `assistant_env` | `[]` | Extra environment variables passed to `agy` (names must start with `ASSISTANT_`). |
| `extra_mcp` | `[]` | Additional Streamable HTTP MCP upstreams (`name=http(s)://...`) proxied on `127.0.0.1:7684/mcp/<name>`. |
| `extra_mcp_auth` | `[]` | Bearer tokens (`name=token`) injected by root-owned nginx into `/mcp/<name>` requests, never exposed to the `antigravity` user. |
| `morning_job` | *(empty)* | Name of a fixed repo job file started by the `morning` stdin command. |
| `morning_timeout` | `900` | Default timeout (seconds) for morning runs. |
| `morning_max_turns` | `40` | Default turn cap (`HA_AGY_MAX_TURNS`) for morning runs. |
| `morning_chat` | `true` | Whether a repo job with `after: ["clear_chat"]` clears/restarts the chat session after running. |
| `run_timeout` | `900` | Default timeout (seconds) for `run <agent>` and fixed repo jobs. |
| `run_max_turns` | `60` | Default turn cap (`HA_AGY_MAX_TURNS`) for `run <agent>` and fixed repo jobs. |
| `chat_resume` | `false` | When `true`, starts `agy --continue` across restarts and unchanged syncs until cleared. |
| `jobs_parallel` | `3` | Maximum concurrent chat jobs. |
| `job_timeout` | `1800` | Default timeout (seconds) for chat jobs. |
| `job_max_turns` | `60` | Default turn cap (`HA_AGY_MAX_TURNS`) for chat jobs. |

## Commands on standard input (`hassio.addon_stdin`)

Send a JSON string (or object) to the add-on's standard input:

- `"ping"` — reports `outcome: ping=ok`.
- `"sync"` — waits for running jobs, pulls `repo_url` (sparse checkout of `repo_path` plus `sync-includes.json`), installs root-owned managed settings from `.agents/managed-settings.json`, updates fixed repo jobs, and restarts or clears the chat session.
- `"restart-chat"` — restarts the tmux chat session.
- `"clear-chat"` — sends `/clear` to the running chat session, waits up to 15s for `HA_AGY_SESSION_MARK` confirmation from `.agents/hooks.json` `SessionStart`, and falls back to a fresh restart if unconfirmed.
- `"morning"` — runs the fixed job named by `morning_job`.
- `"run <agent>"` — runs `.agents/agents/<agent>/agent.md` (or `<agent>.md`) unattended via `agy` stream-json stdin with `HA_AGY_UNATTENDED=<agent>` and `HA_AGY_MAX_TURNS`, validates `/data/results/<agent>.json`, and raises `ha_antigravity_result` + `ha_antigravity_outcome`.
- `"jobs tick"` — evaluates scheduled chat jobs and fixed repo jobs (`run_by: jobs`), publishes MQTT discovery/state under `ha_antigravity/jobs`, and starts due jobs.
- `"report"` or `"report YYYY-MM"` — runs `.agents/report` as `antigravity` and writes sanitized framed output to the add-on log.
- `"memory"` — writes Markdown files from `/data/home/notes/` to the add-on log (framed and bounded).

## Events raised in Home Assistant

- `ha_antigravity_outcome` (`command`, `outcome`, optional `agent` and `by`)
- `ha_antigravity_result` (`agent`, `count`, `verdict`, `text`)
- `ha_antigravity_job_notify` (`job`, `finding`)

## Built-in MCP servers & loopback auth proxy

- **Home Assistant & `extra_mcp` proxy (`127.0.0.1:7684`):** Root-owned nginx
  forwards POST `/mcp` to Home Assistant's MCP endpoint (with `SUPERVISOR_TOKEN`)
  and POST `/mcp/<name>` to each `extra_mcp` upstream (with its `extra_mcp_auth`
  Bearer token). Point `.agents/mcp_config.json` at `http://127.0.0.1:7684/mcp/<name>`.
- **`/usr/local/bin/ha-antigravity-jobs-mcp`:** Stdio MCP server (`job_list`,
  `job_set`, `job_run_now`, `job_status`) validating job files against
  `/usr/share/ha-antigravity/schemas/`. Refuses calls when `HA_AGY_UNATTENDED`
  or `HA_AGY_JOB` is set.
- **`/usr/local/bin/ha-antigravity-docs-mcp`:** Stdio MCP server
  (`read_document`) reading `.docx`, `.xlsx`, `.pptx`, `.odt`, `.ods`, `.odp`,
  and `.pdf` (via `pdftotext`) only from `/data/home/.gemini/antigravity-cli/uploads/`,
  refusing symlinks and unattended runs.
- **`/usr/local/bin/ha-antigravity-browser-mcp`:** Hardened wrapper around
  pinned `@playwright/mcp` running root-owned Chromium headless shell with its
  sandbox enabled and in-memory profile. Refuses to run as root.

## Security boundary

- The assistant runs as unprivileged user `antigravity` (`UID 1500`) with a
  scrubbed environment (`SUPERVISOR_TOKEN` never reaches `antigravity`).
- `/data/workspace/assistant`, `/data/home`, `/data/home/.gemini`, and
  `/data/home/.gemini/config` are owned by `root:root` (`0755`) with read-only
  placeholders (`0444`/`0555`) for global `hooks.json`, `mcp_config.json`,
  `config.json`, `skills.json`, `plugins.json`, `rules.json`, `AGENTS.md`,
  `GEMINI.md`, `plugins/`, `agents/`, `skills/`, and `rules/`. The `antigravity`
  user cannot rename `~/.gemini` or inject global hooks/MCP servers.
- Only explicit writable subdirectories (`notes`, `tool-record`, `.cache`,
  `.config`, `.ssh`, `.npm`, `.local`, `.gemini/antigravity-cli`,
  `.gemini/config/projects`, `/data/handover`, `/data/results`, `/data/jobs`)
  are owned by `antigravity`.
- Root installs `.agents/managed-settings.json` to `/etc/ha-antigravity/settings.json`
  (passed via `--settings` to every `agy` run) and seeds its `permissions.deny`
  and `toolPermission` baseline into `~/.gemini/antigravity-cli/settings.json`
  without reading user files as root.
- Handover and writable data folders are cleaned of instruction/config files
  (`AGENTS.md`, `GEMINI.md`, `CLAUDE.md`, `CLAUDE.local.md`, `.agents`,
  `.agent`, `_agents`, `_agent`, `.claude`, `hooks.json`, `mcp_config.json`,
  `.mcp.json`) before runs and on startup.

## Troubleshooting

Open **Shell** in the sidebar and run `ha-antigravity-status`. It reports
`antigravity login: yes` or `no`, the tmux chat session state, and the last
`sync` status. If `antigravity login: no`, open the **Chat** tab and complete
the Google OAuth login.
