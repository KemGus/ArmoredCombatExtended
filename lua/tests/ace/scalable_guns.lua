-- GLuaTest coverage for the ACE.GunScale scalable-gun pipeline:
-- kernel registration, legacy + parameterized spawning, ammo linking rules
-- and dupe-field round trips. Runs on a real GMod server via GLuaTest.

local function makeTestOwner()
	local entityMeta = FindMetaTable( "Entity" )
	-- Headless-only compatibility shims: native tests have no player/CPPI addon.
	if entityMeta and not entityMeta.CPPISetOwner then
		entityMeta.CPPISetOwner = function( self, owner ) self._TestCPPIOwner = owner end
	end
	if entityMeta and not entityMeta.UniqueID then
		entityMeta.UniqueID = function( self ) return "ACE_HEADLESS_" .. self:EntIndex() end
	end
	local owner = ents.Create( "prop_physics" )
	owner:SetModel( "models/props_c17/oildrum001.mdl" )
	owner:SetPos( Vector( 0, 0, 64 ) )
	owner:Spawn()
	owner.CheckLimit = function() return true end
	owner.AddCount = function() end
	owner.AddCleanup = function() end
	return owner
end

local function spawnGun( owner, pos, id, opts )
	local gun = ACE.MakeGun( owner, pos, Angle( 0, 0, 0 ), id, opts )
	-- Not expect(): helpers keep the file environment, where GLuaTest's
	-- sandboxed expect global is not visible. assert errors are still
	-- reported as test failures by the runner.
	assert( IsValid( gun ), "spawnGun: MakeGun returned an invalid entity" )
	return gun
end

return {
	groupName = "ACE scalable gun kernel and entity tests",
	cases = {
		{
			name = "registers the ACE.GunScale kernel",
			func = function()
				expect( ACE.GunScale ).to.exist()
				expect( ACE.GunScale.ParseKey ).to.beA( "function" )
				expect( ACE.GunScale.Limits ).to.beA( "function" )
				expect( ACE.GunScale.Normalize ).to.beA( "function" )
				expect( ACE.GunScale.Stats ).to.beA( "function" )
				expect( ACE.GunScale.AmmoFits ).to.beA( "function" )
				expect( ACE.GunScale.ResolveDef ).to.beA( "function" )
			end
		},
		{
			name = "exposes a scaling envelope on regular gun classes",
			func = function()
				local Limits = ACE.GunScale.Limits( "120mmC" )
				expect( Limits ).to.exist()
				expect( Limits.basecal ).to.equal( 12 )
				expect( Limits.baselen ).to.equal( 45 )
				expect( Limits.calmin ).to.equal( 3.7 )
				expect( Limits.calmax ).to.equal( 20 )
				expect( Limits.lenmin ).to.equal( 15 )
				expect( Limits.lenmax ).to.beGreaterThan( 45 )

				-- Every gun class scales now. The utility classes are caliber-only:
				-- the length axis locks.
				for _, id in ipairs( { "30mmHMG", "40mmGL", "40mmFGL", "20mmRAC", "40mmSL", "14.5mmATR", "20mmMG" } ) do
					local lim = ACE.GunScale.Limits( id )
					expect( lim ).to.exist()
					if lim then
						expect( lim.lenmin ).to.equal( lim.lenmax )
					end
				end
				expect( ACE.GunScale.IsScalableId( "120mmC" ) ).to.equal( true )
				expect( ACE.GunScale.IsScalableId( "20mmMG" ) ).to.equal( true )
			end
		},
		{
			name = "parses parameterized ids and builds keys",
			func = function()
				local base, cal, len = ACE.GunScale.ParseKey( "120mmC@140x55" )
				expect( base ).to.equal( "120mmC" )
				expect( cal ).to.equal( 140 )
				expect( len ).to.equal( 55 )

				expect( ACE.GunScale.Key( "120mmC", 140, 55 ) ).to.equal( "120mmC@140x55" )
				expect( ACE.GunScale.ResolveDef( "120mmC@140x55" ) ).to.equal( ACE.Weapons.Guns["C"] )
				expect( ACE.CheckGun( "120mmC@140x55" ) ).to.equal( true )
			end
		},
		{
			name = "spawns a base-spec gun through the legacy signature",
			func = function()
				local owner = makeTestOwner()
				local gun = spawnGun( owner, Vector( 0, 0, 64 ), "120mmC" )

				expect( gun.Id ).to.equal( "120mmC" )
				expect( gun.Caliber ).to.equal( 12 )
				expect( gun.Mass ).to.equal( 2100 )
				expect( gun.ScalableSpec ).to.exist()
				-- Identity scale keeps the stock hull: IsScalable stays unset.
				expect( gun.IsScalable ).to.equal( nil )
				expect( gun.GunOpts ).to.equal( "" )
				expect( gun.Muzzle ).to.exist()

				gun:Remove()
				owner:Remove()
			end
		},
		{
			name = "spawns a scaled gun with effective stats",
			func = function()
				local owner = makeTestOwner()
				local gun = spawnGun( owner, Vector( 0, 0, 64 ), "120mmC", "140x55" )

				expect( gun.CaliberMM ).to.equal( 140 )
				expect( gun.BoreLength ).to.equal( 55 )
				expect( gun.Caliber ).to.equal( 14 )
				expect( gun.IsScalable ).to.equal( true )
				expect( gun.Mass ).to.beGreaterThan( 2100 )
				expect( gun.ScaleData ).to.exist()
				expect( gun.ScaleData.Scale.x ).to.beGreaterThan( 1 )
				expect( gun.ScaleData.Scale.y ).to.beGreaterThan( 1 )
				-- Piecewise tube stretch: hull and render split at the barrel
				-- joint so the breech keeps only the caliber scale.
				expect( gun.ScaleData.Split ).to.exist()
				expect( gun.ScaleData.LenScale ).to.beGreaterThan( 1 )
				expect( gun.TubeSplit ).to.equal( gun.ScaleData.Split )
				expect( gun.GunOpts ).to.equal( "140x55" )
				expect( gun.GunKey ).to.equal( "C@140x55" )
				expect( gun.MVMod ).to.beGreaterThan( 1 )
				expect( gun.ChamberLen ).to.beGreaterThan( 110 )
				expect( gun.Muzzle ).to.exist()

				-- Piecewise muzzle: the attach point slides rigidly past the
				-- tube end, so x' = 207.9 + (55/45 - 1) * 188.4, then the 14/12
				-- caliber scale applies.
				local expected = ( 207.9 + ( 55 / 45 - 1 ) * 188.4 ) * 14 / 12
				expect( math.abs( gun.Muzzle.x - expected ) ).to.beLessThan( 5 )

				gun:Remove()
				owner:Remove()
			end
		},
		{
			name = "accepts parameterized ids from dupe data",
			func = function()
				local owner = makeTestOwner()
				local gun = spawnGun( owner, Vector( 0, 0, 64 ), "120mmC@130x50" )

				expect( gun.CaliberMM ).to.equal( 130 )
				expect( gun.BoreLength ).to.equal( 50 )
				expect( gun.Id ).to.equal( "120mmC" )

				gun:Remove()
				owner:Remove()
			end
		},
		{
			name = "clamps out-of-envelope parameters",
			func = function()
				local owner = makeTestOwner()
				local Limits = ACE.GunScale.Limits( "120mmC" )
				local gun = spawnGun( owner, Vector( 0, 0, 64 ), "120mmC", "999x999" )

				expect( gun.CaliberMM ).to.beLessThan( Limits.calmax * 10 + 0.01 )
				expect( gun.BoreLength ).to.beLessThan( Limits.lenmax + 0.01 )

				gun:Remove()
				owner:Remove()
			end
		},
		{
			name = "spawns a caliber-only gun with a locked length axis",
			func = function()
				local owner = makeTestOwner()
				local Limits = ACE.GunScale.Limits( "120mmM" )
				expect( Limits ).to.exist()
				-- Mortars scale caliber only: lenmin == lenmax == baselen.
				expect( Limits.lenmin ).to.equal( Limits.lenmax )

				local gun = spawnGun( owner, Vector( 0, 0, 64 ), "120mmM", "140" )
				expect( gun.CaliberMM ).to.equal( 140 )
				expect( gun.BoreLength ).to.equal( Limits.baselen )
				expect( gun.IsScalable ).to.equal( true )
				expect( gun.ScaleData ).to.exist()
				-- No barrel split: the whole model keeps a uniform scale.
				expect( gun.ScaleData.Split ).to.equal( nil )
				expect( gun.GunOpts ).to.equal( "140" )
				expect( gun.GunKey ).to.equal( "MO@140" )

				gun:Remove()
				owner:Remove()
			end
		},
		{
			name = "spawns a semiautocannon on the rebuilt rig",
			func = function()
				local owner = makeTestOwner()
				local gun = spawnGun( owner, Vector( 0, 0, 64 ), "45mmSA", "50x55" )

				expect( gun.CaliberMM ).to.equal( 50 )
				expect( gun.BoreLength ).to.equal( 55 )
				expect( gun.IsScalable ).to.equal( true )
				expect( gun.ScaleData ).to.exist()
				expect( gun.ScaleData.Split ).to.exist()
				expect( gun.ScaleData.Split.bore.y ).to.equal( -1 )
				expect( gun.GunOpts ).to.equal( "50x55" )
				expect( gun.GunKey ).to.equal( "SA@50x55" )

				gun:Remove()
				owner:Remove()
			end
		},
		{
			name = "builds scaled rounds through keyed ammo ids",
			func = function()
				local owner = makeTestOwner()
				local crate = ACE.MakeAmmo( owner, Vector( 0, 64, 64 ), Angle( 0, 0, 0 ),
					"Shell120mm", "120mmC@140", "AP", 40, 60 )
				expect( IsValid( crate ) ).to.equal( true )

				expect( crate.RoundId ).to.equal( "120mmC@140" )
				expect( crate.BulletData ).to.exist()
				expect( crate.BulletData.Id ).to.equal( "120mmC@140" )
				expect( math.abs( crate.BulletData.Caliber - 14 ) ).to.beLessThan( 0.01 )

				crate:Remove()
				owner:Remove()
			end
		},
		{
			name = "links a scaled gun to a matching-caliber crate",
			func = function()
				local owner = makeTestOwner()
				local gun = spawnGun( owner, Vector( 0, 0, 64 ), "120mmC", "140x55" )
				local crate = ACE.MakeAmmo( owner, gun:GetPos() + Vector( 0, 64, 0 ), Angle( 0, 0, 0 ),
					"Shell120mm", "120mmC@140", "AP", 40, 60 )
				expect( IsValid( crate ) ).to.equal( true )

				local ok = gun:Link( crate )
				expect( ok ).to.equal( true )

				crate:Remove()
				gun:Remove()
				owner:Remove()
			end
		},
		{
			name = "links a base-spec gun to a plain unkeyed crate",
			func = function()
				local owner = makeTestOwner()
				local gun = spawnGun( owner, Vector( 0, 0, 64 ), "120mmC" )
				local crate = ACE.MakeAmmo( owner, gun:GetPos() + Vector( 0, 64, 0 ), Angle( 0, 0, 0 ),
					"Shell120mm", "120mmC", "AP", 40, 60 )
				expect( IsValid( crate ) ).to.equal( true )

				-- The degenerate compat case: the class is scalable, but a base-spec
				-- gun must still feed from the plain crates old contraptions use.
				local ok = gun:Link( crate )
				expect( ok ).to.equal( true )

				crate:Remove()
				gun:Remove()
				owner:Remove()
			end
		},
		{
			name = "rejects a mismatched-caliber crate on a scaled gun",
			func = function()
				local owner = makeTestOwner()
				local gun = spawnGun( owner, Vector( 0, 0, 64 ), "120mmC", "140x55" )
				-- Base-spec round: 120mm against a 140mm gun.
				local crate = ACE.MakeAmmo( owner, gun:GetPos() + Vector( 0, 64, 0 ), Angle( 0, 0, 0 ),
					"Shell120mm", "120mmC", "AP", 40, 60 )
				expect( IsValid( crate ) ).to.equal( true )

				local ok, reason = gun:Link( crate )
				expect( ok ).to.equal( false )
				expect( reason ).to.equal( "Wrong caliber!" )

				crate:Remove()
				gun:Remove()
				owner:Remove()
			end
		},
		{
			name = "round-trips scale options through dupe fields",
			func = function()
				local owner = makeTestOwner()
				local gun = spawnGun( owner, Vector( 0, 0, 64 ), "120mmC", "140x55" )

				-- The duplicator stores GunOpts; pasting feeds it back to MakeGun.
				expect( gun.GunOpts ).to.equal( "140x55" )
				local clone = spawnGun( owner, Vector( 0, 128, 64 ), gun.Id, gun.GunOpts )

				expect( clone.CaliberMM ).to.equal( gun.CaliberMM )
				expect( clone.BoreLength ).to.equal( gun.BoreLength )
				expect( clone.Mass ).to.equal( gun.Mass )

				clone:Remove()
				gun:Remove()
				owner:Remove()
			end
		}
	}
}
