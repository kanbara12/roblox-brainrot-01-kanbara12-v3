// main.ts
// The grader entry point. It assembles the submission output: it copies the
// game files into the output directory and writes dossier.json, the summary
// the judge reads, using the vendored make.fun library.

import { copyFileSync, cpSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildDossier } from "./vendor/makefun-roblox.ts";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const outputDir = process.env.MAKEFUN_OUTPUT_DIR || "/output";

// A path is copied only when no component of its name starts with a dot.
// The filter runs at every depth, so dotted names anywhere are excluded.
function isNotDotName(sourcePath: string): boolean {
	return !basename(sourcePath).startsWith(".");
}

mkdirSync(outputDir, { recursive: true });

// Copy the game bundle and the play manifest.
copyFileSync(join(scriptDir, "game.rbxl"), join(outputDir, "game.rbxl"));
copyFileSync(join(scriptDir, "PLAY.json"), join(outputDir, "PLAY.json"));

// Copy the whole src/ directory, excluding dot-named files and directories.
cpSync(join(scriptDir, "src"), join(outputDir, "src"), {
	recursive: true,
	filter: isNotDotName,
});

// Create screenshots/ in the output directory, and copy the screenshots in
// with the same dot-name filter when they exist beside this program.
mkdirSync(join(outputDir, "screenshots"), { recursive: true });
const screenshotsDir = join(scriptDir, "screenshots");
if (existsSync(screenshotsDir)) {
	cpSync(screenshotsDir, join(outputDir, "screenshots"), {
		recursive: true,
		filter: isNotDotName,
	});
}

// Write dossier.json with the scorer caps.
const dossier = buildDossier(outputDir, {
	text_max_bytes: 65536,
	screenshots: { max: 4, max_bytes: 262144 },
	max_instances: 500000,
	scripts_max_source_bytes: 8388608,
	scripts_max_path_chars: 1048576,
});
writeFileSync(join(outputDir, "dossier.json"), dossier);
