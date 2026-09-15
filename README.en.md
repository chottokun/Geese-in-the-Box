# Goose-in-the-Box: Complete Traffic Control & Audit Sandbox for AI Agents

[English](README.en.md) | [日本語](README.md)

Goose-in-the-Box is a Docker-based, completely network-isolated and audited sandbox designed for safely running the AI agent "Goose".

With a **dual-layer defense mechanism** consisting of Docker's `internal: true` network (L3/L4) and a Squid forward proxy (L7), it 100% blocks unauthorized external communications and data exfiltration by AI agents. All connection attempts are recorded and audited in structured JSON logs. Additionally, Goose's anonymous telemetry transmission is disabled by default.

---

## Key Features

- 🔒 **Complete Elimination of Proxy Bypasses (L3/L4 Isolation)**:
  - Agent containers reside within an `internal: true` network with no default gateway to the outside world.
  - Even if direct connection attempts (e.g., direct IP hits or DNS leaks) bypassing proxy configurations are made, the Linux kernel immediately drops the packets (`Network unreachable`).
- 🛡️ **Strict Whitelist Control (L7 Control)**:
  - The Squid proxy acts as the sole outbound gateway, allowing traffic only to domains listed in `squid/whitelist.txt`. Unapproved domains are blocked immediately with `403 Forbidden`.
- 📊 **Structured JSON Audit Logging**:
  - All network events (allowed, denied, HTTP status, domain, transferred bytes) are logged with ISO 8601 timestamps in `/var/log/squid/access.json`, enabling fast CLI filtering and aggregation.
- 🚫 **Mandatory Telemetry Suppression**:
  - `GOOSE_TELEMETRY_ENABLED=false` is enforced to prevent the agent from sending telemetry data.

---

## Repository Structure

```text
goose-in-the-box/
├── docker-compose.yml       # Definitions for internal network (internal-net) and external proxy (external-net)
├── Makefile                 # Commands for build, test, session, GUI, log monitoring, and exports
├── README.md                # Japanese documentation
├── README.en.md             # English documentation (this file)
├── .env.example             # Template for environment variables and API keys
├── squid/
│   ├── squid.conf           # Strict forward proxy rules + JSON audit log definitions
│   └── whitelist.txt        # Allowed domain whitelist (LLMs, GitHub, PyPI, npm, etc.)
├── nginx/
│   └── nginx.conf           # Ingress reverse proxy configuration (noVNC WebSocket / ACP proxy)
├── goose/
│   └── Dockerfile           # Goose Desktop/CLI + Xfce4/noVNC + Fcitx5 + uv/npm/tmux
├── bin/
│   ├── test-egress.sh       # Automated verification script for network isolation and proxy audit
│   ├── start-goose.sh       # Session startup script combining AGENTS.md / rules
│   ├── start-desktop.sh     # Startup script for Xfce4, VNC, websockify, Fcitx5, Goose Desktop
│   ├── audit-tools.sh       # Audit log aggregation and violation detection tools
│   ├── watch-alerts.sh      # Real-time alert monitoring with storm suppression and webhooks
│   ├── generate-report.sh   # Observability report and JSON/Markdown API generator
│   └── session-audit.sh     # Cross-session network traffic comparison
├── workspace/               # Goose working directory (real-time host bind mount)
│   ├── .goosehints          # Official project hints for Goose (Git, tmux, uv preferences)
│   ├── .gitignore           # Standard workspace ignore settings
│   ├── AGENTS.md            # Execution rules and security guidelines for AI agents
│   └── .agents/             # Skills and modularized rules
├── config/                  # Goose configuration directory (persisted host mount)
│   ├── config.yaml          # Provider (e.g. Ollama) and extension configs
│   └── llm-pricing.json     # Pricing model and alert thresholds for observability
├── data/                    # Storage for Goose internal persistent data
│   ├── sessions/            # Chat session history DB
│   └── logs/                # Goose internal application logs
├── logs/                    # Audit logs directory (accessible from host)
│   ├── squid/
│   │   ├── access.json      # Structured JSON audit log
│   │   └── access.log       # Standard text access log
│   ├── nginx/
│   │   └── ingress.json     # Ingress audit log
│   └── report/              # Dashboard Web UI and API outputs
└── plan/                    # Implementation and architecture documentation
```

---

## Configuration Parameters (.env)

All environment variables are centrally managed via the `.env` file (refer to `.env.example`).

| Parameter | Description | Default Value |
| :--- | :--- | :--- |
| **`HOST_BIND`** | Host IP binding configuration (`0.0.0.0` for all, `127.0.0.1` for local only) | `0.0.0.0` |
| **`OPENAI_API_KEY` etc.** | API keys for various LLM providers | (empty) |
| **`OPENAI_BASE_URL`** | OpenAI-compatible base URL (no trailing slash) | `https://api.openai.com/v1` |
| **`OPENAI_HOST`** | OpenAI-compatible hostname for provider resolution | `https://api.openai.com` |
| **`OLLAMA_HOST`** | Local LLM host endpoint (port 11434) | `http://host.docker.internal:11434` |
| **`NOVNC_PORT`** | noVNC Web UI port (browser access) | `6080` |
| **`GOOSE_SERVE_PORT`** | Goose ACP server listening port | `3284` |
| **`SQUID_PORT`** | Squid proxy listening port | `3128` |
| **`DOZZLE_PORT`** | Dozzle real-time log viewer Web port | `8080` |
| **`RESOLUTION`** | Virtual desktop screen resolution | `1280x800x24` |
| **`TZ`** | System timezone for logs and clock | `Asia/Tokyo` |
| **`SHM_SIZE`** | Shared memory size for virtual desktop stability | `1gb` |
| **`UID` / `GID`** | User ID / Group ID inside the container | `1000` / `1000` |
| **`GOOSE_TELEMETRY_ENABLED`** | Toggle for anonymous usage telemetry | `false` |

---

## Quick Start

### 1. Environment Setup
```bash
cp .env.example .env
# Edit .env to set your API keys and configuration
```

### 2. Build Container Images
```bash
make build
```

### 3. Run Automated Isolation Test
Execute the test suite from inside the sandbox to verify that network controls are functioning as intended:
```bash
make test
```
**Test Coverage:**
1. ✅ **Whitelisted Domain (`api.openai.com`)**: Connects successfully through proxy
2. 🛑 **Unapproved Domain (`www.google.com`)**: Blocked with `403 Forbidden` by Squid
3. 🔒 **Direct Connection Bypass**: Dropped with `Network unreachable` via Docker `internal: true`

---

## Running Goose

### Interactive CLI Session
Starts an interactive Goose CLI session inside the isolated container, automatically loading `workspace/AGENTS.md` and `.agents/rules/*.md`:
```bash
make session
```

### Connection with Goose Desktop (Host GUI)
Launches the Agent Communication Protocol (ACP) server so host-side Goose Desktop can connect:
```bash
make serve
```
* Connection endpoint for host Goose Desktop: `http://localhost:3284`

### In-Container GUI Desktop (noVNC Browser Control)
To enable agent web browsing or inspect the full container desktop UI:
```bash
make gui
```
* Open **`http://localhost:6080/vnc.html`** in your browser to view and control the Xfce4 desktop environment inside the sandbox.
* For native VNC clients, connect to `localhost:5900`.

---

## Audit Logs & Traffic Observability

### Real-time Web Log Viewer via Dozzle
Dozzle is integrated into `docker-compose.yml` for viewing, searching, and filtering container logs live in your browser:
* Access **`http://<HOST_IP>:8080`** (e.g., `http://localhost:8080`)
* Select the `egress-proxy` container to observe Squid access events (`TCP_TUNNEL/200`, `TCP_DENIED/403`) cleanly without health check noise.

### Real-time CLI Audit Logs
```bash
make logs
```

### Real-time Color Alert Monitoring
Detect blocked connection attempts instantly in your terminal (supports alert storm suppression and Webhook notifications):
```bash
make watch
```

### List Blocked Requests (403 DENIED)
View domains and URLs blocked by the proxy when accessed by the agent:
```bash
make audit-denied
```

### Domain Frequency & Data Transfer Summary
```bash
make audit-summary
```

### Ingress Audit Logs
Display connection logs from host connections to noVNC and ACP server:
```bash
make audit-ingress
```

### Observability Dashboard & APIs for Humans and LLMs
Analyzes Squid JSON logs (`/var/log/squid/access.json`) to generate human-readable Web Dashboards and structured JSON/Markdown APIs for LLM agents:

- `user_agent`: Identify tools and libraries making outbound requests
- `bytes_sent` / `bytes_received`: Estimate LLM token usage and cost
- `duration_ms`: Response time per request
- `alerts`: Proactive alert evaluations for block rate spikes or large transfers

```bash
# Generate dashboard and JSON / Markdown API manually
make report

# Output JSON report directly to stdout for LLM monitoring pipelines
make report-json
```

- 🔄 **Automated Continuous Updates (`report-watcher`)**:
  - When running via `make up-proxy` or `docker compose up -d`, a dedicated background worker automatically recalculates metrics every 30 seconds (interval configurable via `REPORT_INTERVAL` in `.env`).
- 📊 **Web UI Dashboard**: `http://<HOST_IP>:6080/report/` (Auto-refreshes every 30s with direct links to noVNC & Dozzle)
- 🤖 **LLM JSON API**: `http://<HOST_IP>:6080/report/api/status.json` (Structured JSON for curl or LLM parsing)
- 📝 **LLM Markdown Summary**: `http://<HOST_IP>:6080/report/api/summary.md` (Context-optimized text summary)
- ⚙️ **Pricing & Alert Rules**: Configurable via `config/llm-pricing.json`

### Cross-Session Comparison
Compare network patterns across historical session logs:
```bash
make audit-history
```

### Manual Log Rotation
```bash
make log-rotate
```

---

## Dynamic Whitelist Management & Emergency Kill-Switch

### Dynamic Whitelist Reload
To add or modify allowed egress domains, edit `squid/whitelist.txt` on the host and reload configuration instantly:
```bash
# Run after updating squid/whitelist.txt
make reload
```
*(Applies changes immediately without breaking active connections)*

### Emergency Kill-Switch
Instantly cut off or restore all outbound agent traffic via CLI:
```bash
# Emergency block: Clears whitelist and reconfigures Squid
make block-all

# Restore traffic: Restores original whitelist and reconfigures Squid
make unblock
```

---

## Starter Environment & MCP Infrastructure

The sandbox includes pre-configured tooling and best practices so AI agents can autonomously write code and interact with Model Context Protocol (MCP) servers:

1. **Core Utilities & Pre-configured Git**:
   - `git` pre-configured with `user.name` (Goose Agent), `user.email`, `safe.directory`, and `defaultBranch`.
   - `tmux` (background session persistence and mouse support enabled).
   - Core CLI tools: `build-essential` (make, gcc, etc.), `wget`, `unzip`, `nano`, `less`, `htop`, `tree`.
2. **Runtimes & MCP Infrastructure**:
   - **Python 3.11** + **`uv` / `uvx`**: Ultra-fast package management and on-demand MCP server execution.
   - **`pipx`**: Isolated CLI tool execution environment.
   - **Node.js** + **`npm` / `npx`**: Platform for running TypeScript/JavaScript MCP servers.
3. **Official Project Instructions (`.goosehints`)**:
   - Located at `/workspace/.goosehints`, defining best practices for agent execution.

---

## Workspace Sharing & Artifact Export

1. **Real-time Host Synchronization (Bind Mount)**:
   - Any files created or modified by Goose inside `/workspace` are immediately synchronized to `./workspace/` on the host machine.
2. **One-command Artifact Export**:
   - Export workspace artifacts into a timestamped tar.gz archive:
     ```bash
     make export-workspace
     ```
     Archives are saved to `exports/workspace_YYYYMMDD_HHMMSS.tar.gz`.
