local ADDON, ns = ...

local defaults = {
	enabled = true,
	width = 120,
	height = 11,
	scale = 1,
	fontSize = 10,
	targetScale = 1.15,
	classColor = true,
	threat = true,
	healthText = true,
	level = true,
	castbar = true,
	debuffs = true,
	ownOnly = false,
	raidIcon = true,
	quest = true,
	friendlyNames = false,
	tank = false,
	fade = false,
}

ACore.New(ADDON, ns, { db = "APlatesDB", defaults = defaults, profile = true })

ACore.Register({
	name = "APlates",
	title = "APlates",
	slash = "/aplates",
	desc = "nameplates",
	toggle = function() ns.OpenOptions() end,
	options = function() return ns.Entries() end,
})

local queue = {}

function ns.Locked()
	return InCombatLockdown and InCombatLockdown() and true or false
end

function ns.Safe(key, fn)
	if ns.Locked() then
		queue[key] = fn
		return false
	end
	fn()
	return true
end

ns:On("PLAYER_REGEN_ENABLED", function()
	local run = queue
	queue = {}
	for _, fn in pairs(run) do pcall(fn) end
end)

function ns.GetCVar(name)
	local v
	if C_CVar and C_CVar.GetCVar then
		local ok, r = pcall(C_CVar.GetCVar, name)
		if ok then v = r end
	elseif GetCVar then
		local ok, r = pcall(GetCVar, name)
		if ok then v = r end
	end
	return v
end

function ns.SetCVar(name, value)
	return ns.Safe("cvar" .. name, function()
		if C_CVar and C_CVar.SetCVar then
			pcall(C_CVar.SetCVar, name, value)
		elseif SetCVar then
			pcall(SetCVar, name, value)
		end
	end)
end

function ns.CVarOn(name)
	local v = ns.GetCVar(name)
	return v == "1" or v == 1 or v == true
end

function ns.SetClickThrough(enemy, on)
	ns.Safe("click" .. (enemy and "e" or "f"), function()
		if not C_NamePlate then return end
		local fn = enemy and C_NamePlate.SetNamePlateEnemyClickThrough or C_NamePlate.SetNamePlateFriendlyClickThrough
		if fn then pcall(fn, on and true or false) end
	end)
end

function ns.ClickThrough(enemy)
	if not C_NamePlate then return false end
	local fn = enemy and C_NamePlate.GetNamePlateEnemyClickThrough or C_NamePlate.GetNamePlateFriendlyClickThrough
	if not fn then return false end
	local ok, v = pcall(fn)
	return ok and v and true or false
end

SLASH_APLATES1 = "/aplates"
SLASH_APLATES2 = "/apl"
SlashCmdList["APLATES"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "off" or msg == "on" then
		ns.db.enabled = msg == "on"
		ns:Fire("OPTIONS")
		ns.Print(ns.db.enabled and "on" or "off")
	elseif msg == "auras" then
		ns.AuraReport("target")
	elseif msg == "reset" then
		for k, v in pairs(defaults) do ns.db[k] = v end
		ns:Fire("OPTIONS")
	else
		ns.OpenOptions()
	end
end
