--[[
TurretUpgradeHandler.server.lua
Handles turret upgrade validation and replacement on the server.

Features:
- Validates upgrade request via RemoteFunction with coin check.
- Replaces turret with next-level model while preserving:
  - Position
  - Targeting mode
  - Creator (for earnings)
  - TotalInvested cost
- Begins new attack coroutine after upgrade.
- Sends turret upgrade event back to the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local RemoteEvents    = ReplicatedStorage:WaitForChild("RemoteEvents")

local requestUpgradeFunction = RemoteFunctions:WaitForChild("RequestTowerUpgrade")
local spawnUpgradeEvent      = RemoteEvents:WaitForChild("SpawnUpgradedTower")

-- ensure TurretUpgraded RemoteEvent exists
local turretUpgradedEvent = RemoteEvents:FindFirstChild("TurretUpgraded")
if not turretUpgradedEvent then
	turretUpgradedEvent = Instance.new("RemoteEvent")
	turretUpgradedEvent.Name   = "TurretUpgraded"
	turretUpgradedEvent.Parent = RemoteEvents
end

local animateEvent = RemoteEvents:WaitForChild("AnimateTower")

--------------------------------------------------------------------------------
-- find player's plot (for waypoint targeting)
local function getPlayerPlot(player)
	for _, plot in ipairs(Workspace:WaitForChild("Plots"):GetChildren()) do
		if plot:GetAttribute("Owner") == player.UserId then
			return plot
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- tutorial‐style targeting function (unchanged)
local function findTarget(turret, range, mode, player)
	local plot = getPlayerPlot(player)
	if not plot then return nil end

	local wps = plot:FindFirstChild("Waypoints")
	local waypoints = wps and wps:GetChildren() or {}
	table.sort(waypoints, function(a,b)
		return tonumber(a.Name) < tonumber(b.Name)
	end)

	local bestTarget, bestWaypoint, bestDistance, bestHealth

	for _, mob in ipairs(Workspace:WaitForChild("Mobs"):GetChildren()) do
		local hrp      = mob:FindFirstChild("HumanoidRootPart")
		local humanoid = mob:FindFirstChild("Humanoid")
		if not (hrp and humanoid) then continue end

		local dToMob = (hrp.Position - turret.PrimaryPart.Position).Magnitude
		if dToMob > range then continue end

		local idx    = (mob:FindFirstChild("MovingTo") and mob.MovingTo.Value) or 1
		local wp     = waypoints[idx]
		local dToWP  = wp and (hrp.Position - wp.Position).Magnitude or math.huge

		if mode == "Near" or mode == "Closest" then
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
-- shared turret attack loop (unchanged)
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
			motor.C0 = originalC0 * (cf - cf.Position)

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
-- helper: get next-upgrade cost
local function getUpgradeCost(turretModel)
	local cfg      = turretModel:FindFirstChild("Config")
	local upgValue = cfg and cfg:FindFirstChild("Upgrade")
	if not (upgValue and upgValue.Value) then
		return nil
	end
	local nextTpl  = upgValue.Value
	local nextCfg  = nextTpl:FindFirstChild("Config")
	local priceVal = nextCfg and nextCfg:FindFirstChild("Price")
	if not (priceVal and priceVal:IsA("NumberValue")) then
		return nil
	end
	return priceVal.Value
end

--------------------------------------------------------------------------------
-- 1) Validate & charge upgrade request
requestUpgradeFunction.OnServerInvoke = function(player, turretModel)
	if not (turretModel and turretModel:IsDescendantOf(Workspace.Turrets)) then
		return false
	end

	-- cost of the next tier
	local cost = getUpgradeCost(turretModel)
	if not cost then
		return false
	end

	-- check player's coins
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	if not (coins and coins:IsA("IntValue")) then
		return false
	end

	if coins.Value < cost then
		return false
	end

	-- deduct now
	coins.Value = coins.Value - cost
	return true
end

--------------------------------------------------------------------------------
-- 2) Perform the upgrade swap
spawnUpgradeEvent.OnServerEvent:Connect(function(player, oldTurret)
	if not (oldTurret and oldTurret:IsDescendantOf(Workspace.Turrets)) then
		return
	end

	local config     = oldTurret:FindFirstChild("Config")
	local upgradeObj = config and config:FindFirstChild("Upgrade")
	if not (upgradeObj and upgradeObj.Value) then
		return
	end

	-- clone & position
	local upgraded = upgradeObj.Value:Clone()
	local hrp      = upgraded:FindFirstChild("HumanoidRootPart")
	if hrp then upgraded.PrimaryPart = hrp end
	upgraded:SetPrimaryPartCFrame(oldTurret:GetPrimaryPartCFrame())
	upgraded.Name = (upgraded.Config:FindFirstChild("Name") and upgraded.Config.Name.Value)
		or upgraded.Name
	upgraded.Parent = Workspace.Turrets

	-- CollisionGroup + gyro
	for _, part in ipairs(upgraded:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Turret"
		end
	end
	local gyro = Instance.new("BodyGyro", upgraded.PrimaryPart)
	gyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	gyro.D         = 0
	gyro.CFrame    = upgraded.PrimaryPart.CFrame

	-- carry over owner
	local oldCreator = oldTurret:FindFirstChild("creator")
	if oldCreator and oldCreator.Value then
		local newCreator = Instance.new("ObjectValue", upgraded)
		newCreator.Name  = "creator"
		newCreator.Value = oldCreator.Value
	end

	-- carry over targeting mode
	local oldMode = config:FindFirstChild("TargetingMode")
	if oldMode then
		local newMode = Instance.new("StringValue", upgraded.Config)
		newMode.Name  = "TargetingMode"
		newMode.Value = oldMode.Value
	end

	-- recalc TotalInvested
	local oldInvVal   = config:FindFirstChild("TotalInvested")
	local oldInv = oldInvVal and oldInvVal.Value
		or (config:FindFirstChild("Price") and config.Price.Value or 0)
	local nextCost = getUpgradeCost(oldTurret) or 0

	local totalInv    = Instance.new("NumberValue", upgraded.Config)
	totalInv.Name     = "TotalInvested"
	totalInv.Value    = oldInv + nextCost

	-- remove old
	oldTurret:Destroy()

	-- begin attack
	coroutine.wrap(turretAttack)(upgraded, player)

	-- notify client
	turretUpgradedEvent:FireClient(player, upgraded)
end)
