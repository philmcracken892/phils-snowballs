local RSGCore = exports['rsg-core']:GetCoreObject()


RSGCore.Functions.CreateCallback('rsg-snowball:server:getcount', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then 
        cb(0)
        return
    end
    
    local item = Player.Functions.GetItemByName('snowball')
    if item then
        cb(item.amount or 0)
    else
        cb(0)
    end
end)

RSGCore.Functions.CreateCallback('rsg-snowball:server:checkitem', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then 
        cb(false)
        return
    end
    
    local hasItem = Player.Functions.GetItemByName('snowball')
    cb(hasItem ~= nil and hasItem.amount > 0)
end)


RegisterNetEvent('rsg-snowball:server:pickup', function(amount)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    amount = amount or 10
    
    
    if Player.Functions.AddItem('snowball', amount) then
        TriggerClientEvent('inventory:client:ItemBox', src, RSGCore.Shared.Items['snowball'], "add", amount)
        TriggerClientEvent('ox_lib:notify', src, { 
            title = 'Snowball', 
            description = 'Picked up ' .. amount .. ' snowball(s)', 
            type = 'success' 
        })
    else
        TriggerClientEvent('ox_lib:notify', src, { 
            title = 'Snowball', 
            description = 'Cannot carry more!', 
            type = 'error' 
        })
    end
end)


RegisterNetEvent('rsg-snowball:server:throw', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    
    
    local hasItem = Player.Functions.GetItemByName('snowball')
    if hasItem and hasItem.amount > 0 then
        Player.Functions.RemoveItem('snowball', 1)
        TriggerClientEvent('inventory:client:ItemBox', src, RSGCore.Shared.Items['snowball'], "remove", 1)
    end
end)


RegisterNetEvent('rsg-snowball:server:hit', function(targetId, damage)
    local src = source
    if not RSGCore.Functions.GetPlayer(src) then return end
    if not RSGCore.Functions.GetPlayer(targetId) then return end
    TriggerClientEvent('rsg-snowball:client:hit', targetId, damage)
end)


RSGCore.Functions.CreateUseableItem('snowball', function(source)
    TriggerClientEvent('rsg-snowball:client:use', source)
end)

