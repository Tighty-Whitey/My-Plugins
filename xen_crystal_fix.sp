#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define AMMO_ENERGY 1

ConVar g_cvArmorRadius;
ConVar g_cvArmorCharge;
ConVar g_cvAmmoRadius;
ConVar g_cvAmmoCharge;
ConVar g_cvHealthRadius;
ConVar g_cvHealthCharge;
ConVar g_cvCheckInterval;

public Plugin myinfo = 
{
    name        = "Xen Crystal Charger Fix",
    author      = "Tighty-Whitey",
    description = "Fixes Xen health, armor & ammo crystals for multiplayer",
    version     = "1.0",
    url         = ""
};

public void OnPluginStart()
{
    g_cvArmorRadius   = CreateConVar("sm_xen_armor_radius",     "175.0", "Radius for ARMOR crystal", _, true, 0.0);
    g_cvArmorCharge   = CreateConVar("sm_xen_armor_charge",     "10",    "Armor points per tick", _, true, 1, true, 100);
    g_cvAmmoRadius    = CreateConVar("sm_xen_ammo_radius",      "320.0", "Radius for AMMO crystal", _, true, 0.0);
    g_cvAmmoCharge    = CreateConVar("sm_xen_ammo_charge",      "10",    "Energy ammo units per tick", _, true, 1);
    g_cvHealthRadius  = CreateConVar("sm_xen_health_radius",    "175.0", "Radius for HEALTH crystal", _, true, 0.0);
    g_cvHealthCharge  = CreateConVar("sm_xen_health_charge",    "5",     "Health points per tick", _, true, 1, true, 100);
    g_cvCheckInterval = CreateConVar("sm_xen_interval",         "1.0",   "Seconds between checks", _, true, 0.1);

    AutoExecConfig(true, "xen_crystal_fix");
    CreateTimer(g_cvCheckInterval.FloatValue, Timer_ChargeCrystals, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ChargeCrystals(Handle timer)
{
    float armorRadius  = g_cvArmorRadius.FloatValue;
    int armorCharge    = g_cvArmorCharge.IntValue;
    float ammoRadius   = g_cvAmmoRadius.FloatValue;
    int ammoCharge     = g_cvAmmoCharge.IntValue;
    float healthRadius = g_cvHealthRadius.FloatValue;
    int healthCharge   = g_cvHealthCharge.IntValue;

    // ===== ARMOR =====
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "prop_hev_charger")) != -1)
    {
        char model[256];
        GetEntPropString(ent, Prop_Data, "m_ModelName", model, sizeof(model));
        if (StrContains(model, "xen_charger_crystal.mdl", false) == -1)
            continue;

        float crystalPos[3];
        GetEntPropVector(ent, Prop_Send, "m_vecAbsOrigin", crystalPos); // <-- FIXED

        for (int client = 1; client <= MaxClients; client++)
        {
            if (!IsClientInGame(client) || !IsPlayerAlive(client))
                continue;

            float playerPos[3];
            GetClientAbsOrigin(client, playerPos);

            if (GetVectorDistance(crystalPos, playerPos) <= armorRadius)
            {
                int currentArmor = GetEntProp(client, Prop_Data, "m_iArmor");
                int newArmor = currentArmor + armorCharge;
                if (newArmor > 100) newArmor = 100;
                SetEntProp(client, Prop_Data, "m_iArmor", newArmor);
            }
        }
    }

    // ===== AMMO =====
    ent = -1;
    while ((ent = FindEntityByClassname(ent, "prop_radiation_charger")) != -1)
    {
        char model[256];
        GetEntPropString(ent, Prop_Data, "m_ModelName", model, sizeof(model));
        if (StrContains(model, "uranium_crystal_large.mdl", false) == -1)
            continue;

        float crystalPos[3];
        GetEntPropVector(ent, Prop_Send, "m_vecAbsOrigin", crystalPos); // <-- FIXED

        for (int client = 1; client <= MaxClients; client++)
        {
            if (!IsClientInGame(client) || !IsPlayerAlive(client))
                continue;

            float playerPos[3];
            GetClientAbsOrigin(client, playerPos);

            if (GetVectorDistance(crystalPos, playerPos) <= ammoRadius)
            {
                GivePlayerAmmo(client, ammoCharge, AMMO_ENERGY);
            }
        }
    }

    // ===== HEALTH =====
    ent = -1;
    while ((ent = FindEntityByClassname(ent, "prop_dynamic_override")) != -1)
    {
        char model[256];
        GetEntPropString(ent, Prop_Data, "m_ModelName", model, sizeof(model));
        if (StrContains(model, "xen_charger_crystal_small.mdl", false) == -1)
            continue;

        float crystalPos[3];
        GetEntPropVector(ent, Prop_Send, "m_vecAbsOrigin", crystalPos); // <-- FIXED

        for (int client = 1; client <= MaxClients; client++)
        {
            if (!IsClientInGame(client) || !IsPlayerAlive(client))
                continue;

            float playerPos[3];
            GetClientAbsOrigin(client, playerPos);

            if (GetVectorDistance(crystalPos, playerPos) <= healthRadius)
            {
                int currentHealth = GetClientHealth(client);
                int newHealth = currentHealth + healthCharge;
                if (newHealth > 100) newHealth = 100;
                SetEntityHealth(client, newHealth);
            }
        }
    }

    return Plugin_Continue;
}