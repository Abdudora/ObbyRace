--[[
	Locomotion: speed build-up, crouch and slide (works on PC, mobile, and console)

	SPEED BUILD-UP:
	  You start moving at WalkStartSpeed and accelerate to WalkSpeed (top
	  speed). Stopping on the ground resets you to WalkStartSpeed. If you're
	  going faster than top speed (e.g. jumping out of a slide), you slow
	  back down to it at OverSpeedDecay.

	CROUCH / SLIDE:
	  PC      -> hold Left Control
	  Mobile  -> hold the on-screen "Slide" button (appears automatically)
	  Console -> hold B

	  - Moving at SlideMinSpeed or faster: you slide, starting at SlideSpeed
	    and slowing down by SlideFriction. When the slide runs out you
	    crouch if you're still holding the button.
	  - Slower than that: you crouch and move at CrouchSpeed.
	  - Release to stand up. Jump during a slide to keep its speed.
	  - Holding the button while landing at speed starts a slide.
	  - Crouching/sliding shrinks your hitbox (CROUCH_HEIGHT / SLIDE_HEIGHT),
	    so you fit under low gaps. You stay crouched until there's room to stand.

	STATS (set by the server from ReplicatedStorage.CharacterStats):
	  WalkSpeed, WalkStartSpeed, WalkAcceleration, OverSpeedDecay,
	  CrouchEnabled, CrouchSpeed,
	  SlideEnabled, SlideMinSpeed, SlideSpeed, SlideFriction, SlideCooldown

	This script owns Humanoid.WalkSpeed; other scripts should read it, not set it.
]]

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")

-- SETTINGS -------------------------------------------------------------
local CROUCH_DROP = 0.6        -- how far the body lowers when crouching (studs)
local CROUCH_TILT = -20        -- body lean when crouching (degrees, negative = forward)
local SLIDE_DROP = 1.5         -- how far the body lowers when sliding (studs)
local SLIDE_TILT = 60          -- body lean when sliding (degrees, positive = back)

local CROUCH_HEIGHT = 3.5      -- hitbox height while crouching (studs above the ground; standing is 5)
local SLIDE_HEIGHT = 2.8       -- hitbox height while sliding (studs above the ground)

-- Optional: your own animation IDs, e.g. "rbxassetid://1234567890".
-- Leave empty to just lower the character.
local CROUCH_ANIMATION_ID = ""
local SLIDE_ANIMATION_ID = "rbxassetid://74523646723259"
-------------------------------------------------------------------------

local ACTION_NAME = "Slide"

-- Reads a stat attribute from the server, or the default if it hasn't arrived yet
local function stat(name, default)
	local value = character:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local attachment = Instance.new("Attachment")
attachment.Name = "SlideAttachment"
attachment.Parent = root

-- The pose is shown by offsetting the joint between the HumanoidRootPart
-- and the body (RootJoint on R6, Root on R15). This only moves the visuals;
-- the collision box stays the same size.
local rootJoint = root:FindFirstChild("RootJoint") or character:WaitForChild("LowerTorso"):WaitForChild("Root")
local baseRootC0 = rootJoint.C0

-- Hitbox: while crouching/sliding the normal colliding body parts (Torso and
-- Head on R6) stop colliding and a shorter invisible box takes their place.
-- Heights below are measured from the HumanoidRootPart's centre.
local isR6 = humanoid.RigType == Enum.HumanoidRigType.R6
local rootHeight = (isR6 and 2 or humanoid.HipHeight) + root.Size.Y / 2 -- root centre above the ground

local bodyColliders = {}
local colliderBottom = math.huge
local standingTop = -math.huge
for _, part in character:GetDescendants() do
	if part:IsA("BasePart") and part.CanCollide then
		table.insert(bodyColliders, part)
		local y = root.CFrame:PointToObjectSpace(part.Position).Y
		colliderBottom = math.min(colliderBottom, y - part.Size.Y / 2)
		standingTop = math.max(standingTop, y + part.Size.Y / 2)
	end
end

local hitbox = Instance.new("Part")
hitbox.Name = "CrouchHitbox"
hitbox.Transparency = 1
hitbox.Massless = true
hitbox.CanCollide = false
hitbox.CanTouch = false
hitbox.CanQuery = false
hitbox.Size = Vector3.new(root.Size.X, 1, root.Size.Z)
hitbox.CFrame = root.CFrame
local hitboxWeld = Instance.new("Weld")
hitboxWeld.Part0 = root
hitboxWeld.Part1 = hitbox
hitboxWeld.Parent = hitbox
hitbox.Parent = character

local headroomParams = RaycastParams.new()
headroomParams.FilterType = Enum.RaycastFilterType.Exclude
headroomParams.FilterDescendantsInstances = { character }
headroomParams.RespectCanCollide = true

local animator = humanoid:WaitForChild("Animator")
local function loadAnimation(id)
	if id == "" then return nil end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	return track
end
local crouchTrack = loadAnimation(CROUCH_ANIMATION_ID)
local slideTrack = loadAnimation(SLIDE_ANIMATION_ID)

local currentSpeed = stat("WalkStartSpeed", 16)
local crouchHeld = false
local pose = "Stand"         -- "Stand", "Crouch" or "Slide"
local slideVelocity = nil
local slideDirection = nil
local slideSpeed = 0
local slideStart = 0
local lastSlideEnd = -math.huge

local function isGrounded()
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

local function horizontalVelocity()
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z)
end

local function playTrack(track, shouldPlay)
	if not track then return end
	if shouldPlay and not track.IsPlaying then
		track:Play(0.1)
	elseif not shouldPlay and track.IsPlaying then
		track:Stop(0.1)
	end
end

local function setPose(newPose)
	pose = newPose

	local drop, tilt = 0, 0
	if newPose == "Crouch" then
		drop, tilt = CROUCH_DROP, CROUCH_TILT
	elseif newPose == "Slide" then
		-- The slide animation poses the body itself, so skip the extra lean
		drop, tilt = SLIDE_DROP, if slideTrack then 0 else SLIDE_TILT
	end
	rootJoint.C0 = CFrame.new(0, -drop, 0) * CFrame.Angles(math.rad(tilt), 0, 0) * baseRootC0
	humanoid.CameraOffset = Vector3.new(0, -drop, 0)

	local lowered = newPose ~= "Stand"
	for _, part in bodyColliders do
		part.CanCollide = not lowered
	end
	hitbox.CanCollide = lowered
	if lowered then
		local top = (newPose == "Slide" and SLIDE_HEIGHT or CROUCH_HEIGHT) - rootHeight
		hitbox.Size = Vector3.new(root.Size.X, top - colliderBottom, root.Size.Z)
		hitboxWeld.C0 = CFrame.new(0, (top + colliderBottom) / 2, 0)
	end

	playTrack(crouchTrack, newPose == "Crouch")
	playTrack(slideTrack, newPose == "Slide")

	character:SetAttribute("Crouching", newPose == "Crouch")
	character:SetAttribute("Sliding", newPose == "Slide")
end

-- True if there's nothing above that would block standing up
local function hasHeadroom()
	local start = colliderBottom + 0.3
	local origin = root.CFrame * CFrame.new(0, start, 0)
	local size = Vector3.new(root.Size.X - 0.2, 0.4, root.Size.Z - 0.2)
	return workspace:Blockcast(origin, size, root.CFrame.UpVector * (standingTop - start), headroomParams) == nil
end

-- Stand up if there's room, otherwise stay crouched
local function standUp()
	if hasHeadroom() then
		setPose("Stand")
	elseif pose ~= "Crouch" then
		setPose("Crouch")
	end
end

local function endSlide()
	if pose ~= "Slide" then return end
	lastSlideEnd = os.clock()

	if slideVelocity then
		slideVelocity:Destroy()
		slideVelocity = nil
	end

	-- Carry on at the slide's current speed: above top speed it decays at
	-- OverSpeedDecay, below it you accelerate back up as normal
	currentSpeed = slideSpeed

	if crouchHeld and stat("CrouchEnabled", false) and isGrounded() then
		setPose("Crouch")
	else
		standUp()
	end
end

local function startSlide(velocity)
	slideStart = os.clock()
	slideDirection = velocity.Unit
	slideSpeed = math.max(stat("SlideSpeed", 40), velocity.Magnitude)

	slideVelocity = Instance.new("LinearVelocity")
	slideVelocity.Name = "SlideVelocity"
	slideVelocity.Attachment0 = attachment
	slideVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	slideVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	slideVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	-- Only push horizontally so gravity still works normally
	slideVelocity.MaxAxesForce = Vector3.new(1e6, 0, 1e6)
	slideVelocity.VectorVelocity = slideDirection * slideSpeed
	slideVelocity.Parent = root

	setPose("Slide")
end

-- Slide if moving fast enough, otherwise crouch
local function tryCrouchOrSlide()
	if humanoid.Health <= 0 or humanoid.Sit then return end
	if character:GetAttribute("WallRunning") then return end
	if not isGrounded() then return end

	local velocity = horizontalVelocity()
	local canSlide = stat("SlideEnabled", false)
		and os.clock() - lastSlideEnd >= stat("SlideCooldown", 0.5)
		and humanoid.MoveDirection.Magnitude > 0.05
		and velocity.Magnitude >= stat("SlideMinSpeed", 18)

	if canSlide then
		startSlide(velocity)
	elseif stat("CrouchEnabled", false) then
		setPose("Crouch")
	end
end

local function updateSlide(dt)
	slideSpeed -= stat("SlideFriction", 30) * dt

	local leftGround = os.clock() - slideStart > 0.1 and not isGrounded()
	if slideSpeed <= stat("CrouchSpeed", 8) or leftGround then
		endSlide()
		return
	end

	slideVelocity.VectorVelocity = slideDirection * slideSpeed
end

local function updateWalkSpeed(dt)
	local topSpeed = stat("WalkSpeed", 16)
	if pose == "Crouch" then
		topSpeed = stat("CrouchSpeed", 8)
	end
	local startSpeed = math.min(stat("WalkStartSpeed", topSpeed), topSpeed)

	if humanoid.MoveDirection.Magnitude < 0.05 and isGrounded() then
		currentSpeed = startSpeed
	elseif currentSpeed < topSpeed then
		currentSpeed = math.min(currentSpeed + stat("WalkAcceleration", 1000) * dt, topSpeed)
	elseif currentSpeed > topSpeed then
		currentSpeed = math.max(currentSpeed - stat("OverSpeedDecay", 20) * dt, topSpeed)
	end

	humanoid.WalkSpeed = currentSpeed
end

RunService.Heartbeat:Connect(function(dt)
	if humanoid.Health <= 0 then return end

	if pose == "Slide" then
		updateSlide(dt)
	elseif pose == "Crouch" and (not crouchHeld or not isGrounded()) then
		-- Released (or in the air): stand once there's room overhead. Landing
		-- while still holding crouches/slides again.
		standUp()
	elseif pose == "Stand" and crouchHeld then
		tryCrouchOrSlide()
	end

	if pose ~= "Slide" then
		updateWalkSpeed(dt)
	end
end)

-- Keep the normal body parts from colliding while lowered, in case anything
-- turns their collision back on
RunService.Stepped:Connect(function()
	if pose ~= "Stand" then
		for _, part in bodyColliders do
			part.CanCollide = false
		end
	end
end)

-- Jumping out of a slide keeps its speed
UserInputService.JumpRequest:Connect(function()
	if pose == "Slide" then
		endSlide()
	end
end)

-- Dashing cancels a slide so the two don't fight
root.ChildAdded:Connect(function(child)
	if child.Name == "DashVelocity" then
		endSlide()
	end
end)

local function onCrouchAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		crouchHeld = true
		tryCrouchOrSlide()
	elseif inputState == Enum.UserInputState.End
		or inputState == Enum.UserInputState.Cancel then
		crouchHeld = false
		if pose == "Slide" then
			endSlide()
		elseif pose == "Crouch" then
			standUp()
		end
	end
	return Enum.ContextActionResult.Sink
end

local isBound = false

local function bind()
	if isBound then return end
	isBound = true
	-- "true" creates the on-screen button for mobile players automatically
	ContextActionService:BindAction(ACTION_NAME, onCrouchAction, true,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:SetTitle(ACTION_NAME, "Slide")
end

local function unbind()
	crouchHeld = false
	endSlide()
	if pose ~= "Stand" then
		setPose("Stand")
	end
	if not isBound then return end
	isBound = false
	ContextActionService:UnbindAction(ACTION_NAME)
end

-- Only bind while crouch or slide is enabled, so it doesn't block
-- Left Control / B in places without them
local function refreshBinding()
	if (stat("CrouchEnabled", false) or stat("SlideEnabled", false)) and humanoid.Health > 0 then
		bind()
	else
		unbind()
	end
end
character:GetAttributeChangedSignal("CrouchEnabled"):Connect(refreshBinding)
character:GetAttributeChangedSignal("SlideEnabled"):Connect(refreshBinding)
refreshBinding()

-- Clean up when the character dies/respawns so the button doesn't break
humanoid.Died:Connect(unbind)
script.Destroying:Connect(unbind)
