-- SelfDefenseModule.lua
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local SelfDefense = {}
SelfDefense.__index = SelfDefense

function SelfDefense.new(config)
    local self = setmetatable({}, SelfDefense)
    self.MaxDistance = config.MaxDistance or 60
    self.AutoFireCooldown = config.Cooldown or 0.5
    self.LastShotTime = 0
    self.IsEnabled = false
    return self
end

-- Checks if there is an unobstructed line of sight to the Murderer
function SelfDefense:HasLineOfSight(origin, targetPart)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    raycastParams.IgnoreWater = true

    local direction = (targetPart.Position - origin).Unit * self.MaxDistance
    local result = Workspace:Raycast(origin, direction, raycastParams)

    if result and result.Instance:IsDescendantOf(targetPart.Parent) then
        return true
    end
    return false
end

-- Locates the current active Murderer in the game instance
function SelfDefense:GetTargetMurderer()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            -- Verify if target is holding or equipped with the Knife (Murderer role)
            local hasKnife = player.Character:FindFirstChild("Knife") 
                or (player:FindFirstChild("Backpack") and player.Backpack:FindFirstChild("Knife"))
            
            if hasKnife then
                return player.Character.HumanoidRootPart
            end
        end
    end
    return nil
end

-- Core logic loop to evaluate threat and auto-fire
function SelfDefense:EvaluateAndShoot(gunTool, fireRemote)
    if not self.IsEnabled then return end
    if os.clock() - self.LastShotTime < self.AutoFireCooldown then return end

    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end

    local targetRoot = self:GetTargetMurderer()
    if not targetRoot then return end

    local myPos = char.HumanoidRootPart.Position
    local distance = (targetRoot.Position - myPos).Magnitude

    if distance <= self.MaxDistance then
        if self:HasLineOfSight(myPos, targetRoot) then
            self.LastShotTime = os.clock()
            
            -- Trigger weapon firing sequence
            if fireRemote then
                fireRemote:FireServer(targetRoot.Position)
            elseif gunTool and gunTool:FindFirstChild("Shoot") then
                gunTool.Shoot:FireServer(targetRoot.Position)
            end
        end
    end
end

return SelfDefense
