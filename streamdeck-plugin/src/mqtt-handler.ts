import * as net from "node:net";
import streamDeck from "@elgato/streamdeck";
// mqtt-connection: 純 packet codec，比 mqtt.js 輕。背景：mqtt.js v4/v5 在
// SD plugin Node runtime 對 idle 連線會持續燒 CPU（plugin 22% + SD app 65%）。
// 改用 mqtt-connection + 自管 net socket 後，idle 連線 < 2% SD app。
// @ts-ignore -- 套件無 type definitions
import mqttCon from "mqtt-connection";

export type StateChangeCallback = (project: string, state: string | null) => void;
export type RebuildCallback = (cache: Map<string, string>) => void;
export type SysStatsCallback = (temp: number, ram: number) => void;
export type WinStatsCallback = (temp: number, freq: number, ram: number) => void;

const RECONNECT_MS = 5000;
const REBUILD_DEBOUNCE_MS = 300;
const REBUILD_FALLBACK_MS = 1000;

interface PublishPacket {
  topic: string;
  payload: Buffer;
  retain?: boolean;
}

/**
 * MQTT client using mqtt-connection (codec only) + raw net socket.
 * 自管：reconnect、subscribe、rebuild phase。
 */
export class MqttHandler {
  private socket: net.Socket | null = null;
  private conn: any = null;
  private cache = new Map<string, string>();
  private rebuilding = false;
  private rebuildTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private currentBroker = "";
  private currentPort = 0;
  private stopped = false;
  private lastSysStats = "";
  private lastWinStats = "";

  constructor(
    private onStateChange: StateChangeCallback,
    private onRebuild: RebuildCallback,
    private onSysStats?: SysStatsCallback,
    private onWinStats?: WinStatsCallback,
  ) {}

  connect(broker: string, port: number): void {
    if (this.socket && this.currentBroker === broker && this.currentPort === port) {
      return;
    }
    this.disconnect();
    this.currentBroker = broker;
    this.currentPort = port;
    this.stopped = false;
    this.openSocket();
  }

  disconnect(): void {
    this.stopped = true;
    if (this.rebuildTimer) {
      clearTimeout(this.rebuildTimer);
      this.rebuildTimer = null;
    }
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.conn) {
      try { this.conn.destroy(); } catch { /* ignore */ }
      this.conn = null;
    }
    if (this.socket) {
      try { this.socket.destroy(); } catch { /* ignore */ }
      this.socket = null;
    }
    this.currentBroker = "";
    this.currentPort = 0;
  }

  private openSocket(): void {
    if (this.stopped) return;
    streamDeck.logger.info(`MQTT connecting to mqtt://${this.currentBroker}:${this.currentPort}`);

    const sock = net.createConnection({ host: this.currentBroker, port: this.currentPort });
    this.socket = sock;
    const conn = mqttCon(sock);
    this.conn = conn;

    sock.on("connect", () => {
      conn.connect({
        protocolId: "MQTT",
        protocolVersion: 4,
        clientId: `sd-claude-monitor-${Math.floor(Math.random() * 1e6)}`,
        clean: true,
        keepalive: 60,
      });
    });

    conn.on("connack", (packet: { returnCode: number }) => {
      if (packet.returnCode !== 0) {
        streamDeck.logger.error(`MQTT CONNACK rc=${packet.returnCode}`);
        this.scheduleReconnect();
        return;
      }
      streamDeck.logger.info("MQTT connected, rebuilding...");
      this.startRebuild();
      conn.subscribe({
        messageId: 1,
        subscriptions: [
          { topic: "claude/led/+", qos: 0 },
          { topic: "system/stats", qos: 0 },
          { topic: "system/stats/win", qos: 0 },
        ],
      });
    });

    conn.on("publish", (packet: PublishPacket) => this.handlePublish(packet));
    conn.on("pingresp", () => { /* ignore */ });
    conn.on("error", (err: Error) => {
      streamDeck.logger.error(`MQTT codec error: ${err.message}`);
    });

    sock.on("error", (err: Error) => {
      streamDeck.logger.error(`MQTT socket error: ${err.message}`);
    });
    sock.on("close", () => {
      this.scheduleReconnect();
    });

    // 自送 PINGREQ；keepalive=60 表示 60s 內必須有 packet，否則 broker 斷線
    const pingTimer = setInterval(() => {
      if (this.conn === conn) {
        try { conn.pingreq(); } catch { /* socket closed */ }
      } else {
        clearInterval(pingTimer);
      }
    }, 50_000);
    sock.on("close", () => clearInterval(pingTimer));
  }

  private scheduleReconnect(): void {
    if (this.stopped) return;
    if (this.reconnectTimer) return;
    if (this.conn) {
      try { this.conn.destroy(); } catch { /* ignore */ }
      this.conn = null;
    }
    if (this.socket) {
      try { this.socket.destroy(); } catch { /* ignore */ }
      this.socket = null;
    }
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.openSocket();
    }, RECONNECT_MS);
  }

  private handlePublish(packet: PublishPacket): void {
    const topic = packet.topic;
    const payload = packet.payload;

    if (topic === "system/stats" && this.onSysStats) {
      const raw = payload.toString();
      if (raw === this.lastSysStats) return;
      this.lastSysStats = raw;
      try {
        const data = JSON.parse(raw);
        this.onSysStats(data.temp ?? 0, data.ram ?? 0);
      } catch { /* ignore malformed */ }
      return;
    }

    if (topic === "system/stats/win" && this.onWinStats) {
      const raw = payload.toString();
      if (raw === this.lastWinStats) return;
      this.lastWinStats = raw;
      try {
        const data = JSON.parse(raw);
        this.onWinStats(data.temp ?? 0, data.freq ?? 0, data.ram ?? 0);
      } catch { /* ignore malformed */ }
      return;
    }

    const parts = topic.split("/");
    if (parts.length !== 3) return;
    const project = parts[2];

    if (!payload || payload.length === 0) {
      this.cache.delete(project);
      if (!this.rebuilding) {
        this.onStateChange(project, null);
      }
      return;
    }

    let state: string;
    try {
      const data = JSON.parse(payload.toString());
      state = (data.state || "").toLowerCase();
    } catch {
      return;
    }

    if (this.cache.get(project) === state && !this.rebuilding) {
      return;
    }
    this.cache.set(project, state);

    if (this.rebuilding) {
      if (this.rebuildTimer) clearTimeout(this.rebuildTimer);
      this.rebuildTimer = setTimeout(() => this.finishRebuild(), REBUILD_DEBOUNCE_MS);
    } else {
      this.onStateChange(project, state);
    }
  }

  private startRebuild(): void {
    this.cache.clear();
    this.rebuilding = true;
    if (this.rebuildTimer) clearTimeout(this.rebuildTimer);
    this.rebuildTimer = setTimeout(() => this.finishRebuild(), REBUILD_FALLBACK_MS);
  }

  private finishRebuild(): void {
    this.rebuilding = false;
    this.rebuildTimer = null;
    streamDeck.logger.info(`Rebuild complete: ${this.cache.size} projects`);
    this.onRebuild(new Map(this.cache));
  }
}
