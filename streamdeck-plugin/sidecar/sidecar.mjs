// Stream Deck claude-monitor sidecar — MQTT subscriber that runs OUTSIDE
// the SD plugin sandbox.
//
// Why this exists:
//   The SD plugin sandbox has a regression in v7.4.x: any outgoing TCP
//   socket (including idle ones) opened from the plugin Node process
//   pegs ~20% of one CPU core on the plugin and ~66% on StreamDeck.exe.
//   See streamdeck-plugin/tests/cpu-ablation-log.md (T0..T8). Same MQTT
//   workload run as a plain Node process outside the sandbox burns 0%.
//
// Architecture:
//   This sidecar holds the MQTT connection. It maintains the same cache
//   the old in-process MqttHandler did and writes a snapshot to
//   %LOCALAPPDATA%\claude-monitor\state.json after every change. The SD
//   plugin polls that file (StateReader) instead of opening its own
//   socket.
//
// State file shape (version 1):
//   {
//     "version": 1,
//     "updatedAt": "ISO-8601",
//     "rebuildId": <int, increments after each MQTT (re)connect rebuild>,
//     "projects": { "<project>": "<state>" },
//     "sysStats": { "temp": number, "ram": number } | null,
//     "winStats": { "temp": number, "freq": number, "ram": number } | null
//   }
//
// rebuildId:
//   The plugin tracks rebuildId. When it changes, plugin treats the new
//   projects map as a full rebuild (clear assignments and re-apply).
//   When it does not change, plugin diffs new vs last and applies
//   incremental assignProject / removeProject calls.
//
// Atomic write:
//   We write to state.json.tmp and rename to state.json. fs.renameSync on
//   Windows is atomic when source and target are on the same volume, so
//   a polling reader never observes a half-written file.

import * as net from "node:net";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import mqttCon from "mqtt-connection";

const BROKER = "192.168.88.10";
const PORT = 1883;
const RECONNECT_MS = 5000;
const REBUILD_DEBOUNCE_MS = 300;
const REBUILD_FALLBACK_MS = 1000;
const PING_MS = 50_000;
const HEARTBEAT_MS = 30_000;

const STATE_DIR = path.join(
  process.env.LOCALAPPDATA || os.homedir(),
  "claude-monitor",
);
const STATE_FILE = path.join(STATE_DIR, "state.json");
const TMP_FILE = STATE_FILE + ".tmp";

fs.mkdirSync(STATE_DIR, { recursive: true });

// Cache state (mirrors MqttHandler internals)
const projects = new Map();
let sysStats = null;
let winStats = null;
let rebuildId = 0;
let rebuilding = false;
let rebuildTimer = null;
let lastSysRaw = "";
let lastWinRaw = "";

// Connection state
let socket = null;
let conn = null;
let pingTimer = null;
let reconnectTimer = null;
let stopped = false;

function writeSnapshot() {
  if (rebuilding) return;
  const snapshot = {
    version: 1,
    updatedAt: new Date().toISOString(),
    rebuildId,
    projects: Object.fromEntries(projects),
    sysStats,
    winStats,
  };
  try {
    fs.writeFileSync(TMP_FILE, JSON.stringify(snapshot), "utf8");
    fs.renameSync(TMP_FILE, STATE_FILE);
  } catch (err) {
    console.error(`[sidecar] write failed: ${err.message}`);
  }
}

function startRebuild() {
  rebuilding = true;
  projects.clear();
  if (rebuildTimer) clearTimeout(rebuildTimer);
  rebuildTimer = setTimeout(finishRebuild, REBUILD_FALLBACK_MS);
}

function finishRebuild() {
  rebuilding = false;
  rebuildTimer = null;
  rebuildId++;
  console.log(
    `[sidecar] rebuild ${rebuildId} complete: ${projects.size} projects`,
  );
  writeSnapshot();
}

function debounceRebuild() {
  if (!rebuilding) return;
  if (rebuildTimer) clearTimeout(rebuildTimer);
  rebuildTimer = setTimeout(finishRebuild, REBUILD_DEBOUNCE_MS);
}

function handlePublish(packet) {
  const topic = packet.topic;
  const payload = packet.payload;

  if (topic === "system/stats") {
    const raw = payload.toString();
    if (raw === lastSysRaw) return;
    lastSysRaw = raw;
    try {
      const data = JSON.parse(raw);
      sysStats = { temp: data.temp ?? 0, ram: data.ram ?? 0 };
      writeSnapshot();
    } catch {
      // ignore malformed
    }
    return;
  }

  if (topic === "system/stats/win") {
    const raw = payload.toString();
    if (raw === lastWinRaw) return;
    lastWinRaw = raw;
    try {
      const data = JSON.parse(raw);
      winStats = {
        temp: data.temp ?? 0,
        freq: data.freq ?? 0,
        ram: data.ram ?? 0,
      };
      writeSnapshot();
    } catch {
      // ignore malformed
    }
    return;
  }

  // claude/led/<project>
  const parts = topic.split("/");
  if (parts.length !== 3) return;
  const project = parts[2];

  if (!payload || payload.length === 0) {
    if (!projects.has(project)) return;
    projects.delete(project);
    if (rebuilding) {
      debounceRebuild();
    } else {
      writeSnapshot();
    }
    return;
  }

  let state;
  try {
    const data = JSON.parse(payload.toString());
    state = (data.state || "").toLowerCase();
  } catch {
    return;
  }

  const prev = projects.get(project);
  if (prev === state && !rebuilding) return;
  projects.set(project, state);

  if (rebuilding) {
    debounceRebuild();
  } else {
    writeSnapshot();
  }
}

function openSocket() {
  if (stopped) return;
  console.log(`[sidecar] connecting to mqtt://${BROKER}:${PORT}`);
  const sock = net.createConnection({ host: BROKER, port: PORT });
  socket = sock;
  const c = mqttCon(sock);
  conn = c;

  sock.on("connect", () => {
    c.connect({
      protocolId: "MQTT",
      protocolVersion: 4,
      clientId: `sidecar-claude-monitor-${Math.floor(Math.random() * 1e6)}`,
      clean: true,
      keepalive: 60,
    });
  });

  c.on("connack", (packet) => {
    if (packet.returnCode !== 0) {
      console.error(`[sidecar] connack failed rc=${packet.returnCode}`);
      scheduleReconnect();
      return;
    }
    console.log("[sidecar] connected, rebuilding");
    startRebuild();
    c.subscribe({
      messageId: 1,
      subscriptions: [
        { topic: "claude/led/+", qos: 0 },
        { topic: "system/stats", qos: 0 },
        { topic: "system/stats/win", qos: 0 },
      ],
    });
  });

  c.on("publish", handlePublish);
  c.on("pingresp", () => {});
  c.on("error", (err) => console.error(`[sidecar] codec error: ${err.message}`));

  sock.on("error", (err) => console.error(`[sidecar] socket error: ${err.message}`));
  sock.on("close", () => scheduleReconnect());

  if (pingTimer) clearInterval(pingTimer);
  pingTimer = setInterval(() => {
    if (conn === c) {
      try {
        c.pingreq();
      } catch {
        // socket closed
      }
    }
  }, PING_MS);
  sock.on("close", () => clearInterval(pingTimer));
}

function scheduleReconnect() {
  if (stopped) return;
  if (reconnectTimer) return;
  if (conn) {
    try {
      conn.destroy();
    } catch {}
    conn = null;
  }
  if (socket) {
    try {
      socket.destroy();
    } catch {}
    socket = null;
  }
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    openSocket();
  }, RECONNECT_MS);
}

function shutdown() {
  stopped = true;
  if (rebuildTimer) clearTimeout(rebuildTimer);
  if (reconnectTimer) clearTimeout(reconnectTimer);
  if (pingTimer) clearInterval(pingTimer);
  if (conn) try { conn.destroy(); } catch {}
  if (socket) try { socket.destroy(); } catch {}
  process.exit(0);
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

console.log(`[sidecar] state file: ${STATE_FILE}`);
openSocket();

setInterval(() => {
  console.log(
    `[sidecar] alive: rebuild=${rebuildId} projects=${projects.size} sys=${sysStats ? "ok" : "none"} win=${winStats ? "ok" : "none"}`,
  );
  // Bump state.json updatedAt so the plugin can distinguish "sidecar idle
  // but alive" from "sidecar dead". Plugin's StateReader treats snapshots
  // older than 2× HEARTBEAT_MS as stale.
  writeSnapshot();
}, HEARTBEAT_MS);
