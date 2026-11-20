import { copyFileSync, cpSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildDossier } from "./vendor/makefun-roblox.ts";

// Rotbeard's Lagoon — grader entry point. Copies the game files into the
// output directory and writes dossier.json with the vendored make.fun library.
const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = process.env.MAKEFUN_OUTPUT_DIR ?? "/output";

// Reject every file or directory whose name starts with a dot, at any depth.
// A dotted name anywhere under the output fails the grader.
const noDotName = (src: string) => !path.basename(src).startsWith(".");

mkdirSync(outDir, { recursive: true });
copyFileSync(path.join(here, "game.rbxl"), path.join(outDir, "game.rbxl"));
copyFileSync(path.join(here, "PLAY.json"), path.join(outDir, "PLAY.json"));
cpSync(path.join(here, "src"), path.join(outDir, "src"), {
	recursive: true,
	filter: noDotName,
});
mkdirSync(path.join(outDir, "screenshots"), { recursive: true });
if (existsSync(path.join(here, "screenshots"))) {
	cpSync(path.join(here, "screenshots"), path.join(outDir, "screenshots"), {
		recursive: true,
		filter: noDotName,
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
