-- game services for bindables(linking script event) event
local ServerStorage = game:GetService("ServerStorage")
local bindables = ServerStorage:WaitForChild("Bindables") 
--[[
BaseModule.lua
Manages the Base's health system and destruction logic.

Features:
- Tracks base current/max HP
- Updates GUI health bar dynamically
- Fires GameOver event when health reaches 0
- Connects to UpdateBaseHealth BindableEvent
]]

local updateBaseHealthEvent = bindables:WaitForChild("UpdateBaseHealth")
local gameOverEvent = bindables:WaitForChild("GameOver")

local base = {}


function base.Setup(map, health) 
	base.Model = map:WaitForChild("Base")
	base.CurrentHealth = health
	base.MaxHealth = health
	
	base.UpdateHealth()
	
end

function base.UpdateHealth(damage)
	if damage then 
		base.CurrentHealth -= damage
	end
	
	local gui = base.Model.HealthGUI	-- updates the GUI
	local percent = base.CurrentHealth / base.MaxHealth -- gives us percentage variable
	
	gui.CurrentHealth.Size = UDim2.new(percent, 0,0.5,0) -- sets the size of the health bar to the percent of health left and shows the red underneath
	if base.CurrentHealth <= 0 then
		gameOverEvent:Fire()
		gui.Title.Text = "Base: Destroyed" -- change this line for the title of the base when it is destroyed
		return
	end
	gui.Title.Text = "Base: " .. base.CurrentHealth .. "/" .. base.MaxHealth -- Shows health when base teakes damage
end

updateBaseHealthEvent.Event:Connect(base.UpdateHealth)

return base
