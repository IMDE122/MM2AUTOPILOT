--[[
    ================================================================
        IMDE HUB V8.2
        ADVANCED ESP & SMART NAVIGATION
    ================================================================

    Intended for:
        Roblox Studio
        Your own Roblox experience

    Location:
        StarterPlayer
        └── StarterPlayerScripts
            └── IMDEHubV82.client.lua

    Features:
        • Advanced ESP
        • Display Name
        • Username
        • Role
        • Distance
        • Health / HP Bar
        • Selected Player Indicator
        • Role Highlight
        • Smart Chase
        • Smart Avoid
        • Selected Player Navigation
        • Auto Collect
        • Path Memory
        • Obstacle Memory
        • Smart Repath
        • Jump Assist
        • Side Recovery
        • Stuck Recovery
        • Incremental Map Scanner
        • Priority System
        • Mobile UI
        • Drag / Resize
        • Minimize / Restore
        • Save / Load / Reset
        • Full Cleanup

    NOTE:
        This script does NOT automate weapon firing or killing.
    ================================================================
]]

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------

local CONFIG = {

    ------------------------------------------------------------
    -- MOVEMENT
    ------------------------------------------------------------

    DefaultWalkSpeed = 16,
    DefaultJumpPower = 50,

    MinWalkSpeed = 0,
    MaxWalkSpeed = 100,

    MinJumpPower = 0,
    MaxJumpPower = 150,

    ------------------------------------------------------------
    -- RANGE
    ------------------------------------------------------------

    DefaultChaseDistance = 500,
    DefaultAvoidDistance = 100,
    DefaultCollectDistance = 250,

    MaxChaseDistance = 2000,
    MaxAvoidDistance = 1000,
    MaxCollectDistance = 1000,

    ------------------------------------------------------------
    -- PATHFINDING
    ------------------------------------------------------------

    PathRecomputeCooldown = 0.40,

    TargetMoveThreshold = 12,
    DestinationMoveThreshold = 10,

    WaypointReachedDistance = 3.5,

    AgentRadius = 2,
    AgentHeight = 5,
    WaypointSpacing = 4,

    ------------------------------------------------------------
    -- OBSTACLE DETECTION
    ------------------------------------------------------------

    RaycastDistance = 6,
    LowRayHeight = 1.5,
    UpperRayHeight = 4,

    SideRayOffset = 2,

    ------------------------------------------------------------
    -- RECOVERY
    ------------------------------------------------------------

    StuckTimeThreshold = 1.5,
    StuckMovementThreshold = 1,

    RecoveryDistance = 7,
    RecoveryDuration = 0.45,

    RecoveryCooldown = 0.8,
    JumpCooldown = 0.8,

    ------------------------------------------------------------
    -- BEHAVIOR
    ------------------------------------------------------------

    BehaviorSwitchMargin = 5,

    CollectTargetLockTime = 4,
    CollectTargetSwitchThreshold = 15,

    ------------------------------------------------------------
    -- MAP SCANNER
    ------------------------------------------------------------

    AutoMapScan = true,

    MapScanBatchSize = 75,

    MapScanMaxDistance = 1000,

    ------------------------------------------------------------
    -- MEMORY
    ------------------------------------------------------------

    RememberPaths = true,
    RememberObstacles = true,

    PathMemoryTTL = 120,
    ObstacleMemoryTTL = 45,

    MemoryCellSize = 12,

    ------------------------------------------------------------
    -- ESP
    ------------------------------------------------------------

    ESPUpdateRate = 0.20,

    ESPMaxDistance = 1500,

    ESPStudsOffset = Vector3.new(0, 4, 0),

    ------------------------------------------------------------
    -- ENGINE
    ------------------------------------------------------------

    MovementUpdateRate = 0.08,

    RoleCacheRate = 0.5,

    UIUpdateRate = 0.20,

    MemoryPruneRate = 5,
}

----------------------------------------------------------------
-- ROLE COLORS
----------------------------------------------------------------

local ROLE_COLORS = {

    Murderer = Color3.fromRGB(255, 60, 60),

    Sheriff = Color3.fromRGB(60, 140, 255),

    Innocent = Color3.fromRGB(60, 255, 100),

    Unknown = Color3.fromRGB(180, 180, 180),
}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------

local State = {

    Running = true,

    ------------------------------------------------------------
    -- MOVEMENT
    ------------------------------------------------------------

    WalkSpeed = CONFIG.DefaultWalkSpeed,

    JumpPower = CONFIG.DefaultJumpPower,

    ChaseDistance = CONFIG.DefaultChaseDistance,

    AvoidDistance = CONFIG.DefaultAvoidDistance,

    CollectDistance = CONFIG.DefaultCollectDistance,

    ------------------------------------------------------------
    -- FEATURES
    ------------------------------------------------------------

    AutoCollect = false,

    ChaseEnabled = false,

    AvoidEnabled = false,

    ESPEnabled = true,

    NavigationEnabled = true,

    SmartRepath = true,

    ObstacleDetection = true,

    JumpAssist = true,

    StuckRecovery = true,

    SideRecovery = true,

    AutoMapScan = CONFIG.AutoMapScan,

    RememberPaths = CONFIG.RememberPaths,

    RememberObstacles = CONFIG.RememberObstacles,

    ------------------------------------------------------------
    -- ESP
    ------------------------------------------------------------

    ESPShowName = true,

    ESPShowUsername = true,

    ESPShowRole = true,

    ESPShowDistance = true,

    ESPShowHealth = true,

    ESPShowSelected = true,

    ESPMaxDistance = CONFIG.ESPMaxDistance,

    ------------------------------------------------------------
    -- TARGET
    ------------------------------------------------------------

    SelectedPlayer = nil,

    ------------------------------------------------------------
    -- STATUS
    ------------------------------------------------------------

    CurrentBehavior = "Idle",

    CurrentTargetName = "None",

    StatusText = "Ready",

    ------------------------------------------------------------
    -- PRIORITY
    ------------------------------------------------------------

    Priority = {

        AvoidMurderer = 100,

        AvoidSheriff = 95,

        AvoidInnocent = 90,

        SelectedPlayer = 80,

        ChaseMurderer = 70,

        ChaseSheriff = 65,

        ChaseInnocent = 60,

        AutoCollect = 50,
    },

    SavedConfig = nil,
}

----------------------------------------------------------------
-- CHARACTER STATE
----------------------------------------------------------------

local CharacterState = {

    Character = nil,

    Humanoid = nil,

    Root = nil,

    OriginalWalkSpeed = nil,

    OriginalJumpPower = nil,
}

----------------------------------------------------------------
-- CONNECTION MANAGER
----------------------------------------------------------------

local Connections = {}

local function connect(signal, callback)
    local connection = signal:Connect(callback)

    table.insert(Connections, connection)

    return connection
end

local function disconnectAll()
    for _, connection in ipairs(Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(Connections)
end

----------------------------------------------------------------
-- UTILITY
----------------------------------------------------------------

local function clampNumber(value, minimum, maximum, fallback)
    value = tonumber(value)

    if not value then
        return fallback
    end

    return math.clamp(value, minimum, maximum)
end

local function isAlive(humanoid)
    return humanoid
        and humanoid.Health > 0
        and humanoid.MaxHealth > 0
end

local function getCharacterParts(player)
    if not player then
        return nil, nil, nil
    end

    local character = player.Character

    if not character then
        return nil, nil, nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root then
        return character, humanoid, root
    end

    if not isAlive(humanoid) then
        return character, humanoid, root
    end

    return character, humanoid, root
end

local function getPosition(instance)
    if not instance then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance.Position
    end

    if instance:IsA("Model") then
        local root = instance.PrimaryPart

        if root then
            return root.Position
        end

        local part = instance:FindFirstChildWhichIsA("BasePart", true)

        if part then
            return part.Position
        end
    end

    return nil
end

local function horizontalDirection(fromPosition, toPosition)
    local direction = Vector3.new(
        toPosition.X - fromPosition.X,
        0,
        toPosition.Z - fromPosition.Z
    )

    if direction.Magnitude < 0.01 then
        return Vector3.zero
    end

    return direction.Unit
end

local function makeCell(position)
    local size = CONFIG.MemoryCellSize

    return string.format(
        "%d:%d",
        math.floor(position.X / size),
        math.floor(position.Z / size)
    )
end

----------------------------------------------------------------
-- CHARACTER MANAGER
----------------------------------------------------------------

local CharacterManager = {}

function CharacterManager:Refresh()
    local character = LocalPlayer.Character

    if character ~= CharacterState.Character then

        CharacterState.Character = character
        CharacterState.Humanoid = nil
        CharacterState.Root = nil

        if character then

            local humanoid =
                character:FindFirstChildOfClass("Humanoid")

            local root =
                character:FindFirstChild("HumanoidRootPart")

            CharacterState.Humanoid = humanoid
            CharacterState.Root = root

            if humanoid then

                CharacterState.OriginalWalkSpeed =
                    humanoid.WalkSpeed

                CharacterState.OriginalJumpPower =
                    humanoid.JumpPower

                humanoid.WalkSpeed = State.WalkSpeed
                humanoid.JumpPower = State.JumpPower
            end

            NavigationController = NavigationController or nil
        end

        return true
    end

    if not CharacterState.Humanoid
        and character then

        CharacterState.Humanoid =
            character:FindFirstChildOfClass("Humanoid")
    end

    if not CharacterState.Root
        and character then

        CharacterState.Root =
            character:FindFirstChild("HumanoidRootPart")
    end

    return false
end

function CharacterManager:ApplyMovement()
    local humanoid = CharacterState.Humanoid

    if not humanoid then
        return
    end

    if humanoid.WalkSpeed ~= State.WalkSpeed then
        humanoid.WalkSpeed = State.WalkSpeed
    end

    if humanoid.JumpPower ~= State.JumpPower then
        humanoid.JumpPower = State.JumpPower
    end
end

function CharacterManager:Restore()
    local humanoid = CharacterState.Humanoid

    if humanoid then

        if CharacterState.OriginalWalkSpeed then
            humanoid.WalkSpeed =
                CharacterState.OriginalWalkSpeed
        end

        if CharacterState.OriginalJumpPower then
            humanoid.JumpPower =
                CharacterState.OriginalJumpPower
        end
    end
end

----------------------------------------------------------------
-- ROLE RESOLVER
----------------------------------------------------------------

local RoleResolver = {

    Cache = {},
}

local function getRoleFromTool(character)

    if not character then
        return nil
    end

    for _, child in ipairs(character:GetChildren()) do

        if child:IsA("Tool") then

            local name = string.lower(child.Name)

            if string.find(name, "knife", 1, true)
                or string.find(name, "blade", 1, true)
                or string.find(name, "dagger", 1, true) then

                return "Murderer"
            end

            if string.find(name, "gun", 1, true)
                or string.find(name, "pistol", 1, true)
                or string.find(name, "revolver", 1, true)
                or string.find(name, "handgun", 1, true) then

                return "Sheriff"
            end
        end
    end

    return nil
end

function RoleResolver:Get(player)

    if not player then
        return "Unknown"
    end

    local now = os.clock()

    local cached = self.Cache[player]

    if cached
        and now - cached.Time < CONFIG.RoleCacheRate then

        return cached.Role
    end

    local role = nil

    ------------------------------------------------------------
    -- CHARACTER ATTRIBUTE
    ------------------------------------------------------------

    if player.Character then

        role = player.Character:GetAttribute("Role")

        if typeof(role) == "string" then
            role = role
        else
            role = nil
        end
    end

    ------------------------------------------------------------
    -- PLAYER ATTRIBUTE
    ------------------------------------------------------------

    if not role then

        local value = player:GetAttribute("Role")

        if typeof(value) == "string" then
            role = value
        end
    end

    ------------------------------------------------------------
    -- TOOL
    ------------------------------------------------------------

    if not role then
        role = getRoleFromTool(player.Character)
    end

    ------------------------------------------------------------
    -- TEAM
    ------------------------------------------------------------

    if not role and player.Team then

        local teamName =
            string.lower(player.Team.Name)

        if string.find(teamName, "murder", 1, true) then
            role = "Murderer"

        elseif string.find(teamName, "sheriff", 1, true) then
            role = "Sheriff"

        elseif string.find(teamName, "innocent", 1, true) then
            role = "Innocent"
        end
    end

    ------------------------------------------------------------
    -- NORMALIZE
    ------------------------------------------------------------

    if role then

        local normalized =
            string.lower(tostring(role))

        if normalized == "murderer"
            or normalized == "murder" then

            role = "Murderer"

        elseif normalized == "sheriff" then

            role = "Sheriff"

        elseif normalized == "innocent" then

            role = "Innocent"

        else
            role = "Unknown"
        end

    else

        role = "Unknown"
    end

    self.Cache[player] = {
        Role = role,
        Time = now,
    }

    return role
end

function RoleResolver:Clear(player)
    self.Cache[player] = nil
end

----------------------------------------------------------------
-- COLLECTION MANAGER
----------------------------------------------------------------

local CollectionManager = {

    Items = {},

    LockedTarget = nil,

    LockedAt = 0,
}

function CollectionManager:RefreshItem(instance)

    if not instance
        or not instance.Parent then

        return
    end

    local position =
        getPosition(instance)

    if position then
        self.Items[instance] = position
    end
end

function CollectionManager:RemoveItem(instance)
    self.Items[instance] = nil

    if self.LockedTarget == instance then
        self.LockedTarget = nil
    end
end

function CollectionManager:GetNearest()

    local root = CharacterState.Root

    if not root then
        return nil
    end

    local nearest = nil
    local nearestDistance = math.huge

    local currentTime = os.clock()

    if self.LockedTarget then

        local locked = self.LockedTarget

        if locked.Parent then

            local lockedPosition =
                getPosition(locked)

            if lockedPosition then

                local lockedDistance =
                    (lockedPosition - root.Position).Magnitude

                if lockedDistance <= State.CollectDistance
                    and currentTime - self.LockedAt
                        <= CONFIG.CollectTargetLockTime then

                    return locked, lockedPosition
                end
            end
        end

        self.LockedTarget = nil
    end

    for instance, position in pairs(self.Items) do

        if not instance.Parent then

            self.Items[instance] = nil

        else

            local newPosition =
                getPosition(instance)

            if newPosition then

                position = newPosition
                self.Items[instance] = position

                local distance =
                    (position - root.Position).Magnitude

                if distance <= State.CollectDistance
                    and distance < nearestDistance then

                    nearest = instance
                    nearestDistance = distance
                end
            end
        end
    end

    if nearest then

        self.LockedTarget = nearest
        self.LockedAt = currentTime

        return nearest, self.Items[nearest]
    end

    return nil
end

----------------------------------------------------------------
-- INITIAL COLLECTABLE CACHE
----------------------------------------------------------------

for _, item in ipairs(
    CollectionService:GetTagged("Collectable")
) do

    CollectionManager:RefreshItem(item)
end

connect(
    CollectionService:GetInstanceAddedSignal("Collectable"),
    function(instance)

        CollectionManager:RefreshItem(instance)
    end
)

connect(
    CollectionService:GetInstanceRemovedSignal("Collectable"),
    function(instance)

        CollectionManager:RemoveItem(instance)
    end
)

----------------------------------------------------------------
-- NAVIGATION MEMORY
----------------------------------------------------------------

local NavigationMemory = {

    Paths = {},

    Obstacles = {},
}

function NavigationMemory:MakePathKey(
    startPosition,
    destinationPosition
)

    return makeCell(startPosition)
        .. "|"
        .. makeCell(destinationPosition)
end

function NavigationMemory:StorePath(
    startPosition,
    destinationPosition,
    waypoints
)

    if not State.RememberPaths then
        return
    end

    if not waypoints
        or #waypoints == 0 then

        return
    end

    local positions = {}

    for _, waypoint in ipairs(waypoints) do

        table.insert(
            positions,
            waypoint.Position
        )
    end

    local key =
        self:MakePathKey(
            startPosition,
            destinationPosition
        )

    self.Paths[key] = {

        Positions = positions,

        Time = os.clock(),
    }
end

function NavigationMemory:GetPath(
    startPosition,
    destinationPosition
)

    if not State.RememberPaths then
        return nil
    end

    local key =
        self:MakePathKey(
            startPosition,
            destinationPosition
        )

    local memory =
        self.Paths[key]

    if not memory then
        return nil
    end

    if os.clock() - memory.Time
        > CONFIG.PathMemoryTTL then

        self.Paths[key] = nil

        return nil
    end

    return memory.Positions
end

function NavigationMemory:RememberObstacle(position)

    if not State.RememberObstacles then
        return
    end

    local cell =
        makeCell(position)

    self.Obstacles[cell] = {

        Position = position,

        Time = os.clock(),
    }
end

function NavigationMemory:IsNearObstacle(
    position,
    distance
)

    if not State.RememberObstacles then
        return false
    end

    local size = CONFIG.MemoryCellSize

    local cellX =
        math.floor(position.X / size)

    local cellZ =
        math.floor(position.Z / size)

    for x = cellX - 1, cellX + 1 do

        for z = cellZ - 1, cellZ + 1 do

            local key =
                tostring(x)
                .. ":"
                .. tostring(z)

            local obstacle =
                self.Obstacles[key]

            if obstacle then

                if os.clock() - obstacle.Time
                    > CONFIG.ObstacleMemoryTTL then

                    self.Obstacles[key] = nil

                else

                    local offset =
                        obstacle.Position - position

                    if Vector3.new(
                        offset.X,
                        0,
                        offset.Z
                    ).Magnitude <= distance then

                        return true
                    end
                end
            end
        end
    end

    return false
end

function NavigationMemory:ClearPaths()
    table.clear(self.Paths)
end

function NavigationMemory:ClearObstacles()
    table.clear(self.Obstacles)
end

function NavigationMemory:Prune()

    local now = os.clock()

    for key, memory in pairs(self.Paths) do

        if now - memory.Time
            > CONFIG.PathMemoryTTL then

            self.Paths[key] = nil
        end
    end

    for key, memory in pairs(self.Obstacles) do

        if now - memory.Time
            > CONFIG.ObstacleMemoryTTL then

            self.Obstacles[key] = nil
        end
    end
end

----------------------------------------------------------------
-- MAP SCANNER
----------------------------------------------------------------

local MapScanner = {

    Objects = {},

    Queue = {},

    QueueIndex = 1,

    LastScan = 0,
}

local function isPlayerCharacter(instance)

    local model =
        instance:IsA("Model")
        and instance
        or instance:FindFirstAncestorOfClass("Model")

    if not model then
        return false
    end

    return model:FindFirstChildOfClass("Humanoid") ~= nil
end

function MapScanner:Add(instance)

    if not instance
        or not instance.Parent then

        return
    end

    if isPlayerCharacter(instance) then
        return
    end

    if instance:IsA("BasePart") then

        if instance.CanCollide
            and instance.Size.Magnitude >= 8 then

            self.Objects[instance] = {
                Position = instance.Position,
                Time = os.clock(),
            }
        end
    end
end

function MapScanner:Remove(instance)
    self.Objects[instance] = nil
end

function MapScanner:BeginScan()

    self.Queue =
        workspace:GetDescendants()

    self.QueueIndex = 1

    self.LastScan = os.clock()
end

function MapScanner:Step()

    if not State.AutoMapScan then
        return
    end

    if #self.Queue == 0 then
        self:BeginScan()
    end

    local root =
        CharacterState.Root

    if not root then
        return
    end

    local processed = 0

    while processed < CONFIG.MapScanBatchSize
        and self.QueueIndex <= #self.Queue do

        local instance =
            self.Queue[self.QueueIndex]

        self.QueueIndex += 1

        processed += 1

        if instance then

            if not isPlayerCharacter(instance)
                and instance:IsA("BasePart")
                and instance.CanCollide then

                local distance =
                    (instance.Position - root.Position).Magnitude

                if distance <= CONFIG.MapScanMaxDistance
                    and instance.Size.Magnitude >= 8 then

                    self:Add(instance)
                end
            end
        end
    end

    if self.QueueIndex > #self.Queue then

        self.Queue = {}

        self.QueueIndex = 1
    end
end

function MapScanner:Clear()

    table.clear(self.Objects)

    self.Queue = {}

    self.QueueIndex = 1
end

connect(
    workspace.DescendantAdded,
    function(instance)

        task.defer(function()

            if State.Running then
                MapScanner:Add(instance)
            end

        end)
    end
)

connect(
    workspace.DescendantRemoving,
    function(instance)

        MapScanner:Remove(instance)
    end
)

MapScanner:BeginScan()

----------------------------------------------------------------
-- OBSTACLE SCANNER
----------------------------------------------------------------

local ObstacleScanner = {

    Params = nil,

    LastCharacter = nil,
}

function ObstacleScanner:RefreshFilter()

    local filter = {}

    if LocalPlayer.Character then
        table.insert(
            filter,
            LocalPlayer.Character
        )
    end

    for _, player in ipairs(
        Players:GetPlayers()
    ) do

        if player ~= LocalPlayer
            and player.Character then

            table.insert(
                filter,
                player.Character
            )
        end
    end

    local params =
        RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances =
        filter

    params.IgnoreWater = true

    self.Params = params

    self.LastCharacter =
        LocalPlayer.Character
end

function ObstacleScanner:EnsureFilter()

    if not self.Params
        or self.LastCharacter
            ~= LocalPlayer.Character then

        self:RefreshFilter()
    end
end

function ObstacleScanner:Check(
    destination
)

    if not State.ObstacleDetection then
        return nil
    end

    local root =
        CharacterState.Root

    if not root then
        return nil
    end

    self:EnsureFilter()

    local origin =
        root.Position

    local direction =
        horizontalDirection(
            origin,
            destination
        )

    if direction.Magnitude < 0.01 then
        return nil
    end

    local right =
        Vector3.new(
            -direction.Z,
            0,
            direction.X
        )

    local rayDistance =
        CONFIG.RaycastDistance

    local centerResult =
        workspace:Raycast(
            origin,
            direction * rayDistance,
            self.Params
        )

    local lowResult =
        workspace:Raycast(
            origin
                + Vector3.new(
                    0,
                    CONFIG.LowRayHeight,
                    0
                ),
            direction * rayDistance,
            self.Params
        )

    local upperResult =
        workspace:Raycast(
            origin
                + Vector3.new(
                    0,
                    CONFIG.UpperRayHeight,
                    0
                ),
            direction * rayDistance,
            self.Params
        )

    local leftResult =
        workspace:Raycast(
            origin,
            (
                direction * rayDistance
            )
                - (
                    right
                    * CONFIG.SideRayOffset
                ),
            self.Params
        )

    local rightResult =
        workspace:Raycast(
            origin,
            (
                direction * rayDistance
            )
                + (
                    right
                    * CONFIG.SideRayOffset
                ),
            self.Params
        )

    local hit =
        centerResult
        or lowResult
        or leftResult
        or rightResult

    if hit then

        NavigationMemory:RememberObstacle(
            hit.Position
        )
    end

    return {

        Center = centerResult,

        Low = lowResult,

        Upper = upperResult,

        Left = leftResult,

        Right = rightResult,

        Direction = direction,

        Side = right,
    }
end

----------------------------------------------------------------
-- BEHAVIOR MANAGER
----------------------------------------------------------------

local BehaviorManager = {}

local function makeCandidate(
    key,
    priority,
    destination,
    target,
    targetPosition,
    description
)

    if not destination then
        return nil
    end

    return {

        Key = key,

        Priority = priority,

        Destination = destination,

        Target = target,

        TargetPosition = targetPosition,

        Description = description or key,
    }
end

local function getPlayerTarget(player)

    local character,
        humanoid,
        root =
        getCharacterParts(player)

    if not root
        or not isAlive(humanoid) then

        return nil, nil, nil
    end

    return character, humanoid, root
end

function BehaviorManager:GetCandidates()

    local candidates = {}

    local localRoot =
        CharacterState.Root

    if not localRoot then
        return candidates
    end

    local localPosition =
        localRoot.Position

    ------------------------------------------------------------
    -- SELECTED PLAYER
    ------------------------------------------------------------

    local selected =
        State.SelectedPlayer

    if selected
        and selected ~= LocalPlayer then

        local _, humanoid, root =
            getPlayerTarget(selected)

        if root and isAlive(humanoid) then

            local distance =
                (root.Position - localPosition).Magnitude

            if distance <= State.ChaseDistance then

                local candidate =
                    makeCandidate(
                        "SelectedPlayer",
                        State.Priority.SelectedPlayer,
                        root.Position,
                        selected,
                        root.Position,
                        "Selected: "
                            .. selected.DisplayName
                    )

                if candidate then
                    table.insert(
                        candidates,
                        candidate
                    )
                end
            end
        end
    end

    ------------------------------------------------------------
    -- OTHER PLAYERS
    ------------------------------------------------------------

    for _, player in ipairs(
        Players:GetPlayers()
    ) do

        if player ~= LocalPlayer then

            local _, humanoid, root =
                getPlayerTarget(player)

            if root and isAlive(humanoid) then

                local distance =
                    (root.Position - localPosition).Magnitude

                if State.AvoidEnabled
                    and distance <= State.AvoidDistance then

                    local role =
                        RoleResolver:Get(player)

                    local priorityKey =
                        "Avoid" .. role

                    local priority =
                        State.Priority[priorityKey]

                    if priority then

                        local away =
                            horizontalDirection(
                                root.Position,
                                localPosition
                            )

                        if away.Magnitude < 0.01 then

                            away =
                                Vector3.new(
                                    1,
                                    0,
                                    0
                                )
                        end

                        local escapeDistance =
                            math.clamp(
                                State.AvoidDistance * 0.55,
                                30,
                                90
                            )

                        local destination =
                            localPosition
                            + away * escapeDistance

                        local candidate =
                            makeCandidate(
                                priorityKey,
                                priority,
                                destination,
                                player,
                                root.Position,
                                "Avoid "
                                    .. role
                                    .. ": "
                                    .. player.DisplayName
                            )

                        if candidate then

                            table.insert(
                                candidates,
                                candidate
                            )
                        end
                    end
                end

                ------------------------------------------------
                -- CHASE
                ------------------------------------------------

                if State.ChaseEnabled
                    and distance <= State.ChaseDistance then

                    local role =
                        RoleResolver:Get(player)

                    local priorityKey =
                        "Chase" .. role

                    local priority =
                        State.Priority[priorityKey]

                    if priority then

                        local candidate =
                            makeCandidate(
                                priorityKey,
                                priority,
                                root.Position,
                                player,
                                root.Position,
                                "Chase "
                                    .. role
                                    .. ": "
                                    .. player.DisplayName
                            )

                        if candidate then

                            table.insert(
                                candidates,
                                candidate
                            )
                        end
                    end
                end
            end
        end
    end

    ------------------------------------------------------------
    -- AUTO COLLECT
    ------------------------------------------------------------

    if State.AutoCollect then

        local item, position =
            CollectionManager:GetNearest()

        if item and position then

            local candidate =
                makeCandidate(
                    "AutoCollect",
                    State.Priority.AutoCollect,
                    position,
                    item,
                    position,
                    "Collect: "
                        .. item.Name
                )

            if candidate then

                table.insert(
                    candidates,
                    candidate
                )
            end
        end
    end

    return candidates
end

function BehaviorManager:Choose(candidates)

    if #candidates == 0 then
        return nil
    end

    table.sort(
        candidates,
        function(a, b)

            if a.Priority ~= b.Priority then
                return a.Priority > b.Priority
            end

            local root =
                CharacterState.Root

            if not root then
                return false
            end

            local distanceA =
                (a.Destination - root.Position).Magnitude

            local distanceB =
                (b.Destination - root.Position).Magnitude

            return distanceA < distanceB
        end
    )

    local best =
        candidates[1]

    ------------------------------------------------------------
    -- HYSTERESIS
    ------------------------------------------------------------

    if NavigationController
        and NavigationController.ActiveCandidate then

        local current =
            NavigationController.ActiveCandidate

        if current.Key ~= best.Key then

            if current.Priority
                >= best.Priority
                    - CONFIG.BehaviorSwitchMargin then

                return current
            end
        end
    end

    return best
end

----------------------------------------------------------------
-- NAVIGATION CONTROLLER
----------------------------------------------------------------

NavigationController = {

    Path = nil,

    Waypoints = nil,

    CurrentWaypointIndex = 0,

    Destination = nil,

    SourcePosition = nil,

    ActivePriority = nil,

    ActiveBehavior = nil,

    ActiveTarget = nil,

    TargetPosition = nil,

    LastComputeTime = 0,

    ForceRepath = false,

    BlockedConnection = nil,

    LastPosition = nil,

    LastProgressTime = 0,

    LastMoveCommandPosition = nil,

    LastRecoveryTime = 0,

    LastJumpTime = 0,

    RecoveryDirection = 1,

    IsRecovering = false,

    RecoveryStartTime = 0,

    ActiveCandidate = nil,

    FailedAttempts = 0,
}

function NavigationController:Reset()

    if self.BlockedConnection then

        pcall(function()
            self.BlockedConnection:Disconnect()
        end)

        self.BlockedConnection = nil
    end

    self.Path = nil
    self.Waypoints = nil
    self.CurrentWaypointIndex = 0

    self.Destination = nil
    self.SourcePosition = nil

    self.ActivePriority = nil
    self.ActiveBehavior = nil
    self.ActiveTarget = nil
    self.TargetPosition = nil

    self.LastMoveCommandPosition = nil

    self.IsRecovering = false
    self.RecoveryStartTime = 0

    self.ForceRepath = true
end

function NavigationController:NeedsRepath(candidate)

    if self.ForceRepath then
        return true
    end

    if not self.Path
        or not self.Waypoints
        or self.CurrentWaypointIndex <= 0 then

        return true
    end

    if not self.ActiveCandidate then
        return true
    end

    if self.ActiveBehavior
        ~= candidate.Key then

        return true
    end

    if self.ActiveTarget
        ~= candidate.Target then

        return true
    end

    ------------------------------------------------------------
    -- SmartRepath controls extra recalculation.
    -- It must NOT prevent the first path from being built.
    ------------------------------------------------------------

    if not State.SmartRepath then
        return false
    end

    local now =
        os.clock()

    if now - self.LastComputeTime
        < CONFIG.PathRecomputeCooldown then

        return false
    end

    if self.Destination then

        if (
            self.Destination
            - candidate.Destination
        ).Magnitude
            >= CONFIG.DestinationMoveThreshold then

            return true
        end
    end

    if self.TargetPosition
        and candidate.TargetPosition then

        if (
            self.TargetPosition
            - candidate.TargetPosition
        ).Magnitude
            >= CONFIG.TargetMoveThreshold then

            return true
        end
    end

    return false
end

function NavigationController:BuildPath(
    startPosition,
    destination
)

    local path =
        PathfindingService:CreatePath({

            AgentRadius =
                CONFIG.AgentRadius,

            AgentHeight =
                CONFIG.AgentHeight,

            AgentCanJump = true,

            AgentCanClimb = true,

            WaypointSpacing =
                CONFIG.WaypointSpacing,
        })

    local success =
        pcall(function()

            path:ComputeAsync(
                startPosition,
                destination
            )

        end)

    if not success then
        return nil
    end

    if path.Status
        ~= Enum.PathStatus.Success then

        return nil
    end

    local waypoints =
        path:GetWaypoints()

    if #waypoints == 0 then
        return nil
    end

    return path, waypoints
end

function NavigationController:TryMemoryPath(
    startPosition,
    destination
)

    if not State.RememberPaths then
        return nil
    end

    local remembered =
        NavigationMemory:GetPath(
            startPosition,
            destination
        )

    if not remembered
        or #remembered == 0 then

        return nil
    end

    local waypoints = {}

    for _, position in ipairs(remembered) do

        table.insert(
            waypoints,
            {
                Position = position,
                Action =
                    Enum.PathWaypointAction.Walk,
            }
        )
    end

    if #waypoints == 0 then
        return nil
    end

    ------------------------------------------------------------
    -- Basic validation:
    -- if first useful segment is obviously blocked,
    -- discard memory and compute a real path.
    ------------------------------------------------------------

    if #waypoints >= 2
        and State.ObstacleDetection then

        local check =
            ObstacleScanner:Check(
                waypoints[2].Position
            )

        if check and check.Center then
            return nil
        end
    end

    return waypoints
end

function NavigationController:ComputePath(candidate)

    local root =
        CharacterState.Root

    if not root then
        return false
    end

    local destination =
        candidate.Destination

    if not destination then
        return false
    end

    self:Reset()

    self.ActiveCandidate = candidate

    self.ActiveBehavior =
        candidate.Key

    self.ActivePriority =
        candidate.Priority

    self.ActiveTarget =
        candidate.Target

    self.TargetPosition =
        candidate.TargetPosition

    self.Destination =
        destination

    self.SourcePosition =
        root.Position

    local remembered =
        self:TryMemoryPath(
            root.Position,
            destination
        )

    local path
    local waypoints

    if remembered then

        waypoints =
            remembered

    else

        path, waypoints =
            self:BuildPath(
                root.Position,
                destination
            )

        if path and waypoints then

            NavigationMemory:StorePath(
                root.Position,
                destination,
                waypoints
            )
        end
    end

    if not waypoints then

        self.FailedAttempts += 1

        self.ForceRepath = true

        return false
    end

    self.Path = path

    self.Waypoints =
        waypoints

    self.CurrentWaypointIndex =
        (#waypoints >= 2)
        and 2
        or 1

    self.LastComputeTime =
        os.clock()

    self.ForceRepath = false

    self.FailedAttempts = 0

    ------------------------------------------------------------
    -- Actual Path.Blocked only exists for actual Path object.
    -- Memory paths don't have this event.
    ------------------------------------------------------------

    if path then

        self.BlockedConnection =
            path.Blocked:Connect(
                function(blockedIndex)

                    if blockedIndex
                        >= self.CurrentWaypointIndex then

                        self.ForceRepath = true
                    end
                end
            )

        table.insert(
            Connections,
            self.BlockedConnection
        )
    end

    return true
end

function NavigationController:StartRecovery(
    desiredDirection
)

    local root =
        CharacterState.Root

    local humanoid =
        CharacterState.Humanoid

    if not root or not humanoid then
        return
    end

    local now =
        os.clock()

    if now - self.LastRecoveryTime
        < CONFIG.RecoveryCooldown then

        return
    end

    self.LastRecoveryTime = now

    self.IsRecovering = true

    self.RecoveryStartTime = now

    self.RecoveryDirection *= -1

    local direction =
        desiredDirection

    if not direction
        or direction.Magnitude < 0.01 then

        direction =
            Vector3.new(
                0,
                0,
                -1
            )
    else

        direction = direction.Unit
    end

    local side =
        Vector3.new(
            -direction.Z,
            0,
            direction.X
        )

    local recoveryVector =
        (
            direction * self.RecoveryDistance
        )
        + (
            side
            * self.RecoveryDirection
            * self.RecoveryDistance
            * 0.7
        )

    humanoid:MoveTo(
        root.Position
            + recoveryVector
    )

    self.ForceRepath = true
end

function NavigationController:UpdateRecovery()

    if not self.IsRecovering then
        return false
    end

    local humanoid =
        CharacterState.Humanoid

    if not humanoid then
        self.IsRecovering = false
        return false
    end

    if os.clock() - self.RecoveryStartTime
        >= CONFIG.RecoveryDuration then

        self.IsRecovering = false

        self.ForceRepath = true

        return false
    end

    return true
end

function NavigationController:TryJump()

    local humanoid =
        CharacterState.Humanoid

    if not humanoid
        or not State.JumpAssist then

        return
    end

    local now =
        os.clock()

    if now - self.LastJumpTime
        < CONFIG.JumpCooldown then

        return
    end

    self.LastJumpTime = now

    humanoid.Jump = true
end

function NavigationController:Follow(candidate)

    local root =
        CharacterState.Root

    local humanoid =
        CharacterState.Humanoid

    if not root or not humanoid then
        return
    end

    if self:UpdateRecovery() then
        return
    end

    if not self.Waypoints
        or #self.Waypoints == 0 then

        return
    end

    if self.CurrentWaypointIndex
        > #self.Waypoints then

        self.ForceRepath = true

        return
    end

    local waypoint =
        self.Waypoints[
            self.CurrentWaypointIndex
        ]

    if not waypoint then

        self.ForceRepath = true

        return
    end

    local position =
        waypoint.Position

    local distance =
        (position - root.Position).Magnitude

    ------------------------------------------------------------
    -- WAYPOINT REACHED
    ------------------------------------------------------------

    if distance
        <= CONFIG.WaypointReachedDistance then

        self.CurrentWaypointIndex += 1

        if self.CurrentWaypointIndex
            > #self.Waypoints then

            self.ForceRepath = true

            return
        end

        waypoint =
            self.Waypoints[
                self.CurrentWaypointIndex
            ]

        position =
            waypoint.Position
    end

    ------------------------------------------------------------
    -- WAYPOINT JUMP
    ------------------------------------------------------------

    if waypoint.Action
        == Enum.PathWaypointAction.Jump then

        self:TryJump()
    end

    ------------------------------------------------------------
    -- OBSTACLE DETECTION
    ------------------------------------------------------------

    if State.ObstacleDetection then

        local obstacle =
            ObstacleScanner:Check(
                position
            )

        if obstacle then

            if obstacle.Center
                or obstacle.Low then

                ------------------------------------------------
                -- Jump if upper space is open.
                ------------------------------------------------

                if State.JumpAssist
                    and not obstacle.Upper then

                    self:TryJump()

                elseif State.SideRecovery then

                    self:StartRecovery(
                        obstacle.Direction
                    )

                    return
                end
            end
        end
    end

    ------------------------------------------------------------
    -- REMEMBERED OBSTACLE
    ------------------------------------------------------------

    if State.RememberObstacles
        and NavigationMemory:IsNearObstacle(
            position,
            4
        ) then

        if State.SideRecovery then

            self:StartRecovery(
                horizontalDirection(
                    root.Position,
                    position
                )
            )

            return
        end
    end

    ------------------------------------------------------------
    -- MOVE ONLY WHEN NEEDED
    ------------------------------------------------------------

    if not self.LastMoveCommandPosition
        or (
            self.LastMoveCommandPosition
            - position
        ).Magnitude > 2 then

        humanoid:MoveTo(position)

        self.LastMoveCommandPosition =
            position
    end
end

function NavigationController:UpdateStuck()

    if not State.StuckRecovery then
        return
    end

    local root =
        CharacterState.Root

    if not root then
        return
    end

    local now =
        os.clock()

    if not self.LastPosition then

        self.LastPosition =
            root.Position

        self.LastProgressTime =
            now

        return
    end

    local moved =
        (
            root.Position
            - self.LastPosition
        ).Magnitude

    if moved
        >= CONFIG.StuckMovementThreshold then

        self.LastProgressTime =
            now

        self.LastPosition =
            root.Position

        return
    end

    if now - self.LastProgressTime
        >= CONFIG.StuckTimeThreshold then

        local direction = Vector3.zero

        if self.Destination then

            direction =
                horizontalDirection(
                    root.Position,
                    self.Destination
                )
        end

        self:StartRecovery(direction)

        self.LastProgressTime =
            now

        self.LastPosition =
            root.Position
    end
end

function NavigationController:Step(candidate)

    if not State.NavigationEnabled then

        self:Reset()

        return
    end

    if not candidate then

        self:Reset()

        State.CurrentBehavior = "Idle"
        State.CurrentTargetName = "None"

        return
    end

    State.CurrentBehavior =
        candidate.Key

    if candidate.Target
        and candidate.Target:IsA("Player") then

        State.CurrentTargetName =
            candidate.Target.DisplayName

    elseif candidate.Target
        and candidate.Target.Name then

        State.CurrentTargetName =
            candidate.Target.Name

    else

        State.CurrentTargetName =
            "None"
    end

    self:UpdateStuck()

    if self:NeedsRepath(candidate) then

        self:ComputePath(candidate)
    end

    self:Follow(candidate)
end

----------------------------------------------------------------
-- ESP MANAGER
----------------------------------------------------------------

local ESPManager = {

    Objects = {},
}

function ESPManager:GetColor(role)

    return ROLE_COLORS[role]
        or ROLE_COLORS.Unknown
end

function ESPManager:DestroyPlayer(player)

    local data =
        self.Objects[player]

    if not data then
        return
    end

    if data.Highlight then

        pcall(function()
            data.Highlight:Destroy()
        end)
    end

    if data.Billboard then

        pcall(function()
            data.Billboard:Destroy()
        end)
    end

    self.Objects[player] = nil
end

function ESPManager:Create(player)

    if player == LocalPlayer then
        return
    end

    local character =
        player.Character

    if not character then
        return
    end

    local humanoid =
        character:FindFirstChildOfClass(
            "Humanoid"
        )

    local root =
        character:FindFirstChild(
            "HumanoidRootPart"
        )

    if not humanoid or not root then
        return
    end

    ------------------------------------------------------------
    -- Remove stale object for previous character.
    ------------------------------------------------------------

    local old =
        self.Objects[player]

    if old
        and old.Character == character then

        return
    end

    if old then
        self:DestroyPlayer(player)
    end

    ------------------------------------------------------------
    -- HIGHLIGHT
    ------------------------------------------------------------

    local highlight =
        Instance.new("Highlight")

    highlight.Name =
        "IMDE_ESP_Highlight"

    highlight.Adornee =
        character

    highlight.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop

    highlight.FillTransparency =
        0.72

    highlight.OutlineTransparency =
        0

    highlight.Parent =
        character

    ------------------------------------------------------------
    -- BILLBOARD
    ------------------------------------------------------------

    local billboard =
        Instance.new("BillboardGui")

    billboard.Name =
        "IMDE_ESP_Billboard"

    billboard.Adornee =
        root

    billboard.Size =
        UDim2.fromOffset(
            190,
            105
        )

    billboard.StudsOffset =
        CONFIG.ESPStudsOffset

    billboard.AlwaysOnTop =
        true

    billboard.MaxDistance =
        State.ESPMaxDistance

    billboard.ResetOnSpawn =
        false

    billboard.Parent =
        root

    ------------------------------------------------------------
    -- BACKGROUND
    ------------------------------------------------------------

    local background =
        Instance.new("Frame")

    background.Name =
        "Background"

    background.Size =
        UDim2.fromScale(
            1,
            1
        )

    background.BackgroundColor3 =
        Color3.fromRGB(
            18,
            12,
            28
        )

    background.BackgroundTransparency =
        0.18

    background.BorderSizePixel =
        0

    background.Parent =
        billboard

    local corner =
        Instance.new("UICorner")

    corner.CornerRadius =
        UDim.new(
            0,
            8
        )

    corner.Parent =
        background

    local stroke =
        Instance.new("UIStroke")

    stroke.Name =
        "RoleStroke"

    stroke.Thickness =
        1.5

    stroke.Transparency =
        0.15

    stroke.Parent =
        background

    ------------------------------------------------------------
    -- CONTENT
    ------------------------------------------------------------

    local layout =
        Instance.new("UIListLayout")

    layout.Padding =
        UDim.new(
            0,
            1
        )

    layout.HorizontalAlignment =
        Enum.HorizontalAlignment.Center

    layout.VerticalAlignment =
        Enum.VerticalAlignment.Top

    layout.Parent =
        background

    local padding =
        Instance.new("UIPadding")

    padding.PaddingTop =
        UDim.new(
            0,
            4
        )

    padding.PaddingBottom =
        UDim.new(
            0,
            4
        )

    padding.PaddingLeft =
        UDim.new(
            0,
            5
        )

    padding.PaddingRight =
        UDim.new(
            0,
            5
        )

    padding.Parent =
        background

    local function createLabel(
        name,
        text,
        height,
        fontSize
    )

        local label =
            Instance.new("TextLabel")

        label.Name =
            name

        label.Size =
            UDim2.new(
                1,
                0,
                0,
                height
            )

        label.BackgroundTransparency =
            1

        label.Text =
            text

        label.TextColor3 =
            Color3.new(
                1,
                1,
                1
            )

        label.TextStrokeTransparency =
            0.45

        label.Font =
            Enum.Font.GothamBold

        label.TextSize =
            fontSize

        label.TextXAlignment =
            Enum.TextXAlignment.Center

        label.Parent =
            background

        return label
    end

    local selected =
        createLabel(
            "Selected",
            "★ SELECTED ★",
            16,
            11
        )

    local nameLabel =
        createLabel(
            "DisplayName",
            player.DisplayName,
            20,
            14
        )

    local usernameLabel =
        createLabel(
            "Username",
            "@" .. player.Name,
            15,
            10
        )

    local roleLabel =
        createLabel(
            "Role",
            "UNKNOWN",
            17,
            11
        )

    local distanceLabel =
        createLabel(
            "Distance",
            "0 studs",
            15,
            10
        )

    local healthLabel =
        createLabel(
            "HealthText",
            "HP 100 / 100",
            15,
            10
        )

    ------------------------------------------------------------
    -- HEALTH BAR
    ------------------------------------------------------------

    local healthBack =
        Instance.new("Frame")

    healthBack.Name =
        "HealthBack"

    healthBack.Size =
        UDim2.new(
            1,
            0,
            0,
            6
        )

    healthBack.BackgroundColor3 =
        Color3.fromRGB(
            45,
            45,
            45
        )

    healthBack.BorderSizePixel =
        0

    healthBack.Parent =
        background

    local healthCorner =
        Instance.new("UICorner")

    healthCorner.CornerRadius =
        UDim.new(
            1,
            0
        )

    healthCorner.Parent =
        healthBack

    local healthFill =
        Instance.new("Frame")

    healthFill.Name =
        "HealthFill"

    healthFill.Size =
        UDim2.fromScale(
            1,
            1
        )

    healthFill.BackgroundColor3 =
        Color3.fromRGB(
            70,
            255,
            100
        )

    healthFill.BorderSizePixel =
        0

    healthFill.Parent =
        healthBack

    local fillCorner =
        Instance.new("UICorner")

    fillCorner.CornerRadius =
        UDim.new(
            1,
            0
        )

    fillCorner.Parent =
        healthFill

    ------------------------------------------------------------
    -- SAVE
    ------------------------------------------------------------

    self.Objects[player] = {

        Character = character,

        Humanoid = humanoid,

        Root = root,

        Highlight = highlight,

        Billboard = billboard,

        Background = background,

        Stroke = stroke,

        Selected = selected,

        NameLabel = nameLabel,

        UsernameLabel = usernameLabel,

        RoleLabel = roleLabel,

        DistanceLabel = distanceLabel,

        HealthLabel = healthLabel,

        HealthBack = healthBack,

        HealthFill = healthFill,
    }
end

function ESPManager:Ensure(player)

    if player == LocalPlayer then
        return nil
    end

    local character =
        player.Character

    if not character then

        self:DestroyPlayer(player)

        return nil
    end

    local data =
        self.Objects[player]

    if not data
        or data.Character ~= character then

        self:Create(player)

        data =
            self.Objects[player]
    end

    return data
end

function ESPManager:RefreshPlayer(player)

    if player == LocalPlayer then
        return
    end

    local data =
        self:Ensure(player)

    if not data then
        return
    end

    local character =
        player.Character

    local humanoid =
        character
        and character:FindFirstChildOfClass(
            "Humanoid"
        )

    local root =
        character
        and character:FindFirstChild(
            "HumanoidRootPart"
        )

    if not humanoid or not root then

        data.Billboard.Enabled = false
        data.Highlight.Enabled = false

        return
    end

    data.Humanoid = humanoid
    data.Root = root

    data.Billboard.Adornee =
        root

    data.Highlight.Adornee =
        character

    if not State.ESPEnabled then

        data.Billboard.Enabled = false
        data.Highlight.Enabled = false

        return
    end

    if not isAlive(humanoid) then

        data.Billboard.Enabled = false
        data.Highlight.Enabled = false

        return
    end

    local localRoot =
        CharacterState.Root

    if not localRoot then
        return
    end

    local distance =
        (root.Position - localRoot.Position).Magnitude

    if distance > State.ESPMaxDistance then

        data.Billboard.Enabled = false
        data.Highlight.Enabled = false

        return
    end

    ------------------------------------------------------------
    -- ROLE
    ------------------------------------------------------------

    local role =
        RoleResolver:Get(player)

    local roleColor =
        self:GetColor(role)

    data.Highlight.FillColor =
        roleColor

    data.Highlight.OutlineColor =
        roleColor

    data.Stroke.Color =
        roleColor

    data.RoleLabel.Text =
        role:upper()

    data.RoleLabel.TextColor3 =
        roleColor

    ------------------------------------------------------------
    -- NAME
    ------------------------------------------------------------

    data.NameLabel.Visible =
        State.ESPShowName

    data.NameLabel.Text =
        player.DisplayName

    ------------------------------------------------------------
    -- USERNAME
    ------------------------------------------------------------

    data.UsernameLabel.Visible =
        State.ESPShowUsername

    data.UsernameLabel.Text =
        "@" .. player.Name

    ------------------------------------------------------------
    -- ROLE
    ------------------------------------------------------------

    data.RoleLabel.Visible =
        State.ESPShowRole

    ------------------------------------------------------------
    -- DISTANCE
    ------------------------------------------------------------

    data.DistanceLabel.Visible =
        State.ESPShowDistance

    data.DistanceLabel.Text =
        string.format(
            "%.0f studs",
            distance
        )

    ------------------------------------------------------------
    -- HEALTH
    ------------------------------------------------------------

    data.HealthLabel.Visible =
        State.ESPShowHealth

    data.HealthBack.Visible =
        State.ESPShowHealth

    if humanoid.MaxHealth > 0 then

        local health =
            math.clamp(
                humanoid.Health
                    / humanoid.MaxHealth,
                0,
                1
            )

        data.HealthFill.Size =
            UDim2.fromScale(
                health,
                1
            )

        data.HealthLabel.Text =
            string.format(
                "HP %.0f / %.0f",
                humanoid.Health,
                humanoid.MaxHealth
            )
    end

    ------------------------------------------------------------
    -- SELECTED
    ------------------------------------------------------------

    local isSelected =
        State.SelectedPlayer
        == player

    data.Selected.Visible =
        State.ESPShowSelected
        and isSelected

    data.Selected.TextColor3 =
        roleColor

    ------------------------------------------------------------
    -- BILLBOARD
    ------------------------------------------------------------

    data.Billboard.MaxDistance =
        State.ESPMaxDistance

    data.Billboard.Enabled = true
    data.Highlight.Enabled = true
end

function ESPManager:RefreshAll()

    for _, player in ipairs(
        Players:GetPlayers()
    ) do

        if player ~= LocalPlayer then
            self:RefreshPlayer(player)
        end
    end
end

function ESPManager:Clear()

    for player in pairs(self.Objects) do

        self:DestroyPlayer(player)
    end
end

----------------------------------------------------------------
-- ESP PLAYER CONNECTIONS
----------------------------------------------------------------

local PlayerConnections = {}

local function disconnectPlayerConnections(player)

    local list =
        PlayerConnections[player]

    if not list then
        return
    end

    for _, connection in ipairs(list) do

        pcall(function()
            connection:Disconnect()
        end)
    end

    PlayerConnections[player] = nil
end

local function setupPlayerESP(player)

    if player == LocalPlayer then
        return
    end

    disconnectPlayerConnections(player)

    PlayerConnections[player] = {}

    local list =
        PlayerConnections[player]

    table.insert(
        list,
        player.CharacterAdded:Connect(
            function()

                RoleResolver:Clear(player)

                task.wait(0.15)

                if State.Running then
                    ESPManager:Create(player)
                end

                if NavigationController then
                    NavigationController.ForceRepath = true
                end
            end
        )
    )

    table.insert(
        list,
        player.CharacterRemoving:Connect(
            function()

                ESPManager:DestroyPlayer(
                    player
                )

                RoleResolver:Clear(player)
            end
        )
    )

    table.insert(
        list,
        player:GetAttributeChangedSignal("Role"):Connect(
            function()

                RoleResolver:Clear(player)
            end
        )
    )

    table.insert(
        list,
        player:GetPropertyChangedSignal("Team"):Connect(
            function()

                RoleResolver:Clear(player)
            end
        )
    )
end

for _, player in ipairs(
    Players:GetPlayers()
) do

    setupPlayerESP(player)
end

connect(
    Players.PlayerAdded,
    function(player)

        setupPlayerESP(player)
    end
)

connect(
    Players.PlayerRemoving,
    function(player)

        disconnectPlayerConnections(player)

        ESPManager:DestroyPlayer(player)

        RoleResolver:Clear(player)

        if State.SelectedPlayer == player then
            State.SelectedPlayer = nil
        end
    end
)

----------------------------------------------------------------
-- CONFIG MANAGER
----------------------------------------------------------------

local ConfigManager = {}

function ConfigManager:Snapshot()

    return {

        WalkSpeed =
            State.WalkSpeed,

        JumpPower =
            State.JumpPower,

        ChaseDistance =
            State.ChaseDistance,

        AvoidDistance =
            State.AvoidDistance,

        CollectDistance =
            State.CollectDistance,

        ESPMaxDistance =
            State.ESPMaxDistance,

        AutoCollect =
            State.AutoCollect,

        ChaseEnabled =
            State.ChaseEnabled,

        AvoidEnabled =
            State.AvoidEnabled,

        ESPEnabled =
            State.ESPEnabled,

        NavigationEnabled =
            State.NavigationEnabled,

        SmartRepath =
            State.SmartRepath,

        ObstacleDetection =
            State.ObstacleDetection,

        JumpAssist =
            State.JumpAssist,

        StuckRecovery =
            State.StuckRecovery,

        SideRecovery =
            State.SideRecovery,

        AutoMapScan =
            State.AutoMapScan,

        RememberPaths =
            State.RememberPaths,

        RememberObstacles =
            State.RememberObstacles,

        ESPShowName =
            State.ESPShowName,

        ESPShowUsername =
            State.ESPShowUsername,

        ESPShowRole =
            State.ESPShowRole,

        ESPShowDistance =
            State.ESPShowDistance,

        ESPShowHealth =
            State.ESPShowHealth,

        ESPShowSelected =
            State.ESPShowSelected,

        Priority = {},
    }
end

function ConfigManager:Save()

    local snapshot =
        self:Snapshot()

    for key, value in pairs(
        State.Priority
    ) do

        snapshot.Priority[key] =
            value
    end

    State.SavedConfig =
        snapshot

    State.StatusText =
        "Configuration saved"
end

function ConfigManager:Load()

    local config =
        State.SavedConfig

    if not config then

        State.StatusText =
            "No saved configuration"

        return
    end

    for key, value in pairs(config) do

        if key ~= "Priority"
            and State[key] ~= nil then

            State[key] = value
        end
    end

    if config.Priority then

        for key, value in pairs(
            config.Priority
        ) do

            State.Priority[key] =
                clampNumber(
                    value,
                    0,
                    999,
                    State.Priority[key]
                )
        end
    end

    State.WalkSpeed =
        clampNumber(
            State.WalkSpeed,
            CONFIG.MinWalkSpeed,
            CONFIG.MaxWalkSpeed,
            CONFIG.DefaultWalkSpeed
        )

    State.JumpPower =
        clampNumber(
            State.JumpPower,
            CONFIG.MinJumpPower,
            CONFIG.MaxJumpPower,
            CONFIG.DefaultJumpPower
        )

    State.ChaseDistance =
        clampNumber(
            State.ChaseDistance,
            0,
            CONFIG.MaxChaseDistance,
            CONFIG.DefaultChaseDistance
        )

    State.AvoidDistance =
        clampNumber(
            State.AvoidDistance,
            0,
            CONFIG.MaxAvoidDistance,
            CONFIG.DefaultAvoidDistance
        )

    State.CollectDistance =
        clampNumber(
            State.CollectDistance,
            0,
            CONFIG.MaxCollectDistance,
            CONFIG.DefaultCollectDistance
        )

    State.ESPMaxDistance =
        clampNumber(
            State.ESPMaxDistance,
            50,
            3000,
            CONFIG.ESPMaxDistance
        )

    NavigationController:Reset()

    State.StatusText =
        "Configuration loaded"
end

function ConfigManager:Reset()

    State.WalkSpeed =
        CONFIG.DefaultWalkSpeed

    State.JumpPower =
        CONFIG.DefaultJumpPower

    State.ChaseDistance =
        CONFIG.DefaultChaseDistance

    State.AvoidDistance =
        CONFIG.DefaultAvoidDistance

    State.CollectDistance =
        CONFIG.DefaultCollectDistance

    State.ESPMaxDistance =
        CONFIG.ESPMaxDistance

    State.AutoCollect = false
    State.ChaseEnabled = false
    State.AvoidEnabled = false

    State.ESPEnabled = true

    State.NavigationEnabled = true
    State.SmartRepath = true
    State.ObstacleDetection = true
    State.JumpAssist = true
    State.StuckRecovery = true
    State.SideRecovery = true

    State.AutoMapScan = true
    State.RememberPaths = true
    State.RememberObstacles = true

    State.ESPShowName = true
    State.ESPShowUsername = true
    State.ESPShowRole = true
    State.ESPShowDistance = true
    State.ESPShowHealth = true
    State.ESPShowSelected = true

    State.Priority = {

        AvoidMurderer = 100,
        AvoidSheriff = 95,
        AvoidInnocent = 90,

        SelectedPlayer = 80,

        ChaseMurderer = 70,
        ChaseSheriff = 65,
        ChaseInnocent = 60,

        AutoCollect = 50,
    }

    NavigationController:Reset()

    State.StatusText =
        "Configuration reset"
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------

local UI = {

    Gui = nil,

    Main = nil,

    Content = nil,

    Status = nil,

    PlayerList = nil,

    MinimizedButton = nil,

    PlayerButtons = {},

    PlayerButtonConnections = {},

    ToggleObjects = {},
}

local function createInstance(
    className,
    properties,
    parent
)

    local object =
        Instance.new(className)

    for property, value in pairs(
        properties or {}
    ) do

        object[property] =
            value
    end

    if parent then
        object.Parent = parent
    end

    return object
end

local function createCorner(parent, radius)

    return createInstance(
        "UICorner",
        {
            CornerRadius =
                UDim.new(
                    0,
                    radius or 8
                ),
        },
        parent
    )
end

local function createStroke(parent, thickness)

    return createInstance(
        "UIStroke",
        {
            Thickness =
                thickness or 1,

            Transparency =
                0.35,
        },
        parent
    )
end

local function createText(
    parent,
    text,
    size,
    position,
    fontSize
)

    return createInstance(
        "TextLabel",
        {

            Size = size,

            Position = position,

            BackgroundTransparency = 1,

            Text = text,

            TextColor3 =
                Color3.fromRGB(
                    240,
                    235,
                    255
                ),

            TextSize =
                fontSize or 13,

            Font =
                Enum.Font.Gotham,

            TextXAlignment =
                Enum.TextXAlignment.Left,

            TextYAlignment =
                Enum.TextYAlignment.Center,
        },
        parent
    )
end

local function createSection(parent, title)

    local frame =
        createInstance(
            "Frame",
            {

                Size =
                    UDim2.new(
                        1,
                        -10,
                        0,
                        32
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        35,
                        20,
                        50
                    ),

                BorderSizePixel = 0,
            },
            parent
        )

    createCorner(frame, 8)

    local label =
        createText(
            frame,
            title,
            UDim2.new(
                1,
                -20,
                1,
                0
            ),
            UDim2.fromOffset(
                10,
                0
            ),
            12
        )

    label.Font =
        Enum.Font.GothamBold

    return frame
end

local function createButton(
    parent,
    text,
    height
)

    local button =
        createInstance(
            "TextButton",
            {

                Size =
                    UDim2.new(
                        1,
                        -10,
                        0,
                        height or 34
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        40,
                        26,
                        58
                    ),

                BorderSizePixel = 0,

                Text = text,

                TextColor3 =
                    Color3.fromRGB(
                        240,
                        235,
                        255
                    ),

                TextSize = 12,

                Font =
                    Enum.Font.GothamMedium,

                AutoButtonColor = true,
            },
            parent
        )

    createCorner(button, 7)

    return button
end

local function createInput(
    parent,
    labelText,
    stateKey,
    minimum,
    maximum
)

    local holder =
        createInstance(
            "Frame",
            {

                Size =
                    UDim2.new(
                        1,
                        -10,
                        0,
                        40
                    ),

                BackgroundTransparency = 1,
            },
            parent
        )

    createText(
        holder,
        labelText,
        UDim2.new(
            0.52,
            0,
            1,
            0
        ),
        UDim2.fromOffset(
            4,
            0
        ),
        11
    )

    local box =
        createInstance(
            "TextBox",
            {

                Size =
                    UDim2.new(
                        0.40,
                        0,
                        0,
                        30
                    ),

                Position =
                    UDim2.new(
                        0.58,
                        0,
                        0,
                        5
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        30,
                        22,
                        40
                    ),

                BorderSizePixel = 0,

                Text =
                    tostring(
                        State[stateKey]
                    ),

                TextColor3 =
                    Color3.fromRGB(
                        255,
                        255,
                        255
                    ),

                TextSize = 12,

                Font =
                    Enum.Font.Gotham,

                ClearTextOnFocus = false,
            },
            holder
        )

    createCorner(box, 6)

    box.FocusLost:Connect(
        function()

            local value =
                tonumber(box.Text)

            if value then

                State[stateKey] =
                    math.clamp(
                        value,
                        minimum,
                        maximum
                    )

                NavigationController:Reset()

            end

            box.Text =
                tostring(
                    State[stateKey]
                )
        end
    )

    return box
end

local function createPriorityInput(
    parent,
    labelText,
    priorityKey
)

    local holder =
        createInstance(
            "Frame",
            {

                Size =
                    UDim2.new(
                        1,
                        -10,
                        0,
                        36
                    ),

                BackgroundTransparency = 1,
            },
            parent
        )

    createText(
        holder,
        labelText,
        UDim2.new(
            0.62,
            0,
            1,
            0
        ),
        UDim2.fromOffset(
            4,
            0
        ),
        10
    )

    local box =
        createInstance(
            "TextBox",
            {

                Size =
                    UDim2.new(
                        0.30,
                        0,
                        0,
                        28
                    ),

                Position =
                    UDim2.new(
                        0.68,
                        0,
                        0,
                        4
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        30,
                        22,
                        40
                    ),

                BorderSizePixel = 0,

                Text =
                    tostring(
                        State.Priority[priorityKey]
                    ),

                TextColor3 =
                    Color3.fromRGB(
                        255,
                        255,
                        255
                    ),

                TextSize = 11,

                Font =
                    Enum.Font.Gotham,

                ClearTextOnFocus = false,
            },
            holder
        )

    createCorner(box, 6)

    box.FocusLost:Connect(
        function()

            local value =
                tonumber(box.Text)

            if value then

                State.Priority[priorityKey] =
                    math.clamp(
                        value,
                        0,
                        999
                    )

                NavigationController:Reset()
            end

            box.Text =
                tostring(
                    State.Priority[priorityKey]
                )
        end
    )

    return box
end

local function createToggle(
    parent,
    labelText,
    stateKey
)

    local button =
        createInstance(
            "TextButton",
            {

                Size =
                    UDim2.new(
                        1,
                        -10,
                        0,
                        36
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        38,
                        26,
                        52
                    ),

                BorderSizePixel = 0,

                Text = "",

                AutoButtonColor = false,
            },
            parent
        )

    createCorner(button, 7)

    local indicator =
        createInstance(
            "Frame",
            {

                Size =
                    UDim2.fromOffset(
                        14,
                        14
                    ),

                Position =
                    UDim2.new(
                        1,
                        -25,
                        0.5,
                        -7
                    ),

                BorderSizePixel = 0,

                BackgroundColor3 =
                    Color3.fromRGB(
                        85,
                        65,
                        100
                    ),
            },
            button
        )

    createCorner(
        indicator,
        7
    )

    local label =
        createText(
            button,
            labelText,
            UDim2.new(
                1,
                -45,
                1,
                0
            ),
            UDim2.fromOffset(
                10,
                0
            ),
            11
        )

    UI.ToggleObjects[stateKey] = {
        Button = button,
        Indicator = indicator,
        Label = label,
    }

    local function refresh()

        local enabled =
            State[stateKey]

        if enabled then

            indicator.BackgroundColor3 =
                Color3.fromRGB(
                    180,
                    70,
                    255
                )

            button.BackgroundColor3 =
                Color3.fromRGB(
                    55,
                    30,
                    75
                )

        else

            indicator.BackgroundColor3 =
                Color3.fromRGB(
                    85,
                    65,
                    100
                )

            button.BackgroundColor3 =
                Color3.fromRGB(
                    38,
                    26,
                    52
                )
        end
    end

    button.Activated:Connect(
        function()

            State[stateKey] =
                not State[stateKey]

            refresh()

            if stateKey == "NavigationEnabled"
                or stateKey == "SmartRepath"
                or stateKey == "ObstacleDetection"
                or stateKey == "JumpAssist"
                or stateKey == "StuckRecovery"
                or stateKey == "SideRecovery"
                or stateKey == "RememberPaths"
                or stateKey == "RememberObstacles" then

                NavigationController:Reset()
            end
        end
    )

    refresh()

    return button
end

----------------------------------------------------------------
-- BUILD UI
----------------------------------------------------------------

function UI:Build()

    local playerGui =
        LocalPlayer:WaitForChild(
            "PlayerGui"
        )

    local gui =
        createInstance(
            "ScreenGui",
            {

                Name =
                    "IMDEHubV82",

                ResetOnSpawn = false,

                ZIndexBehavior =
                    Enum.ZIndexBehavior.Sibling,
            },
            playerGui
        )

    self.Gui = gui

    ------------------------------------------------------------
    -- MAIN
    ------------------------------------------------------------

    local main =
        createInstance(
            "Frame",
            {

                Name = "Main",

                Size =
                    UDim2.fromOffset(
                        450,
                        650
                    ),

                Position =
                    UDim2.new(
                        0.5,
                        -225,
                        0.5,
                        -325
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        20,
                        13,
                        28
                    ),

                BorderSizePixel = 0,

                ClipsDescendants = true,
            },
            gui
        )

    createCorner(main, 12)

    createStroke(main, 1.5)

    self.Main = main

    ------------------------------------------------------------
    -- HEADER
    ------------------------------------------------------------

    local header =
        createInstance(
            "Frame",
            {

                Size =
                    UDim2.new(
                        1,
                        0,
                        0,
                        70
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        32,
                        18,
                        44
                    ),

                BorderSizePixel = 0,
            },
            main
        )

    local title =
        createText(
            header,
            "IMDE HUB V8.2",
            UDim2.new(
                1,
                -110,
                0,
                30
            ),
            UDim2.fromOffset(
                16,
                7
            ),
            20
        )

    title.Font =
        Enum.Font.GothamBlack

    title.TextColor3 =
        Color3.fromRGB(
            215,
            120,
            255
        )

    local subtitle =
        createText(
            header,
            "ADVANCED ESP • SMART NAVIGATION",
            UDim2.new(
                1,
                -110,
                0,
                20
            ),
            UDim2.fromOffset(
                17,
                38
            ),
            9
        )

    subtitle.TextColor3 =
        Color3.fromRGB(
            175,
            155,
            190
        )

    ------------------------------------------------------------
    -- MINIMIZE
    ------------------------------------------------------------

    local minimize =
        createInstance(
            "TextButton",
            {

                Size =
                    UDim2.fromOffset(
                        35,
                        30
                    ),

                Position =
                    UDim2.new(
                        1,
                        -78,
                        0,
                        12
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        60,
                        35,
                        75
                    ),

                BorderSizePixel = 0,

                Text = "—",

                TextColor3 =
                    Color3.new(
                        1,
                        1,
                        1
                    ),

                TextSize = 16,

                Font =
                    Enum.Font.GothamBold,
            },
            header
        )

    createCorner(minimize, 7)

    ------------------------------------------------------------
    -- EXIT
    ------------------------------------------------------------

    local exit =
        createInstance(
            "TextButton",
            {

                Size =
                    UDim2.fromOffset(
                        35,
                        30
                    ),

                Position =
                    UDim2.new(
                        1,
                        -38,
                        0,
                        12
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        95,
                        35,
                        55
                    ),

                BorderSizePixel = 0,

                Text = "×",

                TextColor3 =
                    Color3.new(
                        1,
                        1,
                        1
                    ),

                TextSize = 17,

                Font =
                    Enum.Font.GothamBold,
            },
            header
        )

    createCorner(exit, 7)

    ------------------------------------------------------------
    -- STATUS
    ------------------------------------------------------------

    local status =
        createText(
            main,
            "Ready",
            UDim2.new(
                1,
                -20,
                0,
                30
            ),
            UDim2.fromOffset(
                10,
                74
            ),
            10
        )

    status.TextColor3 =
        Color3.fromRGB(
            180,
            150,
            200
        )

    self.Status = status

    ------------------------------------------------------------
    -- CONTENT
    ------------------------------------------------------------

    local content =
        createInstance(
            "ScrollingFrame",
            {

                Name = "Content",

                Size =
                    UDim2.new(
                        1,
                        -10,
                        1,
                        -112
                    ),

                Position =
                    UDim2.fromOffset(
                        5,
                        105
                    ),

                BackgroundTransparency = 1,

                BorderSizePixel = 0,

                ScrollBarThickness = 4,

                CanvasSize =
                    UDim2.new(
                        0,
                        0,
                        0,
                        0
                    ),

                AutomaticCanvasSize =
                    Enum.AutomaticSize.Y,
            },
            main
        )

    self.Content = content

    local layout =
        createInstance(
            "UIListLayout",
            {

                Padding =
                    UDim.new(
                        0,
                        7
                    ),

                HorizontalAlignment =
                    Enum.HorizontalAlignment.Center,
            },
            content
        )

    createInstance(
        "UIPadding",
        {

            PaddingLeft =
                UDim.new(
                    0,
                    3
                ),

            PaddingRight =
                UDim.new(
                    0,
                    3
                ),

            PaddingBottom =
                UDim.new(
                    0,
                    10
                ),
        },
        content
    )

    ------------------------------------------------------------
    -- MOVEMENT
    ------------------------------------------------------------

    createSection(
        content,
        "MOVEMENT"
    )

    createInput(
        content,
        "Walk Speed",
        "WalkSpeed",
        CONFIG.MinWalkSpeed,
        CONFIG.MaxWalkSpeed
    )

    createInput(
        content,
        "Jump Power",
        "JumpPower",
        CONFIG.MinJumpPower,
        CONFIG.MaxJumpPower
    )

    createToggle(
        content,
        "Navigation Enabled",
        "NavigationEnabled"
    )

    createToggle(
        content,
        "Smart Repath",
        "SmartRepath"
    )

    createToggle(
        content,
        "Obstacle Detection",
        "ObstacleDetection"
    )

    createToggle(
        content,
        "Jump Assist",
        "JumpAssist"
    )

    createToggle(
        content,
        "Stuck Recovery",
        "StuckRecovery"
    )

    createToggle(
        content,
        "Side Recovery",
        "SideRecovery"
    )

    ------------------------------------------------------------
    -- RANGE
    ------------------------------------------------------------

    createSection(
        content,
        "RANGES"
    )

    createInput(
        content,
        "Chase Range",
        "ChaseDistance",
        0,
        CONFIG.MaxChaseDistance
    )

    createInput(
        content,
        "Avoid Range",
        "AvoidDistance",
        0,
        CONFIG.MaxAvoidDistance
    )

    createInput(
        content,
        "Collect Range",
        "CollectDistance",
        0,
        CONFIG.MaxCollectDistance
    )

    ------------------------------------------------------------
    -- AUTOMATION
    ------------------------------------------------------------

    createSection(
        content,
        "AUTOMATION"
    )

    createToggle(
        content,
        "Auto Collect",
        "AutoCollect"
    )

    createToggle(
        content,
        "Chase Players",
        "ChaseEnabled"
    )

    createToggle(
        content,
        "Avoid Players",
        "AvoidEnabled"
    )

    ------------------------------------------------------------
    -- ESP
    ------------------------------------------------------------

    createSection(
        content,
        "ADVANCED ESP"
    )

    createToggle(
        content,
        "ESP Enabled",
        "ESPEnabled"
    )

    createToggle(
        content,
        "Display Name",
        "ESPShowName"
    )

    createToggle(
        content,
        "Username",
        "ESPShowUsername"
    )

    createToggle(
        content,
        "Role",
        "ESPShowRole"
    )

    createToggle(
        content,
        "Distance",
        "ESPShowDistance"
    )

    createToggle(
        content,
        "Health / HP Bar",
        "ESPShowHealth"
    )

    createToggle(
        content,
        "Selected Indicator",
        "ESPShowSelected"
    )

    createInput(
        content,
        "ESP Max Distance",
        "ESPMaxDistance",
        50,
        3000
    )

    ------------------------------------------------------------
    -- MAP
    ------------------------------------------------------------

    createSection(
        content,
        "MAP & MEMORY"
    )

    createToggle(
        content,
        "Automatic Map Scan",
        "AutoMapScan"
    )

    createToggle(
        content,
        "Remember Paths",
        "RememberPaths"
    )

    createToggle(
        content,
        "Remember Obstacles",
        "RememberObstacles"
    )

    local scanButton =
        createButton(
            content,
            "SCAN MAP NOW",
            34
        )

    scanButton.Activated:Connect(
        function()

            MapScanner:BeginScan()

            State.StatusText =
                "Map scan started"
        end
    )

    local clearPaths =
        createButton(
            content,
            "CLEAR PATH MEMORY",
            34
        )

    clearPaths.Activated:Connect(
        function()

            NavigationMemory:ClearPaths()

            NavigationController:Reset()

            State.StatusText =
                "Path memory cleared"
        end
    )

    local clearObstacles =
        createButton(
            content,
            "CLEAR OBSTACLE MEMORY",
            34
        )

    clearObstacles.Activated:Connect(
        function()

            NavigationMemory:ClearObstacles()

            State.StatusText =
                "Obstacle memory cleared"
        end
    )

    ------------------------------------------------------------
    -- PRIORITY
    ------------------------------------------------------------

    createSection(
        content,
        "BEHAVIOR PRIORITY"
    )

    createPriorityInput(
        content,
        "Avoid Murderer",
        "AvoidMurderer"
    )

    createPriorityInput(
        content,
        "Avoid Sheriff",
        "AvoidSheriff"
    )

    createPriorityInput(
        content,
        "Avoid Innocent",
        "AvoidInnocent"
    )

    createPriorityInput(
        content,
        "Selected Player",
        "SelectedPlayer"
    )

    createPriorityInput(
        content,
        "Chase Murderer",
        "ChaseMurderer"
    )

    createPriorityInput(
        content,
        "Chase Sheriff",
        "ChaseSheriff"
    )

    createPriorityInput(
        content,
        "Chase Innocent",
        "ChaseInnocent"
    )

    createPriorityInput(
        content,
        "Auto Collect",
        "AutoCollect"
    )

    local resetPriority =
        createButton(
            content,
            "RESET PRIORITIES",
            34
        )

    resetPriority.Activated:Connect(
        function()

            State.Priority = {

                AvoidMurderer = 100,
                AvoidSheriff = 95,
                AvoidInnocent = 90,

                SelectedPlayer = 80,

                ChaseMurderer = 70,
                ChaseSheriff = 65,
                ChaseInnocent = 60,

                AutoCollect = 50,
            }

            NavigationController:Reset()

            State.StatusText =
                "Priorities reset"
        end
    )

    ------------------------------------------------------------
    -- PLAYER SELECTOR
    ------------------------------------------------------------

    createSection(
        content,
        "PLAYER SELECTOR"
    )

    local selectorInfo =
        createText(
            content,
            "Tap a player to select. Tap again to deselect.",
            UDim2.new(
                1,
                -10,
                0,
                28
            ),
            UDim2.fromOffset(
                4,
                0
            ),
            10
        )

    selectorInfo.TextColor3 =
        Color3.fromRGB(
            160,
            145,
            175
        )

    local playerList =
        createInstance(
            "Frame",
            {

                Size =
                    UDim2.new(
                        1,
                        -10,
                        0,
                        150
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        28,
                        18,
                        38
                    ),

                BorderSizePixel = 0,
            },
            content
        )

    createCorner(
        playerList,
        8
    )

    self.PlayerList =
        playerList

    local playerLayout =
        createInstance(
            "UIListLayout",
            {

                Padding =
                    UDim.new(
                        0,
                        4
                    ),

                HorizontalAlignment =
                    Enum.HorizontalAlignment.Center,
            },
            playerList
        )

    createInstance(
        "UIPadding",
        {

            PaddingTop =
                UDim.new(
                    0,
                    5
                ),

            PaddingLeft =
                UDim.new(
                    0,
                    5
                ),

            PaddingRight =
                UDim.new(
                    0,
                    5
                ),
        },
        playerList
    )

    ------------------------------------------------------------
    -- CONFIG
    ------------------------------------------------------------

    createSection(
        content,
        "CONFIGURATION"
    )

    local save =
        createButton(
            content,
            "SAVE CONFIG",
            34
        )

    save.Activated:Connect(
        function()
            ConfigManager:Save()
        end
    )

    local load =
        createButton(
            content,
            "LOAD CONFIG",
            34
        )

    load.Activated:Connect(
        function()
            ConfigManager:Load()
        end
    )

    local reset =
        createButton(
            content,
            "RESET CONFIG",
            34
        )

    reset.Activated:Connect(
        function()
            ConfigManager:Reset()
        end
    )

    ------------------------------------------------------------
    -- COMMUNITY
    ------------------------------------------------------------

    createSection(
        content,
        "COMMUNITY"
    )

    local discord =
        createButton(
            content,
            "DISCORD • discord.gg/kM8nGKswcH",
            38
        )

    discord.Activated:Connect(
        function()

            State.StatusText =
                "Discord: discord.gg/kM8nGKswcH"
        end
    )

    ------------------------------------------------------------
    -- PLAYER LIST REFRESH
    ------------------------------------------------------------

    function self:RefreshPlayers()

        for _, connection in pairs(
            self.PlayerButtonConnections
        ) do

            pcall(function()
                connection:Disconnect()
            end)
        end

        table.clear(
            self.PlayerButtonConnections
        )

        for _, button in ipairs(
            self.PlayerButtons
        ) do

            pcall(function()
                button:Destroy()
            end)
        end

        table.clear(
            self.PlayerButtons
        )

        for _, player in ipairs(
            Players:GetPlayers()
        ) do

            if player ~= LocalPlayer then

                local button =
                    createInstance(
                        "TextButton",
                        {

                            Size =
                                UDim2.new(
                                    1,
                                    -10,
                                    0,
                                    30
                                ),

                            BackgroundColor3 =
                                Color3.fromRGB(
                                    40,
                                    25,
                                    52
                                ),

                            BorderSizePixel = 0,

                            Text =
                                player.DisplayName
                                .. "  @"
                                .. player.Name,

                            TextColor3 =
                                Color3.fromRGB(
                                    235,
                                    225,
                                    245
                                ),

                            TextSize = 10,

                            Font =
                                Enum.Font.GothamMedium,
                        },
                        self.PlayerList
                    )

                createCorner(
                    button,
                    6
                )

                table.insert(
                    self.PlayerButtons,
                    button
                )

                local connection =
                    button.Activated:Connect(
                        function()

                            if State.SelectedPlayer
                                == player then

                                State.SelectedPlayer =
                                    nil

                                State.StatusText =
                                    "Player deselected"

                            else

                                State.SelectedPlayer =
                                    player

                                State.StatusText =
                                    "Selected: "
                                    .. player.DisplayName
                            end

                            NavigationController:Reset()

                            self:RefreshPlayers()
                        end
                    )

                table.insert(
                    self.PlayerButtonConnections,
                    connection
                )

                if State.SelectedPlayer
                    == player then

                    button.BackgroundColor3 =
                        Color3.fromRGB(
                            90,
                            40,
                            120
                        )
                end
            end
        end
    end

    self:RefreshPlayers()

    ------------------------------------------------------------
    -- MINIMIZED BUTTON
    ------------------------------------------------------------

    local miniButton =
        createInstance(
            "TextButton",
            {

                Name =
                    "MinimizedButton",

                Size =
                    UDim2.fromOffset(
                        58,
                        58
                    ),

                Position =
                    UDim2.new(
                        0,
                        20,
                        0.5,
                        -29
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        95,
                        40,
                        130
                    ),

                BorderSizePixel = 0,

                Text = "IMDE",

                TextColor3 =
                    Color3.new(
                        1,
                        1,
                        1
                    ),

                TextSize = 12,

                Font =
                    Enum.Font.GothamBlack,

                Visible = false,
            },
            gui
        )

    createCorner(
        miniButton,
        15
    )

    createStroke(
        miniButton,
        1.5
    )

    self.MinimizedButton =
        miniButton

    ------------------------------------------------------------
    -- MINIMIZE BEHAVIOR
    ------------------------------------------------------------

    minimize.Activated:Connect(
        function()

            main.Visible = false
            miniButton.Visible = true
        end
    )

    miniButton.Activated:Connect(
        function()

            main.Visible = true
            miniButton.Visible = false
        end
    )

    ------------------------------------------------------------
    -- EXIT
    ------------------------------------------------------------

    exit.Activated:Connect(
        function()

            self:Destroy()
        end
    )

    ------------------------------------------------------------
    -- DRAG
    ------------------------------------------------------------

    local dragging = false
    local dragStart
    local startPosition

    header.InputBegan:Connect(
        function(input)

            if input.UserInputType
                == Enum.UserInputType.MouseButton1
                or input.UserInputType
                == Enum.UserInputType.Touch then

                dragging = true

                dragStart =
                    input.Position

                startPosition =
                    main.Position
            end
        end
    )

    header.InputEnded:Connect(
        function(input)

            if input.UserInputType
                == Enum.UserInputType.MouseButton1
                or input.UserInputType
                == Enum.UserInputType.Touch then

                dragging = false
            end
        end
    )

    UserInputService.InputChanged:Connect(
        function(input)

            if not dragging then
                return
            end

            if input.UserInputType
                ~= Enum.UserInputType.MouseMovement
                and input.UserInputType
                ~= Enum.UserInputType.Touch then

                return
            end

            local delta =
                input.Position
                - dragStart

            main.Position =
                UDim2.new(
                    startPosition.X.Scale,
                    startPosition.X.Offset
                        + delta.X,

                    startPosition.Y.Scale,
                    startPosition.Y.Offset
                        + delta.Y
                )
        end
    )

    ------------------------------------------------------------
    -- RESIZE HANDLE
    ------------------------------------------------------------

    local resize =
        createInstance(
            "TextButton",
            {

                Size =
                    UDim2.fromOffset(
                        22,
                        22
                    ),

                Position =
                    UDim2.new(
                        1,
                        -22,
                        1,
                        -22
                    ),

                BackgroundTransparency = 1,

                Text = "◢",

                TextColor3 =
                    Color3.fromRGB(
                        170,
                        120,
                        200
                    ),

                TextSize = 14,

                Font =
                    Enum.Font.GothamBold,

                AutoButtonColor = false,
            },
            main
        )

    local resizing = false
    local resizeStart
    local originalSize

    resize.InputBegan:Connect(
        function(input)

            if input.UserInputType
                == Enum.UserInputType.MouseButton1
                or input.UserInputType
                == Enum.UserInputType.Touch then

                resizing = true

                resizeStart =
                    input.Position

                originalSize =
                    main.Size
            end
        end
    )

    resize.InputEnded:Connect(
        function(input)

            if input.UserInputType
                == Enum.UserInputType.MouseButton1
                or input.UserInputType
                == Enum.UserInputType.Touch then

                resizing = false
            end
        end
    )

    UserInputService.InputChanged:Connect(
        function(input)

            if not resizing then
                return
            end

            if input.UserInputType
                ~= Enum.UserInputType.MouseMovement
                and input.UserInputType
                ~= Enum.UserInputType.Touch then

                return
            end

            local delta =
                input.Position
                - resizeStart

            local width =
                math.clamp(
                    originalSize.X.Offset
                        + delta.X,
                    350,
                    700
                )

            local height =
                math.clamp(
                    originalSize.Y.Offset
                        + delta.Y,
                    450,
                    850
                )

            main.Size =
                UDim2.fromOffset(
                    width,
                    height
                )
        end
    )
end

function UI:Update()

    if not self.Status then
        return
    end

    local behavior =
        State.CurrentBehavior

    local target =
        State.CurrentTargetName

    self.Status.Text =
        string.format(
            "%s  |  Target: %s  |  %s",
            behavior,
            target,
            State.StatusText
        )
end

function UI:Destroy()

    if self.Gui then

        pcall(function()
            self.Gui:Destroy()
        end)
    end

    self.Gui = nil
end

----------------------------------------------------------------
-- CHARACTER EVENTS
----------------------------------------------------------------

connect(
    LocalPlayer.CharacterAdded,
    function()

        CharacterState.Character = nil
        CharacterState.Humanoid = nil
        CharacterState.Root = nil

        NavigationController:Reset()

        task.wait(0.15)

        CharacterManager:Refresh()
        CharacterManager:ApplyMovement()
    end
)

----------------------------------------------------------------
-- MAIN ENGINE
----------------------------------------------------------------

local movementAccumulator = 0
local espAccumulator = 0
local uiAccumulator = 0
local memoryAccumulator = 0
local mapAccumulator = 0
local playerRefreshAccumulator = 0

UI:Build()

connect(
    RunService.Heartbeat,
    function(deltaTime)

        if not State.Running then
            return
        end

        --------------------------------------------------------
        -- CHARACTER
        --------------------------------------------------------

        local changed =
            CharacterManager:Refresh()

        CharacterManager:ApplyMovement()

        if changed then
            NavigationController:Reset()
        end

        --------------------------------------------------------
        -- MOVEMENT
        --------------------------------------------------------

        movementAccumulator += deltaTime

        if movementAccumulator
            >= CONFIG.MovementUpdateRate then

            movementAccumulator = 0

            if State.NavigationEnabled then

                local candidates =
                    BehaviorManager:GetCandidates()

                local selected =
                    BehaviorManager:Choose(
                        candidates
                    )

                NavigationController:Step(
                    selected
                )

            else

                NavigationController:Reset()

                State.CurrentBehavior =
                    "Navigation Off"

                State.CurrentTargetName =
                    "None"
            end
        end

        --------------------------------------------------------
        -- ESP
        --------------------------------------------------------

        espAccumulator += deltaTime

        if espAccumulator
            >= CONFIG.ESPUpdateRate then

            espAccumulator = 0

            ESPManager:RefreshAll()
        end

        --------------------------------------------------------
        -- MAP
        --------------------------------------------------------

        mapAccumulator += deltaTime

        if mapAccumulator
            >= 0.10 then

            mapAccumulator = 0

            MapScanner:Step()
        end

        --------------------------------------------------------
        -- MEMORY
        --------------------------------------------------------

        memoryAccumulator += deltaTime

        if memoryAccumulator
            >= CONFIG.MemoryPruneRate then

            memoryAccumulator = 0

            NavigationMemory:Prune()
        end

        --------------------------------------------------------
        -- PLAYER LIST
        --------------------------------------------------------

        playerRefreshAccumulator += deltaTime

        if playerRefreshAccumulator
            >= 1 then

            playerRefreshAccumulator = 0

            if UI.Main then
                UI:RefreshPlayers()
            end
        end

        --------------------------------------------------------
        -- UI
        --------------------------------------------------------

        uiAccumulator += deltaTime

        if uiAccumulator
            >= CONFIG.UIUpdateRate then

            uiAccumulator = 0

            UI:Update()
        end
    end
)

----------------------------------------------------------------
-- STARTUP
----------------------------------------------------------------

CharacterManager:Refresh()
CharacterManager:ApplyMovement()

State.StatusText =
    "IMDE HUB V8.2 loaded"

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------

local function Cleanup()

    if not State.Running then
        return
    end

    State.Running = false

    ------------------------------------------------------------
    -- NAVIGATION
    ------------------------------------------------------------

    NavigationController:Reset()

    ------------------------------------------------------------
    -- CHARACTER
    ------------------------------------------------------------

    CharacterManager:Restore()

    ------------------------------------------------------------
    -- ESP
    ------------------------------------------------------------

    ESPManager:Clear()

    for player in pairs(
        PlayerConnections
    ) do

        disconnectPlayerConnections(
            player
        )
    end

    ------------------------------------------------------------
    -- CONNECTIONS
    ------------------------------------------------------------

    disconnectAll()

    ------------------------------------------------------------
    -- MEMORY
    ------------------------------------------------------------

    NavigationMemory:ClearPaths()
    NavigationMemory:ClearObstacles()

    CollectionManager.Items = {}
    CollectionManager.LockedTarget = nil

    MapScanner:Clear()

    ------------------------------------------------------------
    -- UI
    ------------------------------------------------------------

    UI:Destroy()
end

UI.Cleanup = Cleanup

----------------------------------------------------------------
-- END
----------------------------------------------------------------
