--[[
TurretSellHandler.server.lua
Handles turret sell requests by validating ownership and refunding a portion of the turret's cost.

Features:
- Validates turret model and ownership
- Calculates refund based on TotalInvested or fallback Price
- Adds refund to player's Coins
- Destroys the sold turret

Refund ratio is controlled by REFUND_RATIO.
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local SellTowerFunction   = ReplicatedStorage
	:WaitForChild("RemoteFunctions")
	:WaitForChild("SellTowerFunction")

local REFUND_RATIO = 0.5  -- 50% refund

SellTowerFunction.OnServerInvoke = function(player, turretModel)
	--------------------------------------------------------------------------------
	-- 1) Basic validity & ownership checks
	if not (turretModel and turretModel:IsDescendantOf(workspace.Turrets)) then
		warn("TurretSellHandler — invalid model")
		return false
	end
	local creator = turretModel:FindFirstChild("creator")
	if not (creator and creator.Value == player) then
		warn("TurretSellHandler — not owner")
		return false
	end

	--------------------------------------------------------------------------------
	-- 2) Grab its Config folder
	local config = turretModel:FindFirstChild("Config")
	if not config then
		warn("TurretSellHandler — missing Config")
		return false
	end

	--------------------------------------------------------------------------------
	-- 3) Compute how much was invested
	local totalInvVal = config:FindFirstChild("TotalInvested")
	local invested    = nil

	if totalInvVal and totalInvVal:IsA("NumberValue") then
		invested = totalInvVal.Value
	else
		-- fallback to the turret's own Price NumberValue
		local priceVal = config:FindFirstChild("Price")
		if priceVal and priceVal:IsA("NumberValue") then
			invested = priceVal.Value
		else
			warn("TurretSellHandler — no TotalInvested or Config.Price on", turretModel.Name)
			return false
		end
	end

	--------------------------------------------------------------------------------
	-- 4) Calculate refund & give coins
	local refundAmount = math.floor(invested * REFUND_RATIO)
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	if coins then
		coins.Value = coins.Value + refundAmount
	end

	--------------------------------------------------------------------------------
	-- 5) Destroy the turret and return success
	turretModel:Destroy()
	return true
end
