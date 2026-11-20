-- init.server.luau
-- Boots Rotbeard's Lagoon: creates the remotes, paints the world sign and
-- pedestal numbers, fills the rival deck, starts every loop, and wires
-- player join/leave plus client actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create the remotes FIRST, before any require, so the client never waits
-- on a remote that only appears after the require chain. PirateState
-- reuses this same LagoonUpdate remote.
local LagoonAction = Instance.new("RemoteEvent")
LagoonAction.Name = "LagoonAction"
LagoonAction.Parent = ReplicatedStorage
local LagoonUpdate = Instance.new("RemoteEvent")
LagoonUpdate.Name = "LagoonUpdate"
LagoonUpdate.Parent = ReplicatedStorage

-- Require the modules. The require form is critical: Rojo builds this
-- file into a Script named "Server" whose children are the server
-- modules, so the requires must be require(script.<ModuleName>) -- never
-- require(script.Parent.<ModuleName>), which resolves to nil and kills
-- the boot script. Shared modules come from ReplicatedStorage.
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
local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))

local SLAP_RANGE = 14
local LOCK_EXPIRY_INTERVAL = 5
local JOIN_SNAPSHOT_DELAY = 1
local CHARACTER_SETUP_DELAY = 1

-- Sends the full snapshot to a player: cash, income per second, rebirths,
-- rebirth multiplier, slots, upgrades, the bounty list, the found set,
-- the base, and the remaining lock seconds.
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

-- Runs when a player joins. Creates the player state, wires the character
-- setup (wait 1 second, apply all upgrades for walk speed, apply the
-- rebirth aura when the player has any rebirths), and sends the full
-- snapshot 1 second after join.
local function onPlayerAdded(player)
	PirateState.initPlayerState(player)
	player.CharacterAdded:Connect(function(_character)
		task.wait(CHARACTER_SETUP_DELAY)
		UpgradeService.applyAllUpgradesToCharacter(player)
		local state = PirateState.getState(player)
		if state and state.rebirths > 0 then
			LegendService.applyRebirthAura(player)
		end
	end)
	task.spawn(function()
		task.wait(JOIN_SNAPSHOT_DELAY)
		sendSnapshot(player)
	end)
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
		task.wait(LOCK_EXPIRY_INTERVAL)
		PlunderService.expireBaseLocks()
	end
end)

-- Player join/leave. Players already in the server at boot are handled
-- the same way as new joins.
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	PirateState.removePlayerState(player)
end)

-- Client actions. Dispatches by action name.
LagoonAction.OnServerEvent:Connect(function(player, action, arg1, arg2)
	if action == "snapshot" then
		sendSnapshot(player)
	elseif action == "lock" then
		PlunderService.activateBaseLock(player)
	elseif action == "slap" then
		-- Find the nearest other player within 14 studs; the nearest one
		-- wins. Do nothing when no other player is in range.
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end
		local nearest = nil
		local nearestDistance = SLAP_RANGE
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local otherCharacter = other.Character
				local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
				if otherRoot then
					local distance = (otherRoot.Position - rootPart.Position).Magnitude
					if distance <= nearestDistance then
						nearest = other
						nearestDistance = distance
					end
				end
			end
		end
		if nearest then
			PlunderService.handleSlapPlayer(player, nearest)
		end
	elseif action == "rebirth" then
		LegendService.performPlayerRebirth(player)
	elseif action == "buyUpgrade" then
		UpgradeService.buyUpgrade(player, arg1)
	elseif action == "stealFrom" then
		PlunderService.startStealBrainrot(player, arg1, arg2)
	elseif action == "stealRival" then
		RivalCrewService.handleStealFromRivalPlot(player, arg1)
	end
end)

-- Keep the Stagehand, BootyCatalog, and LagoonLayout requires live so the
-- boot keeps them loaded for the TOUR steps and the shared contracts.
local _keepLoaded = { Stagehand, BootyCatalog, LagoonLayout, LagoonUpdate }

print("[Rotbeard's Lagoon] Server booted. 40 brainrots, 3 events, rival crew live.")
