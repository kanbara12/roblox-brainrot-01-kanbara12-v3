-- BootyCatalog: the 40 original pirate-lagoon brainrots of Rotbeard's Lagoon.
-- Every name is invented for this game. No canonical Steal-a-Brainrot names.
-- Rarity ladder: COMMON -> RARE -> EPIC -> LEGENDARY -> MYTHIC -> CAPTAIN -> LEGEND.
-- Mutations: GOLDEN x2, PEARL x3, CURSED x5, GHOST x10.
local BootyCatalog = {}

BootyCatalog.RARITY_ORDER = { "COMMON", "RARE", "EPIC", "LEGENDARY", "MYTHIC", "CAPTAIN", "LEGEND" }

BootyCatalog.RARITY_COLORS = {
	COMMON = Color3.fromRGB(180, 180, 180),
	RARE = Color3.fromRGB(80, 160, 255),
	EPIC = Color3.fromRGB(170, 90, 255),
	LEGENDARY = Color3.fromRGB(255, 170, 0),
	MYTHIC = Color3.fromRGB(255, 60, 120),
	CAPTAIN = Color3.fromRGB(255, 60, 60),
	LEGEND = Color3.fromRGB(255, 215, 0),
}

BootyCatalog.RARITY_WEIGHTS = {
	COMMON = 45, RARE = 25, EPIC = 15, LEGENDARY = 8, MYTHIC = 4, CAPTAIN = 2, LEGEND = 1,
}

BootyCatalog.MUTATIONS = {
	{ name = "GOLDEN", mult = 2, color = Color3.fromRGB(255, 215, 0) },
	{ name = "PEARL", mult = 3, color = Color3.fromRGB(220, 240, 255) },
	{ name = "CURSED", mult = 5, color = Color3.fromRGB(160, 60, 255) },
	{ name = "GHOST", mult = 10, color = Color3.fromRGB(180, 255, 240) },
}

-- id, name, rarity, cost, income per second, rig shape, body color, accent color, joke
BootyCatalog.BRAINROTS = {
	{ id = 1, name = "Barnacle Barry", rarity = "COMMON", cost = 10, income = 1, shape = "Crab", body = Color3.fromRGB(150, 120, 90), accent = Color3.fromRGB(90, 70, 50), joke = "I came with the ship. Literally." },
	{ id = 2, name = "Sardine Sorbet", rarity = "COMMON", cost = 25, income = 2, shape = "Fish", body = Color3.fromRGB(180, 200, 220), accent = Color3.fromRGB(255, 150, 180), joke = "Cold, tiny, and somehow in charge." },
	{ id = 3, name = "Minnow Meringue", rarity = "COMMON", cost = 50, income = 4, shape = "Fish", body = Color3.fromRGB(255, 240, 200), accent = Color3.fromRGB(255, 180, 120), joke = "Sweet, small, slightly soggy." },
	{ id = 4, name = "Clam Chowder", rarity = "COMMON", cost = 90, income = 7, shape = "Crab", body = Color3.fromRGB(220, 200, 170), accent = Color3.fromRGB(255, 120, 60), joke = "He is the soup now." },
	{ id = 5, name = "Guppy Guacamole", rarity = "COMMON", cost = 150, income = 11, shape = "Fish", body = Color3.fromRGB(120, 200, 80), accent = Color3.fromRGB(255, 220, 60), joke = "Extra chips not included." },
	{ id = 6, name = "Pelican Pancake", rarity = "RARE", cost = 250, income = 18, shape = "Bird", body = Color3.fromRGB(240, 220, 180), accent = Color3.fromRGB(255, 140, 40), joke = "His beak holds the whole treasury." },
	{ id = 7, name = "Cod Crouton", rarity = "RARE", cost = 400, income = 28, shape = "Fish", body = Color3.fromRGB(200, 160, 100), accent = Color3.fromRGB(120, 80, 40), joke = "Crunchy on the outside, rich inside." },
	{ id = 8, name = "Mussel Muffin", rarity = "RARE", cost = 600, income = 42, shape = "Crab", body = Color3.fromRGB(80, 80, 110), accent = Color3.fromRGB(200, 160, 255), joke = "Baked at the bottom of the sea." },
	{ id = 9, name = "Herring Hummus", rarity = "RARE", cost = 900, income = 60, shape = "Fish", body = Color3.fromRGB(230, 210, 160), accent = Color3.fromRGB(180, 120, 60), joke = "Dip him in doubloons." },
	{ id = 10, name = "Seagull Sourdough", rarity = "EPIC", cost = 1500, income = 95, shape = "Bird", body = Color3.fromRGB(240, 240, 240), accent = Color3.fromRGB(255, 190, 60), joke = "He stole my sandwich AND my savings." },
	{ id = 11, name = "Oyster Oreo", rarity = "EPIC", cost = 2200, income = 140, shape = "Crab", body = Color3.fromRGB(60, 60, 70), accent = Color3.fromRGB(255, 255, 255), joke = "Twist him open, find a pearl. Or a lawsuit." },
	{ id = 12, name = "Crab Cakes", rarity = "EPIC", cost = 3200, income = 200, shape = "Crab", body = Color3.fromRGB(255, 90, 60), accent = Color3.fromRGB(255, 200, 60), joke = "Two claws, zero manners, endless cash." },
	{ id = 13, name = "Eel Eclair", rarity = "EPIC", cost = 4500, income = 290, shape = "Snake", body = Color3.fromRGB(120, 60, 160), accent = Color3.fromRGB(255, 220, 130), joke = "Slippery, sweet, and fully charged." },
	{ id = 14, name = "Starfish Salsa", rarity = "EPIC", cost = 6000, income = 400, shape = "Seal", body = Color3.fromRGB(255, 140, 90), accent = Color3.fromRGB(255, 220, 80), joke = "Five arms, all of them dancing." },
	{ id = 15, name = "Jellyfish Jam", rarity = "LEGENDARY", cost = 9000, income = 550, shape = "Ghost", body = Color3.fromRGB(255, 150, 200), accent = Color3.fromRGB(255, 220, 240), joke = "Do not toast him. He toasts back." },
	{ id = 16, name = "Lobster Linguine", rarity = "LEGENDARY", cost = 13000, income = 780, shape = "Crab", body = Color3.fromRGB(230, 60, 40), accent = Color3.fromRGB(255, 220, 100), joke = "Al dente and absolutely loaded." },
	{ id = 17, name = "Seahorse Scone", rarity = "LEGENDARY", cost = 18000, income = 1100, shape = "Seal", body = Color3.fromRGB(255, 200, 90), accent = Color3.fromRGB(200, 120, 220), joke = "Tiny knight, giant bank account." },
	{ id = 18, name = "Turtle Tiramisu", rarity = "LEGENDARY", cost = 25000, income = 1500, shape = "Turtle", body = Color3.fromRGB(90, 160, 90), accent = Color3.fromRGB(200, 150, 100), joke = "Slow? Yes. Broke? Never." },
	{ id = 19, name = "Puffin Pizza", rarity = "LEGENDARY", cost = 30000, income = 1900, shape = "Bird", body = Color3.fromRGB(40, 40, 50), accent = Color3.fromRGB(255, 120, 40), joke = "Delivered in 30 minutes or your doubloons back." },
	{ id = 20, name = "Octopus Omelette", rarity = "MYTHIC", cost = 45000, income = 2600, shape = "Octo", body = Color3.fromRGB(180, 100, 200), accent = Color3.fromRGB(255, 180, 80), joke = "Eight arms, eight bank accounts." },
	{ id = 21, name = "Narwhal Nacho", rarity = "MYTHIC", cost = 65000, income = 3600, shape = "Shark", body = Color3.fromRGB(140, 180, 230), accent = Color3.fromRGB(255, 210, 60), joke = "A unicorn that learned to swim. And invest." },
	{ id = 22, name = "Manatee Macaron", rarity = "MYTHIC", cost = 90000, income = 5000, shape = "Seal", body = Color3.fromRGB(200, 170, 210), accent = Color3.fromRGB(255, 150, 200), joke = "Round, calm, and richer than you." },
	{ id = 23, name = "Ray Ravioli", rarity = "MYTHIC", cost = 120000, income = 6800, shape = "Fish", body = Color3.fromRGB(90, 120, 200), accent = Color3.fromRGB(255, 230, 150), joke = "He glides. The money follows." },
	{ id = 24, name = "Whale Waffle", rarity = "MYTHIC", cost = 150000, income = 9000, shape = "Shark", body = Color3.fromRGB(80, 110, 180), accent = Color3.fromRGB(255, 200, 100), joke = "The biggest breakfast in the lagoon." },
	{ id = 25, name = "Parrot Pistachio", rarity = "CAPTAIN", cost = 220000, income = 13000, shape = "Bird", body = Color3.fromRGB(80, 200, 90), accent = Color3.fromRGB(255, 60, 60), joke = "Polly wants a doubloon. Polly gets ten." },
	{ id = 26, name = "Mermaid Marmalade", rarity = "CAPTAIN", cost = 300000, income = 18000, shape = "Ghost", body = Color3.fromRGB(255, 170, 140), accent = Color3.fromRGB(80, 200, 255), joke = "Her song sinks ships and raises rent." },
	{ id = 27, name = "Sharkbait Sherry", rarity = "CAPTAIN", cost = 420000, income = 25000, shape = "Shark", body = Color3.fromRGB(120, 130, 150), accent = Color3.fromRGB(255, 80, 80), joke = "She is the bait. You are the catch." },
	{ id = 28, name = "Treasure Chestnut", rarity = "CAPTAIN", cost = 550000, income = 34000, shape = "Chest", body = Color3.fromRGB(160, 110, 50), accent = Color3.fromRGB(255, 215, 0), joke = "Open him and retire forever." },
	{ id = 29, name = "Cannonball Carl", rarity = "CAPTAIN", cost = 700000, income = 46000, shape = "Seal", body = Color3.fromRGB(50, 50, 55), accent = Color3.fromRGB(255, 150, 40), joke = "Launched once. Never came down. Still earning." },
	{ id = 30, name = "Doubloon Dolphin", rarity = "CAPTAIN", cost = 800000, income = 60000, shape = "Fish", body = Color3.fromRGB(140, 170, 230), accent = Color3.fromRGB(255, 215, 0), joke = "He prints money by jumping through it." },
	{ id = 31, name = "Rum Raisin", rarity = "LEGEND", cost = 1200000, income = 85000, shape = "Ghost", body = Color3.fromRGB(120, 70, 140), accent = Color3.fromRGB(255, 190, 80), joke = "Aged 300 years. Worth every second." },
	{ id = 32, name = "Sailor Sundae", rarity = "LEGEND", cost = 1800000, income = 120000, shape = "Seal", body = Color3.fromRGB(255, 240, 230), accent = Color3.fromRGB(255, 90, 140), joke = "Three scoops of pure profit." },
	{ id = 33, name = "Coral Croissant", rarity = "LEGEND", cost = 2500000, income = 170000, shape = "Crab", body = Color3.fromRGB(255, 160, 120), accent = Color3.fromRGB(255, 90, 150), joke = "Flaky, fabulous, and fully reef-financed." },
	{ id = 34, name = "Kraken Ketchup", rarity = "LEGEND", cost = 3200000, income = 240000, shape = "Octo", body = Color3.fromRGB(90, 40, 140), accent = Color3.fromRGB(255, 60, 60), joke = "He squeezes the whole ocean for cash." },
	{ id = 35, name = "Pirate Pretzel", rarity = "LEGEND", cost = 4000000, income = 330000, shape = "Snake", body = Color3.fromRGB(200, 150, 70), accent = Color3.fromRGB(255, 220, 120), joke = "Twisted, salty, and sailing in gold." },
	{ id = 36, name = "Anchovy Admiral", rarity = "LEGEND", cost = 5000000, income = 450000, shape = "Fish", body = Color3.fromRGB(70, 90, 140), accent = Color3.fromRGB(255, 215, 0), joke = "The smallest admiral. The biggest fleet." },
	{ id = 37, name = "Cap'n Crumblo", rarity = "LEGEND", cost = 7000000, income = 620000, shape = "Bird", body = Color3.fromRGB(140, 90, 50), accent = Color3.fromRGB(255, 60, 60), joke = "His hat is bigger than your house." },
	{ id = 38, name = "Ghost Galleon", rarity = "LEGEND", cost = 10000000, income = 900000, shape = "Ghost", body = Color3.fromRGB(180, 220, 230), accent = Color3.fromRGB(120, 240, 220), joke = "A ship that sailed off the map. Into the bank." },
	{ id = 39, name = "Rotbeard the Rotten", rarity = "LEGEND", cost = 15000000, income = 1300000, shape = "Chest", body = Color3.fromRGB(60, 50, 70), accent = Color3.fromRGB(80, 230, 130), joke = "The lagoon is named after him. He charges rent." },
	{ id = 40, name = "The Golden Kraken", rarity = "LEGEND", cost = 25000000, income = 2000000, shape = "Octo", body = Color3.fromRGB(255, 200, 40), accent = Color3.fromRGB(255, 120, 40), joke = "Ten arms. One crown. Zero mercy." },
}

function BootyCatalog.getBrainrotDefinition(id)
	for _, def in ipairs(BootyCatalog.BRAINROTS) do
		if def.id == id then
			return def
		end
	end
	return nil
end

function BootyCatalog.getRarityColor(rarity)
	return BootyCatalog.RARITY_COLORS[rarity] or Color3.fromRGB(255, 255, 255)
end

function BootyCatalog.getMutationMultiplier(mutationName)
	for _, m in ipairs(BootyCatalog.MUTATIONS) do
		if m.name == mutationName then
			return m.mult
		end
	end
	return 1
end

function BootyCatalog.getMutationColor(mutationName)
	for _, m in ipairs(BootyCatalog.MUTATIONS) do
		if m.name == mutationName then
			return m.color
		end
	end
	return Color3.fromRGB(255, 255, 255)
end

function BootyCatalog.getBrainrotCost(def, mutationName)
	return math.floor(def.cost * BootyCatalog.getMutationMultiplier(mutationName))
end

function BootyCatalog.calculateBrainrotIncome(def, mutationName, rebirthMultiplier)
	local base = def.income * BootyCatalog.getMutationMultiplier(mutationName)
	return math.floor(base * (rebirthMultiplier or 1))
end

function BootyCatalog.rollRarityTier()
	local total = 0
	for _, w in pairs(BootyCatalog.RARITY_WEIGHTS) do
		total += w
	end
	local roll = math.random(1, total)
	local running = 0
	for _, rarity in ipairs(BootyCatalog.RARITY_ORDER) do
		running += BootyCatalog.RARITY_WEIGHTS[rarity]
		if roll <= running then
			return rarity
		end
	end
	return "COMMON"
end

function BootyCatalog.rollMutationModifier()
	local roll = math.random()
	if roll < 0.80 then
		return "NONE"
	elseif roll < 0.90 then
		return "GOLDEN"
	elseif roll < 0.95 then
		return "PEARL"
	elseif roll < 0.985 then
		return "CURSED"
	else
		return "GHOST"
	end
end

function BootyCatalog.pickRandomBrainrotOfRarity(rarity)
	local pool = {}
	for _, def in ipairs(BootyCatalog.BRAINROTS) do
		if def.rarity == rarity then
			table.insert(pool, def)
		end
	end
	if #pool == 0 then
		return BootyCatalog.BRAINROTS[1]
	end
	return pool[math.random(1, #pool)]
end

function BootyCatalog.formatMoney(amount)
	amount = math.floor(amount)
	if amount >= 1000000000 then
		return string.format("$%.2fB", amount / 1000000000)
	elseif amount >= 1000000 then
		return string.format("$%.2fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("$%.1fK", amount / 1000)
	else
		return "$" .. tostring(amount)
	end
end

return BootyCatalog
