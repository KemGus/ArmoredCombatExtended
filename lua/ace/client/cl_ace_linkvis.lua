-- Link preview for the ACE menu tool: while entities are selected for linking, draws a beam from each
-- of them to the aimed entity, coloured by whether the link would pass the mobility link rules.
-- Idea from ACF-3 PR #449 (link visualisation). The checks mirror the server rules in
-- acf_engine/init.lua and acf_gearbox/init.lua; the server still decides.

ACE = ACE or {}
ACE.LinkVis = ACE.LinkVis or {}

local LinkVis = ACE.LinkVis

-- Mirrors of the server constants. Keep in sync with acf_engine/init.lua and acf_gearbox/init.lua.
LinkVis.FuelLinkDist   = 512 -- FuelLinkDistBase: fuel tanks and radiators
LinkVis.MaxShaftDot    = 0.7 -- Checkdriveshaft MaxAngle
LinkVis.WarnFraction   = 0.9 -- within 10% of a limit shows as a warning

local ColorOk   = Color(55, 235, 55)
local ColorFail = Color(255, 88, 88)
local ColorWarn = Color(255, 200, 80)
local ColorInfo = Color(205, 235, 255)
local ColorBack = Color(0, 0, 0)

local Selected = {}

net.Receive("ACE_MenuLinkSelection", function()
	Selected = {}

	local Count = net.ReadUInt(8)

	for _ = 1, Count do
		local Ent = net.ReadEntity()

		if IsValid(Ent) then
			Selected[#Selected + 1] = Ent
		end
	end
end)

--- Returns the entities the server says are selected for linking.
-- @return table Array of entities.
function LinkVis.GetSelected()
	return Selected
end

-- World position of a model attachment, or the entity origin when the model has none.
local function AttachmentPos(Ent, Name)
	local Id = Ent:LookupAttachment(Name)

	if Id and Id > 0 then
		local Att = Ent:GetAttachment(Id)

		if Att then return Att.Pos end
	end

	return Ent:GetPos()
end

local EngineDefsByModel, EngineDefsByName

local function EngineDef(Ent)
	if not EngineDefsByModel then
		EngineDefsByModel, EngineDefsByName = {}, {}

		for _, Def in pairs(ACE.Weapons and ACE.Weapons.Engines or {}) do
			if Def.name then EngineDefsByName[Def.name] = Def end
			if Def.model and not EngineDefsByModel[Def.model] then EngineDefsByModel[Def.model] = Def end
		end
	end

	return EngineDefsByName[Ent:GetNWString("WireName", "")] or EngineDefsByModel[Ent:GetModel()]
end

-- Fuel tanks are named "ACE <Fuel> <size> Fuel Tank" or "ACE <size> Li-Ion Battery".
local function TankFuel(Ent)
	local Name = Ent:GetNWString("WireName", "")

	if Name:find("Li-Ion Battery", 1, true) then return "Electric" end

	return Name:match("^ACE (%a+) ")
end

local function Result(Col, Text)
	return { col = Col, text = Text }
end

local function DistanceResult(Dist, MaxDist, What)
	if Dist > MaxDist then
		return Result(ColorFail, What .. " is too far away (" .. math.Round(Dist) .. " / " .. MaxDist .. " units)"), MaxDist
	elseif Dist > MaxDist * LinkVis.WarnFraction then
		return Result(ColorWarn, "Close to the link distance limit (" .. math.Round(Dist) .. " / " .. MaxDist .. " units)")
	end

	return Result(ColorOk, "OK (" .. math.Round(Dist) .. " units)")
end

local function ShaftResult(Dot, From, To)
	if Dot < LinkVis.MaxShaftDot then
		return Result(ColorFail, "Excessive driveshaft angle"), nil, From, To
	elseif Dot < LinkVis.MaxShaftDot + 0.05 then
		return Result(ColorWarn, "Driveshaft angle is close to the limit"), nil, From, To
	end

	return Result(ColorOk, "OK"), nil, From, To
end

-- Engine driveshaft check, same as ENT:Checkdriveshaft in acf_engine/init.lua.
local function EngineToGearbox(Engine, Gearbox)
	local OutPos = AttachmentPos(Engine, "driveshaft")
	local InPos  = AttachmentPos(Gearbox, "input")
	local Def    = EngineDef(Engine)
	local Dir    = (Def and Def.istrans) and -Engine:GetRight() or Engine:GetForward()

	return ShaftResult((OutPos - InPos):GetNormalized():Dot(Dir), OutPos, InPos)
end

-- Gearbox output check, same as ENT:Checkdriveshaft in acf_gearbox/init.lua.
local function GearboxToOutput(Gearbox, Target)
	local InPos = Target:GetClass() == "acf_gearbox" and AttachmentPos(Target, "input") or Target:GetPos()
	local Left  = Gearbox:WorldToLocal(InPos).y < 0
	local OutPos = AttachmentPos(Gearbox, Left and "driveshaftL" or "driveshaftR")
	local Side  = Gearbox:WorldToLocal(OutPos).y
	local Dir   = (Gearbox:GetRight() * Side):GetNormalized()

	return ShaftResult((OutPos - InPos):GetNormalized():Dot(Dir), OutPos, InPos)
end

local EngineTargets = {
	acf_gearbox = EngineToGearbox,

	acf_fueltank = function(Engine, Tank)
		local Def = EngineDef(Engine)
		local EngineFuel = Def and Def.fuel
		local Fuel = TankFuel(Tank)

		if EngineFuel and Fuel and not (EngineFuel == "Multifuel" and Fuel ~= "Electric") and EngineFuel ~= Fuel then
			return Result(ColorFail, "Fuel type is incompatible (" .. EngineFuel .. " engine, " .. Fuel .. " tank)")
		end

		return DistanceResult(Engine:GetPos():Distance(Tank:GetPos()), LinkVis.FuelLinkDist, "The fuel tank")
	end,

	ace_radiator = function(Engine, Radiator)
		return DistanceResult(Engine:GetPos():Distance(Radiator:GetPos()), LinkVis.FuelLinkDist, "The radiator")
	end,

	ace_crewseat_driver = function()
		return Result(ColorOk, "OK - the seat must be legal")
	end,
}

local GearboxTargets = {
	acf_gearbox = true,
	prop_physics = true,
	tire = true,
}

-- Works out which entity links which (same order as linkEnts in the acemenu tool) and checks it.
-- Returns a result, an optional max distance for the beam split, and optional beam end points.
local function CheckLink(SelectedEnt, Aimed)
	if SelectedEnt == Aimed then
		return Result(ColorFail, "Cannot link an entity to itself")
	end

	local SClass, AClass = SelectedEnt:GetClass(), Aimed:GetClass()
	local Engine, Other

	if SClass == "acf_engine" then
		Engine, Other = SelectedEnt, Aimed
	elseif AClass == "acf_engine" then
		Engine, Other = Aimed, SelectedEnt
	end

	if Engine then
		local Check = EngineTargets[Other:GetClass()]
		if not Check then
			return Result(ColorFail, "Engines only link to gearboxes, fuel tanks, radiators or driver seats")
		end

		return Check(Engine, Other)
	end

	-- Gearbox to gearbox: the selected one drives the aimed one
	if SClass == "acf_gearbox" and GearboxTargets[AClass] then
		return GearboxToOutput(SelectedEnt, Aimed)
	elseif AClass == "acf_gearbox" and SClass ~= "acf_gearbox" and GearboxTargets[SClass] then
		return GearboxToOutput(Aimed, SelectedEnt)
	elseif SClass == "acf_gearbox" or AClass == "acf_gearbox" then
		return Result(ColorFail, "Gearboxes only link to gearboxes or wheels")
	end

	return Result(ColorWarn, "Not checked here - the server decides")
end

-- Returns true while the local player holds the ACE menu tool with a link selection pending.
local function InLinkMode()
	if #Selected == 0 then return false end

	local Ply = LocalPlayer()
	if not IsValid(Ply) then return false end

	local Weapon = Ply:GetActiveWeapon()
	if not IsValid(Weapon) or Weapon:GetClass() ~= "gmod_tool" then return false end

	local Tool = Ply:GetTool()

	return Tool ~= nil and Tool.Mode == "acemenu" and Tool:GetStage() == 1
end

local Labels = {}

local function DrawBeam(From, To, Col)
	render.DrawBeam(From, To, 2, 0, 1, ColorBack)
	render.DrawBeam(From, To, 1, 0, 1, Col)
end

hook.Add("PostDrawTranslucentRenderables", "ACE_LinkVis_Beams", function(Depth, Skybox)
	if Depth or Skybox then return end

	Labels = {}

	if not InLinkMode() then return end

	local Ply       = LocalPlayer()
	local Trace     = Ply:GetEyeTrace()
	local Aimed     = Trace.Entity
	local HasTarget = IsValid(Aimed) and not Aimed:IsWorld()
	local Unlinking = Ply:KeyDown(IN_USE)

	render.SetColorMaterial()
	render.DepthRange(0, 0)

	for _, Ent in ipairs(Selected) do
		if IsValid(Ent) then
			local From, To = Ent:GetPos(), HasTarget and Aimed:GetPos() or Trace.HitPos
			local Res, MaxDist, ShaftFrom, ShaftTo

			if not HasTarget then
				Res = Result(ColorInfo, math.Round(From:Distance(To)) .. " units")
			elseif Unlinking then
				Res = Result(ColorInfo, "Unlink")
			else
				Res, MaxDist, ShaftFrom, ShaftTo = CheckLink(Ent, Aimed)
			end

			if ShaftFrom and ShaftTo then
				From, To = ShaftFrom, ShaftTo
			end

			if MaxDist then
				local Split = From + (To - From):GetNormalized() * MaxDist

				DrawBeam(From, Split, ColorWarn)
				DrawBeam(Split, To, ColorFail)
			else
				DrawBeam(From, To, Res.col)
			end

			local Screen = LerpVector(0.5, From, To):ToScreen()

			Labels[#Labels + 1] = { x = Screen.x, y = Screen.y, text = Res.text, col = Res.col }
		end
	end

	render.DepthRange(0, 1)
end)

hook.Add("HUDPaint", "ACE_LinkVis_Labels", function()
	if #Labels == 0 or not InLinkMode() then return end

	local W, H = ScrW(), ScrH()

	for _, Label in ipairs(Labels) do
		local X = math.Clamp(Label.x, 150, W - 150)
		local Y = math.Clamp(Label.y, 20, H - 20)

		draw.SimpleTextOutlined(Label.text, "DermaDefaultBold", X, Y, Label.col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, ColorBack)
	end
end)
