-- ACE Customs: what the mobility branch adds to ACE's lua/ace/server/sv_acfbase.lua.

--- Whether a player wants engine and drivetrain hints (client setting ace_engine_hints, on by
-- default, in the ACE menu's client settings).
-- @param ply Player
-- @return boolean
function ACE.WantsEngineHints( ply )
	return IsValid( ply ) and ply:IsPlayer() and ply:GetInfoNum( "ace_engine_hints", 1 ) ~= 0
end

--- Sends an engine or drivetrain hint to a player's chat, unless they turned those hints off.
-- @param ply Player, usually the engine's owner.
-- @param message string
-- @param color Color|nil
-- @return boolean Whether it was sent.
function ACE.SendEngineHint( ply, message, color )
	if not ACE.WantsEngineHints( ply ) then return false end
	ACE.ChatMessagePly( ply, message, color )
	return true
end
