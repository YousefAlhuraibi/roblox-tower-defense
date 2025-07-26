# 🛡️ Roblox Tower Defense

A fully custom infinite tower defense game created in Roblox Studio using Lua. Features real-time turret placement, upgrade/sell systems, wave-based enemy spawns, and a persistent client-server inventory for managing turret purchases.

## ✨ Features

- 🔫 Real-time turret placement with rotation & preview
- 📦 Hotbar & overflow inventory system (client/server synced)
- 💰 In-game shop using coins (with purchase, stack, and storage logic)
- 📈 Infinite wave scaling (WIP)
- 🧟‍♂️ Mob pathfinding with health & animations
- 🏰 Base health bar and game over condition
- 🛠️ Modular architecture for turrets, mobs, and wave control

## 🧑‍💻 Authors

- **Yousef Alhuraibi** — Developer, system architect, UI/UX logic
- **Brandon Shelhorse** — Co-developer, 3D Models


## 🗂️ Folder Structure

- **ClientScripts/**
  - TurretAnim.client.lua
  - TurretPlacementClient.lua

- **ServerScripts/**
  - MobModule.lua
  - TurretPlacementHandler.server.lua
  - TurretSellHandler.server.lua
  - TurretShopHandler.server.lua
  - TurretUpgradeHandler.server.lua
  - WaveController.server.lua

- **SharedModules/**
  - BaseModule.lua

## 🛠️ Technologies

- Roblox Studio (Luau)
- OOP-style module scripting
- Git version control for collaboration
- Manual file organization outside Roblox for source control

## 📈 Status

> 🔄 In development: core systems complete, infinite wave progression being expanded.

## 📄 License

This project is for educational and portfolio use. Feel free to explore or adapt with credit.
