local success, err = pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/IMDE122/MM2AUTOPILOT/refs/heads/main/Needfix", true))()
end)
if not success then warn("Failed to execute MM2 script: " .. tostring(err)) end
