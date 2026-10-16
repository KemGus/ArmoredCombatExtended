--[[
	Hot-swap and copy settings for engines and gearboxes.

	Clicking a placed engine or gearbox with the ACE menu tool updates it in place to what the
	menu has selected (ENT:Update): it stays the same entity, so its welds, parent, wiring and
	links are kept. When the new choice needs a different collision model (another model, or
	another size of a scalable gearbox), the physics object is rebuilt, which drops every
	constraint on it; ACE.SaveEntity / ACE.RestoreEntity carry them across.

	Reload (R) with the menu tool on an engine or gearbox, or "Copy settings to ACE menu" in its
	context menu, fills the menu with that entity's settings, ready to spawn or update another.
]]

ACE = ACE or {}

local CopyClasses = { acf_engine = true, acf_gearbox = true }

if SERVER then

	util.AddNetworkString( "ACE_CopyToMenu" )

	--[[
		Saving and restoring an entity's constraints across a physics rebuild.
		Adapted from ACF-3's ACF.SaveEntity / ACF.RestoreEntity (lua/acf/core/utilities/util_sv.lua),
		as first brought to ACE for guns.
	]]
	local ConstraintTypes = duplicator.ConstraintType
	local Saved = {}

	local function ResetCollisions( Entity )
		if not IsValid( Entity ) then return end

		local PhysObj = Entity:GetPhysicsObject()
		if not IsValid( PhysObj ) then return end

		PhysObj:EnableCollisions( true )
	end

	-- Wire hydraulics tie the constraint, its rope and its controller together with
	-- DeleteOnRemove. Break those ties first so removing the constraint keeps the controller.
	local function ClearHydraulic( Constraint )
		local ID = Constraint.MyCrtl
		if not ID then return end

		local Controller = ents.GetByIndex( ID )
		if not IsValid( Controller ) then return end

		local Rope = Controller.Rope

		Controller:DontDeleteOnRemove( Constraint )
		Constraint:DontDeleteOnRemove( Controller )

		if IsValid( Rope ) then
			Controller:DontDeleteOnRemove( Rope )
			Rope:DontDeleteOnRemove( Constraint )
		end
	end

	local ConstrainedKeys = { "Ent1", "Ent2", "Ent3", "Ent4" }

	-- Like constraint.RemoveAll, without the hydraulic controllers going with it.
	local function ClearConstraints( Entity )
		local Constraints = Entity.Constraints
		if not Constraints then return end

		-- A snapshot: the loop takes each constraint off this list (and the other entities' lists).
		for _, Constraint in ipairs( table.ClearKeys( Constraints ) ) do
			if IsValid( Constraint ) then
				ResetCollisions( Constraint.Ent1 )
				ResetCollisions( Constraint.Ent2 )

				if Constraint.Type == "WireHydraulic" then
					ClearHydraulic( Constraint )
				end

				-- Remove only takes effect at the end of the tick. Until then the constraint would
				-- still be listed on the entities it joins, and constraint.Find would see it: a
				-- NoCollide rebuilt in the same tick is refused as already present.
				for _, Key in ipairs( ConstrainedKeys ) do
					local Ent = Constraint[ Key ]
					if IsValid( Ent ) and Ent.Constraints then
						table.RemoveByValue( Ent.Constraints, Constraint )
					end
				end

				Constraint:Remove()
			end
		end

		table.Empty( Constraints )

		Entity:IsConstrained()
	end

	-- Re-attaches a rebuilt hydraulic constraint to its controller and rope.
	local function RestoreHydraulic( ID, Constraint, Rope )
		local Controller = ents.GetByIndex( ID )
		if not IsValid( Controller ) or not IsValid( Constraint ) then return end

		Constraint.MyCrtl = Controller:EntIndex()
		Controller.MyId   = Controller:EntIndex()

		Controller:SetConstraint( Constraint )
		Controller:DeleteOnRemove( Constraint )

		if IsValid( Rope ) then
			Controller:SetRope( Rope )
			Controller:DeleteOnRemove( Rope )
		end

		Controller:SetLength( Controller.TargetLength )
		Controller:TriggerInput( "Constant", Controller.current_constant )
		Controller:TriggerInput( "Damping", Controller.current_damping )

		Constraint:DeleteOnRemove( Controller )
	end

	local function RestoreConstraint( Data )
		local Type    = Data.Type
		local Factory = Type and ConstraintTypes[ Type ]
		if not Factory then return false end

		local ID   = Data.MyCrtl
		local Args = {}

		if ID then Data.MyCrtl = nil end

		for Index, Name in ipairs( Factory.Args ) do
			Args[ Index ] = Data[ Name ]
		end

		local Constraint, Rope = Factory.Func( unpack( Args, 1, #Factory.Args ) )

		if Type == "WireHydraulic" then
			RestoreHydraulic( ID, Constraint, Rope )
		end

		return IsValid( Constraint )
	end

	--- Saves an entity's constraints and physics state, then removes the constraints, so the
	-- entity's physics object can be rebuilt (PhysicsInit) without leaving them dangling.
	-- Follow with ACE.RestoreEntity once the new physics object exists.
	-- @param Entity Entity The entity whose physics is about to be rebuilt.
	function ACE.SaveEntity( Entity )
		if not IsValid( Entity ) then return end

		local PhysObj = Entity:GetPhysicsObject()
		if not IsValid( PhysObj ) then return end

		Saved[ Entity ] = {
			Constraints = constraint.GetTable( Entity ),
			Gravity     = PhysObj:IsGravityEnabled(),
			Motion      = PhysObj:IsMotionEnabled(),
			Contents    = PhysObj:GetContents(),
			Material    = PhysObj:GetMaterial(),
		}

		ClearConstraints( Entity )

		-- If the entity is removed before RestoreEntity runs, drop the snapshot.
		Entity:CallOnRemove( "ACE_RestoreEntity", function()
			Saved[ Entity ] = nil
		end )
	end

	--- Rebuilds the constraints and physics state saved by ACE.SaveEntity.
	-- @param Entity Entity The entity, with its new physics object.
	-- @return number Constraints restored.
	-- @return number Constraints that could not be restored.
	function ACE.RestoreEntity( Entity )
		if not IsValid( Entity ) then return 0, 0 end

		local Data = Saved[ Entity ]
		if not Data then return 0, 0 end

		local PhysObj = Entity:GetPhysicsObject()
		if IsValid( PhysObj ) then
			PhysObj:EnableGravity( Data.Gravity )
			PhysObj:EnableMotion( Data.Motion )
			PhysObj:SetContents( Data.Contents )
			PhysObj:SetMaterial( Data.Material )
		end

		local Restored, Failed = 0, 0
		for _, Constraint in ipairs( Data.Constraints ) do
			if RestoreConstraint( Constraint ) then
				Restored = Restored + 1
			else
				Failed = Failed + 1
			end
		end

		Saved[ Entity ] = nil
		Entity:RemoveCallOnRemove( "ACE_RestoreEntity" )

		return Restored, Failed
	end

	--- Redraws a drivetrain link's rope between new end points, when the link had one.
	-- @param Link table The link (its Rope field is replaced).
	-- @param Ent1 Entity Driving entity.
	-- @param LPos1 Vector Output point, local to Ent1.
	-- @param Ent2 Entity Driven entity.
	-- @param LPos2 Vector Input point, local to Ent2.
	function ACE.RedrawLinkRope( Link, Ent1, LPos1, Ent2, LPos2 )
		if not IsValid( Link.Rope ) then return end
		Link.Rope:Remove()
		Link.Rope = ACE.CreateLinkRope( Ent1:LocalToWorld( LPos1 ), Ent1, LPos1, Ent2, LPos2 )
	end

	-- Model-local attachment points, read once per model from an unparented helper entity.
	local AttachmentCache = {}

	--- An attachment's position local to an entity (unscaled model space). The server reads a
	-- parented entity's attachments wrongly, so for one that is parented (a hot-swapped engine
	-- or gearbox on a parented build) the point is read from an unparented copy of its model.
	-- @param Ent Entity
	-- @param Name string Attachment name.
	-- @return Vector|nil Local position, nil when the model has no such attachment.
	function ACE.LocalAttachment( Ent, Name )
		if not IsValid( Ent:GetParent() ) then
			local Att = Ent:GetAttachment( Ent:LookupAttachment( Name ) )
			return Att and Ent:WorldToLocal( Att.Pos )
		end

		local Model = Ent:GetModel()
		local Points = AttachmentCache[ Model ]
		if not Points then
			Points = {}
			AttachmentCache[ Model ] = Points
		end

		if Points[ Name ] == nil then
			local Helper = ents.Create( "prop_dynamic" )
			Helper:SetModel( Model )
			Helper:SetPos( vector_origin )
			Helper:SetAngles( angle_zero )
			Helper:Spawn()

			local Att = Helper:GetAttachment( Helper:LookupAttachment( Name ) )
			Points[ Name ] = Att and Helper:WorldToLocal( Att.Pos ) or false
			Helper:Remove()
		end

		return Points[ Name ] and Vector( Points[ Name ] ) or nil
	end

	--- Makes sure a scalable entity is on the list late-joining clients get render scales from.
	-- @param Entity Entity
	function ACE.TrackScalable( Entity )
		ACE.ScalableEnts = ACE.ScalableEnts or {}
		if not table.HasValue( ACE.ScalableEnts, Entity ) then
			table.insert( ACE.ScalableEnts, Entity )
		end
	end

	--- Sends an engine's or gearbox's settings to a player's ACE menu.
	-- @param Ply Player
	-- @param Ent Entity acf_engine or acf_gearbox.
	-- @return boolean Success.
	-- @return string Message for the player.
	function ACE.CopyToMenu( Ply, Ent )
		if not IsValid( Ent ) or not CopyClasses[ Ent:GetClass() ] or not Ent.GetMenuSettings then
			return false, "Only engines and gearboxes can be copied to the menu."
		end
		if Ent.CPPICanTool and not Ent:CPPICanTool( Ply, "acemenu" ) then
			return false, "You can't copy that."
		end

		local Settings = Ent:GetMenuSettings()
		if not Settings then return false, "Nothing to copy." end

		net.Start( "ACE_CopyToMenu" )
			net.WriteString( Ent:GetClass() )
			net.WriteTable( Settings )
		net.Send( Ply )

		return true, "Settings copied to the ACE menu."
	end

else

	net.Receive( "ACE_CopyToMenu", function()
		local Class = net.ReadString()
		local Settings = net.ReadTable()

		if Class == "acf_gearbox" and ACE.GearboxMenuPaste then
			ACE.GearboxMenuPaste( Settings )
		elseif Class == "acf_engine" and ACE.EngineMenuPaste then
			ACE.EngineMenuPaste( Settings )
		end
	end )

	--- Opens a menu item in the ACE menu, as clicking it in the tree would.
	-- @param Table table The item's definition (ACE.Weapons.Engines / Gearboxes entry).
	function ACE.MenuShowItem( Table )
		if not Table then return end
		RunConsoleCommand( "acemenu_type", Table.type )
		RunConsoleCommand( "acemenu_id", Table.id )
		if IsValid( acemenupanel ) then
			acemenupanel:UpdateDisplay( Table )
		end
	end

end

properties.Add( "ace_copy_to_menu", {
	MenuLabel = "Copy settings to ACE menu",
	Order = 1700,
	MenuIcon = "icon16/page_copy.png",

	Filter = function( _, Ent, Ply )
		if not IsValid( Ent ) or not CopyClasses[ Ent:GetClass() ] then return false end
		return gamemode.Call( "CanProperty", Ply, "ace_copy_to_menu", Ent ) ~= false
	end,

	Action = function( self, Ent )
		self:MsgStart()
			net.WriteEntity( Ent )
		self:MsgEnd()
	end,

	Receive = function( self, _, Ply )
		local Ent = net.ReadEntity()
		if not self:Filter( Ent, Ply ) then return end

		local Success, Msg = ACE.CopyToMenu( Ply, Ent )
		ACE.SendNotify( Ply, Success, Msg )
		-- Hand the player the menu tool, so the next click spawns or updates with these settings.
		if Success then Ply:ConCommand( "gmod_tool acemenu" ) end
	end
} )
