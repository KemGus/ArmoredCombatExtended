--[[
	Hydrodynamic torque converter.

	Uses the characteristic form of SAE J643 (Hydrodynamic Drive Test Code): input capacity
	factor K = N_pump / √T_pump [rpm/√(N·m)] and torque ratio TR = T_turbine / T_pump, both as
	functions of speed ratio SR = N_turbine / N_pump.

	The curve shape follows a typical three-element converter: TR ≈ 2.0 at stall falling
	linearly to 1.0 at the coupling point SR ≈ 0.87, and K roughly flat to SR ≈ 0.6 before
	rising steeply as SR → 1 (Naunheimer et al., Automotive Transmissions, 2nd ed., §6.3;
	Kotwicki, SAE 820393). Above the coupling point the stator freewheels and the converter
	behaves as a fluid coupling (TR = 1).
]]

ACE = ACE or {}
ACE.Mobility = ACE.Mobility or {}

local TC = {}
ACE.Mobility.TorqueConverter = TC

local abs = math.abs
local sqrt = math.sqrt
local RadToRPM = 30 / math.pi

TC.CouplingSR = 0.87

--- Torque ratio at a speed ratio.
function TC.TorqueRatio(Stall, SR)
	if SR >= TC.CouplingSR then return 1 end
	if SR <= 0 then return Stall end
	return Stall + (1 - Stall) * SR / TC.CouplingSR
end

--- Capacity factor K at a speed ratio, relative to its stall value.
function TC.CapacityScale(SR)
	if SR <= 0.6 then return 1 + 0.1 * SR / 0.6 end
	if SR >= 0.999 then return 1e3 end
	-- Rises from 1.1 at 0.6 towards infinity at SR = 1; 2.5 at the coupling point.
	local X = (SR - 0.6) / 0.4
	return 1.1 / (1 - X) ^ 0.75
end

--- Sizes a converter so the engine reaches StallRPM against a held turbine at full load.
-- @param StallRPM Engine speed at stall.
-- @param StallTorque Engine torque at StallRPM.
-- @param TRStall Torque ratio at stall (typically 1.8-2.4).
-- @return Converter description.
function TC.New(StallRPM, StallTorque, TRStall)
	return {
		KStall = StallRPM / sqrt(math.max(StallTorque, 1)),
		TRStall = TRStall or 2.0,
	}
end

--- Pump and turbine torques for given shaft speeds.
-- @param Conv Converter from TC.New.
-- @param Wp Pump (engine) speed, rad/s.
-- @param Wt Turbine (gearbox input) speed, rad/s.
-- @return Pump torque (load on the engine, N·m) and turbine torque (drive on the gearbox, N·m).
function TC.Torques(Conv, Wp, Wt)
	local Np, Nt = Wp * RadToRPM, Wt * RadToRPM
	if abs(Np) < 1e-3 and abs(Nt) < 1e-3 then return 0, 0 end

	if abs(Np) >= abs(Nt) then
		-- Normal drive: pump faster than turbine.
		local SR = abs(Np) > 1e-3 and Nt / Np or 0
		local K = Conv.KStall * TC.CapacityScale(SR)
		local Tp = (Np / K) ^ 2 * (Np >= 0 and 1 or -1)
		return Tp, Tp * TC.TorqueRatio(Conv.TRStall, SR)
	end

	-- Overrun (engine braking): turbine drives the pump, stator freewheels, TR = 1.
	local SR = Np / Nt
	local K = Conv.KStall * TC.CapacityScale(SR)
	local Tt = (Nt / K) ^ 2 * (Nt >= 0 and 1 or -1)
	return -Tt, -Tt
end

return TC
