local RSGCore = exports['rsg-core']:GetCoreObject()

local snowballModel = nil
local snowballHash = nil
local animDict = nil
local animName = nil

local isReady = false
local isThrowing = false
local isPickingUp = false
local isAiming = false
local targetEntity = nil
local lastPickupTime = 0
local isInSnowZone = false
local activeSnowballs = {}
local cachedSnowballCount = 0

local PickupPrompt = nil
local PickupGroup = nil

-- Snow surface material hashes for RDR2/RedM
local SnowMaterialHashes = {
    -- Common snow hashes
    951832588,
    -1520033454,
    -1942642813,
    -824037923,
    1635579929,
    -1286696947,
    -1885547121,
    -461723753,
    -- Ice hashes
    -897054847,
    126657546,
}

-- Snow weather types
local SnowWeatherHashes = {
    GetHashKey("SNOW"),
    GetHashKey("BLIZZARD"),
    GetHashKey("SNOWLIGHT"),
    GetHashKey("WHITEOUT"),
    GetHashKey("SNOWCLEARING"),
    GetHashKey("GROUNDBLIZZARD"),
    GetHashKey("SLEET"),
}

----------------------------------------------------------------
-- SNOW DETECTION FUNCTIONS
----------------------------------------------------------------
function IsXmasEnabled()
    return Config.EnableXmas == true
end

-- Check if current weather is snowy
function IsSnowWeather()
    local currentWeather = GetPrevWeatherTypeHashName()
    local nextWeather = GetNextWeatherTypeHashName()
    
    for _, weatherHash in ipairs(SnowWeatherHashes) do
        if currentWeather == weatherHash or nextWeather == weatherHash then
            return true
        end
    end
    
    return false
end

-- Check if standing on snow/ice ground using raycast
function IsOnSnowGround()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    
    -- Cast a ray downward to get ground material
    local startPos = vector3(coords.x, coords.y, coords.z + 0.5)
    local endPos = vector3(coords.x, coords.y, coords.z - 2.0)
    
    local rayHandle = StartShapeTestRay(startPos.x, startPos.y, startPos.z, 
                                         endPos.x, endPos.y, endPos.z, 
                                         1, ped, 7)
    
    local retval, hit, endCoords, surfaceNormal, materialHash = GetShapeTestResultIncludingMaterial(rayHandle)
    
    if hit and materialHash then
        for _, snowHash in ipairs(SnowMaterialHashes) do
            if materialHash == snowHash then
                return true
            end
        end
        
        -- Also check using string comparison for material names
        local materialName = tostring(materialHash)
        if string.find(string.lower(materialName), "snow") or string.find(string.lower(materialName), "ice") then
            return true
        end
    end
    
    return false
end

-- Alternative method using ground probe
function IsOnSnowGroundAlt()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    
    -- Use native to get surface material at coordinates
    local groundHash = Citizen.InvokeNative(0x39C0F30A0D8C1A5B, coords.x, coords.y, coords.z, Citizen.ResultAsInteger())
    
    if groundHash then
        for _, snowHash in ipairs(SnowMaterialHashes) do
            if groundHash == snowHash then
                return true
            end
        end
    end
    
    return false
end

-- Check if in known snowy regions based on coordinates (Grizzlies, Ambarino, etc.)
function IsInSnowyRegion()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    
    -- The Grizzlies and Ambarino are generally in the northern part of the map
    -- High elevation + northern coordinates typically mean snow
    
    -- Grizzlies West, Grizzlies East, Ambarino region
    if coords.y > 1200.0 and coords.z > 100.0 then
        return true
    end
    
    -- Colter area
    if coords.x > -1500.0 and coords.x < -1000.0 and coords.y > 1200.0 and coords.y < 1600.0 then
        return true
    end
    
    -- Mount Hagen area
    if coords.x > -2200.0 and coords.x < -1800.0 and coords.y > 800.0 and coords.y < 1200.0 then
        return true
    end
    
    return false
end

-- Main function to check if in snow zone (combines all methods)
function CheckIfInSnowZone(coords)
    -- Priority 1: Christmas mode overrides everything
    if IsXmasEnabled() then
        return true, "Christmas"
    end
    
    -- Priority 2: Check if standing on snow ground
    if IsOnSnowGround() then
        return true, "Snow Ground"
    end
    
    -- Priority 3: Check alternative ground detection
    if IsOnSnowGroundAlt() then
        return true, "Snow Ground"
    end
    
    -- Priority 4: Check current weather
    if IsSnowWeather() then
        return true, "Snow Weather"
    end
    
    -- Priority 5: Check if in known snowy region
    if IsInSnowyRegion() then
        return true, "Snowy Region"
    end
    
    -- Priority 6: Fallback to config zones if they exist
    if Config.Snowball.SnowZones and #Config.Snowball.SnowZones > 0 then
        for _, zone in ipairs(Config.Snowball.SnowZones) do
            local distance = #(coords - zone.coords)
            if distance <= zone.radius then
                return true, zone.name
            end
        end
    end
    
    return false, nil
end

function CanPickupSnow()
    if isPickingUp then return false end
    if GetGameTimer() - lastPickupTime < Config.Snowball.Pickup.Cooldown then return false end
    return true
end

function Normalize(vec)
    local len = #vec
    if len == 0 then return vector3(0, 0, 0) end
    return vector3(vec.x / len, vec.y / len, vec.z / len)
end

function GetCameraDirection()
    local camRot = GetGameplayCamRot(0)
    local pitch = math.rad(camRot.x)
    local yaw = math.rad(camRot.z)
    
    local direction = vector3(
        -math.sin(yaw) * math.cos(pitch),
        math.cos(yaw) * math.cos(pitch),
        math.sin(pitch)
    )
    
    return direction
end

function UpdateSnowballCount()
    RSGCore.Functions.TriggerCallback('rsg-snowball:server:getcount', function(amount)
        cachedSnowballCount = amount or 0
    end)
end

function GetSnowballCount()
    return cachedSnowballCount
end

function HasSnowballs()
    return cachedSnowballCount > 0
end

function CreatePrompts()
    PickupGroup = GetRandomIntInRange(0, 0xffffff)
    
    PickupPrompt = PromptRegisterBegin()
    PromptSetControlAction(PickupPrompt, 0xCEFD9220) -- E key
    PromptSetText(PickupPrompt, CreateVarString(10, "LITERAL_STRING", "Pick Up Snowball"))
    PromptSetEnabled(PickupPrompt, true)
    PromptSetVisible(PickupPrompt, true)
    PromptSetHoldMode(PickupPrompt, true)
    PromptSetGroup(PickupPrompt, PickupGroup, 0)
    PromptRegisterEnd(PickupPrompt)
end

----------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------
CreateThread(function()
    -- Wait for config
    while Config == nil or Config.Snowball == nil do
        Wait(100)
    end
    
    if not Config.Snowball.Enabled then
        return
    end
    
    snowballModel = Config.Snowball.Model
    snowballHash = GetHashKey(snowballModel)
    animDict = Config.Snowball.AnimDict
    animName = Config.Snowball.AnimName
    
    RequestAnimDict(animDict)
    local timeout = 0
    while not HasAnimDictLoaded(animDict) do
        Wait(10)
        timeout = timeout + 10
        if timeout > 5000 then
            return
        end
    end
    
    RequestModel(snowballHash, false)
    timeout = 0
    while not HasModelLoaded(snowballHash) do
        Wait(10)
        timeout = timeout + 10
        if timeout > 5000 then
            return
        end
    end
    
    CreatePrompts()
    
    isReady = true
    
    UpdateSnowballCount()
end)

CreateThread(function()
    while true do
        Wait(2000)
        if isReady then
            UpdateSnowballCount()
        end
    end
end)

function PickupSnowball()
    if not CanPickupSnow() then return end
    
    isPickingUp = true
    local ped = PlayerPedId()
    
    TaskStartScenarioInPlace(ped, `WORLD_HUMAN_CROUCH_INSPECT`, 0, true)
    
    Wait(2000)
    
    lastPickupTime = GetGameTimer()
    TriggerServerEvent('rsg-snowball:server:pickup', Config.Snowball.Pickup.Amount)
    Wait(500)
    UpdateSnowballCount()
    
    ClearPedTasks(ped)
    
    isPickingUp = false
end

function GetNearbyPeds(coords, radius)
    local peds = {}
    local pool = GetGamePool('CPed')
    local myPed = PlayerPedId()
    
    for _, ped in ipairs(pool) do
        if DoesEntityExist(ped) and ped ~= myPed and not IsEntityDead(ped) then
            local pedCoords = GetEntityCoords(ped)
            local distance = #(coords - pedCoords)
            if distance <= radius then
                table.insert(peds, {
                    ped = ped,
                    distance = distance,
                    isPlayer = IsPedAPlayer(ped)
                })
            end
        end
    end
    
    return peds
end

function ApplyDamage(ped, isPlayer)
    if not Config.Snowball.Damage.Enabled then return end
    
    local damage = isPlayer and Config.Snowball.Damage.PlayerDamage or Config.Snowball.Damage.NPCDamage
    
    ApplyDamageToPed(ped, damage, true, true, true)
    
    if not isPlayer then
        ClearPedTasksImmediately(ped)
        SetPedToRagdoll(ped, 1000, 1000, 0, true, true, false)
        
        if not IsEntityDead(ped) then
            Wait(1000)
            TaskSmartFleePed(ped, PlayerPedId(), 100.0, -1, false, false)
        end
    end
    
    if Config.Snowball.Damage.Ragdoll then
        local chance = math.random(1, 100)
        if chance <= Config.Snowball.Damage.RagdollChance then
            SetPedToRagdoll(ped, Config.Snowball.Damage.RagdollDuration, Config.Snowball.Damage.RagdollDuration, 0, true, true, false)
        end
    end
end

function CheckSnowballHit(snowball, targetPed)
    if not DoesEntityExist(snowball) then return true end
    
    local coords = GetEntityCoords(snowball)
    local hasCollided = HasEntityCollidedWithAnything(snowball)
    
    local hitRadius = Config.Snowball.Damage.HitRadius * 1.5
    
    if targetPed and DoesEntityExist(targetPed) then
        local targetCoords = GetEntityCoords(targetPed)
        local distToTarget = #(coords - targetCoords)
        
        if distToTarget <= hitRadius + 0.5 then 
            ApplyDamage(targetPed, IsPedAPlayer(targetPed))
            
            if IsPedAPlayer(targetPed) then
                lib.notify({ title = 'Snowball', description = 'Direct hit on player!', type = 'success', duration = 2000 })
                local playerId = NetworkGetPlayerIndexFromPed(targetPed)
                if playerId then
                    TriggerServerEvent('rsg-snowball:server:hit', GetPlayerServerId(playerId), Config.Snowball.Damage.PlayerDamage)
                end
            else
                lib.notify({ title = 'Snowball', description = 'Direct hit on NPC!', type = 'success', duration = 2000 })
            end
            
            DeleteEntity(snowball)
            return true
        end
    end
    
    local nearbyPeds = GetNearbyPeds(coords, hitRadius)
    
    for _, pedData in ipairs(nearbyPeds) do
        ApplyDamage(pedData.ped, pedData.isPlayer)
        
        if pedData.isPlayer then
            lib.notify({ title = 'Snowball', description = 'Hit a player!', type = 'success', duration = 2000 })
            local playerId = NetworkGetPlayerIndexFromPed(pedData.ped)
            if playerId then
                TriggerServerEvent('rsg-snowball:server:hit', GetPlayerServerId(playerId), Config.Snowball.Damage.PlayerDamage)
            end
        else
            lib.notify({ title = 'Snowball', description = 'Hit an NPC!', type = 'success', duration = 2000 })
        end
        
        DeleteEntity(snowball)
        return true
    end
    
    if hasCollided then
        DeleteEntity(snowball)
        return true
    end
    
    return false
end

CreateThread(function()
    while true do
        if #activeSnowballs > 0 then
            Wait(0)
            for i = #activeSnowballs, 1, -1 do
                local data = activeSnowballs[i]
                if GetGameTimer() - data.createdAt > 10000 or not DoesEntityExist(data.entity) then
                    if DoesEntityExist(data.entity) then DeleteEntity(data.entity) end
                    table.remove(activeSnowballs, i)
                elseif CheckSnowballHit(data.entity, data.targetPed) then
                    table.remove(activeSnowballs, i)
                end
            end
        else
            Wait(500)
        end
    end
end)

function GetNearbyTargets(radius, includeNPCs)
    local targets = {}
    local myPed = PlayerPedId()
    local myPos = GetEntityCoords(myPed)
    
    local pool = GetGamePool('CPed')
    
    for _, ped in ipairs(pool) do
        if DoesEntityExist(ped) and ped ~= myPed and not IsEntityDead(ped) then
            local pedPos = GetEntityCoords(ped)
            local distance = #(myPos - pedPos)
            
            if distance <= radius then
                local isPlayer = IsPedAPlayer(ped)
                
                if isPlayer or includeNPCs then
                    local raycast = StartShapeTestRay(myPos.x, myPos.y, myPos.z + 0.5, 
                                                      pedPos.x, pedPos.y, pedPos.z + 0.5, 
                                                      -1, myPed, 0)
                    local _, hit, _, _, entityHit = GetShapeTestResult(raycast)
                    
                    if not hit or entityHit == ped then
                        table.insert(targets, {
                            ped = ped,
                            pos = pedPos,
                            distance = distance,
                            isPlayer = isPlayer
                        })
                    end
                end
            end
        end
    end
    
    table.sort(targets, function(a, b) return a.distance < b.distance end)
    return targets
end

function GetEntityInCrosshair()
    local nearbyTargets = GetNearbyTargets(Config.Snowball.AimDistance, true)
    local bestTarget = nil
    local bestScore = -1
    
    for _, target in ipairs(nearbyTargets) do
        local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(target.pos.x, target.pos.y, target.pos.z + 1.0)
        if onScreen and screenX and screenY then
            local centerDist = math.sqrt((screenX - 0.5)^2 + (screenY - 0.5)^2)
            if centerDist < 0.25 then
                local score = (1 - centerDist) * 100 + (1 - target.distance / Config.Snowball.AimDistance) * 50
                
                if target.isPlayer then
                    score = score + 10
                end
                if score > bestScore then
                    bestScore = score
                    bestTarget = target
                end
            end
        end
    end
    
    return bestTarget
end

local function DrawTexture(textureStreamed, textureName, x, y, width, height, rotation, r, g, b, a)
    if not HasStreamedTextureDictLoaded(textureStreamed) then
        RequestStreamedTextureDict(textureStreamed, false)
    else
        DrawSprite(textureStreamed, textureName, x, y, width, height, rotation, r, g, b, a, false)
    end
end

function DrawTargetMarker(target)
    local pos = GetEntityCoords(target.ped)
    local r, g, b = 255, 50, 50 
    
    if not target.isPlayer then
        r, g, b = 255, 150, 50 
    end
    
    local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z + 0.5)
    if onScreen then
        DrawTexture("overhead", "overhead_marked_for_death", screenX, screenY, 0.02, 0.035, 0.0, r, g, b, 240)
    end
end

function SpawnSnowball(ped)
    local pos = GetEntityCoords(ped)
    local velocity
    local throwForce = Config.Snowball.ThrowForce
    local targetPed = nil
    
    if targetEntity and targetEntity.ped and DoesEntityExist(targetEntity.ped) then
        targetPed = targetEntity.ped
        local targetPos = GetEntityCoords(targetEntity.ped)
        local distance = #(targetPos - pos)
        
        targetPos = vector3(targetPos.x, targetPos.y, targetPos.z + 0.5)
        
        local direction = Normalize(targetPos - pos)
        
        local arc = math.max(0.2, distance * 0.015)
        direction = vector3(direction.x, direction.y, direction.z + arc)
        
        local force = throwForce + (distance * 0.8)
        velocity = Normalize(direction) * force
    else
        local camDir = GetCameraDirection()
        camDir = vector3(camDir.x, camDir.y, camDir.z + 0.2)
        velocity = Normalize(camDir) * throwForce
    end
    
    local forward = GetEntityForwardVector(ped)
    local spawnPos = vector3(
        pos.x + forward.x,
        pos.y + forward.y,
        pos.z + 1.2
    )
    
    local snowball = CreateObject(snowballHash, spawnPos.x, spawnPos.y, spawnPos.z, true, true, false)
    if not DoesEntityExist(snowball) then return false end
    
    SetEntityVisible(snowball, true)
    SetEntityCollision(snowball, true, true)
    SetEntityDynamic(snowball, true)
    FreezeEntityPosition(snowball, false)
    
    ActivatePhysics(snowball)
    Wait(50)
    
    SetEntityVelocity(snowball, velocity.x, velocity.y, velocity.z)
    
    table.insert(activeSnowballs, { 
        entity = snowball, 
        createdAt = GetGameTimer(),
        targetPed = targetPed
    })
    
    return true
end

function ThrowSnowball()
    if not isReady or isThrowing then return false end
    
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then return false end
    
    if cachedSnowballCount <= 0 then
        lib.notify({ title = 'Snowball', description = 'No snowballs in inventory!', type = 'error', duration = 3000 })
        return false
    end
    
    isThrowing = true
    
    TriggerServerEvent('rsg-snowball:server:throw')
    cachedSnowballCount = cachedSnowballCount - 1
    
    TaskPlayAnim(ped, animDict, animName, 1.0, 1.0, 1000, 0, 0, false, false, false, false, false)
    
    Wait(400)
    
    SpawnSnowball(ped)
    
    Wait(600)
    
    ClearPedTasks(ped)
    
    targetEntity = nil
    isThrowing = false
    
    UpdateSnowballCount()
    
    return true
end

function ToggleAiming()
    if cachedSnowballCount <= 0 then
        lib.notify({ title = 'Snowball', description = 'No snowballs to aim!', type = 'error', duration = 3000 })
        isAiming = false
        targetEntity = nil
        return
    end
    
    isAiming = not isAiming
    if isAiming then
        lib.notify({ title = 'Snowball', description = 'Aim mode ON - Target NPCs & Players', type = 'success', duration = 2000 })
    else
        lib.notify({ title = 'Snowball', description = 'Aim mode OFF', type = 'error', duration = 2000 })
        targetEntity = nil
    end
end

----------------------------------------------------------------
-- KEYBIND CONTROLS
----------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(0)
        
        if isReady and not isThrowing and not isPickingUp then
            if IsControlJustPressed(0, 0x760A9C6F) then -- G key
                ThrowSnowball()
            end
            
            if IsControlJustPressed(0, 0x4CC0E2FE) then -- B key
                ToggleAiming()
            end
            
            if isAiming then
                if IsControlJustPressed(0, 0x3076E97C) then -- Mouse wheel up
                    local targets = GetNearbyTargets(Config.Snowball.AimDistance, true)
                    if #targets > 1 then
                        local currentIndex = 0
                        for i, t in ipairs(targets) do
                            if targetEntity and t.ped == targetEntity.ped then
                                currentIndex = i
                                break
                            end
                        end
                        
                        currentIndex = currentIndex + 1
                        if currentIndex > #targets then currentIndex = 1 end
                        targetEntity = targets[currentIndex]
                    end
                end
            end
        else
            Wait(100) 
        end
    end
end)

----------------------------------------------------------------
-- MAIN PROMPT LOOP
----------------------------------------------------------------
CreateThread(function()
    while not isReady do
        Wait(100)
    end
    
    local wasInZone = false
    local lastZoneCheck = 0
    local zoneCheckInterval = 500 -- Check every 500ms instead of every frame
    
    while true do
        Wait(0)
        
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local inVehicle = IsPedInAnyVehicle(ped, false)
        local isDead = IsEntityDead(ped)
        
        -- Only check zone status periodically to save performance
        local currentTime = GetGameTimer()
        if currentTime - lastZoneCheck > zoneCheckInterval then
            lastZoneCheck = currentTime
            
            local inZone, zoneName = CheckIfInSnowZone(coords)
            isInSnowZone = inZone
            
            if inZone and not wasInZone then
                local message = zoneName == "Snow Ground" and 'Standing on snow - you can pick up snowballs!' or 
                               zoneName == "Snow Weather" and 'Snowy weather - you can pick up snowballs!' or
                               zoneName == "Snowy Region" and 'In snowy region - you can pick up snowballs!' or
                               'You can pick up snowballs here!'
                lib.notify({ title = 'Snow Zone', description = message, type = 'inform', duration = 4000 })
            end
            wasInZone = inZone
        end
        
        if isInSnowZone and not inVehicle and not isDead and not isPickingUp and not isThrowing then
            if PickupPrompt and PickupGroup then
                local label = CreateVarString(10, "LITERAL_STRING", "Snow")
                PromptSetActiveGroupThisFrame(PickupGroup, label)
                PromptSetEnabled(PickupPrompt, CanPickupSnow())
                
                if PromptHasHoldModeCompleted(PickupPrompt) then
                    CreateThread(PickupSnowball)
                end
            end
        end
        
        if isAiming and cachedSnowballCount <= 0 then
            isAiming = false
            targetEntity = nil
        end
        
        if isAiming and not isThrowing and cachedSnowballCount > 0 then
            targetEntity = GetEntityInCrosshair()
            if targetEntity then
                DrawTargetMarker(targetEntity)
            end
        end
    end
end)

----------------------------------------------------------------
-- HUD
----------------------------------------------------------------
CreateThread(function()
    while true do
        if Config.Snowball and Config.Snowball.ShowHUD and isReady and cachedSnowballCount > 0 then
            Wait(0)
            
            local r, g, b = 255, 255, 255
            local bgR, bgG, bgB = 0, 0, 0
            
            if isAiming then
                r, g, b = 100, 200, 255
                bgR, bgG, bgB = 20, 50, 80
            end
            
            local hudX = 0.5
            local hudY = 0.85
            
            DrawTexture("generic_textures", "default_pedshot", hudX, hudY + 0.03, 0.15, 0.1, 0.0, bgR, bgG, bgB, 180)
            
            SetTextScale(0.45, 0.45)
            SetTextColor(r, g, b, 255)
            SetTextCentre(true)
            SetTextDropshadow(1, 0, 0, 0, 255)
            local countStr = CreateVarString(10, "LITERAL_STRING", "Snowballs: " .. cachedSnowballCount)
            DisplayText(countStr, hudX, hudY)
            
            SetTextScale(0.28, 0.28)
            SetTextColor(r, g, b, 200)
            SetTextCentre(true)
            SetTextDropshadow(1, 0, 0, 0, 255)
            
            if isAiming then
                local aimStr = CreateVarString(10, "LITERAL_STRING", "[G] Throw    [B] Cancel")
                DisplayText(aimStr, hudX, hudY + 0.04)
            else
                local normalStr = CreateVarString(10, "LITERAL_STRING", "[G] Throw    [B] Aim")
                DisplayText(normalStr, hudX, hudY + 0.04)
            end
        else
            Wait(500)
        end
    end
end)

----------------------------------------------------------------
-- EVENTS
----------------------------------------------------------------
RegisterNetEvent('rsg-snowball:client:hit', function(damage)
    local ped = PlayerPedId()
    ApplyDamageToPed(ped, damage, false)
    
    if Config.Snowball.Damage.Ragdoll then
        local chance = math.random(1, 100)
        if chance <= Config.Snowball.Damage.RagdollChance then
            SetPedToRagdoll(ped, Config.Snowball.Damage.RagdollDuration, Config.Snowball.Damage.RagdollDuration, 0, false, false, false)
        end
    end
    
    lib.notify({ title = 'Snowball', description = 'You got hit!', type = 'error', duration = 2000 })
end)

RegisterNetEvent('rsg-snowball:client:use', function()
    ThrowSnowball()
end)

RegisterNetEvent('rsg-snowball:client:updatecount', function()
    UpdateSnowballCount()
end)

RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function()
    activeSnowballs = {}
    UpdateSnowballCount()
end)

----------------------------------------------------------------
-- EXPORTS
----------------------------------------------------------------
exports('GetSnowballCount', GetSnowballCount)
exports('ThrowSnowball', ThrowSnowball)
exports('HasSnowballs', HasSnowballs)
exports('IsInSnowZone', function() return isInSnowZone end)

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------
AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    
    for _, data in ipairs(activeSnowballs) do
        if DoesEntityExist(data.entity) then DeleteEntity(data.entity) end
    end
    
    if PickupPrompt then PromptDelete(PickupPrompt) end
    
    if animDict then RemoveAnimDict(animDict) end
    if snowballHash then SetModelAsNoLongerNeeded(snowballHash) end
end)
