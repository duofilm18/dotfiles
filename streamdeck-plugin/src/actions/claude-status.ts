import {
  action,
  SingletonAction,
  type KeyDownEvent,
  type WillAppearEvent,
  type WillDisappearEvent,
} from "@elgato/streamdeck";
import streamDeck from "@elgato/streamdeck";
import { execFile } from "node:child_process";
import { STATE_DISPLAY, UNKNOWN_DISPLAY } from "../types";

const OFF_ICON = "imgs/states/off";

/**
 * Claude Status action：自動分配 MQTT 專案、按鍵切 tmux
 *
 * 用戶拖 N 個 "Claude Status" 到按鍵上，plugin 自動分配 MQTT 專案。
 * assignments: Map<contextId, projectName | null>
 *
 * 渲染策略（輕量）：
 *   - setImage：靜態 SVG 路徑，只在 state 真的切換時呼叫
 *   - setTitle：專案名 + 狀態 label（多行），便宜，每次更新都呼叫
 *   - 每個 slot 記住 lastIcon / lastTitle，避免重送相同值
 */
@action({ UUID: "com.duofilm.claude-monitor.claude-status" })
export class ClaudeStatusAction extends SingletonAction {
  /** contextId → project name (null = unassigned slot) */
  private assignments = new Map<string, string | null>();
  /** project → current state */
  private projectStates = new Map<string, string>();
  /** contextId → last icon path sent（避免重送 setImage） */
  private lastIcon = new Map<string, string>();
  /** contextId → last title sent（避免重送 setTitle） */
  private lastTitle = new Map<string, string>();

  override async onWillAppear(ev: WillAppearEvent): Promise<void> {
    if (!this.assignments.has(ev.action.id)) {
      this.assignments.set(ev.action.id, null);
    }
    this.lastIcon.delete(ev.action.id);
    this.lastTitle.delete(ev.action.id);
    await this.renderOff(ev.action.id);
  }

  override async onWillDisappear(ev: WillDisappearEvent): Promise<void> {
    this.assignments.delete(ev.action.id);
    this.lastIcon.delete(ev.action.id);
    this.lastTitle.delete(ev.action.id);
  }

  override async onKeyDown(ev: KeyDownEvent): Promise<void> {
    const project = this.assignments.get(ev.action.id);
    if (!project) return;

    execFile("wsl.exe", ["bash", "-lc", `~/dotfiles/scripts/tmux-switch-project.sh '${project}'`], (err) => {
      if (err) streamDeck.logger.error(`tmux switch failed: ${err.message}`);
    });

    execFile(
      "powershell.exe",
      [
        "-WindowStyle", "Hidden",
        "-Command",
        "(New-Object -ComObject WScript.Shell).AppActivate('Terminal')",
      ],
      (err) => {
        if (err) streamDeck.logger.error(`AppActivate failed: ${err.message}`);
      },
    );
  }

  // --- Public API（由 plugin.ts 呼叫） ---

  assignProject(project: string, state: string): void {
    this.projectStates.set(project, state);

    for (const [ctxId, p] of this.assignments) {
      if (p === project) {
        this.renderKey(ctxId, project, state);
        return;
      }
    }

    for (const [ctxId, p] of this.assignments) {
      if (p === null) {
        this.assignments.set(ctxId, project);
        this.renderKey(ctxId, project, state);
        return;
      }
    }

    streamDeck.logger.warn(`No available slot for project: ${project}`);
  }

  removeProject(project: string): void {
    this.projectStates.delete(project);
    for (const [ctxId, p] of this.assignments) {
      if (p === project) {
        this.assignments.set(ctxId, null);
        this.renderOff(ctxId);
        return;
      }
    }
  }

  rebuild(cache: Map<string, string>): void {
    for (const ctxId of this.assignments.keys()) {
      this.assignments.set(ctxId, null);
    }
    this.projectStates.clear();

    for (const [project, state] of cache) {
      this.assignProject(project, state);
    }

    for (const [ctxId, p] of this.assignments) {
      if (p === null) {
        this.renderOff(ctxId);
      }
    }
  }

  // --- Private rendering ---

  private renderKey(contextId: string, project: string, state: string): void {
    const display = STATE_DISPLAY[state] ?? UNKNOWN_DISPLAY;
    const act = this.findAction(contextId);
    if (!act) return;

    const iconPath = display.iconPath;
    if (this.lastIcon.get(contextId) !== iconPath) {
      this.lastIcon.set(contextId, iconPath);
      act.setImage(iconPath);
    }

    const title = `${project.slice(0, 10)}\n\n${display.label}`;
    if (this.lastTitle.get(contextId) !== title) {
      this.lastTitle.set(contextId, title);
      act.setTitle(title);
    }
  }

  private renderOff(contextId: string): void {
    const act = this.findAction(contextId);
    if (!act) return;

    if (this.lastIcon.get(contextId) !== OFF_ICON) {
      this.lastIcon.set(contextId, OFF_ICON);
      act.setImage(OFF_ICON);
    }
    if (this.lastTitle.get(contextId) !== "") {
      this.lastTitle.set(contextId, "");
      act.setTitle("");
    }
  }

  private findAction(contextId: string) {
    for (const a of this.actions) {
      if (a.id === contextId) return a;
    }
    return undefined;
  }
}
