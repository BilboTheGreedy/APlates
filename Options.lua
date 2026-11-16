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

local function cvar(text, name)
	return {
		text = text, checked = ns.CVarOn(name),
		func = function()
			if not ns.SetCVar(name, ns.CVarOn(name) and "0" or "1") then
				ns.Print("will change after combat")
			end
		end,
	}
end

function ns.Entries()
	local db = ns.db
	local entries = {
		{ text = "APlates", title = true },
		UI.Check(db, "enabled", "Restyle nameplates", changed),
		UI.Check(db, "classColor", "Class colours on players", changed),
		UI.Check(db, "threat", "Colour by threat", changed),
		UI.Check(db, "healthText", "Health percent", changed),
		UI.Check(db, "level", "Level", changed),
		UI.Check(db, "castbar", "Cast bar", changed),
		UI.Check(db, "debuffs", "Debuffs", changed),
		UI.Check(db, "ownOnly", "Only my debuffs", changed),
		UI.Check(db, "raidIcon", "Raid target icon", changed),
		UI.Check(db, "quest", "Quest mob marker", changed),
		UI.Check(db, "friendlyNames", "Friendly plates as names only", changed),
		{ text = "Game settings", title = true },
		cvar("Show enemy plates", "nameplateShowEnemies"),
		cvar("Show friendly plates", "nameplateShowFriends"),
		cvar("Always show plates", "nameplateShowAll"),
		cvar("Stack plates instead of overlapping", "nameplateMotion"),
		{
			text = "Click through enemy plates", checked = ns.ClickThrough(true),
			func = function() ns.SetClickThrough(true, not ns.ClickThrough(true)) end,
		},
		{
			text = "Click through friendly plates", checked = ns.ClickThrough(false),
			func = function() ns.SetClickThrough(false, not ns.ClickThrough(false)) end,
		},
	}
	pick(entries, "Width", "width", { 90, 105, 120, 140, 160 })
	pick(entries, "Height", "height", { 8, 11, 14, 17 })
	pick(entries, "Text size", "fontSize", { 9, 10, 11, 12 })
	pick(entries, "Target size", "targetScale", { 1, 1.15, 1.3 }, "x")
	for _, e in ipairs(UI.ScaleEntries(db, changed)) do entries[#entries + 1] = e end
	return entries
end

function ns.OpenOptions(at)
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
