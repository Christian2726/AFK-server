
if queue_on_teleport then
    queue_on_teleport([[
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Christian2726/AFK-server/main/afk.lua"))()
    ]])
end 

-- SERVICES
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- CONFIG
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1428137351468814388/RqZsa_247ReiJSR1lLyD2Kb5xQrNdj0pf3UyNbWnkdml3uFDUHvAAiIfZc6jxKEuvohb"
local COUNTDOWN_SECONDS = 5
local REMOTE_SCRIPT_URL = "https://raw.githubusercontent.com/Christian2726/Christianscript/main/Christian.lua"
local SERVER_COOLDOWN = 20 * 60 -- 20 minutos
local visitedServers = {}

-- RemoteEvent para señal post-teleport
local teleportFlag = ReplicatedStorage:FindFirstChild("ClownTeleportFlag")
if not teleportFlag then
    local evt = Instance.new("RemoteEvent")
    evt.Name = "ClownTeleportFlag"
    evt.Parent = ReplicatedStorage
    teleportFlag = evt
end

-- ESTADO
local hrp
local currentBillboard, currentBeam, attachPlayer, attachClown
local lastSentValue = nil
local detectedPart, detectedValue = nil, 0

-- UTILIDADES
local function parseRateToNumber(text)
    if not text then return 0 end
    local val, suf = string.match(text, "%$([%d%.]+)([kKmMbB]?)/s")
    if not val then return 0 end
    local n = tonumber(val)
    if not n then return 0 end
    suf = (suf or ""):lower()
    if suf == "k" then n = n * 1e3
    elseif suf == "m" then n = n * 1e6
    elseif suf == "b" then n = n * 1e9 end
    return n
end

local function formatRate(num)
    if not num then return "N/A" end
    if num >= 1e9 then return string.format("$%gB/s", num/1e9)
    elseif num >= 1e6 then return string.format("$%gM/s", num/1e6)
    elseif num >= 1e3 then return string.format("$%gK/s", num/1e3)
    else return string.format("$%g/s", num) end
end

local function isInsideBase(obj)
    local cur = obj
    while cur do
        local n = tostring(cur.Name):lower()
        if n:find("base") or n:find("tycoon") or n:find("plot") then return true end
        cur = cur.Parent
    end
    return false
end

-- FIND PAYASO
local function findRichestClown()
    local bestVal = -math.huge
    local bestModel = nil
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Text and obj.Text:find("/s") and isInsideBase(obj) then
            local val = parseRateToNumber(obj.Text)
            if val and val > bestVal then
                local model = obj:FindFirstAncestorOfClass("Model")
                if model and model:FindFirstChildWhichIsA("BasePart") then
                    bestVal = val
                    bestModel = model
                end
            end
        end
    end
    if bestModel then
        local part = bestModel:FindFirstChildWhichIsA("BasePart")
        return part, bestVal
    end
    return nil, 0
end

-- CLEAN visuals
local function cleanupVisuals()
    pcall(function()
        if currentBillboard then currentBillboard:Destroy() currentBillboard=nil end
        if currentBeam then currentBeam:Destroy() currentBeam=nil end
        if attachPlayer then attachPlayer:Destroy() attachPlayer=nil end
        if attachClown then attachClown:Destroy() attachClown=nil end
    end)
    detectedPart, detectedValue = nil, 0
end

-- CREATE billboard
local function createBillboardOnPart(part, value)
    if not part then return nil end
    for _, c in ipairs(part:GetChildren()) do
        if c:IsA("BillboardGui") then pcall(function() c:Destroy() end) end
    end
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0,220,0,40)
    bb.StudsOffset = Vector3.new(0,3.5,0)
    bb.AlwaysOnTop = true
    bb.Parent = part

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,0,1,0)
    lbl.BackgroundTransparency = 0.3
    lbl.BackgroundColor3 = Color3.fromRGB(0,0,0)
    lbl.TextColor3 = Color3.fromRGB(255,255,255)
    lbl.TextScaled = true
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = formatRate(value)
    lbl.Parent = bb

    return bb
end

-- CREATE beam
local function createBeam(hrpRef, part)
    if not hrpRef or not part then return nil,nil,nil end
    local a0 = Instance.new("Attachment", hrpRef)
    local a1 = Instance.new("Attachment", part)
    local beam = Instance.new("Beam")
    beam.Attachment0 = a0
    beam.Attachment1 = a1
    beam.Width0 = 2
    beam.Width1 = 2
    beam.LightEmission = 1
    beam.Texture = "rbxassetid://446111271"
    beam.TextureMode = Enum.TextureMode.Wrap
    beam.TextureSpeed = 4
    beam.Transparency = NumberSequence.new(0)
    beam.Parent = hrpRef
    return beam, a0, a1
end

-- SAFE clipboard
local function safeSetClipboard(text)
    pcall(function() setclipboard(tostring(text)) end)
end

-- SEND webhook
local function sendWebhook(value)
    if not DISCORD_WEBHOOK or DISCORD_WEBHOOK=="" then return end
    if not value or value<=0 then return end
    if lastSentValue==value then return end

    local placeId = tostring(game.PlaceId or "N/A")
    local jobId = tostring(game.JobId or "N/A")
    local joinLink = string.format("https://kebabman.vercel.app/start?placeId=%s&gameInstanceId=%s", placeId, jobId)

    local payload = {
        content = string.format("**💰 Payaso más valioso detectado**\nValor: %s\nPlaceId: %s\nJobId: %s\nUnirse: %s",
            formatRate(value), placeId, jobId, joinLink),
        embeds = {{
            title = "Payaso más valioso",
            color = 3447003,
            fields = {
                { name = "Valor", value = formatRate(value), inline=true },
                { name = "Unirse", value = string.format("[Unirse al servidor](%s)", joinLink), inline=true }
            },
            timestamp=os.date("!%Y-%m-%dT%H:%M:%SZ", os.time())
        }}
    }
    pcall(function()
        HttpService:RequestAsync({
            Url=DISCORD_WEBHOOK,
            Method="POST",
            Headers={["Content-Type"]="application/json"},
            Body=HttpService:JSONEncode(payload)
        })
    end)
    lastSentValue = value
end

-- TELEPORT aleatorio evitando servidores recientes
local function getRandomServer()
    local placeId = game.PlaceId
    local servers = {}
    local cursor = nil

    repeat
        local url = "https://games.roblox.com/v1/games/"..placeId.."/servers/Public?limit=100"
        if cursor then url = url.."&cursor="..cursor end
        local success, result = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)
        if success and result and result.data then
            for _, srv in ipairs(result.data) do
                if srv.playing < srv.maxPlayers and (not visitedServers[srv.id] or tick() - visitedServers[srv.id] > SERVER_COOLDOWN) then
                    table.insert(servers, srv.id)
                end
            end
            cursor = result.nextPageCursor
        else
            break
        end
    until not cursor

    if #servers > 0 then
        local selected = servers[math.random(1,#servers)]
        visitedServers[selected] = tick()
        return selected
    end
    return nil
end

local function teleportToRandomServer()
    local jobId = getRandomServer()
    if jobId then
        teleportFlag:FireServer(LocalPlayer)
        TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LocalPlayer)
    end
end

-- GUI con auto inicio de cuenta atrás
local function createMainGUI()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("ClownAutoGUI")
    if old then old:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ClownAutoGUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    local frame = Instance.new("Frame", screenGui)
    frame.Size = UDim2.new(0,230,0,150)
    frame.Position = UDim2.new(0,10,0,60)
    frame.BackgroundColor3 = Color3.fromRGB(20,20,20)
    frame.BorderSizePixel = 0

    local copyPlace = Instance.new("TextButton", frame)
    copyPlace.Size = UDim2.new(1,-12,0,30)
    copyPlace.Position = UDim2.new(0,6,0,6)
    copyPlace.Text = "PlaceId"
    copyPlace.TextScaled = true
    copyPlace.MouseButton1Click:Connect(function()
        safeSetClipboard(tostring(game.PlaceId))
    end)

    local copyJob = Instance.new("TextButton", frame)
    copyJob.Size = UDim2.new(1,-12,0,30)
    copyJob.Position = UDim2.new(0,6,0,42)
    copyJob.Text = "JobId"
    copyJob.TextScaled = true
    copyJob.MouseButton1Click:Connect(function()
        safeSetClipboard(tostring(game.JobId))
    end)

    local joinBtn = Instance.new("TextButton", frame)
    joinBtn.Size = UDim2.new(1,-12,0,30)
    joinBtn.Position = UDim2.new(0,6,0,78)
    joinBtn.Text = "Unirse (Click para iniciar 5s)"
    joinBtn.TextScaled = true

    -- AUTO countdown
    task.spawn(function()
        joinBtn.Active = false
        for i=COUNTDOWN_SECONDS,1,-1 do
            joinBtn.Text = "Unirse en "..i.."s"
            task.wait(1)
        end
        joinBtn.Text = "Teletransportando..."
        teleportToRandomServer()
    end)

    return screenGui
end

-- MAIN LOOP
task.spawn(function()
    hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    createMainGUI()

    while true do
        task.wait(0.5)
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            hrp = LocalPlayer.Character.HumanoidRootPart
        end
        local part, val = findRichestClown()
        if part and val>0 then
            if part~=detectedPart then
                cleanupVisuals()
                currentBillboard = createBillboardOnPart(part,val)
                currentBeam, attachPlayer, attachClown = createBeam(hrp,part)
                detectedPart = part
                detectedValue = val
            end
            sendWebhook(val)
        else
            cleanupVisuals()
        end
    end
end)

-- AUTO EXECUTE SCRIPT AFTER TELEPORT
teleportFlag.OnClientEvent:Connect(function()
    task.wait(0.25)
    pcall(function()
        local code = game:HttpGet(REMOTE_SCRIPT_URL,true)
        local func = loadstring(code)
        if func then func() end
    end)
end)

print("[ClownAutoTeleport] listo.")
