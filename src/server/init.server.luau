local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local actionRemote = Instance.new("RemoteEvent")
actionRemote.Name = "LagoonAction"
actionRemote.Parent = ReplicatedStorage

local updateRemote = Instance.new("RemoteEvent")
updateRemote.Name = "LagoonUpdate"
updateRemote.Parent = ReplicatedStorage

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
		setupCharacter(player)
	end)
	if player.Character then
		task.spawn(function()
			setupCharacter(player)
		end)
	end
	task.delay(1, function()
		sendSnapshot(player)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	PirateState.removePlayerState(player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

RigBuilder.paintLagoonSign()
RigBuilder.paintPedestalNumbers("A")
RigBuilder.paintPedestalNumbers("B")
RigBuilder.paintPedestalNumbers("R")

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

actionRemote.OnServerEvent:Connect(function(player, action, arg1, arg2)
	if action == "snapshot" then
		sendSnapshot(player)
	elseif action == "lock" then
		PlunderService.activateBaseLock(player)
	elseif action == "slap" then
		local character = player.Character
		if not character then
			return
		end
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local nearest = nil
		local nearestDist = 14
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local otherChar = other.Character
				if otherChar then
					local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
					if otherHrp then
						local dist = (hrp.Position - otherHrp.Position).Magnitude
						if dist <= nearestDist then
							nearest = other
							nearestDist = dist
						end
					end
				end
			end
		end
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

print("[Rotbeard's Lagoon] Server booted. 40 brainrots, 3 events, rival crew live.")
