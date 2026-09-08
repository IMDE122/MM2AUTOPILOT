--[[
    ================================================================================
    IMDE HUB V11 — SUPREME AUTONOMOUS AI & COMBAT SUITE
    ================================================================================
    Updates in V11:
      - AI Core: Risk-Benefit Utility Evaluator with Threat Dynamics & Multi-Target Logic
      - Auto-Collect Engine: Auto-Tagging System for workspace coin detection
      - Precision Role Engine: Dual-Scan (Character + Backpack) Knife & Gun Finder
      - Defense Matrix: Lead-targeting Auto-Gun Fire + Auto-Knife Throwing
      - UI Dashboard: Tabbed layout with full Minimize & Drag support
      - Expanded Matrix: Unlimited range bounds for ESP, Collect, Avoid & Chase
    ================================================================================
--]]

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ================================================================================
-- CONFIGURATION
-- ================================================================================
local CONFIG = {
	Version = "IMDE HUB V11 — Supreme AI",
	Ranges = {
		ESPMaxDistance = 5000,
		CollectMaxDistance = 3000,
		AvoidDistance = 150,
		ChaseMaxDistance = 2000,
		DefenseMaxDistance = 500,
	},
	Navigation = {
		PathCooldown = 0.15,
		WaypointReachDist = 3.0,
		AgentRadius = 2.0,
		AgentHeight = 5.0,
		AgentCanJump = true,
		StuckTimeout = 0.8,
		JumpCooldown = 0.6,
	},
	Collection = {
		Enabled = true,
		AutoTagInterval = 2.0,
		TargetKeywords = { "coin", "gold", "gem", "diamond", "currency", "drop", "credit" },
		Folders = { "CoinContainer", "Coins", "Items", "CurrencyContainer", "Drops" },
		Tags = { "Collectable", "Coin", "Drop" },
	},
	ESP = {
		Enabled = true,
		FillTransparency = 0.35,
		OutlineTransparency = 0.05,
	},
	AI = {
		Enabled = true,
		AggressionFactor = 1.5,
		SurvivalWeight = 3.0,
		FarmWeight = 1.0,
	},
	Defense = {
		Enabled = true,
		AutoFireCooldown = 0.15,
		BulletSpeed = 350,
		KnifeThrowSpeed = 120,
	},
	UI = {
		MainColor = Color3.fromRGB(15, 12, 22),
		HeaderColor = Color3.fromRGB(24, 18, 36),
		CardColor = Color3.fromRGB(28, 22, 42),
		AccentColor = Color3.fromRGB(138, 43, 226),
		TargetColor = Color3.fromRGB(255, 30, 80),
		TextColor = Color3.fromRGB(250, 250, 255),
		SubTextColor = Color3.fromRGB(160, 155, 180),
		ToggleKey = Enum.KeyCode.RightShift,
	}
}

-- ================================================================================
-- UTILITY FUNCTIONS
-- ================================================================================
local function GetSafeGuiParent()
	local success, _ = pcall(function() return CoreGui.Name end)
	if success and CoreGui then
		return CoreGui
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function getCharacterParts(player)
	if not player then return nil, nil, nil end
	local char = player.Character
	if not char then return nil, nil, nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
	return char, hum, root
end

-- ================================================================================
-- ACCURATE ROLE RESOLVER ENGINE
-- ================================================================================
local RoleResolver = { Cache = {} }

local function IsKnifeTool(tool)
	if not tool or not tool:IsA("Tool") then return false end
	local lname = string.lower(tool.Name)
	if lname:find("knife") or lname:find("blade") or lname:find("dagger") or lname == "murderer" or tool:FindFirstChild("KnifeServer") then
		return true
	end
	return false
end

local function IsGunTool(tool)
	if not tool or not tool:IsA("Tool") then return false end
	local lname = string.lower(tool.Name)
	if lname:find("gun") or lname:find("revolver") or lname:find("pistol") or lname == "sheriff" or tool:FindFirstChild("GunServer") then
		return true
	end
	return false
end

function RoleResolver:Get(player)
	if not player then return "Innocent" end

	local char = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")

	if not char and not backpack then return "Innocent" end

	local function scanContainer(container)
		if not container then return nil end
		for _, item in ipairs(container:GetChildren()) do
			if IsKnifeTool(item) then
				return "Murderer"
			elseif IsGunTool(item) then
				return "Sheriff"
			end
		end
		return nil
	end

	local detected = scanContainer(char) or scanContainer(backpack)
	if detected then
		self.Cache[player] = detected
		return detected
	end

	return self.Cache[player] or "Innocent"
end

function RoleResolver:Clear(player)
	if player then self.Cache[player] = nil else table.clear(self.Cache) end
end

-- ================================================================================
-- DYNAMIC COIN AUTO-TAGGING & COLLECTION ENGINE
-- ================================================================================
local CollectionManager = { Cache = {}, Enabled = CONFIG.Collection.Enabled, LastTagScan = 0 }

function CollectionManager.TagWorkspaceCoins()
	local now = os.clock()
	if now - CollectionManager.LastTagScan < CONFIG.Collection.AutoTagInterval then return end
	CollectionManager.LastTagScan = now

	local function processInstance(inst)
		if inst:IsA("BasePart") or inst:IsA("Model") then
			local lname = string.lower(inst.Name)
			for _, keyword in ipairs(CONFIG.Collection.TargetKeywords) do
				if lname:find(keyword) then
					if not CollectionService:HasTag(inst, "Collectable") then
						CollectionService:AddTag(inst, "Collectable")
					end
					break
				end
			end
		end
	end

	for _, folderName in ipairs(CONFIG.Collection.Folders) do
		local folder = Workspace:FindFirstChild(folderName)
		if folder then
			for _, child in ipairs(folder:GetDescendants()) do
				processInstance(child)
			end
		end
	end

	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("Model") then
			processInstance(child)
		end
	end
end

local function CacheItem(instance)
	if instance:IsA("BasePart") then
		CollectionManager.Cache[instance] = instance
	elseif instance:IsA("Model") then
		CollectionManager.Cache[instance] = instance
	end
end

function CollectionManager.Init()
	for _, tag in ipairs(CONFIG.Collection.Tags) do
		for _, item in ipairs(CollectionService:GetTagged(tag)) do CacheItem(item) end
		CollectionService:GetInstanceAddedSignal(tag):Connect(CacheItem)
	end
	CollectionService:GetInstanceRemovedSignal("Collectable"):Connect(function(item)
		CollectionManager.Cache[item] = nil
	end)
end

function CollectionManager.GetClosestItem()
	CollectionManager.TagWorkspaceCoins()
	local _, _, root = getCharacterParts(LocalPlayer)
	if not root then return nil, nil end

	local closestObj, closestPos = nil, nil
	local minDistance = CONFIG.Ranges.CollectMaxDistance

	for item, _ in pairs(CollectionManager.Cache) do
		if not item or not item.Parent then
			CollectionManager.Cache[item] = nil
		else
			local itemPos = item:IsA("BasePart") and item.Position or item:GetPivot().Position
			local dist = (itemPos - root.Position).Magnitude
			if dist < minDistance then
				minDistance = dist
				closestObj = item
				closestPos = itemPos
			end
		end
	end
	return closestObj, closestPos
end

-- ================================================================================
-- PATHFINDING NAVIGATION ENGINE
-- ================================================================================
local NavigationManager = {
	State = "IDLE",
	Waypoints = {},
	WaypointIndex = 1,
	LastPathCompute = 0,
	LastPosition = Vector3.zero,
	StuckTimer = 0,
	LastJumpTime = 0,
}

function NavigationManager.NavigateTo(targetPos)
	local _, _, root = getCharacterParts(LocalPlayer)
	if not root then return end

	local now = os.clock()
	if now - NavigationManager.LastPathCompute < CONFIG.Navigation.PathCooldown then return end
	NavigationManager.LastPathCompute = now

	local path = PathfindingService:CreatePath({
		AgentRadius = CONFIG.Navigation.AgentRadius,
		AgentHeight = CONFIG.Navigation.AgentHeight,
		AgentCanJump = CONFIG.Navigation.AgentCanJump,
	})

	task.spawn(function()
		local success = pcall(function() path:ComputeAsync(root.Position, targetPos) end)
		if success and path.Status == Enum.PathStatus.Success then
			NavigationManager.Waypoints = path:GetWaypoints()
			NavigationManager.WaypointIndex = 2
			NavigationManager.State = "FOLLOWING"
		else
			NavigationManager.State = "FAILED"
		end
	end)
end

function NavigationManager.Update(dt)
	if NavigationManager.State ~= "FOLLOWING" then return end
	local _, hum, root = getCharacterParts(LocalPlayer)
	if not root or not hum or hum.Health <= 0 then return end

	local movedDistance = (root.Position - NavigationManager.LastPosition).Magnitude
	if movedDistance < 0.2 and hum.MoveDirection.Magnitude > 0.1 then
		NavigationManager.StuckTimer += dt
		if NavigationManager.StuckTimer >= CONFIG.Navigation.StuckTimeout then
			hum.Jump = true
			NavigationManager.StuckTimer = 0
		end
	else
		NavigationManager.StuckTimer = 0
	end
	NavigationManager.LastPosition = root.Position

	if NavigationManager.WaypointIndex <= #NavigationManager.Waypoints then
		local waypoint = NavigationManager.Waypoints[NavigationManager.WaypointIndex]
		local wayPos = waypoint.Position
		local distance = (Vector3.new(wayPos.X, root.Position.Y, wayPos.Z) - root.Position).Magnitude

		if waypoint.Action == Enum.PathWaypointAction.Jump then
			local now = os.clock()
			if now - NavigationManager.LastJumpTime >= CONFIG.Navigation.JumpCooldown then
				hum.Jump = true
				NavigationManager.LastJumpTime = now
			end
		end

		if distance <= CONFIG.Navigation.WaypointReachDist then
			NavigationManager.WaypointIndex += 1
		end
		hum:MoveTo(wayPos)
	else
		NavigationManager.State = "IDLE"
	end
end

-- ================================================================================
-- MULTI-THREAT SELF-DEFENSE & AUTO THROW MODULE
-- ================================================================================
local DefenseEngine = {
	LastShotTime = 0,
	CurrentTarget = nil,
	ThreatScores = {}
}

function DefenseEngine:PredictTargetPosition(origin, targetPart, projectileSpeed)
	local targetPos = targetPart.Position
	local targetVel = targetPart.AssemblyLinearVelocity or targetPart.Velocity or Vector3.zero
	local distance = (targetPos - origin).Magnitude

	local timeOfFlight = (projectileSpeed > 0 and projectileSpeed < 9999) and (distance / projectileSpeed) or 0
	return targetPos + (targetVel * timeOfFlight)
end

function DefenseEngine:HasLineOfSight(origin, predictedPos, targetPart)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
	raycastParams.IgnoreWater = true

	local direction = (predictedPos - origin)
	local result = Workspace:Raycast(origin, direction, raycastParams)

	if not result or (result and result.Instance:IsDescendantOf(targetPart.Parent)) then
		return true
	end
	return false
end

function DefenseEngine:UpdateThreatMatrix()
	table.clear(self.ThreatScores)
	local char, _, root = getCharacterParts(LocalPlayer)
	if not char or not root then
		self.CurrentTarget = nil
		return
	end

	local myPos = root.Position
	local myRole = RoleResolver:Get(LocalPlayer)
	local highestScore = -1
	local selectedTarget = nil

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			local pChar = player.Character
			local targetRoot = pChar:FindFirstChild("HumanoidRootPart")
			local hum = pChar:FindFirstChildOfClass("Humanoid")

			if targetRoot and hum and hum.Health > 0 then
				local role = RoleResolver:Get(player)
				local isEnemy = false

				if myRole == "Murderer" and (role == "Sheriff" or role == "Hero" or role == "Innocent") then
					isEnemy = true
				elseif (myRole == "Sheriff" or myRole == "Hero" or myRole == "Innocent") and role == "Murderer" then
					isEnemy = true
				end

				if isEnemy then
					local distance = (targetRoot.Position - myPos).Magnitude
					if distance <= CONFIG.Ranges.DefenseMaxDistance then
						local distScore = 1 - (distance / CONFIG.Ranges.DefenseMaxDistance)
						local enemyLook = targetRoot.CFrame.LookVector
						local dirToUs = (myPos - targetRoot.Position).Unit
						local facingUsDot = enemyLook:Dot(dirToUs)
						local orientationScore = math.clamp((facingUsDot + 1) / 2, 0, 1)

						local totalScore = (distScore * 0.6) + (orientationScore * 0.4)
						local scorePercent = math.floor(totalScore * 100)
						self.ThreatScores[player] = scorePercent

						if totalScore > highestScore then
							highestScore = totalScore
							selectedTarget = targetRoot
						end
					end
				end
			end
		end
	end

	self.CurrentTarget = selectedTarget
end

function DefenseEngine:Step()
	if not CONFIG.Defense.Enabled then return end
	self:UpdateThreatMatrix()

	if os.clock() - self.LastShotTime < CONFIG.Defense.AutoFireCooldown then return end
	if not self.CurrentTarget then return end

	local char, _, root = getCharacterParts(LocalPlayer)
	if not char or not root then return end

	local myRole = RoleResolver:Get(LocalPlayer)
	local myPos = root.Position

	if myRole == "Murderer" then
		local knifeTool = char:FindFirstChildOfClass("Tool")
		if knifeTool and IsKnifeTool(knifeTool) then
			local throwRemote = knifeTool:FindFirstChild("Throw") or knifeTool:FindFirstChild("ThrowKnife") or knifeTool:FindFirstChild("KnifeServer")
			local predictedAimPos = self:PredictTargetPosition(myPos, self.CurrentTarget, CONFIG.Defense.KnifeThrowSpeed)

			if self:HasLineOfSight(myPos, predictedAimPos, self.CurrentTarget) then
				self.LastShotTime = os.clock()
				if throwRemote and throwRemote:IsA("RemoteEvent") then
					throwRemote:FireServer(predictedAimPos)
				end
			end
		end
	else
		local gunTool = char:FindFirstChildOfClass("Tool")
		if gunTool and IsGunTool(gunTool) then
			local fireRemote = gunTool:FindFirstChild("Shoot") or gunTool:FindFirstChild("ShootRemote") or gunTool:FindFirstChild("GunServer")
			local predictedAimPos = self:PredictTargetPosition(myPos, self.CurrentTarget, CONFIG.Defense.BulletSpeed)

			if self:HasLineOfSight(myPos, predictedAimPos, self.CurrentTarget) then
				self.LastShotTime = os.clock()
				if fireRemote and fireRemote:IsA("RemoteFunction") then
					fireRemote:InvokeServer(predictedAimPos)
				elseif fireRemote and fireRemote:IsA("RemoteEvent") then
					fireRemote:FireServer(predictedAimPos)
				end
			end
		end
	end
end

-- ================================================================================
-- ADVANCED AI BRAIN ENGINE
-- ================================================================================
local AIBrain = { CurrentAction = "IDLE", StatusText = "Engine Active" }

function AIBrain.Step(dt)
	if not CONFIG.AI.Enabled then return end

	local char, hum, root = getCharacterParts(LocalPlayer)
	if not char or not hum or hum.Health <= 0 or not root then
		AIBrain.CurrentAction = "DEAD"
		AIBrain.StatusText = "Awaiting Respawn..."
		return
	end

	local localPos = root.Position
	local myRole = RoleResolver:Get(LocalPlayer)
	local healthRatio = hum.Health / hum.MaxHealth
	local candidates = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local _, pHum, pRoot = getCharacterParts(player)
			if pRoot and pHum and pHum.Health > 0 then
				local dist = (pRoot.Position - localPos).Magnitude
				local role = RoleResolver:Get(player)

				if role == "Murderer" and myRole ~= "Murderer" then
					if dist <= CONFIG.Ranges.AvoidDistance then
						local fleeScore = (CONFIG.Ranges.AvoidDistance / math.max(dist, 1)) * CONFIG.AI.SurvivalWeight * (2 - healthRatio)
						local fleeVector = (localPos - pRoot.Position).Unit * 80
						local fleePos = localPos + fleeVector
						table.insert(candidates, {
							Type = "EVADE",
							Score = fleeScore,
							Position = fleePos,
							Description = "Evading Murderer (" .. player.DisplayName .. ")"
						})
					end
				elseif (myRole == "Sheriff" or myRole == "Hero" or myRole == "Murderer") then
					local isTarget = false
					if myRole == "Murderer" then
						isTarget = true
					elseif role == "Murderer" then
						isTarget = true
					end

					if isTarget and dist <= CONFIG.Ranges.ChaseMaxDistance then
						local chaseScore = 150 + ((CONFIG.Ranges.ChaseMaxDistance - dist) * 0.2) * CONFIG.AI.AggressionFactor
						table.insert(candidates, {
							Type = "CHASE",
							Score = chaseScore,
							Position = pRoot.Position,
							Description = "Hunting Target (" .. player.DisplayName .. ")"
						})
					end
				end
			end
		end
	end

	if CONFIG.Collection.Enabled then
		local item, itemPos = CollectionManager.GetClosestItem()
		if item and itemPos then
			local dist = (itemPos - localPos).Magnitude
			local farmScore = (120 - (dist * 0.05)) * CONFIG.AI.FarmWeight
			table.insert(candidates, {
				Type = "FARM",
				Score = farmScore,
				Position = itemPos,
				Description = "Farming Item: " .. item.Name
			})
		end
	end

	table.sort(candidates, function(a, b) return a.Score > b.Score end)

	if #candidates > 0 then
		local winner = candidates[1]
		AIBrain.CurrentAction = winner.Type
		AIBrain.StatusText = winner.Description
		NavigationManager.NavigateTo(winner.Position)
		NavigationManager.Update(dt)
	else
		AIBrain.CurrentAction = "IDLE"
		AIBrain.StatusText = "AI Standby: Patrolling Matrix"
	end
end

-- ================================================================================
-- DYNAMIC ESP SYSTEM
-- ================================================================================
local ESPManager = {
	ActiveHighlights = {},
	ActiveBillboards = {},
	Colors = {
		Murderer = Color3.fromRGB(255, 30, 80),
		Sheriff  = Color3.fromRGB(30, 140, 255),
		Hero     = Color3.fromRGB(255, 215, 0),
		Innocent = Color3.fromRGB(40, 220, 120)
	}
}

function ESPManager.CreateBillboard(head)
	local bGui = Instance.new("BillboardGui")
	bGui.Name = "IMDE_Tag_V11"
	bGui.Adornee = head
	bGui.Size = UDim2.new(0, 200, 0, 50)
	bGui.StudsOffset = Vector3.new(0, 3.2, 0)
	bGui.AlwaysOnTop = true

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 1
	frame.Parent = bGui

	local label = Instance.new("TextLabel")
	label.Name = "InfoLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = frame

	bGui.Parent = head
	return bGui
end

function ESPManager.Update()
	if not CONFIG.ESP.Enabled then
		for p, h in pairs(ESPManager.ActiveHighlights) do h:Destroy() end
		for p, b in pairs(ESPManager.ActiveBillboards) do b:Destroy() end
		table.clear(ESPManager.ActiveHighlights)
		table.clear(ESPManager.ActiveBillboards)
		return
	end

	local _, _, localRoot = getCharacterParts(LocalPlayer)
	if not localRoot then return end

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			local char = player.Character
			local head = char:FindFirstChild("Head")
			local _, pHum, pRoot = getCharacterParts(player)

			if pRoot and pHum and pHum.Health > 0 and head then
				local dist = (pRoot.Position - localRoot.Position).Magnitude
				if dist <= CONFIG.Ranges.ESPMaxDistance then
					local role = RoleResolver:Get(player)
					local roleColor = ESPManager.Colors[role] or ESPManager.Colors.Innocent

					local h = ESPManager.ActiveHighlights[player]
					if not h or h.Parent ~= char then
						if h then h:Destroy() end
						h = Instance.new("Highlight")
						h.Name = "IMDE_ESP"
						h.Adornee = char
						h.Parent = char
						ESPManager.ActiveHighlights[player] = h
					end

					local b = ESPManager.ActiveBillboards[player]
					if not b or b.Parent ~= head then
						if b then b:Destroy() end
						b = ESPManager.CreateBillboard(head)
						ESPManager.ActiveBillboards[player] = b
					end

					local label = b.Frame.InfoLabel
					local score = DefenseEngine.ThreatScores[player]
					local isTargeted = DefenseEngine.CurrentTarget and DefenseEngine.CurrentTarget.Parent == char

					if isTargeted then
						label.Text = string.format("🎯 TARGET LOCKED 🎯\n[%s] - %s\nThreat: %d%%", player.DisplayName, string.upper(role), score or 100)
						label.TextColor3 = CONFIG.UI.TargetColor
						h.FillColor = CONFIG.UI.TargetColor
					elseif score then
						label.Text = string.format("%s [%s]\nThreat: %d%% (%d studs)", player.DisplayName, string.upper(role), score, math.floor(dist))
						label.TextColor3 = Color3.fromRGB(255, 160, 0)
						h.FillColor = Color3.fromRGB(255, 160, 0)
					else
						label.Text = string.format("%s\n[%s] %d studs", player.DisplayName, string.upper(role), math.floor(dist))
						label.TextColor3 = roleColor
						h.FillColor = roleColor
					end

					h.FillTransparency = CONFIG.ESP.FillTransparency
				else
					if ESPManager.ActiveHighlights[player] then ESPManager.ActiveHighlights[player]:Destroy() ESPManager.ActiveHighlights[player] = nil end
					if ESPManager.ActiveBillboards[player] then ESPManager.ActiveBillboards[player]:Destroy() ESPManager.ActiveBillboards[player] = nil end
				end
			end
		end
	end
end

-- ================================================================================
-- SCREEN-SPACE RETICLE TARGET LOCK
-- ================================================================================
local TargetLockUI = {}
TargetLockUI.__index = TargetLockUI

function TargetLockUI.new()
	local self = setmetatable({}, TargetLockUI)
	local parentGui = GetSafeGuiParent()

	local oldGui = parentGui:FindFirstChild("IMDE_TargetLock_UI")
	if oldGui then oldGui:Destroy() end

	self.ScreenGui = Instance.new("ScreenGui")
	self.ScreenGui.Name = "IMDE_TargetLock_UI"
	self.ScreenGui.ResetOnSpawn = false
	self.ScreenGui.Parent = parentGui

	self.RingFrame = Instance.new("Frame")
	self.RingFrame.Size = UDim2.new(0, 56, 0, 56)
	self.RingFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	self.RingFrame.BackgroundTransparency = 1
	self.RingFrame.Visible = false
	self.RingFrame.Parent = self.ScreenGui

	local outer = Instance.new("Frame")
	outer.Size = UDim2.new(1, 0, 1, 0)
	outer.BackgroundTransparency = 1
	outer.Parent = self.RingFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = CONFIG.UI.TargetColor
	stroke.Thickness = 2
	stroke.Parent = outer
	Instance.new("UICorner", outer).CornerRadius = UDim.new(1, 0)

	local centerDot = Instance.new("Frame")
	centerDot.Size = UDim2.new(0, 6, 0, 6)
	centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
	centerDot.Position = UDim2.new(0.5, 0, 0.5, 0)
	centerDot.BackgroundColor3 = CONFIG.UI.TargetColor
	centerDot.Parent = self.RingFrame
	Instance.new("UICorner", centerDot).CornerRadius = UDim.new(1, 0)

	self.RotationAngle = 0
	return self
end

function TargetLockUI:Update(targetPart)
	if not targetPart or not targetPart:IsA("BasePart") then
		self.RingFrame.Visible = false
		return
	end

	local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
	if onScreen then
		self.RingFrame.Visible = true
		self.RingFrame.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y)
		self.RotationAngle = (self.RotationAngle + 4) % 360
		self.RingFrame.Rotation = self.RotationAngle
	else
		self.RingFrame.Visible = false
	end
end

-- ================================================================================
-- TABBED & MINIMIZABLE GUI DASHBOARD
-- ================================================================================
local function BuildUI()
	local targetParent = GetSafeGuiParent()
	local oldUI = targetParent:FindFirstChild("IMDE_Unified_UI")
	if oldUI then oldUI:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "IMDE_Unified_UI"
	gui.ResetOnSpawn = false
	gui.Parent = targetParent

	local mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(0, 360, 0, 280)
	mainFrame.Position = UDim2.new(0.5, -180, 0.5, -140)
	mainFrame.BackgroundColor3 = CONFIG.UI.MainColor
	mainFrame.Active = true
	mainFrame.Draggable = true
	mainFrame.ClipsDescendants = true
	mainFrame.Parent = gui

	Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = CONFIG.UI.AccentColor
	stroke.Thickness = 1.5
	stroke.Parent = mainFrame

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 36)
	header.BackgroundColor3 = CONFIG.UI.HeaderColor
	header.Parent = mainFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -70, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = CONFIG.Version
	title.TextColor3 = CONFIG.UI.TextColor
	title.Font = Enum.Font.GothamBold
	title.TextSize = 11
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	local minBtn = Instance.new("TextButton")
	minBtn.Size = UDim2.new(0, 26, 0, 26)
	minBtn.Position = UDim2.new(1, -32, 0, 5)
	minBtn.BackgroundColor3 = CONFIG.UI.CardColor
	minBtn.Text = "-"
	minBtn.TextColor3 = CONFIG.UI.TextColor
	minBtn.Font = Enum.Font.GothamBold
	minBtn.TextSize = 14
	minBtn.Parent = header
	Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

	local isMinimized = false
	minBtn.MouseButton1Click:Connect(function()
		isMinimized = not isMinimized
		if isMinimized then
			mainFrame:TweenSize(UDim2.new(0, 360, 0, 36), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.25, true)
			minBtn.Text = "+"
		else
			mainFrame:TweenSize(UDim2.new(0, 360, 0, 280), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.25, true)
			minBtn.Text = "-"
		end
	end)

	-- Navigation Tabs
	local tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, -20, 0, 30)
	tabBar.Position = UDim2.new(0, 10, 0, 42)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = mainFrame

	local contentContainer = Instance.new("Frame")
	contentContainer.Size = UDim2.new(1, -20, 1, -82)
	contentContainer.Position = UDim2.new(0, 10, 0, 76)
	contentContainer.BackgroundTransparency = 1
	contentContainer.Parent = mainFrame

	local tabs = { "AI Core", "Combat", "ESP", "Farm" }
	local tabButtons = {}
	local tabPages = {}

	for i, tabName in ipairs(tabs) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0.23, 0, 1, 0)
		btn.Position = UDim2.new((i - 1) * 0.255, 0, 0, 0)
		btn.BackgroundColor3 = i == 1 and CONFIG.UI.AccentColor or CONFIG.UI.CardColor
		btn.Text = tabName
		btn.TextColor3 = CONFIG.UI.TextColor
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 10
		btn.Parent = tabBar
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
		tabButtons[tabName] = btn

		local page = Instance.new("Frame")
		page.Size = UDim2.new(1, 0, 1, 0)
		page.BackgroundTransparency = 1
		page.Visible = (i == 1)
		page.Parent = contentContainer
		tabPages[tabName] = page
	end

	local function SwitchTab(selected)
		for name, page in pairs(tabPages) do
			page.Visible = (name == selected)
			tabButtons[name].BackgroundColor3 = (name == selected) and CONFIG.UI.AccentColor or CONFIG.UI.CardColor
		end
	end

	for name, btn in pairs(tabButtons) do
		btn.MouseButton1Click:Connect(function() SwitchTab(name) end)
	end

	-- PAGE 1: AI CORE
	local aiStatusCard = Instance.new("Frame")
	aiStatusCard.Size = UDim2.new(1, 0, 0, 60)
	aiStatusCard.BackgroundColor3 = CONFIG.UI.CardColor
	aiStatusCard.Parent = tabPages["AI Core"]
	Instance.new("UICorner", aiStatusCard).CornerRadius = UDim.new(0, 8)

	local aiStatusLabel = Instance.new("TextLabel")
	aiStatusLabel.Size = UDim2.new(1, -16, 1, -12)
	aiStatusLabel.Position = UDim2.new(0, 8, 0, 6)
	aiStatusLabel.BackgroundTransparency = 1
	aiStatusLabel.Text = "Status: Initializing AI System..."
	aiStatusLabel.TextColor3 = CONFIG.UI.SubTextColor
	aiStatusLabel.Font = Enum.Font.Gotham
	aiStatusLabel.TextSize = 10
	aiStatusLabel.TextWrapped = true
	aiStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	aiStatusLabel.Parent = aiStatusCard

	local toggleAiBtn = Instance.new("TextButton")
	toggleAiBtn.Size = UDim2.new(1, 0, 0, 34)
	toggleAiBtn.Position = UDim2.new(0, 0, 0, 68)
	toggleAiBtn.BackgroundColor3 = CONFIG.AI.Enabled and CONFIG.UI.AccentColor or CONFIG.UI.CardColor
	toggleAiBtn.Text = "Toggle AI Decision Engine"
	toggleAiBtn.TextColor3 = CONFIG.UI.TextColor
	toggleAiBtn.Font = Enum.Font.GothamBold
	toggleAiBtn.TextSize = 10
	toggleAiBtn.Parent = tabPages["AI Core"]
	Instance.new("UICorner", toggleAiBtn).CornerRadius = UDim.new(0, 6)

	toggleAiBtn.MouseButton1Click:Connect(function()
		CONFIG.AI.Enabled = not CONFIG.AI.Enabled
		toggleAiBtn.BackgroundColor3 = CONFIG.AI.Enabled and CONFIG.UI.AccentColor or CONFIG.UI.CardColor
	end)

	-- PAGE 2: COMBAT
	local toggleDefenseBtn = Instance.new("TextButton")
	toggleDefenseBtn.Size = UDim2.new(1, 0, 0, 34)
	toggleDefenseBtn.BackgroundColor3 = CONFIG.Defense.Enabled and CONFIG.UI.AccentColor or CONFIG.UI.CardColor
	toggleDefenseBtn.Text = "Auto-Defense & Auto-Knife Throw"
	toggleDefenseBtn.TextColor3 = CONFIG.UI.TextColor
	toggleDefenseBtn.Font = Enum.Font.GothamBold
	toggleDefenseBtn.TextSize = 10
	toggleDefenseBtn.Parent = tabPages["Combat"]
	Instance.new("UICorner", toggleDefenseBtn).CornerRadius = UDim.new(0, 6)

	toggleDefenseBtn.MouseButton1Click:Connect(function()
		CONFIG.Defense.Enabled = not CONFIG.Defense.Enabled
		toggleDefenseBtn.BackgroundColor3 = CONFIG.Defense.Enabled and CONFIG.UI.AccentColor or CONFIG.UI.CardColor
	end)

	-- PAGE 3: ESP
	local toggleEspBtn = Instance.new("TextButton")
	toggleEspBtn.Size = UDim2.new(1, 0, 0, 34)
	toggleEspBtn.BackgroundColor3 = CONFIG.ESP.Enabled and CONFIG.UI.AccentColor or CONFIG.UI.CardColor
	toggleEspBtn.Text = "Toggle Player ESP"
	toggleEspBtn.TextColor3 = CONFIG.UI.TextColor
	toggleEspBtn.Font = Enum.Font.GothamBold
	toggleEspBtn.TextSize = 10
	toggleEspBtn.Parent = tabPages["ESP"]
	Instance.new("UICorner", toggleEspBtn).CornerRadius = UDim.new(0, 6)

	toggleEspBtn.MouseButton1Click:Connect(function()
		CONFIG.ESP.Enabled = not CONFIG.ESP.Enabled
		toggleEspBtn.BackgroundColor3 = CONFIG.ESP.Enabled and CONFIG.UI.AccentColor or CONFIG.UI.CardColor
	end)

	-- PAGE 4: FARM
	local toggleCollectBtn = Instance.new("TextButton")
	toggleCollectBtn.Size = UDim2.new(1, 0, 0, 34)
	toggleCollectBtn.BackgroundColor3 = CONFIG.Collection.Enabled and CONFIG.UI.AccentColor or CONFIG.UI.CardColor
	toggleCollectBtn.Text = "Auto-Collect Items (Auto-Tag)"
	toggleCollectBtn.TextColor3 = CONFIG.UI.TextColor
	toggleCollectBtn.Font = Enum.Font.GothamBold
	toggleCollectBtn.TextSize = 10
	toggleCollectBtn.Parent = tabPages["Farm"]
	Instance.new("UICorner", toggleCollectBtn).CornerRadius = UDim.new(0, 6)

	toggleCollectBtn.MouseButton1Click:Connect(function()
		CONFIG.Collection.Enabled = not CONFIG.Collection.Enabled
		toggleCollectBtn.BackgroundColor3 = CONFIG.Collection.Enabled and CONFIG.UI.AccentColor or CONFIG.UI.CardColor
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == CONFIG.UI.ToggleKey then
			mainFrame.Visible = not mainFrame.Visible
		end
	end)

	RunService.RenderStepped:Connect(function()
		aiStatusLabel.Text = string.format("Action: %s\n%s", AIBrain.CurrentAction, AIBrain.StatusText)
	end)
end

-- ================================================================================
-- INITIALIZATION & MAIN LOOPS
-- ================================================================================
CollectionManager.Init()
BuildUI()
local targetLockHud = TargetLockUI.new()

Players.PlayerRemoving:Connect(function(player)
	RoleResolver:Clear(player)
	if ESPManager.ActiveHighlights[player] then ESPManager.ActiveHighlights[player]:Destroy() end
	if ESPManager.ActiveBillboards[player] then ESPManager.ActiveBillboards[player]:Destroy() end
end)

RunService.Heartbeat:Connect(function(dt)
	AIBrain.Step(dt)
	DefenseEngine:Step()
	ESPManager.Update()
end)

RunService.RenderStepped:Connect(function()
	targetLockHud:Update(DefenseEngine.CurrentTarget)
end)

print("[" .. CONFIG.Version .. "] Fully Mounted & Operational!")
