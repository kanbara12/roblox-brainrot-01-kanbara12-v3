import { copyFileSync, cpSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildDossier } from "./vendor/makefun-roblox.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = process.env.MAKEFUN_OUTPUT_DIR ?? "/output";

mkdirSync(outDir, { recursive: true });

copyFileSync(path.join(here, "game.rbxl"), path.join(outDir, "game.rbxl"));
copyFileSync(path.join(here, "PLAY.json"), path.join(outDir, "PLAY.json"));

const skipDotted = (src: string) => !path.basename(src).startsWith(".");

cpSync(path.join(here, "src"), path.join(outDir, "src"), {
  recursive: true,
  filter: skipDotted,
});

const screenshotsSource = path.join(here, "screenshots");
mkdirSync(path.join(outDir, "screenshots"), { recursive: true });
if (existsSync(screenshotsSource)) {
  cpSync(screenshotsSource, path.join(outDir, "screenshots"), {
    recursive: true,
    filter: skipDotted,
  });
}

const dossier = buildDossier(outDir, {
  text_max_bytes: 65536,
  screenshots: { max: 4, max_bytes: 262144 },
  max_instances: 500000,
  scripts_max_source_bytes: 8388608,
  scripts_max_path_chars: 1048576,
});
writeFileSync(path.join(outDir, "dossier.json"), dossier);
