--[[
	Character Stats Service

	Applies the stats from ReplicatedStorage.Shared.CharacterStats to every
	character when it spawns. Movement scripts read the results from the
	Humanoid (JumpPower) and character attributes (everything else).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterStats = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterStats"))

local profileName = CharacterStats.GetProfileName()

-- Extra modifiers applied only when playtesting in Studio, so you can try
-- purchasable abilities before the shop exists. Never used in live servers.
local STUDIO_TEST_MODIFIERS = {
	{ WallRunEnabled = true },
}

-- Ability/passive modifiers for this player. The ability system will
-- return the player's equipped abilities' modifiers here.
local function getModifiers(player)
	if RunService:IsStudio() then
		return STUDIO_TEST_MODIFIERS
	end
	return {}
end

local function applyStats(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	local stats = CharacterStats.Resolve(profileName, getModifiers(player))

	humanoid.UseJumpPower = true
	for key, value in stats do
		if CharacterStats.HumanoidProperties[key] then
			humanoid[key] = value
		else
			character:SetAttribute(key, value)
		end
	end
	character:SetAttribute("StatsProfile", profileName)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		applyStats(player, character)
	end)
	if player.Character then
		applyStats(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
