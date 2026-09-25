
include("shared.lua")

CreateClientConVar("ACE_RadiatorInfoWhileSeated", 0, true, false)

-- copied from base_wire_entity: DoNormalDraw's notip arg isn't accessible from ENT:Draw defined there.
function ENT:Draw()

	local lply = LocalPlayer()
	local hideBubble = not GetConVar("ACE_RadiatorInfoWhileSeated"):GetBool() and IsValid(lply) and lply:InVehicle()

	self.BaseClass.DoNormalDraw(self, false, hideBubble)
	Wire_Render(self)

	if self.GetBeamLength and (not self.GetShowBeam or self:GetShowBeam()) then
		-- Every SENT that has GetBeamLength should draw a tracer. Some of them have the GetShowBeam boolean
		Wire_DrawTracerBeam( self, 1, self.GetBeamHighlight and self:GetBeamHighlight() or false )
	end

end

do

	local Wall = 0.75 -- wall thickness in inches

	local function CreateIdForCrate()

		   local X = math.Round( acemenupanel.RadiatorPanelConfig["Crate_Length"], 1 )
		   local Y = math.Round( acemenupanel.RadiatorPanelConfig["Crate_Width"], 1 )
		   local Z = math.Round( acemenupanel.RadiatorPanelConfig["Crate_Height"], 1)

		   local Id = X .. ":" .. Y .. ":" .. Z

		   ACE.RadiatorGUIUpdate()
		   acemenupanel.RadiatorData["Id"] = Id
		   RunConsoleCommand( "acemenu_data1", Id )

	 end

	function ACE.RadiatorGUICreate( Table )
		if not acemenupanel.CustomDisplay then return end

		local MainPanel = acemenupanel.CustomDisplay

		if not acemenupanel.RadiatorData then
			acemenupanel.RadiatorData          = {}
			acemenupanel.RadiatorData.Id       = "10:10:10"
		end

		if not acemenupanel.RadiatorPanelConfig then

			acemenupanel.RadiatorPanelConfig = {}
			acemenupanel.RadiatorPanelConfig["Crate_Length"]  = 1
			acemenupanel.RadiatorPanelConfig["Crate_Width"]   = 10
			acemenupanel.RadiatorPanelConfig["Crate_Height"]  = 10
			acemenupanel.RadiatorPanelConfig["Crate_Shape"] = "Radiator"

		 end

		acemenupanel:CPanelText("Name", Table.name, "DermaDefaultBold")

		-- Preview of the radiator model (it is scaled to the chosen size when spawned).
		if not IsValid(acemenupanel.CData.DisplayModel) then
			local Preview = vgui.Create( "DModelPanel", acemenupanel.CustomDisplay )
			Preview:SetSize( acemenupanel:GetWide(), acemenupanel:GetWide() * 0.6 )
			Preview.LayoutEntity = function() end
			acemenupanel.CData.DisplayModel = Preview
			acemenupanel.CustomDisplay:AddItem( Preview )
		end
		local RadModel = ACE.ModelData["Radiator"] and ACE.ModelData["Radiator"].Model or "models/radiators/radiator_med.mdl"
		acemenupanel.CData.DisplayModel:SetModel( RadModel )
		acemenupanel.CData.DisplayModel:SetCamPos( Vector( 55, 90, 45 ) )
		acemenupanel.CData.DisplayModel:SetLookAt( Vector( 0, 0, 0 ) )
		acemenupanel.CData.DisplayModel:SetFOV( 25 )

		acemenupanel:CPanelText("Desc", Table.desc)

		--------------- NEW CONFIG ---------------
		do

			local CrateNewCat = vgui.Create( "DCollapsibleCategory" )	-- Create a collapsible category
			acemenupanel.CustomDisplay:AddItem(CrateNewCat)
			CrateNewCat:SetLabel( "Radiator Config" )						-- Set the name ( label )
			CrateNewCat:SetPos( 25, 50 )		-- Set position
			CrateNewCat:SetSize( 250, 100 )	-- Set size
			CrateNewCat:SetExpanded( acemenupanel.RadiatorPanelConfig["ExpandedCatNew"] )

			function CrateNewCat:OnToggle( bool )
			   acemenupanel.RadiatorPanelConfig["ExpandedCatNew"] = bool
			end

			local CrateNewPanel = vgui.Create( "DPanelList" )
			CrateNewPanel:SetSpacing( 10 )
			CrateNewPanel:EnableHorizontal( false )
			CrateNewPanel:EnableVerticalScrollbar( true )
			CrateNewPanel:SetPaintBackground( false )
			CrateNewPanel:AddItem(LengthSlider)
			CrateNewCat:SetContents( CrateNewPanel )

			local MinCrateSize = ACE.CrateMinimumSize or 1
			local MaxCrateSize = ACE.CrateMaximumSize

			acemenupanel:CPanelText("Crate_desc_new", "\nAdjust the dimensions for the radiator. In inches.", nil, CrateNewPanel)

			-- X Slider
			local LengthSlider = vgui.Create( "DNumSlider" )
			LengthSlider:SetText( "Length" )
			LengthSlider:SetDark( true )
			LengthSlider:SetMin( MinCrateSize )
			LengthSlider:SetMax( MaxCrateSize )
			LengthSlider:SetValue( acemenupanel.RadiatorPanelConfig["Crate_Length"] or 10 )
			LengthSlider:SetDecimals( 1 )

			function LengthSlider:OnValueChanged( value )
				acemenupanel.RadiatorPanelConfig["Crate_Length"] = value
				CreateIdForCrate()
			end
			CrateNewPanel:AddItem(LengthSlider)

			-- Y Slider
			local WidthSlider = vgui.Create( "DNumSlider" )
			WidthSlider:SetText( "Width" )
			WidthSlider:SetDark( true )
			WidthSlider:SetMin( MinCrateSize )
			WidthSlider:SetMax( MaxCrateSize )
			WidthSlider:SetValue( acemenupanel.RadiatorPanelConfig["Crate_Width"] or 10 )
			WidthSlider:SetDecimals( 1 )

			function WidthSlider:OnValueChanged( value )
			acemenupanel.RadiatorPanelConfig["Crate_Width"] = value
			CreateIdForCrate()
			end
			CrateNewPanel:AddItem(WidthSlider)

			-- Z Slider
			local HeightSlider = vgui.Create( "DNumSlider" )
			HeightSlider:SetText( "Height" )
			HeightSlider:SetDark( true )
			HeightSlider:SetMin( MinCrateSize )
			HeightSlider:SetMax( MaxCrateSize )
			HeightSlider:SetValue( acemenupanel.RadiatorPanelConfig["Crate_Height"] or 10 )
			HeightSlider:SetDecimals( 1 )

			function HeightSlider:OnValueChanged( value )
			acemenupanel.RadiatorPanelConfig["Crate_Height"] = value
			CreateIdForCrate()
			end
			CrateNewPanel:AddItem(HeightSlider)

		end

		----------- The rest below -----------

		-- Send the size now, not only when a slider moves: data1 still holds whatever the last
		-- menu item wrote (an ammo or engine id), which is not a radiator size.
		CreateIdForCrate()

		MainPanel:PerformLayout()

	end

	function ACE.RadiatorGUIUpdate( _ )

		if not acemenupanel.CustomDisplay then return end

			local Length = acemenupanel.RadiatorPanelConfig["Crate_Length"]
			local Width = acemenupanel.RadiatorPanelConfig["Crate_Width"]
			local Height = acemenupanel.RadiatorPanelConfig["Crate_Height"]
			local Shape = "Box" --Box

			local ModelData = ACE.ModelData[Shape]

			local CrateVolume = ModelData.volumefunction( Length, Width, Height)
			local ContentVolume = math.max(ModelData.volumefunction( Length, Width - (Wall * 2), Height - (Wall * 2)) * 0.7,0) --Assume 2/3rds volume radiator fins, 1/3rd water

			local Capacity  = ContentVolume * ACE.CuIToLiter * ACE.TankVolumeMul * 0.4774  -- internal volume available for fuel in liters, with magic realism number
			local EmptyMass = (CrateVolume - ContentVolume) * 16.387 * ( 2.6 / 1000 )               -- total wall volume * cu in to cc * density of aluminum (kg/cc)
			local Mass      = EmptyMass + Capacity --* 1   Conversion Ommited    -- weight of tank + weight of contained water. Water is 1kg/Liter

			acemenupanel:CPanelText("Mass", "Full mass: " .. math.Round(Mass,1) .. " kg, Empty mass: " .. math.Round(EmptyMass,1) .. " kg")
			acemenupanel:CPanelText("Cap", "Capacity: " .. math.Round(Capacity,1) .. " liters / " .. math.Round(Capacity * 0.264172,1) .. " gallons")

			-- Same heat exchanger model the server runs (ace/shared/mobility/thermal_model.lua).
			local Thermal = ACE.Mobility.Thermal
			local FrontM2 = math.max(Width - Wall * 2, 0) * math.max(Height - Wall * 2, 0) * 0.00064516
			local DepthM = Length * 0.0254
			local function Rating(SpeedMS, Fan)
				local Face = Thermal.FaceVelocity(DepthM, SpeedMS, Fan)
				return math.Round(Thermal.RadiatorRating(FrontM2, DepthM, Face, 80) / 1000, 1)
			end

			acemenupanel:CPanelText("Core", "Core: " .. math.Round(FrontM2, 2) .. " m^2 face, " .. math.Round(DepthM * 100, 1) .. " cm deep (Length is the depth)")
			acemenupanel:CPanelText("CoolStand", "Cooling at 100 °C coolant, 20 °C air, standing: " .. Rating(0, 0) .. " kW, with fan: " .. Rating(0, 1) .. " kW")
			acemenupanel:CPanelText("CoolMove", "At 40 km/h with fan: " .. Rating(40 / 3.6, 1) .. " kW. An engine rejects roughly its own power to coolant at full load.")


	end
end