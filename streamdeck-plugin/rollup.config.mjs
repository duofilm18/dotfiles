import { builtinModules } from "node:module";
import commonjs from "@rollup/plugin-commonjs";
import json from "@rollup/plugin-json";
import nodeResolve from "@rollup/plugin-node-resolve";
import typescript from "@rollup/plugin-typescript";

export default {
  input: "src/plugin.ts",
  output: {
    file: "com.duofilm.claude-monitor.sdPlugin/bin/plugin.js",
    format: "cjs",
    sourcemap: true,
  },
  external: [
    ...builtinModules,
    ...builtinModules.map((m) => `node:${m}`),
  ],
  plugins: [
    typescript(),
    nodeResolve({
      preferBuiltins: true,
      // 強制走 Node 入口；mqtt v5 的 browser ESM 會把 worker-timers 整包打進來，
      // 即便 SD plugin 在 Node 跑也會起 Web Worker 持續 IPC（~22% CPU）。
      exportConditions: ["node"],
      mainFields: ["main", "module"],
    }),
    commonjs(),
    json(),
  ],
};
