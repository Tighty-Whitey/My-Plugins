// l4d2_flow_cleaner.sp
// Removes far-behind AI infected not closing the gap.

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "1.1"
#define LOG_FILE "l4d2_flow_cleaner.log"

ConVar g_cvEnable, g_cvInterval, g_cvDist, g_cvMinTime, g_cvMinReduce, g_cvDebug, g_cvAdminFlag, g_cvMode;
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
    description = "Removes stuck AI infected far behind the leading survivor (or team center, or nearest survivor)",
    version = "1.1",
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
    g_cvDist = CreateConVar("l4d2_flow_cleaner_dist", "8000.0", "Distance threshold from reference (units)", FCVAR_NOTIFY, true, 100.0, true, 20000.0);
    g_cvMinTime = CreateConVar("l4d2_flow_cleaner_mintime", "45.0", "Minimum age after spawn before removal (seconds)", FCVAR_NOTIFY, true, 0.0, true, 120.0);
    g_cvMinReduce = CreateConVar("l4d2_flow_cleaner_minreduce", "1200.0", "Min distance reduction to be 'approaching'", FCVAR_NOTIFY, true, 0.0, true, 9999.0);
    g_cvDebug = CreateConVar("l4d2_flow_cleaner_debug", "0", "Debug: 0=off, 1=log to file, 2=log+admin chat", FCVAR_NOTIFY, true, 0.0, true, 2.0);
    g_cvAdminFlag = CreateConVar("l4d2_flow_cleaner_admin_flag", "z", "Admin flag for chat messages", FCVAR_NOTIFY);
    g_cvMode = CreateConVar("l4d2_flow_cleaner_mode", "1", "Mode: 1=leading survivor, 2=team center (average X,Y,Z), 3=nearest survivor", FCVAR_NOTIFY, true, 1.0, true, 3.0);

    AutoExecConfig(true, "l4d2_flow_cleaner");

    if (g_cvDebug.IntValue >= 2)
        PrintToChatAll("\x03[Cleaner]\x01 Plugin loaded. Debug level = %d, Mode = %d", g_cvDebug.IntValue, g_cvMode.IntValue);

    OnConVarChanged(null, "", "");
    g_cvEnable.AddChangeHook(OnConVarChanged);
    g_cvInterval.AddChangeHook(OnConVarChanged);
    g_cvMode.AddChangeHook(OnConVarChanged);

    HookEvent("entity_killed", Event_EntityKilled, EventHookMode_Pre);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
    HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
    g_LastDistMap.Clear();
    g_LastTimeMap.Clear();
    g_SpawnTimeMap.Clear();

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

int GetReferencePosition(float refPos[3])
{
    int mode = g_cvMode.IntValue;

    if (mode == 1)
    {
        int leader = L4D_GetHighestFlowSurvivor();
        if (leader > 0 && leader <= MaxClients && IsClientInGame(leader) && GetClientTeam(leader) == 2 && IsPlayerAlive(leader))
        {
            GetClientAbsOrigin(leader, refPos);
            return leader;
        }
        return -1;
    }
    else if (mode == 2)
    {
        int count = 0;
        float center[3] = {0.0, 0.0, 0.0};
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
            {
                float pos[3];
                GetClientAbsOrigin(i, pos);
                center[0] += pos[0];
                center[1] += pos[1];
                center[2] += pos[2];
                count++;
            }
        }
        if (count == 0)
            return -1;

        refPos[0] = center[0] / float(count);
        refPos[1] = center[1] / float(count);
        refPos[2] = center[2] / float(count);
        return 0;
    }
    else if (mode == 3)
    {
        // No single reference point – mode 3 uses per‑entity nearest survivor
        return -1; // sentinel
    }

    return -1;
}

bool GetEntityPosition(int entity, float pos[3])
{
    if (entity > MaxClients)
    {
        if (!IsValidEntity(entity))
            return false;
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
    }
    else
    {
        GetClientAbsOrigin(entity, pos);
    }
    return true;
}

bool IsEntityTrackable(int entity)
{
    if (entity > MaxClients)
        return true;
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

// Returns nearest survivor distance, or -1.0 if no survivors
float GetNearestSurvivorDistance(const float entityPos[3])
{
    float nearest = 999999.0;
    bool found = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
        {
            float pos[3];
            GetClientAbsOrigin(i, pos);
            float dist = GetVectorDistance(pos, entityPos);
            if (dist < nearest)
            {
                nearest = dist;
                found = true;
            }
        }
    }
    return found ? nearest : -1.0;
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

void ProcessEntity(int entity, int mode, float refPos[3], float distThreshold, float minAge, float minReduce, int debug, float curTime, float interval, ArrayList admins, int &killed)
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
    if (!GetEntityPosition(entity, pos))
        return;

    float distToRef;
    if (mode == 1 || mode == 2)
    {
        distToRef = GetVectorDistance(pos, refPos);
    }
    else if (mode == 3)
    {
        distToRef = GetNearestSurvivorDistance(pos);
        if (distToRef < 0.0)
            return; // no survivors alive
    }
    else
    {
        return;
    }

    if (distToRef < distThreshold)
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
            float reduction = lastDist - distToRef;
            char displayName[64];
            GetEntityDisplayName(entity, displayName, sizeof(displayName));
            char msg[256];

            if (reduction < minReduce)
            {
                Format(msg, sizeof(msg), "[Cleaner] Killed %s %d (age %.1f, dist %.1f, reduction %.1f)", 
                       displayName, entity, age, distToRef, reduction);

                KillEntity(entity, msg, debug, admins);

                g_LastDistMap.Remove(key);
                g_LastTimeMap.Remove(key);
                g_SpawnTimeMap.Remove(key);
                killed++;
                return;
            }
            else
            {
                Format(msg, sizeof(msg), "[Cleaner] %s %d updating: dist=%.1f, reduction=%.1f", displayName, entity, distToRef, reduction);

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

                g_LastDistMap.SetValue(key, distToRef, true);
                g_LastTimeMap.SetValue(key, curTime, true);
            }
        }
    }
    else
    {
        g_LastDistMap.SetValue(key, distToRef, true);
        g_LastTimeMap.SetValue(key, curTime, true);
        if (debug >= 1)
        {
            char displayName[64];
            GetEntityDisplayName(entity, displayName, sizeof(displayName));
            char msg[256];
            Format(msg, sizeof(msg), "[Cleaner] Stored data for %s %d: dist=%.1f", displayName, entity, distToRef);
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

    int mode = g_cvMode.IntValue;
    float refPos[3] = {0.0, 0.0, 0.0}; // only used for modes 1/2

    if (mode == 1 || mode == 2)
    {
        int ref = GetReferencePosition(refPos);
        if (ref == -1)
            return Plugin_Continue;
    }
    // mode 3 does not need refPos

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

    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "infected")) != -1)
    {
        if (IsValidEntity(entity))
            ProcessEntity(entity, mode, refPos, distThreshold, minAge, minReduce, debug, curTime, interval, admins, killed);
    }

    entity = -1;
    while ((entity = FindEntityByClassname(entity, "witch")) != -1)
    {
        if (IsValidEntity(entity))
            ProcessEntity(entity, mode, refPos, distThreshold, minAge, minReduce, debug, curTime, interval, admins, killed);
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i)) continue;
        if (GetClientTeam(i) != 3) continue;
        if (!IsFakeClient(i)) continue;
        if (!IsPlayerAlive(i)) continue;
        ProcessEntity(i, mode, refPos, distThreshold, minAge, minReduce, debug, curTime, interval, admins, killed);
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