# Geese-in-the-Box (formerly Goose-in-the-Box): Network Isolation & Audit Sandbox for Multi-AI Agents

[![CI Sandbox Egress & Audit Test](https://github.com/chottokun/Geese-in-the-Box/actions/workflows/ci.yml/badge.svg)](https://github.com/chottokun/Geese-in-the-Box/actions/workflows/ci.yml)

## 📌 Project Overview (What is Geese-in-the-Box?)
**Geese-in-the-Box** (formerly Goose-in-the-Box) is a "Docker Isolation + Squid Audit Proxy Infrastructure" designed to safely execute autonomous AI agents like Goose, OpenCode, and OpenClaw 2.0.

**Why is it necessary?**
Granting wild AI agents or autonomous coding agents direct network or host access introduces critical risks:
- Unauthorized data exfiltration to external servers.
- Leakage of credentials (e.g., secret keys or API tokens).
- Exploitation or destruction of the host environment itself.

Geese-in-the-Box solves these risks through "Defense in Depth", providing a sandbox where agents can securely reason and act.

---

## 🏛️ Architecture Overview

The core concept of this infrastructure is the **Defense in Depth** model.

1. **L3/L4 Network Isolation (Docker `internal: true`)**:
   - AI agents run in a dedicated internal network completely disconnected from the external internet.
2. **L7 Whitelist Proxy (Squid)**:
   - When agents need to communicate externally, they must route through the Squid proxy.
   - Only pre-approved domains (e.g., `api.openai.com`, `github.com`) are allowed; all other requests are blocked with `403 Forbidden` and logged for auditing.

### Supported Agents
- **Goose Agent** (by Block / CLI & GUI support)
- **OpenCode** (Open-source / Terminal & GUI support)
- **OpenClaw 2.0** (Latest autonomous agent / Terminal & GUI support)

---

## 🚀 Quickstart in 3 Steps

### Step 1: Initial Setup
First, create a `.env` file to configure API keys and settings.
```bash
cp .env.example .env
```
> [!TIP]
> Use `.env` to configure API keys for OpenAI, Anthropic, etc. This is not required if using a local LLM (like Ollama).

### Step 2: Bootup
Build the Docker images and start the agent. Choose the command based on your workflow.

```bash
# Base build (Goose + Proxy infrastructure)
make build

# Start Goose CLI interactive session
make session
```

**Agent startup commands**:
- **Goose**:
  - Terminal: `make session`
  - GUI (Browser Virtual Desktop): `make gui`
- **OpenCode**:
  - Build: `make build-opencode`
  - Terminal: `make run-opencode`
  - GUI (Browser Virtual Desktop): `make run-opencode-gui`
- **OpenClaw 2.0**:
  - Build: `make build-openclaw`
  - Terminal: `make run-openclaw`
  - GUI (Browser Virtual Desktop): `make run-openclaw-gui`

**Container Recreation, Reset & Execution Options**:
- **Recreate containers**: `make recreate` (Drop existing containers and force-recreate fresh from image)
- **Rebuild image without cache**: `make rebuild`
- **Complete teardown & purge**: `make clean-all` (Remove all containers, orphans, and named volumes)
- **Keep container state (`--rm` control)**: `RM=0 make <cmd>` (Do not delete container upon exit, keeping state/installed packages. Default is `RM=1` for ephemeral clean-up)
- **GPU Activation**: `USE_GPU=1 make <cmd>`

### Step 3: Operate & Monitor (Unified UI)
Once the agent is running, you can monitor and control its traffic or interact with GUIs from your browser.
- **Control Panel**: `http://localhost:6080/control/` (Killswitch & Whitelist management)
- **Dozzle (Container Logs)**: `http://localhost:8080/`
- **Virtual Desktop (noVNC)**:
  - Goose: `http://localhost:6080/vnc.html`
  - OpenCode: `http://localhost:6081/vnc.html`
  - OpenClaw 2.0: `http://localhost:6082/vnc.html`

---

## ✨ Key Features Showcase

### 🎛️ Unified Control Panel (`make control`)
A real-time Web UI to dynamically modify domain whitelists and operate the emergency killswitch.
![Geese-in-the-Box Unified Control Panel](docs/images/control-panel-en.png)
- 🔒 **Emergency Killswitch**: Instantly block all outbound agent network traffic with one click.
- ⏳ **One-Click Temporary Whitelisting**: Grant 15-minute or 1-hour exemptions directly from blocked logs.

### 📊 Audit & Observability Dashboard
Automatically aggregates Squid JSON logs to visualize traffic volume and alert trends.
![Geese-in-the-Box Audit & Observability Dashboard](docs/images/audit-dashboard-en.png)
- **Web UI Dashboard**: `http://localhost:6080/report/`

### 🖥️ noVNC Browser Desktop Environment
Includes a fully integrated Xfce4 browser-based desktop environment (with Japanese input Fcitx5 support) for visually monitoring or intervening in GUI agent operations (Goose: `:6080`, OpenCode: `:6081`, OpenClaw: `:6082`).

### 🔄 Multi-Agent Switching Support
Provides a unified secure foundation where you can freely switch between or run Goose, OpenCode, and OpenClaw concurrently.

### ⚡ Selective GPU (NVIDIA CUDA) Passthrough
For machine learning workflows or tasks requiring CUDA acceleration, you can selectively pass through host NVIDIA GPUs to agent containers on-demand. Runs on CPU-only by default.
- **On-demand activation**: Prefix commands with `USE_GPU=1` (e.g., `USE_GPU=1 make session`, `USE_GPU=1 make run-opencode-gui`)
- **Persistent activation**: Set `USE_GPU=true` in `.env`

---

## 🛡️ Security Boundaries

### 🟢 Guarantees
- Blocking direct outbound connections from agent containers (Docker L3/L4 isolation).
- Blocking and auditing L7 (HTTP/HTTPS) traffic to unapproved domains (Squid proxy).
- Preventing opaque bypass connections that do not route through the proxy.

### 🔴 Non-Goals
- Preventing deliberate or obfuscated malicious code written by the agent into the host-bound `/workspace` directory (Users must review workspace changes).
- Preventing data exfiltration techniques that exploit permitted whitelist domains (e.g., `github.com`), aside from DNS tunneling and similar lower-layer bypasses.

---

## 📚 Docs Navigation (LLM-Wiki)

For detailed technical architecture and domain knowledge, refer to our internal LLM-Wiki.

- 📖 **[Geese-in-the-Box LLM-Wiki Index (docs/README.md)](docs/README.md)**
- [Defense in Depth Model (Architecture)](docs/architecture/isolation_model.md)
- [Control Panel Mechanics (Infrastructure)](docs/infrastructure/control_panel.md)
- [Agent Comparison & Concurrency (Domain)](docs/domain/agents_comparison.md)

---

## License
This project is licensed under the [MIT License](LICENSE).
