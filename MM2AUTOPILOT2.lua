-- ============================================================================
-- 1. SERVICES
-- ============================================================================
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

-- ============================================================================
-- 2. CONFIGURATION & CONSTANTS
-- ============================================================================
local CONFIG = {
	PathRecomputeCooldown = 0.25,
	TargetMoveThreshold = 8.0,
	DestinationMoveThreshold = 6.0,
	WaypointReachedDistance = 3.5,
	StuckTimeThreshold = 1.0,
	StuckMovementThreshold = 0.8,
	JumpCooldown = 0.6,
	BehaviorSwitchMargin = 2,
	CollectTargetLockTime = 5.0,
	
	-- Map Scan Bounds
	MapScanBatchSize = 150,
	
	-- Raycast Parameters for Obstacles & Bump Detection
	RaycastDistance = 4.5,
	SideOffset = 2.0,
	BumpSensitivityDistance = 2.2,
	
	-- Priority Order (Collection forced to HIGHEST)
	Defaults = {
		Priority_AutoCollect = 1000, -- Maximum Priority
		Priority_AvoidMurderer = 100,
		Priority_AvoidSheriff = 90,
		Priority_AvoidInnocent = 10,
		Priority_SelectedPlayer = 80,
		Priority_ChaseMurderer = 70,
		Priority_ChaseSheriff = 65,
		Priority_ChaseInnocent = 60,
		WalkSpeed = 16,
		JumpPower = 50,
		CollectDistance = 500,
		ChaseMinDistance = 4,
		ChaseMaxDistance = 150,
		AvoidDistance = 35,
		AutoMapScanOnStart = true,
	}
}

-- ============================================================================
-- 3. CENTRAL STATE MANAGEMENT
-- ============================================================================
local State = {
	-- Toggles
	AutoCollect = true, -- Default ON for Collection Priority
	ChaseEnabled = false,
	AvoidEnabled = false,
	ESPEnabled = true,
	NavEnabled = true,
	SmartRepath = true,
	ObstacleDetection = true,
	JumpAssist = true,
	StuckRecovery = true,
	SideRecovery = true,
	AutoTurnOnBump = true,
	AutoMapScanOnStart = CONFIG.Defaults.AutoMapScanOnStart,
	
	-- Dynamic Movement & Ranges
	WalkSpeed = CONFIG.Defaults.WalkSpeed,
	JumpPower = CONFIG.Defaults.JumpPower,
	CollectDistance = CONFIG.Defaults.CollectDistance,
	ChaseMinDistance = CONFIG.Defaults.ChaseMinDistance,
	ChaseMaxDistance = CONFIG.Defaults.ChaseMaxDistance,
	AvoidDistance = CONFIG.Defaults.AvoidDistance,
	
	-- Dynamic Priorities
	Priority = {
		AutoCollect = CONFIG.Defaults.Priority_AutoCollect,
		AvoidMurderer = CONFIG.Defaults.Priority_AvoidMurderer,
		AvoidSheriff = CONFIG.Defaults.Priority_AvoidSheriff,
		AvoidInnocent = CONFIG.Defaults.Priority_AvoidInnocent,
		SelectedPlayer = CONFIG.Defaults.Priority_SelectedPlayer,
		ChaseMurderer = CONFIG.Defaults.Priority_ChaseMurderer,
		ChaseSheriff = CONFIG.Defaults.Priority_ChaseSheriff,
		ChaseInnocent = CONFIG.Defaults.Priority_ChaseInnocent,
	},
	
	-- Target Tracking
	SelectedPlayer = nil,
	CurrentBehavior = "IDLE",
	CurrentTargetName = "None",
	StatusText = "IDLE",
	
	-- Map Scan State
	MapScanRunning = false,
	MapScanProgress = 0,
	MapScanObjectsScanned = 0,
	
	-- Internal Path & Collision State
	PathState = {
		Path = nil,
		Waypoints = {},
		CurrentWaypointIndex = 1,
		Destination = nil,
		SourcePosition = nil,
		ActivePriority = 0,
		TargetPosition = nil,
		LastComputeTime = 0,
		ForceRepath = false,
		BlockedConnection = nil,
		LastPosition = Vector3.zero,
		LastMovementTime = 0,
		JumpCooldownTime = 0,
		FailedAttempts = 0,
		RecoveryAttempts = 0,
		IsRecovering = false,
		RecoveryDirection = nil,
		LastBumpTime = 0,
	}
}

-- Cleanup Architecture
local Janitor = {
	Connections = {},
	ESPObjects = {},
	UIElements = {}
}

function Janitor.Add(conn)
	table.insert(Janitor.Connections, conn)
end

function Janitor.CleanAll()
	for _, conn in ipairs(Janitor.Connections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear(Janitor.Connections)
	
	for _, espGroup in pairs(Janitor.ESPObjects) do
		if espGroup.Highlight then espGroup.Highlight:Destroy() end
		if espGroup.Billboard then espGroup.Billboard:Destroy() end
	end
	table.clear(Janitor.ESPObjects)
end

-- ============================================================================
-- 4. CHARACTER MANAGER
-- ============================================================================
local CharacterManager = {}
local LocalPlayer = Players.LocalPlayer
local Character = nil
local Humanoid = nil
local RootPart = nil

function CharacterManager.GetCharacter()
	if Character and Character.Parent and Humanoid and Humanoid.Health > 0 and RootPart and RootPart.Parent then
		return Character, Humanoid, RootPart
	end
	
	Character = LocalPlayer.Character
	if Character then
		Humanoid = Character:FindFirstChildOfClass("Humanoid")
		RootPart = Character:FindFirstChild("HumanoidRootPart")
	end
	
	if Character and Humanoid and Humanoid.Health > 0 and RootPart then
		return Character, Humanoid, RootPart
	end
	
	return nil, nil, nil
end

function CharacterManager.ApplyMovementStats()
	local _, hum = CharacterManager.GetCharacter()
	if hum then
		hum.WalkSpeed = State.WalkSpeed
		hum.UseJumpPower = true
		hum.JumpPower = State.JumpPower
	end
end

-- ============================================================================
-- 5. CONFIGURATION PERSISTENCE SYSTEM (SAVE / LOAD)
-- ============================================================================
local ConfigManager = {}
local CONFIG_FILE_KEY = "IMDE_HUB_V9_CONFIG"

function ConfigManager.SaveConfig()
	local saveData = {
		WalkSpeed = State.WalkSpeed,
		JumpPower = State.JumpPower,
		CollectDistance = State.CollectDistance,
		ChaseMinDistance = State.ChaseMinDistance,
		ChaseMaxDistance = State.ChaseMaxDistance,
		AvoidDistance = State.AvoidDistance,
		AutoTurnOnBump = State.AutoTurnOnBump,
		Priority = State.Priority,
		AutoMapScanOnStart = State.AutoMapScanOnStart,
	}
	
	local success, json = pcall(function()
		return HttpService:JSONEncode(saveData)
	end)
	
	if success and json then
		LocalPlayer:SetAttribute(CONFIG_FILE_KEY, json)
	end
end

function ConfigManager.LoadConfig()
	local json = LocalPlayer:GetAttribute(CONFIG_FILE_KEY)
	if not json or type(json) ~= "string" then return false end
	
	local success, data = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	
	if success and data then
		if data.WalkSpeed then State.WalkSpeed = data.WalkSpeed end
		if data.JumpPower then State.JumpPower = data.JumpPower end
		if data.CollectDistance then State.CollectDistance = data.CollectDistance end
		if data.ChaseMinDistance then State.ChaseMinDistance = data.ChaseMinDistance end
		if data.ChaseMaxDistance then State.ChaseMaxDistance = data.ChaseMaxDistance end
		if data.AvoidDistance then State.AvoidDistance = data.AvoidDistance end
		if data.AutoTurnOnBump ~= nil then State.AutoTurnOnBump = data.AutoTurnOnBump end
		if data.Priority then
			for k, v in pairs(data.Priority) do
				if State.Priority[k] ~= nil then State.Priority[k] = v end
			end
		end
		CharacterManager.ApplyMovementStats()
		return true
	end
	return false
end

-- ============================================================================
-- 6. DYNAMIC ROLE RESOLVER (KNIFE = MURDERER, GUN = SHERIFF, NONE = INNOCENT)
-- ============================================================================
local RoleResolver = {}

function RoleResolver.GetPlayerRole(player)
	if not player or not player.Character then return "Innocent" end
	
	local char = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	
	local hasKnife = false
	local hasGun = false
	
	local function checkItem(item)
		if item and item:IsA("Tool") then
			local name = item.Name:lower()
			if name:find("knife") or name:find("blade") or name:find("murder") or name:find("sword") or name:find("dagger") then
				hasKnife = true
			elseif name:find("gun") or name:find("revolver") or name:find("sheriff") or name:find("pistol") or name:find("shooter") then
				hasGun = true
			end
		end
	end
	
	-- Check equipped item in Character
	for _, child in ipairs(char:GetChildren()) do
		checkItem(child)
	end
	
	-- Check unequipped items in Backpack
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			checkItem(child)
		end
	end
	
	if hasKnife then
		return "Murderer"
	elseif hasGun then
		return "Sheriff"
	else
		return "Innocent"
	end
end

-- ============================================================================
-- 7. HIGH-PRIORITY COLLECTION ENGINE
-- ============================================================================
local CollectionManager = {
	Cache = {},
	LockedTarget = nil,
	LockTimestamp = 0,
}

function CollectionManager.GetObjectPosition(inst)
	if not inst or not inst.Parent then return nil end
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		if inst.PrimaryPart then return inst.PrimaryPart.Position end
		return inst:GetPivot().Position
	elseif inst:IsA("Folder") then
		local firstPart = inst:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then return firstPart.Position end
	end
	return nil
end

function CollectionManager.Register(inst)
	if CollectionManager.Cache[inst] then return end
	local pos = CollectionManager.GetObjectPosition(inst)
	if pos then
		CollectionManager.Cache[inst] = {
			Position = pos,
			Instance = inst
		}
	end
end

function CollectionManager.Unregister(inst)
	CollectionManager.Cache[inst] = nil
	if CollectionManager.LockedTarget == inst then
		CollectionManager.LockedTarget = nil
	end
end

function CollectionManager.Init()
	Janitor.Add(CollectionService:GetInstanceAddedSignal("Collectable"):Connect(function(inst)
		CollectionManager.Register(inst)
	end))
	
	Janitor.Add(CollectionService:GetInstanceRemovedSignal("Collectable"):Connect(function(inst)
		CollectionManager.Unregister(inst)
	end))
	
	for _, inst in ipairs(CollectionService:GetTagged("Collectable")) do
		CollectionManager.Register(inst)
	end
	
	local itemFolders = {"CoinContainer", "Coins", "Items", "CurrencyContainer", "Drops"}
	for _, folderName in ipairs(itemFolders) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				CollectionManager.Register(child)
			end
			Janitor.Add(folder.ChildAdded:Connect(function(child) CollectionManager.Register(child) end))
			Janitor.Add(folder.ChildRemoved:Connect(function(child) CollectionManager.Unregister(child) end))
		end
	end
end

function CollectionManager.GetBestCandidate(rootPos)
	local now = os.clock()
	
	if CollectionManager.LockedTarget then
		local lockObj = CollectionManager.LockedTarget
		if lockObj and lockObj.Parent and (now - CollectionManager.LockTimestamp < CONFIG.CollectTargetLockTime) then
			local pos = CollectionManager.GetObjectPosition(lockObj)
			if pos and (pos - rootPos).Magnitude <= State.CollectDistance then
				return lockObj, pos, (pos - rootPos).Magnitude
			end
		end
		CollectionManager.LockedTarget = nil
	end
	
	local bestInst = nil
	local bestPos = nil
	local lowestDist = math.huge
	
	for inst, data in pairs(CollectionManager.Cache) do
		if not inst or not inst.Parent then
			CollectionManager.Cache[inst] = nil
		else
			local currentPos = CollectionManager.GetObjectPosition(inst) or data.Position
			local dist = (currentPos - rootPos).Magnitude
			if dist <= State.CollectDistance and dist < lowestDist then
				lowestDist = dist
				bestInst = inst
				bestPos = currentPos
			end
		end
	end
	
	if bestInst and bestPos then
		CollectionManager.LockedTarget = bestInst
		CollectionManager.LockTimestamp = now
		return bestInst, bestPos, lowestDist
	end
	
	return nil, nil, math.huge
end

-- ============================================================================
-- 8. SMART MAP SCANNER & PATHWAY TOPOLOGY MEMORY
-- ============================================================================
local NavigationCache = {
	Initialized = false,
	Obstacles = {},
	WalkableNodes = {},
}

local MapScanner = {}

function MapScanner.StartScan(onComplete)
	if State.MapScanRunning then return end
	State.MapScanRunning = true
	State.MapScanProgress = 0
	State.MapScanObjectsScanned = 0
	
	table.clear(NavigationCache.Obstacles)
	table.clear(NavigationCache.WalkableNodes)
	
	task.spawn(function()
		local allInstances = workspace:GetDescendants()
		local total = #allInstances
		local batchCount = 0
		
		for i, inst in ipairs(allInstances) do
			if not State.MapScanRunning then break end
			State.MapScanObjectsScanned = State.MapScanObjectsScanned + 1
			
			if inst:IsA("BasePart") and inst.CanCollide then
				if inst.Size.Magnitude > 8 then
					table.insert(NavigationCache.Obstacles, inst.Position)
				elseif inst.Size.X > 4 and inst.Size.Z > 4 then
					table.insert(NavigationCache.WalkableNodes, inst.Position + Vector3.new(0, 3, 0))
				end
			end
			
			batchCount = batchCount + 1
			if batchCount >= CONFIG.MapScanBatchSize then
				batchCount = 0
				State.MapScanProgress = math.clamp(i / total, 0, 1)
				task.wait()
			end
		end
		
		NavigationCache.Initialized = true
		State.MapScanProgress = 1
		State.MapScanRunning = false
		if onComplete then onComplete() end
	end)
end

-- ============================================================================
-- 9. OBSTACLE SCANNER & ANTI-BUMP SYSTEM
-- ============================================================================
local ObstacleScanner = {}

local reusableParams = RaycastParams.new()
reusableParams.FilterType = RaycastParamsFilterType.Exclude
reusableParams.IgnoreWater = true

function ObstacleScanner.CheckBumpAndTurn(rootPart, hum)
	if not State.AutoTurnOnBump then return false end
	local now = os.clock()
	local ps = State.PathState
	
	if (now - ps.LastBumpTime) < 0.8 then return false end
	
	reusableParams.FilterDescendantsInstances = {rootPart.Parent}
	local lookRay = workspace:Raycast(rootPart.Position, rootPart.CFrame.LookVector * CONFIG.BumpSensitivityDistance, reusableParams)
	
	if lookRay and lookRay.Instance and lookRay.Instance.CanCollide then
		ps.LastBumpTime = now
		rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(180), 0)
		hum:MoveTo(rootPart.Position + (rootPart.CFrame.LookVector * 8))
		ps.ForceRepath = true
		return true
	end
	
	return false
end

function ObstacleScanner.ScanAhead(rootPart, targetWaypointDir)
	if not State.ObstacleDetection then return false, false, nil end
	
	reusableParams.FilterDescendantsInstances = {rootPart.Parent}
	local origin = rootPart.Position
	local moveDir = Vector3.new(targetWaypointDir.X, 0, targetWaypointDir.Z).Unit
	if moveDir.Magnitude ~= moveDir.Magnitude or moveDir.Magnitude == 0 then
		moveDir = rootPart.CFrame.LookVector
	end
	
	local rayDist = CONFIG.RaycastDistance
	local rightVec = Vector3.new(-moveDir.Z, 0, moveDir.X)
	
	local centerRay = workspace:Raycast(origin, moveDir * rayDist, reusableParams)
	local lowRay = workspace:Raycast(origin - Vector3.new(0, 1.5, 0), moveDir * rayDist, reusableParams)
	local upperRay = workspace:Raycast(origin + Vector3.new(0, 1.5, 0), moveDir * rayDist, reusableParams)
	local leftRay = workspace:Raycast(origin - (rightVec * CONFIG.SideOffset), moveDir * rayDist, reusableParams)
	local rightRay = workspace:Raycast(origin + (rightVec * CONFIG.SideOffset), moveDir * rayDist, reusableParams)
	
	local isBlocked = (centerRay ~= nil) or (lowRay ~= nil) or (leftRay ~= nil and rightRay ~= nil)
	local canJumpOver = (lowRay ~= nil or centerRay ~= nil) and (upperRay == nil)
	
	local suggestedSide = nil
	if leftRay == nil then
		suggestedSide = -rightVec
	elseif rightRay == nil then
		suggestedSide = rightVec
	end
	
	return isBlocked, canJumpOver, suggestedSide
end

-- ============================================================================
-- 10. CANDIDATE EVALUATION & BEHAVIOR MANAGER
-- ============================================================================
local BehaviorManager = {}

function BehaviorManager.EvaluateCandidates()
	local _, _, root = CharacterManager.GetCharacter()
	if not root then return nil end
	
	local rootPos = root.Position
	local candidates = {}
	
	-- 1. Auto Collect Candidate (HIGHEST PRIORITY)
	if State.AutoCollect then
		local collectInst, collectPos, _ = CollectionManager.GetBestCandidate(rootPos)
		if collectInst and collectPos then
			table.insert(candidates, {
				BehaviorName = "AUTO COLLECT",
				Priority = State.Priority.AutoCollect,
				TargetPosition = collectPos,
				TargetName = collectInst.Name,
				TargetInstance = collectInst,
			})
		end
	end
	
	-- 2. Selected Player Candidate
	if State.SelectedPlayer and State.SelectedPlayer.Parent and State.SelectedPlayer.Character then
		local selChar = State.SelectedPlayer.Character
		local selRoot = selChar:FindFirstChild("HumanoidRootPart")
		local selHum = selChar:FindFirstChildOfClass("Humanoid")
		
		if selRoot and selHum and selHum.Health > 0 then
			local dist = (selRoot.Position - rootPos).Magnitude
			if dist <= State.ChaseMaxDistance and dist >= State.ChaseMinDistance then
				table.insert(candidates, {
					BehaviorName = "SELECTED PLAYER",
					Priority = State.Priority.SelectedPlayer,
					TargetPosition = selRoot.Position,
					TargetName = State.SelectedPlayer.DisplayName,
					TargetInstance = selRoot,
				})
			end
		end
	end
	
	-- 3. Chase & Avoid Candidates
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			local pChar = player.Character
			local pRoot = pChar:FindFirstChild("HumanoidRootPart")
			local pHum = pChar:FindFirstChildOfClass("Humanoid")
			
			if pRoot and pHum and pHum.Health > 0 then
				local dist = (pRoot.Position - rootPos).Magnitude
				local role = RoleResolver.GetPlayerRole(player)
				
				-- Chase Candidate
				if State.ChaseEnabled and dist <= State.ChaseMaxDistance and dist >= State.ChaseMinDistance then
					local chasePrio = State.Priority.ChaseInnocent
					if role == "Murderer" then chasePrio = State.Priority.ChaseMurderer
					elseif role == "Sheriff" then chasePrio = State.Priority.ChaseSheriff end
					
					table.insert(candidates, {
						BehaviorName = "CHASE " .. role:upper(),
						Priority = chasePrio,
						TargetPosition = pRoot.Position,
						TargetName = player.DisplayName,
						TargetInstance = pRoot,
					})
				end
				
				-- Avoid Candidate
				if State.AvoidEnabled and dist <= State.AvoidDistance then
					local avoidPrio = State.Priority.AvoidInnocent
					if role == "Murderer" then avoidPrio = State.Priority.AvoidMurderer
					elseif role == "Sheriff" then avoidPrio = State.Priority.AvoidSheriff end
					
					local avoidDir = (rootPos - pRoot.Position).Unit
					local avoidPos = rootPos + (avoidDir * (State.AvoidDistance + 10))
					
					table.insert(candidates, {
						BehaviorName = "AVOID " .. role:upper(),
						Priority = avoidPrio,
						TargetPosition = avoidPos,
						TargetName = player.DisplayName,
						TargetInstance = pRoot,
					})
				end
			end
		end
	end
	
	if #candidates == 0 then return nil end
	
	table.sort(candidates, function(a, b)
		if a.Priority ~= b.Priority then return a.Priority > b.Priority end
		return (a.TargetPosition - rootPos).Magnitude < (b.TargetPosition - rootPos).Magnitude
	end)
	
	local topCandidate = candidates[1]
	
	if State.CurrentBehavior ~= "IDLE" and State.CurrentBehavior ~= topCandidate.BehaviorName then
		local currentActivePrio = State.PathState.ActivePriority or 0
		if (topCandidate.Priority - currentActivePrio) < CONFIG.BehaviorSwitchMargin then
			for _, cand in ipairs(candidates) do
				if cand.BehaviorName == State.CurrentBehavior then return cand end
			end
		end
	end
	
	return topCandidate
end

-- ============================================================================
-- 11. CENTRAL NAVIGATION CONTROLLER
-- ============================================================================
local NavigationController = {}

function NavigationController.ResetPathState()
	local ps = State.PathState
	if ps.BlockedConnection then
		ps.BlockedConnection:Disconnect()
		ps.BlockedConnection = nil
	end
	ps.Path = nil
	table.clear(ps.Waypoints)
	ps.CurrentWaypointIndex = 1
	ps.Destination = nil
	ps.SourcePosition = nil
	ps.ActivePriority = 0
	ps.TargetPosition = nil
	ps.ForceRepath = false
	ps.FailedAttempts = 0
	ps.RecoveryAttempts = 0
	ps.IsRecovering = false
	ps.RecoveryDirection = nil
end

function NavigationController.ComputePath(startPos, endPos)
	local ps = State.PathState
	local now = os.clock()
	
	if (now - ps.LastComputeTime) < CONFIG.PathRecomputeCooldown then return false end
	ps.LastComputeTime = now
	
	local path = PathfindingService:CreatePath({
		AgentRadius = 2.0,
		AgentHeight = 5.0,
		AgentCanJump = true,
		WaypointSpacing = 3.5,
	})
	
	local success, _ = pcall(function()
		path:ComputeAsync(startPos, endPos)
	end)
	
	if success and path.Status == Enum.PathStatus.Success then
		if ps.BlockedConnection then ps.BlockedConnection:Disconnect() end
		
		ps.Path = path
		ps.Waypoints = path:GetWaypoints()
		ps.CurrentWaypointIndex = 2
		ps.Destination = endPos
		ps.SourcePosition = startPos
		ps.ForceRepath = false
		ps.FailedAttempts = 0
		
		ps.BlockedConnection = path.Blocked:Connect(function(blockedIdx)
			if blockedIdx >= ps.CurrentWaypointIndex then ps.ForceRepath = true end
		end)
		return true
	else
		ps.FailedAttempts = ps.FailedAttempts + 1
		return false
	end
end

function NavigationController.Step(dt)
	if not State.NavEnabled then
		State.StatusText = "DISABLED"
		return
	end
	
	local char, hum, root = CharacterManager.GetCharacter()
	if not char or not hum or not root then
		State.StatusText = "NO CHARACTER"
		return
	end
	
	-- Anti-Bump Action
	if ObstacleScanner.CheckBumpAndTurn(root, hum) then
		State.StatusText = "BUMP TURN"
		return
	end
	
	local candidate = BehaviorManager.EvaluateCandidates()
	if not candidate then
		State.CurrentBehavior = "IDLE"
		State.CurrentTargetName = "None"
		State.StatusText = "IDLE"
		NavigationController.ResetPathState()
		return
	end
	
	State.CurrentBehavior = candidate.BehaviorName
	State.CurrentTargetName = candidate.TargetName
	
	local ps = State.PathState
	local rootPos = root.Position
	local now = os.clock()
	
	-- Stuck Recovery
	local distMoved = (rootPos - ps.LastPosition).Magnitude
	if distMoved < CONFIG.StuckMovementThreshold then
		if (now - ps.LastMovementTime) >= CONFIG.StuckTimeThreshold then
			if State.StuckRecovery then
				ps.RecoveryAttempts = ps.RecoveryAttempts + 1
				if ps.RecoveryAttempts <= 3 then
					ps.IsRecovering = true
					ps.RecoveryDirection = (root.CFrame.RightVector * (ps.RecoveryAttempts % 2 == 0 and 1 or -1))
					ps.LastMovementTime = now
				else
					ps.ForceRepath = true
					ps.RecoveryAttempts = 0
				end
			end
		end
	else
		ps.LastPosition = rootPos
		ps.LastMovementTime = now
		ps.RecoveryAttempts = 0
	end
	
	-- Dynamic Repath Trigger
	local needsRepath = ps.ForceRepath
	if not ps.Path or #ps.Waypoints == 0 or ps.CurrentWaypointIndex > #ps.Waypoints then
		needsRepath = true
	elseif ps.TargetPosition and (candidate.TargetPosition - ps.TargetPosition).Magnitude > CONFIG.TargetMoveThreshold then
		needsRepath = true
	elseif ps.Destination and (candidate.TargetPosition - ps.Destination).Magnitude > CONFIG.DestinationMoveThreshold then
		needsRepath = true
	end
	
	if needsRepath then
		ps.ActivePriority = candidate.Priority
		ps.TargetPosition = candidate.TargetPosition
		local computed = NavigationController.ComputePath(rootPos, candidate.TargetPosition)
		if not computed and ps.FailedAttempts > 2 then
			if (candidate.TargetPosition - rootPos).Magnitude < 35 then
				hum:MoveTo(candidate.TargetPosition)
				State.StatusText = "DIRECT FALLBACK"
				return
			end
		end
	end
	
	if ps.IsRecovering and ps.RecoveryDirection then
		State.StatusText = "RECOVERING"
		hum:MoveTo(rootPos + (ps.RecoveryDirection * 6))
		if (now - ps.LastMovementTime) > 0.6 then ps.IsRecovering = false end
		return
	end
	
	if ps.Waypoints and #ps.Waypoints > 0 and ps.CurrentWaypointIndex <= #ps.Waypoints then
		local targetWaypoint = ps.Waypoints[ps.CurrentWaypointIndex]
		local targetPos = targetWaypoint.Position
		local flatDist = (Vector3.new(targetPos.X, rootPos.Y, targetPos.Z) - rootPos).Magnitude
		
		if flatDist <= CONFIG.WaypointReachedDistance then
			ps.CurrentWaypointIndex = ps.CurrentWaypointIndex + 1
			if ps.CurrentWaypointIndex <= #ps.Waypoints then
				targetWaypoint = ps.Waypoints[ps.CurrentWaypointIndex]
				targetPos = targetWaypoint.Position
			else
				hum:MoveTo(rootPos)
				State.StatusText = "REACHED"
				return
			end
		end
		
		local wayDir = (targetPos - rootPos).Unit
		local isBlocked, canJump, sideVec = ObstacleScanner.ScanAhead(root, wayDir)
		
		if isBlocked then
			if canJump and State.JumpAssist and (now - ps.JumpCooldownTime) >= CONFIG.JumpCooldown then
				hum.Jump = true
				ps.JumpCooldownTime = now
			elseif sideVec and State.SideRecovery then
				hum:MoveTo(rootPos + (sideVec * 5))
				return
			else
				ps.ForceRepath = true
			end
		end
		
		if targetWaypoint.Action == Enum.PathWaypointAction.Jump and State.JumpAssist and (now - ps.JumpCooldownTime) >= CONFIG.JumpCooldown then
			hum.Jump = true
			ps.JumpCooldownTime = now
		end
		
		hum:MoveTo(targetPos)
		State.StatusText = State.CurrentBehavior .. " -> " .. State.CurrentTargetName
	else
		State.StatusText = "COMPUTING..."
	end
end

-- ============================================================================
-- 12. ENHANCED ESP MANAGER (ACCURATE ROLES, DISTANCE & HIGHLIGHTS)
-- ============================================================================
local ESPManager = {}

function ESPManager.Update()
	if not State.ESPEnabled then
		for _, espGroup in pairs(Janitor.ESPObjects) do
			if espGroup.Highlight then espGroup.Highlight.Enabled = false end
			if espGroup.Billboard then espGroup.Billboard.Enabled = false end
		end
		return
	end
	
	local _, _, root = CharacterManager.GetCharacter()
	local localPos = root and root.Position or Vector3.zero
	
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			local char = player.Character
			local pHad = char:FindFirstChild("Head")
			local pRoot = char:FindFirstChild("HumanoidRootPart")
			
			if pHad and pRoot then
				local espGroup = Janitor.ESPObjects[char]
				if not espGroup then
					-- Highlight Creation
					local hl = Instance.new("Highlight")
					hl.Name = "IMDE_ESP_HL"
					hl.FillTransparency = 0.4
					hl.OutlineTransparency = 0.1
					hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					hl.Parent = char
					
					-- Billboard GUI Creation
					local bb = Instance.new("BillboardGui")
					bb.Name = "IMDE_ESP_BB"
					bb.Size = UDim2.new(0, 160, 0, 45)
					bb.StudsOffset = Vector3.new(0, 3, 0)
					bb.AlwaysOnTop = true
					bb.Adornee = pHad
					bb.Parent = char
					
					local lbl = Instance.new("TextLabel")
					lbl.Name = "InfoLabel"
					lbl.Size = UDim2.new(1, 0, 1, 0)
					lbl.BackgroundTransparency = 1
					lbl.Font = Enum.Font.GothamBold
					lbl.TextSize = 11
					lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
					lbl.TextStrokeTransparency = 0.2
					lbl.Parent = bb
					
					espGroup = {Highlight = hl, Billboard = bb}
					Janitor.ESPObjects[char] = espGroup
				end
				
				espGroup.Highlight.Enabled = true
				espGroup.Billboard.Enabled = true
				
				local role = RoleResolver.GetPlayerRole(player)
				local dist = math.floor((pRoot.Position - localPos).Magnitude)
				local mainColor = Color3.fromRGB(0, 255, 120) -- Innocent Default
				
				if role == "Murderer" then
					mainColor = Color3.fromRGB(255, 0, 75)
				elseif role == "Sheriff" then
					mainColor = Color3.fromRGB(0, 150, 255)
				end
				
				espGroup.Highlight.FillColor = mainColor
				
				local infoLbl = espGroup.Billboard:FindFirstChild("InfoLabel")
				if infoLbl then
					infoLbl.Text = string.format("%s\n[%s] - %dm", player.DisplayName, role:upper(), dist)
					infoLbl.TextColor3 = mainColor
				end
			end
		end
	end
end

-- ============================================================================
-- 13. UI MANAGER (RESIZABLE CONTROL PANEL)
-- ============================================================================
local UIManager = {}

local COLOR_BG = Color3.fromRGB(18, 14, 28)
local COLOR_PANEL = Color3.fromRGB(28, 20, 42)
local COLOR_ACCENT = Color3.fromRGB(160, 32, 240)
local COLOR_NEON = Color3.fromRGB(200, 80, 255)
local COLOR_TEXT = Color3.fromRGB(240, 235, 255)
local COLOR_MUTED = Color3.fromRGB(150, 140, 170)

function UIManager.CreateRoundedFrame(parent, size, pos, bg)
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = pos
	frame.BackgroundColor3 = bg
	frame.BorderSizePixel = 0
	frame.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	return frame
end

function UIManager.BuildUI()
	local targetGuiParent = LocalPlayer:FindFirstChildOfClass("PlayerGui") or CoreGui
	
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "IMDE_HUB_V9"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = targetGuiParent
	Janitor.UIElements.ScreenGui = screenGui
	
	-- Resizable Main Frame
	local mainFrame = UIManager.CreateRoundedFrame(screenGui, UDim2.new(0, 400, 0, 520), UDim2.new(0.05, 0, 0.15, 0), COLOR_BG)
	mainFrame.ClipsDescendants = true
	mainFrame.Active = true
	mainFrame.Draggable = true
	Janitor.UIElements.MainFrame = mainFrame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_ACCENT
	stroke.Thickness = 1.5
	stroke.Parent = mainFrame
	
	-- Resizer Grip
	local resizeGrip = Instance.new("TextButton")
	resizeGrip.Size = UDim2.new(0, 16, 0, 16)
	resizeGrip.Position = UDim2.new(1, -16, 1, -16)
	resizeGrip.BackgroundTransparency = 1
	resizeGrip.Font = Enum.Font.GothamBold
	resizeGrip.Text = "◢"
	resizeGrip.TextColor3 = COLOR_NEON
	resizeGrip.TextSize = 12
	resizeGrip.Parent = mainFrame
	
	local isResizing = false
	local startSize, startMouse
	
	resizeGrip.MouseButton1Down:Connect(function()
		isResizing = true
		startSize = mainFrame.AbsoluteSize
		startMouse = UserInputService:GetMouseLocation()
	end)
	
	Janitor.Add(UserInputService.InputChanged:Connect(function(input)
		if isResizing and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = UserInputService:GetMouseLocation() - startMouse
			local newX = math.clamp(startSize.X + delta.X, 320, 700)
			local newY = math.clamp(startSize.Y + delta.Y, 380, 850)
			mainFrame.Size = UDim2.new(0, newX, 0, newY)
		end
	end))
	
	Janitor.Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then isResizing = false end
	end))

	-- Header Bar
	local header = UIManager.CreateRoundedFrame(mainFrame, UDim2.new(1, 0, 0, 45), UDim2.new(0, 0, 0, 0), COLOR_PANEL)
	
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.6, 0, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "IMDE HUB V9"
	title.TextColor3 = COLOR_NEON
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	
	-- Exit Button
	local exitBtn = Instance.new("TextButton")
	exitBtn.Size = UDim2.new(0, 28, 0, 28)
	exitBtn.Position = UDim2.new(1, -34, 0, 8)
	exitBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 60)
	exitBtn.Font = Enum.Font.GothamBold
	exitBtn.Text = "✕"
	exitBtn.TextColor3 = COLOR_TEXT
	exitBtn.TextSize = 13
	exitBtn.Parent = header
	
	local exitCorner = Instance.new("UICorner")
	exitCorner.CornerRadius = UDim.new(0, 6)
	exitCorner.Parent = exitBtn
	
	exitBtn.MouseButton1Click:Connect(function()
		Janitor.CleanAll()
		screenGui:Destroy()
	end)
	
	-- Scroll Frame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -16, 1, -55)
	scroll.Position = UDim2.new(0, 8, 0, 50)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = COLOR_ACCENT
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = mainFrame
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll
	
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 15)
	end)
	
	local function CreateSection(titleText, order)
		local secFrame = UIManager.CreateRoundedFrame(scroll, UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 0, 0), COLOR_PANEL)
		secFrame.LayoutOrder = order
		secFrame.ClipsDescendants = true
		
		local secHeader = Instance.new("TextButton")
		secHeader.Size = UDim2.new(1, 0, 0, 32)
		secHeader.BackgroundTransparency = 1
		secHeader.Font = Enum.Font.GothamBold
		secHeader.Text = "   " .. titleText
		secHeader.TextColor3 = COLOR_TEXT
		secHeader.TextSize = 11
		secHeader.TextXAlignment = Enum.TextXAlignment.Left
		secHeader.Parent = secFrame
		
		local arrow = Instance.new("TextLabel")
		arrow.Size = UDim2.new(0, 30, 0, 32)
		arrow.Position = UDim2.new(1, -30, 0, 0)
		arrow.BackgroundTransparency = 1
		arrow.Font = Enum.Font.GothamBold
		arrow.Text = "▼"
		arrow.TextColor3 = COLOR_MUTED
		arrow.TextSize = 10
		arrow.Parent = secHeader
		
		local content = Instance.new("Frame")
		content.Size = UDim2.new(1, -16, 0, 0)
		content.Position = UDim2.new(0, 8, 0, 32)
		content.BackgroundTransparency = 1
		content.Parent = secFrame
		
		local cLayout = Instance.new("UIListLayout")
		cLayout.Padding = UDim.new(0, 4)
		cLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cLayout.Parent = content
		
		local expanded = false
		secHeader.MouseButton1Click:Connect(function()
			expanded = not expanded
			arrow.Text = expanded and "▲" or "▼"
			local targetHeight = expanded and (cLayout.AbsoluteContentSize.Y + 40) or 32
			TweenService:Create(secFrame, TweenInfo.new(0.2), {Size = UDim2.new(1, 0, 0, targetHeight)}):Play()
		end)
		
		cLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			if expanded then secFrame.Size = UDim2.new(1, 0, 0, cLayout.AbsoluteContentSize.Y + 40) end
		end)
		
		return secFrame, content
	end
	
	local function CreateToggle(parent, labelText, defaultState, callback)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 24)
		row.BackgroundTransparency = 1
		row.Parent = parent
		
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(0.7, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.Gotham
		lbl.Text = labelText
		lbl.TextColor3 = COLOR_TEXT
		lbl.TextSize = 10
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = row
		
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 40, 0, 20)
		btn.Position = UDim2.new(1, -40, 0, 2)
		btn.BackgroundColor3 = defaultState and COLOR_ACCENT or COLOR_BG
		btn.Font = Enum.Font.GothamBold
		btn.Text = defaultState and "ON" or "OFF"
		btn.TextColor3 = COLOR_TEXT
		btn.TextSize = 9
		btn.Parent = row
		
		local bCorner = Instance.new("UICorner")
		bCorner.CornerRadius = UDim.new(0, 4)
		bCorner.Parent = btn
		
		local state = defaultState
		btn.MouseButton1Click:Connect(function()
			state = not state
			btn.BackgroundColor3 = state and COLOR_ACCENT or COLOR_BG
			btn.Text = state and "ON" or "OFF"
			callback(state)
		end)
	end
	
	local function CreateNumberInput(parent, labelText, defaultValue, minVal, maxVal, callback)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 24)
		row.BackgroundTransparency = 1
		row.Parent = parent
		
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(0.6, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.Gotham
		lbl.Text = labelText
		lbl.TextColor3 = COLOR_TEXT
		lbl.TextSize = 10
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = row
		
		local box = Instance.new("TextBox")
		box.Size = UDim2.new(0, 50, 0, 20)
		box.Position = UDim2.new(1, -50, 0, 2)
		box.BackgroundColor3 = COLOR_BG
		box.Font = Enum.Font.GothamBold
		box.Text = tostring(defaultValue)
		box.TextColor3 = COLOR_NEON
		box.TextSize = 10
		box.Parent = row
		
		local bCorner = Instance.new("UICorner")
		bCorner.CornerRadius = UDim.new(0, 4)
		bCorner.Parent = box
		
		box.FocusLost:Connect(function()
			local num = tonumber(box.Text)
			if num then
				num = math.clamp(num, minVal, maxVal)
				box.Text = tostring(num)
				callback(num)
			else
				box.Text = tostring(defaultValue)
			end
		end)
	end

	-- 1. SYSTEM STATUS
	local _, statusContent = CreateSection("SYSTEM STATUS", 1)
	local statusLbl = Instance.new("TextLabel")
	statusLbl.Size = UDim2.new(1, 0, 0, 35)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Font = Enum.Font.Gotham
	statusLbl.Text = "Status: IDLE\nTarget: None"
	statusLbl.TextColor3 = COLOR_NEON
	statusLbl.TextSize = 10
	statusLbl.TextXAlignment = Enum.TextXAlignment.Left
	statusLbl.Parent = statusContent
	Janitor.UIElements.StatusLbl = statusLbl
	
	-- 2. COLLECTION & MOVEMENT
	local _, moveContent = CreateSection("COLLECTION & MOVEMENT", 2)
	CreateToggle(moveContent, "Priority Auto Collect", State.AutoCollect, function(s) State.AutoCollect = s end)
	CreateNumberInput(moveContent, "Collect Distance", State.CollectDistance, 10, 2000, function(val) State.CollectDistance = val end)
	CreateNumberInput(moveContent, "WalkSpeed", State.WalkSpeed, 1, 100, function(val) State.WalkSpeed = val CharacterManager.ApplyMovementStats() end)
	CreateNumberInput(moveContent, "JumpPower", State.JumpPower, 1, 150, function(val) State.JumpPower = val CharacterManager.ApplyMovementStats() end)
	CreateToggle(moveContent, "Auto Turn On Bump", State.AutoTurnOnBump, function(s) State.AutoTurnOnBump = s end)
	
	-- 3. CHASE & AVOID RANGES
	local _, rangeContent = CreateSection("CHASE & AVOID CONTROLS", 3)
	CreateToggle(rangeContent, "Chase Players", State.ChaseEnabled, function(s) State.ChaseEnabled = s end)
	CreateToggle(rangeContent, "Avoid Threats", State.AvoidEnabled, function(s) State.AvoidEnabled = s end)
	CreateNumberInput(rangeContent, "Chase Min Distance", State.ChaseMinDistance, 1, 50, function(val) State.ChaseMinDistance = val end)
	CreateNumberInput(rangeContent, "Chase Max Distance", State.ChaseMaxDistance, 20, 500, function(val) State.ChaseMaxDistance = val end)
	CreateNumberInput(rangeContent, "Avoid Range", State.AvoidDistance, 10, 200, function(val) State.AvoidDistance = val end)

	-- 4. VISUAL ESP
	local _, espContent = CreateSection("PLAYER ESP & ROLES", 4)
	CreateToggle(espContent, "ESP Name, Role & Distance", State.ESPEnabled, function(s) State.ESPEnabled = s end)
	
	-- 5. PRESETS & SAVING
	local _, configContent = CreateSection("CONFIG PERSISTENCE", 5)
	local saveBtn = Instance.new("TextButton")
	saveBtn.Size = UDim2.new(1, 0, 0, 24)
	saveBtn.BackgroundColor3 = COLOR_ACCENT
	saveBtn.Font = Enum.Font.GothamBold
	saveBtn.Text = "SAVE CONFIGURATION"
	saveBtn.TextColor3 = COLOR_TEXT
	saveBtn.TextSize = 10
	saveBtn.Parent = configContent
	
	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0, 4)
	sCorner.Parent = saveBtn
	
	saveBtn.MouseButton1Click:Connect(function()
		ConfigManager.SaveConfig()
		saveBtn.Text = "SAVED!"
		task.delay(1.5, function() saveBtn.Text = "SAVE CONFIGURATION" end)
	end)
end

function UIManager.UpdateStatusDisplay()
	local lbl = Janitor.UIElements.StatusLbl
	if lbl then
		lbl.Text = string.format("Status: %s\nTarget: %s", State.StatusText, State.CurrentTargetName)
	end
end

-- ============================================================================
-- 14. MAIN ENGINE LOOPS & INITIALIZATION
-- ============================================================================
local function Initialize()
	ConfigManager.LoadConfig()
	CollectionManager.Init()
	UIManager.BuildUI()
	
	if State.AutoMapScanOnStart then
		task.defer(function() MapScanner.StartScan() end)
	end
	
	local function OnCharacterAdded(newChar)
		Character = newChar
		Humanoid = newChar:WaitForChild("Humanoid")
		RootPart = newChar:WaitForChild("HumanoidRootPart")
		
		NavigationController.ResetPathState()
		CharacterManager.ApplyMovementStats()
	end
	
	if LocalPlayer.Character then OnCharacterAdded(LocalPlayer.Character) end
	Janitor.Add(LocalPlayer.CharacterAdded:Connect(OnCharacterAdded))
	
	-- Navigation & Movement Loop (~0.05s)
	local lastEngineStep = 0
	Janitor.Add(RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		if now - lastEngineStep >= 0.05 then
			lastEngineStep = now
			NavigationController.Step(dt)
		end
	end))
	
	-- ESP & Status Render Loop (~0.2s)
	local lastUIUpdate = 0
	Janitor.Add(RunService.Stepped:Connect(function()
		local now = os.clock()
		if now - lastUIUpdate >= 0.2 then
			lastUIUpdate = now
			ESPManager.Update()
			UIManager.UpdateStatusDisplay()
		end
	end))
end

-- Execute Script
Initialize()
