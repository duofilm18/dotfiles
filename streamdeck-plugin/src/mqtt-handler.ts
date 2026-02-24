import mqtt, { type MqttClient } from "mqtt";
import streamDeck from "@elgato/streamdeck";

export type StateChangeCallback = (project: string, state: string | null) => void;
export type RebuildCallback = (cache: Map<string, string>) => void;
export type SysStatsCallback = (temp: number, ram: number) => void;

/**
 * MQTT 連線管理 + Rebuild Phase
 *
 * Rebuild Phase（與 Python 完全一致）：
 *   on_connect → 清快取、設 rebuilding=true、1.0s fallback timer
 *   on_message → 更新快取、重設 0.3s debounce timer
 *   debounce 到期 → finishRebuild() → 批次通知 action 層
 */
export class MqttHandler {
  private client: MqttClient | null = null;
  private cache = new Map<string, string>();
  private rebuilding = false;
  private rebuildTimer: ReturnType<typeof setTimeout> | null = null;
  private currentBroker = "";
  private currentPort = 0;

  constructor(
    private onStateChange: StateChangeCallback,
    private onRebuild: RebuildCallback,
    private onSysStats?: SysStatsCallback,
  ) {}

  connect(broker: string, port: number): void {
    // 同一 broker 不重連
    if (
      this.client &&
      this.currentBroker === broker &&
      this.currentPort === port
    ) {
      return;
    }

    this.disconnect();
    this.currentBroker = broker;
    this.currentPort = port;

    const url = `mqtt://${broker}:${port}`;
    streamDeck.logger.info(`MQTT connecting to ${url}`);

    this.client = mqtt.connect(url, {
      reconnectPeriod: 5000,
    });

    this.client.on("connect", () => {
      streamDeck.logger.info("MQTT connected, rebuilding...");
      this.startRebuild();
      this.client!.subscribe("claude/led/+");
      this.client!.subscribe("system/stats");
    });

    this.client.on("message", (_topic, payload, packet) => {
      // system/stats → 獨立處理，不走 rebuild
      if (packet.topic === "system/stats" && this.onSysStats) {
        try {
          const data = JSON.parse(payload.toString());
          this.onSysStats(data.temp ?? 0, data.ram ?? 0);
        } catch { /* ignore malformed */ }
        return;
      }

      const parts = packet.topic.split("/");
      if (parts.length !== 3) return;
      const project = parts[2];

      // 空 payload = 專案已關閉
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

      this.cache.set(project, state);

      if (this.rebuilding) {
        // Rebuild Phase：只更新 cache，debounce 後 batch render
        if (this.rebuildTimer) clearTimeout(this.rebuildTimer);
        this.rebuildTimer = setTimeout(() => this.finishRebuild(), 300);
      } else {
        this.onStateChange(project, state);
      }
    });

    this.client.on("error", (err) => {
      streamDeck.logger.error(`MQTT error: ${err.message}`);
    });
  }

  disconnect(): void {
    if (this.rebuildTimer) {
      clearTimeout(this.rebuildTimer);
      this.rebuildTimer = null;
    }
    if (this.client) {
      this.client.end(true);
      this.client = null;
    }
    this.currentBroker = "";
    this.currentPort = 0;
  }

  private startRebuild(): void {
    this.cache.clear();
    this.rebuilding = true;
    if (this.rebuildTimer) clearTimeout(this.rebuildTimer);
    // Fallback：若 broker 無 retained 訊息，1s 後仍完成 rebuild
    this.rebuildTimer = setTimeout(() => this.finishRebuild(), 1000);
  }

  private finishRebuild(): void {
    this.rebuilding = false;
    this.rebuildTimer = null;
    streamDeck.logger.info(`Rebuild complete: ${this.cache.size} projects`);
    this.onRebuild(new Map(this.cache));
  }
}
