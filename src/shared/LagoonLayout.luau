-- LagoonLayout: every fixed position of Rotbeard's Lagoon in one place, so the
-- services, the renderer and the HUD all agree on where things are.
local LagoonLayout = {}

LagoonLayout.CHUTE_START = Vector3.new(-70, 6.5, -40)
LagoonLayout.CHUTE_END = Vector3.new(70, 6.5, -40)
LagoonLayout.CHUTE_SPEED = 6 -- studs per second along the chute
LagoonLayout.CHUTE_LIFETIME = 25 -- seconds before an unsold brainrot sails off

LagoonLayout.HIGH_GROUND_Y = 10 -- standing above this survives the Kraken Surge
LagoonLayout.LIGHTHOUSE_TOP = Vector3.new(-100, 16, -30)
LagoonLayout.GALLEON_DECK = Vector3.new(100, 11, -30)

LagoonLayout.BASES = {
	A = { center = Vector3.new(-45, 2, 30), spawn = Vector3.new(-45, 3, 8) },
	B = { center = Vector3.new(45, 2, 30), spawn = Vector3.new(45, 3, 8) },
	R = { center = Vector3.new(0, 2, -70), spawn = Vector3.new(0, 3, -52) },
}

function LagoonLayout.getPedestalPosition(prefix, slot)
	local base = LagoonLayout.BASES[prefix]
	if not base then
		return Vector3.new(0, 2, 0)
	end
	local col = (slot - 1) % 4
	local row = math.floor((slot - 1) / 4)
	local x = base.center.X + (col - 1.5) * 9
	local z = base.center.Z + (row == 0 and -6 or 6)
	return Vector3.new(x, 2.6, z)
end

function LagoonLayout.getPedestalPart(prefix, slot)
	return workspace:FindFirstChild("Pedestal" .. prefix .. slot)
end

function LagoonLayout.getLockDome(prefix)
	return workspace:FindFirstChild("LockDome" .. prefix)
end

function LagoonLayout.isOnHighGround(character)
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return root.Position.Y > LagoonLayout.HIGH_GROUND_Y
end

return LagoonLayout
