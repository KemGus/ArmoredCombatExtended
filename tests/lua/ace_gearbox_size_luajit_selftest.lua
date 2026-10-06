-- Scalable gearbox sizes (lua/ace/shared/mobility/gearbox_size.lua): legacy items map onto the
-- families at their old scales, and stats follow the scale laws.
local Repo = arg[1] or "."

math.Clamp = function( V, Lo, Hi ) return math.min( math.max( V, Lo ), Hi ) end
math.Round = function( V, D ) local M = 10 ^ ( D or 0 ) return math.floor( V * M + 0.5 ) / M end
isfunction = function( V ) return type( V ) == "function" end
ACE = {}

dofile( Repo .. "/lua/ace/shared/mobility/gearbox_size.lua" )
local Size = ACE.GearboxSize

local Failures = 0
local function check( Cond, Msg )
	if not Cond then
		Failures = Failures + 1
		print( "FAIL: " .. Msg )
	end
end
local function near( A, B, Tol ) return math.abs( A - B ) <= Tol end

-- The small boxes reproduce the legacy stats they were fitted to.
local S4 = Size.Stats( "manual", 1, 4 )
check( S4.Mass == 60 and S4.MaxTorque == 1650, "4-speed small: 60 kg, 1650 Nm, got " .. S4.Mass .. ", " .. S4.MaxTorque )
check( Size.Stats( "manual", 1, 8 ).Mass == 100, "8-speed small weighs 100 kg" )
check( near( Size.Stats( "auto", 1, 5 ).MaxTorque, 1520, 30 ), "5-speed auto small near 1520 Nm" )

-- Scale laws: torque and mass with s^3 (same torque per kilogram), inertia with s^5.
local Big = Size.Stats( "manual", 2, 4 )
check( near( Big.MaxTorque / S4.MaxTorque, 8, 0.05 ), "torque grows with scale cubed" )
check( near( Big.Mass / S4.Mass, 8, 0.05 ), "mass grows with scale cubed" )
check( near( Big.InputJ / S4.InputJ, 32, 0.01 ), "input inertia grows with scale to the fifth" )
check( Big.Switch > S4.Switch, "bigger boxes shift slower" )

-- Clamping.
check( Size.ClampScale( 10 ) == Size.Max and Size.ClampScale( 0 ) == Size.Min, "scale clamps" )
check( Size.ClampGears( Size.Families.manual, 20 ) == 9, "manual gear count clamps to 9" )
check( Size.ClampGears( Size.Families.diff, 5 ) == 1, "fixed families ignore the requested gear count" )

-- Legacy ids map to their family and old scale; layout and clutch stay as they were.
local function legacy( Def )
	local Spec = Size.Resolve( Def )
	return Spec
end
local L = legacy( { id = "4Gear-L-L", gears = 4, category = "4-Speed" } )
check( L.Family == "manual" and L.Scale == 2.5 and L.Gears == 4, "4Gear-L-L is a 4-speed manual at 2.5" )
local ST = legacy( { id = "6Gear-ST-L", gears = 6, category = "6-Speed" } )
check( ST.Scale == 2, "straight large models are scale 2" )
local A = legacy( { id = "7Gear-A-TD-M", gears = 7, auto = true, doubleclutch = true, category = "Automatic" } )
check( A.Family == "auto" and A.Scale == 1.5 and A.Dual, "7Gear-A-TD-M is a dual-clutch automatic at 1.5" )
check( legacy( { id = "Clutch-S-T", gears = 0, category = "Clutch" } ).Scale == 0.75, "tiny clutch is 0.75" )
check( legacy( { id = "2Gear-L-M-NC", gears = 2, category = "Transfer" } ).Family == "transfer", "single-clutch transfer" )
check( legacy( { id = "DoubleDiff-T-L", gears = 1, doublediff = true, doubleclutch = true, category = "Regenerative Steering" } ).Family == "doublediff", "double diff" )

-- Scalable ids take the builder's choices.
local Scal = Size.Resolve( { scalable = true, family = "manual" }, 1.5, 6, 1 )
check( Scal.Scale == 1.5 and Scal.Gears == 6 and Scal.Dual and Scal.Scaled, "scalable manual takes size, gears and dual" )
check( Size.Resolve( { scalable = true, family = "transfer" }, 1 ).Dual, "transfer cases default to dual clutch" )
check( Size.Resolve( { scalable = true, family = "doublediff" }, 1, 1, 0 ).Dual, "double diffs always have two clutches" )
check( not Size.Resolve( { scalable = true, family = "clutch" }, 1, 0, 1 ).Dual, "a standalone clutch has one clutch" )

-- Compound manuals: 5 main gears (the 5th a reverse) x range x splitter.
local Speeds = Size.Expand( { 0.1, 0.2, 0.3, 0.4, -0.1 }, 3.5, 1.2 )
check( #Speeds == 20, "5 main gears with range and splitter give 20 speeds, got " .. #Speeds )
local Ordered = true
for I = 2, 16 do
	if Speeds[I].Value < Speeds[I - 1].Value then Ordered = false end
end
check( Ordered, "forward speeds run slowest first" )
check( Speeds[1].Low and Speeds[1].SplitLow and Speeds[1].Main == 1, "1st speed is gear 1, low range, low split" )
check( Speeds[16].Value == 0.4 and not Speeds[16].Low, "top speed is gear 4 high range direct" )
check( Speeds[17].Value < 0 and Speeds[20].Value < 0, "the four reverse speeds come last" )
local Split = Size.CompoundShiftTime( Speeds[1], Speeds[2], 0.2 )
check( Split > 0 and Split < 0.2, "a split-only shift is quicker than a gear shift" )
local Main1, Main2
for _, Sp in ipairs( Speeds ) do
	if Sp.Main == 4 and Sp.Low and not Sp.SplitLow then Main1 = Sp end
	if Sp.Main == 1 and not Sp.Low and Sp.SplitLow then Main2 = Sp end
end
check( Size.CompoundShiftTime( Main1, Main2, 0.2 ) >= 0.4 - 1e-9, "a range change takes about twice a gear shift" )
local Plain = Size.Stats( "manual", 1, 5 )
local Compound = Size.Stats( "manual", 1, 5, false, 3.5, 1.2 )
check( Compound.Mass > Plain.Mass and Compound.MaxTorque == Plain.MaxTorque, "range and splitter add weight, not rating" )
check( Size.Resolve( { scalable = true, family = "auto" }, 1, 5, 0, 3.5, 1.2 ).Range == nil, "only manuals take range and splitter" )
check( Size.Resolve( { scalable = true, family = "manual" }, 1, 5, 0, 0, 0 ).Range == nil, "0 means no range section" )

if Failures > 0 then
	print( Failures .. " gearbox size check(s) failed" )
	os.exit( 1 )
end
print( "gearbox size: all checks passed" )
