--[[
	Directional Dash (works on PC, mobile, and console)

	SETUP:
	  1. In Roblox Studio, go to StarterPlayer > StarterCharacterScripts
	  2. Insert a LocalScript and name it "Dash"
	  3. Paste this code in

	CONTROLS:
	  PC      -> Q
	  Mobile  -> on-screen "Dash" button (appears automatically)
	  Console -> X button

	DIRECTION:
	  Dashes the way you're moving (W = forward, A/D = side, S = back,
	  diagonals work too). Standing still = dash the way you're facing.
	  Moving joystick on mobile works the same way.

	STATS (set by the server from ReplicatedStorage.CharacterStats):
	  DashEnabled   -> dash is only bound while this is true
	  DashCharges   -> dashes you can chain (2 = double dash); each charge
	                   refills DashCooldown seconds after it's used
	  DashSpeed, DashDuration, DashCooldown, AllowAirDash
]]

local ContextActionService = game:GetService("ContextActionService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")

local ACTION_NAME = "Dash"

-- Reads a stat attribute from the server, or the default if it hasn't arrived yet
local function stat(name, default)
	local value = character:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local attachment = Instance.new("Attachment")
attachment.Name = "DashAttachment"
attachment.Parent = root

local chargesUsed = 0
local isDashing = false

local function getDashDirection()
	-- MoveDirection already accounts for the camera, so W = forward from your view
	local move = humanoid.MoveDirection
	local flat = Vector3.new(move.X, 0, move.Z)
	if flat.Magnitude > 0.05 then
		return flat.Unit
	end

	-- Not moving: dash the way the character is facing
	local look = root.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function dash()
	if isDashing then return end
	if not stat("DashEnabled", false) then return end
	if chargesUsed >= stat("DashCharges", 1) then return end
	if humanoid.Health <= 0 or humanoid.Sit then return end
	if character:GetAttribute("WallRunning") then return end

	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Climbing
		or state == Enum.HumanoidStateType.Swimming then
		return
	end
	if not stat("AllowAirDash", true) and (state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Jumping) then
		return
	end

	isDashing = true
	chargesUsed += 1
	task.delay(stat("DashCooldown", 1), function()
		chargesUsed = math.max(chargesUsed - 1, 0)
	end)

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DashVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	-- Only push horizontally so gravity still works normally
	velocity.MaxAxesForce = Vector3.new(1e6, 0, 1e6)
	velocity.VectorVelocity = getDashDirection() * stat("DashSpeed", 80)
	velocity.Parent = root

	task.delay(stat("DashDuration", 0.2), function()
		velocity:Destroy()
		isDashing = false
	end)
end

local function onDashAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		dash()
	end
	return Enum.ContextActionResult.Sink
end

local isBound = false

local function bind()
	if isBound then return end
	isBound = true
	-- "true" creates the on-screen button for mobile players automatically
	ContextActionService:BindAction(ACTION_NAME, onDashAction, true,
		Enum.KeyCode.Q,
		Enum.KeyCode.ButtonX
	)
	ContextActionService:SetTitle(ACTION_NAME, "Dash")
	-- To move the mobile button, uncomment and adjust:
	-- ContextActionService:SetPosition(ACTION_NAME, UDim2.new(0.2, 0, 0.5, 0))
end

local function unbind()
	if not isBound then return end
	isBound = false
	ContextActionService:UnbindAction(ACTION_NAME)
end

-- Only bind Q / X / the mobile button while dash is enabled, so it doesn't
-- block those inputs in places without dash (e.g. the lobby)
local function refreshBinding()
	if stat("DashEnabled", false) and humanoid.Health > 0 then
		bind()
	else
		unbind()
	end
end
character:GetAttributeChangedSignal("DashEnabled"):Connect(refreshBinding)
refreshBinding()

-- Clean up when the character dies/respawns so the button doesn't break
humanoid.Died:Connect(unbind)
script.Destroying:Connect(unbind)