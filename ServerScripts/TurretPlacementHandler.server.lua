--[[
TurretPlacementHandler.server.lua
Main handler for turret placement, attacking logic, targeting modes, upgrades, and rotation handling.

Features:
- Validates turret placement via RemoteFunction.
- Handles turret auto-targeting using different player-selected targeting modes.
- Supports turret upgrades and invested-cost tracking.
- Automatically rotates turrets toward targets with configurable base Y rotation.
- Awards player coins based on mob kills.

Used by: Turret placement tools, upgrade buttons, targeting mode buttons, and server logic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local PhysicsService    = game:GetService("PhysicsService")

local turretFolder      = ReplicatedStorage:WaitForChild("Turrets")
local events            = ReplicatedStorage:WaitForChild("RemoteEvents")
local functions         = ReplicatedStorage:WaitForChild("RemoteFunctions")

-- RemoteFunctions
local placeTurretFunction    = functions:WaitForChild("PlaceTurretFunction")
local requestUpgradeFunction = functions:WaitForChild("RequestTowerUpgrade")
local changeModeFunction     = functions:WaitForChild("ChangeTowerMode")

-- RemoteEvents
local spawnUpgradeEvent      = events:WaitForChild("SpawnUpgradedTower")
local animateEvent           = events:WaitForChild("AnimateTower")
local turretUpgradedEvent    = events:FindFirstChild("TurretUpgraded")
if not turretUpgradedEvent then
	turretUpgradedEvent = Instance.new("RemoteEvent")
	turretUpgradedEvent.Name   = "TurretUpgraded"
	turretUpgradedEvent.Parent = events
end

local placedTowersPerPlayer = {}
local maxTowers            = 10

--------------------------------------------------------------------------------
-- 1) Find the player's plot
local function getPlayerPlot(player)
	for _, plot in ipairs(Workspace:WaitForChild("Plots"):GetChildren()) do
		if plot:GetAttribute("Owner") == player.UserId then
			return plot
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- 2) Target‐selection
local function findTarget(turret, range, mode, player)
	local plot = getPlayerPlot(player)
	local map  = plot or Workspace:WaitForChild("Grassland")
	local bestTarget, bestWaypoint, bestDistance, bestHealth

	for _, mob in ipairs(Workspace:WaitForChild("Mobs"):GetChildren()) do
		local hrp      = mob:FindFirstChild("HumanoidRootPart")
		local humanoid = mob:FindFirstChild("Humanoid")
		if not (hrp and humanoid) then continue end

		local dToMob = (hrp.Position - turret.PrimaryPart.Position).Magnitude
		if dToMob > range then continue end

		local idx = mob:FindFirstChild("MovingTo") and mob.MovingTo.Value or 1
		local wp  = map:FindFirstChild("Waypoints") and map.Waypoints:FindFirstChild(tostring(idx))
		local dToWP = wp and (hrp.Position - wp.Position).Magnitude or math.huge

		if mode == "Closest" or mode == "Near" then
			if not bestDistance or dToMob < bestDistance then
				bestDistance, bestTarget = dToMob, mob
			end

		elseif mode == "First" then
			if not bestWaypoint or idx > bestWaypoint then
				bestWaypoint, bestDistance, bestTarget = idx, dToWP, mob
			elseif idx == bestWaypoint and dToWP < bestDistance then
				bestDistance, bestTarget = dToWP, mob
			end

		elseif mode == "Last" then
			if not bestWaypoint or idx < bestWaypoint then
				bestWaypoint, bestDistance, bestTarget = idx, dToWP, mob
			elseif idx == bestWaypoint and dToWP > bestDistance then
				bestDistance, bestTarget = dToWP, mob
			end

		elseif mode == "Strong" or mode == "Strongest" then
			local h = humanoid.Health
			if not bestHealth or h > bestHealth then
				bestHealth, bestTarget = h, mob
			end

		elseif mode == "Weak" or mode == "Weakest" then
			local h = humanoid.Health
			if not bestHealth or h < bestHealth then
				bestHealth, bestTarget = h, mob
			end
		end
	end

	return bestTarget
end

--------------------------------------------------------------------------------
-- 3) Turret attack loop
local function turretAttack(turret, player)
	local config = turret:FindFirstChild("Config")
	local base   = turret:FindFirstChild("HumanoidRootPart")
	local head   = turret:FindFirstChild("TurretHead")
	if not (config and base and head) then return end

	local motor = base:FindFirstChild("Motor6D")
	if not motor then
		motor = Instance.new("Motor6D")
		motor.Name   = "Motor6D"
		motor.Part0  = base
		motor.Part1  = head
		motor.C0     = base.CFrame:ToObjectSpace(head.CFrame)
		motor.C1     = CFrame.new()
		motor.Parent = base
	end

	local originalC0 = motor.C0
	turret:SetAttribute("IsAttacking", false)

	local baseRotation = 0
	local rotVal = config:FindFirstChild("BaseRotation")
	if rotVal then
		baseRotation = rotVal.Value
	end

	while turret.Parent do
		local modeVal = config:FindFirstChild("TargetingMode")
		local mode    = (modeVal and modeVal.Value) or "First"
		local target  = findTarget(turret, config.Range.Value, mode, player)
		local isAtk   = turret:GetAttribute("IsAttacking")

		if target and target:FindFirstChild("HumanoidRootPart") then
			if not isAtk then turret:SetAttribute("IsAttacking", true) end
			animateEvent:FireAllClients(turret, "Attack", target)

			local bp, tp = base.Position, target.HumanoidRootPart.Position
			local cf = CFrame.lookAt(bp, Vector3.new(tp.X, bp.Y, tp.Z))
			local rotAdjust = CFrame.Angles(0, -math.rad(baseRotation), 0)
			motor.C0 = originalC0 * (rotAdjust * (cf - cf.Position))

			local hum = target:FindFirstChild("Humanoid")
			if hum then
				hum:TakeDamage(config.Damage.Value)
				if hum.Health <= 0 then
					local stats = player:FindFirstChild("leaderstats")
					if stats and stats:FindFirstChild("Coins") then
						stats.Coins.Value += hum.MaxHealth
					end
				end
			end
		else
			if isAtk then turret:SetAttribute("IsAttacking", false) end
		end

		task.wait(config.Cooldown.Value)
	end
end

--------------------------------------------------------------------------------
-- 4) Billboard name updater
local function updateBillboardName(turret)
	local nameVal = turret.Config:FindFirstChild("Name")
	if nameVal then
		for _, lbl in ipairs(turret:GetDescendants()) do
			if lbl:IsA("TextLabel") then
				lbl.Text = nameVal.Value
			end
		end
	end
end

--------------------------------------------------------------------------------
-- 5) Cycle targeting mode
changeModeFunction.OnServerInvoke = function(player, turretModel)
	if not (turretModel and turretModel:IsDescendantOf(Workspace.Turrets)) then
		return nil
	end
	local modeVal = turretModel.Config and turretModel.Config:FindFirstChild("TargetingMode")
	if not modeVal then return nil end

	local modes = { "First", "Last", "Closest", "Strongest", "Weakest" }
	local idx   = table.find(modes, modeVal.Value) or 1
	modeVal.Value = modes[(idx % #modes) + 1]
	return modeVal.Value
end

--------------------------------------------------------------------------------
-- 6) Place Turret
placeTurretFunction.OnServerInvoke = function(player, position, turretName, rotation)
	local char = player.Character
	if not char then return false end

	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= turretName then return false end

	local template = turretFolder:FindFirstChild(turretName)
	if not template then return false end

	local plot = getPlayerPlot(player)
	if not plot then return false end

	placedTowersPerPlayer[player.UserId] = (placedTowersPerPlayer[player.UserId] or 0)
	if placedTowersPerPlayer[player.UserId] >= maxTowers then
		return false
	end

	tool:Destroy()

	local turret = template:Clone()
	local hrp    = turret:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	turret.PrimaryPart = hrp

	local rotCF   = CFrame.Angles(0, math.rad(rotation), 0)
	local finalCF = CFrame.new(position) * rotCF
	local origCF  = hrp.CFrame
	local offset  = finalCF * origCF:Inverse()

	for _, part in ipairs(turret:GetDescendants()) do
		if part:IsA("BasePart") and part.Anchored then
			part.CFrame = offset * part.CFrame
		end
	end

	turret.Parent = Workspace:WaitForChild("Turrets")
	hrp.Anchored  = true
	turret.Name   = (template.Config:FindFirstChild("Name") and template.Config.Name.Value)
		or turretName

	for _, part in ipairs(turret:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Turret"
		end
	end

	updateBillboardName(turret)

	local creator = Instance.new("ObjectValue", turret)
	creator.Name  = "creator"
	creator.Value = player

	local config = turret:FindFirstChild("Config")
	if config then
		local modeVal = Instance.new("StringValue", config)
		modeVal.Name  = "TargetingMode"
		modeVal.Value = "First"

		local rotVal = Instance.new("NumberValue", config)
		rotVal.Name  = "BaseRotation"
		rotVal.Value = rotation

		local priceVal = config:FindFirstChild("Price")
		if priceVal and priceVal:IsA("NumberValue") then
			local invested = Instance.new("NumberValue", config)
			invested.Name  = "TotalInvested"
			invested.Value = priceVal.Value
		else
			warn("TurretPlacementHandler – missing Config.Price on", turretName)
		end
	end

	placedTowersPerPlayer[player.UserId] += 1
	coroutine.wrap(turretAttack)(turret, player)
	return true
end

--------------------------------------------------------------------------------
-- 7) Upgrade Handler
spawnUpgradeEvent.OnServerEvent:Connect(function(player, oldTurret)
	if not (oldTurret and oldTurret:IsDescendantOf(Workspace.Turrets)) then return end

	local config    = oldTurret:FindFirstChild("Config")
	local upgradeObj= config and config:FindFirstChild("Upgrade")
	if not (upgradeObj and upgradeObj.Value) then return end

	local upgraded = upgradeObj.Value:Clone()
	local hrp      = upgraded:FindFirstChild("HumanoidRootPart")
	if hrp then upgraded.PrimaryPart = hrp end
	upgraded:SetPrimaryPartCFrame(oldTurret:GetPrimaryPartCFrame())
	upgraded.Name = (upgraded.Config:FindFirstChild("Name") and upgraded.Config.Name.Value)
		or upgraded.Name
	upgraded.Parent = Workspace:WaitForChild("Turrets")

	for _, part in ipairs(upgraded:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Turret"
		end
	end

	local gyro = Instance.new("BodyGyro", upgraded.PrimaryPart)
	gyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	gyro.D         = 0
	gyro.CFrame    = upgraded.PrimaryPart.CFrame

	local oldCreator = oldTurret:FindFirstChild("creator")
	if oldCreator and oldCreator.Value then
		local newCreator = Instance.new("ObjectValue", upgraded)
		newCreator.Name  = "creator"
		newCreator.Value = oldCreator.Value
	end

	local oldMode = config:FindFirstChild("TargetingMode")
	if oldMode then
		local newMode = Instance.new("StringValue", upgraded.Config)
		newMode.Name  = "TargetingMode"
		newMode.Value = oldMode.Value
	end

	local oldInvVal   = config:FindFirstChild("TotalInvested")
	local oldInvested = oldInvVal and oldInvVal.Value or (config:FindFirstChild("Price") and config.Price.Value or 0)

	local newPriceVal = upgraded.Config:FindFirstChild("Price")
	local upgradeCost = newPriceVal and newPriceVal.Value or 0

	local totalInv    = Instance.new("NumberValue", upgraded.Config)
	totalInv.Name     = "TotalInvested"
	totalInv.Value    = oldInvested + upgradeCost

	local oldRot = config:FindFirstChild("BaseRotation")
	if oldRot then
		local newRot = Instance.new("NumberValue", upgraded.Config)
		newRot.Name = "BaseRotation"
		newRot.Value = oldRot.Value
	end

	oldTurret:Destroy()
	coroutine.wrap(turretAttack)(upgraded, player)
	turretUpgradedEvent:FireClient(player, upgraded)
end)
