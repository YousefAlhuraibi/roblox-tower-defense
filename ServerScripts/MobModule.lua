--[[
MobModule.lua
Handles spawning and path movement logic for enemy mobs in the Roblox Tower Defense game.
Includes waypoint navigation, collision setup, and base damage logic.
]]

-- ServerStorage/MobModule.lua
local ServerStorage    = game:GetService("ServerStorage")
local PhysicsService   = game:GetService("PhysicsService")

local bindables        = ServerStorage:WaitForChild("Bindables")
local updateBaseHealth = bindables:WaitForChild("UpdateBaseHealth")

local mob = {}

function mob.Move(thisMob, map)
	local humanoid  = thisMob:WaitForChild("Humanoid")
	local waypoints = map:WaitForChild("Waypoints"):GetChildren()
	table.sort(waypoints, function(a,b) return tonumber(a.Name) < tonumber(b.Name) end)

	for idx, wp in ipairs(waypoints) do
		if not thisMob.Parent then return end
		thisMob.MovingTo.Value = idx
		humanoid:MoveTo(wp.Position)
		humanoid.MoveToFinished:Wait()
	end

	-- when mob finishes, deal damage and destroy
	updateBaseHealth:Fire(humanoid.Health)
	thisMob:Destroy()
end

function mob.Spawn(name, quantity, map)
	local template = ServerStorage:WaitForChild("Mobs"):FindFirstChild(name)
	if not template then
		warn("Requested mob does not exist:", name)
		return
	end

	-- make sure workspace.Mobs exists
	local mobFolder = workspace:FindFirstChild("Mobs")
	if not mobFolder then
		mobFolder = Instance.new("Folder", workspace)
		mobFolder.Name = "Mobs"
	end

	for i = 1, quantity do
		task.wait(0.5)
		local newMob = template:Clone()
		newMob.Parent = mobFolder

		-- place at start via HumanoidRootPart
		local hrp = newMob:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = map.Start.CFrame
			hrp:SetNetworkOwner(nil)
		else
			warn("Mob missing HumanoidRootPart:", newMob.Name)
		end

		-- add MovingTo counter
		local iv = Instance.new("IntValue", newMob)
		iv.Name  = "MovingTo"
		iv.Value = 1

		-- collision group
		for _, part in ipairs(newMob:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CollisionGroup = "Mob"
			end
		end

		-- cleanup on death
		newMob.Humanoid.Died:Connect(function()
			task.wait(0.3)
			if newMob.Parent then
				newMob:Destroy()
			end
		end)

		-- start moving
		coroutine.wrap(mob.Move)(newMob, map)
	end
end

return mob
