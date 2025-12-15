local RSGCore = exports['rsg-core']:GetCoreObject()

-- State
local isInSnowZone = false
local currentZone = nil
local lastPickupTime = 0
local isPickingUp = false

-- Animation
local pickupAnimDict = "amb_work@world_human_gravedig@male_a@base"
local pickupAnimName = "base"

-- Prompt
local PickupPromptGroup = GetRandomIntInRange(0, 0xffffff)
local PickupPrompt = nil

----------------------------------------------------------------
-- CHECK IF XMAS MODE
----------------------------------------------------------------
function IsXmasEnabled()
    if Config.EnableXmas ~= nil then
        return Config.EnableXmas
    end
    return false
end

----------------------------------------------------------------
-- CHECK IF IN SNOW ZONE
----------------------------------------------------------------
function CheckIfInSnowZone(coords)
    -- Xmas mode = snow everywhere
    if IsXmasEnabled() then
        return true, "Christmas Mode"
    end
    
    -- Check snow zones
    for _, zone in ipairs(Config.Snowball.SnowZones) do
        local distance = #(coords - zone.coords)
        if distance <= zone.radius then
            return true, zone.name
        end
    end
    
    return false, nil
end

----------------------------------------------------------------
-- CAN PICKUP
----------------------------------------------------------------
function CanPickupSnow()
    -- Check cooldown
    local currentTime = GetGameTimer()
    if currentTime - lastPickupTime < Config.Snowball.Pickup.Cooldown then
        return false
    end
    
    -- Check if already picking up
    if isPickingUp then
        return false
    end
    
    return true
end

----------------------------------------------------------------
-- PICKUP FUNCTION - ADDS TO INVENTORY
----------------------------------------------------------------
function PickupSnowball()
    if not CanPickupSnow() then
        return
    end
    
    isPickingUp = true
    local ped = PlayerPedId()
    
    -- Freeze player
    FreezeEntityPosition(ped, true)
    
    -- Progress bar with animation
    if lib.progressBar({
        duration = 2000,
        label = 'Picking up snow...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = pickupAnimDict,
            clip = pickupAnimName,
        },
    }) then
        -- Success - add to inventory via server
        lastPickupTime = GetGameTimer()
        TriggerServerEvent('rsg-snowball:server:pickupSnowball', Config.Snowball.Pickup.Amount)
    else
        lib.notify({
            title = 'Snowball',
            description = 'Cancelled',
            type = 'error',
            duration = 2000
        })
    end
    
    FreezeEntityPosition(ped, false)
    isPickingUp = false
end

----------------------------------------------------------------
-- PROMPT SETUP
----------------------------------------------------------------
function SetupPickupPrompt()
    PickupPrompt = Citizen.InvokeNative(0x04F97DE45A519419) -- PromptRegisterBegin
    Citizen.InvokeNative(0xB5352B7494A08258, PickupPrompt, Config.Snowball.Keys.Pickup) -- SetControlAction
    local str = CreateVarString(10, "LITERAL_STRING", "Pick Up Snowball")
    Citizen.InvokeNative(0x5DD02A8318420DD7, PickupPrompt, str) -- SetText
    Citizen.InvokeNative(0x8A0FB4D03A630D21, PickupPrompt, true) -- SetEnabled
    Citizen.InvokeNative(0x71215ACCFDE075EE, PickupPrompt, false) -- SetVisible
    Citizen.InvokeNative(0x94073D5CA3F16B7B, PickupPrompt, true) -- SetHoldMode
    Citizen.InvokeNative(0xCC6656799977741B, PickupPrompt, 1000) -- SetHoldDuration
    Citizen.InvokeNative(0x2F11D3A254169EA4, PickupPrompt, PickupPromptGroup, 0) -- SetGroup
    Citizen.InvokeNative(0xF7AA2696A22AD8B9, PickupPrompt) -- PromptRegisterEnd
    
    print("^2[Snowball] Pickup prompt created^0")
end

----------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------
CreateThread(function()
    if not Config.Snowball or not Config.Snowball.Enabled then
        print("^1[Snowball] Config not found or disabled^0")
        return
    end
    
    if not Config.Snowball.Pickup or not Config.Snowball.Pickup.Enabled then
        print("^1[Snowball] Pickup disabled^0")
        return
    end
    
    -- Load animation
    RequestAnimDict(pickupAnimDict)
    while not HasAnimDictLoaded(pickupAnimDict) do
        Wait(10)
    end
    
    -- Setup prompt
    SetupPickupPrompt()
    
    print("^2[Snowball] Pickup system ready!^0")
end)

----------------------------------------------------------------
-- MAIN LOOP
----------------------------------------------------------------
CreateThread(function()
    -- Wait for prompt to be created
    while not PickupPrompt do
        Wait(100)
    end
    
    local wasInZone = false
    
    while true do
        Wait(0)
        
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        
        -- Check if in snow zone
        local inZone, zoneName = CheckIfInSnowZone(coords)
        isInSnowZone = inZone
        currentZone = zoneName
        
        -- Zone enter notification
        if inZone and not wasInZone then
            lib.notify({
                title = 'Snow Zone',
                description = 'You can pick up snowballs here!',
                type = 'inform',
                duration = 4000
            })
        end
        wasInZone = inZone
        
        -- Show/hide prompt based on zone
        if inZone and not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) and not isPickingUp then
            -- Show prompt
            Citizen.InvokeNative(0x71215ACCFDE075EE, PickupPrompt, true) -- SetVisible
            Citizen.InvokeNative(0x8A0FB4D03A630D21, PickupPrompt, CanPickupSnow()) -- SetEnabled
            
            -- Display prompt group
            local groupName = CreateVarString(10, "LITERAL_STRING", "Snow")
            Citizen.InvokeNative(0xC65A45D4453C2627, PickupPromptGroup, groupName, 0) -- PromptSetActiveGroupThisFrame
            
            -- Check if hold completed
            if Citizen.InvokeNative(0xE0F65F0640EF0617, PickupPrompt) then -- PromptHasHoldModeCompleted
                PickupSnowball()
            end
        else
            -- Hide prompt
            Citizen.InvokeNative(0x71215ACCFDE075EE, PickupPrompt, false) -- SetVisible
        end
    end
end)

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------
AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    
    if PickupPrompt then
        Citizen.InvokeNative(0x00EDE88D4D13CF59, PickupPrompt) -- PromptDelete
    end
    
    RemoveAnimDict(pickupAnimDict)
end)