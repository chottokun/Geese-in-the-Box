let currentKillswitchStatus = "online";
let isAuthEnabled = false;
let isAuthenticated = false;

// API Helper
async function apiCall(endpoint, options = {}) {
  options.headers = options.headers || {};
  if (!options.headers["Content-Type"] && options.body && typeof options.body === "string") {
    options.headers["Content-Type"] = "application/json";
  }

  try {
    const response = await fetch(endpoint, options);
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
    const summary = data.summary || { total_requests: 0, allowed: 0, denied: 0, block_rate_pct: 0 };

    document.getElementById("statTotalRequests").innerText = summary.total_requests.toLocaleString();
    document.getElementById("statAllowedRequests").innerText = summary.allowed.toLocaleString();
    document.getElementById("statDeniedRequests").innerText = summary.denied.toLocaleString();
    document.getElementById("statBlockRate").innerText = `${summary.block_rate_pct}%`;

    // Render Recent Denied
    const deniedTbody = document.getElementById("recentDeniedTable");
    const recentDenied = data.recent_denied || [];
    if (recentDenied.length === 0) {
      deniedTbody.innerHTML = `<tr><td colspan="4" style="text-align:center; color:var(--text-secondary);">遮断ログはありません</td></tr>`;
    } else {
      deniedTbody.innerHTML = recentDenied.slice(0, 10).map(item => `
        <tr>
          <td>${item.time ? new Date(item.time).toLocaleTimeString("ja-JP") : "-"}</td>
          <td style="color:#f85149; font-weight:600;">${item.domain || "-"}</td>
          <td><code>${item.method || "-"}</code></td>
          <td>${item.client || "-"}</td>
        </tr>
      `).join("");
    }

    // Render Top Domains
    const domainsTbody = document.getElementById("topDomainsTable");
    const domains = data.domains || [];
    if (domains.length === 0) {
      domainsTbody.innerHTML = `<tr><td colspan="4" style="text-align:center; color:var(--text-secondary);">データはありません</td></tr>`;
    } else {
      domainsTbody.innerHTML = domains.slice(0, 10).map(d => `
        <tr>
          <td><b>${d.domain}</b></td>
          <td>${d.total}</td>
          <td style="color:#3fb950;">${d.allowed}</td>
          <td style="color:#f85149;">${d.denied}</td>
        </tr>
      `).join("");
    }
  } catch (err) {
    console.error("Dashboard load failed:", err);
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

    tbody.innerHTML = domains.map(d => `
      <tr>
        <td>
          <button class="btn ${d.enabled ? 'btn-success' : 'btn-secondary'}" onclick="toggleDomain('${d.domain}', ${!d.enabled})">
            ${d.enabled ? '🟢 有効' : '⚪ 無効'}
          </button>
        </td>
        <td style="${!d.enabled ? 'text-decoration:line-through; color:var(--text-secondary);' : 'font-weight:600;'}">
          ${d.domain}
        </td>
        <td>
          <button class="btn btn-danger" onclick="deleteDomain('${d.domain}')">🗑️ 削除</button>
        </td>
      </tr>
    `).join("");
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
  checkAuth();
});
