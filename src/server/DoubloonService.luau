-- DoubloonService: every brainrot on a deck earns doubloons every second.
-- The per-second value already includes the rebirth multiplier, the income
-- upgrade and the Golden Tide x2, so the payout is just that value.
local Players = game:GetService("Players")

local PirateState = require(script.Parent.PirateState)

local DoubloonService = {}

function DoubloonService.startIncomeLoop()
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				local perSecond = PirateState.getIncomePerSecond(player)
				if perSecond > 0 then
					PirateState.addCash(player, perSecond)
					PirateState.broadcast(player, { type = "tick", amount = perSecond })
				end
			end
		end
	end)
end

return DoubloonService
