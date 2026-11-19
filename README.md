# ROTBEARD'S LAGOON — a pirate brainrot game for make.fun

[![make.fun](https://img.shields.io/badge/make.fun-roblox--brainrot--01-8b5cf6)](https://make.fun)
[![Roblox](https://img.shields.io/badge/Roblox-Place-ff0000)](https://www.roblox.com/games/117240506291115/Rotbeards-Lagoon)

Ahoy! Rotbeard's Lagoon is a 3D pirate brainrot game built for make.fun's
"Make the best AI Roblox brainrot game" bounty (roblox-brainrot-01). Brainrots
sail down a treasure chute onto the lagoon, you buy them, carry them home to
your ship deck, and earn doubloons every second. Then the real pirate life
starts: steal from the rival crew, slap thieves off their feet, lock your
deck behind a cannon net, survive the Kraken Surge on high ground, and
rebirth for a permanent income multiplier.

## What is in the game

- **40 original brainrots** in 7 rarities (COMMON, RARE, EPIC, LEGENDARY,
  MYTHIC, CAPTAIN, LEGEND), each a hand-built 3D rig with its own joke line,
  from Anchovy Al ($10) to Rotbeard Rex ($25,000,000).
- **4 mutations** on every roll: GOLDEN x2, PEARL x3, CURSED x5, GHOST x10,
  each with its own look — gold neon and sparkles, glass pearl, cursed
  purple light, ghost transparency.
- **A living lagoon**: a treasure chute with a spawn gate and exit portal, two
  ship-deck bases with 8 gold-trimmed pedestals each, a rival crew deck, a
  galleon, a lighthouse, palm trees, treasure chests, cannons and torches.
- **Steal, slap, lock**: click a brainrot on another deck to steal it, carry
  it home over your head, slap a thief to knock it loose, lock your deck
  for 40 seconds plus 10 per lock upgrade.
- **3 scheduled events**: Kraken Surge (a wave sweeps the low ground — only
  the galleon deck and lighthouse keep your loot safe), Golden Tide (all
  income x2 for 60 seconds), Parrot Raid (thieving parrots hit unlocked
  decks).
- **Progression**: 4 ship upgrades (walk speed, lock time, extra pedestal,
  income), rebirth from $50,000 with a permanent x2 multiplier, 12 bounties
  with doubloon rewards, and the Captain's Log — a 40-tile collection index.
- **HUD**: top-center cash and income, event banner with countdown, feed,
  bounty tracker, carrying bar, and keybinds — LOCK [L], WHACK [F],
  UPGRADES [U], LOG [B], REBIRTH [R].

## How to play

1. Wait at the treasure chute. When a brainrot you like rides past, click
   it to buy it.
2. Carry it home to your deck. It lands on a free pedestal and starts
   paying you every second.
3. Steal from the rival crew's deck (north side) — or from other players —
   but watch for the slap.
4. When the Kraken Surge warning sounds, get to high ground: the galleon
   deck or the lighthouse platform. Anything carried on the low ground is
   lost to the wave.
5. Spend doubloons on upgrades, lock your deck before a Parrot Raid, and
   rebirth once you own a LEGENDARY brainrot.

## Build and run

- `main.ts` (Node 22, standard library only) hands the game in: it copies
  `game.rbxl`, `src/`, `screenshots/` and `PLAY.json` to `/output`, leaving
  out every name that starts with a dot, and writes `/output/dossier.json`
  with `vendor/makefun-roblox.ts`, the kit's copy, unchanged.
- `game.rbxl` is the place Rojo builds from `src/` and
  `default.project.json`: `rojo build default.project.json --output game.rbxl`.
- `screenshots/` holds four captures of the game; the first by name is the
  cover, and it is also the thumbnail uploaded for the game on Roblox.
- `PLAY.json` names the published place (place 117240506291115, universe
  10777825734).
- `TOUR.json` is the optional tour: for each screenshot, the Stagehand
  function that brings the game to that screen in Studio.

Run it as the grader does, writing `out/` in place of `/output`:

    mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

The rules are on the bounty's page (/bounty/roblox-brainrot-01) and in the
kit's RULES.txt, which gives every command in order (Before you submit,
then Enter).
