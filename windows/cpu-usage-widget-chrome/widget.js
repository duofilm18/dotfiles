const openButton = document.getElementById("open-widget");
const openPipButton = document.getElementById("open-pip");
const statusEl = document.getElementById("status");
const widgetTemplate = document.getElementById("widget-template");

let pipWindow = null;
let popupWindow = null;
let refreshTimer = null;

function updateLayout(win) {
  const width = win.innerWidth || 220;
  const height = win.innerHeight || 140;
  const scale = Math.max(0.58, Math.min(1.45, Math.min(width / 220, height / 140)));

  win.document.documentElement.style.setProperty("--scale", scale.toFixed(3));
  win.document.body.classList.toggle("compact", width < 190 || height < 118);
  win.document.body.classList.toggle("ultra", width < 168 || height < 104);
}

function formatRate(bytesPerSecond) {
  if (bytesPerSecond < 1024) {
    return `${Math.round(bytesPerSecond)} B/s`;
  }
  if (bytesPerSecond < 1024 ** 2) {
    return `${(bytesPerSecond / 1024).toFixed(1)} KB/s`;
  }
  if (bytesPerSecond < 1024 ** 3) {
    return `${(bytesPerSecond / 1024 ** 2).toFixed(1)} MB/s`;
  }
  return `${(bytesPerSecond / 1024 ** 3).toFixed(2)} GB/s`;
}

async function fetchStats() {
  const response = await fetch("/api/stats", { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`stats fetch failed: ${response.status}`);
  }
  return response.json();
}

function setStatus(text) {
  statusEl.textContent = text;
}

function updateWidget(win, stats) {
  win.document.getElementById("cpu-value").textContent = `${stats.cpu_pct}%`;
  win.document.getElementById("ram-value").textContent =
    `${stats.ram.used_pct}% ${stats.ram.used_gb.toFixed(1)}G`;
  win.document.getElementById("down-value").textContent = formatRate(stats.network.down_bps);
  win.document.getElementById("up-value").textContent = formatRate(stats.network.up_bps);
  win.document.getElementById("cpu-mini").textContent = `${stats.cpu_pct}%`;
  win.document.getElementById("ram-mini").textContent = `${stats.ram.used_pct}%`;
  win.document.getElementById("down-mini").textContent = formatRate(stats.network.down_bps);
  win.document.getElementById("up-mini").textContent = formatRate(stats.network.up_bps);

  const stamp = new Date(stats.ts).toLocaleTimeString("zh-TW", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
  win.document.getElementById("mini-stamp").textContent = stamp;
}

async function tick() {
  const activeWindow = !popupWindow || popupWindow.closed ? pipWindow : popupWindow;
  if (!activeWindow || activeWindow.closed) {
    return;
  }

  try {
    const stats = await fetchStats();
    updateWidget(activeWindow, stats);
    setStatus("小窗更新中");
  } catch (error) {
    setStatus("資料更新失敗");
  }
}

function stopTicker() {
  if (refreshTimer) {
    clearInterval(refreshTimer);
    refreshTimer = null;
  }
}

function mountWidget(win, bodyClassName) {
  const doc = win.document;
  doc.head.innerHTML = "";

  const styleLink = doc.createElement("link");
  styleLink.rel = "stylesheet";
  styleLink.href = `${location.origin}/widget.css`;
  doc.head.append(styleLink);
  doc.title = "CPU Usage Widget";
  doc.body.innerHTML = "";
  doc.body.className = bodyClassName;
  doc.body.append(widgetTemplate.content.cloneNode(true));
  updateLayout(win);

  win.addEventListener("resize", () => {
    updateLayout(win);
  });
}

function startTicker() {
  stopTicker();
  refreshTimer = window.setInterval(tick, 1000);
}

function wireWindowClose(win, onClose) {
  win.addEventListener("beforeunload", onClose);
  win.addEventListener("pagehide", onClose);
}

function openPopupWidget() {
  popupWindow = window.open(
    "",
    "cpu-usage-widget",
    "popup=yes,width=220,height=140,resizable=yes,scrollbars=no"
  );

  if (!popupWindow) {
    setStatus("Chrome 擋下 popup，請允許此頁面開小窗");
    return;
  }

  mountWidget(popupWindow, "widget-popup");
  wireWindowClose(popupWindow, () => {
    popupWindow = null;
    if (!pipWindow) {
      stopTicker();
    }
    setStatus("小窗已關閉");
  });

  void tick();
  startTicker();
  popupWindow.focus();
  setStatus("可調大小小窗已開啟，可拖動也可縮放");
}

async function openPipWidget() {
  if (!("documentPictureInPicture" in window)) {
    setStatus("這個 Chrome 版本不支援 Document PiP");
    return;
  }

  pipWindow = await window.documentPictureInPicture.requestWindow({
    width: 180,
    height: 112,
  });

  mountWidget(pipWindow, "widget-pip");
  wireWindowClose(pipWindow, () => {
    pipWindow = null;
    if (!popupWindow) {
      stopTicker();
    }
    setStatus("小窗已關閉");
  });

  await tick();
  startTicker();
  setStatus("PiP 小窗已開啟，可拖動");
}

openButton.addEventListener("click", () => {
  openPopupWidget();
});

if (!("documentPictureInPicture" in window)) {
  openPipButton.disabled = true;
} else {
  openPipButton.addEventListener("click", () => {
    void openPipWidget();
  });
}
