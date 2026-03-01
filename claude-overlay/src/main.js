const { invoke } = window.__TAURI__.core;

const BLINK_STATES = new Set(["WAITING", "IDLE"]);
const app = document.getElementById("app");

function render(projects) {
  if (!projects.length) {
    app.innerHTML = '<p class="empty">No active sessions</p>';
    return;
  }

  app.innerHTML = projects
    .map((p) => {
      const s = p.state.toLowerCase();
      const blink = BLINK_STATES.has(p.state) ? " blink" : "";
      return `
      <div class="card border-${s}${blink}">
        <span class="dot dot-${s}"></span>
        <div class="info">
          <div class="name">${escapeHtml(p.name)}</div>
          <div class="state state-${s}">${escapeHtml(p.state)}</div>
        </div>
      </div>`;
    })
    .join("");
}

function escapeHtml(s) {
  const d = document.createElement("div");
  d.textContent = s;
  return d.innerHTML;
}

async function poll() {
  try {
    const projects = await invoke("get_projects");
    render(projects);
  } catch (e) {
    console.error("get_projects failed:", e);
  }
}

// Initial fetch + 1-second polling
poll();
setInterval(poll, 1000);
