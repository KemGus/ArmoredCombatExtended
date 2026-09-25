--- Client side of the ACF library: controls how ACE sounds reach the local player.
-- @name acf
-- @class library
-- @libtbl acf_library
SF.RegisterLibrary("acf")

local registerprivilege = SF.Permissions.registerPrivilege

registerprivilege("acf.cabinOpening", "Set ACE cabin opening", "Allows the chip to open or close the local player's vehicle cabin for engine sound muffling", { client = { default = 1 } })

return function(instance)
local checkpermission = instance.player ~= SF.Superuser and SF.Permissions.check or function() end
local checkluatype = SF.CheckLuaType

local acf_library = instance.Libraries.acf

-- Only the chip's owner, or a chip on the vehicle the local player sits in, may change it.
local function mayControlCabin()
	local Ply = LocalPlayer()
	if instance.player == Ply then return true end

	local Seat = IsValid(Ply) and Ply:GetVehicle()
	if not IsValid(Seat) or not IsValid(instance.entity) then return false end

	return ACE.GetPhysicalParent(Seat) == ACE.GetPhysicalParent(instance.entity)
end

local Changed = false

instance:AddHook("deinitialize", function()
	if Changed and ACE.EngineSound then
		ACE.EngineSound.CabinOpening = 0
	end
end)

--- Opens or closes the cabin for engine sound muffling on this client, like a window or hatch.
-- Banks with Cabin muffling set are muffled by (1 - fraction) while the local player sits in
-- their vehicle in first person. Goes back to closed when the chip is removed.
-- Works for the chip's owner, or when the local player sits in the chip's vehicle.
-- @client
-- @param number fraction 0 = closed (full muffling) .. 1 = open (no muffling).
function acf_library.setCabinOpening(fraction)
	checkpermission(instance, nil, "acf.cabinOpening")
	checkluatype(fraction, TYPE_NUMBER)

	if not ACE or not ACE.EngineSound or not mayControlCabin() then return end

	ACE.EngineSound.CabinOpening = math.Clamp(fraction, 0, 1)
	Changed = true
end

--- Returns the cabin opening set by setCabinOpening.
-- @client
-- @return number 0 = closed .. 1 = open.
function acf_library.getCabinOpening()
	return ACE and ACE.EngineSound and ACE.EngineSound.CabinOpening or 0
end

end
