if queue_on_teleport then
    queue_on_teleport([[
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Christian2726/AFK-server/main/afk.lua"))()
    ]])
end 

-- SERVICIOS
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- CONFIG
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1436961265464512583/zXtR1YJJew8TZTteDI3AZITZp0BunTvsUAAVt8pz2D9S2Bezeyz5HxzK0pcjZgckLKfx"
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
local detectedPart, detectedValue = nil, 0

-----------------------------------------------------
-- FUNCIONES UTILITARIAS
-----------------------------------------------------
local function parseRateToNumber(text)
    if not text then return 0 end
    text = text:gsub("%s+", ""):lower()
    local val, suf = string.match(text, "%$([%d%.]+)([kmb]?)/s")
    if not val then return 0 end
    local n = tonumber(val)
    if not n then return 0 end
    if suf == "k" then n = n * 1e3
    elseif suf == "m" then n = n * 1e6
    elseif suf == "b" then n = n * 1e9
    end
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

-----------------------------------------------------
-- Buscar el "payaso más rico"
-----------------------------------------------------
local function findRichestClown()
    local bestVal = -math.huge
    local bestPart = nil
    local fields = {
        valorPorSegundo = "",
        valorTotal = "",
        rareza = "",
        nombre = "",
        estado = "",
        extra = ""
    }

    local rarezas = {["Gold"]=true, ["Diamond"]=true, ["Platinum"]=true, ["Silver"]=true}
    local estadosValidos = {["STOLEN"]=true, ["SECRET"]=true}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Text and isInsideBase(obj) then
            local val = parseRateToNumber(obj.Text)
            if val and val > bestVal and obj.Text:find("/") then
                local model = obj:FindFirstAncestorOfClass("Model")
                if model then
                    local part = model:FindFirstChildWhichIsA("BasePart")
                    if part then
                        bestVal = val
                        bestPart = part

                        local parent = obj.Parent
                        local labels = {}
                        for _, child in ipairs(parent:GetChildren()) do
                            if child:IsA("TextLabel") and child.Text ~= "" then
                                table.insert(labels, child)
                            end
                        end
                        table.sort(labels, function(a,b) return a.Position.Y.Scale < b.Position.Y.Scale end)

                        local posiblesNombre = {}
                        for _, lbl in ipairs(labels) do
                            local txt = lbl.Text
                            if txt:find("/") then
                                fields.valorPorSegundo = txt
                            elseif tonumber(txt:match("[%d%.]+")) and not txt:find("/") then
                                fields.valorTotal = txt
                            elseif rarezas[txt] then
                                fields.rareza = txt
                            elseif estadosValidos[txt:upper()] then
                                fields.estado = txt
                            else
                                if #txt:split(" ") >= 2 then
                                    table.insert(posiblesNombre, txt)
                                elseif #txt:split(" ") == 1 then
                                    fields.extra = txt
                                end
                            end
                        end

                        if #posiblesNombre >= 1 then
                            fields.nombre = posiblesNombre[1]
                        end
                    end
                end
            end
        end
    end

    return bestPart, bestVal, fields
end

-----------------------------------------------------
-- LIMPIAR VISUALES
-----------------------------------------------------
local function cleanupVisuals()
    pcall(function()
        if currentBillboard then currentBillboard:Destroy() currentBillboard=nil end
        if currentBeam then currentBeam:Destroy() currentBeam=nil end
        if attachPlayer then attachPlayer:Destroy() attachPlayer=nil end
        if attachClown then attachClown:Destroy() attachClown=nil end
    end)
    detectedPart, detectedValue = nil, 0
end

-----------------------------------------------------
-- BILLBOARD
-----------------------------------------------------
local function createBillboardOnPart(part, combinedText)
    if not part then return nil end
    for _, c in ipairs(part:GetChildren()) do
        if c:IsA("BillboardGui") then pcall(function() c:Destroy() end) end
    end
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0,220,0,70)
    bb.StudsOffset = Vector3.new(0,3.5,0)
    bb.AlwaysOnTop = true
    bb.Parent = part

    local lblAll = Instance.new("TextLabel")
    lblAll.Size = UDim2.new(1,0,1,0)
    lblAll.BackgroundTransparency = 1
    lblAll.TextColor3 = Color3.fromRGB(255,255,0)
    lblAll.TextScaled = true
    lblAll.Font = Enum.Font.GothamBold
    lblAll.Text = combinedText
    lblAll.Parent = bb

    return bb
end

-----------------------------------------------------
-- BEAM
-----------------------------------------------------
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

-----------------------------------------------------
-- WEBHOOK (SIN CAMBIOS)
-----------------------------------------------------
local function sendWebhook(fields)
    if not DISCORD_WEBHOOK or DISCORD_WEBHOOK=="" then return end
    if not fields then return end

    local placeId = tostring(game.PlaceId or "N/A")
    local jobId = tostring(game.JobId or "N/A")
    local joinLink = string.format(
        "https://kebabman.vercel.app/start?placeId=%s&gameInstanceId=%s",
        placeId, jobId
    )

    local discordFields = {}
    table.insert(discordFields, {name="Nombre", value=fields.nombre, inline=false})
    table.insert(discordFields, {name="Valor por segundo", value=fields.valorPorSegundo, inline=true})
    table.insert(discordFields, {name="Valor total", value=fields.valorTotal, inline=true})
    table.insert(discordFields, {name="Rareza_1", value=fields.rareza, inline=true})
    table.insert(discordFields, {name="Rareza_2", value=fields.estado, inline=true})
    table.insert(discordFields, {name="Extra", value=fields.extra, inline=true})
    table.insert(discordFields, {
        name="Unirse al Servidor",
        value=string.format("[Click aquí para unirse](%s)", joinLink),
        inline=false
    })

    local payload = {
        content="**💰 Payaso más valioso**",
        embeds={{
            title="",
            color=3447003,
            fields=discordFields,
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
end

-----------------------------------------------------
-- SERVER HOP
-----------------------------------------------------
local function createServerHopButton()
    local ScreenGui = Instance.new("ScreenGui", game.CoreGui)
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(0, 140, 0, 40)
    Button.Position = UDim2.new(1, -160, 1, -60)
    Button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    Button.TextColor3 = Color3.fromRGB(255, 255, 255)
    Button.Font = Enum.Font.GothamBold
    Button.TextScaled = true
    Button.Text = "🔄 Server Hop"
    Button.Parent = ScreenGui

    local function doServerHop()
        Button.Text = "Buscando..."
        pcall(function()
            local servers = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
            local available = {}
            for _, srv in ipairs(servers.data) do
                if srv.playing < srv.maxPlayers and srv.id ~= game.JobId then
                    table.insert(available, srv.id)
                end
            end
            if #available > 0 then
                local chosen = available[math.random(1, #available)]
                Button.Text = "Teleporting..."
                TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen, LocalPlayer)
            else
                Button.Text = "Sin servidores"
                task.wait(2)
                Button.Text = "🔄 Server Hop"
            end
        end)
    end

    Button.MouseButton1Click:Connect(doServerHop)
    task.spawn(function()
        while task.wait(4) do
            doServerHop()
        end
    end)
end

createServerHopButton()

-----------------------------------------------------
-- BUCLE PRINCIPAL
-----------------------------------------------------
task.spawn(function()
    hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    while true do
        task.wait(0.5)
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            hrp = LocalPlayer.Character.HumanoidRootPart
        end

        local part, val, fields = findRichestClown()
        if part and val>0 then
            if part ~= detectedPart then
                cleanupVisuals()
                
                -- Modificar texto y color según si cumple >= 1M/s
                local displayRate = val >= 1e6 and fields.valorPorSegundo or "< $1M/s"
                local combinedText = table.concat({
                    fields.nombre,
                    fields.rareza,
                    fields.valorTotal,
                    displayRate,
                    fields.estado,
                    fields.extra
                }, "\n")
                
                currentBillboard = createBillboardOnPart(part, combinedText)
                if currentBillboard and currentBillboard:FindFirstChildOfClass("TextLabel") then
                    local lbl = currentBillboard:FindFirstChildOfClass("TextLabel")
                    if val >= 1e6 then
                        lbl.TextColor3 = Color3.fromRGB(255, 255, 0) -- amarillo brillante
                    else
                        lbl.TextColor3 = Color3.fromRGB(150, 150, 150) -- gris
                    end
                end

                currentBeam, attachPlayer, attachClown = createBeam(hrp, part)

                detectedPart = part
                detectedValue = val

                -- ENVIAR WEBHOOK SOLO SI VALOR >= $1M/s Y NOMBRE NO ES "Brainrot God"
                if val >= 1e6 and fields.nombre:lower() ~= "brainrot god" then
                    sendWebhook(fields)
                    print("[ClownAutoTeleport] Brainrot valioso detectado y enviado: "..formatRate(val))
                else
                    if fields.nombre:lower() == "brainrot god" then
                        print("[ClownAutoTeleport] Brainrot God detectado, no se envía webhook.")
                    elseif val < 1e6 then
                        print("[ClownAutoTeleport] Brainrot detectado pero < $1M/s, no se envía webhook.")
                    end
                end
            end
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

print("[ClownAutoTeleport] listo con Server Hop automático cada 4s.")
