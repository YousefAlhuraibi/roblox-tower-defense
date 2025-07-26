--[[
TurretShopHandler.server.lua
Handles player turret purchases and tool distribution.

Features:
- Grants starting coins to new players
- Handles purchase requests via CoreEvent
- Validates turret existence and price via ReplicatedStorage.Turrets
- Deducts coins and clones Tool from ServerStorage.TurretFolder to player’s Backpack
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Players           = game:GetService("Players")

-- RemoteEvent for purchases
local CoreEvent = ReplicatedStorage
	:WaitForChild("RemoteEvents")
	:WaitForChild("CoreEvent")

-- Model folder (holds your turret templates with Config.Price)
local ModelFolder = ReplicatedStorage:WaitForChild("Turrets")

-- Tool folder (holds the actual Tool instances you give to players)
local ToolFolder  = ServerStorage:WaitForChild("TurretFolder")

local STARTING_COINS = 100000

-- Give each player coins on join
Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name   = "leaderstats"
	stats.Parent = player

	local coins = Instance.new("IntValue")
	coins.Name   = "Coins"
	coins.Value  = STARTING_COINS
	coins.Parent = stats
end)

-- Handle the Buy event
CoreEvent.OnServerEvent:Connect(function(player, eventType, turretName)
	if eventType ~= "Buy" then
		return
	end

	--------------------------------------------------
	-- 1) Read price from the Model’s Config.Price --
	--------------------------------------------------
	local modelTemplate = ModelFolder:FindFirstChild(turretName)
	if not modelTemplate then
		warn("TurretShopHandler – no model named", turretName)
		return
	end

	local cfg      = modelTemplate:FindFirstChild("Config")
	if not cfg then
		warn("TurretShopHandler – model missing Config folder:", turretName)
		return
	end

	local priceVal = cfg:FindFirstChild("Price")
	if not priceVal or not priceVal:IsA("NumberValue") then
		warn("TurretShopHandler – missing Config.Price on model:", turretName)
		return
	end

	local cost = priceVal.Value

	--------------------------------------------------
	-- 2) Check & deduct player’s coins              --
	--------------------------------------------------
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	if not coins then
		warn("TurretShopHandler – no leaderstats.Coins for", player.Name)
		return
	end

	if coins.Value < cost then
		-- not enough money
		return
	end

	coins.Value = coins.Value - cost

	--------------------------------------------------
	-- 3) Clone the Tool into their Backpack         --
	--------------------------------------------------
	local toolTemplate = ToolFolder:FindFirstChild(turretName)
	if not toolTemplate or not toolTemplate:IsA("Tool") then
		warn("TurretShopHandler – no Tool named", turretName)
		return
	end

	local toolClone = toolTemplate:Clone()
	toolClone.Parent = player:WaitForChild("Backpack")
end)
