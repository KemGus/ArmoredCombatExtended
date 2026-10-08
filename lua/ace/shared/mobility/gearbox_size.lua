--[[
	Scalable gearboxes: one gearbox family per layout (inline, transaxial, straight-through) whose
	size and gear count the builder picks, instead of fixed small/medium/large items.

	Scale s is the linear size relative to the small model (1). Everything follows from geometric
	similarity at the same material and stress:
	  Torque rating ~ s^3. A gear tooth's bending strength is F = sigma * b * m * Y (Lewis
	    bending equation, engineersedge.com/gears/lewis-factor.htm): face width b and module m both
	    grow with s, so the tooth force grows with s^2 and the torque (force times pitch radius)
	    with s^3. A shaft in torsion carries T = tau * pi * d^3 / 16
	    (en.wikipedia.org/wiki/Torsion_(mechanics)), also s^3.
	  Mass ~ s^3: volume. Rating and mass grow together, so torque per kilogram stays the same,
	    as in real gearboxes: about 10 N·m/kg from car manuals (around 400 N·m at 40-45 kg) to
	    heavy-truck boxes (about 2,600 N·m at 280 kg), from manufacturer data sheets (recalled, not
	    re-checked). ACE's own torque per kilogram (its legacy small gearboxes) is kept.
	  Input inertia ~ s^5: mass times radius squared.
	Each extra gear pair makes the box longer (mass grows linearly with the gear count) and, for
	the same housing, the gears share the face width, so the rating falls by a fixed share per
	extra gear. Both are fitted to ACE's legacy small gearboxes (4/6/8-speed manuals, 3/5/7-speed
	automatics), which already followed this pattern.
	Shift time grows slowly with size: fitted to the legacy 0.15 / 0.2 / 0.3 s of the small,
	medium and large boxes (about s^0.6).

	Legacy items (4Gear-L-S, 3Gear-A-T-L, ...) keep their model and wire inputs, and take their
	stats from the family at the scale their model has: tiny 0.75, small 1, medium 1.5, large 2.5
	(2 for the straight-through large model), as ACF-3 maps them (lua/acf/compatibility/acf3/
	gearboxes.lua, pre-scalable aliases).
]]

ACE = ACE or {}
local Size = {}
ACE.GearboxSize = Size

Size.Min = 0.3
Size.Max = 3

-- Straight-through boxes carry a little more torque for their weight (shorter, one shaft line).
local StraightMass, StraightTorque = 0.75, 1.25

--[[
	Families. Mass and Torque give the small (scale 1) box; for families with a gear count they
	are functions of it. Gears: { Min, Max, Default }. Fixed: a gear count that cannot change.
]]
Size.Families = {
	manual = {
		Mass = function( N ) return 20 + 10 * N end,        -- 4: 60, 6: 80, 8: 100 kg
		Torque = function( N ) return 1650 * 0.92 ^ ( N - 4 ) end, -- 4: 1650, 6: 1397, 8: 1182 N·m
		Gears = { 1, 9, 5 }, Switch = 0.15, InputJ = 0.02, CanDual = true, CanCompound = true,
	},
	auto = {
		Mass = function( N ) return 45 + 15 * N end,        -- 3: 90, 5: 120, 7: 150 kg
		Torque = function( N ) return 1750 * 0.925 ^ ( N - 3 ) end, -- 3: 1750, 5: 1497, 7: 1281 N·m
		Gears = { 1, 7, 5 }, Switch = 0.25, InputJ = 0.03, CanDual = true,
	},
	cvt = { Mass = 65, Torque = 880, Fixed = 2, Switch = 0.15, InputJ = 0.03, CanDual = true },
	clutch = { Mass = 5, Torque = 1140, Fixed = 0, Switch = 0.15, InputJ = 0.01 },
	diff = { Mass = 10, Torque = 42500, Fixed = 1, Switch = 0.3, InputJ = 0.02 },
	transfer = { Mass = 20, Torque = 42500, Fixed = 2, Switch = 0.3, InputJ = 0.02, CanDual = true, DualDefault = true },
	doublediff = { Mass = 45, Torque = 35000, Fixed = 1, Switch = 0.2, InputJ = 0.02, DualForced = true },
}

local function value( V, N )
	if isfunction( V ) then return V( N ) end
	return V
end

--- Clamps a requested scale to the allowed range.
-- @param Scale number|string|nil
-- @return number
function Size.ClampScale( Scale )
	Scale = tonumber( Scale ) or 1
	return math.Clamp( math.Round( Scale, 2 ), Size.Min, Size.Max )
end

--- Gear count a family allows, clamped.
-- @param Family table Entry of Size.Families.
-- @param Gears number|string|nil
-- @return number
function Size.ClampGears( Family, Gears )
	if Family.Fixed then return Family.Fixed end
	local Range = Family.Gears
	return math.Clamp( math.floor( tonumber( Gears ) or Range[3] ), Range[1], Range[2] )
end

--- Physical stats of a gearbox of one family at a scale and gear count.
-- @param FamilyId string Key of Size.Families.
-- @param Scale number Linear size, 1 = the small model.
-- @param Gears number Forward gear count (ignored by fixed families).
-- @param Straight boolean Straight-through layout.
-- @param Range number|nil Range section reduction (nil: none).
-- @param Split number|nil Splitter step (nil: none).
-- @return table { Mass (kg), MaxTorque (N·m), Switch (s), InputJ (kg·m²) }
function Size.Stats( FamilyId, Scale, Gears, Straight, Range, Split )
	local Family = Size.Families[FamilyId] or Size.Families.manual
	local N = Size.ClampGears( Family, Gears )
	local S3 = Scale ^ 3
	local Mass = value( Family.Mass, N ) * S3 * ( Straight and StraightMass or 1 )
		* ( Range and Size.RangeMass or 1 ) * ( Split and Size.SplitMass or 1 )
	local Torque = value( Family.Torque, N ) * S3 * ( Straight and StraightTorque or 1 )
	return {
		Mass = math.max( math.Round( Mass, 1 ), 1 ),
		-- Rounded to 10 N·m, as a data sheet would quote it.
		MaxTorque = math.max( math.floor( Torque / 10 + 0.5 ) * 10, 10 ),
		Switch = Family.Switch * Scale ^ 0.6,
		-- Floored so a tiny box's input shaft does not make the drivetrain solve stiff.
		InputJ = math.max( Family.InputJ * Scale ^ 5, 0.001 ),
		Gears = N,
	}
end

--[[
	Compound manuals: how truck gearboxes get 10 to 18 speeds out of a 4-6 speed main section
	(Eaton Fuller, ZF Ecosplit / AS-Tronic).
	  Range section: a planetary stage behind the main box, low (reduction) or high (direct). It
	    doubles the speeds: the main gears are run through once in low range, then again in high.
	    Low range ratios run about 3-4:1 so the high-range gears carry on where the low ones stop
	    (an Eaton RTLO 10-speed: about 3.5:1, recalled from data sheets, not re-checked).
	  Splitter: a small input stage with two close ratios, low (a small reduction) or direct. It
	    splits every main gear into two close steps, about 1.15-1.3:1 (ZF 16S splitter steps ~1.2,
	    recalled), which keeps a diesel inside its narrow powerband.
	Speeds = main gears x 2 (range) x 2 (splitter): 5 + range + splitter = 20.
	Mass: the range planetary adds about 15 % and the splitter about 8 % to the box (estimated
	from 10- vs 18-speed truck box weights, about 290 vs 340 kg). The rating stays the main
	section's: the range planetary is sized to carry the low-range output.
	Shift time: a splitter shift is air-operated and preselected, done in a clutch dip (about
	0.6 of a main gear shift); a range shift moves the planetary's synchroniser and takes about
	twice a main gear shift (both estimated).
]]
Size.RangeMass, Size.SplitMass = 1.15, 1.08
Size.RangeDefault, Size.RangeMin, Size.RangeMax = 3.5, 1.5, 6
Size.SplitDefault, Size.SplitMin, Size.SplitMax = 1.2, 1.05, 2
Size.SplitShift, Size.RangeShift = 0.6, 2

local function compoundRatio( Value, Lo, Hi )
	Value = tonumber( Value ) or 0
	if Value <= 1 then return nil end
	return math.Clamp( math.Round( Value, 2 ), Lo, Hi )
end

--- Range section reduction from a stored value: nil (no range section) for 0 or below 1.
-- @param Value number|string|nil
-- @return number|nil
function Size.ClampRange( Value ) return compoundRatio( Value, Size.RangeMin, Size.RangeMax ) end

--- Splitter step from a stored value: nil (no splitter) for 0 or below 1.
-- @param Value number|string|nil
-- @return number|nil
function Size.ClampSplit( Value ) return compoundRatio( Value, Size.SplitMin, Size.SplitMax ) end

--- Every speed a compound manual has, lowest first, then its reverse speeds.
-- Gear values are ACE's output/input speed (0.25 = 4:1); low range and low split divide them.
-- @param Main table Main section gear values, 1..N (zeros are skipped).
-- @param Range number|nil Range reduction, nil for none.
-- @param Split number|nil Splitter step, nil for none.
-- @return table Array of { Value, Main (index), Low (range low), SplitLow }.
function Size.Expand( Main, Range, Split )
	local Forward, Reverse = {}, {}
	for I, V in ipairs( Main ) do
		if V ~= 0 then
			for _, Low in ipairs( Range and { true, false } or { false } ) do
				for _, SplitLow in ipairs( Split and { true, false } or { false } ) do
					local Value = V / ( Low and Range or 1 ) / ( SplitLow and Split or 1 )
					local Speed = { Value = Value, Main = I, Low = Low, SplitLow = SplitLow }
					if V > 0 then Forward[#Forward + 1] = Speed else Reverse[#Reverse + 1] = Speed end
				end
			end
		end
	end
	local function slowestFirst( A, B ) return math.abs( A.Value ) < math.abs( B.Value ) end
	table.sort( Forward, slowestFirst )
	table.sort( Reverse, slowestFirst )
	for _, Speed in ipairs( Reverse ) do Forward[#Forward + 1] = Speed end
	return Forward
end

--- Shift time between two speeds of a compound manual: the slowest of what has to move.
-- @param From table|nil Speed from Size.Expand (nil: neutral).
-- @param To table|nil Speed from Size.Expand (nil: neutral).
-- @param Switch number The box's main gear shift time [s].
-- @return number Seconds.
function Size.CompoundShiftTime( From, To, Switch )
	if not From or not To or From.Main ~= To.Main then
		local T = Switch
		if From and To and From.Low ~= To.Low then T = math.max( T, Switch * Size.RangeShift ) end
		return T
	end
	local T = 0
	if From.Low ~= To.Low then T = math.max( T, Switch * Size.RangeShift ) end
	if From.SplitLow ~= To.SplitLow then T = math.max( T, Switch * Size.SplitShift ) end
	return T
end

--[[
	Legacy ids -> family, scale and gear count. Built from the id pattern of the old items:
	"<n>Gear-<layout>-<size>" manuals, "<n>Gear-A-<layout>-<size>" automatics, "CVT-<layout>-<size>",
	"Clutch-S-<size>", "1Gear-<layout>-<size>" differentials, "2Gear-<layout>-<size>[-NC]" transfer
	cases, "DoubleDiff-T-<size>".
]]
local SizeScale = { T = 0.75, S = 1, M = 1.5, L = 2.5 }

--- Family, scale and gear count of a legacy gearbox definition.
-- @param Def table Gearbox definition (ACE.Weapons.Gearboxes entry).
-- @return string|nil FamilyId
-- @return number Scale
-- @return number Gears
-- @return boolean Straight
function Size.LegacyOf( Def )
	if not Def or Def.scalable then return end
	local Id = Def.id or ""
	local Letter = string.match( Id, "%-(%a)$" ) or string.match( Id, "%-(%a)%-NC$" ) or "S"
	local Straight = string.find( Id, "%-ST%-" ) ~= nil
	local Scale = SizeScale[Letter] or 1
	if Straight and Letter == "L" then Scale = 2 end

	local Family
	if Def.doublediff then
		Family = "doublediff"
	elseif Def.cvt then
		Family = "cvt"
	elseif Def.auto then
		Family = "auto"
	elseif ( Def.gears or 0 ) == 0 then
		Family = "clutch"
		if Letter == "T" then Scale = 0.75 end
	elseif Def.category == "Transfer" then
		Family = "transfer"
	elseif Def.category == "Differential" then
		Family = "diff"
	else
		Family = "manual"
	end
	return Family, Scale, Def.gears or 0, Straight
end

--- Everything a gearbox entity needs from its id and the builder's size choices.
-- Legacy ids ignore Scale/Gears/Dual and use their own model, gear count and clutch layout.
-- @param Def table Gearbox definition.
-- @param Scale number|nil Requested scale (scalable ids).
-- @param Gears number|nil Requested forward gear count (scalable ids).
-- @param Dual any Requested dual clutch (scalable ids): 1/true or 0/false/nil.
-- @param Range any Range section reduction (scalable manuals), 0 or nil for none.
-- @param Split any Splitter step (scalable manuals), 0 or nil for none.
-- @return table Spec with Family, Scale, Gears (main section), Dual, Range, Split, Mass,
-- MaxTorque, Switch, InputJ, Scaled.
function Size.Resolve( Def, Scale, Gears, Dual, Range, Split )
	if Def.scalable then
		local Family = Size.Families[Def.family]
		Scale = Size.ClampScale( Scale )
		if Family.CanCompound then
			Range, Split = Size.ClampRange( Range ), Size.ClampSplit( Split )
		else
			Range, Split = nil, nil
		end
		local Spec = Size.Stats( Def.family, Scale, Gears, Def.straight, Range, Split )
		Spec.Range, Spec.Split = Range, Split
		Spec.Family = Def.family
		Spec.Scale = Scale
		local WantDual = Dual == true or tonumber( Dual ) == 1
		if Dual == nil or Dual == "" then WantDual = Family.DualDefault or false end
		Spec.Dual = Family.DualForced or ( Family.CanDual and WantDual ) or false
		Spec.Scaled = math.abs( Scale - 1 ) > 1e-3
		return Spec
	end

	local Family, LegacyScale, LegacyGears, Straight = Size.LegacyOf( Def )
	local Spec = Size.Stats( Family, LegacyScale, LegacyGears, Straight )
	Spec.Family = Family
	Spec.Scale = LegacyScale
	Spec.Gears = Def.gears or 0
	Spec.Dual = Def.doubleclutch or false
	Spec.Scaled = false
	return Spec
end

--- Name shown for a spawned gearbox: a scalable one adds its gear count and dual clutch.
-- @param Def table Gearbox definition.
-- @param Spec table From Size.Resolve.
-- @return string
function Size.DisplayName( Def, Spec )
	local Name = Def.name or "Gearbox"
	if not Def.scalable then return Name end
	local Family = Size.Families[Def.family] or {}
	if not Family.Fixed then
		if Spec.Range or Spec.Split then
			Name = Name .. ", " .. Spec.Gears .. " gears" .. ( Spec.Range and " x range" or "" ) .. ( Spec.Split and " x splitter" or "" )
		else
			Name = Name .. ", " .. Spec.Gears .. "-speed"
		end
	end
	if Spec.Dual and not Family.DualForced then Name = Name .. ", Dual Clutch" end
	return Name .. string.format( " (size %.2f)", Spec.Scale )
end
