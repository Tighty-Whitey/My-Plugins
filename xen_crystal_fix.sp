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

Handle g_hTimer = null;

#define ARMOR_PROP "m_ArmorValue"

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
    g_cvArmorCharge   = CreateConVar("sm_xen_armor_charge",     "10",    "Armor points per tick", _, true, 1.0, true, 100.0);
    g_cvAmmoRadius    = CreateConVar("sm_xen_ammo_radius",      "320.0", "Radius for AMMO crystal", _, true, 0.0);
    g_cvAmmoCharge    = CreateConVar("sm_xen_ammo_charge",      "10",    "Energy ammo units per tick", _, true, 1.0);
    g_cvHealthRadius  = CreateConVar("sm_xen_health_radius",    "175.0", "Radius for HEALTH crystal", _, true, 0.0);
    g_cvHealthCharge  = CreateConVar("sm_xen_health_charge",    "5",     "Health points per tick", _, true, 1.0, true, 100.0);
    g_cvCheckInterval = CreateConVar("sm_xen_interval",         "1.0",   "Seconds between checks", _, true, 0.1);

    g_cvCheckInterval.AddChangeHook(OnIntervalChanged);
    AutoExecConfig(true, "xen_crystal_fix");
}

public void OnMapStart()
{
    if (g_hTimer != null)
    {
        KillTimer(g_hTimer);
        g_hTimer = null;
    }
    g_hTimer = CreateTimer(g_cvCheckInterval.FloatValue, Timer_ChargeCrystals, _, TIMER_REPEAT);
}

public void OnMapEnd()
{
    if (g_hTimer != null)
    {
        KillTimer(g_hTimer);
        g_hTimer = null;
    }
}

public void OnIntervalChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (g_hTimer != null)
    {
        KillTimer(g_hTimer);
        g_hTimer = null;
    }
    g_hTimer = CreateTimer(g_cvCheckInterval.FloatValue, Timer_ChargeCrystals, _, TIMER_REPEAT);
}

// ---------- safe absolute origin ----------
stock void GetEntityAbsOrigin(int entity, float origin[3])
{
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
    int parent = GetEntPropEnt(entity, Prop_Data, "m_hParent");
    if (parent != -1)
    {
        float parentOrigin[3];
        GetEntPropVector(parent, Prop_Send, "m_vecOrigin", parentOrigin);
        origin[0] += parentOrigin[0];
        origin[1] += parentOrigin[1];
        origin[2] += parentOrigin[2];
    }
}

// ---------- Main timer ----------
public Action Timer_ChargeCrystals(Handle timer)
{
    if (g_hTimer == null)
        return Plugin_Stop;

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
        GetEntityAbsOrigin(ent, crystalPos);

        for (int client = 1; client <= MaxClients; client++)
        {
            if (!IsClientInGame(client) || !IsPlayerAlive(client))
                continue;

            float playerPos[3];
            GetClientAbsOrigin(client, playerPos);

            if (GetVectorDistance(crystalPos, playerPos) <= armorRadius)
            {
                int currentArmor = GetEntProp(client, Prop_Data, ARMOR_PROP);
                int newArmor = currentArmor + armorCharge;
                if (newArmor > 100) newArmor = 100;
                SetEntProp(client, Prop_Data, ARMOR_PROP, newArmor);
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
        GetEntityAbsOrigin(ent, crystalPos);

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
        GetEntityAbsOrigin(ent, crystalPos);

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