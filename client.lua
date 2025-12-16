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
local promptsDisabled = false
local PickupPrompt = nil
local PickupGroup = nil

----------------------------------------------------------------
-- SNOW ZONE DEFINITIONS (Using Hash Values)
----------------------------------------------------------------

-- Snow Districts (ZoneTypeId 10) - Using hashes from your data
local SnowDistricts = {
    -----120156735,  -- GrizzliesEast (0xF8D68DC1)
    1645618177,  -- GrizzliesWest (0x62162401)
}

-- Snow Locations (ZoneTypeId 12 - TEXT_WRITTEN) - Using hashes
local SnowLocations = {
    -1043500161, -- W_4_ADLER_RANCH
    -2000021141, -- W_4_CAIRN_LODGE
    -1496551068, -- W_4_COLTER
    -545967610,  -- W_4_EWING_BASIN
    1506834348,  -- W_4_MICAHS_HIDEOUT
    1448805167,  -- W_4_FLATTENED_CABIN
    320988519,   -- W_4_COCHINAY
    -930437658,  -- W_4_DORMIN_CREST
    -1692509313, -- W_4_LAKE_DON_JULIO_HOUSE
    -1217490622, -- W_4_BEARTOOTH_BECK
    1418297928,  -- W_4_DEADBOOT_CREEK
    -1114958242, -- W_4_GRANITE_PASS
    -1926488450, -- W_4_THREE_SISTERS
    375900073,   -- W_4_NEKOTI_ROCK
    -218679770,  -- W_4_SPIDER_GORGE (from creek data)
    1246510947,  -- W_4_WINDOW_ROCK
    -1821194396, -- W_4_FACE_ROCK
    -2038495927, -- W_4_TEMPEST_RIM
    1962976783,  -- W_4_DONNER_FALLS
    1645047683,  -- W_4_CLAWSONS_REST
    848488661,   -- W_4_CASTORS_RIDGE
    -962704492,  -- W_4_COTORRA_SPRINGS
    -735849380,  -- W_5_WAPITI_INDIAN_RESERVATION
    1427239788,  -- W_5_VETTERS_ECHO
}

-- Snow Lakes/Ponds (ZoneTypeId 8) - Using hashes
local SnowWater = {
    -1073312073, -- WATER_CAIRN_LAKE
    795414694,   -- WATER_BARROW_LAGOON
    592454541,   -- WATER_LAKE_ISABELLA
    -218679770,  -- WATER_SPIDER_GORGE
    650214731,   -- WATER_BEARTOOTH_BECK
}

-- Snow Printed Text locations (ZoneTypeId 11) - Using hashes
local SnowPrinted = {
    1498241388,  -- P_3_BARROW_LAGOON
    591254234,   -- P_3_CAIRN_LAKE
    1688095983,  -- P_3_SPIDER_GORGE
    1192830049,  -- P_3_AURORA_BASIN
    1806114556,  -- P_3_MOUNT_HAGEN
    -1217490622, -- P_4_BEARTOOTH_BECK
    831787576,   -- P_4_LAKE_ISABELLA
    -2038495927, -- P_4_TEMPEST_RIM
    1962976783,  -- P_4_DONNER_FALLS
    1246510947,  -- P_4_WINDOW_ROCK
    -962704492,  -- P_4_COTORRA_SPRINGS
    -1926488450, -- P_4_THREE_SISTERS
    -1114958242, -- P_4_GRANITE_PASS
   
}
-- Snow weather types
local SnowWeatherHashes = {
    GetHashKey("SNOW"),
    GetHashKey("BLIZZARD"),
    GetHashKey("SNOWLIGHT"),
    GetHashKey("WHITEOUT"),
    GetHashKey("SNOWCLEARING"),
    GetHashKey("GROUNDBLIZZARD"),
    GetHashKey("XMAS"),
}

----------------------------------------------------------------
-- ZONE DETECTION FUNCTIONS
----------------------------------------------------------------

function GetZoneHash(zoneTypeId)
    local ped = PlayerPedId()
    local x, y, z = table.unpack(GetEntityCoords(ped))
    local zoneHash = Citizen.InvokeNative(0x43AD8FC02B429D33, x, y, z, zoneTypeId)
    return zoneHash or 0
end

function IsXmasEnabled()
    return Config.EnableXmas == true
end

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

function IsInSnowyRegion()
    -- Check District (Type 10)
    local district = GetZoneHash(10)
    for _, snowHash in ipairs(SnowDistricts) do
        if district == snowHash then
            return true
        end
    end
    
    -- Check Written Location (Type 12)
    local location = GetZoneHash(12)
    for _, snowHash in ipairs(SnowLocations) do
        if location == snowHash then
            return true
        end
    end
    
    -- Check Printed Location (Type 11)
    local printed = GetZoneHash(11)
    for _, snowHash in ipairs(SnowPrinted) do
        if printed == snowHash then
            return true
        end
    end
    
    -- Check Water (Type 8)
    local water = GetZoneHash(8)
    for _, snowHash in ipairs(SnowWater) do
        if water == snowHash then
            return true
        end
    end
    
    return false
end

function CheckIfInSnowZone(coords)
    -- Priority 1: Christmas mode overrides everything
    if IsXmasEnabled() then
        return true, "Christmas"
    end
    
    -- Priority 2: Check current weather
    if IsSnowWeather() then
        return true, "Snow Weather"
    end
    
    -- Priority 3: Check if in known snowy region (using native zones)
    if IsInSnowyRegion() then
        return true, "Snowy Region"
    end
    
    -- Priority 4: Fallback to config zones if they exist
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

----------------------------------------------------------------
-- UTILITY FUNCTIONS
----------------------------------------------------------------

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
    PromptSetText(PickupPrompt, CreateVarString(10, "LITERAL_STRING", "Pick Up Snowball /snowball to Toggle"))
    PromptSetEnabled(PickupPrompt, true)
    PromptSetVisible(PickupPrompt, true)
    PromptSetHoldMode(PickupPrompt, true)
    PromptSetGroup(PickupPrompt, PickupGroup, 0)
    PromptRegisterEnd(PickupPrompt)
end

----------------------------------------------------------------
-- TOGGLE COMMAND
----------------------------------------------------------------

RegisterCommand('snowball', function()
    promptsDisabled = not promptsDisabled
    
    if promptsDisabled then
        lib.notify({ title = 'Snowball', description = 'Prompts disabled', type = 'inform', duration = 3000 })
    else
        lib.notify({ title = 'Snowball', description = 'Prompts enabled', type = 'success', duration = 3000 })
    end
    
    SetResourceKvp('snowball_prompts_disabled', promptsDisabled and 'true' or 'false')
end, false)



----------------------------------------------------------------
-- LOAD SAVED PREFERENCES
----------------------------------------------------------------

CreateThread(function()
    local savedPrompts = GetResourceKvpString('snowball_prompts_disabled')
    
    if savedPrompts == 'true' then
        promptsDisabled = true
    end
end)

----------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------

CreateThread(function()
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

----------------------------------------------------------------
-- SNOWBALL ACTIONS
----------------------------------------------------------------

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

----------------------------------------------------------------
-- TARGETING FUNCTIONS
----------------------------------------------------------------

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

----------------------------------------------------------------
-- THROWING FUNCTIONS
----------------------------------------------------------------

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
    local zoneCheckInterval = 500
    
    while true do
        Wait(0)
        
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local inVehicle = IsPedInAnyVehicle(ped, false)
        local isDead = IsEntityDead(ped)
        
        local currentTime = GetGameTimer()
        if currentTime - lastZoneCheck > zoneCheckInterval then
            lastZoneCheck = currentTime
            
            local inZone, zoneName = CheckIfInSnowZone(coords)
            isInSnowZone = inZone
            
            if inZone and not wasInZone and not promptsDisabled then
                local message = zoneName == "Snow Weather" and 'Snowy weather - you can pick up snowballs!' or
                               zoneName == "Snowy Region" and 'In snowy region - you can pick up snowballs!' or
                               zoneName == "Christmas" and 'Christmas mode - you can pick up snowballs everywhere!' or
                               'You can pick up snowballs here!'
                lib.notify({ title = 'Snow Zone', description = message, type = 'inform', duration = 4000 })
            end
            wasInZone = inZone
        end
        
        if isInSnowZone and not inVehicle and not isDead and not isPickingUp and not isThrowing and not promptsDisabled then
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
