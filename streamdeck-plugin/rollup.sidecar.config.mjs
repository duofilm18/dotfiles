// Sidecar bundle config — bundles streamdeck-plugin/sidecar/sidecar.mjs
// (and its mqtt-connection dependency) into a self-contained CJS file at
// sidecar/dist/sidecar.js. The npm `build:sidecar` script then copies it
// to %LOCALAPPDATA%\claude-monitor\sidecar.js via deploy-paths.sh, so we
// never hardcode a Windows path here (CLAUDE.md rule 14: deploy-paths).
//
// This is the production sidecar that pairs with src/state-reader.ts to
// keep MQTT out of the SD plugin sandbox (see sidecar/README.md).
//
// (Axis 8 ablation also used a sidecar bundle; that one-shot test bundle
// still lives at /mnt/c/temp/axis8/sidecar.js and was built from
// scripts/sidecar-mqtt-test.mjs — to rebuild it, point input at that
// source temporarily.)
import { builtinModules } from "node:module";
import commonjs from "@rollup/plugin-commonjs";
import json from "@rollup/plugin-json";
import nodeResolve from "@rollup/plugin-node-resolve";

export default {
  input: "sidecar/sidecar.mjs",
  output: {
    file: "sidecar/dist/sidecar.js",
    format: "cjs",
  },
  external: [
    ...builtinModules,
    ...builtinModules.map((m) => `node:${m}`),
  ],
  plugins: [
    nodeResolve({
      preferBuiltins: true,
      exportConditions: ["node"],
      mainFields: ["main", "module"],
    }),
    commonjs(),
    json(),
  ],
};
