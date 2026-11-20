-- init.server — server boot.
-- Boots Rotbeard's Lagoon: creates the remotes, paints the world sign and
-- pedestal numbers, fills the rival deck, starts every loop, and wires
-- player join/leave plus client actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 1. Create the remotes first, before any require, so the client never waits
-- on a remote that only appears after the require chain.
local LagoonAction = ReplicatedStorage:FindFirstChild("LagoonAction")
if not LagoonAction then
	LagoonAction = Instance.new("RemoteEvent")
	LagoonAction.Name = "LagoonAction"
	LagoonAction.Parent = ReplicatedStorage
end
local LagoonUpdate = ReplicatedStorage:FindFirstChild("LagoonUpdate")
if not LagoonUpdate then
	LagoonUpdate = Instance.new("RemoteEvent")
	LagoonUpdate.Name = "LagoonUpdate"
	LagoonUpdate.Parent = ReplicatedStorage
end

-- 2. Require the modules. Rojo builds this file into a Script named "Server"
-- whose children are the server modules, so the requires MUST be of the form
-- require(script.<ModuleName>) — never require(script.Parent.<ModuleName>).
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

-- 3. Paint the world.
RigBuilder.paintLagoonSign()
RigBuilder.paintPedestalNumbers("A")
RigBuilder.paintPedestalNumbers("B")
RigBuilder.paintPedestalNumbers("R")

-- 4. Start the world systems.
RivalCrewService.populateSoloRivalPlot()
TreasureChuteService.startChuteLoop()
DoubloonService.startIncomeLoop()
StormService.startEventScheduler()

-- 5. Expire base locks every 5 seconds.
task.spawn(function()
	while true do
		task.wait(5)
		PlunderService.expireBaseLocks()
	end
end)

--------------------------------------------------------------------------------
-- Players
--------------------------------------------------------------------------------

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

local function setupCharacter(player)
	task.wait(1)
	UpgradeService.applyAllUpgradesToCharacter(player)
	local state = PirateState.getState(player)
	if state and state.rebirths > 0 then
		LegendService.applyRebirthAura(player)
	end
end

local function onPlayerAdded(player)
	PirateState.initPlayerState(player)
	player.CharacterAdded:Connect(function()
		task.spawn(setupCharacter, player)
	end)
	if player.Character then
		task.spawn(setupCharacter, player)
	end
	task.delay(1, function()
		sendSnapshot(player)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	PirateState.removePlayerState(player)
end)

--------------------------------------------------------------------------------
-- Client actions
--------------------------------------------------------------------------------

local SLAP_RANGE = 14

local function findNearestPlayerInRange(player, range)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local nearest = nil
	local nearestDist = range
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local otherChar = other.Character
			local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local dist = (otherRoot.Position - root.Position).Magnitude
				if dist <= nearestDist then
					nearest = other
					nearestDist = dist
				end
			end
		end
	end
	return nearest
end

LagoonAction.OnServerEvent:Connect(function(player, action, arg1, arg2)
	if action == "snapshot" then
		sendSnapshot(player)
	elseif action == "lock" then
		PlunderService.activateBaseLock(player)
	elseif action == "slap" then
		local victim = findNearestPlayerInRange(player, SLAP_RANGE)
		if victim then
			PlunderService.handleSlapPlayer(player, victim)
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

print("[Rotbeard's Lagoon] Server booted. 40 brainrots, 3 events, rival crew live.")
