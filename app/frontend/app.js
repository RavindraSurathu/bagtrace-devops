// BagTrace dashboard: talks only to /api and /health, which Nginx proxies to the app tier.
const STATUSES = ["CHECKED_IN", "SCREENED", "LOADED", "OFFLOADED", "ARRIVED", "DELETED"];
const $ = (id) => document.getElementById(id);
let currentFlight = "";

const esc = (v) => String(v ?? "—").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const label = (s) => s.replace("_", " ").toLowerCase().replace(/^\w/, (c) => c.toUpperCase());

async function api(path, options = {}) {
  const res = await fetch(path, options);
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || `Request failed (${res.status})`);
  return body;
}

async function checkHealth() {
  const el = $("health");
  try {
    const h = await api("/health");
    el.className = "health up";
    $("healthText").textContent = `API up · database ${h.database}`;
  } catch {
    el.className = "health down";
    $("healthText").textContent = "API or database unreachable";
  }
}

async function loadStats() {
  try {
    const s = await api("/api/stats");
    const tiles = [["Bags", s.total], ["Flights", s.flights], ...STATUSES.map((k) => [label(k), s.by_status[k] ?? 0])];
    $("stats").innerHTML = tiles.map(([k, v]) => `<div class="stat"><b>${v}</b><span>${esc(k)}</span></div>`).join("");
  } catch { $("stats").innerHTML = ""; }
}

async function loadBags() {
  const tbody = $("bags");
  try {
    const q = currentFlight ? `?flight=${encodeURIComponent(currentFlight)}` : "";
    const { bags } = await api(`/api/bags${q}`);
    if (!bags.length) {
      tbody.innerHTML = `<tr><td colspan="7" class="empty">No bags${currentFlight ? " for " + esc(currentFlight) : ""} yet. Send a BSM to add one.</td></tr>`;
      return;
    }
    tbody.innerHTML = bags.map((b) => `
      <tr>
        <td class="tag">${esc(b.tag)}</td>
        <td>${esc(b.flight)} <small style="color:var(--muted)">${esc(b.flight_date)}</small></td>
        <td>${esc(b.origin)} → ${esc(b.destination)}</td>
        <td>${esc(b.passenger)}</td>
        <td>${esc(b.weight_kg)}</td>
        <td><span class="pill s-${esc(b.status)}">${esc(label(b.status))}</span></td>
        <td><label class="sr" for="st-${esc(b.tag)}">Change status</label>
          <select id="st-${esc(b.tag)}" data-tag="${esc(b.tag)}">
            ${STATUSES.map((s) => `<option value="${s}" ${s === b.status ? "selected" : ""}>${label(s)}</option>`).join("")}
          </select></td>
      </tr>`).join("");
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="7" class="empty">${esc(e.message)}</td></tr>`;
  }
}

const refresh = () => Promise.all([loadStats(), loadBags()]);

$("bags").addEventListener("change", async (e) => {
  const tag = e.target.dataset.tag;
  if (!tag) return;
  try {
    await api(`/api/bags/${tag}`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ status: e.target.value }) });
  } finally { refresh(); }
});

$("filterForm").addEventListener("submit", (e) => { e.preventDefault(); currentFlight = $("flight").value.trim().toUpperCase(); loadBags(); });
$("clearFilter").addEventListener("click", () => { $("flight").value = ""; currentFlight = ""; loadBags(); });

$("bsmForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const out = $("bsmResult");
  try {
    const r = await api("/api/bsm", { method: "POST", headers: { "Content-Type": "text/plain" }, body: $("bsm").value });
    const m = r.message;
    out.innerHTML = `<div class="ok">${m.action === "DEL" ? "Deleted" : "Accepted"} ${m.tags.length} bag(s) on ${esc(m.flight)} ${esc(m.airport)} → ${esc(m.destination)}</div>` +
      (m.warnings.length ? `<ol>${m.warnings.map((w) => `<li>${esc(w)}</li>`).join("")}</ol>` : "");
    refresh();
  } catch (err) { out.innerHTML = `<div class="err">${esc(err.message)}</div>`; }
});

$("trackForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const out = $("trackResult"), tag = $("tag").value.trim();
  try {
    const b = await api(`/api/bags/${encodeURIComponent(tag)}`);
    out.innerHTML = `<div><span class="pill s-${esc(b.status)}">${esc(label(b.status))}</span> ${esc(b.flight)} ${esc(b.origin)} → ${esc(b.destination)} · ${esc(b.passenger)}</div>
      <ol>${b.events.map((ev) => `<li>${esc(ev.created_at)} · ${esc(ev.event)}</li>`).join("")}</ol>`;
  } catch (err) { out.innerHTML = `<div class="err">${esc(err.message)}</div>`; }
});

checkHealth();
refresh();
setInterval(checkHealth, 15000);
