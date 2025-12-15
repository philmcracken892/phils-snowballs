Config = {}

Config.EnableXmas = false -- Set to true to allow snowball pickup everywhere

Config.Snowball = {
    Enabled = true,
    Model = "p_cs_snowball01x",
    
    -- Throwing animation
    AnimDict = "mech_weapons_thrown@base",
    AnimName = "throw_m_fb_stand",
    
    ThrowForce = 60.0,
    AimDistance = 50.0,
    DefaultAmount = 10,
    MaxAmount = 10,
    ShowHUD = true,
    
    Pickup = {
        Cooldown = 1000,  -- ms between pickups
        Amount = 1,       -- snowballs per pickup
    },
    
    Damage = {
        Enabled = true,
        PlayerDamage = 5,
        NPCDamage = 10,
        HitRadius = 5.5,
        Ragdoll = true,
        RagdollChance = 30,
        RagdollDuration = 2000,
    },
    
    SnowZones = {
        { name = "Colter", coords = vector3(vector3(-734.43, 1849.86, 330.13)), radius = 500.0 },
        { name = "Cairn Lake", coords = vector3(-1320.0, 1950.0, 260.0), radius = 550.0 },
        -- Add more zones as needed
    },
}