--[[
	Wall Run (works on PC, mobile, and console)

	SETUP:
	  1. In Roblox Studio, go to StarterPlayer > StarterCharacterScripts
	  2. Insert a LocalScript and name it "WallRun"
	  3. Paste this code in
	  (Use the updated DoubleJump and Dash scripts too so they don't clash.)

	HOW IT WORKS:
	  - While in the air with a wall on your left or right, press jump
	    (Space / mobile jump button / A on controller) to start a wall run.
	  - You run along the wall for up to WallRunDuration seconds while
	    slowly sliding down (reduced gravity).
	  - It ends early if the wall ends, you touch the ground, or you
	    press jump again (which kicks you off the wall).

	STATS (set by the server from ReplicatedStorage.CharacterStats):
	  WallRunEnabled  -> wall running only works while this is true
	  WallRunDuration
	  (Wall run speed matches the Humanoid's WalkSpeed.)
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")

-- SETTINGS -------------------------------------------------------------
local WALL_GRAVITY = 8           -- gravity while wall running (normal Roblox gravity is 196.2)
local MAX_FALL_SPEED = 6         -- fastest you can slide down the wall (studs/sec)
local START_UPWARD_SPEED = 4     -- small hop up when the wall run starts
local WALL_CHECK_DISTANCE = 3    -- how close a wall must be to your side (studs)
local WALL_RUN_COOLDOWN = 0.4    -- seconds before you can wall run again

local JUMP_OFF_ENABLED = true    -- press jump during a wall run to kick off
local JUMP_OFF_PUSH = 35         -- how hard you're pushed away from the wall
local JUMP_OFF_UP = 50           -- upward speed when kicking off
-------------------------------------------------------------------------

-- Reads a stat attribute from the server, or the default if it hasn't arrived yet
local function stat(name, default)
	local value = character:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { character }
rayParams.RespectCanCollide = true

local attachment = Instance.new("Attachment")
attachment.Name = "WallRunAttachment"
attachment.Parent = root

local isWallRunning = false
local wallNormal = nil      -- points out of the wall, toward the player
local runDirection = nil    -- direction along the wall
local verticalSpeed = 0
local startTime = 0
local runSpeed = 0          -- WalkSpeed / WallRunDuration, read when the run starts
local runDuration = 0
local lastEndTime = -math.huge
local lastJumpRequest = -math.huge
local velocity = nil
local runConnection = nil

local function isAirborne()
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Jumping
end

-- Raycast in a direction and return the hit if it's a usable wall
local function castForWall(direction)
	local result = workspace:Raycast(root.Position, direction * WALL_CHECK_DISTANCE, rayParams)
	if not result then return nil end
	if math.abs(result.Normal.Y) > 0.3 then return nil end -- floors, ceilings, steep slopes
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then return nil end -- other players
	return result
end

local function findSideWall()
	local right = root.CFrame.RightVector
	right = Vector3.new(right.X, 0, right.Z).Unit
	return castForWall(right) or castForWall(-right)
end

local function alongWall(normal, reference)
	local along = normal:Cross(Vector3.yAxis).Unit
	if along:Dot(reference) < 0 then
		along = -along
	end
	return along
end

local function endWallRun(jumpOff)
	if not isWallRunning then return end
	isWallRunning = false
	lastEndTime = os.clock()

	if runConnection then
		runConnection:Disconnect()
		runConnection = nil
	end
	if velocity then
		velocity:Destroy()
		velocity = nil
	end
	humanoid.AutoRotate = true

	if jumpOff then
		root.AssemblyLinearVelocity = wallNormal * JUMP_OFF_PUSH
			+ runDirection * (runSpeed * 0.5)
			+ Vector3.new(0, JUMP_OFF_UP, 0)
	end

	character:SetAttribute("WallRunning", false)
end

local function updateWallRun(dt)
	local elapsed = os.clock() - startTime

	if humanoid.Health <= 0 or elapsed >= runDuration then
		endWallRun(false)
		return
	end
	-- Touched the ground (small grace period right after starting)
	if elapsed > 0.1 and humanoid.FloorMaterial ~= Enum.Material.Air then
		endWallRun(false)
		return
	end

	-- Make sure the wall is still there (also follows curved walls)
	local result = castForWall(-wallNormal)
	if not result then
		endWallRun(false)
		return
	end
	wallNormal = result.Normal
	runDirection = alongWall(wallNormal, runDirection)

	-- Slow gravity: fall speed builds up gently and is capped
	verticalSpeed = math.max(verticalSpeed - WALL_GRAVITY * dt, -MAX_FALL_SPEED)

	velocity.VectorVelocity = runDirection * runSpeed
		+ Vector3.new(0, verticalSpeed, 0)
	- wallNormal * 2 -- slight pull into the wall so you stick to it

	-- Face the direction you're running
	root.CFrame = CFrame.lookAt(root.Position, root.Position + runDirection)
end

local function startWallRun(wallHit)
	isWallRunning = true
	startTime = os.clock()
	wallNormal = wallHit.Normal
	runSpeed = humanoid.WalkSpeed
	runDuration = stat("WallRunDuration", 5)

	-- Run whichever way you're moving (or facing, if no input)
	local reference = humanoid.MoveDirection
	if reference.Magnitude < 0.1 then
		reference = root.CFrame.LookVector
	end
	runDirection = alongWall(wallNormal, reference)
	verticalSpeed = START_UPWARD_SPEED

	humanoid.AutoRotate = false

	velocity = Instance.new("LinearVelocity")
	velocity.Name = "WallRunVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = 1e6
	velocity.VectorVelocity = runDirection * runSpeed + Vector3.new(0, verticalSpeed, 0)
	velocity.Parent = root

	character:SetAttribute("WallRunning", true)
	runConnection = RunService.Heartbeat:Connect(updateWallRun)
end

UserInputService.JumpRequest:Connect(function()
	-- JumpRequest repeats while the button is held, so only react to a fresh press
	local now = os.clock()
	local isFreshPress = now - lastJumpRequest > 0.15
	lastJumpRequest = now
	if not isFreshPress then return end

	if isWallRunning then
		if JUMP_OFF_ENABLED and now - startTime > 0.1 then
			endWallRun(true)
		end
		return
	end

	if humanoid.Health <= 0 then return end
	if not stat("WallRunEnabled", false) then return end
	if now - lastEndTime < WALL_RUN_COOLDOWN then return end
	if not isAirborne() then return end

	local wall = findSideWall()
	if wall then
		startWallRun(wall)
	end
end)

-- Tell the other scripts when a wall run is possible, so the double jump
-- doesn't fire instead of the wall run
character:SetAttribute("WallRunning", false)
character:SetAttribute("NearWall", false)
RunService.Heartbeat:Connect(function()
	local near = not isWallRunning
		and stat("WallRunEnabled", false)
		and isAirborne()
		and os.clock() - lastEndTime >= WALL_RUN_COOLDOWN
		and findSideWall() ~= nil
	if character:GetAttribute("NearWall") ~= near then
		character:SetAttribute("NearWall", near)
	end
end)

humanoid.Died:Connect(function()
	endWallRun(false)
end)