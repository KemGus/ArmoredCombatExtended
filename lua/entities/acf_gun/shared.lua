DEFINE_BASECLASS( "ace_scalability" )

ENT.PrintName		= "ACF Gun"
ENT.WireDebugName	= "ACF Gun"

function ENT:CanTool( ply, tr, mode, tool, button )

	-- The scalability base blocks tools that rebuild physics. Only enforce that
	-- on guns that actually carry a scaled hull so stock guns keep legacy access.
	if self.IsScalable then
		return BaseClass.CanTool( self, ply, tr, mode, tool, button )
	end

	return true

end
