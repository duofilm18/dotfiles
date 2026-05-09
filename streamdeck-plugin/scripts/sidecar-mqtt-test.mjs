// Axis 8 ablation: full MQTT subscribe pipeline running OUTSIDE the
// Stream Deck plugin sandbox. Mirrors mqtt-handler.ts contract — same
// mqtt-connection codec, same broker, same 3 topics, same 50s PINGREQ.
//
// Bundled by rollup.sidecar.config.mjs to /mnt/c/temp/axis8/sidecar.js
// so it runs as a self-contained CJS file via the Stream Deck bundled
// node.exe (same Node version as the plugin sandbox).
//
// stdout markers consumed by C:\temp\sd-cpu-axis8.ps1:
//   "subscribed" — sidecar is ready, harness can begin idle window

import * as net from "node:net";
import mqttCon from "mqtt-connection";

const BROKER = "192.168.88.10";
const PORT = 1883;
const CLIENT_ID = `axis8-sidecar-${Math.floor(Math.random() * 1e6)}`;

let pubCount = 0;

const sock = net.createConnection({ host: BROKER, port: PORT });
const conn = mqttCon(sock);

sock.on("connect", () => {
  console.log(`tcp connected to ${BROKER}:${PORT}`);
  conn.connect({
    protocolId: "MQTT",
    protocolVersion: 4,
    clientId: CLIENT_ID,
    clean: true,
    keepalive: 60,
  });
});

conn.on("connack", (packet) => {
  if (packet.returnCode !== 0) {
    console.error(`connack failed rc=${packet.returnCode}`);
    process.exit(1);
  }
  console.log("mqtt connack ok");
  conn.subscribe({
    messageId: 1,
    subscriptions: [
      { topic: "claude/led/+", qos: 0 },
      { topic: "system/stats", qos: 0 },
      { topic: "system/stats/win", qos: 0 },
    ],
  });
  console.log("subscribed");
});

conn.on("publish", () => {
  pubCount++;
});
conn.on("pingresp", () => {});
conn.on("error", (err) => {
  console.error(`codec error: ${err.message}`);
});

sock.on("error", (err) => {
  console.error(`socket error: ${err.message}`);
});
sock.on("close", () => {
  console.error("socket closed");
  process.exit(2);
});

setInterval(() => {
  try {
    conn.pingreq();
  } catch {}
}, 50_000);

setInterval(() => {
  console.log(`pub count: ${pubCount}`);
}, 30_000);
