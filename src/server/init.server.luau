-- init.server.luau
-- Boots Rotbeard's Lagoon: creates the remotes, paints the world sign and
-- pedestal numbers, fills the rival deck, starts every loop, and wires
-- player join/leave plus client actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create the remotes BEFORE any require, so the client never waits on a
-- remote that only appears after the require chain. PirateState reuses the
-- LagoonUpdate remote created here.
local LagoonAction = Instance.new("RemoteEvent")
LagoonAction.Name = "LagoonAction"
LagoonAction.Parent = ReplicatedStorage

local LagoonUpdate = Instance.new("RemoteEvent")
LagoonUpdate.Name = "LagoonUpdate"
LagoonUpdate.Parent = ReplicatedStorage

-- Require the modules. Rojo builds this file into a Script named "Server"
-- whose children are the server modules, so the requires are of the form
-- require(script.<ModuleName>). Shared modules come from ReplicatedStorage.
local PirateState = require(script.PirateState)
local TreasureChuteService = require(script.TreasureChuteService)
local DoubloonService = require(script.DoubloonService)
local PlunderService = require(script.PlunderService)
local StormService = require(script.StormService)
local RivalCrewService = require(script.RivalCrewService)
local LegendService = require(script.LegendService)
local UpgradeService = require(script.UpgradeService)
local BountyService = require(script.BountyService)
local Stagehand = require(script.Stagehand)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BootyCatalog = require(Shared:WaitForChild("BootyCatalog"))
local RigBuilder = require(Shared:WaitForChild("RigBuilder"))
local LagoonLayout = require(Shared:WaitForChild("LagoonLayout"))

-- The slap range in studs (for finding the nearest other player).
local SLAP_RANGE = 14

-- Sends the full snapshot to a player: cash, income per second, rebirths,
-- rebirth multiplier, slots, upgrades, the bounty list, the found set, the
-- base, and the remaining lock seconds.
local function sendSnapshot(player)
	local state = PirateState.getState(player)
	if not state then
		return
	end
	PirateState.broadcast(player, {
		type = "snapshot",
		cash = state.cash,
		income = PirateState.getIncomePerSecond(player),
		rebirths = state.rebirths,
		multiplier = PirateState.getRebirthMultiplier(player),
		slots = state.slots,
		upgrades = state.upgrades,
		bounties = BountyService.getBountyList(player),
		found = state.found,
		base = state.base,
		remaining = math.floor(PirateState.getBaseLockRemaining(player)),
	})
end

-- Sets up a player who joined: creates the state, wires character spawn
-- (wait 1 second, apply all upgrades, apply the rebirth aura if the player
-- has any rebirths), and sends the snapshot 1 second after join.
local function setupPlayer(player)
	PirateState.initPlayerState(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(1)
		if not PirateState.getState(player) then
			return
		end
		UpgradeService.applyAllUpgradesToCharacter(player)
		local state = PirateState.getState(player)
		if state and state.rebirths > 0 then
			LegendService.applyRebirthAura(player)
		end
	end)
	task.spawn(function()
		task.wait(1)
		sendSnapshot(player)
	end)
end

-- Finds the nearest other player within 14 studs of the given player, by
-- HumanoidRootPart distance. Returns nil when no other player is in range.
local function findNearestPlayerInRange(player)
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local nearest = nil
	local nearestDistance = SLAP_RANGE
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local otherChar = other.Character
			if otherChar then
				local otherRoot = otherChar:FindFirstChild("HumanoidRootPart")
				if otherRoot then
					local distance = (otherRoot.Position - root.Position).Magnitude
					if distance <= nearestDistance then
						nearest = other
						nearestDistance = distance
					end
				end
			end
		end
	end
	return nearest
end

-- Paint the lagoon sign, then the pedestal numbers for bases A, B, and R.
RigBuilder.paintLagoonSign()
RigBuilder.paintPedestalNumbers("A")
RigBuilder.paintPedestalNumbers("B")
RigBuilder.paintPedestalNumbers("R")

-- Fill the rival plot, start the chute loop, start the income loop, and
-- start the event scheduler.
RivalCrewService.populateSoloRivalPlot()
TreasureChuteService.startChuteLoop()
DoubloonService.startIncomeLoop()
StormService.startEventScheduler()

-- Expire base locks every 5 seconds.
task.spawn(function()
	while true do
		task.wait(5)
		PlunderService.expireBaseLocks()
	end
end)

-- Handle players already in the server at boot, then new joins and leaves.
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end
Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	PirateState.removePlayerState(player)
end)

-- Dispatch client actions from the LagoonAction remote.
LagoonAction.OnServerEvent:Connect(function(player, action, arg1, arg2)
	if action == "snapshot" then
		sendSnapshot(player)
	elseif action == "lock" then
		PlunderService.activateBaseLock(player)
	elseif action == "slap" then
		local nearest = findNearestPlayerInRange(player)
		if nearest then
			PlunderService.handleSlapPlayer(player, nearest)
		end
	elseif action == "rebirth" then
		if LegendService.canPlayerRebirth(player) then
			LegendService.performPlayerRebirth(player)
		end
	elseif action == "buyUpgrade" then
		UpgradeService.buyUpgrade(player, arg1)
	elseif action == "stealFrom" then
		PlunderService.startStealBrainrot(player, arg1, arg2)
	elseif action == "stealRival" then
		RivalCrewService.handleStealFromRivalPlot(player, arg1)
	end
end)

-- Keep the Stagehand module referenced so the TOUR steps can require it.
local _stagehand = Stagehand
local _catalog = BootyCatalog
local _layout = LagoonLayout
local _update = LagoonUpdate

print("[Rotbeard's Lagoon] Server booted. 40 brainrots, 3 events, rival crew live.")
