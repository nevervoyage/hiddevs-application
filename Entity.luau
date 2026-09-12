--Connected Discord-GitHub
-- Get Roblox services.
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Load required modules.
local StateMachine = require(ServerStorage.Modules.StateMachine)
local Ragdoll = require(ServerStorage.Modules.Ragdoll)
local Maid = require(ReplicatedStorage.Modules.Maid)
local Signal = require(ReplicatedStorage.Modules.Signal)
local Replication = require(ReplicatedStorage.Modules.Replication)
local ClanData = require(script.ClanData)
local HistoryData = require(script.HistoryData)
local DataCache = require(ServerStorage.Modules.ProfileStore.DataCache)

-- Store commonly used assets.
local Animations = ReplicatedStorage.Assets.Animations
local Sounds = ReplicatedStorage.Assets.Sounds

-- Define the default entity statistics.
local BASE_HEALTH = 100
local BASE_WALKSPEED = 18
local BASE_JUMPPOWER = 50
local BASE_POSTURE = 100
local BASE_DEFENSE = 0.02
local BASE_DAMAGE = 1
local BASE_STAMINA = 100
local BASE_HEALTH_REGEN = 0.03
local COMBAT_HEALTH_REGEN = 0
local BASE_STAMINA_REGEN = 0.025

-- Define the bonuses gained from passing rings.
local RING_HEALTH = 25
local RING_POSTURE = 10
local RING_DEFENSE = 0.001
local RING_DAMAGE = 0.05
local RING_STAMINA = 10

-- Store possible randomly generated character names.
local randomNames = {
	"Elaraeth",
	"Elaraeth",
	"Sorian",
	"Kaelen",
	"Vorian",
	"Lyria",
	"Theron",
	"Nyxis",
	"Phaedra",
	"Zevran",
	"Isolde"
}

-- Store possible randomly selected face assets.
local randomFaces = {
	21638407,
	7076053,
	7074972,
	9250431,
	15177471,
	14861556,
	7699115,
	7132019
}

-- Store possible randomly generated races.
local randomRace = {
	"Forlorn",
	"Malaphage",
	"Nephilim"
}

-- Store possible clans for each race.
local randomClan = {
	Forlorn = {
		"Gloomwrathi",
		"Mournshadia",
		"Nullmere",
		"Warbardt",
		"Blightoath",
		"Craventh",
		"Dirgekini",
		"Dusktharn",
		"Sorroveilo",
		"Threnody"
	},

	Malaphage = {
		"Vainglory",
		"Obliviscor",
		"Ravore",
		"Heartclaw",
		"Abyssur",
		"Blightvein",
		"Famesor",
		"Cinderhalt",
		"Cryptmaw",
		"Devourante"
	},

	Nephilim = {
		"Exsul",
		"Lucifug",
		"Desperatio",
		"Iratum",
		"Vacillo",
		"Contritum",
		"Desiderium",
		"Divulsum",
		"Initium",
		"Laceratum"
	}
}

-- Disable humanoid states that are not used by the custom character controller.
local function disableHumanoidStates(entity)
	local bloatStates = {
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Seated,
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.Swimming,
		Enum.HumanoidStateType.Flying,
		Enum.HumanoidStateType.StrafingNoPhysics,
		Enum.HumanoidStateType.GettingUp,
	}

	-- Disable every unwanted humanoid state.
	for _, state in bloatStates do
		entity.humanoid:SetStateEnabled(state, false)
	end
end

-- Preload all animations used by the entity.
local function loadAnimations(entity)
	for _, animation in pairs(Animations:GetDescendants()) do
		if animation:IsA("Animation") then
			entity.animator:LoadAnimation(animation)
		end
	end
end

-- Calculate the stat bonuses gained from passed rings.
local function processRing(entity)
	return {
		maxHealth = RING_HEALTH * (entity.ringPassed + 1),
		posture = RING_POSTURE * (entity.ringPassed + 1), 
		defense = RING_DEFENSE * (entity.ringPassed + 1),
		damage = RING_DAMAGE * (entity.ringPassed + 1),
		stamina = RING_STAMINA * (entity.ringPassed + 1),
	}
end

-- Calculate the bonuses and penalties provided by the entity's history.
local function processHistory(entity)
	if HistoryData[entity.history] then
		local history = HistoryData[entity.history]
		
		-- Copy the history's positive effects.
		local historyStats = {}
		for name, buff in pairs(history.buff) do
			historyStats[name] = buff
		end
		
		-- Reduce negative effects based on the number of passed rings.
		for name, debuff in pairs(history.debuff) do
			historyStats[name] = math.max(debuff * -(1 - (entity.ringPassed * 0.15)), debuff * 0.3)
		end
		
		return historyStats
	end
	
	-- Return no bonuses if the history does not exist.
	return {}
end

-- Process all torments currently affecting the entity.
local function processTorments(entity)
	if entity.torments then
		local tormentStats = {}
		
		for _, torment in pairs(entity.torments) do
			-- Run one-time torment logic before applying its stats.
			if not torment.processed then
				torment.once(entity)
				torment.processed = true
			end
			
			-- Add the torment's stat effects.
			table.insert(tormentStats, table.unpack(torment.stats))
		end
		
		return tormentStats
	end

	-- Return no bonuses if the entity has no torments.
	return {}
end

-- Retrieve the stat bonuses provided by the entity's clan.
local function processClan(entity)
	if ClanData[entity.race] then
		local raceClans = ClanData[entity.race]
		if raceClans[entity.clan] then
			return raceClans[entity.clan]
		end
	end
	
	-- Return no bonuses if the clan cannot be found.
	return {}
end

-- Update and apply all temporary statuses on the entity.
local function processStatuses(entity, deltaTime)
	local bufferedMaxHealth = 1
	local bufferedWalkSpeed = 1
	local bufferedJumpPower = 1
	
	for name, status in pairs(entity.statuses) do
		-- Remove statuses that have expired.
		if status.duration <= 0 then
			entity.statuses[name] = nil
			entity.character:SetAttribute(name, nil)
			
			-- Remove the visual effect for Hyper Armor.
			if name == "HyperArmor" and entity.character:FindFirstChild("HyperArmorOutline") then
				entity.character.HyperArmorOutline:Destroy()
			end
			
			-- Disable ragdoll when the status ends.
			if name == "Ragdolled" then
				Ragdoll:Disable(entity.character)
			end
			
			-- Run the status exit callback.
			if status.data.exit then
				status.data.exit(entity, status)
			end
			continue
		end
		
		-- Reduce the remaining duration of the status.
		entity.statuses[name].duration = status.duration - deltaTime
		entity.character:SetAttribute(name, true)
		
		-- Create the Hyper Armor visual effect.
		if name == "HyperArmor" and not entity.character:FindFirstChild("HyperArmorOutline") then
			local outline = Instance.new("Highlight")
			outline.Name = "HyperArmorOutline"
			outline.FillTransparency = 1
			outline.DepthMode = Enum.HighlightDepthMode.Occluded
			outline.OutlineColor = Color3.new(1, 0.50, 0)
			outline.Parent = entity.character
		end
		
		-- Enable ragdoll while the status is active.
		if name == "Ragdolled" then
			Ragdoll:Enable(entity.character)
		end
		
		-- Combine the stat multipliers provided by active statuses.
		bufferedMaxHealth = bufferedMaxHealth * (status.data.health or 1)
		bufferedWalkSpeed = bufferedWalkSpeed * (status.data.walkSpeed or 1)
		bufferedJumpPower = bufferedJumpPower * (status.data.jumpPower or 1)
		
		-- Run the status's active callback.
		if status.callback then
			status.callback(entity, status)
		end
	end
	
	return {
		maxHealth = bufferedMaxHealth,
		walkSpeed = bufferedWalkSpeed,
		jumpPower = bufferedJumpPower
	}
end

-- Update all combat tags and determine whether the entity is in combat.
local function processCombatTags(entity, deltaTime)
	for name, combatTag in pairs(entity.combatTags) do
		-- Reduce the remaining combat tag duration.
		entity.combatTags[name].duration = combatTag.duration - deltaTime
		
		if combatTag.duration <= 0 then
			-- Remove expired combat tags.
			entity.combatTags[name] = nil
			entity.inCombat = false
			entity.character:SetAttribute("Combat", nil)
		else
			-- Mark the entity as being in combat.
			entity.inCombat = true
			entity.character:SetAttribute("Combat", true)
		end
	end
end

-- Update and remove expired ability cooldowns.
local function processCooldowns(entity, deltaTime)
	for cooldown, duration in pairs(entity.cooldowns) do
		-- Reduce the cooldown timer.
		entity.cooldowns[cooldown] = duration - deltaTime

		-- Remove the cooldown once it expires.
		if duration <= 0 then
			entity.cooldowns[cooldown] = nil
		end
	end
end

-- Update the damage combo and determine its current rank.
local function processCombo(entity, deltaTime)
	-- Slowly decay the entity's combo over time.
	entity.damageCombo = math.max(0, entity.damageCombo - (deltaTime * 2.7))

	-- Store the temporary bonuses provided by the combo rank.
	local statsTable = {
		walkSpeed = 0,
		damage = 0,
		staminaRegen = 0,
	}
	
	-- Determine the combo rank and its corresponding bonuses.
	if entity.damageCombo > 0 and entity.damageCombo < 30 then
		entity.damageRank = "D"
		statsTable.walkSpeed = 0.1
	elseif entity.damageCombo >= 30 and entity.damageCombo < 45 then
		entity.damageRank = "C"
		statsTable.walkSpeed = 0.4
	elseif entity.damageCombo >= 45 and entity.damageCombo < 70 then
		entity.damageRank = "B"
		statsTable.walkSpeed = 0.7
		statsTable.staminaRegen = 0.01
	elseif entity.damageCombo >= 70 and entity.damageCombo < 100 then
		entity.damageRank = "A"
		statsTable.damage = 0.01
		statsTable.walkSpeed = 1.1
		statsTable.staminaRegen = 0.01
	elseif entity.damageCombo >= 90 and entity.damageCombo < 150 then
		entity.damageRank = "S"
		statsTable.damage = 0.01
		statsTable.walkSpeed = 1.9
		statsTable.staminaRegen = 0.02
	elseif entity.damageCombo >= 150 then
		entity.damageRank = "N"
		statsTable.damage = 0.02
		statsTable.walkSpeed = 2.3
		statsTable.staminaRegen = 0.03
	else
		entity.damageRank = "F"
	end
	
	return statsTable
end

-- Apply the entity's configured hair color to its hair meshes.
local function colorHair(entity)
	for _, v in pairs(entity.character:GetDescendants()) do
		if v:IsA("SpecialMesh") and v.MeshType ~= Enum.MeshType.Head and v.MeshType ~= Enum.MeshType.Torso and v.Parent.Parent ~= entity.character then
			v.Parent.Color = entity.hairColor
		end
	end
end

-- Recalculate all entity statistics and update its state.
local function processEntity(entity, deltaTime)
	-- Calculate every source of stat modification.
	local statusStats = processStatuses(entity, deltaTime)
	local clanStats = processClan(entity)
	local ringStats = processRing(entity)
	local historyStats = processHistory(entity)
	local tormentStats = processTorments(entity)
	local comboStats = processCombo(entity, deltaTime)
	
	-- Update temporary systems.
	processCombatTags(entity, deltaTime)
	processCooldowns(entity, deltaTime)
	
	-- Calculate the entity's final statistics.
	entity.maxHealth = math.max((BASE_HEALTH + (clanStats.maxHealth or 0) + (historyStats.maxHealth or 0) + (tormentStats.maxHealth or 0) + ringStats.maxHealth) * statusStats.maxHealth, 1)
	entity.walkSpeed = math.max((BASE_WALKSPEED + (comboStats.walkSpeed or 0)) * statusStats.walkSpeed, 0)
	entity.jumpPower = math.max(BASE_JUMPPOWER * statusStats.jumpPower, 0)
	entity.maxPosture = math.max(BASE_POSTURE + (clanStats.posture or 0) + (historyStats.posture or 0) + (tormentStats.maxPosture or 0) + ringStats.posture, 0)
	entity.defense = math.max(BASE_DEFENSE + (historyStats.defense or 0) + (tormentStats.defense or 0) + ringStats.defense, 0)
	entity.damage = math.max(BASE_DAMAGE + (comboStats.damage or 0) + (historyStats.damage or 0) + (tormentStats.damage or 0) + ringStats.damage, 0)
	entity.healthRegen = entity.inCombat and COMBAT_HEALTH_REGEN or BASE_HEALTH_REGEN
	entity.maxStamina = math.max(BASE_STAMINA + (clanStats.stamina or 0) + (historyStats.stamina or 0) + (tormentStats.stamina or 0) + ringStats.stamina, 0)
	
	-- Regenerate stamina while respecting its maximum value.
	entity.stamina = math.clamp(
		math.min(
			entity.stamina + (((entity.maxStamina + (comboStats.staminaRegen or 0)) * entity.staminaRegen) * deltaTime),
			entity.maxStamina
		),
		0,
		entity.maxStamina
	)
	
	-- Replicate important combat values through character attributes.
	entity.character:SetAttribute("Posture", entity.posture)
	entity.character:SetAttribute("MaxPosture", entity.maxPosture)
	entity.character:SetAttribute("Stamina", entity.stamina)
	entity.character:SetAttribute("MaxStamina", entity.maxStamina)
	entity.character:SetAttribute("ComboRank", entity.damageRank)
	
	-- Regenerate entity-specific stamina if it exists.
	if entity.entStamina then
		entity.entStamina = math.min(
			entity.entStamina + ((entity.entMaxStamina * entity.entStaminaRegen) * deltaTime),
			entity.entMaxStamina
		)
	end

	-- Knock the entity when its health reaches the critical threshold.
	if entity.humanoid.Health < entity.maxHealth * 0.01 and entity.stateMachine.currentState ~= "Knocked" then
		entity.stateMachine:SetState("Knocked", entity)
		entity.combatTags = {}
		entity.inCombat = false
	end
	
	-- Apply the calculated humanoid statistics.
	entity.humanoid.MaxHealth = entity.maxHealth 
	entity.humanoid.Health = entity.humanoid.Health > 0 and 
		math.min(entity.humanoid.Health + ((entity.maxHealth * entity.healthRegen) * deltaTime), entity.maxHealth) or
		0
	entity.humanoid.WalkSpeed = entity.walkSpeed
	entity.humanoid.JumpPower = entity.jumpPower
	
	-- Recover from the knocked state after enough health is restored.
	if entity.stateMachine.currentState == "Knocked" and entity.humanoid.Health > entity.maxHealth * 0.25 then
		entity.stateMachine:SetState("Idle", entity)
	end
	
	-- Automatically enter the blocking state when block input was buffered.
	if entity.bufferBlock then
		coroutine.wrap(function()
			if entity.stateMachine.currentState == "Blocking" then return end
			
			repeat
				wait()
			until not entity:CheckStatus("Stun") and entity.stateMachine.currentState == "Idle" and entity.bufferBlock
			
			entity.stateMachine:SetState("Blocking", entity)
		end)()
	end
end

-- Define the Entity class.
local Entity = { maid = Maid.new() }
Entity.__index = Entity

-- Create a new entity from a character model.
function Entity.new(character)
	-- Seed the random number generator.
	math.randomseed(tick())
	
	local self = setmetatable({}, Entity)
	
	-- Retrieve the player associated with the character.
	local player = Players:GetPlayerFromCharacter(character)
	local playerData
	
	if player then
		playerData = DataCache[player].Data
	end
	
	-- Store references to the character's main objects.
	self.character = character
	self.humanoid = character:FindFirstChildOfClass("Humanoid")
	self.root = character:FindFirstChild("HumanoidRootPart")
	
	-- Create an animator for the entity.
	self.animator = Instance.new("Animator")
	self.animator.Parent = self.humanoid
	
	-- Initialize the entity's base statistics.
	self.maxHealth = BASE_HEALTH
	self.walkSpeed = BASE_WALKSPEED
	self.jumpPower = BASE_JUMPPOWER
	self.posture = 0
	self.maxPosture = BASE_POSTURE
	self.defense = BASE_DEFENSE
	self.damage = BASE_DAMAGE
	self.maxstamina = BASE_STAMINA
	self.stamina = BASE_STAMINA
	self.healthRegen = BASE_HEALTH_REGEN
	self.staminaRegen = BASE_STAMINA_REGEN
	self.inCombat = false
	
	-- Initialize combo information.
	self.damageCombo = 0
	self.damageRank = "F"
	
	-- Initialize temporary entity systems.
	self.statuses = {}
	self.combatTags = {}
	self.cooldowns = {}
	
	-- Load persistent player data when available.
	self.torments = playerData and playerData.slots["slot" .. playerData.currentSlot].torments or {}
	
	-- Define the entity's available skills.
	self.skills = {
		StepDance = true,
		Showstopper = true,
		Guillotine = true,
		Ravage = true
	}
	
	-- Define the entity's skill toolbar.
	self.toolbar = {
		"StepDance_Skill",
		"Showstopper_Skill",
		"Guillotine_Skill",
		"Ravage_Skill",
		"None_None",
		"None_None",
		"None_None",
		"None_None",
		"None_None",
		"None_None"
	}
	
	-- Load persistent character data or generate defaults.
	self.characterName = playerData and playerData.slots["slot" .. playerData.currentSlot].name or randomNames[math.random(1, #randomNames)]
	self.weapon = playerData and playerData.slots["slot" .. playerData.currentSlot].weapon or "Fists"
	self.element = playerData and playerData.slots["slot" .. playerData.currentSlot].element or "Light"
	self.race = playerData and playerData.slots["slot" .. playerData.currentSlot].race or randomRace[math.random(1, #randomRace)]
	self.clan = playerData and playerData.slots["slot" .. playerData.currentSlot].clan or randomClan[self.race][math.random(1, #randomClan[self.race])]
	self.history = playerData and playerData.slots["slot" .. playerData.currentSlot].history or "Lust"
	self.ringPassed = playerData and playerData.slots["slot" .. playerData.currentSlot].rings or 0

	-- Get the hair color defined by the entity's clan.
	self.hairColor = ClanData[self.race][self.clan].hairColor
	
	-- Create the entity's state machine.
	self.stateMachine = StateMachine.new()
	
	return self
end

-- Initialize the entity after it has been created.
function Entity:__init()
	-- Replicate state machine changes to the character.
	self.stateMachine.stateChanged:Connect(function(newState)
		self.character:SetAttribute("State", newState)
	end)

	-- Hide the default humanoid health bar and set the display name.
	self.humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	self.humanoid.DisplayName = self.characterName .. " " .. self.clan

	-- Apply a random face to the character.
	self.character:FindFirstChild("face", true).Texture = string.format(
		"rbxassetid://%d",
		randomFaces[math.random(1, #randomFaces)]
	)
	
	-- Configure the character's body parts and appearance.
	for _, v:BasePart in pairs(self.character:GetDescendants()) do
		if v:IsA("BasePart") then
			-- Put all character parts into the character collision group.
			v.CollisionGroup = "Character"
			
			-- Apply the race's default body color.
			if v.Parent == self.character then
				if self.race == "Nephillim" then
					v.Color = Color3.new(0.87, 0.87, 0.87)
				elseif self.race == "Malaphage" then
					v.Color = Color3.new(0.26, 0.26, 0.26)
				elseif self.race == "Forlorn" then
					v.Color = Color3.new(0.87, 0.76, 0.50)
				end
			end
		end
		
		-- Remove unwanted character meshes.
		if v:IsA("CharacterMesh") then
			if v.BodyPart == Enum.BodyPart.Torso then
				if v.MeshId ~= 0 and v.MeshId ~= 48112070 then
					v:Destroy()
				end
			else
				v:Destroy()
			end
		end

		-- Remove textures from custom body meshes.
		if v:IsA("SpecialMesh") and v.MeshType ~= Enum.MeshType.Head and v.MeshType ~= Enum.MeshType.Torso then
			v.TextureId = ""
		end

		-- Remove all accessories except hair.
		if v:IsA("Accessory") then
			if v.AccessoryType ~= Enum.AccessoryType.Hair then
				v:Destroy()
			end
		end
	end
	
	-- Create player-specific soul effects.
	local player = Players:GetPlayerFromCharacter(self.character)
	local playerData
	
	if player then
		playerData = DataCache[player].Data

		-- Create the soul part representing the player's remaining lives.
		local soul = Instance.new("Part")
		soul.Name = "SoulPart"
		soul.CanCollide = false
		soul.CanQuery = false
		soul.CanTouch = false
		soul.Size = Vector3.new(1, 1, 1)
		soul.Material = Enum.Material.Neon 
		soul.Transparency = playerData.slots["slot" .. playerData.currentSlot].lives == 2 and 0 or 0.5
		
		-- Set the soul's color based on the character's race.
		if self.race == "Forlorn" then
			soul.Color = Color3.new(0.32, 0.82, 0.30)
		elseif self.race == "Nephilim" then
			soul.Color = Color3.new(0.53, 0.21, 0.82)
		elseif self.race == "Malaphage" then
			soul.Color = Color3.new(0.82, 0.18, 0.18)
		end
		
		soul.Parent = self.character

		-- Create the attachment that drags the soul behind the character.
		local soulDragAttachment = Instance.new("Attachment")
		soulDragAttachment.CFrame = CFrame.new(-2.5, 2.5, 0)
		soulDragAttachment.Parent = self.root

		-- Create the attachment used by the soul itself.
		local soulAttachment = Instance.new("Attachment")
		soulAttachment.CFrame = CFrame.new(0, 0, 0)
		soulAttachment.Parent = soul

		-- Connect the soul to the character using physics alignment.
		local soulAlign = Instance.new("AlignPosition")
		soulAlign.Attachment0 = soulAttachment
		soulAlign.Attachment1 = soulDragAttachment
		soulAlign.ApplyAtCenterOfMass = true
		soulAlign.Responsiveness = 5
		soulAlign.Parent = soul
	end

	-- Initialize the entity's gameplay systems.
	self.stateMachine:SetState("Idle", self)
	disableHumanoidStates(self)
	loadAnimations(self)
	Ragdoll:Setup(self.character)
	processEntity(self, 0)
	colorHair(self)

	-- Apply the entity's initial statistics.
	self.humanoid.Health = self.maxHealth
	self.humanoid.WalkSpeed = self.walkSpeed
	self.humanoid.JumpPower = self.jumpPower
	self.stamina = self.maxstamina
	
	-- Mark the character as fully initialized.
	self.character:SetAttribute("Initialized", true)
	
	-- Handle player death and remaining lives.
	self.humanoid.Died:Once(function()
		if player then
			playerData.slots["slot" .. playerData.currentSlot].lives -= 1
			
			-- Remove character customization and kick the player when all lives are lost.
			if playerData.slots["slot" .. playerData.currentSlot].lives <= 0 then
				playerData.slots["slot" .. playerData.currentSlot].customized = false
				player:Kick("You lost all lives")
			end
		end
	end)

	-- Update the entity every frame.
	RunService.Heartbeat:Connect(function(deltaTime)
		coroutine.wrap(function()
			processEntity(self, deltaTime)
		end)()
	end)
end

-- Deal damage to the entity and handle all combat interactions.
function Entity:TakeDamage(amount, blockbreak, statuses, attacker)
	-- Ignore damage while invulnerable.
	if self:CheckStatus("IFrames") then return end
	
	-- Apply the entity's defense to the incoming damage.
	local damage = amount * (1 - self.defense)
	
	-- Process the damage after the latency compensation delay.
	local function takeDmg()
		-- Evade the attack if the entity has an Evasive status.
		if self:CheckStatus("Evasive") then 
			self:SetCooldown("Dash")
			self:CancelAnimations({LDash = true, RDash = true})
			Replication:Replicate("Evasive", self.root.Position)
			self.posture = math.max(self.posture - (damage * 1.25), 0)
			self.stamina = math.clamp(self.stamina + (damage * 1.1) + 6, 0, self.maxStamina)
			self:RemoveStatus("Stun")
			self:ApplyStatus("HyperArmor", 0.3)
			self:ApplyStatus("Evasive", 0.1)
			self:ApplyStatus("Swiftness", 0.8, {
				walkSpeed = 1.1
			})
			
			-- Play the dodge animation.
			self.animator:LoadAnimation(Animations.Combat.Dodge):Play()
			return
		end
		
		-- Handle attacks against a blocking entity.
		if self.stateMachine.currentState == "Blocking" then
			self.posture = math.min(self.posture + damage * 1.25, self.maxPosture)

			-- Break the block when posture reaches its limit.
			if self.posture == self.maxPosture or blockbreak then
				local idleData = self.idleData or {}
				self.posture = 0
				self.stateMachine:SetState("TrueStun", self)
				
				-- Return to idle after the stun ends.
				task.delay(2.5, function()
					self.stateMachine:SetState("Idle", self, idleData)
				end)
				return
			else
				return
			end
		end

		-- Enter the knocked state when health reaches the critical threshold.
		if self.humanoid.Health - damage < self.maxHealth * 0.01 and self.stateMachine.currentState ~= "Knocked" then
			self.humanoid.Health = self.maxHealth * 0.01
			self.stateMachine:SetState("Knocked", self)
			return
		end
		
		-- Reduce damage while the entity is already knocked.
		if self.stateMachine.currentState == "Knocked" then
			if not statuses["AutoGrip"] then
				damage = math.max(0, math.min(damage / 4, self.humanoid.Health - (self.maxHealth * 0.01)))
			else
				-- Instantly finish the knocked entity when AutoGrip is used.
				damage = self.humanoid.Health + 1
				self:RemoveStatus("Ragdolled")
				
				-- Restore a life to the attacker.
				if attacker then
					local attackerPlayer = Players:GetPlayerFromCharacter(attacker.character)
					if attackerPlayer then
						local attackerPlayerData = DataCache[attackerPlayer].Data
						attackerPlayerData.slots["slot" .. attackerPlayerData.currentSlot].lives = math.clamp(
							attackerPlayerData.slots["slot" .. attackerPlayerData.currentSlot].lives + 1,
							0,
							2
						)
						
						-- Update the attacker's soul visual.
						local soul = attacker.character:FindFirstChild("SoulPart")
						soul.Transparency = attackerPlayerData.slots["slot" .. attackerPlayerData.currentSlot].lives == 2 and 0 or 0.5
					end
				end
				
				-- Remove attachments created by the knocked state.
				for _, descendant in pairs(self.character:GetDescendants()) do
					if descendant:IsA("Attachment") then
						descendant:Destroy()
					end
				end
			end
		end
		
		-- Apply the final damage and posture reduction.
		self.humanoid.Health = self.humanoid.Health - damage
		self.posture = math.max(self.posture - (damage * 0.3), 0)

		-- Reward the attacker and apply combat tagging.
		if attacker then
			self:ApplyCombat(attacker)
			attacker.damageCombo = attacker.damageCombo + damage
			attacker.stamina = attacker.stamina + (damage * 1.4)
		end
		
		-- Play the hit sound.
		local sound = Sounds.Hit:Clone()
		sound.Parent = self.character:FindFirstChild("Torso")
		sound:Play()

		-- Apply hitstun and additional statuses unless Hyper Armor is active.
		if statuses and not self:CheckStatus("HyperArmor") then
			for _, animation in self.animator:GetPlayingAnimationTracks() do
				animation:Stop()
			end

			-- Play the hit reaction animation.
			self.animator:LoadAnimation(ReplicatedStorage.Assets.Animations.Hit):Play()

			-- Apply all statuses attached to the attack.
			for name, status in pairs(statuses) do
				if type(status) ~= "table" then continue end
				self:ApplyStatus(name, status.duration, status.data, status.callback)
			end
		end
	end
	
	-- Delay damage based on the target player's network latency.
	local player = Players:GetPlayerFromCharacter(self.character)
	local compesantion = player and ((player:GetNetworkPing() * 2000 > 88 and player:GetNetworkPing() * 2000 < 524) and player:GetNetworkPing() * 2) or 0
	
	task.delay(compesantion, takeDmg)
	return true
end

-- Apply a knockback force to the entity.
function Entity:Knockback(initiateValues, destroyTime, tweenValues)
	-- Ignore knockback while Hyper Armor is active.
	if self:CheckStatus("HyperArmor") then return end
	
	-- Create the initial knockback force.
	local knockback = Instance.new("BodyVelocity")
	knockback.MaxForce = initiateValues.maxForce
	knockback.Velocity = initiateValues.direction * (
		initiateValues.power +
		(initiateValues.ignore and 0 or math.clamp(self.root.AssemblyLinearVelocity.Magnitude, 0, 47))
	)
	knockback.Parent = self.root
	
	-- Smoothly transition the knockback when tween values are provided.
	if tweenValues then
		TweenService:Create(
			knockback,
			TweenInfo.new(tweenValues.duration, Enum.EasingStyle.Linear)
			{
				MaxForce = tweenValues.maxForce or initiateValues.maxForce, 
				Velocity = (tweenValues.direction or Vector3.zero) * (tweenValues.power or 1)
			}
		):Play()
	end
	
	-- Remove the knockback force after its lifetime expires.
	task.delay(destroyTime, function()
		knockback:Destroy()
	end)
end

-- Add or replace a status effect on the entity.
function Entity:ApplyStatus(name, duration, data, callback)
	self.statuses[name] = {
		duration = duration or math.huge,
		data = data or {},
		callback = callback or nil
	}
end

-- Mark a status for removal on the next status update.
function Entity:RemoveStatus(name)
	if self.statuses[name] then
		self.statuses[name].duration = 0
	end
end

-- Check whether the entity currently has a status.
function Entity:CheckStatus(name)
	return self.statuses[name]
end

-- Apply a combat tag linking the entity to its attacker.
function Entity:ApplyCombat(entity)
	self.combatTags[entity.character.Name] = {
		attacker = entity.character.Name, 
		duration = 35
	}
end

-- Start a cooldown for the specified ability.
function Entity:SetCooldown(name, duration)
	self.cooldowns[name] = duration
end

-- Check whether an ability currently has a cooldown.
function Entity:CheckCooldown(name)
	return self.cooldowns[name]
end

-- Stop animations currently playing on the entity.
function Entity:CancelAnimations(whitelist)
	for _, animation in pairs(self.animator:GetPlayingAnimationTracks()) do
		-- Stop only animations included in the whitelist when one is provided.
		if whitelist then
			if whitelist[animation.Name] then animation:Stop() end
		else
			animation:Stop()
		end
	end
end

-- Return the Entity class.
return Entity
