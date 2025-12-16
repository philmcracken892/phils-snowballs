Config = {}

Config.EnableXmas = false -- Set to true to allow snowball pickup everywhere (overrides all detection)

Config.Snowball = {
    Enabled = true,
    Model = "p_cs_snowball01x",
    
    -- Throwing animation
    AnimDict = "mech_weapons_thrown@base",
    AnimName = "throw_m_fb_stand",
    
    ThrowForce = 60.0,
    AimDistance = 60.0,
    ShowHUD = true,
    
    Pickup = {
        Cooldown = 1000,  -- ms between pickups
        Amount = 1,       -- snowballs per pickup
    },
    
    Damage = {
        Enabled = true,
        PlayerDamage = 5,
        NPCDamage = 10,
        HitRadius = 10.5,
        Ragdoll = true,
        RagdollChance = 30,
        RagdollDuration = 2000,
    },
    
    -- OPTIONAL: Manual zones as fallback (can be empty or removed entirely)
    -- Only used if automatic snow detection fails
    SnowZones = {},
}
