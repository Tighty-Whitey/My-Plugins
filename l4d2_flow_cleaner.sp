// l4d2_flow_cleaner.sp
// Removes far-behind AI infected not closing the gap.

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "1.0"
#define LOG_FILE "l4d2_flow_cleaner.log"

ConVar g_cvEnable, g_cvInterval, g_cvDist, g_cvMinTime, g_cvMinReduce, g_cvDebug, g_cvAdminFlag;
Handle g_hTimer;
StringMap g_LastDistMap;
StringMap g_LastTimeMap;
StringMap g_SpawnTimeMap;
char g_sLogPath[PLATFORM_MAX_PATH];

static const char ZOMBIE_CLASS_NAMES[][] =
{
    "unknown", "smoker", "boomer", "hunter", "spitter", "jockey", "charger", "witch", "tank"
};

public Plugin myinfo = 
{
    name = "[L4D2] Flow Cleaner",
    author = "Tighty-Whitey",
    description = "Removes stuck AI infected far behind the leading survivor",
    version = "1.0",
    url = ""
};

public void OnPluginStart()
{
    g_LastDistMap = new StringMap();
    g_LastTimeMap = new StringMap();
    g_SpawnTimeMap = new StringMap();
    BuildPath(Path_SM, g_sLogPath, sizeof(g_sLogPath), "logs/%s", LOG_FILE);

    g_cvEnable = CreateConVar("l4d2_flow_cleaner_enable", "1", "Enable plugin", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvInterval = CreateConVar("l4d2_flow_cleaner_interval", "15.0", "Check interval in seconds", FCVAR_NOTIFY, true, 1.0, true, 60.0);
    g_cvDist = CreateConVar("l4d2_flow_cleaner_dist", "7000.0", "Distance threshold from leader (units)", FCVAR_NOTIFY, true, 100.0, true, 20000.0);
    g_cvMinTime = CreateConVar("l4d2_flow_cleaner_mintime", "45.0", "Minimum age after spawn before removal (seconds)", FCVAR_NOTIFY, true, 0.0, true, 120.0);
    g_cvMinReduce = CreateConVar("l4d2_flow_cleaner_minreduce", "1200.0", "Min distance reduction to be 'approaching'", FCVAR_NOTIFY, true, 0.0, true, 9999.0);
    g_cvDebug = CreateConVar("l4d2_flow_cleaner_debug", "0", "Debug: 0=off, 1=log to file, 2=log+admin chat", FCVAR_NOTIFY, true, 0.0, true, 2.0);
    g_cvAdminFlag = CreateConVar("l4d2_flow_cleaner_admin_flag", "z", "Admin flag for chat messages", FCVAR_NOTIFY);

    AutoExecConfig(true, "l4d2_flow_cleaner");

    // Conditional chat startup – only when debug >= 2
    if (g_cvDebug.IntValue >= 2)
        PrintToChatAll("\x03[Cleaner]\x01 Plugin loaded. Debug level = %d", g_cvDebug.IntValue);

    OnConVarChanged(null, "", "");
    g_cvEnable.AddChangeHook(OnConVarChanged);
    g_cvInterval.AddChangeHook(OnConVarChanged);

    HookEvent("entity_killed", Event_EntityKilled, EventHookMode_Pre);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
    HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
    // Clear stale data on new map
    g_LastDistMap.Clear();
    g_LastTimeMap.Clear();
    g_SpawnTimeMap.Clear();

    // Restart the timer
    if (g_hTimer != null)
    {
        KillTimer(g_hTimer);
        g_hTimer = null;
    }

    if (g_cvEnable.BoolValue)
    {
        float interval = g_cvInterval.FloatValue;
        g_hTimer = CreateTimer(interval, Timer_Clean, _, TIMER_REPEAT);
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "infected") || StrEqual(classname, "witch"))
    {
        char key[16];
        Format(key, sizeof(key), "%d", entity);
        g_SpawnTimeMap.SetValue(key, GetGameTime(), true);
    }
}

public void OnEntityDestroyed(int entity)
{
    if (entity <= 0) return;
    char classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));
    if (!StrEqual(classname, "infected") && !StrEqual(classname, "witch"))
        return;

    char key[16];
    Format(key, sizeof(key), "%d", entity);
    g_LastDistMap.Remove(key);
    g_LastTimeMap.Remove(key);
    g_SpawnTimeMap.Remove(key);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client < 1 || client > MaxClients) return;
    if (!IsClientInGame(client)) return;
    if (!IsPlayerAlive(client)) return;

    char key[16];
    Format(key, sizeof(key), "%d", client);

    g_LastDistMap.Remove(key);
    g_LastTimeMap.Remove(key);
    g_SpawnTimeMap.Remove(key);

    if (GetClientTeam(client) != 3) return;
    if (!IsFakeClient(client)) return;

    g_SpawnTimeMap.SetValue(key, GetGameTime(), true);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client < 1 || client > MaxClients) return;
    char key[16];
    Format(key, sizeof(key), "%d", client);
    g_LastDistMap.Remove(key);
    g_LastTimeMap.Remove(key);
    g_SpawnTimeMap.Remove(key);
}

public void Event_EntityKilled(Event event, const char[] name, bool dontBroadcast)
{
    int entity = event.GetInt("entindex_killed");
    if (entity <= 0) return;
    char key[16];
    Format(key, sizeof(key), "%d", entity);
    g_LastDistMap.Remove(key);
    g_LastTimeMap.Remove(key);
    g_SpawnTimeMap.Remove(key);
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    CreateTimer(0.1, Timer_StartStop, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_StartStop(Handle timer)
{
    if (g_hTimer != null)
    {
        KillTimer(g_hTimer);
        g_hTimer = null;
    }

    if (g_cvEnable.BoolValue)
    {
        // Clear stale data on re‑enable
        g_LastDistMap.Clear();
        g_LastTimeMap.Clear();
        g_SpawnTimeMap.Clear();

        float interval = g_cvInterval.FloatValue;
        g_hTimer = CreateTimer(interval, Timer_Clean, _, TIMER_REPEAT);
    }
    return Plugin_Stop;
}

public void OnMapEnd()
{
    g_LastDistMap.Clear();
    g_LastTimeMap.Clear();
    g_SpawnTimeMap.Clear();
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_LastDistMap.Clear();
    g_LastTimeMap.Clear();
    g_SpawnTimeMap.Clear();
}

int GetLeadingSurvivor(float leaderPos[3])
{
    int leader = L4D_GetHighestFlowSurvivor();
    if (leader > 0 && leader <= MaxClients && IsClientInGame(leader) && GetClientTeam(leader) == 2 && IsPlayerAlive(leader))
    {
        GetClientAbsOrigin(leader, leaderPos);
        return leader;
    }
    return -1;
}

void GetEntityPosition(int entity, float pos[3])
{
    if (entity > MaxClients)
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
    else
        GetClientAbsOrigin(entity, pos);
}

bool IsEntityTrackable(int entity)
{
    if (entity > MaxClients)
    {
        // Already filtered by FindEntityByClassname
        return true;
    }
    else
    {
        if (!IsClientInGame(entity)) return false;
        if (GetClientTeam(entity) != 3) return false;
        if (!IsFakeClient(entity)) return false;
        if (!IsPlayerAlive(entity)) return false;
        return true;
    }
}

void GetEntityDisplayName(int entity, char[] buffer, int maxlen)
{
    if (entity > MaxClients)
    {
        GetEntityClassname(entity, buffer, maxlen);
    }
    else
    {
        int zclass = GetEntProp(entity, Prop_Send, "m_zombieClass");
        if (zclass >= 1 && zclass <= 8)
            strcopy(buffer, maxlen, ZOMBIE_CLASS_NAMES[zclass]);
        else
            strcopy(buffer, maxlen, "player");
    }
}

void KillEntity(int entity, const char[] msg, int debug, ArrayList admins)
{
    if (entity > MaxClients)
    {
        if (!IsValidEntity(entity))
            return;
        RemoveEntity(entity);
    }
    else
    {
        if (!IsClientInGame(entity))
            return;
        ForcePlayerSuicide(entity);
    }

    if (debug >= 1)
        LogToFile(g_sLogPath, msg);
    if (debug >= 2 && admins != null)
    {
        for (int j = 0; j < admins.Length; j++)
        {
            int client = admins.Get(j);
            PrintToChat(client, "\x03[Cleaner]\x01 %s", msg);
        }
    }
}

void ProcessEntity(int entity, float leaderPos[3], float distThreshold, float minAge, float minReduce, int debug, float curTime, float interval, ArrayList admins, int &killed)
{
    if (!IsEntityTrackable(entity))
        return;

    char key[16];
    Format(key, sizeof(key), "%d", entity);

    float spawnTime;
    if (!g_SpawnTimeMap.GetValue(key, spawnTime))
    {
        g_SpawnTimeMap.SetValue(key, curTime, true);
        return;
    }

    float age = curTime - spawnTime;
    if (age < minAge)
        return;

    float pos[3];
    GetEntityPosition(entity, pos);
    float distToLeader = GetVectorDistance(pos, leaderPos);

    if (distToLeader < distThreshold)
    {
        g_LastDistMap.Remove(key);
        g_LastTimeMap.Remove(key);
        return;
    }

    float lastDist, lastTime;
    bool hasDist = g_LastDistMap.GetValue(key, lastDist);
    bool hasTime = g_LastTimeMap.GetValue(key, lastTime);

    if (hasDist && hasTime)
    {
        float elapsed = curTime - lastTime;
        if (elapsed >= interval * 0.9)
        {
            float reduction = lastDist - distToLeader;
            char displayName[64];
            GetEntityDisplayName(entity, displayName, sizeof(displayName));
            char msg[256];

            if (reduction < minReduce)
            {
                Format(msg, sizeof(msg), "[Cleaner] Killed %s %d (age %.1f, dist %.1f, reduction %.1f)", 
                       displayName, entity, age, distToLeader, reduction);

                KillEntity(entity, msg, debug, admins);

                g_LastDistMap.Remove(key);
                g_LastTimeMap.Remove(key);
                g_SpawnTimeMap.Remove(key);
                killed++;
                return;
            }
            else
            {
                Format(msg, sizeof(msg), "[Cleaner] %s %d updating: dist=%.1f, reduction=%.1f", displayName, entity, distToLeader, reduction);

                if (debug >= 1)
                    LogToFile(g_sLogPath, msg);
                if (debug >= 2 && admins != null)
                {
                    for (int j = 0; j < admins.Length; j++)
                    {
                        int client = admins.Get(j);
                        PrintToChat(client, "\x03[Cleaner]\x01 %s", msg);
                    }
                }

                g_LastDistMap.SetValue(key, distToLeader, true);
                g_LastTimeMap.SetValue(key, curTime, true);
            }
        }
    }
    else
    {
        g_LastDistMap.SetValue(key, distToLeader, true);
        g_LastTimeMap.SetValue(key, curTime, true);
        if (debug >= 1)
        {
            char displayName[64];
            GetEntityDisplayName(entity, displayName, sizeof(displayName));
            char msg[256];
            Format(msg, sizeof(msg), "[Cleaner] Stored data for %s %d: dist=%.1f", displayName, entity, distToLeader);
            LogToFile(g_sLogPath, msg);
            if (debug >= 2 && admins != null)
            {
                for (int j = 0; j < admins.Length; j++)
                {
                    int client = admins.Get(j);
                    PrintToChat(client, "\x03[Cleaner]\x01 %s", msg);
                }
            }
        }
    }
}

public Action Timer_Clean(Handle timer)
{
    if (!g_cvEnable.BoolValue)
        return Plugin_Continue;

    float leaderPos[3];
    int leader = GetLeadingSurvivor(leaderPos);
    if (leader == -1)
        return Plugin_Continue;

    float distThreshold = g_cvDist.FloatValue;
    float minAge = g_cvMinTime.FloatValue;
    float minReduce = g_cvMinReduce.FloatValue;
    int debug = g_cvDebug.IntValue;
    float curTime = GetGameTime();
    float interval = g_cvInterval.FloatValue;

    int killed = 0;
    ArrayList admins = null;
    if (debug >= 2)
    {
        admins = new ArrayList();
        char flag[8];
        g_cvAdminFlag.GetString(flag, sizeof(flag));
        int flags = ReadFlagString(flag);
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && CheckCommandAccess(i, "", flags, true))
                admins.Push(i);
        }
    }

    // Process commons via FindEntityByClassname (only infected entities)
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "infected")) != -1)
    {
        ProcessEntity(entity, leaderPos, distThreshold, minAge, minReduce, debug, curTime, interval, admins, killed);
    }

    // Process witches via FindEntityByClassname (only witch entities)
    entity = -1;
    while ((entity = FindEntityByClassname(entity, "witch")) != -1)
    {
        ProcessEntity(entity, leaderPos, distThreshold, minAge, minReduce, debug, curTime, interval, admins, killed);
    }

    // Process clients (AI special infected bots)
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i)) continue;
        if (GetClientTeam(i) != 3) continue;
        if (!IsFakeClient(i)) continue;
        ProcessEntity(i, leaderPos, distThreshold, minAge, minReduce, debug, curTime, interval, admins, killed);
    }

    if (killed > 0)
    {
        char msg[128];
        Format(msg, sizeof(msg), "[Cleaner] Total killed this check: %d", killed);
        if (debug >= 1)
            LogToFile(g_sLogPath, msg);
        if (debug >= 2 && admins != null)
        {
            for (int j = 0; j < admins.Length; j++)
            {
                int client = admins.Get(j);
                PrintToChat(client, "\x03[Cleaner]\x01 %s", msg);
            }
        }
    }

    delete admins;
    return Plugin_Continue;
}