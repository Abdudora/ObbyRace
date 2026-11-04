--[[
	Double Jump (works on PC, mobile, and console)

	TESTINGG

	SETUP:
	  1. In Roblox Studio, go to StarterPlayer > StarterCharacterScripts
	  2. Insert a LocalScript and name it "DoubleJump"
	  3. Paste this code in

	UserInputService.JumpRequest fires for the spacebar (PC), the on-screen
	jump button (mobile), and the A button (controller), so one handler
	covers every device.

	STATS (set by the server from ReplicatedStorage.CharacterStats):
	  MaxJumps      -> 1 = no air jump, 2 = double jump, 3 = triple jump
	  AirJumpBoost  -> 1 = same height as a normal jump, 1.2 = 20% higher
]]

local UserInputService = game:GetService("UserInputService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")

-- SETTINGS -------------------------------------------------------------
local AIR_JUMP_DELAY = 0.01     -- seconds in the air before an air jump is allowed
-------------------------------------------------------------------------

-- Reads a stat attribute from the server, or the default if it hasn't arrived yet
local function stat(name, default)
	local value = character:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local jumpCount = 0
local canAirJump = false
local airToken = 0 -- stops old delayed timers from re-enabling the jump after landing

local function resetJumps()
	jumpCount = 0
	canAirJump = false
	airToken += 1
end

humanoid.StateChanged:Connect(function(_, newState)
	if newState == Enum.HumanoidStateType.Landed
		or newState == Enum.HumanoidStateType.Running
		or newState == Enum.HumanoidStateType.Climbing
		or newState == Enum.HumanoidStateType.Swimming then
		resetJumps()

	elseif newState == Enum.HumanoidStateType.Jumping then
		-- Counts both the normal ground jump and our air jumps
		jumpCount += 1
		canAirJump = false

	elseif newState == Enum.HumanoidStateType.Freefall then
		-- Walking off a ledge counts as the first jump
		if jumpCount == 0 then
			jumpCount = 1
		end

		airToken += 1
		local myToken = airToken
		task.delay(AIR_JUMP_DELAY, function()
			if myToken == airToken and humanoid:GetState() == Enum.HumanoidStateType.Freefall then
				canAirJump = true
			end
		end)
	end
end)

-- Works with the WallRun script
character:GetAttributeChangedSignal("WallRunning"):Connect(function()
	if character:GetAttribute("WallRunning") then
		-- Wall running refreshes your jumps
		resetJumps()
	elseif humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		-- Left the wall: you get one air jump, like walking off a ledge
		jumpCount = 1
		airToken += 1
		local myToken = airToken
		task.delay(AIR_JUMP_DELAY, function()
			if myToken == airToken and humanoid:GetState() == Enum.HumanoidStateType.Freefall then
				canAirJump = true
			end
		end)
	end
end)

UserInputService.JumpRequest:Connect(function()
	-- Let the WallRun script handle jumps when next to a wall or wall running
	if character:GetAttribute("WallRunning") or character:GetAttribute("NearWall") then return end
	if not canAirJump then return end
	if jumpCount >= stat("MaxJumps", 1) then return end
	if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then return end
	if humanoid.Health <= 0 then return end

	canAirJump = false

	-- Optionally boost the air jump
	local boost = stat("AirJumpBoost", 1)
	if boost ~= 1 then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			local jumpVelocity
			if humanoid.UseJumpPower then
				jumpVelocity = humanoid.JumpPower
			else
				jumpVelocity = math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight)
			end
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X, jumpVelocity * boost, v.Z)
			return
		end
	end

	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end)