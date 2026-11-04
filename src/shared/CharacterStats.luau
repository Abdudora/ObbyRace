--[[
	Character Stats

	One place for every movement stat. The server picks a profile based on
	which place the game is running in, applies any ability modifiers, then
	writes the final values onto the character:
	  - JumpPower is set directly on the Humanoid
	  - everything else becomes an attribute on the character
	    (e.g. character:GetAttribute("MaxJumps"))
	  - WalkSpeed is the top speed; the Locomotion script ramps
	    Humanoid.WalkSpeed up to it as you start moving

	MODIFIERS (for abilities/passives later):
	  A modifier is a table of stat changes, e.g. { MaxJumps = 3 }.
	  - A normal key replaces the stat:        MaxJumps = 3
	  - A key ending in "Mult" multiplies it:  WalkSpeedMult = 1.1
]]

local CharacterStats = {}

-- PROFILES -------------------------------------------------------------
CharacterStats.Profiles = {
	Lobby = {
		WalkSpeed = 16,             -- top speed
		WalkStartSpeed = 10,        -- speed the moment you start moving
		WalkAcceleration = 24,      -- studs/sec gained per second until top speed
		OverSpeedDecay = 20,        -- studs/sec lost per second when above top speed
		JumpPower = 50,

		CrouchEnabled = true,
		CrouchSpeed = 8,

		SlideEnabled = false,
		SlideMinSpeed = 14,         -- must be moving at least this fast to slide
		SlideSpeed = 30,            -- speed at the start of a slide
		SlideFriction = 25,         -- studs/sec lost per second while sliding
		SlideCooldown = 0.5,

		MaxJumps = 1,               -- 1 = normal jump only
		AirJumpBoost = 1,           -- 1 = air jumps as high as a normal jump

		DashEnabled = false,
		DashCharges = 1,
		DashSpeed = 80,
		DashDuration = 0.2,
		DashCooldown = 1,
		AllowAirDash = true,

		WallRunEnabled = false,
		WallRunDuration = 5,       -- wall run speed matches WalkSpeed
	},

	Race = {
		WalkSpeed = 70,             -- top speed
		WalkStartSpeed = 30,        -- speed the moment you start moving
		WalkAcceleration = 40,      -- studs/sec gained per second (30 -> 70 in 1s)
		OverSpeedDecay = 50,        -- studs/sec lost per second when above top speed
		JumpPower = 70,

		CrouchEnabled = true,
		CrouchSpeed = 20,

		SlideEnabled = true,        -- default slide
		SlideMinSpeed = 50,         -- must be moving at least this fast to slide
		SlideSpeed = 120,           -- speed at the start of a slide
		SlideFriction = 90,         -- studs/sec lost per second while sliding
		SlideCooldown = 0.5,

		MaxJumps = 2,               -- default double jump
		AirJumpBoost = 1,           -- 1 = air jumps as high as a normal jump

		DashEnabled = true,         -- default single dash
		DashCharges = 1,
		DashSpeed = 200,
		DashDuration = 0.2,
		DashCooldown = 5,
		AllowAirDash = true,

		WallRunEnabled = false,     -- purchasable ability
		WallRunDuration = 5,       -- wall run speed matches WalkSpeed
	},
}

-- Place IDs that use the Race profile. Every other place uses Lobby.
-- Add your race place's ID here once it exists.
CharacterStats.RacePlaceIds = {
	[74521059370103] = true, -- ObbyRaceMovementTesting
	[78292508794807] = true, -- ObbyRace (LGAMES INC), universe 10774652739
}

-- Stats that live on the Humanoid instead of as attributes
CharacterStats.HumanoidProperties = {
	JumpPower = true,
}
-------------------------------------------------------------------------

function CharacterStats.GetProfileName()
	if CharacterStats.RacePlaceIds[game.PlaceId] then
		return "Race"
	end
	return "Lobby"
end

-- Returns a fresh table of final stats: the profile plus every modifier
function CharacterStats.Resolve(profileName, modifiers)
	local profile = CharacterStats.Profiles[profileName]
	assert(profile, "Unknown stats profile: " .. tostring(profileName))

	local stats = table.clone(profile)

	for _, modifier in modifiers or {} do
		for key, value in modifier do
			local baseKey = string.match(key, "^(.+)Mult$")
			if baseKey and type(stats[baseKey]) == "number" then
				stats[baseKey] *= value
			else
				stats[key] = value
			end
		end
	end

	return stats
end

return CharacterStats
