include("shared.lua")

-- Client realm: scaling is handled entirely by the ace_scalability base class
-- (the global ACE_Scalable_Network receiver + render matrix). ENT:Initialize is
-- inherited from the base so a joining client still requests this brick's render
-- scale. We only add the info bubble / wire render here. The ERA configuration UI
-- lives in the ACF Armor Properties tool, not on the entity.

function ENT:Draw()
	self.BaseClass.DoNormalDraw(self, false, false)
	Wire_Render(self)
end
