-- ═══════════════════════════════════════════════════════════════
-- ASTRA HUB - MOTOR DE AUTO FARM (RAID) v2.1 - ARQUIVO ÚNICO
-- Interface + Save + Auto Farm - Tudo em um só
-- ═══════════════════════════════════════════════════════════════

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local RS_Motor     = game:GetService("ReplicatedStorage")
local UserInput    = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui      = game:GetService("CoreGui")
local HttpService  = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- ═══════════════════ CONFIG PADRÃO ═══════════════════
local DEFAULT_CFG = {
    PosicaoFixa = { X = 600.06, Y = -240.61, Z = -24.71 },
    AlienName   = "upgrade",
    GunArmArg   = "Gun_Arm",
    Arg2        = 19.7,
    Paralelas   = 3,
    Delay       = 0.03,
    PastaNPC    = "Enemys",
    TempoReplay = 3,
    MotorAtivo  = false,
    SaveAtivo   = false,
}

-- ═══════════════════ SISTEMA DE SAVE ═══════════════════
local SAVE_FOLDER = "AstraHub"
local SAVE_FILE   = SAVE_FOLDER .. "/config.json"
local hasFS = (writefile and readfile and isfile) and true or false

local function ensureFolder()
    if not isfolder then return end
    if not isfolder(SAVE_FOLDER) then pcall(makefolder, SAVE_FOLDER) end
end

local SaveSystem = {}

function SaveSystem.load()
    if not hasFS then return nil end
    local ok, data = pcall(function()
        if not isfile(SAVE_FILE) then return nil end
        return HttpService:JSONDecode(readfile(SAVE_FILE))
    end)
    if ok and type(data) == "table" then return data end
    return nil
end

function SaveSystem.save(tbl)
    if not hasFS then return false end
    ensureFolder()
    local ok = pcall(function()
        writefile(SAVE_FILE, HttpService:JSONEncode(tbl))
    end)
    return ok
end

local saved = SaveSystem.load()
local CFG = {}
for k, v in pairs(DEFAULT_CFG) do CFG[k] = v end
if saved then
    for k, v in pairs(saved) do
        if CFG[k] ~= nil or k == "PosicaoFixa" then CFG[k] = v end
    end
end

local function getCFramePos()
    local p = CFG.PosicaoFixa
    if typeof(p) == "CFrame" then return p end
    return CFrame.new(p.X, p.Y, p.Z)
end

-- ═══════════════════ ESTADO DO MOTOR ═══════════════════
local AutoGunArm = {}
AutoGunArm.Ativo = false
AutoGunArm.CFG   = CFG
AutoGunArm.CFramePos = getCFramePos()

local pastaAlien, gunArm, armFire, pastaNPC, morphRemote, endMission
local ultimoMorph, ultimoVoto = 0, 0
local loopAntiVoid, loopPos, loopEquip, loopsTiro = nil, nil, nil, {}
local chaoInvisivel = nil
local isSpawning = false
local attach, alignPos, alignOri = nil, nil, nil

pcall(function()
    pastaAlien = RS_Motor:WaitForChild("AliensPowerRemotes", 10)
    if pastaAlien then pastaAlien = pastaAlien:WaitForChild(CFG.AlienName, 10) end
    if pastaAlien then
        gunArm  = pastaAlien:WaitForChild("GunArm", 10)
        armFire = pastaAlien:WaitForChild("ArmFire", 10)
    end
    pastaNPC    = workspace:WaitForChild(CFG.PastaNPC, 10)
    local remotes = RS_Motor:WaitForChild("Remotes", 10)
    if remotes then
        local charRem = remotes:WaitForChild("Character", 10)
        if charRem then
            local morph = charRem:WaitForChild("Morph", 10)
            if morph then morphRemote = morph:WaitForChild("AlienMorph", 5) end
        end
        local uiManager = remotes:FindFirstChild("UIManager")
        endMission = uiManager and uiManager:FindFirstChild("EndMission")
    end
end)

-- ═══════════════════ HELPERS ═══════════════════
local function isInRaid()
    local MUNDO_1 = 85122831959289
    local MUNDO_2 = 131073412590872
    if game.PlaceId == MUNDO_1 or game.PlaceId == MUNDO_2 then return false end
    return true
end

local function criarChao()
    if not chaoInvisivel or not chaoInvisivel.Parent then
        chaoInvisivel = Instance.new("Part")
        chaoInvisivel.Name = "AstraSafeFloor"
        chaoInvisivel.Size = Vector3.new(30, 2, 30)
        chaoInvisivel.Position = AutoGunArm.CFramePos.Position - Vector3.new(0, 4, 0)
        chaoInvisivel.Anchored = true
        chaoInvisivel.CanCollide = true
        chaoInvisivel.Transparency = 1
        chaoInvisivel.Parent = workspace
    end
end

local function setupPhysics(char)
    local root = char:WaitForChild("HumanoidRootPart", 5)
    local hum  = char:WaitForChild("Humanoid", 5)
    if not root or not hum then return end
    root.Anchored = false
    hum.WalkSpeed = 0
    hum.JumpPower = 0
    if attach   then attach:Destroy()   end
    if alignPos then alignPos:Destroy() end
    if alignOri then alignOri:Destroy() end
    attach = Instance.new("Attachment", root)
    attach.Name = "AstraVoidAttachment"
    attach.Position = Vector3.new(0, 0, 0)
    alignPos = Instance.new("AlignPosition", root)
    alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
    alignPos.Attachment0 = attach
    alignPos.Position = AutoGunArm.CFramePos.Position
    alignPos.MaxForce = math.huge
    alignPos.Responsiveness = 200
    alignPos.ApplyAtCenterOfMass = true
    alignOri = Instance.new("AlignOrientation", root)
    alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
    alignOri.Attachment0 = attach
    alignOri.CFrame = AutoGunArm.CFramePos
    alignOri.MaxTorque = math.huge
    alignOri.Responsiveness = 200
end

local function isAlien()
    local char = LocalPlayer.Character
    if not char then return false end
    local alvoLower = CFG.AlienName:lower()
    if char.Name:lower():find(alvoLower) then return true end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj.Name:lower() == alvoLower then return true end
    end
    return false
end

function AutoGunArm.acharAlvos()
    local lista = {}
    if not pastaNPC then return lista end
    for _, npc in ipairs(pastaNPC:GetChildren()) do
        if not npc.Name:lower():find("dummy") then
            local hum = npc:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local root = hum.Parent:FindFirstChild("HumanoidRootPart")
                if root then table.insert(lista, root) end
            end
        end
    end
    return lista
end

local function motorMorphar()
    if not morphRemote or isAlien() then return end
    local agora = os.clock()
    if agora - ultimoMorph < 3 then return end
    ultimoMorph = agora
    pcall(function() morphRemote:InvokeServer(CFG.AlienName) end)
end

local function motorEquipar()
    if not gunArm then return end
    pcall(function() gunArm:InvokeServer(CFG.GunArmArg) end)
end

local function motorAtirar(alvoRoot)
    if not alvoRoot or not armFire then return end
    pcall(function() armFire:InvokeServer(alvoRoot.Position, CFG.Arg2) end)
end

local function motorVotarReplay()
    if not endMission then return end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local hud2 = pg and pg:FindFirstChild("HUD2")
    local fimMissao = hud2 and hud2:FindFirstChild("Fim_Missao")
    local tela = fimMissao and fimMissao:FindFirstChild("Tela")
    if tela and tela.Visible then
        if os.clock() - ultimoVoto > CFG.TempoReplay then
            pcall(function() endMission:FireServer("Choose", "Replay") end)
            ultimoVoto = os.clock()
        end
    end
end

-- ═══════════════════ LOOPS ═══════════════════
local function iniciarAntiVoid()
    if loopAntiVoid then loopAntiVoid:Disconnect() end
    loopAntiVoid = RunService.RenderStepped:Connect(function()
        if not AutoGunArm.Ativo or not isInRaid() or isSpawning then return end
        local char = LocalPlayer.Character
        if char then
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then
                if root.Anchored then root.Anchored = false end
                if not alignPos or not alignPos.Parent then setupPhysics(char); return end
                alignPos.Position = AutoGunArm.CFramePos.Position
                if (root.Position - AutoGunArm.CFramePos.Position).Magnitude > 5 then
                    root.CFrame = AutoGunArm.CFramePos
                end
            end
        end
    end)
end

local function pararLoops()
    if loopAntiVoid then loopAntiVoid:Disconnect(); loopAntiVoid = nil end
    if loopPos      then loopPos:Disconnect();      loopPos = nil end
    if loopEquip    then loopEquip:Disconnect();    loopEquip = nil end
    for _, l in ipairs(loopsTiro) do
        if l then l:Disconnect() end
    end
    loopsTiro = {}
end

local function motorLoopPosicao()
    loopPos = task.spawn(function()
        while AutoGunArm.Ativo do
            if isInRaid() then
                criarChao()
                if not isAlien() then motorMorphar() end
                motorVotarReplay()
            else
                if chaoInvisivel and chaoInvisivel.Parent then
                    chaoInvisivel:Destroy(); chaoInvisivel = nil
                end
            end
            task.wait(0.5)
        end
    end)
end

local function motorLoopAtirar()
    loopEquip = task.spawn(function()
        while AutoGunArm.Ativo do
            if isInRaid() then motorEquipar() end
            task.wait(3)
        end
    end)
    for _ = 1, CFG.Paralelas do
        table.insert(loopsTiro, task.spawn(function()
            while AutoGunArm.Ativo do
                if isInRaid() then
                    local alvos = AutoGunArm.acharAlvos()
                    for _, alvo in ipairs(alvos) do
                        if not AutoGunArm.Ativo then break end
                        motorAtirar(alvo)
                    end
                end
                task.wait(CFG.Delay)
            end
        end))
    end
end

-- ═══════════════════ LIGAR / DESLIGAR ═══════════════════
function AutoGunArm.ligar()
    if AutoGunArm.Ativo then return end
    AutoGunArm.Ativo = true
    local char = LocalPlayer.Character
    if char and isInRaid() then setupPhysics(char) end
    iniciarAntiVoid()
    motorLoopPosicao()
    motorLoopAtirar()
    print("[Astra] Auto Farm ligado!")
    if CFG.SaveAtivo then
        CFG.MotorAtivo = true
        SaveSystem.save(CFG)
    end
end

function AutoGunArm.desligar()
    if not AutoGunArm.Ativo then return end
    AutoGunArm.Ativo = false
    isSpawning = false
    pararLoops()
    if chaoInvisivel and chaoInvisivel.Parent then
        chaoInvisivel:Destroy(); chaoInvisivel = nil
    end
    if attach   then attach:Destroy();   attach = nil   end
    if alignPos then alignPos:Destroy(); alignPos = nil end
    if alignOri then alignOri:Destroy(); alignOri = nil end
    local char = LocalPlayer.Character
    if char then
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if root then pcall(function() root.Anchored = false end) end
        if hum  then hum.WalkSpeed = 16; hum.JumpPower = 50 end
    end
    print("[Astra] Auto Farm desligado!")
    if CFG.SaveAtivo then
        CFG.MotorAtivo = false
        SaveSystem.save(CFG)
    end
end

LocalPlayer.CharacterAdded:Connect(function(char)
    if AutoGunArm.Ativo and isInRaid() then
        isSpawning = true
        local root = char:WaitForChild("HumanoidRootPart", 10)
        if root then
            task.wait(3)
            if AutoGunArm.Ativo and isInRaid() then setupPhysics(char) end
            isSpawning = false
        else
            isSpawning = false
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- INTERFACE GRÁFICA
-- ═══════════════════════════════════════════════════════════════
local function getGuiParent()
    if gethui then return gethui() end
    if CoreGui then return CoreGui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local OLD = getGuiParent():FindFirstChild("AstraHubUI")
if OLD then OLD:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AstraHubUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = getGuiParent()

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 320, 0, 260)
Main.Position = UDim2.new(0.5, -160, 0.5, -130)
Main.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(90, 60, 200)
MainStroke.Thickness = 1.5
MainStroke.Parent = Main

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 38)
Header.BackgroundColor3 = Color3.fromRGB(28, 24, 40)
Header.BorderSizePixel = 0
Header.Parent = Main

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 10)
HeaderCorner.Parent = Header

local HeaderFix = Instance.new("Frame")
HeaderFix.Size = UDim2.new(1, 0, 0, 12)
HeaderFix.Position = UDim2.new(0, 0, 1, -12)
HeaderFix.BackgroundColor3 = Color3.fromRGB(28, 24, 40)
HeaderFix.BorderSizePixel = 0
HeaderFix.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -80, 1, 0)
Title.Position = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "⚡ ASTRA HUB  ·  RAID"
Title.TextColor3 = Color3.fromRGB(230, 225, 255)
Title.TextSize = 15
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local function makeHeaderBtn(txt, x, color)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 24, 0, 24)
    btn.Position = UDim2.new(1, x, 0, 7)
    btn.BackgroundColor3 = color
    btn.Text = txt
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    btn.AutoButtonColor = true
    btn.Parent = Header
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 5)
    c.Parent = btn
    return btn
end

local MinimizeBtn = makeHeaderBtn("—", -60, Color3.fromRGB(60, 60, 75))
local CloseBtn    = makeHeaderBtn("✕", -32, Color3.fromRGB(180, 50, 60))

local Body = Instance.new("Frame")
Body.Name = "Body"
Body.Size = UDim2.new(1, -20, 1, -58)
Body.Position = UDim2.new(0, 10, 0, 48)
Body.BackgroundTransparency = 1
Body.Parent = Main

local BodyLayout = Instance.new("UIListLayout")
BodyLayout.Padding = UDim.new(0, 10)
BodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
BodyLayout.Parent = Body

local function makeToggle(text, color, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 40)
    btn.BackgroundColor3 = color
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 14
    btn.AutoButtonColor = true
    btn.Parent = Body
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = btn
    local stroke = Instance.new("UIStroke")
    stroke.Color = color:Lerp(Color3.new(1,1,1), 0.3)
    stroke.Thickness = 1
    stroke.Parent = btn
    local estado = false
    local function updateVisual()
        if estado then
            btn.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.15)
            btn.Text = text .. "  ✔"
        else
            btn.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.15)
            btn.Text = text .. "  ✘"
        end
    end
    updateVisual()
    btn.MouseButton1Click:Connect(function()
        estado = not estado
        updateVisual()
        if callback then callback(estado) end
    end)
    btn.setEstado = function(v) estado = v; updateVisual() end
    btn.getEstado = function() return estado end
    return btn
end

local MotorBtn = makeToggle("Auto Farm (Raid)", Color3.fromRGB(90, 60, 200), function(state)
    if state then AutoGunArm.ligar() else AutoGunArm.desligar() end
end)

local SaveBtn = makeToggle("Save Config", Color3.fromRGB(40, 140, 90), function(state)
    CFG.SaveAtivo = state
    if state then
        CFG.MotorAtivo = AutoGunArm.Ativo
        local ok = SaveSystem.save(CFG)
        if ok then
            SaveBtn.Text = "Save Config  💾 (salvo!)"
            task.delay(1.5, function()
                if SaveBtn.getEstado() then SaveBtn.Text = "Save Config  ✔"
                else SaveBtn.Text = "Save Config  ✘" end
            end)
        else
            SaveBtn.Text = "Save Config  ⚠ (sem FS)"
        end
    else
        if hasFS and isfile(SAVE_FILE) then pcall(delfile, SAVE_FILE) end
    end
end)

local Footer = Instance.new("TextLabel")
Footer.Size = UDim2.new(1, 0, 0, 20)
Footer.BackgroundTransparency = 1
Footer.Text = "v2.1 · script único"
Footer.TextColor3 = Color3.fromRGB(120, 120, 140)
Footer.TextSize = 11
Footer.Font = Enum.Font.Gotham
Footer.Parent = Body

-- Minimizar
local minimizado = false
local tamanhoNormal = Main.Size
local posicaoNormal = Main.Position

MinimizeBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    if minimizado then
        posicaoNormal = Main.Position
        Body.Visible = false
        TweenService:Create(Main, TweenInfo.new(0.2), {
            Size = UDim2.new(0, 320, 0, 38)
        }):Play()
        MinimizeBtn.Text = "▢"
    else
        TweenService:Create(Main, TweenInfo.new(0.2), {
            Size = tamanhoNormal
        }):Play()
        task.wait(0.2)
        Body.Visible = true
        MinimizeBtn.Text = "—"
    end
end)

-- Fechar
CloseBtn.MouseButton1Click:Connect(function()
    AutoGunArm.desligar()
    ScreenGui:Destroy()
end)

-- Drag
local function makeDraggable(frame, handle)
    local dragging, dragInput, dragStart, startPos
    local function update(input)
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInput.InputChanged:Connect(function(input)
        if input == dragInput and dragging then update(input) end
    end)
end

makeDraggable(Main, Header)

-- Aplica estado salvo
task.spawn(function()
    task.wait(0.5)
    if CFG.SaveAtivo then
        SaveBtn.setEstado(true)
        if CFG.MotorAtivo then
            MotorBtn.setEstado(true)
            AutoGunArm.ligar()
        end
    end
end)

getgenv().AstraHub = {
    AutoGunArm = AutoGunArm,
    CFG = CFG,
    SaveSystem = SaveSystem,
    UI = ScreenGui,
}

print("[Astra Hub] Interface carregada. v2.1 (arquivo único)")