-- TurretAnim.client.lua
-- Handles playing turret attack animations, spawning muzzle flashes, and animating projectiles in a Roblox Tower Defense game.
-- Listens to 'AnimateTower' RemoteEvent and supports predictive targeting.


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local events = ReplicatedStorage:WaitForChild("RemoteEvents")
local animateTowerEvent = events:WaitForChild("AnimateTower")
local projectileFolder = ReplicatedStorage:WaitForChild("Projectiles")

-- Tracks currently playing animation tracks
local currentAnimationTracks = {}

--  Activate muzzle particle from one of the Muzzle# parts under MuzzleFlashes
local function activateMuzzleParticles(turret)
	local turretHead = turret:FindFirstChild("TurretHead")
	if not turretHead then return end

	local flashContainer = turretHead:FindFirstChild("MuzzleFlashes")
	if not flashContainer then return end

	local flashes = {}
	for _, child in ipairs(flashContainer:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^Muzzle%d+$") then
			table.insert(flashes, child)
		end
	end

	if #flashes == 0 then return end

	--  Pick one muzzle randomly (can change to round-robin if needed)
	local muzzle = flashes[math.random(1, #flashes)]

	for _, descendant in ipairs(muzzle:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant:Emit(5)
		end
	end
end



--  Fire projectile with muzzle flash effect
local PROJECTILE_SPEED = 100 -- studs per second

local function fireProjectile(turret, target)
	if not (turret and target and target:FindFirstChild("HumanoidRootPart")) then return end

	local cfg = turret:FindFirstChild("Config")
	if not cfg then return end

	local nameVal = cfg:FindFirstChild("ProjectileName")
	if not (nameVal and nameVal.Value ~= "") then return end

	local template = projectileFolder:FindFirstChild(nameVal.Value)
	if not template then return end

	local proj = template:Clone()
	local origin = turret:FindFirstChild("TurretHead") or turret:FindFirstChild("Head")
	if not origin or not origin:IsA("BasePart") then return end

	local startPos = origin.Position
	local targetPart = target.HumanoidRootPart
	local velocity = targetPart.Velocity

	-- Calculate distance and time to reach target
	local distance = (targetPart.Position - startPos).Magnitude
	local travelTime = distance / PROJECTILE_SPEED

	-- Predict future position
	local predictedPos = targetPart.Position + velocity * travelTime

	-- Face projectile toward predicted position
	local launchCFrame = CFrame.lookAt(startPos, predictedPos) * CFrame.Angles(0, math.rad(-90), 0)

	if proj:IsA("Model") then
		if not proj.PrimaryPart then error("Projectile model "..proj.Name.." needs a PrimaryPart set") end
		proj:SetPrimaryPartCFrame(launchCFrame)
	else
		proj.CFrame = launchCFrame
	end

	proj.Parent = workspace

	--  Muzzle flash
	activateMuzzleParticles(turret)

	--  Animate projectile
	local tweenInfo = TweenInfo.new(travelTime, Enum.EasingStyle.Linear)
	local tweenTarget = (proj:IsA("Model") and proj.PrimaryPart or proj)
	local goal = { Position = predictedPos }
	local tw = TweenService:Create(tweenTarget, tweenInfo, goal)
	tw:Play()

	Debris:AddItem(proj, travelTime)
end



--  Stop animation if already playing
local function stopAnimation(object)
	local track = currentAnimationTracks[object]
	if track then
		track:Stop()
		currentAnimationTracks[object] = nil
	end
end

--  Get or create AnimationController/Humanoid
local function getController(object)
	local h = object:FindFirstChildOfClass("Humanoid")
	if h then return h end

	local ctrl = object:FindFirstChildOfClass("AnimationController")
	if not ctrl then
		ctrl = Instance.new("AnimationController")
		ctrl.Name = "AnimationController"
		ctrl.Parent = object
	end
	return ctrl
end

--  Get or create Animator
local function getAnimator(controller)
	local anim = controller:FindFirstChildOfClass("Animator")
	if not anim then
		anim = Instance.new("Animator")
		anim.Parent = controller
	end
	return anim
end

--  Play turret/mob animation
local function setAnimation(object, animName, looped)
	local folder = object:FindFirstChild("Animations")
	if not folder then return end

	local animObj = folder:FindFirstChild(animName)
	if not animObj then return end

	stopAnimation(object)

	task.defer(function()
		local ctrl = getController(object)
		local animator = getAnimator(ctrl)

		for _ = 1, 10 do
			if animator then break end
			task.wait()
			animator = getAnimator(ctrl)
		end

		if not animator then return end

		local success, track = pcall(function()
			return animator:LoadAnimation(animObj)
		end)

		if not success or not track then return end

		track.Looped = looped
		currentAnimationTracks[object] = track
		track:Play()
	end)
end

--  Auto-play walk animation for mobs
workspace.Mobs.ChildAdded:Connect(function(mob)
	setAnimation(mob, "Walk", true)
end)

--  On turret attack
animateTowerEvent.OnClientEvent:Connect(function(turret, animName, target)
	if not (turret and animName) then return end

	setAnimation(turret, animName, animName == "Walk")

	if target and turret:FindFirstChild("Config") and turret.Config:FindFirstChild("ProjectileName") then
		fireProjectile(turret, target)
	end

	local hrp = turret:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:FindFirstChild("Attack") then
		hrp.Attack:Play()
	end
end)
