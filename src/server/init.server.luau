-- init.server: boots Rotbeard's Lagoon. Creates the LagoonAction remote,
-- paints the world sign and pedestal numbers, fills the rival crew's deck,
-- starts every loop, and wires player join/leave plus client actions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LagoonAction = Instance.new("RemoteEvent")
LagoonAction.Name = "LagoonAction"
LagoonAction.Parent = ReplicatedStorage

-- Created here, before any require, so the client never waits on a remote
-- that only appears after the require chain (see PirateState).
local LagoonUpdate = Instance.new("RemoteEvent")
LagoonUpdate.Name = "LagoonUpdate"
LagoonUpdate.Parent = ReplicatedStorage

local BootyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BootyCatalog"))
local RigBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigBuilder"))
local LagoonLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LagoonLayout"))
local PirateState = require(script.Parent.PirateState)
local TreasureChuteService = require(script.Parent.TreasureChuteService)
local DoubloonService = require(script.Parent.DoubloonService)
local PlunderService = require(script.Parent.PlunderService)
local StormService = require(script.Parent.StormService)
local RivalCrewService = require(script.Parent.RivalCrewService)
local LegendService = require(script.Parent.LegendService)
local UpgradeService = require(script.Parent.UpgradeService)
local BountyService = require(script.Parent.BountyService)
local Stagehand = require(script.Parent.Stagehand)

RigBuilder.paintLagoonSign()
for _, base in ipairs({ "A", "B", "R" }) do
	RigBuilder.paintPedestalNumbers(base)
end

RivalCrewService.populateSoloRivalPlot()
TreasureChuteService.startChuteLoop()
DoubloonService.startIncomeLoop()
StormService.startEventScheduler()

task.spawn(function()
	while true do
		task.wait(5)
		PlunderService.expireBaseLocks()
	end
end)

local function sendSnapshot(player)
	local state = PirateState.getState(player)
	if not state then return end
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
		remaining = PirateState.getBaseLockRemaining(player),
	})
end

local function onPlayerAdded(player)
	PirateState.initPlayerState(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(1)
		UpgradeService.applyAllUpgradesToCharacter(player)
		local st = PirateState.getState(player)
		if st and st.rebirths > 0 then
			LegendService.applyRebirthAura(player)
		end
	end)
	task.wait(1)
	sendSnapshot(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	PirateState.removePlayerState(player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

LagoonAction.OnServerEvent:Connect(function(player, action, arg1, arg2)
	if action == "snapshot" then
		sendSnapshot(player)
	elseif action == "lock" then
		PlunderService.activateBaseLock(player)
	elseif action == "slap" then
		local nearest = nil
		local nearestDist = 14
		local myChar = player.Character
		local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
		if myRoot then
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player and other.Character then
					local root = other.Character:FindFirstChild("HumanoidRootPart")
					if root then
						local dist = (root.Position - myRoot.Position).Magnitude
						if dist < nearestDist then
							nearestDist = dist
							nearest = other
						end
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

print("[Rotbeard's Lagoon] Server booted. 40 brainrots, 3 events, rival crew live.")
