local bar_template = mainForm:GetChildChecked("Bar", false)
local spell_template = mainForm:GetChildChecked("IconSpell", false)

local active_bars = {}
local active_buffs = {}
local tracking_objects_buffs = {}
local counter_buff = 0

local TRACKED_UNITS = {}

local DETECTED_CONTROL = {}

local IGNORED_IDS = {}

----------------------------------------------------------------------------------------------------
-- AOPanel support

local IsAOPanelEnabled = GetConfig("EnableAOPanel") or GetConfig("EnableAOPanel") == nil

local function onAOPanelStart(p)
	if IsAOPanelEnabled then
		local SetVal = { val1 = userMods.ToWString("CC"), class1 = "RelicCursed" }
		local params = { header = SetVal, ptype = "button", size = 32 }
		userMods.SendEvent("AOPANEL_SEND_ADDON",
			{ name = common.GetAddonName(), sysName = common.GetAddonName(), param = params })

		local cfgBtn = mainForm:GetChildChecked("ConfigButton", false)
		if cfgBtn then
			cfgBtn:Show(false)
		end
	end
end

local function onAOPanelLeftClick(p)
	if p.sender == common.GetAddonName() then
		UI.toggle()
	end
end

local function onAOPanelRightClick(p)
	if p.sender == common.GetAddonName() then
		ToggleDnd()
	end
end

local function onAOPanelChange(params)
	if params.unloading and params.name == "UserAddon/AOPanelMod" then
		local cfgBtn = mainForm:GetChildChecked("ConfigButton", false)
		if cfgBtn then
			cfgBtn:Show(true)
		end
	end
end

----------------------------------------------------------------------------------------------------


local function destroyBar(widget)
	if widget == nil then return end
	for k, v in pairs(active_bars) do
		if (v:GetName() == widget:GetName()) then
			table.remove(active_bars, k)
			v:DestroyWidget()
		end
	end

	for k, v in pairs(active_bars) do
		local tempPos = bar_template:GetPlacementPlain()
		tempPos.posY = tempPos.posY + ((tonumber(UI.get("Bars", "BarsHeight")) or 40) + 2) * (k - 1)
		tempPos.sizeX = tonumber(UI.get("Bars", "BarsWidth")) or 300
		WtSetPlace(v, tempPos)
		v:Show(k <= (tonumber(UI.get("Bars", "MaxBars")) or 6))
	end
end

local function removeActiveBuffById(buffId)
	local info = active_buffs[buffId]
	if (info == nil) then return false end
	if (info.castBar ~= nil) then info.castBar:FinishResizeEffect() end
	if (info.bar ~= nil) then
		destroyBar(info.bar)
		active_buffs[buffId] = nil
		return true
	end

	return false
end

local function onBuffRemovedDetected(removed_buff)
	if (not IGNORED_IDS[removed_buff.buffId]) then
		removeActiveBuffById(removed_buff.buffId)

		for k, v in pairs(DETECTED_CONTROL) do
			if v.id == removed_buff.buffId then
				DETECTED_CONTROL[k] = nil
			end
		end
	end
end

local function onPlayEffectFinished(e)
	if e.wtOwner then
		if e.wtOwner:GetName() ~= "ControlBar" then return end

		local bar = e.wtOwner:GetParent()
		e.wtOwner:FinishResizeEffect()

		for k, v in pairs(DETECTED_CONTROL) do
			if v.id == bar:GetName() then
				DETECTED_CONTROL[k] = nil
			end
		end

		if (bar ~= nil and e.wtOwner:GetName() == "ControlBar") then destroyBar(bar) end
	end
end

local function addBuff(info)
	local bar
	bar = mainForm:CreateWidgetByDesc(bar_template:GetWidgetDesc())
	counter_buff = counter_buff + 1

	bar:SetName("ControlBar" .. tostring(counter_buff))
	bar:Show(#active_bars < (tonumber(UI.get("Bars", "MaxBars")) or 6))
	table.insert(active_bars, bar)

	local buffBar
	buffBar = mainForm:CreateWidgetByDesc(mainForm:GetChildChecked("ControlBar", false):GetWidgetDesc())
	buffBar:Show(true)
	buffBar:SetName("ControlBar")
	bar:AddChild(buffBar)

	local settingHeight = tonumber(UI.get("Bars", "BarsHeight")) or 40
	local settingWidth = tonumber(UI.get("Bars", "BarsWidth")) or 300

	local tempPos = bar_template:GetPlacementPlain()
	tempPos.posY = tempPos.posY + (settingHeight + 2) * (#active_bars - 1)
	WtSetPlace(bar, tempPos)
	WtSetPlace(buffBar,
		{ sizeX = settingWidth, sizeY = settingHeight })

	if (info.buffInfo) then
		local objectId = info.buffInfo.objectId
		local buffId = info.buffInfo.buffId

		active_buffs[buffId] = {
			bar = bar,
			castBar = buffBar,
			objectId = objectId,
		}

		if (not info.ignoreBuffRemoved) then
			DETECTED_CONTROL[info.target .. info.name] = {
				id = buffId,
				count = 1,
			}

			if (not tracking_objects_buffs[objectId]) then
				tracking_objects_buffs[objectId] = {
					buffs = {
						buffId
					}
				}

				common.RegisterEventHandler(onBuffRemovedDetected, "EVENT_OBJECT_BUFF_REMOVED", {
					objectId = objectId
				})
			else
				table.insert(tracking_objects_buffs[objectId].buffs, buffId)
			end
		else
			DETECTED_CONTROL[info.target .. info.name] = {
				id = "ControlBar" .. tostring(counter_buff),
				count = 1,
			}
			IGNORED_IDS[buffId] = true
		end

		if (info.target == FromWS(object.GetName(avatar.GetId()))) then
			buffBar:SetBackgroundColor({ r = 0.0, g = 0.8, b = 0.0, a = 0.5 })
		elseif (info.alt_id and object.IsFriend(objectId) and object.IsEnemy(info.alt_id)) then
			buffBar:SetBackgroundColor({ r = 0.8, g = 0, b = 0, a = 0.5 })
		else
			buffBar:SetBackgroundColor({ r = 0.0, g = 0.6, b = 0.6, a = 0.5 })
		end
		WtSetPlace(buffBar, { alignX = 0, sizeX = settingWidth })
		local castBarPlacementEnd = buffBar:GetPlacementPlain()
		castBarPlacementEnd.sizeX = 0
		buffBar:PlayResizeEffect(buffBar:GetPlacementPlain(), castBarPlacementEnd, info.duration,
			EA_MONOTONOUS_INCREASE, true)
	end

	if (info.customColor) then
		buffBar:SetBackgroundColor(info.customColor)
	end

	local spell
	spell = mainForm:CreateWidgetByDesc(spell_template:GetWidgetDesc())
	WtSetPlace(spell,
		{ sizeX = settingWidth, sizeY = settingHeight })

	WtSetPlace(bar,
		{ sizeX = settingWidth, sizeY = settingHeight })

	local iconSize = settingHeight - 8

	if (info.texture) then
		spell:SetBackgroundTexture(info.texture)
	end

	bar:AddChild(spell)
	spell:Show(true)

	local castName = CreateWG("Label", "CastName", bar, true,
		{
			alignX = 0,
			sizeX = settingWidth - settingHeight,
			posX = iconSize + 6,
			highPosX = 0,
			alignY = 0,
			sizeY = 20,
			posY = 2,
			highPosY = 0
		})
	castName:SetFormat(userMods.ToWString(
		"<html><body alignx='left' aligny='bottom' fontsize='16' outline='1' shadow='1'><rs class='class'><r name='name'/></rs></body></html>"))
	castName:SetVal("name", info.name)
	castName:SetClassVal("class", "ColorWhite")

	local offsetTargetText = 0
	if (info.target) then offsetTargetText = 115 end

	local castUnit = CreateWG("Label", "CastUnit", bar, true,
		{
			alignX = 0,
			sizeX = (tonumber(UI.get("Bars", "BarsWidth")) or 300) - iconSize - offsetTargetText,
			posX = iconSize + 6,
			highPosX = 0,
			alignY = 1,
			sizeY = 20,
			posY = 0,
			highPosY = 2
		})
	castUnit:SetFormat(userMods.ToWString(
		"<html><body alignx='left' aligny='bottom' fontsize='13' outline='1' shadow='1'><rs class='class'><r name='name'/></rs></body></html>"))
	castUnit:SetVal("name", "Задело: " .. tostring(DETECTED_CONTROL[info.target .. info.name].count))
	castUnit:SetClassVal("class", "ColorWhite")

	DETECTED_CONTROL[info.target .. info.name].label = castUnit

	local castTarget = CreateWG("Label", "CastTarget", bar, true,
		{ alignX = 1, sizeX = 120, posX = 0, highPosX = 2, alignY = 0, sizeY = 20, posY = 18, highPosY = 0 })
	castTarget:SetFormat(userMods.ToWString(
		"<html><body alignx='right' aligny='bottom' fontsize='12' outline='1' shadow='1'><rs class='class'><r name='name'/></rs></body></html>"))
	castTarget:SetVal("name", info.target)
	castTarget:SetClassVal("class", "RelicCursed")

	bar:AddChild(castName)
	bar:AddChild(castUnit)
	bar:AddChild(castTarget)

	WtSetPlace(spell,
		{ alignX = 0, posX = 4, highPosX = 0, alignY = 0, posY = 4, highPosY = 0, sizeX = iconSize, sizeY = iconSize })

	bar:SetTransparentInput(true)
	buffBar:SetTransparentInput(true)
	spell:SetTransparentInput(true)
end

local function onBuff(p)
	local show = true
	local info = object.GetBuffInfo(p.buffId)
	if (not info) then return end

	if (show) then
		local buffObject = p.objectId
		local buffId = p.buffId

		if (object.IsExist(buffObject) and object.IsUnit(buffObject) and not unit.IsPlayer(buffObject)) then
			local info = object.GetBuffInfo(buffId)

			if (info and info.remainingMs ~= nil and info.remainingMs > 0) then
				local caster = ""
				if (info.producer.casterId) then caster = FromWS(object.GetName(info.producer.casterId)) end

				local buffName = FromWS(info.name)
				local finalSpellName = nil
				local texture = info.texture
				local duration = info.remainingMs

				if (buffName == nil or buffName == "") then return end

				if (info.producer) then
					if (info.producer.spellId) then
						local spellInfo = spellLib.GetDescription(info.producer.spellId)
						if (spellInfo) then
							finalSpellName = FromWS(spellInfo.name)
							local spellTexture = spellLib.GetIcon(info.producer.spellId)
							if (spellTexture) then
								texture = spellTexture
							end
						end
					end
				end

				local ignoreEvent = false

				if (buffName == "Экспрессия") then
					buffName = "Дезориентация"
					finalSpellName = "Экспрессия"
					duration = 2000
					ignoreEvent = true
				end

				if (buffName == "Вакуумный захват") then
					buffName = "Дезориентация"
					finalSpellName = "Паук-подавитель"
					duration = 3000
					ignoreEvent = true
				end

				if (finalSpellName == "Отвар дурман-травы") then
					finalSpellName = "Молния в бутылке"
				end

				if (finalSpellName == nil) then return end

				if (CONTROLS[finalSpellName] == nil or not contains(CONTROLS[finalSpellName], buffName)) then
					return
				end

				if (DETECTED_CONTROL[caster .. finalSpellName] ~= nil) then
					DETECTED_CONTROL[caster .. finalSpellName].count = DETECTED_CONTROL[caster .. finalSpellName].count +
						1
					DETECTED_CONTROL[caster .. finalSpellName].label:SetVal("name",
						"Задело: " .. tostring(DETECTED_CONTROL[caster .. finalSpellName].count))
					return
				end

				if (texture == nil) then
					local relatedTexture = GetGroupTexture("RELATED_TEXTURES", finalSpellName)
					if (relatedTexture ~= nil) then
						texture = relatedTexture
					end
				end

				local castInfo = {
					["name"] = finalSpellName,
					["unit"] = FromWS(object.GetName(buffObject)),
					["target"] = caster,
					["duration"] = duration,
					["buffInfo"] = p,
					["texture"] = texture,
					["alt_id"] = info.producer.casterId,
					["ignoreBuffRemoved"] = ignoreEvent
				}

				UI.registerTexture(FromWS(info.name), {
					buffId = info.buffId,
				})

				addBuff(castInfo)
			end
		end
	end
end

local function getUnits()
	local units = avatar.GetUnitList()
	table.insert(units, avatar.GetId())
	for _, id in ipairs(units) do
		if (not contains(TRACKED_UNITS, id)) then
			table.insert(TRACKED_UNITS, id)
			common.RegisterEventHandler(onBuff, "EVENT_OBJECT_BUFF_ADDED", {
				objectId = id
			})
		end
	end
end

local function onUnitsChanged(p)
	local spawned = p.spawned
	local despawned = p.despawned

	for i = 0, len(spawned) - 1, 1 do
		local id = spawned[i]
		if (id ~= nil) then
			-- Log("spawned " .. tostring(id) .. " " .. FromWS(object.GetName(id)))
			table.insert(TRACKED_UNITS, id)
			common.RegisterEventHandler(onBuff, "EVENT_OBJECT_BUFF_ADDED", {
				objectId = id
			})
		end
	end

	for i = 0, len(despawned) - 1, 1 do
		local id = despawned[i]
		if (id ~= nil) then
			-- Log("despawned " .. tostring(id) .. " " .. FromWS(object.GetName(id)))
			if (tracking_objects_buffs[id] ~= nil) then
				if (tracking_objects_buffs[id].buffs ~= nil) then
					for k, v in pairs(tracking_objects_buffs[id].buffs) do
						removeActiveBuffById(v)
					end
				end
				tracking_objects_buffs[id] = nil

				common.UnRegisterEventHandler(onBuffRemovedDetected, "EVENT_OBJECT_BUFF_REMOVED", {
					objectId = id
				})
			end
			for k, v in pairs(TRACKED_UNITS) do
				if (v == id) then
					table.remove(TRACKED_UNITS, k)
					common.UnRegisterEventHandler(onBuff, "EVENT_OBJECT_BUFF_ADDED", {
						objectId = id
					})
				end
			end
		end
	end
end

local function onSlash(p)
	local m = userMods.FromWString(p.text)
	local split_string = {}
	for w in m:gmatch("%S+") do table.insert(split_string, w) end

	if (split_string[1]:lower() == '/casts.chore') then
		UI.chore()
	end
end

function ToggleDnd()
	local info1 = bar_template:GetChildUnchecked("Info", false)
	if (bar_template:IsVisibleEx()) then
		DnD.Enable(bar_template, false)
		UI.dnd(false)

		bar_template:Show(false)
		bar_template:SetTransparentInput(true)

		spell_template:SetTransparentInput(true)

		local settingHeight = tonumber(UI.get("Bars", "BarsHeight")) or 40
		local settingWidth = tonumber(UI.get("Bars", "BarsWidth")) or 300

		for k, v in pairs(active_bars) do
			local tempPos = bar_template:GetPlacementPlain()
			tempPos.posY = tempPos.posY + ((tonumber(UI.get("Bars", "BarsHeight")) or 40) + 2) * (k - 1)
			WtSetPlace(v, tempPos)
			v:Show(k <= (tonumber(UI.get("Bars", "MaxBars")) or 6))
		end

		if (info1) then
			info1:Show(false)
		end

		Log("Drag & Drop - Off.")
	else
		DnD.Enable(bar_template, true)
		UI.dnd(true)

		bar_template:Show(true)
		bar_template:SetTransparentInput(false)
		spell_template:SetTransparentInput(false)

		for k, v in pairs(active_bars) do
			v:Show(false)
		end

		if (info1) then
			info1:Show(true)
		end

		Log("Drag & Drop - On.")
	end
end

local function onCfgLeft()
	if DnD:IsDragging() then
		return
	end

	UI.toggle()
end

local function onCfgRight()
	if DnD:IsDragging() then
		return
	end

	ToggleDnd()
end

local function setupUI()
	LANG = common.GetLocalization() or "rus"
	UI.init("ControlChecker")

	UI.addGroup("Bars", {
		UI.createInput("MaxBars", {
			maxChars = 2,
			filter = "_INT"
		}, '6'),
		UI.createInput("BarsWidth", {
			maxChars = 4,
			filter = "_INT"
		}, '300'),
		UI.createList("BarsHeight", { 40 }, 1, false),
	})

	UI.setTabs({
		{
			label = "Common",
			buttons = {
				left = { "Restore" },
				right = { "Accept" }
			},
			groups = {
				"Bars",
			}
		},
	}, "Common")

	UI.loadUserSettings()
	UI.render()
end

function Init()
	common.RegisterEventHandler(onPlayEffectFinished, 'EVENT_EFFECT_FINISHED')
	common.RegisterEventHandler(onSlash, 'EVENT_UNKNOWN_SLASH_COMMAND')
	common.RegisterEventHandler(onUnitsChanged, 'EVENT_UNITS_CHANGED')
	common.RegisterReactionHandler(onCfgLeft, "ConfigLeftClick")
	common.RegisterReactionHandler(onCfgRight, "ConfigRightClick")

	-- AOPanel
	common.RegisterEventHandler(onAOPanelStart, "AOPANEL_START")
	common.RegisterEventHandler(onAOPanelLeftClick, "AOPANEL_BUTTON_LEFT_CLICK")
	common.RegisterEventHandler(onAOPanelRightClick, "AOPANEL_BUTTON_RIGHT_CLICK")
	common.RegisterEventHandler(onAOPanelChange, "EVENT_ADDON_LOAD_STATE_CHANGED")

	bar_template:AddChild(spell_template)
	spell_template:Show(true)
	bar_template:SetTransparentInput(true)
	spell_template:SetTransparentInput(true)

	local settingHeight = tonumber(UI.get("Bars", "BarsHeight")) or 40
	local settingWidth = tonumber(UI.get("Bars", "BarsWidth")) or 300

	local iconSize = (tonumber(UI.get("Bars", "BarsHeight")) or 40) - 8
	WtSetPlace(bar_template,
		{ sizeX = settingWidth, sizeY = settingHeight })

	WtSetPlace(spell_template,
		{ alignX = 0, posX = 4, highPosX = 0, alignY = 0, posY = 4, highPosY = 0, sizeX = iconSize, sizeY = iconSize })

	local bar1Info = CreateWG("Label", "Info", bar_template, true,
		{
			alignX = 0,
			sizeX = settingWidth - settingHeight,
			posX = (settingHeight - 8) + 6,
			highPosX = 0,
			alignY = 0,
			sizeY = 20,
			posY = 2,
			highPosY = 0
		})
	bar1Info:SetFormat(userMods.ToWString(
		"<html><body alignx='left' aligny='bottom' fontsize='16' outline='1' shadow='1'><rs class='class'><r name='name'/></rs></body></html>"))
	bar1Info:SetVal("name", "Controls")
	bar1Info:SetClassVal("class", "ColorWhite")
	bar_template:AddChild(bar1Info)
	bar1Info:Show(false)

	DnD.Init(bar_template, spell_template, true)

	local cfgBtn = mainForm:GetChildChecked("ConfigButton", false)
	DnD.Init(cfgBtn, cfgBtn, true)
	DnD.Enable(cfgBtn, true)

	setupUI()
	getUnits()
end

if (avatar.IsExist()) then
	Init()
else
	common.RegisterEventHandler(Init, "EVENT_AVATAR_CREATED")
end
