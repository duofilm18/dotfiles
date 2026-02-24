import {
  action,
  SingletonAction,
  type KeyDownEvent,
  type WillAppearEvent,
  type WillDisappearEvent,
} from "@elgato/streamdeck";
import streamDeck from "@elgato/streamdeck";
import { execFile } from "node:child_process";
import {
  STATE_DISPLAY,
  BLINK_DISPLAY,
  UNKNOWN_DISPLAY,
  type StateDisplay,
} from "../types";
import { renderStatusSvg, renderOffSvg, svgToDataUri } from "../renderer";

/**
 * Claude Status action：自動分配 MQTT 專案、閃爍、按鍵切 tmux
 *
 * 用戶拖 N 個 "Claude Status" 到按鍵上，plugin 自動分配 MQTT 專案。
 * assignments: Map<contextId, projectName | null>
 * 新專案 → 找第一個 null 的 slot 分配
 * 空 payload → 釋放 slot，渲染 off
 */
@action({ UUID: "com.duofilm.claude-monitor.claude-status" })
export class ClaudeStatusAction extends SingletonAction {
  /** contextId → project name (null = unassigned slot) */
  private assignments = new Map<string, string | null>();
  /** project → current state */
  private projectStates = new Map<string, string>();
  /** blink toggle */
  private blinkOn = false;

  constructor() {
    super();
    setInterval(() => this.blinkTick(), 1000);
  }

  override async onWillAppear(ev: WillAppearEvent): Promise<void> {
    if (!this.assignments.has(ev.action.id)) {
      this.assignments.set(ev.action.id, null);
    }
    await ev.action.setImage(svgToDataUri(renderOffSvg()));
  }

  override async onWillDisappear(ev: WillDisappearEvent): Promise<void> {
    this.assignments.delete(ev.action.id);
  }

  override async onKeyDown(ev: KeyDownEvent): Promise<void> {
    const project = this.assignments.get(ev.action.id);
    if (!project) return;

    // 1. 切換 tmux window
    const tmuxCmd =
      `idx=$(tmux list-windows -F '#{window_index} #{@project}'` +
      ` | grep ' ${project}$' | head -1 | cut -d' ' -f1)` +
      ` && [ -n "$idx" ] && tmux select-window -t :$idx`;

    execFile("wsl.exe", ["bash", "-c", tmuxCmd], (err) => {
      if (err) streamDeck.logger.error(`tmux switch failed: ${err.message}`);
    });

    // 2. 把 Windows Terminal 拉到前景
    execFile(
      "powershell.exe",
      [
        "-WindowStyle",
        "Hidden",
        "-Command",
        "(New-Object -ComObject WScript.Shell).AppActivate('Terminal')",
      ],
      (err) => {
        if (err) streamDeck.logger.error(`AppActivate failed: ${err.message}`);
      },
    );
  }

  // --- Public API（由 plugin.ts 呼叫） ---

  /** 新專案或狀態更新 → 分配 slot + 渲染 */
  assignProject(project: string, state: string): void {
    this.projectStates.set(project, state);

    // 已有分配？直接更新
    for (const [ctxId, p] of this.assignments) {
      if (p === project) {
        this.renderKey(ctxId, project, state);
        return;
      }
    }

    // 找第一個 null slot 分配
    for (const [ctxId, p] of this.assignments) {
      if (p === null) {
        this.assignments.set(ctxId, project);
        this.renderKey(ctxId, project, state);
        return;
      }
    }

    streamDeck.logger.warn(`No available slot for project: ${project}`);
  }

  /** 專案移除 → 釋放 slot、渲染 off */
  removeProject(project: string): void {
    this.projectStates.delete(project);
    for (const [ctxId, p] of this.assignments) {
      if (p === project) {
        this.assignments.set(ctxId, null);
        this.renderKeyOff(ctxId);
        return;
      }
    }
  }

  /** Rebuild Phase：清除所有分配，從 cache 重新分配 */
  rebuild(cache: Map<string, string>): void {
    // 清除
    for (const ctxId of this.assignments.keys()) {
      this.assignments.set(ctxId, null);
    }
    this.projectStates.clear();

    // 重新分配
    for (const [project, state] of cache) {
      this.assignProject(project, state);
    }

    // 剩餘空 slot 渲染 off
    for (const [ctxId, p] of this.assignments) {
      if (p === null) {
        this.renderKeyOff(ctxId);
      }
    }
  }

  // --- Private ---

  private renderKey(contextId: string, project: string, state: string): void {
    const display = STATE_DISPLAY[state] ?? UNKNOWN_DISPLAY;
    const svg = renderStatusSvg(project, display);
    const act = this.findAction(contextId);
    act?.setImage(svgToDataUri(svg));
  }

  private renderKeyOff(contextId: string): void {
    const act = this.findAction(contextId);
    act?.setImage(svgToDataUri(renderOffSvg()));
  }

  private findAction(contextId: string) {
    for (const a of this.actions) {
      if (a.id === contextId) return a;
    }
    return undefined;
  }

  /** 每秒閃爍：只重繪 idle/waiting 的按鍵（狀態色 ↔ 白色） */
  private blinkTick(): void {
    this.blinkOn = !this.blinkOn;
    for (const [ctxId, project] of this.assignments) {
      if (!project) continue;
      const state = this.projectStates.get(project);
      if (!state || !(state in BLINK_DISPLAY)) continue;

      const display: StateDisplay = this.blinkOn
        ? BLINK_DISPLAY[state]
        : STATE_DISPLAY[state];

      const svg = renderStatusSvg(project, display);
      const act = this.findAction(ctxId);
      act?.setImage(svgToDataUri(svg));
    }
  }
}
