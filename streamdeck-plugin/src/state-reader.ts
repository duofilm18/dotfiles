// Polls %LOCALAPPDATA%\claude-monitor\state.json (written by the sidecar)
// and applies snapshots to the action instances. Replaces in-process MQTT
// for normal operation — the in-process MqttHandler stays in the codebase
// as a fallback path (see plugin.ts DATA_SOURCE).
//
// Why polling, not fs.watch:
//   The CPU regression we are working around is sandbox-specific to
//   outgoing TCP sockets. fs.watch is not a socket but it does spawn a
//   ReadDirectoryChangesW listener that the sandbox might react to as
//   well. Codex Round 5 review specified to start with conservative
//   polling and only escalate to fs.watch if polling CPU is verified at
//   zero and we want lower latency.
//
// Default poll interval: 1000 ms. Plugin Node CPU contribution should
// remain at noise level — the file is a few hundred bytes and the diff
// against the last applied snapshot is O(projects).
//
// Snapshot version 1 contract: see sidecar/sidecar.mjs.
import * as fs from "node:fs";
import * as path from "node:path";
import streamDeck from "@elgato/streamdeck";
import type { ClaudeStatusAction } from "./actions/claude-status";
import type { SystemStatsAction } from "./actions/system-stats";
import type { WinStatsAction } from "./actions/win-stats";

interface SysStats {
  temp: number;
  ram: number;
}
interface WinStats {
  temp: number;
  freq: number;
  ram: number;
}
interface Snapshot {
  version: number;
  updatedAt: string;
  rebuildId: number;
  projects: Record<string, string>;
  sysStats: SysStats | null;
  winStats: WinStats | null;
}

const STATE_FILE = path.join(
  process.env.LOCALAPPDATA || process.env.HOME || ".",
  "claude-monitor",
  "state.json",
);

export class StateReader {
  private timer: ReturnType<typeof setInterval> | null = null;
  private lastRebuildId = -1;
  private lastProjects: Record<string, string> = {};
  private lastSysJson = "";
  private lastWinJson = "";
  private readErrorLogged = false;

  constructor(
    private statusAction: ClaudeStatusAction,
    private sysAction: SystemStatsAction,
    private winAction: WinStatsAction,
    private intervalMs: number = 1000,
  ) {}

  start(): void {
    streamDeck.logger.info(
      `[state-reader] polling ${STATE_FILE} every ${this.intervalMs}ms`,
    );
    this.tick();
    this.timer = setInterval(() => this.tick(), this.intervalMs);
  }

  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private tick(): void {
    let raw: string;
    try {
      raw = fs.readFileSync(STATE_FILE, "utf8");
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code !== "ENOENT" && !this.readErrorLogged) {
        streamDeck.logger.error(
          `[state-reader] read failed: ${(err as Error).message}`,
        );
        this.readErrorLogged = true;
      }
      return;
    }
    this.readErrorLogged = false;

    let snap: Snapshot;
    try {
      snap = JSON.parse(raw) as Snapshot;
    } catch (err) {
      streamDeck.logger.warn(
        `[state-reader] JSON parse failed: ${(err as Error).message}`,
      );
      return;
    }

    if (snap.version !== 1) {
      streamDeck.logger.warn(
        `[state-reader] unsupported snapshot version: ${snap.version}`,
      );
      return;
    }

    this.applyProjects(snap);
    this.applySysStats(snap);
    this.applyWinStats(snap);
  }

  private applyProjects(snap: Snapshot): void {
    if (snap.rebuildId !== this.lastRebuildId) {
      const cache = new Map(Object.entries(snap.projects));
      this.statusAction.rebuild(cache);
      this.lastRebuildId = snap.rebuildId;
      this.lastProjects = { ...snap.projects };
      return;
    }
    const newP = snap.projects;
    const oldP = this.lastProjects;
    for (const [k, v] of Object.entries(newP)) {
      if (oldP[k] !== v) {
        this.statusAction.assignProject(k, v);
      }
    }
    for (const k of Object.keys(oldP)) {
      if (!(k in newP)) {
        this.statusAction.removeProject(k);
      }
    }
    this.lastProjects = { ...newP };
  }

  private applySysStats(snap: Snapshot): void {
    const j = JSON.stringify(snap.sysStats);
    if (j === this.lastSysJson) return;
    this.lastSysJson = j;
    if (snap.sysStats) {
      this.sysAction.updateStats(snap.sysStats.temp, snap.sysStats.ram);
    }
  }

  private applyWinStats(snap: Snapshot): void {
    const j = JSON.stringify(snap.winStats);
    if (j === this.lastWinJson) return;
    this.lastWinJson = j;
    if (snap.winStats) {
      this.winAction.updateStats(
        snap.winStats.temp,
        snap.winStats.freq,
        snap.winStats.ram,
      );
    }
  }
}
