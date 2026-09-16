let currentKillswitchStatus = "online";
let isAuthEnabled = false;
let isAuthenticated = false;
let currentLang = localStorage.getItem("app_lang") || "ja";

const translations = {
  ja: {
    langBtnText: "🌐 English",
    appTitle: "🎛️ Goose-in-the-Box コントロールパネル",
    navReport: "📊 監査レポート",
    navVnc: "🖥️ noVNC 操作",
    navDozzle: "📜 Dozzle ログ",
    logoutBtn: "🚪 ログアウト",
    tabBtnDashboard: "📊 監査ダッシュボード",
    tabBtnNetwork: "🔒 通信制御 (キルスイッチ・WL)",
    tabBtnAudit: "📋 操作ログ",
    lblTotalReq: "総リクエスト数",
    lblAllowedReq: "許可リクエスト (ALLOWED)",
    lblDeniedReq: "遮断リクエスト (DENIED)",
    lblBlockRate: "遮断率 (Block Rate)",
    titleRecentDenied: "🚨 直近の遮断 (DENIED) ログ",
    titleTopDomains: "🌐 ドメイン別アクセス Top 10",
    titleKillswitch: "🔴 緊急キルスイッチ (Killswitch)",
    titleWhitelist: "📋 ドメインホワイトリスト管理 (whitelist.txt)",
    titleAudit: "📋 コントロールパネル操作監査ログ (control-panel-audit.json)",
    btnRefreshText: "🔄 更新",
    btnReloadText: "🔄 再読み込み",
    btnReloadSquid: "🔄 Squid 再設定 (reconfigure)",
    btnAddDomain: "➕ 追加",
    placeholderAddDomain: "許可ドメインを追加 (例: .openai.com, github.com)",
    loadingText: "読み込み中...",
    noDeniedLogs: "遮断ログはありません",
    noData: "データはありません",
    noWhitelist: "ホワイトリストにドメインがありません",
    noAuditLogs: "操作履歴はありません",
    thDeniedTime: "時刻",
    thDeniedDomain: "宛先ドメイン",
    thDeniedMethod: "メソッド",
    thDeniedClient: "クライアント",
    thDomDomain: "ドメイン",
    thDomTotal: "総数",
    thDomAllowed: "許可",
    thDomDenied: "遮断",
    thWlStatus: "状態",
    thWlDomain: "ドメイン",
    thWlAction: "操作",
    thAuditTime: "日時",
    thAuditAction: "アクション",
    thAuditIp: "クライアント IP",
    thAuditDetails: "詳細",
    statusAllBlocked: "ALL BLOCKED",
    statusOnline: "ONLINE",
    descBlocked: "現在の状態: 全通信緊急遮断中 (ALL BLOCKED)",
    descOnline: "現在の状態: 全通信許可中 (ONLINE)",
    btnUnblockMain: "🟢 遮断解除 (UNBLOCK)",
    btnUnblockQuick: "🟢 遮断解除",
    btnBlockMain: "🔴 緊急全通信遮断",
    btnBlockQuick: "🔴 全遮断 (Killswitch)",
    lastUpdatedPrefix: "最終更新",
    btnEnabled: "🟢 有効",
    btnDisabled: "⚪ 無効",
    btnDelete: "🗑️ 削除",
    confirmBlock: "すべての通信を緊急遮断しますか？",
    confirmUnblock: "通信遮断を解除して通常運用に戻しますか？",
    confirmDeleteDomain: (domain) => `ドメイン '${domain}' をホワイトリストから削除しますか？`,
    loginTitle: "🔐 コントロールパネル ログイン",
    placeholderPassword: "パスワードを入力",
    btnLogin: "ログイン",
    errAuthRequired: "認証が必要です",
    errOccurred: "エラーが発生しました",
    errPrefix: "エラー"
  },
  en: {
    langBtnText: "🌐 日本語",
    appTitle: "🎛️ Goose-in-the-Box Control Panel",
    navReport: "📊 Audit Report",
    navVnc: "🖥️ noVNC Desktop",
    navDozzle: "📜 Dozzle Logs",
    logoutBtn: "🚪 Logout",
    tabBtnDashboard: "📊 Audit Dashboard",
    tabBtnNetwork: "🔒 Traffic Control (Killswitch/WL)",
    tabBtnAudit: "📋 Operation Audit",
    lblTotalReq: "Total Requests",
    lblAllowedReq: "Allowed Requests (ALLOWED)",
    lblDeniedReq: "Denied Requests (DENIED)",
    lblBlockRate: "Block Rate",
    titleRecentDenied: "🚨 Recent Denied Requests",
    titleTopDomains: "🌐 Top 10 Access Domains",
    titleKillswitch: "🔴 Emergency Killswitch",
    titleWhitelist: "📋 Whitelist Management (whitelist.txt)",
    titleAudit: "📋 Control Panel Operation Audit Logs",
    btnRefreshText: "🔄 Refresh",
    btnReloadText: "🔄 Reload",
    btnReloadSquid: "🔄 Squid Reconfigure",
    btnAddDomain: "➕ Add",
    placeholderAddDomain: "Add domain (e.g. .openai.com, github.com)",
    loadingText: "Loading...",
    noDeniedLogs: "No denied logs found.",
    noData: "No data available.",
    noWhitelist: "No domains in whitelist.",
    noAuditLogs: "No operation audit history found.",
    thDeniedTime: "Time",
    thDeniedDomain: "Destination Domain",
    thDeniedMethod: "Method",
    thDeniedClient: "Client",
    thDomDomain: "Domain",
    thDomTotal: "Total",
    thDomAllowed: "Allowed",
    thDomDenied: "Denied",
    thWlStatus: "Status",
    thWlDomain: "Domain",
    thWlAction: "Action",
    thAuditTime: "Date/Time",
    thAuditAction: "Action",
    thAuditIp: "Client IP",
    thAuditDetails: "Details",
    statusAllBlocked: "ALL BLOCKED",
    statusOnline: "ONLINE",
    descBlocked: "Current Status: All Traffic Blocked (ALL BLOCKED)",
    descOnline: "Current Status: All Traffic Allowed (ONLINE)",
    btnUnblockMain: "🟢 Unblock All Traffic",
    btnUnblockQuick: "🟢 Unblock",
    btnBlockMain: "🔴 Emergency Block All",
    btnBlockQuick: "🔴 Killswitch",
    lastUpdatedPrefix: "Last Updated",
    btnEnabled: "🟢 Enabled",
    btnDisabled: "⚪ Disabled",
    btnDelete: "🗑️ Delete",
    confirmBlock: "Are you sure you want to block all network traffic?",
    confirmUnblock: "Are you sure you want to unblock traffic and resume normal operation?",
    confirmDeleteDomain: (domain) => `Are you sure you want to delete '${domain}' from the whitelist?`,
    loginTitle: "🔐 Control Panel Login",
    placeholderPassword: "Enter password",
    btnLogin: "Login",
    errAuthRequired: "Authentication required",
    errOccurred: "An error occurred",
    errPrefix: "Error"
  }
};

function t(key, ...args) {
  const dict = translations[currentLang] || translations.ja;
  const val = dict[key] || translations.ja[key] || key;
  if (typeof val === "function") {
    return val(...args);
  }
  return val;
}

function setLanguage(lang) {
  currentLang = lang;
  localStorage.setItem("app_lang", lang);
  document.documentElement.lang = lang;
  updateStaticLabels();
  initData();
}

function toggleLanguage() {
  setLanguage(currentLang === "ja" ? "en" : "ja");
}

function updateStaticLabels() {
  const el = (id) => document.getElementById(id);

  if (el("langToggleBtn")) el("langToggleBtn").innerText = t("langBtnText");
  if (el("appTitle")) el("appTitle").innerText = t("appTitle");
  if (el("navReport")) el("navReport").innerText = t("navReport");
  if (el("navVnc")) el("navVnc").innerText = t("navVnc");
  if (el("navDozzle")) el("navDozzle").innerText = t("navDozzle");
  if (el("logoutBtn")) el("logoutBtn").innerText = t("logoutBtn");

  if (el("tabBtnDashboard")) el("tabBtnDashboard").innerText = t("tabBtnDashboard");
  if (el("tabBtnNetwork")) el("tabBtnNetwork").innerText = t("tabBtnNetwork");
  if (el("tabBtnAudit")) el("tabBtnAudit").innerText = t("tabBtnAudit");

  if (el("lblTotalReq")) el("lblTotalReq").innerText = t("lblTotalReq");
  if (el("lblAllowedReq")) el("lblAllowedReq").innerText = t("lblAllowedReq");
  if (el("lblDeniedReq")) el("lblDeniedReq").innerText = t("lblDeniedReq");
  if (el("lblBlockRate")) el("lblBlockRate").innerText = t("lblBlockRate");

  if (el("titleRecentDenied")) el("titleRecentDenied").innerHTML = `${t("titleRecentDenied")}`;
  if (el("titleTopDomains")) el("titleTopDomains").innerHTML = `${t("titleTopDomains")}`;
  if (el("titleKillswitch")) el("titleKillswitch").innerHTML = `${t("titleKillswitch")}`;
  if (el("titleWhitelist")) el("titleWhitelist").innerHTML = `${t("titleWhitelist")}`;
  if (el("titleAudit")) el("titleAudit").innerHTML = `${t("titleAudit")}`;

  document.querySelectorAll(".btnRefreshText").forEach(e => e.innerText = t("btnRefreshText"));
  document.querySelectorAll(".btnReloadText").forEach(e => e.innerText = t("btnReloadText"));
  document.querySelectorAll(".loadingText").forEach(e => e.innerText = t("loadingText"));

  if (el("btnReloadSquid")) el("btnReloadSquid").innerText = t("btnReloadSquid");
  if (el("btnAddDomain")) el("btnAddDomain").innerText = t("btnAddDomain");
  if (el("newDomainInput")) el("newDomainInput").placeholder = t("placeholderAddDomain");

  if (el("thDeniedTime")) el("thDeniedTime").innerText = t("thDeniedTime");
  if (el("thDeniedDomain")) el("thDeniedDomain").innerText = t("thDeniedDomain");
  if (el("thDeniedMethod")) el("thDeniedMethod").innerText = t("thDeniedMethod");
  if (el("thDeniedClient")) el("thDeniedClient").innerText = t("thDeniedClient");

  if (el("thDomDomain")) el("thDomDomain").innerText = t("thDomDomain");
  if (el("thDomTotal")) el("thDomTotal").innerText = t("thDomTotal");
  if (el("thDomAllowed")) el("thDomAllowed").innerText = t("thDomAllowed");
  if (el("thDomDenied")) el("thDomDenied").innerText = t("thDomDenied");

  if (el("thWlStatus")) el("thWlStatus").innerText = t("thWlStatus");
  if (el("thWlDomain")) el("thWlDomain").innerText = t("thWlDomain");
  if (el("thWlAction")) el("thWlAction").innerText = t("thWlAction");

  if (el("thAuditTime")) el("thAuditTime").innerText = t("thAuditTime");
  if (el("thAuditAction")) el("thAuditAction").innerText = t("thAuditAction");
  if (el("thAuditIp")) el("thAuditIp").innerText = t("thAuditIp");
  if (el("thAuditDetails")) el("thAuditDetails").innerText = t("thAuditDetails");

  if (el("loginModalTitle")) el("loginModalTitle").innerText = t("loginTitle");
  if (el("passwordInput")) el("passwordInput").placeholder = t("placeholderPassword");
  if (el("loginSubmitBtn")) el("loginSubmitBtn").innerText = t("btnLogin");
}

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
      throw new Error(t("errAuthRequired"));
    }
    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.detail || data.message || t("errOccurred"));
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
      statusText.innerText = t("statusAllBlocked");
      desc.innerText = t("descBlocked");
      desc.style.color = "#f85149";
      mainBtn.className = "btn btn-success";
      mainBtn.innerHTML = t("btnUnblockMain");
      quickBtn.className = "btn btn-success";
      quickBtn.innerHTML = t("btnUnblockQuick");
    } else {
      badge.className = "badge badge-online";
      statusDot.innerText = "🟢";
      statusText.innerText = t("statusOnline");
      desc.innerText = t("descOnline");
      desc.style.color = "#3fb950";
      mainBtn.className = "btn btn-danger";
      mainBtn.innerHTML = t("btnBlockMain");
      quickBtn.className = "btn btn-danger";
      quickBtn.innerHTML = t("btnBlockQuick");
    }

    if (data.last_updated) {
      const dateLocale = currentLang === "ja" ? "ja-JP" : "en-US";
      lastUpdated.innerText = `${t("lastUpdatedPrefix")}: ${new Date(data.last_updated).toLocaleString(dateLocale)}`;
    }
  } catch (err) {
    console.error("Killswitch status load failed:", err);
  }
}

async function toggleKillswitch() {
  const isBlocking = currentKillswitchStatus === "online";
  const actionText = isBlocking ? t("confirmBlock") : t("confirmUnblock");
  if (!confirm(actionText)) return;

  const endpoint = isBlocking ? "/api/killswitch/block" : "/api/killswitch/unblock";
  try {
    const res = await apiCall(endpoint, { method: "POST" });
    showNotification(res.message, "success");
    await loadKillswitchStatus();
    loadDashboard();
  } catch (err) {
    showNotification(`${t("errPrefix")}: ${err.message}`, "error");
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

    const dateLocale = currentLang === "ja" ? "ja-JP" : "en-US";

    document.getElementById("statTotalRequests").innerText = total.toLocaleString(dateLocale);
    document.getElementById("statAllowedRequests").innerText = allowed.toLocaleString(dateLocale);
    document.getElementById("statDeniedRequests").innerText = denied.toLocaleString(dateLocale);
    document.getElementById("statBlockRate").innerText = `${rate}%`;

    // Render Recent Denied
    const deniedTbody = document.getElementById("recentDeniedTable");
    const recentDenied = data.recent_denials || data.recent_denied || [];
    if (recentDenied.length === 0) {
      deniedTbody.innerHTML = `<tr><td colspan="4" style="text-align:center; color:var(--text-secondary);">${t("noDeniedLogs")}</td></tr>`;
    } else {
      deniedTbody.innerHTML = recentDenied.slice(0, 10).map(item => `
        <tr>
          <td>${item.time ? new Date(item.time).toLocaleTimeString(dateLocale) : "-"}</td>
          <td style="color:#f85149; font-weight:600;">${item.domain || "-"}</td>
          <td><code>${item.method || "-"}</code></td>
          <td>${item.client || item.url || "-"}</td>
        </tr>
      `).join("");
    }

    // Render Top Domains
    const domainsTbody = document.getElementById("topDomainsTable");
    const domains = data.top_domains || data.domains || [];
    if (domains.length === 0) {
      domainsTbody.innerHTML = `<tr><td colspan="4" style="text-align:center; color:var(--text-secondary);">${t("noData")}</td></tr>`;
    } else {
      domainsTbody.innerHTML = domains.slice(0, 10).map(d => `
        <tr>
          <td><b>${d.domain}</b></td>
          <td>${(d.count ?? d.total ?? 0).toLocaleString(dateLocale)}</td>
          <td style="color:#3fb950;">${d.allowed !== undefined ? d.allowed.toLocaleString(dateLocale) : "-"}</td>
          <td style="color:#f85149;">${d.denied !== undefined ? d.denied.toLocaleString(dateLocale) : "-"}</td>
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
      tbody.innerHTML = `<tr><td colspan="3" style="text-align:center; color:var(--text-secondary);">${t("noWhitelist")}</td></tr>`;
      return;
    }

    tbody.innerHTML = domains.map(d => `
      <tr>
        <td>
          <button class="btn ${d.enabled ? 'btn-success' : 'btn-secondary'}" onclick="toggleDomain('${d.domain}', ${!d.enabled})">
            ${d.enabled ? t('btnEnabled') : t('btnDisabled')}
          </button>
        </td>
        <td style="${!d.enabled ? 'text-decoration:line-through; color:var(--text-secondary);' : 'font-weight:600;'}">
          ${d.domain}
        </td>
        <td>
          <button class="btn btn-danger" onclick="deleteDomain('${d.domain}')">${t('btnDelete')}</button>
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
    showNotification(`${t("errPrefix")}: ${err.message}`, "error");
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
    showNotification(`${t("errPrefix")}: ${err.message}`, "error");
  }
}

async function deleteDomain(domain) {
  if (!confirm(t("confirmDeleteDomain", domain))) return;

  try {
    const res = await apiCall(`/api/whitelist/${encodeURIComponent(domain)}`, {
      method: "DELETE"
    });
    showNotification(res.message, "success");
    loadWhitelist();
  } catch (err) {
    showNotification(`${t("errPrefix")}: ${err.message}`, "error");
  }
}

async function reloadSquidConfig() {
  try {
    const res = await apiCall("/api/whitelist/reload", { method: "POST" });
    showNotification(res.message, res.squid_reloaded ? "success" : "error");
  } catch (err) {
    showNotification(`${t("errPrefix")}: ${err.message}`, "error");
  }
}

// Operation Audit
async function loadOperationAudit() {
  try {
    const data = await apiCall("/api/audit/operations");
    const tbody = document.getElementById("auditLogsTable");
    const ops = data.operations || [];

    if (ops.length === 0) {
      tbody.innerHTML = `<tr><td colspan="4" style="text-align:center; color:var(--text-secondary);">${t("noAuditLogs")}</td></tr>`;
      return;
    }

    const dateLocale = currentLang === "ja" ? "ja-JP" : "en-US";

    tbody.innerHTML = ops.map(op => `
      <tr>
        <td>${op.time ? new Date(op.time).toLocaleString(dateLocale) : "-"}</td>
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
  updateStaticLabels();
  checkAuth();
});
