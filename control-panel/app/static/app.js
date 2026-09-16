let currentKillswitchStatus = "online";
let isAuthEnabled = false;
let isAuthenticated = false;

// API Helper
async function apiCall(endpoint, options = {}) {
  options.headers = options.headers || {};
  if (!options.headers["Content-Type"] && options.body && typeof options.body === "string") {
    options.headers["Content-Type"] = "application/json";
  }

  // サブパス (/control/) 経由でのアクセスに対応
  const basePath = window.location.pathname.startsWith("/control") ? "/control" : "";
  const url = endpoint.startsWith("/") ? `${basePath}${endpoint}` : `${basePath}/${endpoint}`;

  try {
    const response = await fetch(url, options);
    if (response.status === 401) {
      showLoginModal(true);
      throw new Error("認証が必要です");
    }
    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.detail || data.message || "エラーが発生しました");
    }
    return data;
  } catch (err) {
    throw err;
  }
}

// Notification Banner Helper
function showNotification(msg, type = "success") {
  const banner = document.getElementById("notificationBanner");
  banner.className = `alert-msg alert-${type}`;
  banner.innerText = msg;
  banner.style.display = "block";
  setTimeout(() => {
    banner.style.display = "none";
  }, 4000);
}

// Auth Functions
async function checkAuth() {
  try {
    const data = await apiCall("/api/auth/status");
    isAuthEnabled = data.auth_enabled;
    isAuthenticated = data.authenticated;

    document.getElementById("logoutBtn").style.display = isAuthEnabled && isAuthenticated ? "inline-flex" : "none";

    if (isAuthEnabled && !isAuthenticated) {
      showLoginModal(true);
    } else {
      showLoginModal(false);
      initData();
    }
  } catch (err) {
    console.error("Auth check failed:", err);
  }
}

function showLoginModal(show) {
  document.getElementById("loginModal").style.display = show ? "flex" : "none";
}

async function handleLogin(e) {
  e.preventDefault();
  const password = document.getElementById("passwordInput").value;
  const errorEl = document.getElementById("loginError");
  errorEl.style.display = "none";

  try {
    await apiCall("/api/auth/login", {
      method: "POST",
      body: JSON.stringify({ password })
    });
    document.getElementById("passwordInput").value = "";
    showLoginModal(false);
    checkAuth();
  } catch (err) {
    errorEl.innerText = err.message;
    errorEl.style.display = "block";
  }
}

async function logout() {
  try {
    await apiCall("/api/auth/logout", { method: "POST" });
  } catch (e) {}
  checkAuth();
}

// Tab Switching
function switchTab(tabName) {
  document.querySelectorAll(".tab-btn").forEach(btn => btn.classList.remove("active"));
  document.querySelectorAll(".tab-content").forEach(content => content.classList.remove("active"));

  const targetBtn = event ? event.target : document.querySelector(`.tab-btn[onclick*='${tabName}']`);
  if (targetBtn) targetBtn.classList.add("active");

  const targetTab = document.getElementById(`tab-${tabName}`);
  if (targetTab) targetTab.classList.add("active");

  if (tabName === "dashboard") loadDashboard();
  if (tabName === "network") { loadKillswitchStatus(); loadWhitelist(); }
  if (tabName === "audit") loadOperationAudit();
}

// Data Initialization
function initData() {
  loadKillswitchStatus();
  loadDashboard();
  loadWhitelist();
  loadOperationAudit();
}

// Killswitch & Header Status
async function loadKillswitchStatus() {
  try {
    const data = await apiCall("/api/killswitch");
    currentKillswitchStatus = data.status;
    const isBlocked = data.is_blocked;

    const badge = document.getElementById("statusBadge");
    const statusDot = document.getElementById("statusDot");
    const statusText = document.getElementById("statusText");
    const desc = document.getElementById("killswitchDesc");
    const mainBtn = document.getElementById("mainKillswitchBtn");
    const quickBtn = document.getElementById("quickKillswitchBtn");
    const lastUpdated = document.getElementById("killswitchLastUpdated");

    if (isBlocked) {
      badge.className = "badge badge-blocked";
      statusDot.innerText = "🔴";
      statusText.innerText = "ALL BLOCKED";
      desc.innerText = "現在の状態: 全通信緊急遮断中 (ALL BLOCKED)";
      desc.style.color = "#f85149";
      mainBtn.className = "btn btn-success";
      mainBtn.innerHTML = "🟢 遮断解除 (UNBLOCK)";
      quickBtn.className = "btn btn-success";
      quickBtn.innerHTML = "🟢 遮断解除";
    } else {
      badge.className = "badge badge-online";
      statusDot.innerText = "🟢";
      statusText.innerText = "ONLINE";
      desc.innerText = "現在の状態: 全通信許可中 (ONLINE)";
      desc.style.color = "#3fb950";
      mainBtn.className = "btn btn-danger";
      mainBtn.innerHTML = "🔴 緊急全通信遮断";
      quickBtn.className = "btn btn-danger";
      quickBtn.innerHTML = "🔴 全遮断 (Killswitch)";
    }

    if (data.last_updated) {
      lastUpdated.innerText = `最終更新: ${new Date(data.last_updated).toLocaleString("ja-JP")}`;
    }
  } catch (err) {
    console.error("Killswitch status load failed:", err);
  }
}

async function toggleKillswitch() {
  const isBlocking = currentKillswitchStatus === "online";
  const actionText = isBlocking ? "すべての通信を緊急遮断しますか？" : "通信遮断を解除して通常運用に戻しますか？";
  if (!confirm(actionText)) return;

  const endpoint = isBlocking ? "/api/killswitch/block" : "/api/killswitch/unblock";
  try {
    const res = await apiCall(endpoint, { method: "POST" });
    showNotification(res.message, "success");
    await loadKillswitchStatus();
    loadDashboard();
  } catch (err) {
    showNotification(`エラー: ${err.message}`, "error");
  }
}

// Dashboard
async function loadDashboard() {
  try {
    const data = await apiCall("/api/status");
    const summary = data.summary || {};
    const total = summary.total_requests ?? 0;
    const allowed = summary.allowed_requests ?? summary.allowed ?? 0;
    const denied = summary.denied_requests ?? summary.denied ?? 0;
    const rate = summary.deny_rate_percent ?? summary.block_rate_pct ?? 0;

    document.getElementById("statTotalRequests").innerText = total.toLocaleString();
    document.getElementById("statAllowedRequests").innerText = allowed.toLocaleString();
    document.getElementById("statDeniedRequests").innerText = denied.toLocaleString();
    document.getElementById("statBlockRate").innerText = `${rate}%`;

    // Render Recent Denied
    const deniedTbody = document.getElementById("recentDeniedTable");
    const recentDenied = data.recent_denials || data.recent_denied || [];
    if (recentDenied.length === 0) {
      deniedTbody.innerHTML = `<tr><td colspan="5" style="text-align:center; color:var(--text-secondary);">遮断ログはありません</td></tr>`;
    } else {
      deniedTbody.innerHTML = recentDenied.slice(0, 10).map(item => {
        const dom = item.domain || "";
        const isActionable = dom && dom !== "-" && !dom.includes(" ");
        return `
        <tr>
          <td>${item.time ? new Date(item.time).toLocaleTimeString("ja-JP") : "-"}</td>
          <td style="color:#f85149; font-weight:600;">${dom || "-"}</td>
          <td><code>${item.method || "-"}</code></td>
          <td>${item.client || item.url || "-"}</td>
          <td>
            ${isActionable ? `
              <div class="quick-allow-group">
                <button class="btn btn-temp btn-xs" title="15分間一時許可" onclick="quickAllowDomain('${dom}', 15)">⏳ 15分</button>
                <button class="btn btn-temp btn-xs" title="1時間一時許可" onclick="quickAllowDomain('${dom}', 60)">⏳ 1時間</button>
                <button class="btn btn-secondary btn-xs" title="恒久追加" onclick="quickAllowDomain('${dom}', 0)">➕ 恒久</button>
              </div>
            ` : '-'}
          </td>
        </tr>
      `}).join("");
    }

    // Render Top Domains
    const domainsTbody = document.getElementById("topDomainsTable");
    const domains = data.top_domains || data.domains || [];
    if (domains.length === 0) {
      domainsTbody.innerHTML = `<tr><td colspan="4" style="text-align:center; color:var(--text-secondary);">データはありません</td></tr>`;
    } else {
      domainsTbody.innerHTML = domains.slice(0, 10).map(d => `
        <tr>
          <td><b>${d.domain}</b></td>
          <td>${(d.count ?? d.total ?? 0).toLocaleString()}</td>
          <td style="color:#3fb950;">${d.allowed !== undefined ? d.allowed.toLocaleString() : "-"}</td>
          <td style="color:#f85149;">${d.denied !== undefined ? d.denied.toLocaleString() : "-"}</td>
        </tr>
      `).join("");
    }
  } catch (err) {
    console.error("Dashboard load failed:", err);
  }
}

// Quick Allow Domain from Denied Log
async function quickAllowDomain(domain, minutes) {
  const isPermanent = minutes === 0;
  const promptText = isPermanent
    ? `ドメイン '${domain}' をホワイトリストに恒久追加しますか？`
    : `ドメイン '${domain}' を ${minutes} 分間、一時的にホワイトリストに追加しますか？`;

  if (!confirm(promptText)) return;

  try {
    let res;
    if (isPermanent) {
      res = await apiCall("/api/whitelist", {
        method: "POST",
        body: JSON.stringify({ domain })
      });
    } else {
      res = await apiCall("/api/whitelist/temporary", {
        method: "POST",
        body: JSON.stringify({ domain, duration_minutes: minutes })
      });
    }

    showNotification(res.message, "success");
    loadWhitelist();
    loadDashboard();
  } catch (err) {
    showNotification(`エラー: ${err.message}`, "error");
  }
}

// Whitelist Management
async function loadWhitelist() {
  try {
    const data = await apiCall("/api/whitelist");
    const tbody = document.getElementById("whitelistTable");
    const domains = data.domains || [];

    if (domains.length === 0) {
      tbody.innerHTML = `<tr><td colspan="3" style="text-align:center; color:var(--text-secondary);">ホワイトリストにドメインがありません</td></tr>`;
      return;
    }

    tbody.innerHTML = domains.map(d => {
      let badgeHtml = "";
      if (d.is_temporary && d.remaining_seconds !== null) {
        const minsLeft = Math.ceil(d.remaining_seconds / 60);
        badgeHtml = `<span class="badge badge-temp" title="期限: ${new Date(d.expires_at).toLocaleTimeString('ja-JP')}">⏳ 残り ${minsLeft}分</span>`;
      }

      return `
      <tr>
        <td>
          <button class="btn ${d.enabled ? 'btn-success' : 'btn-secondary'}" onclick="toggleDomain('${d.domain}', ${!d.enabled})">
            ${d.enabled ? '🟢 有効' : '⚪ 無効'}
          </button>
        </td>
        <td style="${!d.enabled ? 'text-decoration:line-through; color:var(--text-secondary);' : 'font-weight:600;'}">
          ${d.domain} ${badgeHtml}
        </td>
        <td>
          <button class="btn btn-danger" onclick="deleteDomain('${d.domain}')">🗑️ 削除</button>
        </td>
      </tr>
    `}).join("");
  } catch (err) {
    console.error("Whitelist load failed:", err);
  }
}

async function addDomain() {
  const input = document.getElementById("newDomainInput");
  const domain = input.value.trim();
  if (!domain) return;

  try {
    const res = await apiCall("/api/whitelist", {
      method: "POST",
      body: JSON.stringify({ domain })
    });
    showNotification(res.message, "success");
    input.value = "";
    loadWhitelist();
  } catch (err) {
    showNotification(`エラー: ${err.message}`, "error");
  }
}

async function toggleDomain(domain, enabled) {
  try {
    const res = await apiCall(`/api/whitelist/${encodeURIComponent(domain)}`, {
      method: "PATCH",
      body: JSON.stringify({ enabled })
    });
    showNotification(res.message, "success");
    loadWhitelist();
  } catch (err) {
    showNotification(`エラー: ${err.message}`, "error");
  }
}

async function deleteDomain(domain) {
  if (!confirm(`ドメイン '${domain}' をホワイトリストから削除しますか？`)) return;

  try {
    const res = await apiCall(`/api/whitelist/${encodeURIComponent(domain)}`, {
      method: "DELETE"
    });
    showNotification(res.message, "success");
    loadWhitelist();
  } catch (err) {
    showNotification(`エラー: ${err.message}`, "error");
  }
}

async function reloadSquidConfig() {
  try {
    const res = await apiCall("/api/whitelist/reload", { method: "POST" });
    showNotification(res.message, res.squid_reloaded ? "success" : "error");
  } catch (err) {
    showNotification(`エラー: ${err.message}`, "error");
  }
}

// Operation Audit
async function loadOperationAudit() {
  try {
    const data = await apiCall("/api/audit/operations");
    const tbody = document.getElementById("auditLogsTable");
    const ops = data.operations || [];

    if (ops.length === 0) {
      tbody.innerHTML = `<tr><td colspan="4" style="text-align:center; color:var(--text-secondary);">操作履歴はありません</td></tr>`;
      return;
    }

    tbody.innerHTML = ops.map(op => `
      <tr>
        <td>${op.time ? new Date(op.time).toLocaleString("ja-JP") : "-"}</td>
        <td><code>${op.action || "-"}</code></td>
        <td>${op.source_ip || "-"}</td>
        <td>${op.details || "-"}</td>
      </tr>
    `).join("");
  } catch (err) {
    console.error("Operation audit load failed:", err);
  }
}

// Auto refresh every 30 seconds
setInterval(() => {
  if (isAuthenticated || !isAuthEnabled) {
    loadKillswitchStatus();
    if (document.getElementById("tab-dashboard").classList.contains("active")) {
      loadDashboard();
    }
  }
}, 30000);

// Initialize on page load
document.addEventListener("DOMContentLoaded", () => {
  const dozzle = document.getElementById("dozzleLink");
  if (dozzle) {
    dozzle.href = '//' + window.location.hostname + ':8080/';
  }
  checkAuth();
});
