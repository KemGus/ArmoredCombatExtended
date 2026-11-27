
include("shared.lua")

local ACE_GunInfoWhileSeated = CreateClientConVar("ace_gun_info_while_seated", 0, true, false)

killicon.Add("acf_gun", "HUD/killicons/acf_gun", ACE.KillIconColor)

function ENT:Initialize()

	self.BaseClass.Initialize( self )

	self.LastFire	= 0
	self.Reload	= 1
	self.CloseTime  = 1
	self.Rate	= 1
	self.RateScale  = 1
	self.FireAnim	= self:LookupSequence( "shoot" )
	self.CloseAnim  = self:LookupSequence( "load" )
	self.LastThink  = 0
end

-- copied from base_wire_entity: DoNormalDraw's notip arg isn't accessible from ENT:Draw defined there.
function ENT:Draw()

	local lply = LocalPlayer()
	local hideBubble = not ACE_GunInfoWhileSeated:GetBool() and IsValid(lply) and lply:InVehicle()

	self.BaseClass.DoNormalDraw(self, false, hideBubble)
	Wire_Render(self)

	if self.GetBeamLength and (not self.GetShowBeam or self:GetShowBeam()) then
		-- Every SENT that has GetBeamLength should draw a tracer. Some of them have the GetShowBeam boolean
		Wire_DrawTracerBeam( self, 1, self.GetBeamHighlight and self:GetBeamHighlight() or false )
	end

end

function ENT:Think()

	self.BaseClass.Think( self )

	local SinceFire = CurTime() - self.LastFire
	self:SetCycle( math.min( SinceFire * self.Rate / self.RateScale, 1 ) )
	if CurTime() > self.LastFire + self.CloseTime and self.CloseAnim then
		-- Reset only on an actual sequence change: re-resetting every Think restarts the
		-- close animation each tick, which strobes the gun (seen on auto first-load guns).
		if self:GetSequence() ~= self.CloseAnim then
			self:ResetSequence( self.CloseAnim )
		end
		local cycle = ( SinceFire - self.CloseTime ) * self.Rate / self.RateScale
		self:SetCycle( math.min( cycle, 1 ) )
		self.Rate = 1 / math.max( self.Reload - self.CloseTime, 0.05 ) -- Base anim time is 1s, rate is in 1/10 of a second
		-- Once the close animation has finished, freeze playback so nothing can advance or
		-- loop it between Thinks; the clamped SetCycle above pins the finished pose.
		self:SetPlaybackRate( cycle >= 1 and 0 or self.Rate )
	end

end

function ENT:Animate( _, ReloadTime, LoadOnly )

	if self.CloseAnim and self.CloseAnim > 0 then
		self.CloseTime = math.max(ReloadTime-0.75,ReloadTime * 0.75)
	else
		self.CloseTime = ReloadTime
		self.CloseAnim = nil
	end

	self:ResetSequence( self.FireAnim )
	self:SetCycle( 0 )
	self.RateScale = self:SequenceDuration()
	if LoadOnly then
		self.Rate = 1000000
	else
		self.Rate = 1 / math.Clamp(self.CloseTime,0.1,1.5)	--Base anim time is 1s, rate is in 1/10 of a second
	end
	self:SetPlaybackRate( self.Rate )
	self.LastFire = CurTime()
	self.Reload = ReloadTime

end

function ACE.GunGUICreate( Table )

	acemenupanel:CPanelText("Name", Table.name, "DermaDefaultBold")

	local GunDisplay = acemenupanel.CData.DisplayModel

	GunDisplay = vgui.Create( "DModelPanel", acemenupanel.CustomDisplay )
	GunDisplay:SetModel( Table.model )
	GunDisplay:SetCamPos( Vector( 250, 500, 250 ) )
	GunDisplay:SetLookAt( Vector( 0, 0, 0 ) )
	GunDisplay:SetFOV( 20 )
	GunDisplay:SetSize(acemenupanel:GetWide(),acemenupanel:GetWide())
	GunDisplay.LayoutEntity = function( _, ent )
		-- Preview the scalable spec on the model panel.
		local Vec = acemenupanel.GunScaleVec
		if Vec and ( Vec.x ~= 1 or Vec.y ~= 1 or Vec.z ~= 1 ) then
			local M = Matrix()
			M:Scale( Vec )
			ent:EnableMatrix( "RenderMultiply", M )
		else
			ent:DisableMatrix( "RenderMultiply" )
		end

		local Len = acemenupanel.GunScaleLen
		if Len then
			ACE.GunScale.ApplyBarrelBones( ent, Len, acemenupanel.GunScaleSplit )
		end
	end
	acemenupanel.CustomDisplay:AddItem( GunDisplay )

	local GunClass = ACE.Classes.GunClass[Table.gunclass]
	acemenupanel:CPanelText("ClassDesc", GunClass.desc)
	acemenupanel:CPanelText("GunDesc", Table.desc)
	acemenupanel:CPanelText("Caliber", "Caliber: " .. (Table.caliber * 10) .. "mm")
	acemenupanel:CPanelText("Weight", "Weight: " .. Table.weight .. "kg")
	acemenupanel:CPanelText("Year", "Year: " .. Table.year)

	if Table.rack then -- if it is missile
		if Table.seekcone then acemenupanel:CPanelText("SeekCone", "Seek Cone: " .. Table.seekcone .. " degrees") end
		if Table.viewcone then acemenupanel:CPanelText("ViewCone", "View Cone: " .. Table.viewcone .. " degrees") end

		if Table.guidelay then acemenupanel:CPanelText("GuiDelay", "Minimum delay to start maneuvers: " .. Table.guidelay .. " seconds")
		else acemenupanel:CPanelText("GuiDelay", "With a guidance, this ordnance will start to do maneuvers with no delays") end


		if Table.guidance and #Table.guidance > 0 then

			local guitxt = ""
			for _, guidance in ipairs(Table.guidance) do
				if guidance ~= "Dumb" then
					guitxt = guitxt .. "- " .. guidance .. "\n"
				end
			end

			if guitxt ~= "" then
				acemenupanel:CPanelText("Guidances", "\nAvailable guidances: \n" .. guitxt )
			end
		end

		if Table.fuses and #Table.fuses > 0 then

			local guitxt = ""
			for _, fuses in ipairs(Table.fuses) do
				guitxt = guitxt .. "- " .. fuses .. "\n"
			end

			acemenupanel:CPanelText("Fuses", "Available fuses: \n" .. guitxt )
		end

	else -- if gun
		local RoundVolume = math.pi * (Table.caliber / 2) ^ 2 * Table.round.maxlength
		local RoF = 60 / (((RoundVolume / 500 ) ^ 0.60 ) * GunClass.rofmod * (Table.rofmod or 1)) --class and per-gun use same var name
		acemenupanel:CPanelText("Firerate", "RoF: " .. math.Round(RoF, 1) .. " rounds/min")

		if Table.maxrof then
			acemenupanel:CPanelText("Max_Rof", "Maximum RoF: " .. Table.maxrof .. " rounds/min")
		end
		if Table.magsize then acemenupanel:CPanelText("Magazine", "Magazine: " .. Table.magsize .. " rounds\nReload: " .. Table.magreload .. " s") end
		acemenupanel:CPanelText("Spread", "Spread: " .. (GunClass.spread * 1.5) .. " degrees")
		acemenupanel:CPanelText("Spread_Gunner", "Spread with gunner: " .. GunClass.spread .. " degrees")

	end

	-- Scalable gun controls: caliber (mm) + bore length (calibers) sliders that
	-- write the acemenu_gunopts spawn cvar. Live stats preview via GunScale.
	local ScaleLimits = ACE.GunScale and ACE.GunScale.Limits( Table.id )
	if ScaleLimits and not ScaleLimits.hasbarrels then

		local GunScaleState = { cal = ScaleLimits.basecal * 10, len = ScaleLimits.baselen }
		local CurOpts = GetConVar( "acemenu_gunopts" )
		if CurOpts then
			local c, l = ACE.GunScale.ParseOpts( CurOpts:GetString() )
			if c then GunScaleState.cal = math.Clamp( c, ScaleLimits.calmin * 10, ScaleLimits.calmax * 10 ) end
			if l then GunScaleState.len = math.Clamp( l, ScaleLimits.lenmin, ScaleLimits.lenmax ) end
		end

		acemenupanel:CPanelText("GunScaleTitle", "Scalable Configuration", "DermaDefaultBold")

		local function PushGunOpts()
			local cal, len = ACE.GunScale.Normalize( Table.id, GunScaleState.cal, GunScaleState.len )
			GunScaleState.cal, GunScaleState.len = cal, len

			RunConsoleCommand( "acemenu_gunopts", ACE.GunScale.OptString( Table.id, cal, len ) )

			local S = ACE.GunScale.Stats( Table, cal / 10, len )
			acemenupanel.GunScaleVec = S.scale
			acemenupanel.GunScaleLen = S.split and S.lenscale or nil
			acemenupanel.GunScaleSplit = S.split
			acemenupanel:CPanelText("GunScaleStats", string.format(
				"Spec: %gmm L%g - %d kg\nMuzzle velocity modifier: x%.2f\nChamber: %gcm - Max propellant: %g kg",
				cal, len, math.Round( S.mass ), S.mvmod, S.chamberLen, S.propLimit ) )
		end

		local CalSlider = vgui.Create( "DNumSlider", acemenupanel.CustomDisplay )
		CalSlider:SetText( "Caliber (mm)" )
		CalSlider:SetDark( true )
		CalSlider:SetMin( ScaleLimits.calmin * 10 )
		CalSlider:SetMax( ScaleLimits.calmax * 10 )
		CalSlider:SetDecimals( 1 )
		CalSlider:SetValue( GunScaleState.cal )
		acemenupanel.CustomDisplay:AddItem( CalSlider )

		-- Caliber-only classes lock the length axis; no point showing it.
		local LenSlider
		if ScaleLimits.lenmin < ScaleLimits.lenmax then
			LenSlider = vgui.Create( "DNumSlider", acemenupanel.CustomDisplay )
			LenSlider:SetText( "Bore length (calibers)" )
			LenSlider:SetDark( true )
			LenSlider:SetMin( ScaleLimits.lenmin )
			LenSlider:SetMax( ScaleLimits.lenmax )
			LenSlider:SetDecimals( 0 )
			LenSlider:SetValue( GunScaleState.len )
			acemenupanel.CustomDisplay:AddItem( LenSlider )
		end

		CalSlider.OnValueChanged = function( _, val )
			GunScaleState.cal = val
			PushGunOpts()
		end
		if LenSlider then
			LenSlider.OnValueChanged = function( _, val )
				GunScaleState.len = val
				PushGunOpts()
			end
		end

		PushGunOpts()
	else
		acemenupanel.GunScaleVec = nil
		acemenupanel.GunScaleLen = nil
		acemenupanel.GunScaleSplit = nil
		RunConsoleCommand( "acemenu_gunopts", "" )
	end

	acemenupanel.CustomDisplay:PerformLayout()

end

--- Unified scalable-class entry: one menu node per gun class whose sliders
-- span the whole family. The caliber slider resolves the nearest concrete def
-- (its model, stats and envelope), so a family like Cannon still spawns a real
-- 120mmC/140mmC under the hood - old ids, dupes and keys are untouched.
function ACE.GunFamilyGUICreate( Table )

	acemenupanel:CPanelText("Name", Table.name, "DermaDefaultBold")

	local fam = Table.family
	local GunScaleState = { cal = nil, len = nil }

	local CurOpts = GetConVar( "acemenu_gunopts" )
	local initDef = ACE.GunScale.ResolveFamilyDef( fam, fam.defs[1].caliber * 10 )
	if CurOpts then
		local c, l = ACE.GunScale.ParseOpts( CurOpts:GetString() )
		if c then GunScaleState.cal = math.Clamp( c, fam.calmin * 10, fam.calmax * 10 ) end
		if l then GunScaleState.len = math.Clamp( l, fam.lenmin, fam.lenmax ) end
	end
	GunScaleState.cal = GunScaleState.cal or ( initDef.caliber * 10 )
	GunScaleState.len = GunScaleState.len or ACE.GunScale.Limits( initDef.id ).baselen

	local Def = initDef
	local GunDisplay = vgui.Create( "DModelPanel", acemenupanel.CustomDisplay )
	GunDisplay:SetModel( Def.model )
	GunDisplay:SetCamPos( Vector( 250, 500, 250 ) )
	GunDisplay:SetLookAt( Vector( 0, 0, 0 ) )
	GunDisplay:SetFOV( 20 )
	GunDisplay:SetSize(acemenupanel:GetWide(),acemenupanel:GetWide())
	GunDisplay.LayoutEntity = function( _, ent )
		local Vec = acemenupanel.GunScaleVec
		if Vec and ( Vec.x ~= 1 or Vec.y ~= 1 or Vec.z ~= 1 ) then
			local M = Matrix()
			M:Scale( Vec )
			ent:EnableMatrix( "RenderMultiply", M )
		else
			ent:DisableMatrix( "RenderMultiply" )
		end

		local Len = acemenupanel.GunScaleLen
		if Len then
			ACE.GunScale.ApplyBarrelBones( ent, Len, acemenupanel.GunScaleSplit )
		end
	end
	acemenupanel.CustomDisplay:AddItem( GunDisplay )

	local GunClass = ACE.Classes.GunClass[Table.class]
	if GunClass then acemenupanel:CPanelText("ClassDesc", GunClass.desc) end

	-- Drum and breech autoloaders are separate classes sharing one menu entry;
	-- the mechanism dropdown rebuilds this panel for the other class. Both
	-- share the caliber/length envelope, so slider state carries over.
	if Table.class == "AL" or Table.class == "BAL" then
		local MechBox = vgui.Create( "DComboBox", acemenupanel.CustomDisplay )
		MechBox:SetText( "Mechanism" )
		MechBox:AddChoice( "Drum Autoloader", "AL", Table.class == "AL" )
		MechBox:AddChoice( "Breech Autoloader", "BAL", Table.class == "BAL" )
		MechBox:SetDark( true )
		MechBox.OnSelect = function( _, _, _, classId )
			if classId == Table.class then return end
			local fams = ACE.GunScale.Families( classId )
			if not fams or not fams[1] then return end
			local fam = fams[1]
			acemenupanel:UpdateDisplay( {
				id       = fam.defs[1].id,
				type     = "Guns",
				name     = "Autoloader",
				model    = fam.defs[1].model,
				class    = classId,
				gunclass = classId,
				family   = fam,
				guicreate = function( _, T ) ACE.GunFamilyGUICreate( T ) end,
				guiupdate = function() return end,
			} )
		end
		acemenupanel.CustomDisplay:AddItem( MechBox )
	end

	acemenupanel:CPanelText("GunScaleTitle", "Scalable Configuration", "DermaDefaultBold")

	local function PushGunOpts()
		local newDef = ACE.GunScale.ResolveFamilyDef( fam, GunScaleState.cal )
		if newDef ~= Def then
			-- Reset stale bone manipulations before the model swap: they are
			-- keyed by index, so the old rig's values would land on the wrong
			-- bones of the next model.
			local ent = GunDisplay.GetEntity and GunDisplay:GetEntity() or GunDisplay.Entity
			if IsValid( ent ) then
				for i = 0, ent:GetBoneCount() - 1 do
					ent:ManipulateBoneScale( i, Vector( 1, 1, 1 ) )
					ent:ManipulateBonePosition( i, Vector( 0, 0, 0 ) )
					ent:ManipulateBoneAngles( i, Angle( 0, 0, 0 ) )
				end
			end
			Def = newDef
			GunDisplay:SetModel( Def.model )
		end

		local cal, len = ACE.GunScale.Normalize( Def.id, GunScaleState.cal, GunScaleState.len )
		GunScaleState.cal, GunScaleState.len = cal, len

		RunConsoleCommand( "acemenu_id", Def.id )
		RunConsoleCommand( "acemenu_gunopts", ACE.GunScale.OptString( Def.id, cal, len ) )

		local S = ACE.GunScale.Stats( Def, cal / 10, len )
		acemenupanel.GunScaleVec = S.scale
		acemenupanel.GunScaleLen = S.split and S.lenscale or nil
		acemenupanel.GunScaleSplit = S.split
		acemenupanel:CPanelText("GunScaleDef", "Spawns as: " .. ACE.GunScale.DisplayName( Def, cal, len ) )
		acemenupanel:CPanelText("GunScaleStats", string.format(
			"Spec: %gmm L%g - %d kg\nMuzzle velocity modifier: x%.2f\nChamber: %gcm - Max propellant: %g kg",
			cal, len, math.Round( S.mass ), S.mvmod, S.chamberLen, S.propLimit ) )
	end

	local CalSlider = vgui.Create( "DNumSlider", acemenupanel.CustomDisplay )
	CalSlider:SetText( "Caliber (mm)" )
	CalSlider:SetDark( true )
	CalSlider:SetMin( fam.calmin * 10 )
	CalSlider:SetMax( fam.calmax * 10 )
	CalSlider:SetDecimals( 1 )
	CalSlider:SetValue( GunScaleState.cal )
	acemenupanel.CustomDisplay:AddItem( CalSlider )

	local LenSlider
	if fam.lenmin < fam.lenmax then
		LenSlider = vgui.Create( "DNumSlider", acemenupanel.CustomDisplay )
		LenSlider:SetText( "Bore length (calibers)" )
		LenSlider:SetDark( true )
		LenSlider:SetMin( fam.lenmin )
		LenSlider:SetMax( fam.lenmax )
		LenSlider:SetDecimals( 0 )
		LenSlider:SetValue( GunScaleState.len )
		acemenupanel.CustomDisplay:AddItem( LenSlider )
	end

	CalSlider.OnValueChanged = function( _, val )
		GunScaleState.cal = val
		PushGunOpts()
	end
	if LenSlider then
		LenSlider.OnValueChanged = function( _, val )
			GunScaleState.len = val
			PushGunOpts()
		end
	end

	PushGunOpts()
	acemenupanel.CustomDisplay:PerformLayout()

end
