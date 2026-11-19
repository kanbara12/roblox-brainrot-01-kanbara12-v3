-- Game.client: boots Rotbeard's Lagoon on the client. The whole HUD lives in
-- DeckHud; this script only starts it once the player is in.
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local DeckHud = require(script.Parent.DeckHud)

player:WaitForChild("PlayerGui")
DeckHud.init()
print("[Rotbeard's Lagoon] DeckHud live for " .. player.Name)
