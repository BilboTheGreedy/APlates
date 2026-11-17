local _, ns = ...
local UI = ns.UI
local C = UI.colors
local IsSecret = ns.IsSecret

local plates = {}
local byPlate = {}
ns.plates = plates

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local MAX_AURAS = 5

local REACTION = {
	hostile = { 0.85, 0.2, 0.2 },
	neutral = { 0.95, 0.8, 0.2 },
	friendly = { 0.25, 0.75, 0.3 },
	tapped = { 0.5, 0.5, 0.5 },
	tanking = { 1, 0.45, 0.1 },
	pulling = { 1, 0.75, 0.3 },
	holding = { 0.25, 0.6, 1 },
}

local function plain(v)
	if IsSecret(v) then return nil end
	return v
end

local function call(fn, ...)
	if not fn then return nil end
	local ok, a, b, c, d, e, f, g, h, i = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c, d, e, f, g, h, i
end

local function isTrue(v)
	if IsSecret(v) then return false end
	return v and true or false
end

local logged = {}
local function note(what, err)
	local msg = what .. ": " .. tostring(err)
	if logged[msg] then return end
	logged[msg] = true
	if ABug and ABug.Log then pcall(ABug.Log, "caught", "APlates: " .. msg) end
end
ns.Note = note

local SCAN = 40

local function own(data)
	local mine = data.isFromPlayerOrPlayerPet
	if not IsSecret(mine) and mine then return true end
	local src = data.sourceUnit
	if not IsSecret(src) and (src == "player" or src == "pet" or src == "vehicle") then return true end
	return false
end

local function others(data)
	local mine = data.isFromPlayerOrPlayerPet
	if not IsSecret(mine) and mine == false then return true end
	local src = data.sourceUnit
	if not IsSecret(src) and type(src) == "string" then return src ~= "player" and src ~= "pet" and src ~= "vehicle" end
	return false
end

local function readable(data)
	if type(data) ~= "table" or IsSecret(data) then return false end
	if issecrettable then
		local ok, hidden = pcall(issecrettable, data)
		if ok and hidden then return false end
	end
	return true
end

local function byIndex(unit, filter, max, out, mine)
	local fn = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not fn then return end
	for i = 1, mine and SCAN or max do
		local data = fn(unit, i, filter)
		if data == nil then return end
		if readable(data) and (not mine or own(data)) then out[#out + 1] = data end
		if #out >= max then return end
	end
end

local function byList(unit, filter, max, out, mine)
	local fn = C_UnitAuras and C_UnitAuras.GetUnitAuras
	if not fn then return end
	local list = fn(unit, filter, not mine and max or nil)
	if not readable(list) then return end
	for i = 1, #list do
		if #out >= max then return end
		local data = list[i]
		if readable(data) and (not mine or own(data)) then out[#out + 1] = data end
	end
end

local function slots(unit, max, out, _, ...)
	for i = 1, select("#", ...) do
		if #out >= max then return end
		local data = C_UnitAuras.GetAuraDataBySlot(unit, (select(i, ...)))
		if readable(data) then out[#out + 1] = data end
	end
end

local function bySlots(unit, filter, max, out)
	if not (C_UnitAuras and C_UnitAuras.GetAuraSlots and C_UnitAuras.GetAuraDataBySlot) then return end
	slots(unit, max, out, C_UnitAuras.GetAuraSlots(unit, filter, max))
end

local function byEach(unit, filter, max, out)
	if not (AuraUtil and AuraUtil.ForEachAura) then return end
	AuraUtil.ForEachAura(unit, filter, max, function(data)
		if readable(data) then out[#out + 1] = data end
		return #out >= max
	end, true)
end

local function byOld(unit, filter, max, out)
	local fn = UnitBuff
	if filter:find("HARMFUL") then fn = UnitDebuff end
	if not fn then fn = UnitAura end
	if not fn then return end
	for i = 1, max do
		local name, icon, count, kind, duration, expires, source = fn(unit, i, filter)
		if not IsSecret(name) and not name then return end
		out[#out + 1] = {
			name = name, icon = icon, applications = count, dispelName = kind, duration = duration,
			expirationTime = expires, sourceUnit = source,
		}
	end
end

local METHODS = {
	{ "GetUnitAuras", byList }, { "GetAuraDataByIndex", byIndex }, { "GetAuraSlots", bySlots },
	{ "ForEachAura", byEach }, { "UnitAura", byOld },
}

local function gather(i, unit, filter, max, out, mine)
	local m = METHODS[i]
	local ok, err = pcall(m[2], unit, filter, max, out, mine)
	if not ok then note(m[1] .. " " .. filter, err) end
	return #out > 0
end

function ns.Auras(unit, filter, max)
	local out = {}
	if not max or max <= 0 then return out end
	if gather(1, unit, filter, max, out) then return out end
	if gather(2, unit, filter, max, out) then
		note("auras read through " .. METHODS[2][1], filter)
		return out
	end
	local base = filter:match("^(%u+)|PLAYER$")
	if base then
		for i = 1, 2 do
			if gather(i, unit, base, max, out, true) then
				note("own auras read through " .. METHODS[i][1], filter)
				return out
			end
		end
	end
	for i = 3, #METHODS do
		if gather(i, unit, filter, max, out) then
			note("auras read through " .. METHODS[i][1], filter)
			return out
		end
	end
	return out
end

function ns.AuraReport(unit)
	unit = unit or "target"
	local lines = { "auras on " .. unit .. ", combat " .. tostring(InCombatLockdown and InCombatLockdown() and true or false) }
	for _, filter in ipairs({ "HARMFUL", "HARMFUL|PLAYER" }) do
		for _, m in ipairs(METHODS) do
			local out = {}
			local ok, err = pcall(m[2], unit, filter, SCAN, out)
			local line = filter .. " " .. m[1] .. ": " .. (ok and #out or ("error " .. tostring(err)))
			local d = out[1]
			if d then
				line = line .. ", icon secret " .. tostring(IsSecret(d.icon)) .. ", id secret " .. tostring(IsSecret(d.auraInstanceID))
			end
			lines[#lines + 1] = line
		end
	end
	for _, line in ipairs(lines) do ns.Print(line) end
	if ABug and ABug.Log then pcall(ABug.Log, "caught", "APlates: " .. table.concat(lines, "; ")) end
	return lines
end

local function font(fs, size)
	local path, _, flags = fs:GetFont()
	if path then pcall(fs.SetFont, fs, path, size, flags ~= "" and flags or "OUTLINE") end
end

local function hideDefault(plate)
	local uf = plate.UnitFrame
	if not uf then return end
	if ns.db.enabled then
		pcall(uf.SetAlpha, uf, 0)
	else
		pcall(uf.SetAlpha, uf, 1)
	end
end

local function createAura(f, i)
	local a = CreateFrame("Frame", nil, f)
	a:SetSize(18, 14)
	UI.Fill(a, { 0, 0, 0, 1 })
	a.icon = a:CreateTexture(nil, "ARTWORK")
	a.icon:SetPoint("TOPLEFT", 1, -1)
	a.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	a.icon:SetTexCoord(0.08, 0.92, 0.2, 0.8)
	local ok, cd = pcall(CreateFrame, "Cooldown", nil, a, "CooldownFrameTemplate")
	if ok and cd then
		cd:SetAllPoints(a.icon)
		if cd.SetReverse then cd:SetReverse(true) end
		if cd.SetDrawEdge then cd:SetDrawEdge(false) end
		a.cd = cd
	else
		note("Cooldown", cd)
	end
	a.count = UI.Text(a, "GameFontHighlightSmall", "RIGHT")
	a.count:SetPoint("BOTTOMRIGHT", 2, -2)
	a:SetPoint("BOTTOMLEFT", f.health, "TOPLEFT", (i - 1) * 20, 14)
	a:Hide()
	return a
end

local function create(plate)
	local f = CreateFrame("Frame", nil, plate)
	f:SetPoint("CENTER", plate, "CENTER", 0, 0)
	f:SetFrameStrata("BACKGROUND")

	local health = UI.Bar(f, 11)
	health:SetPoint("LEFT")
	health:SetPoint("RIGHT")
	health:SetPoint("BOTTOM", 0, 0)
	health.bg:SetColorTexture(0.05, 0.05, 0.06, 0.9)
	health.edges = UI.Border(health, { 0, 0, 0, 1 })
	f.health = health

	f.name = UI.Text(f, "GameFontHighlightSmall", "CENTER")
	f.name:SetPoint("BOTTOM", health, "TOP", 0, 2)
	f.name:SetPoint("LEFT", -30, 0)
	f.name:SetPoint("RIGHT", 30, 0)

	f.level = UI.Text(f, "GameFontHighlightSmall", "RIGHT")
	f.level:SetPoint("RIGHT", health, "LEFT", -3, 0)

	f.raid = f:CreateTexture(nil, "OVERLAY")
	f.raid:SetSize(18, 18)
	f.raid:SetPoint("LEFT", health, "RIGHT", 4, 0)
	f.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	f.raid:Hide()

	f.quest = f:CreateTexture(nil, "OVERLAY")
	f.quest:SetSize(14, 14)
	f.quest:SetPoint("RIGHT", f.level, "LEFT", -1, 0)
	f.quest:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
	f.quest:Hide()

	local glow = {}
	for i = 1, 4 do glow[i] = UI.Tex(f, "OVERLAY", C.accent) end
	glow[1]:SetPoint("BOTTOMLEFT", health, "TOPLEFT", -1, 0) glow[1]:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 1, 0) glow[1]:SetHeight(1)
	glow[2]:SetPoint("TOPLEFT", health, "BOTTOMLEFT", -1, 0) glow[2]:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 1, 0) glow[2]:SetHeight(1)
	glow[3]:SetPoint("TOPRIGHT", health, "TOPLEFT", 0, 1) glow[3]:SetPoint("BOTTOMRIGHT", health, "BOTTOMLEFT", 0, -1) glow[3]:SetWidth(1)
	glow[4]:SetPoint("TOPLEFT", health, "TOPRIGHT", 0, 1) glow[4]:SetPoint("BOTTOMLEFT", health, "BOTTOMRIGHT", 0, -1) glow[4]:SetWidth(1)
	f.glow = glow

	local cast = UI.Bar(f, 8)
	cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -3)
	cast:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -3)
	cast.bg:SetColorTexture(0.05, 0.05, 0.06, 0.9)
	UI.Border(cast, { 0, 0, 0, 1 })
	cast.icon = cast:CreateTexture(nil, "ARTWORK")
	cast.icon:SetSize(12, 12)
	cast.icon:SetPoint("RIGHT", cast, "LEFT", -2, 0)
	cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cast.shield = cast:CreateTexture(nil, "ARTWORK", nil, 1)
	cast.shield:SetAllPoints(cast:GetStatusBarTexture() or cast)
	cast.shield:SetColorTexture(0.6, 0.6, 0.65, 1)
	cast.shield:SetAlpha(0)
	cast:Hide()
	f.cast = cast

	f.auras = {}
	f.plate = plate
	return f
end

local function layout(f)
	local db = ns.db
	f:SetSize(db.width, db.height + 14)
	f.health:SetHeight(db.height)
	f.cast:SetHeight(math.max(6, db.height - 3))
	f.cast.icon:SetSize(math.max(8, db.height + 1), math.max(8, db.height + 1))
	font(f.name, db.fontSize)
	font(f.level, db.fontSize)
	font(f.health.right, math.max(7, db.fontSize - 1))
	font(f.cast.left, math.max(7, db.fontSize - 2))
end

local function difficulty(level)
	local mine = plain(call(UnitLevel, "player")) or 60
	if level <= 0 then return 1, 0.1, 0.1 end
	local diff = level - mine
	if diff >= 5 then return 1, 0.1, 0.1 end
	if diff >= 3 then return 1, 0.5, 0.25 end
	if diff >= -2 then return 1, 0.82, 0 end
	local green = plain(call(GetQuestGreenRange)) or 8
	if type(green) ~= "number" then green = 8 end
	if -diff <= green then return 0.25, 0.75, 0.25 end
	return 0.6, 0.6, 0.6
end

local function friendly(unit)
	local reaction = plain(call(UnitReaction, unit, "player"))
	if type(reaction) == "number" then return reaction >= 5, reaction end
	return isTrue(call(UnitIsFriend, "player", unit)), nil
end

local function color(f)
	local unit = f.unit
	local db = ns.db
	local c
	if isTrue(call(UnitIsPlayer, unit)) and db.classColor then
		local _, class = call(UnitClass, unit)
		class = plain(class)
		local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if cc then c = { cc.r, cc.g, cc.b } end
	end
	if not c then
		if isTrue(call(UnitIsTapDenied, unit)) then
			c = REACTION.tapped
		else
			local isFriend, reaction = friendly(unit)
			if isFriend then
				c = REACTION.friendly
			elseif reaction == 4 then
				c = REACTION.neutral
			else
				c = REACTION.hostile
			end
			if db.threat and not isFriend then
				local status = plain(call(UnitThreatSituation, "player", unit))
				if db.tank then
					if status == 3 then
						c = REACTION.holding
					elseif status == 2 then
						c = REACTION.pulling
					end
				elseif status == 3 then
					c = REACTION.tanking
				elseif status == 1 or status == 2 then
					c = REACTION.pulling
				end
			end
		end
	end
	f.health:SetColor(c[1], c[2], c[3], 1)
end

local function health(f)
	local unit = f.unit
	local bar = f.health
	local ok = pcall(bar.SetMinMaxValues, bar, 0, UnitHealthMax(unit))
	if ok then ok = pcall(bar.SetValue, bar, UnitHealth(unit)) end
	if not ok then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
	end
	local text = bar.right
	if not ns.db.healthText then
		text:SetText("")
		return
	end
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		if pcall(function() text:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)) end) then return end
	end
	local cur, max = plain(call(UnitHealth, unit)), plain(call(UnitHealthMax, unit))
	if type(cur) == "number" and type(max) == "number" and max > 0 then
		text:SetFormattedText("%.0f%%", cur / max * 100)
	else
		text:SetText("")
	end
end

local MARK = { elite = "+", rareelite = "R+", rare = "R", worldboss = "B" }

local function identity(f)
	local unit = f.unit
	local name = call(UnitName, unit)
	if not pcall(f.name.SetText, f.name, name) then f.name:SetText("") end
	local level = plain(call(UnitLevel, unit))
	local mark = MARK[plain(call(UnitClassification, unit)) or ""] or ""
	if ns.db.level and type(level) == "number" then
		local r, g, b = difficulty(level)
		f.level:SetText((level > 0 and level or "??") .. mark)
		f.level:SetTextColor(r, g, b)
	else
		f.level:SetText(mark)
		f.level:SetTextColor(1, 0.82, 0)
	end
	local nameOnly = ns.db.friendlyNames and friendly(unit)
	f.nameOnly = nameOnly and true or false
	f.health:SetShown(not nameOnly)
	f.level:SetShown(not nameOnly)
	if nameOnly then
		f.cast:Hide()
		local _, class = call(UnitClass, unit)
		class = plain(class)
		local cc = isTrue(call(UnitIsPlayer, unit)) and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if cc then
			f.name:SetTextColor(cc.r, cc.g, cc.b)
		else
			f.name:SetTextColor(0.6, 0.9, 0.6)
		end
	else
		f.name:SetTextColor(C.text[1], C.text[2], C.text[3])
	end
end

local function target(f)
	local on = isTrue(call(UnitIsUnit, f.unit, "target"))
	for i = 1, 4 do f.glow[i]:SetShown(on and not f.nameOnly) end
	f:SetScale((ns.db.scale or 1) * (on and (ns.db.targetScale or 1) or 1))
	local dim = ns.db.fade and not on and isTrue(call(UnitExists, "target"))
	f:SetAlpha(dim and 0.55 or 1)
end

local function raid(f)
	local index = ns.db.raidIcon and plain(call(GetRaidTargetIndex, f.unit))
	if type(index) == "number" and index >= 1 and index <= 8 and SetRaidTargetIconTexture then
		SetRaidTargetIconTexture(f.raid, index)
		f.raid:Show()
	else
		f.raid:Hide()
	end
end

local function quest(f)
	local show = false
	if ns.db.quest and AQuest and type(AQuest.IsQuestUnit) == "function" then
		local ok, v = pcall(AQuest.IsQuestUnit, f.unit)
		show = ok and v and true or false
	end
	if ns.db.quest and not show and C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
		show = isTrue(call(C_QuestLog.UnitIsRelatedToActiveQuest, f.unit))
	end
	f.quest:SetShown(show and not f.nameOnly)
end

local function setAura(f, slot, unit, data)
	local a = f.auras[slot]
	if not a then
		a = createAura(f, slot)
		f.auras[slot] = a
	end
	local drawn, why = pcall(a.icon.SetTexture, a.icon, data.icon)
	if not drawn then
		note("SetTexture", why)
		a.icon:SetTexture(QUESTION)
	end
	local id = data.auraInstanceID
	local stacks
	if id and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
		local ok, text = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id, 2, 99)
		if ok then stacks = text else note("GetAuraApplicationDisplayCount", text) end
	end
	if IsSecret(stacks) then
		a.count:SetText(stacks)
	elseif stacks then
		a.count:SetText(stacks)
	else
		local count = plain(data.applications)
		a.count:SetText(type(count) == "number" and count > 1 and count or "")
	end
	if a.cd then
		local duration, expires = plain(data.duration), plain(data.expirationTime)
		local done = false
		if type(duration) == "number" and type(expires) == "number" then
			if duration > 0 then
				a.cd:SetCooldown(expires - duration, duration)
				a.cd:Show()
			else
				a.cd:Hide()
			end
			done = true
		elseif data.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDuration and a.cd.SetCooldownFromDurationObject then
			local ok, obj = pcall(C_UnitAuras.GetAuraDuration, unit, data.auraInstanceID)
			if not ok then
				note("GetAuraDuration", obj)
			elseif obj then
				local err
				done, err = pcall(a.cd.SetCooldownFromDurationObject, a.cd, obj)
				if not done then note("SetCooldownFromDurationObject", err) end
			end
			if done then a.cd:Show() end
		elseif a.cd.SetCooldownFromExpirationTime then
			local err
			done, err = pcall(a.cd.SetCooldownFromExpirationTime, a.cd, data.expirationTime, data.duration)
			if not done then note("SetCooldownFromExpirationTime", err) end
			if done then a.cd:Show() end
		end
		if not done then a.cd:Hide() end
	end
	a:Show()
end

local function auras(f)
	local shown = 0
	if ns.db.debuffs and not f.nameOnly then
		local unit = f.unit
		local mine = ns.Auras(unit, "HARMFUL|PLAYER", MAX_AURAS)
		for i = 1, #mine do
			shown = shown + 1
			setAura(f, shown, unit, mine[i])
		end
		if not ns.db.ownOnly and shown < MAX_AURAS then
			local seen, blind = {}, false
			for i = 1, #mine do
				local id = plain(mine[i].auraInstanceID)
				if id then seen[id] = true else blind = true end
			end
			local all = ns.Auras(unit, "HARMFUL", 16)
			for i = 1, #all do
				if shown >= MAX_AURAS then break end
				local data = all[i]
				local id = plain(data.auraInstanceID)
				local dup
				if id and seen[id] then
					dup = true
				elseif #mine > 0 and own(data) then
					dup = true
				elseif blind and not id and not others(data) then
					dup = true
				end
				if not dup then
					shown = shown + 1
					setAura(f, shown, unit, data)
				end
			end
		end
	end
	for i = shown + 1, #f.auras do f.auras[i]:Hide() end
end

local function castInfo(unit)
	local name, text, icon, startMs, endMs, _, _, shield = call(UnitCastingInfo, unit)
	local channel = false
	if not IsSecret(name) and not name then
		name, text, icon, startMs, endMs, _, shield = call(UnitChannelInfo, unit)
		channel = true
	end
	if not IsSecret(name) and not name then return nil end
	local info = { name = name, text = text, icon = icon, channel = channel }
	info.shield = shield
	startMs, endMs = plain(startMs), plain(endMs)
	if type(startMs) == "number" and type(endMs) == "number" and endMs > startMs then
		info.start, info.finish = startMs / 1000, endMs / 1000
	else
		local fn = channel and UnitChannelDuration or UnitCastingDuration
		if fn then
			local ok, d = pcall(fn, unit)
			if ok and d then info.duration = d end
		end
	end
	return info
end

local function castUpdate(bar)
	local info = bar.info
	if not info or not info.start then return end
	local now = GetTime()
	if now >= info.finish then
		bar.info = nil
		bar:Hide()
		return
	end
	if info.channel then
		bar:SetValue(info.finish - now)
	else
		bar:SetValue(now - info.start)
	end
end

local function cast(f)
	local bar = f.cast
	local info = ns.db.castbar and not f.nameOnly and castInfo(f.unit)
	if not info then
		bar.info = nil
		bar:SetScript("OnUpdate", nil)
		bar:Hide()
		return
	end
	bar.info = info
	local label = info.text
	if not IsSecret(label) and (label == nil or label == "") then label = info.name end
	if not pcall(bar.left.SetText, bar.left, label) then
		pcall(bar.left.SetText, bar.left, info.name)
	end
	if not pcall(bar.icon.SetTexture, bar.icon, info.icon) then bar.icon:SetTexture(QUESTION) end
	bar:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
	local grey, shield = bar.shield, info.shield
	if not IsSecret(shield) then
		grey:SetAlpha(shield and 1 or 0)
	elseif not (grey.SetAlphaFromBoolean and pcall(grey.SetAlphaFromBoolean, grey, shield, 1, 0)) then
		grey:SetAlpha(0)
	end
	if info.start then
		bar:SetMinMaxValues(0, info.finish - info.start)
		bar:SetScript("OnUpdate", castUpdate)
		castUpdate(bar)
		if not bar.info then return end
	else
		bar:SetScript("OnUpdate", nil)
		local timed = false
		if info.duration and bar.SetTimerDuration then
			local dir = Enum and Enum.StatusBarTimerDirection
			local smooth = Enum and Enum.StatusBarInterpolation
			if dir and smooth then
				timed = pcall(bar.SetTimerDuration, bar, info.duration, smooth.Immediate, info.channel and dir.RemainingTime or dir.ElapsedTime)
			end
			if not timed then timed = pcall(bar.SetTimerDuration, bar, info.duration) end
		end
		if not timed then
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(1)
		end
	end
	bar:Show()
end

local function refresh(f)
	layout(f)
	identity(f)
	color(f)
	health(f)
	target(f)
	raid(f)
	quest(f)
	auras(f)
	cast(f)
end

local function getPlate(unit)
	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if ok then return plate end
end

local function added(unit)
	if IsSecret(unit) or type(unit) ~= "string" then return end
	local plate = getPlate(unit)
	if not plate then return end
	hideDefault(plate)
	if not ns.db.enabled then return end
	local f = byPlate[plate]
	if not f then
		f = create(plate)
		byPlate[plate] = f
	end
	f.unit = unit
	plates[unit] = f
	refresh(f)
	f:Show()
end

local function removed(unit)
	if IsSecret(unit) or type(unit) ~= "string" then return end
	local f = plates[unit]
	if not f then return end
	plates[unit] = nil
	f.unit = nil
	f.cast.info = nil
	f.cast:SetScript("OnUpdate", nil)
	f:Hide()
end

local function each(fn)
	for _, f in pairs(plates) do fn(f) end
end

local function on(event, fn)
	ns:On(event, function(unit, ...)
		if IsSecret(unit) or type(unit) ~= "string" then return end
		local f = plates[unit]
		if f then fn(f, ...) end
	end)
end

ns:On("NAME_PLATE_UNIT_ADDED", added)
ns:On("NAME_PLATE_UNIT_REMOVED", removed)

on("UNIT_HEALTH", health)
on("UNIT_MAXHEALTH", health)
on("UNIT_NAME_UPDATE", identity)
on("UNIT_LEVEL", identity)
on("UNIT_CLASSIFICATION_CHANGED", identity)
on("UNIT_FACTION", function(f)
	identity(f)
	color(f)
end)
on("UNIT_THREAT_LIST_UPDATE", color)
on("UNIT_THREAT_SITUATION_UPDATE", color)
on("UNIT_AURA", auras)
for _, event in ipairs({
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}) do
	on(event, cast)
end

ns:On("PLAYER_TARGET_CHANGED", function() each(target) end)
ns:On("RAID_TARGET_UPDATE", function() each(raid) end)
ns:On("QUEST_LOG_UPDATE", function()
	ns.Debounce("quest", 0.5, function() each(quest) end)
end)
ns:On("PLAYER_REGEN_ENABLED", function()
	each(color)
	each(auras)
end)

function ns.RefreshAll()
	if not C_NamePlate or not C_NamePlate.GetNamePlates then
		each(refresh)
		return
	end
	local ok, list = pcall(C_NamePlate.GetNamePlates)
	if not ok or type(list) ~= "table" then
		each(refresh)
		return
	end
	for _, plate in ipairs(list) do
		hideDefault(plate)
		local f = byPlate[plate]
		local unit = (f and f.unit) or plain(plate.namePlateUnitToken)
		if unit then
			if ns.db.enabled then
				added(unit)
			else
				removed(unit)
			end
		end
	end
end

ns:Listen("OPTIONS", ns.RefreshAll)
ns:Listen("LOGIN", ns.RefreshAll)
