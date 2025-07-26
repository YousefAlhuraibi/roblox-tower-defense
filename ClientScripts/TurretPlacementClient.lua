-- TurretPlacementClient.lua
-- Handles turret placement, rotation, UI interaction, and turret selection in a Roblox Tower Defense game.
-- Written in Lua using Roblox Studio APIs (UserInputService, Raycasting, GUI, etc.)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

-- RemoteFunctions & Events
local placeTurretFunction    = ReplicatedStorage.RemoteFunctions:WaitForChild("PlaceTurretFunction")
local requestUpgradeFunction = ReplicatedStorage.RemoteFunctions:WaitForChild("RequestTowerUpgrade")
local changeModeFunction     = ReplicatedStorage.RemoteFunctions:WaitForChild("ChangeTowerMode")
local sellTowerFunction      = ReplicatedStorage.RemoteFunctions:WaitForChild("SellTowerFunction")

local spawnUpgradeEvent   = ReplicatedStorage.RemoteEvents:WaitForChild("SpawnUpgradedTower")
local turretUpgradedEvent = ReplicatedStorage.RemoteEvents:WaitForChild("TurretUpgraded")
local animateEvent        = ReplicatedStorage.RemoteEvents:WaitForChild("AnimateTower")

-- Other services / vars
local turretFolder     = ReplicatedStorage:WaitForChild("Turrets")
local player           = Players.LocalPlayer
local mouse            = player:GetMouse()
local gui              = player:WaitForChild("PlayerGui"):WaitForChild("GameGui")
local selectionUI      = gui:WaitForChild("Selection")

local previewTurret     = nil
local currentRotation   = 0
local selectedTurret    = nil
local activeRangeCircle = nil

local SELL_RATIO = 0.5

-- Helper: check if a part is inside the "Muzzle flash" model
local function isDescendantOfMuzzleFlash(obj)
	local parent = obj
	while parent do
		if parent:IsA("Model") and parent.Name == "Muzzle flash" then
			return true
		end
		parent = parent.Parent
	end
	return false
end

--------------------------------------------------------------------------------
local function CreateRangeCircle(tower)
	if activeRangeCircle then
		activeRangeCircle:Destroy()
	end

	local range = tower.Config.Range.Value
	local base  = tower:FindFirstChild("Base") or tower.PrimaryPart
	local height = base and base.Size.Y / 2 or 3
	local offset = CFrame.new(0, -height, 0)

	local p = Instance.new("Part")
	p.Name         = "Range"
	p.Shape        = Enum.PartType.Cylinder
	p.Material     = Enum.Material.Neon
	p.Transparency = 0.9
	p.Size         = Vector3.new(2, range * 2, range * 2)
	p.TopSurface   = Enum.SurfaceType.Smooth
	p.BottomSurface= Enum.SurfaceType.Smooth
	p.CFrame       = tower.PrimaryPart.CFrame * offset * CFrame.Angles(0,0,math.rad(90))
	p.CanCollide   = false
	p.Anchored     = true
	p.Parent       = workspace.Camera

	activeRangeCircle = p
end

--------------------------------------------------------------------------------
local function getEquippedTurretName()
	local char = player.Character
	if not char then return nil end
	for _, item in ipairs(char:GetChildren()) do
		if item:IsA("Tool") then
			return item.Name
		end
	end
	return nil
end

local function getPlayerPlot()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:GetAttribute("Owner") == player.UserId then
			return plot
		end
	end
	return nil
end

local function isPlacementValid(position)
	if not previewTurret or not previewTurret.PrimaryPart then
		return false
	end

	local plot = getPlayerPlot()
	if not plot then return false end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	rayParams.FilterDescendantsInstances = { previewTurret, workspace.Camera }

	local ray = workspace:Raycast(position + Vector3.new(0,5,0), Vector3.new(0,-10,0), rayParams)
	if not ray or ray.Instance ~= plot:FindFirstChild("PlotFloor") then
		return false
	end

	local pathsFolder = plot:FindFirstChild("Paths")
	if pathsFolder then
		local region = Region3.new(position - Vector3.new(2,3,2), position + Vector3.new(2,3,2))
		local overlaps = workspace:FindPartsInRegion3WithIgnoreList(region, {previewTurret,workspace.Camera}, 50)
		for _, part in ipairs(overlaps) do
			if part:IsDescendantOf(pathsFolder) then
				return false
			end
		end
	end

	do
		local region = Region3.new(position - Vector3.new(2,3,2), position + Vector3.new(2,3,2))
		local overlaps = workspace:FindPartsInRegion3WithIgnoreList(region, {previewTurret,workspace.Camera}, 50)
		for _, part in ipairs(overlaps) do
			local anc = part:FindFirstAncestorOfClass("Model")
			if anc and anc ~= previewTurret and anc.Name:match("Turret") then
				return false
			end
		end
	end

	return true
end

--------------------------------------------------------------------------------
local function updateSelectionUI(turret)
	selectedTurret = turret
	local config = turret:FindFirstChild("Config")
	if config then
		selectionUI.Visible = true
		selectionUI.Stats.Damage.Value.Text   = config.Damage.Value
		selectionUI.Stats.Range.Value.Text    = config.Range.Value
		selectionUI.Stats.Cooldown.Value.Text = config.Cooldown.Value

		local nameVal = config:FindFirstChild("Name")
		selectionUI.Title.TowerName.Text = (nameVal and nameVal.Value) or "Unnamed"

		if config:FindFirstChild("Image") then
			selectionUI.Title.ImageLabel.Image = config.Image.Texture
		end

		local modeVal = config:FindFirstChild("TargetingMode")
		if modeVal then
			selectionUI.Action.Targeting.Title.Text = modeVal.Value
		end

		local upVal = config:FindFirstChild("Upgrade")
		if upVal and upVal.Value then
			local nxtCfg   = upVal.Value:FindFirstChild("Config")
			local priceVal = nxtCfg and nxtCfg:FindFirstChild("Price")
			local cost     = (priceVal and priceVal.Value) or 0
			selectionUI.Action.Upgrade.Title.Text = "Upgrade ("..tostring(cost)..")"
		else
			selectionUI.Action.Upgrade.Title.Text = "Upgrade (-)"
		end

		local investedVal = config:FindFirstChild("TotalInvested")
		local invested    = (investedVal and investedVal.Value)
			or (config:FindFirstChild("Price") and config.Price.Value)
			or 0

		local refundAmt   = math.floor(invested * SELL_RATIO)
		selectionUI.Action.Sell.Title.Text = "Sell ("..tostring(refundAmt)..")"
	end

	CreateRangeCircle(turret)
end

--------------------------------------------------------------------------------
local function updatePreview()
	local turretName = getEquippedTurretName()
	if not turretName then
		if previewTurret then
			previewTurret:Destroy()
			previewTurret = nil
		end
		return
	end

	local template = turretFolder:FindFirstChild(turretName)
	if not template then return end

	if not previewTurret or previewTurret.Name ~= turretName.."_Preview" then
		if previewTurret then previewTurret:Destroy() end

		previewTurret = template:Clone()
		previewTurret.Name = turretName.."_Preview"

		for _, obj in ipairs(previewTurret:GetDescendants()) do
			if obj:IsA("Humanoid") or obj:IsA("Motor6D") or obj:IsA("Animator")
				or obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("Constraint") then
				obj:Destroy()
			elseif obj:IsA("BasePart") then
				obj.Anchored = true
				obj.CanCollide = false

				-- Hide Muzzle flash parts and HumanoidRootPart
				if obj.Name == "HumanoidRootPart"
					or obj.Name == "Muzzle flash"
					or isDescendantOfMuzzleFlash(obj) then
					obj.Transparency = 1
				else
					obj.Transparency = 0.5
				end
			elseif obj:IsA("ParticleEmitter") or obj:IsA("PointLight") then
				obj.Enabled = false
			end
		end


		previewTurret:SetPrimaryPartCFrame(CFrame.new(0,-1000,0))
		previewTurret.Parent = workspace

		do
			local range = previewTurret.Config.Range.Value
			local h     = previewTurret.PrimaryPart.Size.Y
			local offset= CFrame.new(0,-h,0)
			local p     = Instance.new("Part")
			p.Name     = "Range"
			p.Shape    = Enum.PartType.Cylinder
			p.Material = Enum.Material.Neon
			p.Transparency = 0.9
			p.Size     = Vector3.new(2, range*2, range*2)
			p.TopSurface   = Enum.SurfaceType.Smooth
			p.BottomSurface= Enum.SurfaceType.Smooth
			p.Anchored     = false
			p.CanCollide   = false
			p.CFrame       = previewTurret.PrimaryPart.CFrame * offset * CFrame.Angles(0,0,math.rad(90))
			local weld     = Instance.new("WeldConstraint", p)
			weld.Part0     = p
			weld.Part1     = previewTurret.PrimaryPart
			p.Parent       = previewTurret
		end
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	rayParams.FilterDescendantsInstances = {previewTurret, workspace.Camera}

	local ray = workspace:Raycast(mouse.UnitRay.Origin, mouse.UnitRay.Direction*500, rayParams)
	if ray then
		local yOff = previewTurret.PrimaryPart.Size.Y/2
		local pos  = ray.Position + Vector3.new(0,yOff,0)
		previewTurret:SetPrimaryPartCFrame(CFrame.new(pos) * CFrame.Angles(0,math.rad(currentRotation),0))

		local valid = isPlacementValid(pos)
		local color = valid and Color3.new(0,1,0) or Color3.new(1,0,0)
		for _, part in ipairs(previewTurret:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Color = color
			end
		end
	end
end

--------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local ray = workspace:Raycast(mouse.UnitRay.Origin, mouse.UnitRay.Direction*100)
		if ray then
			local mdl = ray.Instance:FindFirstAncestorOfClass("Model")
			if mdl and mdl.Parent == workspace.Turrets then
				updateSelectionUI(mdl)
				return
			end
		end

		selectionUI.Visible = false
		selectedTurret = nil
		if activeRangeCircle then
			activeRangeCircle:Destroy()
			activeRangeCircle = nil
		end

		if previewTurret then
			local pos = previewTurret.PrimaryPart.Position
			if isPlacementValid(pos) then
				local name = getEquippedTurretName()
				local ok   = placeTurretFunction:InvokeServer(pos, name, currentRotation)
				if ok then
					previewTurret:Destroy()
					previewTurret = nil
					currentRotation = 0
				end
			end
		end
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 and previewTurret then
		previewTurret:Destroy()
		previewTurret = nil
	end

	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.R then
		currentRotation = (currentRotation + 45) % 360
	end
end)

--------------------------------------------------------------------------------
selectionUI.Action.Upgrade.Activated:Connect(function()
	if not selectedTurret then return end
	local cfg = selectedTurret:FindFirstChild("Config")
	local up  = cfg and cfg:FindFirstChild("Upgrade")
	if up and up.Value then
		local ok = requestUpgradeFunction:InvokeServer(selectedTurret)
		if ok then
			spawnUpgradeEvent:FireServer(selectedTurret)
		end
	end
end)

turretUpgradedEvent.OnClientEvent:Connect(function(newTurret)
	if newTurret then
		updateSelectionUI(newTurret)
	end
end)

selectionUI.Action.Sell.Activated:Connect(function()
	if selectedTurret then
		local ok = sellTowerFunction:InvokeServer(selectedTurret)
		if ok then
			selectedTurret = nil
			selectionUI.Visible = false
			if activeRangeCircle then
				activeRangeCircle:Destroy()
				activeRangeCircle = nil
			end
		end
	end
end)

selectionUI.Action.Targeting.Activated:Connect(function()
	if not selectedTurret then return end
	local success, newMode = pcall(function()
		return changeModeFunction:InvokeServer(selectedTurret)
	end)
	if success and newMode then
		selectionUI.Action.Targeting.Title.Text = newMode
	else
		warn("ChangeTowerMode failed:", newMode)
	end
end)

--------------------------------------------------------------------------------
RunService.RenderStepped:Connect(updatePreview)
