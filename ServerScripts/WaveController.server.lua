--[[
WaveController.server.lua
Controls the spawning and progression of enemy waves in the tower defense game.

Current Behavior:
- Spawns mobs for 5 preset waves, scaling in difficulty.
- Ends the game early if a game-over event is fired.

Planned Upgrades:
- Transition to infinite wave mode with dynamic scaling (health, speed, damage).
- Multi-plot support for multiplayer games.
- Event-driven architecture for better scalability.

WIP (Work in Progress)
]]


local ServerStorage = game:GetService("ServerStorage")

local bindables = ServerStorage:WaitForChild("Bindables") 
local gameOverEvent = bindables:WaitForChild("GameOver")

local base = require(script.Base)
local mob = require(script.Mob)  -- Import the 'mob' module which contains the Spawn and Move functions
local map = workspace.Plots.Plot1  -- Reference the map named 'plot1' from the Workspace (need to update later for all maps and not recursive)

local gameOver = false

base.Setup(map, 500)

gameOverEvent.Event:Connect(function()
	gameOver = true
end)

for wave = 1 , 5 do
	print("WAVE STARTING:",wave)
	if wave < 5 then 
		
		mob.Spawn("Noob", 3 * wave, map) -- Spawn a 3 zombies for each wave. (wave 2 gets 6 and so on)
		mob.Spawn("Zombie", 3 * wave, map)
	elseif wave == 5 then
		mob.Spawn("Zombie", 100, map)  -- at wave 5, 100 zombies spawn
	end
	
	repeat
		task.wait(1) -- checks every second if there are still zombies alive so we dont start next round
	until #workspace.Mobs:GetChildren() == 0 or gameOver -- this is what actually checks if there are zombies still
	
	-- this if statement is the logic we need to use when we want to exist out of infinte waves
	if gameOver then
		print("Game Over!") 
		break
	end
	
	print("WAVE ENDED:", wave)
	task.wait(1)
end
	

