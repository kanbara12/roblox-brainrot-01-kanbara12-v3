// main.ts — the grader entry point for Rotbeard's Lagoon.
// Assembles the submission output: copies the game files into the output
// directory and writes dossier.json, the summary the judge reads, using
// the vendored make.fun library. Node 22, standard library only.
import { cpSync, existsSync, mkdirSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { buildDossier } from "./vendor/makefun-roblox.ts";

const here = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(process.env.MAKEFUN_OUTPUT_DIR ?? "/output");

// Copies a directory tree, skipping every file and directory whose name
// starts with a dot at any depth (a dotted name anywhere under the output
// fails the grader, so the filter applies at every depth).
function copyTree(srcDir: string, destDir: string): void {
	mkdirSync(destDir, { recursive: true });
	for (const entry of readdirSync(srcDir)) {
		if (entry.startsWith(".")) {
			continue;
		}
		const srcPath = join(srcDir, entry);
		const destPath = join(destDir, entry);
		if (statSync(srcPath).isDirectory()) {
			copyTree(srcPath, destPath);
		} else {
			cpSync(srcPath, destPath);
		}
	}
}

mkdirSync(outDir, { recursive: true });
cpSync(join(here, "game.rbxl"), join(outDir, "game.rbxl"));
cpSync(join(here, "PLAY.json"), join(outDir, "PLAY.json"));
copyTree(join(here, "src"), join(outDir, "src"));
const screenshotsDir = join(here, "screenshots");
mkdirSync(join(outDir, "screenshots"), { recursive: true });
if (existsSync(screenshotsDir)) {
	copyTree(screenshotsDir, join(outDir, "screenshots"));
}
const dossier = buildDossier(outDir, {
	text_max_bytes: 65536,
	screenshots: { max: 4, max_bytes: 262144 },
	max_instances: 500000,
	scripts_max_source_bytes: 8388608,
	scripts_max_path_chars: 1048576,
});
writeFileSync(join(outDir, "dossier.json"), dossier);
