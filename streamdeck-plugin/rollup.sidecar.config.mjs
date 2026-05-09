// Sidecar bundle config for Axis 8 ablation — see scripts/sidecar-mqtt-test.mjs.
// Mirrors rollup.config.mjs's resolution rules so we get the exact same
// mqtt-connection bundle the plugin runs with.
import { builtinModules } from "node:module";
import commonjs from "@rollup/plugin-commonjs";
import json from "@rollup/plugin-json";
import nodeResolve from "@rollup/plugin-node-resolve";

export default {
  input: "scripts/sidecar-mqtt-test.mjs",
  output: {
    file: "/mnt/c/temp/axis8/sidecar.js",
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
