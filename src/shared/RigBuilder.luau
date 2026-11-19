-- RigBuilder: builds the 3D multi-part rigs for every brainrot, its overhead
-- billboard, its mutation look, and the painted signs of the lagoon.
local BootyCatalog = require(script.Parent.BootyCatalog)

local RigBuilder = {}

local function addPart(model, name, size, color, offset, shape, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Shape = shape or Enum.PartType.Block
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CFrame = CFrame.new(offset)
	p.Parent = model
	return p
end

local function addEyes(model, y, z, spread, size)
	local eyeL = addPart(model, "EyeL", Vector3.new(size, size, size), Color3.fromRGB(255, 255, 255), Vector3.new(-spread, y, z), Enum.PartType.Ball)
	local eyeR = addPart(model, "EyeR", Vector3.new(size, size, size), Color3.fromRGB(255, 255, 255), Vector3.new(spread, y, z), Enum.PartType.Ball)
	addPart(model, "PupilL", Vector3.new(size * 0.5, size * 0.5, size * 0.5), Color3.fromRGB(20, 20, 20), Vector3.new(-spread, y, z + size * 0.55), Enum.PartType.Ball)
	addPart(model, "PupilR", Vector3.new(size * 0.5, size * 0.5, size * 0.5), Color3.fromRGB(20, 20, 20), Vector3.new(spread, y, z + size * 0.55), Enum.PartType.Ball)
	return eyeL, eyeR
end

function RigBuilder.buildBrainrotRig(def, mutationName)
	local model = Instance.new("Model")
	model.Name = def.name
	local body = def.body
	local accent = def.accent
	local shape = def.shape

	if shape == "Fish" then
		addPart(model, "Body", Vector3.new(3, 2.4, 4.5), body, Vector3.new(0, 1.6, 0), Enum.PartType.Ball)
		addPart(model, "Tail", Vector3.new(0.5, 2.2, 1.8), accent, Vector3.new(0, 1.6, -2.8), Enum.PartType.Block)
		addPart(model, "TopFin", Vector3.new(0.4, 1.4, 2), accent, Vector3.new(0, 3.2, -0.3), Enum.PartType.Block)
		addPart(model, "Belly", Vector3.new(2.2, 1.4, 3), Color3.fromRGB(255, 245, 220), Vector3.new(0, 0.9, 0.4), Enum.PartType.Ball)
		addEyes(model, 2.1, 2.1, 0.8, 0.7)
	elseif shape == "Bird" then
		addPart(model, "Body", Vector3.new(2.6, 3, 2.6), body, Vector3.new(0, 1.8, 0), Enum.PartType.Ball)
		addPart(model, "Beak", Vector3.new(1.4, 0.8, 1.6), Color3.fromRGB(255, 170, 40), Vector3.new(0, 1.9, 1.7), Enum.PartType.Block)
		addPart(model, "WingL", Vector3.new(0.4, 2, 2.4), accent, Vector3.new(-1.5, 1.8, 0), Enum.PartType.Block)
		addPart(model, "WingR", Vector3.new(0.4, 2, 2.4), accent, Vector3.new(1.5, 1.8, 0), Enum.PartType.Block)
		addPart(model, "Hat", Vector3.new(2, 0.5, 2), accent, Vector3.new(0, 3.5, 0), Enum.PartType.Block)
		addPart(model, "HatTop", Vector3.new(1.2, 1, 1.2), accent, Vector3.new(0, 4.2, 0), Enum.PartType.Block)
		addEyes(model, 2.4, 1.2, 0.7, 0.6)
	elseif shape == "Crab" then
		addPart(model, "Body", Vector3.new(4, 1.8, 3), body, Vector3.new(0, 1.2, 0), Enum.PartType.Ball)
		addPart(model, "ClawL", Vector3.new(1.4, 1.4, 1.4), accent, Vector3.new(-2.6, 1.4, 0.8), Enum.PartType.Ball)
		addPart(model, "ClawR", Vector3.new(1.4, 1.4, 1.4), accent, Vector3.new(2.6, 1.4, 0.8), Enum.PartType.Ball)
		addPart(model, "LegL1", Vector3.new(1.6, 0.4, 0.4), body, Vector3.new(-2.2, 0.7, -0.8), Enum.PartType.Block)
		addPart(model, "LegR1", Vector3.new(1.6, 0.4, 0.4), body, Vector3.new(2.2, 0.7, -0.8), Enum.PartType.Block)
		addPart(model, "LegL2", Vector3.new(1.6, 0.4, 0.4), body, Vector3.new(-2.2, 0.7, 0.8), Enum.PartType.Block)
		addPart(model, "LegR2", Vector3.new(1.6, 0.4, 0.4), body, Vector3.new(2.2, 0.7, 0.8), Enum.PartType.Block)
		addPart(model, "EyeStalkL", Vector3.new(0.3, 1, 0.3), body, Vector3.new(-0.8, 2.4, 0.6), Enum.PartType.Block)
		addPart(model, "EyeStalkR", Vector3.new(0.3, 1, 0.3), body, Vector3.new(0.8, 2.4, 0.6), Enum.PartType.Block)
		addEyes(model, 3, 0.7, 0.8, 0.6)
	elseif shape == "Octo" then
		addPart(model, "Head", Vector3.new(3.6, 3.4, 3.6), body, Vector3.new(0, 2.6, 0), Enum.PartType.Ball)
		for i = 1, 8 do
			local angle = (i - 1) * (math.pi * 2 / 8)
			local x = math.cos(angle) * 1.4
			local z = math.sin(angle) * 1.4
			addPart(model, "Tentacle" .. i, Vector3.new(0.7, 1.8, 0.7), accent, Vector3.new(x, 0.9, z), Enum.PartType.Block)
		end
		addPart(model, "Crown", Vector3.new(2.2, 0.6, 2.2), Color3.fromRGB(255, 215, 0), Vector3.new(0, 4.5, 0), Enum.PartType.Block)
		addEyes(model, 3, 1.7, 0.9, 0.7)
	elseif shape == "Shark" then
		addPart(model, "Body", Vector3.new(2.6, 2.6, 6), body, Vector3.new(0, 1.6, 0), Enum.PartType.Ball)
		addPart(model, "Fin", Vector3.new(0.4, 1.8, 2), accent, Vector3.new(0, 3.2, -0.5), Enum.PartType.Block)
		addPart(model, "TailFin", Vector3.new(0.4, 2.4, 1.6), accent, Vector3.new(0, 1.8, -3.4), Enum.PartType.Block)
		addPart(model, "Belly", Vector3.new(2, 1.6, 4.5), Color3.fromRGB(240, 240, 240), Vector3.new(0, 0.9, 0.2), Enum.PartType.Ball)
		addPart(model, "ToothRow", Vector3.new(1.6, 0.4, 0.8), Color3.fromRGB(255, 255, 255), Vector3.new(0, 1.2, 2.9), Enum.PartType.Block)
		addEyes(model, 2.2, 2.4, 0.8, 0.6)
	elseif shape == "Turtle" then
		addPart(model, "Shell", Vector3.new(4, 2.4, 4.6), body, Vector3.new(0, 1.6, 0), Enum.PartType.Ball)
		addPart(model, "ShellTop", Vector3.new(3, 1, 3.4), accent, Vector3.new(0, 2.9, 0), Enum.PartType.Ball)
		addPart(model, "Head", Vector3.new(1.4, 1.4, 1.4), body, Vector3.new(0, 1.6, 2.9), Enum.PartType.Ball)
		addPart(model, "FootL", Vector3.new(1, 0.8, 1.4), body, Vector3.new(-1.8, 0.5, 1.4), Enum.PartType.Ball)
		addPart(model, "FootR", Vector3.new(1, 0.8, 1.4), body, Vector3.new(1.8, 0.5, 1.4), Enum.PartType.Ball)
		addPart(model, "FootBackL", Vector3.new(1, 0.8, 1.4), body, Vector3.new(-1.8, 0.5, -1.6), Enum.PartType.Ball)
		addPart(model, "FootBackR", Vector3.new(1, 0.8, 1.4), body, Vector3.new(1.8, 0.5, -1.6), Enum.PartType.Ball)
		addEyes(model, 1.9, 3.5, 0.5, 0.5)
	elseif shape == "Chest" then
		addPart(model, "Box", Vector3.new(3.4, 2.4, 2.6), body, Vector3.new(0, 1.4, 0), Enum.PartType.Block)
		addPart(model, "Lid", Vector3.new(3.4, 1.2, 2.6), accent, Vector3.new(0, 3, 0), Enum.PartType.Block)
		addPart(model, "Trim", Vector3.new(3.6, 0.4, 2.8), Color3.fromRGB(255, 215, 0), Vector3.new(0, 2.4, 0), Enum.PartType.Block)
		addPart(model, "Lock", Vector3.new(0.9, 0.9, 0.5), Color3.fromRGB(255, 215, 0), Vector3.new(0, 2.2, 1.4), Enum.PartType.Ball)
		addPart(model, "GoldPile", Vector3.new(2.4, 0.8, 1.8), Color3.fromRGB(255, 215, 0), Vector3.new(0, 3.9, 0), Enum.PartType.Ball)
		addEyes(model, 1.6, 1.4, 0.8, 0.6)
	elseif shape == "Ghost" then
		addPart(model, "Body", Vector3.new(3, 3.6, 3), body, Vector3.new(0, 2.2, 0), Enum.PartType.Ball)
		addPart(model, "Skirt", Vector3.new(3.2, 1.2, 3.2), body, Vector3.new(0, 0.6, 0), Enum.PartType.Block)
		addPart(model, "WispL", Vector3.new(0.8, 2, 0.8), accent, Vector3.new(-1.8, 2, 0), Enum.PartType.Block)
		addPart(model, "WispR", Vector3.new(0.8, 2, 0.8), accent, Vector3.new(1.8, 2, 0), Enum.PartType.Block)
		addPart(model, "Halo", Vector3.new(2.4, 0.4, 2.4), Color3.fromRGB(255, 230, 120), Vector3.new(0, 4.4, 0), Enum.PartType.Block)
		addEyes(model, 2.6, 1.5, 0.8, 0.7)
	elseif shape == "Seal" then
		addPart(model, "Body", Vector3.new(2.6, 2.4, 4.4), body, Vector3.new(0, 1.5, 0), Enum.PartType.Ball)
		addPart(model, "Head", Vector3.new(1.8, 1.8, 1.8), body, Vector3.new(0, 2.2, 2.2), Enum.PartType.Ball)
		addPart(model, "FlipperL", Vector3.new(0.4, 1.2, 2), accent, Vector3.new(-1.4, 1.1, 0.6), Enum.PartType.Block)
		addPart(model, "FlipperR", Vector3.new(0.4, 1.2, 2), accent, Vector3.new(1.4, 1.1, 0.6), Enum.PartType.Block)
		addPart(model, "TailFluke", Vector3.new(2, 0.5, 1.4), accent, Vector3.new(0, 1, -2.4), Enum.PartType.Block)
		addPart(model, "Ball", Vector3.new(1.2, 1.2, 1.2), accent, Vector3.new(0, 3.4, 2.2), Enum.PartType.Ball)
		addEyes(model, 2.5, 3, 0.6, 0.5)
	else -- Snake
		addPart(model, "Seg1", Vector3.new(2.2, 2.2, 2.2), body, Vector3.new(0, 1.1, 0), Enum.PartType.Ball)
		addPart(model, "Seg2", Vector3.new(1.9, 1.9, 1.9), body, Vector3.new(0, 2.6, 0.3), Enum.PartType.Ball)
		addPart(model, "Head", Vector3.new(1.8, 1.6, 2), accent, Vector3.new(0, 4, 0.6), Enum.PartType.Ball)
		addPart(model, "Tongue", Vector3.new(0.3, 0.3, 1.2), Color3.fromRGB(255, 60, 90), Vector3.new(0, 3.8, 1.9), Enum.PartType.Block)
		addPart(model, "Rattle", Vector3.new(1, 1, 1), Color3.fromRGB(255, 215, 0), Vector3.new(0, 0.8, -1.4), Enum.PartType.Ball)
		addEyes(model, 4.3, 1.5, 0.6, 0.5)
	end

	local primary = model:FindFirstChild("Body") or model:FindFirstChild("Head") or model:GetChildren()[1]
	model.PrimaryPart = primary
	RigBuilder.applyMutationVisuals(model, mutationName)
	return model
end

function RigBuilder.applyMutationVisuals(model, mutationName)
	if mutationName == "NONE" or mutationName == nil then
		return
	end
	local color = BootyCatalog.getMutationColor(mutationName)
	local primary = model.PrimaryPart
	if mutationName == "GOLDEN" then
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") then
				child.Material = Enum.Material.Neon
				child.Color = Color3.fromRGB(255, 205, 40)
			end
		end
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 220, 80)
		sparkles.Parent = primary
	elseif mutationName == "PEARL" then
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") then
				child.Material = Enum.Material.Glass
				child.Transparency = 0.25
			end
		end
	elseif mutationName == "CURSED" then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(160, 60, 255)
		light.Range = 10
		light.Brightness = 2
		light.Parent = primary
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") and child.Name ~= "EyeL" and child.Name ~= "EyeR" then
				child.Color = Color3.fromRGB(90, 40, 140)
			end
		end
	elseif mutationName == "GHOST" then
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") then
				child.Transparency = 0.35
			end
		end
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(180, 255, 240)
		light.Range = 12
		light.Brightness = 2
		light.Parent = primary
	end
end

-- One billboard per rig, three lines inside a single label, so labels can
-- never overlap each other the way the old game's separate labels did.
function RigBuilder.replaceOverheadBillboard(model, def, mutationName, bottomLine)
	local primary = model.PrimaryPart
	if not primary then
		return nil
	end
	for _, child in ipairs(primary:GetChildren()) do
		if child:IsA("BillboardGui") then
			child:Destroy()
		end
	end
	return RigBuilder.attachOverheadBillboard(model, def, mutationName, bottomLine)
end

function RigBuilder.attachOverheadBillboard(model, def, mutationName, bottomLine)
	local primary = model.PrimaryPart
	if not primary then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "OverheadBillboard"
	gui.Size = UDim2.fromOffset(200, 78)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
	gui.AlwaysOnTop = true
	gui.Parent = primary
	local label = Instance.new("TextLabel")
	label.Name = "OverheadLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextWrapped = true
	label.RichText = true
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	local rarity = def.rarity
	local rarityHex = "#" .. BootyCatalog.getRarityColor(rarity):ToHex()
	local mutText = ""
	if mutationName ~= "NONE" and mutationName ~= nil then
		local mutHex = "#" .. BootyCatalog.getMutationColor(mutationName):ToHex()
		mutText = ' • <font color="' .. mutHex .. '">[' .. mutationName .. ']</font>'
	end
	label.Text = '<font color="#FFFFFF">' .. def.name .. '</font>\n'
		.. '<font color="' .. rarityHex .. '">' .. rarity .. '</font>' .. mutText .. '\n'
		.. '<font color="#FFE066">' .. bottomLine .. '</font>'
	label.Parent = gui
	return gui
end

function RigBuilder.paintLagoonSign()
	local board = workspace:FindFirstChild("SignBoard")
	if not board then
		return
	end
	-- Painted on BOTH faces: the old version only painted Front, so the
	-- sign was a dark blank board seen from behind (the spawn side).
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "LagoonSign"
		gui.Face = face
		gui.Parent = board
		local title = Instance.new("TextLabel")
		title.Name = "SignTitle"
		title.Size = UDim2.fromScale(1, 0.65)
		title.Position = UDim2.fromScale(0, 0.05)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(255, 215, 0)
		title.TextStrokeTransparency = 0
		title.Text = "ROTBEARD'S LAGOON"
		title.Parent = gui
		local sub = Instance.new("TextLabel")
		sub.Name = "SignSub"
		sub.Size = UDim2.fromScale(1, 0.25)
		sub.Position = UDim2.fromScale(0, 0.7)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(255, 255, 255)
		sub.Text = "40 BRAINROTS  •  STEAL  •  LOCK  •  REBIRTH"
		sub.Parent = gui
	end
end

function RigBuilder.paintPedestalNumbers(prefix)
	for i = 1, 8 do
		local pad = workspace:FindFirstChild("Pedestal" .. prefix .. i)
		if pad then
			local gui = Instance.new("SurfaceGui")
			gui.Name = "PedestalNumber"
			gui.Face = Enum.NormalId.Top
			gui.Parent = pad
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBlack
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextStrokeTransparency = 0
			label.Text = tostring(i)
			label.Parent = gui
		end
	end
end

return RigBuilder
