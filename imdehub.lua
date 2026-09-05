--[[
========================================================
                    IMDE HUB
           PREMIUM STUDIO EDITION V4
========================================================

FOR YOUR OWN ROBLOX STUDIO EXPERIENCE

FEATURES
• Auto Item Collect
• Auto Avoid
• Auto Chase
• Chase All
• Unlimited Chase
• Unlimited Avoid
• Inventory Weapon ESP
• Player Distance / Status
• Scrollable Player Selector
• WalkSpeed
• JumpPower
• Non-blocking Pathfinding
• Respawn Support
• Draggable UI
• Minimizable UI
• Mobile Friendly

ESP
🔴 Knife
🔵 Gun
🟢 No Weapon

ITEM FOLDER
Workspace.SpawnedItems

========================================================
]]

--========================================================
-- SERVICES
--========================================================

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

--========================================================
-- SETTINGS
--========================================================

local Settings = {
	AutoCollect = false,
	AutoAvoid = false,
	AutoChase = false,
	ChaseAll = false,

	SelectedPlayer = nil,

	WalkSpeed = 16,
	JumpPower = 50,

	CollectRadius = 150,
	AvoidDistance = 25,
	ChaseDistance = 250,

	UnlimitedChase = false,
	UnlimitedAvoid = false,

	ESP = false,
	PlayerInfo = true,

	RepathInterval = 0.18,

	CurrentCharacter = nil,
	CurrentHumanoid = nil,
	CurrentRoot = nil,
}

--========================================================
-- CHARACTER CACHE
--========================================================

local function updateCharacter(character)
	Settings.CurrentCharacter = character

	if character then
		Settings.CurrentHumanoid =
			character:FindFirstChildOfClass("Humanoid")

		Settings.CurrentRoot =
			character:FindFirstChild("HumanoidRootPart")
	else
		Settings.CurrentHumanoid = nil
		Settings.CurrentRoot = nil
	end
end

local function getCharacter()
	local character = LocalPlayer.Character

	if character ~= Settings.CurrentCharacter then
		updateCharacter(character)
	end

	return Settings.CurrentCharacter
end

local function getHumanoid()
	getCharacter()

	if Settings.CurrentHumanoid
		and Settings.CurrentHumanoid.Parent then
		return Settings.CurrentHumanoid
	end

	local character = getCharacter()

	if character then
		Settings.CurrentHumanoid =
			character:FindFirstChildOfClass("Humanoid")
	end

	return Settings.CurrentHumanoid
end

local function getRoot()
	getCharacter()

	if Settings.CurrentRoot
		and Settings.CurrentRoot.Parent then
		return Settings.CurrentRoot
	end

	local character = getCharacter()

	if character then
		Settings.CurrentRoot =
			character:FindFirstChild("HumanoidRootPart")
	end

	return Settings.CurrentRoot
end

local function applyMovementSettings()
	local humanoid = getHumanoid()

	if not humanoid then
		return
	end

	humanoid.WalkSpeed = Settings.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Settings.JumpPower
end

--========================================================
-- RESPAWN
--========================================================

LocalPlayer.CharacterAdded:Connect(function(character)
	updateCharacter(character)

	task.wait(0.5)

	applyMovementSettings()
end)

if LocalPlayer.Character then
	updateCharacter(LocalPlayer.Character)
	applyMovementSettings()
end

--========================================================
-- CHARACTER VALIDATION
--========================================================

local function validCharacter(player)
	if not player then
		return false
	end

	local character = player.Character

	if not character then
		return false
	end

	local humanoid =
		character:FindFirstChildOfClass("Humanoid")

	local root =
		character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root then
		return false
	end

	return humanoid.Health > 0
end

--========================================================
-- PATH STATE
--========================================================

local PathState = {
	Destination = nil,
	Waypoints = {},
	Index = 1,
	LastCompute = 0,
	Target = nil,
}

local PATH_RECOMPUTE_TIME = 0.45
local WAYPOINT_DISTANCE = 4

local function clearPath()
	PathState.Destination = nil
	PathState.Waypoints = {}
	PathState.Index = 1
	PathState.LastCompute = 0
	PathState.Target = nil
end

local function computePath(destination, target)
	local root = getRoot()

	if not root then
		return false
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentCanClimb = true,
		WaypointSpacing = 4,
	})

	local success = pcall(function()
		path:ComputeAsync(
			root.Position,
			destination
		)
	end)

	if not success
		or path.Status ~= Enum.PathStatus.Success then
		return false
	end

	local waypoints = path:GetWaypoints()

	if #waypoints == 0 then
		return false
	end

	PathState.Destination = destination
	PathState.Waypoints = waypoints
	PathState.Index = 1
	PathState.LastCompute = os.clock()
	PathState.Target = target

	return true
end

--========================================================
-- NON-BLOCKING MOVEMENT
--========================================================

local function moveTowards(destination, target)
	local humanoid = getHumanoid()
	local root = getRoot()

	if not humanoid or not root then
		return
	end

	local shouldRepath = false

	if not PathState.Destination then
		shouldRepath = true

	elseif not PathState.Waypoints[PathState.Index] then
		shouldRepath = true

	elseif os.clock() - PathState.LastCompute
		>= PATH_RECOMPUTE_TIME then

		if
			(PathState.Destination - destination).Magnitude
			> 6
		then
			shouldRepath = true
		end

		if target ~= PathState.Target then
			shouldRepath = true
		end
	end

	if shouldRepath then
		local success =
			computePath(destination, target)

		if not success then
			humanoid:MoveTo(destination)
			return
		end
	end

	local waypoint =
		PathState.Waypoints[PathState.Index]

	if not waypoint then
		humanoid:MoveTo(destination)
		return
	end

	if waypoint.Action ==
		Enum.PathWaypointAction.Jump then

		humanoid.Jump = true
	end

	humanoid:MoveTo(waypoint.Position)

	if
		(root.Position - waypoint.Position).Magnitude
		<= WAYPOINT_DISTANCE
	then

		PathState.Index += 1

		if not PathState.Waypoints[PathState.Index] then
			clearPath()
		end
	end
end

--========================================================
-- SPAWNED ITEMS
--========================================================

local CurrentItemTarget = nil

local function getSpawnedItemsFolder()
	return workspace:FindFirstChild("SpawnedItems")
end

local function getItemPosition(object)
	if not object then
		return nil
	end

	if object:IsA("BasePart") then
		return object.Position
	end

	if object:IsA("Model") then
		local success, pivot = pcall(function()
			return object:GetPivot()
		end)

		if success and pivot then
			return pivot.Position
		end
	end

	return nil
end

local function isValidItem(object)
	if not object then
		return false
	end

	if object:IsA("BasePart") then
		return true
	end

	if object:IsA("Model") then
		return true
	end

	return false
end

local function findNearestFloatingItem()
	local root = getRoot()

	if not root then
		return nil
	end

	local folder = getSpawnedItemsFolder()

	if not folder then
		return nil
	end

	local nearest = nil
	local nearestDistance = math.huge

	for _, object in ipairs(folder:GetChildren()) do
		if isValidItem(object) then

			local position =
				getItemPosition(object)

			if position then
				local distance =
					(root.Position - position).Magnitude

				if
					distance <= Settings.CollectRadius
					and distance < nearestDistance
				then

					nearest = object
					nearestDistance = distance
				end
			end
		end
	end

	return nearest
end

--========================================================
-- AUTO COLLECT
--========================================================

local function autoCollect()
	if not Settings.AutoCollect then
		return
	end

	local root = getRoot()

	if not root then
		return
	end

	if
		CurrentItemTarget
		and CurrentItemTarget.Parent
	then

		local position =
			getItemPosition(CurrentItemTarget)

		if position then

			local distance =
				(root.Position - position).Magnitude

			if distance <= 6 then
				CurrentItemTarget = nil
				clearPath()
				return
			end

			moveTowards(
				position,
				CurrentItemTarget
			)

			return
		end
	end

	CurrentItemTarget =
		findNearestFloatingItem()

	if CurrentItemTarget then
		local position =
			getItemPosition(CurrentItemTarget)

		if position then
			moveTowards(
				position,
				CurrentItemTarget
			)
		end
	end
end

--========================================================
-- PLAYER FUNCTIONS
--========================================================

local function getPlayers()
	local result = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer
			and validCharacter(player)
		then
			table.insert(result, player)
		end
	end

	return result
end

local function getNearestPlayer()
	local root = getRoot()

	if not root then
		return nil
	end

	local nearest = nil
	local nearestDistance = math.huge

	for _, player in ipairs(getPlayers()) do

		local targetRoot =
			player.Character
			and player.Character:FindFirstChild(
				"HumanoidRootPart"
			)

		if targetRoot then

			local distance =
				(root.Position - targetRoot.Position).Magnitude

			if distance < nearestDistance then
				nearest = player
				nearestDistance = distance
			end
		end
	end

	return nearest
end

--========================================================
-- AUTO CHASE
--========================================================

local function getChaseDistance()
	if Settings.UnlimitedChase then
		return math.huge
	end

	return Settings.ChaseDistance
end

local function chasePlayer(player)
	if not Settings.AutoChase then
		return
	end

	if not validCharacter(player) then
		return
	end

	local root = getRoot()

	local targetRoot =
		player.Character
		and player.Character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not root or not targetRoot then
		return
	end

	local distance =
		(root.Position - targetRoot.Position).Magnitude

	if distance > getChaseDistance() then
		return
	end

	local direction =
		targetRoot.CFrame.LookVector

	local destination =
		targetRoot.Position - direction * 4

	moveTowards(
		destination,
		player
	)
end

local function autoChase()
	if not Settings.AutoChase then
		return
	end

	local target

	if Settings.ChaseAll then
		target = getNearestPlayer()
	else
		target = Settings.SelectedPlayer
	end

	if target then
		chasePlayer(target)
	else
		clearPath()
	end
end

--========================================================
-- AUTO AVOID
--========================================================

local function findDanger()
	local root = getRoot()

	if not root then
		return nil
	end

	local closest = nil
	local closestDistance = math.huge

	local maxDistance =
		Settings.UnlimitedAvoid
		and math.huge
		or Settings.AvoidDistance

	for _, player in ipairs(getPlayers()) do

		local targetRoot =
			player.Character
			and player.Character:FindFirstChild(
				"HumanoidRootPart"
			)

		if targetRoot then

			local distance =
				(root.Position - targetRoot.Position).Magnitude

			if
				distance <= maxDistance
				and distance < closestDistance
			then

				closest = player
				closestDistance = distance
			end
		end
	end

	return closest
end

local function autoAvoid()
	if not Settings.AutoAvoid then
		return
	end

	local root = getRoot()

	if not root then
		return
	end

	local danger = findDanger()

	if not danger then
		return
	end

	local targetRoot =
		danger.Character
		and danger.Character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not targetRoot then
		return
	end

	local away =
		root.Position - targetRoot.Position

	if away.Magnitude < 0.1 then
		away = Vector3.new(1, 0, 0)
	end

	away = away.Unit

	local distance =
		Settings.UnlimitedAvoid
		and 40
		or math.max(
			Settings.AvoidDistance,
			30
		)

	local destinations = {
		root.Position + away * distance,

		root.Position +
			(away + Vector3.new(1, 0, 0)).Unit
			* distance,

		root.Position +
			(away + Vector3.new(-1, 0, 0)).Unit
			* distance,

		root.Position +
			(away + Vector3.new(0, 0, 1)).Unit
			* distance,

		root.Position +
			(away + Vector3.new(0, 0, -1)).Unit
			* distance,
	}

	local bestDestination = destinations[1]
	local bestDistance = -math.huge

	for _, destination in ipairs(destinations) do

		local targetDistance =
			(destination - targetRoot.Position).Magnitude

		if targetDistance > bestDistance then
			bestDistance = targetDistance
			bestDestination = destination
		end
	end

	moveTowards(
		bestDestination,
		danger
	)
end

--========================================================
-- INVENTORY WEAPON DETECTOR
--========================================================

local function normalizeWeaponName(name)
	if not name then
		return nil
	end

	local lower =
		tostring(name):lower()

	if
		lower:find("knife")
		or lower:find("blade")
		or lower:find("dagger")
	then
		return "Knife"
	end

	if
		lower:find("gun")
		or lower:find("pistol")
		or lower:find("revolver")
		or lower:find("handgun")
	then
		return "Gun"
	end

	return nil
end

local function scanContainerForWeapon(container)
	if not container then
		return nil
	end

	for _, object in ipairs(container:GetChildren()) do

		if object:IsA("Tool") then

			local weapon =
				normalizeWeaponName(
					object.Name
				)

			if weapon then
				return weapon
			end
		end
	end

	for _, object in ipairs(container:GetDescendants()) do

		if object:IsA("Tool") then

			local weapon =
				normalizeWeaponName(
					object.Name
				)

			if weapon then
				return weapon
			end
		end
	end

	return nil
end

local function getInventoryWeapon(player)
	if not player then
		return nil
	end

	local backpack =
		player:FindFirstChildOfClass("Backpack")

	local character =
		player.Character

	local backpackWeapon =
		scanContainerForWeapon(backpack)

	local characterWeapon =
		scanContainerForWeapon(character)

	-- Knife priority
	if
		backpackWeapon == "Knife"
		or characterWeapon == "Knife"
	then
		return "Knife"
	end

	if
		backpackWeapon == "Gun"
		or characterWeapon == "Gun"
	then
		return "Gun"
	end

	return nil
end

--========================================================
-- ESP
--========================================================

local function getESPColor(player)
	local weapon =
		getInventoryWeapon(player)

	if weapon == "Knife" then
		return Color3.fromRGB(
			255,
			55,
			65
		)
	end

	if weapon == "Gun" then
		return Color3.fromRGB(
			60,
			140,
			255
		)
	end

	return Color3.fromRGB(
		70,
		255,
		120
	)
end

local function getESPStatus(player)
	local weapon =
		getInventoryWeapon(player)

	if weapon == "Knife" then
		return "🔪 Knife"
	end

	if weapon == "Gun" then
		return "🔫 Gun"
	end

	return "🟢 No Weapon"
end

local espObjects = {}

local function removeESP(player)
	local object =
		espObjects[player]

	if not object then
		return
	end

	if object.Highlight then
		object.Highlight:Destroy()
	end

	if object.Billboard then
		object.Billboard:Destroy()
	end

	espObjects[player] = nil
end

local function createESP(player)
	if player == LocalPlayer then
		return
	end

	if not validCharacter(player) then
		return
	end

	removeESP(player)

	local character =
		player.Character

	if not character then
		return
	end

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not root then
		return
	end

	local highlight =
		Instance.new("Highlight")

	highlight.Name =
		"IMDE_InventoryESP"

	highlight.DepthMode =
		Enum.HighlightDepthMode.AlwaysOnTop

	highlight.FillTransparency = 0.45
	highlight.OutlineTransparency = 0

	highlight.Parent = character

	local billboard =
		Instance.new("BillboardGui")

	billboard.Name =
		"IMDE_PlayerInfo"

	billboard.Adornee = root

	billboard.Size =
		UDim2.new(
			0,
			200,
			0,
			58
		)

	billboard.StudsOffset =
		Vector3.new(0, 3.5, 0)

	billboard.AlwaysOnTop = true
	billboard.ResetOnSpawn = false

	billboard.Parent = root

	local label =
		Instance.new("TextLabel")

	label.Name = "Info"

	label.Size =
		UDim2.fromScale(1, 1)

	label.BackgroundTransparency = 1

	label.TextSize = 13

	label.Font =
		Enum.Font.GothamBold

	label.TextStrokeTransparency = 0.2

	label.Parent = billboard

	espObjects[player] = {
		Highlight = highlight,
		Billboard = billboard,
		Label = label,
	}

	local color =
		getESPColor(player)

	highlight.FillColor = color
	highlight.OutlineColor = color

	label.TextColor3 = color
end

local function refreshESP()
	if not Settings.ESP then

		for player in pairs(espObjects) do
			removeESP(player)
		end

		return
	end

	for _, player in ipairs(Players:GetPlayers()) do

		if player ~= LocalPlayer then

			if validCharacter(player) then

				if not espObjects[player] then
					createESP(player)
				end

			else
				removeESP(player)
			end
		end
	end
end

local function updateESP()
	if not Settings.ESP then
		return
	end

	local localRoot = getRoot()

	if not localRoot then
		return
	end

	for player, objects in pairs(espObjects) do

		if not validCharacter(player) then
			removeESP(player)
			continue
		end

		local character =
			player.Character

		local root =
			character
			and character:FindFirstChild(
				"HumanoidRootPart"
			)

		if not root then
			removeESP(player)
			continue
		end

		local color =
			getESPColor(player)

		local status =
			getESPStatus(player)

		local distance =
			math.floor(
				(
					localRoot.Position
					- root.Position
				).Magnitude
			)

		if objects.Highlight then
			objects.Highlight.FillColor = color
			objects.Highlight.OutlineColor = color
		end

		if objects.Label then

			objects.Label.TextColor3 = color

			if Settings.PlayerInfo then

				objects.Label.Text =
					player.DisplayName
					.. "\n"
					.. status
					.. " • "
					.. distance
					.. " studs"

			else

				objects.Label.Text =
					status
			end
		end
	end
end

--========================================================
-- GUI
--========================================================

local ScreenGui =
	Instance.new("ScreenGui")

ScreenGui.Name =
	"IMDE_HUB_PREMIUM_V4"

ScreenGui.ResetOnSpawn = false

ScreenGui.ZIndexBehavior =
	Enum.ZIndexBehavior.Sibling

ScreenGui.Parent =
	LocalPlayer:WaitForChild("PlayerGui")

--========================================================
-- MAIN
--========================================================

local Main =
	Instance.new("Frame")

Main.Name = "Main"

Main.Size =
	UDim2.new(
		0,
		360,
		0,
		570
	)

Main.Position =
	UDim2.new(
		0.5,
		-180,
		0.5,
		-285
	)

Main.BackgroundColor3 =
	Color3.fromRGB(
		20,
		12,
		35
	)

Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Parent = ScreenGui

local MainCorner =
	Instance.new("UICorner")

MainCorner.CornerRadius =
	UDim.new(0, 14)

MainCorner.Parent = Main

local MainStroke =
	Instance.new("UIStroke")

MainStroke.Color =
	Color3.fromRGB(
		130,
		70,
		220
	)

MainStroke.Thickness = 1.5
MainStroke.Transparency = 0.15
MainStroke.Parent = Main

--========================================================
-- TOP BAR
--========================================================

local TopBar =
	Instance.new("Frame")

TopBar.Size =
	UDim2.new(
		1,
		0,
		0,
		65
	)

TopBar.BackgroundColor3 =
	Color3.fromRGB(
		30,
		17,
		52
	)

TopBar.BorderSizePixel = 0
TopBar.Parent = Main

local Title =
	Instance.new("TextLabel")

Title.BackgroundTransparency = 1

Title.Position =
	UDim2.new(
		0,
		18,
		0,
		7
	)

Title.Size =
	UDim2.new(
		1,
		-115,
		0,
		28
	)

Title.Text =
	"IMDE HUB"

Title.TextColor3 =
	Color3.fromRGB(
		220,
		180,
		255
	)

Title.Font =
	Enum.Font.GothamBold

Title.TextSize = 21

Title.TextXAlignment =
	Enum.TextXAlignment.Left

Title.Parent = TopBar

local Subtitle =
	Instance.new("TextLabel")

Subtitle.BackgroundTransparency = 1

Subtitle.Position =
	UDim2.new(
		0,
		19,
		0,
		35
	)

Subtitle.Size =
	UDim2.new(
		1,
		-115,
		0,
		18
	)

Subtitle.Text =
	"PREMIUM • STUDIO EDITION V4"

Subtitle.TextColor3 =
	Color3.fromRGB(
		160,
		130,
		190
	)

Subtitle.Font =
	Enum.Font.Gotham

Subtitle.TextSize = 10

Subtitle.TextXAlignment =
	Enum.TextXAlignment.Left

Subtitle.Parent = TopBar

--========================================================
-- MINIMIZE
--========================================================

local Minimize =
	Instance.new("TextButton")

Minimize.Size =
	UDim2.new(
		0,
		38,
		0,
		38
	)

Minimize.Position =
	UDim2.new(
		1,
		-48,
		0,
		13
	)

Minimize.BackgroundColor3 =
	Color3.fromRGB(
		70,
		35,
		105
	)

Minimize.Text = "−"

Minimize.TextColor3 =
	Color3.new(
		1,
		1,
		1
	)

Minimize.Font =
	Enum.Font.GothamBold

Minimize.TextSize = 24

Minimize.BorderSizePixel = 0
Minimize.Parent = TopBar

local MinCorner =
	Instance.new("UICorner")

MinCorner.CornerRadius =
	UDim.new(0, 9)

MinCorner.Parent = Minimize

--========================================================
-- CONTENT
--========================================================

local Content =
	Instance.new("ScrollingFrame")

Content.Name = "Content"

Content.Position =
	UDim2.new(
		0,
		8,
		0,
		72
	)

Content.Size =
	UDim2.new(
		1,
		-16,
		1,
		-80
	)

Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0

Content.ScrollBarThickness = 5

Content.ScrollingDirection =
	Enum.ScrollingDirection.Y

Content.AutomaticCanvasSize =
	Enum.AutomaticSize.Y

Content.CanvasSize =
	UDim2.new(
		0,
		0,
		0,
		0
	)

Content.Parent = Main

local Layout =
	Instance.new("UIListLayout")

Layout.Padding =
	UDim.new(0, 7)

Layout.HorizontalAlignment =
	Enum.HorizontalAlignment.Center

Layout.Parent = Content

--========================================================
-- UI HELPERS
--========================================================

local function createSection(text)
	local section =
		Instance.new("TextLabel")

	section.Size =
		UDim2.new(
			1,
			-12,
			0,
			28
		)

	section.BackgroundTransparency = 1

	section.Text =
		"  " .. text

	section.TextColor3 =
		Color3.fromRGB(
			185,
			135,
			245
		)

	section.Font =
		Enum.Font.GothamBold

	section.TextSize = 13

	section.TextXAlignment =
		Enum.TextXAlignment.Left

	section.Parent = Content

	return section
end

local function createButton(text)
	local button =
		Instance.new("TextButton")

	button.Size =
		UDim2.new(
			1,
			-12,
			0,
			40
		)

	button.BackgroundColor3 =
		Color3.fromRGB(
			38,
			23,
			58
		)

	button.BorderSizePixel = 0

	button.Text = text

	button.TextColor3 =
		Color3.fromRGB(
			225,
			215,
			235
		)

	button.Font =
		Enum.Font.GothamMedium

	button.TextSize = 13

	button.AutoButtonColor = false
	button.Parent = Content

	local corner =
		Instance.new("UICorner")

	corner.CornerRadius =
		UDim.new(0, 9)

	corner.Parent = button

	return button
end

local function updateButton(
	button,
	name,
	enabled
)
	button.Text =
		name
		.. " : "
		.. (
			enabled
			and "ON"
			or "OFF"
		)

	if enabled then

		button.BackgroundColor3 =
			Color3.fromRGB(
				92,
				42,
				140
			)

	else

		button.BackgroundColor3 =
			Color3.fromRGB(
				38,
				23,
				58
			)
	end
end

local function createInputRow(
	labelText,
	defaultValue
)
	local row =
		Instance.new("Frame")

	row.Size =
		UDim2.new(
			1,
			-12,
			0,
			42
		)

	row.BackgroundColor3 =
		Color3.fromRGB(
			38,
			23,
			58
		)

	row.BorderSizePixel = 0
	row.Parent = Content

	local corner =
		Instance.new("UICorner")

	corner.CornerRadius =
		UDim.new(0, 9)

	corner.Parent = row

	local label =
		Instance.new("TextLabel")

	label.Size =
		UDim2.new(
			0.55,
			0,
			1,
			0
		)

	label.Position =
		UDim2.new(
			0,
			12,
			0,
			0
		)

	label.BackgroundTransparency = 1

	label.Text = labelText

	label.TextColor3 =
		Color3.fromRGB(
			220,
			210,
			235
		)

	label.Font =
		Enum.Font.GothamMedium

	label.TextSize = 12

	label.TextXAlignment =
		Enum.TextXAlignment.Left

	label.Parent = row

	local box =
		Instance.new("TextBox")

	box.Size =
		UDim2.new(
			0.32,
			0,
			0,
			30
		)

	box.Position =
		UDim2.new(
			0.64,
			0,
			0.5,
			-15
		)

	box.BackgroundColor3 =
		Color3.fromRGB(
			25,
			15,
			40
		)

	box.BorderSizePixel = 0

	box.Text =
		tostring(defaultValue)

	box.TextColor3 =
		Color3.new(
			1,
			1,
			1
		)

	box.Font =
		Enum.Font.Gotham

	box.TextSize = 12

	box.ClearTextOnFocus = false

	box.Parent = row

	local boxCorner =
		Instance.new("UICorner")

	boxCorner.CornerRadius =
		UDim.new(0, 7)

	boxCorner.Parent = box

	return box
end

--========================================================
-- AUTOMATION UI
--========================================================

createSection("AUTOMATION")

local AutoCollectButton =
	createButton(
		"📦 Auto Item Collect : OFF"
	)

AutoCollectButton.MouseButton1Click:Connect(
	function()

		Settings.AutoCollect =
			not Settings.AutoCollect

		if not Settings.AutoCollect then
			CurrentItemTarget = nil
			clearPath()
		end

		updateButton(
			AutoCollectButton,
			"📦 Auto Item Collect",
			Settings.AutoCollect
		)
	end
)

local AutoAvoidButton =
	createButton(
		"🛡 Auto Avoid : OFF"
	)

AutoAvoidButton.MouseButton1Click:Connect(
	function()

		Settings.AutoAvoid =
			not Settings.AutoAvoid

		clearPath()

		updateButton(
			AutoAvoidButton,
			"🛡 Auto Avoid",
			Settings.AutoAvoid
		)
	end
)

local AutoChaseButton =
	createButton(
		"🎯 Auto Chase : OFF"
	)

AutoChaseButton.MouseButton1Click:Connect(
	function()

		Settings.AutoChase =
			not Settings.AutoChase

		clearPath()

		updateButton(
			AutoChaseButton,
			"🎯 Auto Chase",
			Settings.AutoChase
		)
	end
)

local ChaseAllButton =
	createButton(
		"👥 Chase All : OFF"
	)

ChaseAllButton.MouseButton1Click:Connect(
	function()

		Settings.ChaseAll =
			not Settings.ChaseAll

		if Settings.ChaseAll then
			Settings.AutoChase = true

			updateButton(
				AutoChaseButton,
				"🎯 Auto Chase",
				true
			)
		end

		clearPath()

		updateButton(
			ChaseAllButton,
			"👥 Chase All",
			Settings.ChaseAll
		)
	end
)

--========================================================
-- RANGE
--========================================================

createSection("RANGE")

local UnlimitedChaseButton =
	createButton(
		"♾ Unlimited Chase : OFF"
	)

UnlimitedChaseButton.MouseButton1Click:Connect(
	function()

		Settings.UnlimitedChase =
			not Settings.UnlimitedChase

		updateButton(
			UnlimitedChaseButton,
			"♾ Unlimited Chase",
			Settings.UnlimitedChase
		)
	end
)

local UnlimitedAvoidButton =
	createButton(
		"♾ Unlimited Avoid : OFF"
	)

UnlimitedAvoidButton.MouseButton1Click:Connect(
	function()

		Settings.UnlimitedAvoid =
			not Settings.UnlimitedAvoid

		updateButton(
			UnlimitedAvoidButton,
			"♾ Unlimited Avoid",
			Settings.UnlimitedAvoid
		)
	end
)

--========================================================
-- MOVEMENT
--========================================================

createSection("MOVEMENT")

local SpeedBox =
	createInputRow(
		"WalkSpeed",
		Settings.WalkSpeed
	)

SpeedBox.FocusLost:Connect(
	function()

		local value =
			tonumber(SpeedBox.Text)

		if value then

			Settings.WalkSpeed =
				math.clamp(
					value,
					0,
					200
				)

			SpeedBox.Text =
				tostring(
					Settings.WalkSpeed
				)

			applyMovementSettings()
		else
			SpeedBox.Text =
				tostring(
					Settings.WalkSpeed
				)
		end
	end
)

local JumpBox =
	createInputRow(
		"JumpPower",
		Settings.JumpPower
	)

JumpBox.FocusLost:Connect(
	function()

		local value =
			tonumber(JumpBox.Text)

		if value then

			Settings.JumpPower =
				math.clamp(
					value,
					0,
					200
				)

			JumpBox.Text =
				tostring(
					Settings.JumpPower
				)

			applyMovementSettings()
		else
			JumpBox.Text =
				tostring(
					Settings.JumpPower
				)
		end
	end
)

--========================================================
-- VISUALS
--========================================================

createSection("PLAYER VISUALS")

local ESPButton =
	createButton(
		"👁 ESP : OFF"
	)

ESPButton.MouseButton1Click:Connect(
	function()

		Settings.ESP =
			not Settings.ESP

		updateButton(
			ESPButton,
			"👁 ESP",
			Settings.ESP
		)

		refreshESP()
	end
)

local InfoButton =
	createButton(
		"📊 Player Info : ON"
	)

InfoButton.MouseButton1Click:Connect(
	function()

		Settings.PlayerInfo =
			not Settings.PlayerInfo

		updateButton(
			InfoButton,
			"📊 Player Info",
			Settings.PlayerInfo
		)
	end
)

--========================================================
-- PLAYER SELECTOR
--========================================================

createSection("PLAYER SELECTOR")

local PlayerListFrame =
	Instance.new("ScrollingFrame")

PlayerListFrame.Name =
	"PlayerSelector"

PlayerListFrame.Size =
	UDim2.new(
		1,
		-12,
		0,
		190
	)

PlayerListFrame.BackgroundColor3 =
	Color3.fromRGB(
		27,
		17,
		42
	)

PlayerListFrame.BorderSizePixel = 0

PlayerListFrame.ScrollBarThickness = 5

PlayerListFrame.ScrollingDirection =
	Enum.ScrollingDirection.Y

PlayerListFrame.CanvasSize =
	UDim2.new(
		0,
		0,
		0,
		0
	)

PlayerListFrame.AutomaticCanvasSize =
	Enum.AutomaticSize.Y

PlayerListFrame.ClipsDescendants = true

PlayerListFrame.Parent = Content

local PlayerListCorner =
	Instance.new("UICorner")

PlayerListCorner.CornerRadius =
	UDim.new(0, 10)

PlayerListCorner.Parent =
	PlayerListFrame

local PlayerPadding =
	Instance.new("UIPadding")

PlayerPadding.PaddingTop =
	UDim.new(0, 5)

PlayerPadding.PaddingBottom =
	UDim.new(0, 5)

PlayerPadding.PaddingLeft =
	UDim.new(0, 5)

PlayerPadding.PaddingRight =
	UDim.new(0, 5)

PlayerPadding.Parent =
	PlayerListFrame

local PlayerLayout =
	Instance.new("UIListLayout")

PlayerLayout.Padding =
	UDim.new(0, 4)

PlayerLayout.HorizontalAlignment =
	Enum.HorizontalAlignment.Center

PlayerLayout.Parent =
	PlayerListFrame

--========================================================
-- PLAYER LIST
--========================================================

local function refreshPlayers()
	for _, child in ipairs(
		PlayerListFrame:GetChildren()
	) do

		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local playerCount = 0

	for _, player in ipairs(
		Players:GetPlayers()
	) do

		if player ~= LocalPlayer then

			playerCount += 1

			local button =
				Instance.new("TextButton")

			button.Size =
				UDim2.new(
					1,
					-4,
					0,
					34
				)

			button.BackgroundColor3 =
				Color3.fromRGB(
					42,
					27,
					60
				)

			button.BorderSizePixel = 0

			button.Text =
				player.DisplayName
				.. "  @"
				.. player.Name

			button.TextColor3 =
				Color3.fromRGB(
					220,
					210,
					230
				)

			button.Font =
				Enum.Font.Gotham

			button.TextSize = 11

			button.AutoButtonColor = false

			button.Parent =
				PlayerListFrame

			local corner =
				Instance.new("UICorner")

			corner.CornerRadius =
				UDim.new(0, 7)

			corner.Parent = button

			button.MouseButton1Click:Connect(
				function()

					Settings.SelectedPlayer =
						player

					Settings.ChaseAll = false

					clearPath()

					updateButton(
						ChaseAllButton,
						"👥 Chase All",
						false
					)
				end
			)

			if
				Settings.SelectedPlayer
				== player
			then

				button.BackgroundColor3 =
					Color3.fromRGB(
						92,
						42,
						140
					)
			end
		end
	end

	if playerCount == 0 then

		local empty =
			Instance.new("TextLabel")

		empty.Size =
			UDim2.new(
				1,
				0,
				0,
				34
			)

		empty.BackgroundTransparency = 1

		empty.Text =
			"No other players"

		empty.TextColor3 =
			Color3.fromRGB(
				150,
				140,
				165
			)

		empty.Font =
			Enum.Font.Gotham

		empty.TextSize = 12

		empty.Parent =
			PlayerListFrame
	end
end

--========================================================
-- DRAGGING
--========================================================

local dragging = false
local dragStart
local startPosition

TopBar.InputBegan:Connect(
	function(input)

		if
			input.UserInputType
			== Enum.UserInputType.MouseButton1
			or input.UserInputType
			== Enum.UserInputType.Touch
		then

			dragging = true

			dragStart =
				input.Position

			startPosition =
				Main.Position

			input.Changed:Connect(
				function()

					if
						input.UserInputState
						== Enum.UserInputState.End
					then

						dragging = false
					end
				end
			)
		end
	end
)

UserInputService.InputChanged:Connect(
	function(input)

		if not dragging then
			return
		end

		if
			input.UserInputType
			== Enum.UserInputType.MouseMovement
			or input.UserInputType
			== Enum.UserInputType.Touch
		then

			local delta =
				input.Position - dragStart

			Main.Position =
				UDim2.new(
					startPosition.X.Scale,
					startPosition.X.Offset + delta.X,

					startPosition.Y.Scale,
					startPosition.Y.Offset + delta.Y
				)
		end
	end
)

--========================================================
-- MINIMIZE
--========================================================

local minimized = false

Minimize.MouseButton1Click:Connect(
	function()

		minimized = not minimized

		Content.Visible =
			not minimized

		if minimized then

			Main.Size =
				UDim2.new(
					0,
					360,
					0,
					65
				)

			Minimize.Text = "+"

		else

			Main.Size =
				UDim2.new(
					0,
					360,
					0,
					570
				)

			Minimize.Text = "−"
		end
	end
)

--========================================================
-- PLAYER EVENTS
--========================================================

Players.PlayerAdded:Connect(
	function(player)

		player.CharacterAdded:Connect(
			function()

				task.wait(0.5)

				refreshPlayers()

				if Settings.ESP then
					createESP(player)
				end
			end
		)

		refreshPlayers()
	end
)

Players.PlayerRemoving:Connect(
	function(player)

		if Settings.SelectedPlayer
			== player
		then

			Settings.SelectedPlayer = nil
			clearPath()
		end

		removeESP(player)
		refreshPlayers()
	end
)

for _, player in ipairs(
	Players:GetPlayers()
) do

	if player ~= LocalPlayer then

		player.CharacterAdded:Connect(
			function()

				task.wait(0.5)

				if Settings.ESP then
					createESP(player)
				end

				refreshPlayers()
			end
		)

		player.CharacterRemoving:Connect(
			function()

				removeESP(player)

			end
		)
	end
end

--========================================================
-- AUTOMATION LOOP
--========================================================

task.spawn(
	function()

		while ScreenGui.Parent do

			task.wait(
				Settings.RepathInterval
			)

			applyMovementSettings()

			-- Priority:
			-- Avoid > Chase > Collect

			if Settings.AutoAvoid then

				autoAvoid()

			elseif Settings.AutoChase then

				autoChase()

			elseif Settings.AutoCollect then

				autoCollect()

			else

				clearPath()
			end
		end
	end
)

--========================================================
-- ITEM MONITOR
--========================================================

task.spawn(
	function()

		while ScreenGui.Parent do

			task.wait(0.25)

			if Settings.AutoCollect then

				if
					CurrentItemTarget
					and not CurrentItemTarget.Parent
				then

					CurrentItemTarget = nil
					clearPath()
				end
			end
		end
	end
)

--========================================================
-- ESP LOOP
--========================================================

task.spawn(
	function()

		while ScreenGui.Parent do

			task.wait(0.35)

			if Settings.ESP then
				refreshESP()
				updateESP()
			end
		end
	end
)

--========================================================
-- PLAYER LIST LOOP
--========================================================

task.spawn(
	function()

		while ScreenGui.Parent do

			task.wait(2)

			refreshPlayers()
		end
	end
)

--========================================================
-- INITIALIZATION
--========================================================

updateCharacter(
	LocalPlayer.Character
)

applyMovementSettings()

refreshPlayers()
refreshESP()

print(
	"[IMDE HUB] Premium Studio Edition V4 loaded."
)
