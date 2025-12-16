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


function IsXmasEnabled()
    return Config.EnableXmas == true
end

function CheckIfInSnowZone(coords)
    if IsXmasEnabled() then
        return true, "Christmas"
    end
    
    for _, zone in ipairs(Config.Snowball.SnowZones) do
        local distance = #(coords - zone.coords)
        if distance <= zone.radius then
            return true, zone.name
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
    
    if lib.progressBar({
        duration = 2000,
        label = 'Picking up snow...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    }) then
        lastPickupTime = GetGameTimer()
        
        
        TriggerServerEvent('rsg-snowball:server:pickup', Config.Snowball.Pickup.Amount)
        Wait(500)
        UpdateSnowballCount()
    end
    
    
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
    -- Ragdoll chance for all peds
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
    local nearbyTargets = GetNearbyTargets(Config.Snowball.AimDistance, true) -- true = include NPCs
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

function DrawTargetMarker(target)
    local pos = GetEntityCoords(target.ped)
    local r, g, b = 255, 50, 50 
    
    if not target.isPlayer then
        r, g, b = 255, 150, 50 
    end
    
    DrawMarker(0x94FDAE17, pos.x, pos.y, pos.z + 1.3, 0, 0, 0, 0, 0, 0, 0.4, 0.4, 0.4, r, g, b, 200, false, false, 2, false, nil, nil, false)
    
   
    local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z + 1.5)
    if onScreen then
        SetTextScale(0.3, 0.3)
        SetTextColor(r, g, b, 255)
        SetTextCentre(true)
        SetTextDropshadow(1, 0, 0, 0, 255)
        local text = target.isPlayer and "PLAYER" or "NPC"
        text = text .. " [" .. math.floor(target.distance) .. "m]"
        local str = CreateVarString(10, "LITERAL_STRING", text)
        DisplayText(str, screenX, screenY)
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
            -- G key to throw
            if IsControlJustPressed(0, 0x760A9C6F) then -- G key
                ThrowSnowball()
            end
            
            -- B key to toggle aim
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
    
    while true do
        Wait(0)
        
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local inVehicle = IsPedInAnyVehicle(ped, false)
        local isDead = IsEntityDead(ped)
        
        
        local inZone, zoneName = CheckIfInSnowZone(coords)
        isInSnowZone = inZone
        
       
        if inZone and not wasInZone then
            lib.notify({ title = 'Snow Zone', description = 'You can pick up snowballs here!', type = 'inform', duration = 4000 })
        end
        wasInZone = inZone
        
        
        if inZone and not inVehicle and not isDead and not isPickingUp and not isThrowing then
            if PickupPrompt and PickupGroup then
                local label = CreateVarString(10, "LITERAL_STRING", "Snow")
                PromptSetActiveGroupThisFrame(PickupGroup, label)
                PromptSetEnabled(PickupPrompt, CanPickupSnow())
                
                if PromptHasHoldModeCompleted(PickupPrompt) then
                    CreateThread(PickupSnowball)
                end
            end
        end
        
        -- AUTO-DISABLE AIM MODE WHEN NO SNOWBALLS
        if isAiming and cachedSnowballCount <= 0 then
            isAiming = false
            targetEntity = nil
        end
        
        -- Only draw target marker if aiming AND have snowballs
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
            
            local text
            if isAiming then
                text = "[AIM MODE] Snowballs: " .. cachedSnowballCount .. " | G=Throw B=Aim"
            else
                text = "Snowballs: " .. cachedSnowballCount .. " | G=Throw B=Aim"
            end
            
            SetTextScale(0.35, 0.35)
            SetTextColor(255, 255, 255, 255)
            SetTextCentre(true)
            SetTextDropshadow(1, 0, 0, 0, 255)
            local str = CreateVarString(10, "LITERAL_STRING", text)
            DisplayText(str, 0.5, 0.9)
        else
            Wait(500)
        end
    end
end)

----------------------------------------------------------------
-- EVENTS & REMAINING CODE STAYS THE SAME
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
