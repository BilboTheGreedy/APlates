local _, ns = ...
local UI = ns.UI

local anchor

local function changed()
	ns:Fire("OPTIONS")
end

local function pick(entries, title, key, values, suffix)
	entries[#entries + 1] = { text = title, title = true }
	for _, v in ipairs(values) do
		entries[#entries + 1] = {
			text = v .. (suffix or ""), checked = ns.db[key] == v,
			func = function()
				ns.db[key] = v
				changed()
			end,
		}
	end
end

local function cvar(entries, text, ...)
	local name
	for i = 1, select("#", ...) do
		local n = select(i, ...)
		if ns.GetCVar(n) ~= nil then
			name = n
			break
		end
	end
	if not name then return end
	entries[#entries + 1] = {
		text = text, checked = ns.CVarOn(name),
		func = function()
			if not ns.SetCVar(name, ns.CVarOn(name) and "0" or "1") then
				ns.Print("will change after combat")
			end
		end,
	}
end

local function steps(entries, text, name, values)
	local now = tonumber(ns.GetCVar(name))
	if not now then return end
	entries[#entries + 1] = {
		text = text .. ": " .. now,
		func = function()
			local nxt = values[1]
			for i, v in ipairs(values) do
				if math.abs(v - now) < 0.001 then nxt = values[i % #values + 1] end
			end
			if not ns.SetCVar(name, tostring(nxt)) then ns.Print("will change after combat") end
		end,
	}
end

local function through(entries, text, enemy)
	if not C_NamePlate then return end
	local set = C_NamePlate.SetNamePlateFriendlyClickThrough
	if enemy then set = C_NamePlate.SetNamePlateEnemyClickThrough end
	if not set then return end
	entries[#entries + 1] = {
		text = text, checked = ns.ClickThrough(enemy),
		func = function() ns.SetClickThrough(enemy, not ns.ClickThrough(enemy)) end,
	}
end

function ns.Entries()
	local db = ns.db
	local entries = {
		{ text = "APlates", title = true },
		UI.Check(db, "enabled", "Restyle nameplates", changed),
		UI.Check(db, "classColor", "Class colours on players", changed),
		UI.Check(db, "threat", "Colour by threat", changed),
		UI.Check(db, "tank", "Tank colours (blue while I hold aggro)", changed),
		UI.Check(db, "healthText", "Health percent", changed),
		UI.Check(db, "level", "Level", changed),
		UI.Check(db, "castbar", "Cast bar", changed),
		UI.Check(db, "debuffs", "Debuffs", changed),
		UI.Check(db, "ownOnly", "Only my debuffs", changed),
		UI.Check(db, "raidIcon", "Raid target icon", changed),
		UI.Check(db, "quest", "Quest mob marker", changed),
		UI.Check(db, "friendlyNames", "Friendly plates as names only", changed),
		UI.Check(db, "fade", "Fade plates that are not my target", changed),
		{ text = "Game settings", title = true },
	}
	cvar(entries, "Show enemy plates", "nameplateShowEnemies")
	cvar(entries, "Show friendly plates", "nameplateShowFriends", "nameplateShowFriendlyPlayers")
	cvar(entries, "Show friendly NPC plates", "nameplateShowFriendlyNpcs", "nameplateShowFriendlyNPCs")
	cvar(entries, "Always show plates", "nameplateShowAll")
	cvar(entries, "Stack plates instead of overlapping", "nameplateMotion")
	cvar(entries, "Enemy totem plates", "nameplateShowEnemyTotems")
	cvar(entries, "Enemy pet plates", "nameplateShowEnemyPets")
	cvar(entries, "Personal resource bar", "nameplateShowSelf")
	steps(entries, "Plate distance", "nameplateMaxDistance", { 20, 30, 40, 60 })
	steps(entries, "Vertical spacing when stacked", "nameplateOverlapV", { 0.6, 0.8, 1.1, 1.4 })
	through(entries, "Click through enemy plates", true)
	through(entries, "Click through friendly plates", false)
	pick(entries, "Width", "width", { 90, 105, 120, 140, 160 })
	pick(entries, "Height", "height", { 8, 11, 14, 17 })
	pick(entries, "Text size", "fontSize", { 9, 10, 11, 12 })
	pick(entries, "Target size", "targetScale", { 1, 1.15, 1.3 }, "x")
	for _, e in ipairs(UI.ScaleEntries(db, changed)) do entries[#entries + 1] = e end
	return entries
end

function ns.OpenOptions(at)
	if not at and ACore.OpenPanel then
		ACore.OpenPanel("APlates")
		return
	end
	if not at then
		if not anchor then
			anchor = CreateFrame("Frame", nil, UIParent)
			anchor:SetSize(1, 1)
			anchor:SetPoint("CENTER", UIParent, "CENTER", -110, 260)
		end
		at = anchor
	end
	UI.Menu(at, ns.Entries())
end
