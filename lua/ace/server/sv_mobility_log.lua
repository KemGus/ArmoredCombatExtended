--[[
	Drivetrain flight recorder. Records everything the drivetrain saw and did for one vehicle,
	every physics step, into a rolling buffer, and writes it to data/ace_mobility_log/ on
	request. Meant for problems that come and go: start it, play until the problem shows up,
	mark the moment, save.

	Console commands (superadmin, listen server host or singleplayer):
	  ace_mobility_log_start [seconds] [entity index]
	      Start recording the vehicle you sit in or look at (or the given entity's vehicle).
	      Keeps the last [seconds] (default 30).
	  ace_mobility_log_mark [text]   Put a marker in the log ("swinging starts now"). Bind it to a key.
	  ace_mobility_log_save          Write the buffer to disk and keep recording.
	  ace_mobility_log_stop          Write the buffer to disk and stop.

	Files (one folder per save):
	  setup.txt   server settings, every entity of the vehicle and every constraint between them
	  events.csv  brake locks made and released (and why), load latches, gear and pedal changes,
	              markers, the drivetrain switching between in-step and per-tick solving
	  frames.csv  one row per solve: chassis position, angles, velocity and spin in its own frame
	  wheels.csv  one row per wheel per solve: everything the solver read and applied
	  boxes.csv   one row per gearbox per solve: gear, pedals, clutch, differential
	  engines.csv one row per engine per solve
	  bodies.csv  one row per physical body per solve: velocity and spin, to see what swings
]]

local M = ACE.Mobility
local Log = {}

local InchToMeter = M.Units.InchToMeter
local format = string.format
local abs = math.abs

local Rec -- the running recording, or nil

local function canUse(Ply)
	return not IsValid(Ply) or game.SinglePlayer() or Ply:IsSuperAdmin() or Ply:IsListenServerHost()
end

local function say(Ply, Text)
	Text = "[ACE mobility log] " .. Text
	if IsValid(Ply) then Ply:ChatPrint(Text) end
	MsgN(Text)
end

local function id(Ent)
	return IsValid(Ent) and Ent:EntIndex() or -1
end

local function num(V, Places)
	if V == nil then return "" end
	if V == true then return "1" end
	if V == false then return "0" end
	if type(V) ~= "number" then return tostring(V) end
	if V ~= V then return "nan" end
	if V % 1 == 0 and abs(V) < 1e9 then return format("%d", V) end
	return format("%." .. (Places or 3) .. "f", V)
end

local function row(T)
	for I = 1, #T do
		local V = T[I]
		if type(V) ~= "string" then T[I] = num(V) end
	end
	return table.concat(T, ",") .. "\n"
end

-- Everything physically attached to Ent, and everything parented to that.
local function members(Ent)
	local Set = {}
	-- Children, but not a seated player and what the player carries.
	local function add(E)
		if Set[E] or not IsValid(E) or E:IsPlayer() then return end
		Set[E] = true
		for _, C in ipairs(E:GetChildren()) do add(C) end
	end
	-- Parented props carry no constraints: start from the body they ride on.
	Ent = ACE.GetPhysicalParent(Ent) or Ent
	for _, V in pairs(ACE.GetAllPhysicalConstraints(Ent) or {}) do add(V) end
	return Set
end

-- Angular velocity in world space, deg/s.
local function worldAngVel(Phys)
	return Phys:LocalToWorldVector(Phys:GetAngleVelocity())
end

local function now()
	return CurTime()
end

------------------------------------------------------------------------ recording

--- Records one drivetrain solve. Called by sv_mobility while a recording runs.
-- @param Kind "step" (inside a physics step), "tick" (once per tick) or "standalone" (engineless gearbox tree).
-- @param Group Engines of the group, or nil.
-- @param Ctx The solve context.
-- @param Dt Solve step length.
function Log.Frame(Kind, Group, Ctx, Dt)
	if not Rec then return end
	local First = Ctx.WheelList[1]
	if not (Rec.Members[Ctx.Chassis] or First and Rec.Members[First.Ent]) then return end

	Rec.FrameNo = Rec.FrameNo + 1
	local F = Rec.FrameNo
	local T = now()
	local Tick = engine.TickCount()
	local Head = format("%d,%.4f,%d,%s,%.4f", F, T - Rec.Start, Tick, Kind, Dt)
	local Bundle = { T = T, Frames = {}, Wheels = {}, Boxes = {}, Engines = {}, Bodies = {} }

	-- Chassis, in its own frame: x forward, y left, z up for most builds.
	local Chassis = Ctx.Chassis
	local CPhys = IsValid(Chassis) and Chassis:GetPhysicsObject()
	if IsValid(CPhys) then
		local Pos, Ang = CPhys:GetPos(), CPhys:GetAngles()
		local Vel = CPhys:WorldToLocalVector(CPhys:GetVelocity()) * InchToMeter
		local AV = CPhys:GetAngleVelocity()
		Bundle.Frames[1] = row({ Head, id(Chassis), Pos.x, Pos.y, Pos.z, Ang.p, Ang.y, Ang.r, Vel.x, Vel.y, Vel.z,
			AV.x, AV.y, AV.z, CPhys:GetVelocity():Length() * InchToMeter * 3.6, CPhys:IsMotionEnabled() and 0 or 1,
			CPhys:IsAsleep() and 1 or 0, #Ctx.WheelList, M.InStep == true })
	else
		Bundle.Frames[1] = row({ Head, -1, "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", #Ctx.WheelList, M.InStep == true })
	end

	for _, E in ipairs(Group or {}) do
		if IsValid(E) then
			local St = E.MobState or {}
			Bundle.Engines[#Bundle.Engines + 1] = row({ Head, id(E), E.Active == true, St.Running == true, St.Stalled == true,
				St.Cranking or 0, E.FlyRPM or 0, E.Throttle or 0, E.Torque or 0, E.PhysMass or 0, E.TotalMass or 0, id(E.MobLeader) })
			if Rec.Last[E] ~= E.Active then
				if Rec.Last[E] ~= nil then Log.Event(E, "engine", E.Active and "switched on" or "switched off") end
				Rec.Last[E] = E.Active
			end
		end
	end

	for _, Box in ipairs(Ctx.BoxList) do
		if IsValid(Box) then
			local D = Box.Mob or {}
			Bundle.Boxes[#Bundle.Boxes + 1] = row({ Head, id(Box), Box.Gear or 0, D.Ratio or 0, Box.LBrake or 0, Box.RBrake or 0,
				M.BrakePedal(Box.LBrake), M.BrakePedal(Box.RBrake), Box.LClutch or 0, Box.RClutch or 0, Box.MobClutchCap or "",
				Box.MobCapFull == true, D.ClutchFree == true, tostring(D.Diff), (D.InputW or 0) * 30 / math.pi, M.IsAssisted(Box),
				D.BrakeOnly == true, Box.SteerRate or 0, (D.Brake or {})[0] or 0, (D.Brake or {})[1] or 0, id(ACE.GetPhysicalParent(Box)) })
			local Key = format("gear %s, brakes %.2f/%.2f, clutch %.0f/%.0f", tostring(Box.Gear), Box.LBrake or 0, Box.RBrake or 0,
				Box.LClutch or 0, Box.RClutch or 0)
			if Rec.Last[Box] ~= Key then
				if Rec.Last[Box] ~= nil then Log.Event(Box, "inputs", Key) end
				Rec.Last[Box] = Key
			end
		end
	end

	local Hubs = {}
	for _, W in ipairs(Ctx.WheelList) do
		local G = W.Ground
		local RelX, RelY, RelZ = "", "", ""
		local Phys, HubPhys = W.Phys, IsValid(W.Hub) and W.Hub:GetPhysicsObject()
		if IsValid(Phys) and IsValid(HubPhys) then
			local Rel = Phys:GetAngleVelocity() - Phys:WorldToLocalVector(worldAngVel(HubPhys))
			RelX, RelY, RelZ = Rel.x, Rel.y, Rel.z
			Hubs[W.Hub] = true
		end
		local Pedal = IsValid(W.Box) and (W.Link and W.Link.Side == 0 and W.Box.LBrake or W.Box.RBrake) or 0
		Bundle.Wheels[#Bundle.Wheels + 1] = row({ Head, id(W.Ent), id(W.Box), W.Link and W.Link.Side or -1, id(W.Hub),
			W.Grounded == true, W.Meshed == true, W.Loaded == true, W.LoadEMA or "", W.FreeTicks or 0, W.Held == true,
			W.HeldStill == true, W.Anchored == true, tostring(W.LockWant), IsValid(W.BrakeLock), W.LockWhy or "",
			W.Braking == true, M.BrakePedal(Pedal), W.BrakeMax or 0, W.BrakeSlipped == true, W.AnchorTorque or "",
			W.Mu or 0, W.Radius or 0, W.J or 0, W.W or 0, W.WOut or 0, W.GroundSpeed or 0,
			(W.GroundSpeed or 0) / math.max(W.Radius or 1, 1e-3), G and G.W or "", G and G.Cap or "", W.Impulse or 0,
			W.GroundImpulse or 0, W.ImpOut or 0, W.AppliedDW or 0, W.TyreImp or "", W.SlideCap or "", W.RollDrag or 0,
			RelX, RelY, RelZ, IsValid(Phys) and Phys:IsAsleep() or false })
	end

	-- Every physical body of the vehicle: what moves when the body swings.
	for Ent in pairs(Rec.Bodies) do
		local P = IsValid(Ent) and Ent:GetPhysicsObject()
		if IsValid(P) then
			local Pos = IsValid(CPhys) and CPhys:WorldToLocal(P:GetPos()) or P:GetPos()
			local Vel = P:GetVelocity() * InchToMeter
			local AV = worldAngVel(P)
			local Rel = IsValid(CPhys) and CPhys:WorldToLocalVector(AV - worldAngVel(CPhys)) or AV
			Bundle.Bodies[#Bundle.Bodies + 1] = row({ Head, id(Ent), Ent == Chassis, Hubs[Ent] == true, Pos.x, Pos.y, Pos.z,
				Vel.x, Vel.y, Vel.z, AV.x, AV.y, AV.z, Rel.x, Rel.y, Rel.z, P:IsMotionEnabled() and 0 or 1, P:IsAsleep() })
		end
	end

	local Buf = Rec.Buffer
	Buf[#Buf + 1] = Bundle
	-- Drop what fell out of the window, in chunks so this stays cheap.
	if Rec.Head > 512 then
		local Kept = {}
		for I = Rec.Head, #Buf do Kept[#Kept + 1] = Buf[I] end
		Rec.Buffer, Rec.Head = Kept, 1
		Buf = Kept
	end
	while Buf[Rec.Head] and Buf[Rec.Head].T < T - Rec.Window do Rec.Head = Rec.Head + 1 end
end

--- Records an event (brake lock made or released, load latch, input change, marker).
-- @param Ent The entity it concerns, or nil.
-- @param Kind Short event name.
-- @param Text Detail.
function Log.Event(Ent, Kind, Text)
	if not Rec then return end
	if Ent and IsValid(Ent) and not Rec.Members[Ent] then return end
	local Events = Rec.Events
	Events[#Events + 1] = row({ format("%.4f", now() - Rec.Start), engine.TickCount(), Rec.FrameNo, Kind,
		Ent and id(Ent) or -1, Ent and IsValid(Ent) and Ent:GetClass() or "", '"' .. tostring(Text or ""):gsub('"', "'") .. '"' })
end

------------------------------------------------------------------------ setup snapshot

local ConVars = { "ace_mobility_instep", "ace_mobility_assisted", "ace_mobility_allow_assisted", "ace_mobility_substeps",
	"ace_mobility_tyre_grip", "ace_mobility_brakeonly_boxes", "ace_mobility_apply", "ace_mobility_brake_full",
	"ace_mobility_measured_grip", "ace_mobility_debug" }

local function setupText()
	local L = {}
	L[#L + 1] = format("ACE mobility log, %s, map %s, tickrate %.1f, physics settings %s", os.date("%Y-%m-%d %H:%M:%S"),
		game.GetMap(), 1 / engine.TickInterval(), util.TableToJSON(physenv.GetPerformanceSettings() or {}))
	L[#L + 1] = "gravity " .. tostring(physenv.GetGravity())
	for _, Name in ipairs(ConVars) do
		local CV = GetConVar(Name)
		L[#L + 1] = format("%s %s", Name, CV and CV:GetString() or "(missing)")
	end
	L[#L + 1] = ""
	L[#L + 1] = "entities: index, class, model, parent, physical parent, mass, frozen, local pos/ang relative to the target"
	local Target = Rec.Target
	local Ents = {}
	for Ent in pairs(Rec.Members) do
		if IsValid(Ent) then Ents[#Ents + 1] = Ent end
	end
	table.sort(Ents, function(A, B) return A:EntIndex() < B:EntIndex() end)
	for _, Ent in ipairs(Ents) do
		local P = Ent:GetPhysicsObject()
		local Extra = ""
		if Ent:GetClass() == "acf_gearbox" then
			local Links = {}
			for _, Link in pairs(Ent.WheelLink or {}) do
				Links[#Links + 1] = format("%d(side %s axis %s)", id(Link.Ent), tostring(Link.Side), tostring(Link.Axis))
			end
			Extra = format(" id %s gears %s final %s maxtorque %s dual %s doublediff %s auto %s cvt %s links [%s]", tostring(Ent.Id),
				tostring(Ent.Gears), tostring(Ent.GearTable and Ent.GearTable.Final), tostring(Ent.MaxTorque), tostring(Ent.Dual),
				tostring(Ent.DoubleDiff), tostring(Ent.Auto), tostring(Ent.CVT), table.concat(Links, " "))
		elseif Ent:GetClass() == "acf_engine" then
			Extra = format(" id %s", tostring(Ent.Id))
		end
		L[#L + 1] = format("%d %s %s parent %d physparent %d mass %s frozen %s pos %s ang %s%s", Ent:EntIndex(), Ent:GetClass(),
			Ent:GetModel() or "", id(Ent:GetParent()), id(ACE.GetPhysicalParent(Ent)), IsValid(P) and num(P:GetMass(), 1) or "-",
			IsValid(P) and tostring(not P:IsMotionEnabled()) or "-",
			IsValid(Target) and tostring(Target:WorldToLocal(Ent:GetPos())) or "", IsValid(Target) and tostring(Target:WorldToLocalAngles(Ent:GetAngles())) or "",
			Extra)
	end
	L[#L + 1] = ""
	L[#L + 1] = "constraints: type, entity 1, entity 2, settings"
	local Seen = {}
	for _, Ent in ipairs(Ents) do
		for _, Con in ipairs(constraint.GetTable(Ent)) do
			local C = Con.Constraint
			if not Seen[C or Con] then
				Seen[C or Con] = true
				local E1 = Con.Entity and Con.Entity[1] and Con.Entity[1].Entity
				local E2 = Con.Entity and Con.Entity[2] and Con.Entity[2].Entity
				local Keys = {}
				for K, V in pairs(Con) do
					local TV = type(V)
					if TV == "number" or TV == "boolean" or TV == "Vector" or TV == "string" and K ~= "Type" then
						Keys[#Keys + 1] = K .. "=" .. tostring(V)
					end
				end
				table.sort(Keys)
				L[#L + 1] = format("%s %d %d %s%s", tostring(Con.Type), id(E1), id(E2), table.concat(Keys, " "),
					IsValid(C) and C.ACE_BrakeLock and " (ACE brake lock)" or "")
			end
		end
	end
	return table.concat(L, "\n") .. "\n"
end

------------------------------------------------------------------------ files

local Headers = {
	frames = "frame,t,tick,kind,dt,chassis,x,y,z,pitch,yaw,roll,vel_fwd,vel_left,vel_up,angvel_x,angvel_y,angvel_z,speed_kmh,frozen,asleep,wheels,instep\n",
	engines = "frame,t,tick,kind,dt,engine,active,running,stalled,cranking,rpm,throttle,torque,phys_mass,total_mass,leader\n",
	boxes = "frame,t,tick,kind,dt,box,gear,ratio,lbrake_in,rbrake_in,lbrake_pedal,rbrake_pedal,lclutch,rclutch,clutch_cap,cap_full,clutch_free,diff,input_rpm,assisted,brake_only,steer,brake_torque_l,brake_torque_r,phys_parent\n",
	wheels = "frame,t,tick,kind,dt,wheel,box,side,hub,grounded,meshed,loaded,load_ema,free_ticks,player_held,held_still,anchored,lock_want,lock_on,lock_why,braking,pedal,brake_max,brake_slipped,anchor_torque,mu,radius,J,w,w_out,ground_speed,ground_speed_as_w,ground_w,ground_cap,impulse,ground_impulse,impulse_applied,applied_dw,tyre_imp,slide_cap,roll_drag,spin_vs_hub_x,spin_vs_hub_y,spin_vs_hub_z,asleep\n",
	bodies = "frame,t,tick,kind,dt,body,is_chassis,is_hub,x,y,z,vel_x,vel_y,vel_z,angvel_x,angvel_y,angvel_z,angvel_vs_chassis_x,angvel_vs_chassis_y,angvel_vs_chassis_z,frozen,asleep\n",
}
local Keys = { frames = "Frames", engines = "Engines", boxes = "Boxes", wheels = "Wheels", bodies = "Bodies" }

local function save(Ply)
	if not Rec then return say(Ply, "not recording. Start with ace_mobility_log_start.") end
	local Dir = "ace_mobility_log/" .. os.date("%Y%m%d_%H%M%S")
	file.CreateDir(Dir)
	file.Write(Dir .. "/setup.txt", setupText())
	file.Write(Dir .. "/events.csv", "t,tick,frame,kind,entity,class,detail\n" .. table.concat(Rec.Events))
	local Count = 0
	for Name, Header in pairs(Headers) do
		local F = file.Open(Dir .. "/" .. Name .. ".csv", "w", "DATA")
		if F then
			F:Write(Header)
			local Key = Keys[Name]
			for I = Rec.Head, #Rec.Buffer do
				local Rows = Rec.Buffer[I][Key]
				for J = 1, #Rows do F:Write(Rows[J]) end
				if Name == "frames" then Count = Count + 1 end
			end
			F:Close()
		end
	end
	say(Ply, format("saved %d solves and %d events to garrysmod/data/%s", Count, #Rec.Events, Dir))
end

local function refreshMembers()
	if not Rec then return end
	if not IsValid(Rec.Target) then
		say(Rec.Owner, "the recorded vehicle is gone; saving and stopping.")
		save(Rec.Owner)
		Rec = nil
		M.Log = nil
		return
	end
	Rec.Members = members(Rec.Target)
	local Bodies = {}
	for Ent in pairs(Rec.Members) do
		if IsValid(Ent) and not IsValid(Ent:GetParent()) and IsValid(Ent:GetPhysicsObject()) then Bodies[Ent] = true end
	end
	Rec.Bodies = Bodies
end

timer.Create("ACE_Mobility_LogMembers", 2, 0, refreshMembers)

------------------------------------------------------------------------ commands

concommand.Add("ace_mobility_log_start", function(Ply, _, Args)
	if not canUse(Ply) then return say(Ply, "only superadmins can record.") end
	local Window = math.Clamp(tonumber(Args[1]) or 30, 5, 600)
	local Target
	if Args[2] then
		Target = Entity(tonumber(Args[2]) or -1)
	elseif IsValid(Ply) then
		Target = IsValid(Ply:GetVehicle()) and Ply:GetVehicle() or Ply:GetEyeTrace().Entity
	end
	if not IsValid(Target) or Target:IsWorld() then
		return say(Ply, "sit in the vehicle or look at it (or give an entity index: ace_mobility_log_start 30 <index>).")
	end
	Rec = {
		Owner = Ply, Target = Target, Window = Window, Start = now(), FrameNo = 0,
		Buffer = {}, Head = 1, Events = {}, Last = {}, Members = {}, Bodies = {},
	}
	M.Log = Log
	refreshMembers()
	local N = 0
	for _ in pairs(Rec.Members) do N = N + 1 end
	local B = 0
	for _ in pairs(Rec.Bodies) do B = B + 1 end
	Log.Event(nil, "start", format("target %s, %d entities, %d physical bodies, keeping %d s", tostring(Target), N, B, Window))
	say(Ply, format("recording %s (%d entities, %d physical bodies), keeping the last %d s. Mark moments with ace_mobility_log_mark, save with ace_mobility_log_save or ace_mobility_log_stop.",
		tostring(Target), N, B, Window))
end)

concommand.Add("ace_mobility_log_mark", function(Ply, _, Args)
	if not canUse(Ply) then return end
	if not Rec then return say(Ply, "not recording.") end
	local Text = #Args > 0 and table.concat(Args, " ") or "mark"
	Log.Event(nil, "mark", Text)
	say(Ply, format("marked at %.2f s: %s", now() - Rec.Start, Text))
end)

concommand.Add("ace_mobility_log_save", function(Ply)
	if not canUse(Ply) then return end
	save(Ply)
end)

concommand.Add("ace_mobility_log_stop", function(Ply)
	if not canUse(Ply) then return end
	if not Rec then return say(Ply, "not recording.") end
	save(Ply)
	Rec = nil
	M.Log = nil
end)
