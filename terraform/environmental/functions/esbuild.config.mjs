import { build } from "esbuild";
import { writeFileSync, mkdirSync } from "fs";

const result = await build({
  entryPoints: ["src/redirect-www-to-bare.ts"],
  bundle: true,
  write: false,
  format: "esm",
  target: "es2021",
  minify: false,
  define: {
    __DOMAIN__: JSON.stringify(process.env.DOMAIN || "francescoalbanese.dev"),
  },
});

const output = result.outputFiles[0].text
  .replace(/^export\s*\{[^}]*\};\s*$/gm, "")
  .trim();

mkdirSync("dist", { recursive: true });
writeFileSync("dist/redirect-www-to-bare.js", output + "\n");

console.log("Built dist/redirect-www-to-bare.js");
