--[[
	Scalable gearboxes: pick the layout here, then the size and gear count in the menu.
	Mass, torque rating, shift time and input inertia follow from the size; see
	lua/ace/shared/mobility/gearbox_size.lua. The fixed small/medium/large items in the other
	files of this folder are kept, hidden from the menu, so old contraptions still paste.
]]

local AutoBlurb = "\n\nIn Drive the box picks its own gear from the vehicle speed and the upshift speeds set here. "
	.. "Automatics are heavier than manuals and lose a little more to their torque converter and hydraulics."

local CVTBlurb = "\n\nA CVT keeps the engine inside a target RPM range by changing its ratio continuously, at the cost of weight and belt losses."

local DualBlurb = " A dual clutch lets each side be driven and braked on its own, for skid steering."

local Layouts = {
	{ Suffix = "L", Name = "Inline", Model = "models/engines/linear_s.mdl", Straight = false },
	{ Suffix = "T", Name = "Transaxial", Model = "models/engines/transaxial_s.mdl", Straight = false },
	{ Suffix = "ST", Name = "Straight", Model = "models/engines/t5small.mdl", Straight = true },
}

local Families = {
	{ Id = "Manual", Family = "manual", Gears = 5, Category = "Manual", Name = "Manual",
		Desc = "A manual gearbox: the driver picks the gear and works the clutch." .. DualBlurb,
		Extra = {} },
	{ Id = "Auto", Family = "auto", Gears = 5, Category = "Automatic", Name = "Automatic",
		Desc = "An automatic gearbox with a torque converter." .. AutoBlurb,
		Extra = { auto = true } },
	{ Id = "CVT", Family = "cvt", Gears = 2, Category = "CVT", Name = "CVT",
		Desc = "A continuously variable transmission." .. CVTBlurb,
		Extra = { cvt = true } },
	{ Id = "Transfer", Family = "transfer", Gears = 2, Category = "Transfer", Name = "Transfer case", NoStraight = true,
		Desc = "A two-speed transfer case for low and high range, or a cross drive for tank steering.",
		Extra = { parentable = true } },
	{ Id = "Diff", Family = "diff", Gears = 1, Category = "Differential", Name = "Differential", NoStraight = true,
		Desc = "A differential that carries the drive to an axle.",
		Extra = { parentable = true } },
}

for _, F in ipairs( Families ) do
	for _, L in ipairs( Layouts ) do
		if F.NoStraight and L.Straight then continue end

		local Def = {
			name = F.Name .. ", " .. L.Name,
			desc = F.Desc,
			model = L.Model,
			category = F.Category,
			scalable = true,
			family = F.Family,
			straight = L.Straight,
			weight = 1,
			switch = 0.15,
			maxtq = 1,
			gears = F.Gears,
			geartable = { [ 0 ] = 0, [ -1 ] = 0.5 },
		}
		for Key, Value in pairs( F.Extra ) do Def[Key] = Value end
		if F.Family == "cvt" then
			Def.geartable = { [ -3 ] = 3000, [ -2 ] = 5000, [ -1 ] = 1, [ 0 ] = 0, [ 1 ] = 0, [ 2 ] = -0.1 }
		end

		ACE.DefineGearbox( F.Id .. "-" .. L.Suffix, Def )
	end
end

ACE.DefineGearbox( "Clutch-S", {
	name = "Clutch, Straight",
	desc = "A standalone clutch for when a full gearbox is not needed or too long.",
	model = "models/engines/flywheelclutchs.mdl",
	category = "Clutch",
	scalable = true,
	family = "clutch",
	parentable = true,
	weight = 1,
	switch = 0.15,
	maxtq = 1,
	gears = 0,
	geartable = { [ 0 ] = 1, [ -1 ] = 1 },
} )

ACE.DefineGearbox( "DoubleDiff-T", {
	name = "Double Differential",
	desc = "A regenerative (double differential) steering transmission: it steers by speeding one track up and slowing the other, and can pivot in place.",
	model = "models/engines/transaxial_s.mdl",
	category = "Regenerative Steering",
	scalable = true,
	family = "doublediff",
	parentable = true,
	doublediff = true,
	doubleclutch = true,
	weight = 1,
	switch = 0.2,
	maxtq = 1,
	gears = 1,
	geartable = { [ 0 ] = 0, [ 1 ] = 1, [ -1 ] = 1 },
} )

-- Collision meshes for the scaled models are the models' own, scaled (ace_scalability).
for _, Model in ipairs( { "models/engines/linear_s.mdl", "models/engines/transaxial_s.mdl", "models/engines/t5small.mdl", "models/engines/flywheelclutchs.mdl" } ) do
	ACE.DefineModelData( Model, { Model = Model, DefaultSize = 1 } )
end
