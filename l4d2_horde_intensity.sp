#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

ConVar gC_Enable;
ConVar gC_Debug;
ConVar gC_Modes;
ConVar gC_TimerEnable;
ConVar gC_TimerDelay;
ConVar gC_TimerRebreather;
ConVar gC_TrackEnable;
ConVar gC_AllowEverywhere;
ConVar gC_AllowEverywhereInitial;
ConVar gC_Threshold;
ConVar gC_InitialWeight;
ConVar gC_DamageDivider;
ConVar gC_IntRebreather;
ConVar gC_DecayEnable;
ConVar gC_DecayInterval;
ConVar gC_DecayDelay;
ConVar gC_ResetLevel;
ConVar gC_HUD;
ConVar gC_Chat;

ConVar g_hMPGameMode;
bool  g_bModeAllowed = true;

public Plugin myinfo = {
    name = "L4D2 Horde Intensity",
    author = "Tighty-Whitey",
    description = "Hybrid health & damage intensity horde blocking.",
    version = "1.0",
    url = ""
};

// Global state
float g_fDefaultMin = -1.0;
float g_fDefaultMax = -1.0;
float g_fLastMin    = -1.0;
float g_fLastMax    = -1.0;
bool  g_bBaselineSet = false;

bool  g_bEventActive = false;
bool  g_bInOverride = false;

bool  g_bTimerBlockActive = false;
bool  g_bTimerPendingDelay = false;
Handle g_hTimerDelay = null;
Handle g_hTimerBlock = null;

float g_fIntensity = 0.0;
float g_fLastDamageTime = 0.0;
bool  g_bIntensityBlockActive = false;
bool  g_bIntensityPostBlock = false;
float g_fResetThreshold = 0.0;
Handle g_hIntRebreather = null;

Handle g_hHUDTimer = null;

char g_sLogPath[PLATFORM_MAX_PATH];

// Plugin start
public void OnPluginStart()
{
    gC_Enable           = CreateConVar("horde_intensity_plugin",            "1",    "Enable Horde Intensity", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gC_Debug            = CreateConVar("horde_intensity_debug",            "0",    "Debug logging", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gC_Modes            = CreateConVar("horde_intensity_modes",            "",     "Enable only in these game modes, comma‑separated (no spaces). Empty = all.", FCVAR_NOTIFY);

    gC_TimerEnable      = CreateConVar("horde_intensity_timer",            "0",    "Enable non-adaptive time‑based block cycle. Separate non-intensity based system. Off by default", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gC_TimerDelay       = CreateConVar("horde_intensity_timer_delay",      "60.0", "Delay before block (seconds). Part of a separate non-intensity based system.", FCVAR_NOTIFY, true, 0.0);
    gC_TimerRebreather  = CreateConVar("horde_intensity_timer_rebreather", "30.0", "Block duration (seconds). Part of a separate non-intensity based system. 0=disabled", FCVAR_NOTIFY, true, 0.0);

    gC_TrackEnable      = CreateConVar("horde_intensity_tracking",         "1",    "Enable adaptive intensity tracking. Enables core intensity system", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gC_AllowEverywhere  = CreateConVar("horde_intensity_allow_everywhere", "1",    "If 1, intensity works everywhere (ignores mob‑time changes) and acts as an expanded director, blocking off hordes where a team is struggling throughout any moment in the campaign. 0 - only detects artificial mob interval changes native to the events", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gC_AllowEverywhereInitial = CreateConVar("horde_intensity_allow_everywhere_initial", "0", "If 1, apply an additive initial team‑health intensity bump when an event overrides spawn times even in allow‑everywhere mode. If team stress is too high before triggering the event, it can block the horde right on event start.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    gC_Threshold        = CreateConVar("horde_intensity_threshold",        "1.0",  "Intensity threshold to trigger block", FCVAR_NOTIFY, true, 0.0);
    gC_InitialWeight    = CreateConVar("horde_intensity_initial_weight",   "1.0",  "Multiplier for team health deficit at event start. Gives an intensity headstart bump based on current amount of team health when event starts", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gC_DamageDivider    = CreateConVar("horde_intensity_damage_divider",   "500.0", "Damage taken divided by this value to increase intensity. Higher = slower buildup.", FCVAR_NOTIFY, true, 1.0);
    gC_IntRebreather    = CreateConVar("horde_intensity_rebreather",       "60.0",  "Intensity block duration (seconds). Horde prevention lasts for this amount of seconds", FCVAR_NOTIFY, true, 0.0);
    gC_DecayEnable      = CreateConVar("horde_intensity_decay_enable",     "1",    "Enable intensity decay", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gC_DecayInterval    = CreateConVar("horde_intensity_decay_interval",   "17.0",  "Seconds to lose 0.1 intensity", FCVAR_NOTIFY, true, 0.1);
    gC_DecayDelay       = CreateConVar("horde_intensity_decay_delay",      "25.0",  "Seconds without damage before decay starts", FCVAR_NOTIFY, true, 0.0);
    gC_ResetLevel       = CreateConVar("horde_intensity_reset_level",      "0.9",   "Early re-block prevention. If block is over and team is still at this value, jump to the threshold will not produce block, unless intensity dropped below this value, thus making it less generous. Set to the current intensity threshold value to disable.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gC_HUD              = CreateConVar("horde_intensity_hud",              "0",    "Show intensity HUD (root admins only)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gC_Chat             = CreateConVar("horde_intensity_chat",             "0",    "Print block messages to root admins", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    AutoExecConfig(true, "l4d2_horde_intensity");

    BuildPath(Path_SM, g_sLogPath, sizeof(g_sLogPath), "logs/horde_intensity_debug.log");

    CreateTimer(0.5, Timer_Check, _, TIMER_REPEAT);
    g_hHUDTimer = CreateTimer(1.0, Timer_HUD, _, TIMER_REPEAT);

    HookEvent("round_end",          Event_ClearState, EventHookMode_PostNoCopy);
    HookEvent("mission_lost",       Event_ClearState, EventHookMode_PostNoCopy);
    HookEvent("map_transition",     Event_ClearState, EventHookMode_PostNoCopy);
    HookEvent("finale_vehicle_leaving", Event_ClearState, EventHookMode_PostNoCopy);

    RegAdminCmd("sm_detecttime", Cmd_DetectTime, ADMFLAG_ROOT, "Show current limits and intensity");

    g_hMPGameMode = FindConVar("mp_gamemode");
    if (g_hMPGameMode != null)
        g_hMPGameMode.AddChangeHook(Cvar_ModeChanged);
    gC_Modes.AddChangeHook(Cvar_ModeChanged);
    UpdateAllowedGameMode();

    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i))
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnMapStart()
{
    g_bBaselineSet = false;
    g_bEventActive = false;
    g_bInOverride = false;
    g_bTimerBlockActive = false;
    g_bIntensityBlockActive = false;
    g_bIntensityPostBlock = false;
    g_fIntensity = 0.0;
    g_fLastDamageTime = GetEngineTime();
    KillTimerSystemTimers();
    KillIntensityTimers();
    UpdateAllowedGameMode();
    CreateTimer(2.0, Timer_SetBaseline);
}

public void OnMapEnd()
{
    KillTimerSystemTimers();
    KillIntensityTimers();
    g_bTimerBlockActive = false;
    g_bIntensityBlockActive = false;
    g_bEventActive = false;
    g_bInOverride = false;
}

// Mode filter
void UpdateAllowedGameMode()
{
    g_bModeAllowed = true;
    char list[256];
    gC_Modes.GetString(list, sizeof(list));
    TrimString(list);
    if (!list[0]) return;

    if (g_hMPGameMode == null)
    {
        g_bModeAllowed = false;
        return;
    }

    char mode[64];
    g_hMPGameMode.GetString(mode, sizeof(mode));
    TrimString(mode);

    char hay[320];
    char needle[96];
    Format(hay, sizeof(hay), ",%s,", list);
    Format(needle, sizeof(needle), ",%s,", mode);

    g_bModeAllowed = (StrContains(hay, needle, false) != -1);
}

public void Cvar_ModeChanged(ConVar cvar, const char[] oldV, const char[] newV)
{
    UpdateAllowedGameMode();
}

// Helpers
bool IsAnyBlockActive()
{
    return (gC_TimerEnable.BoolValue && g_bTimerBlockActive) ||
    (gC_TrackEnable.BoolValue && g_bIntensityBlockActive);
}

void KillTimerSystemTimers()
{
    if (g_hTimerDelay != null) { KillTimer(g_hTimerDelay); g_hTimerDelay = null; }
    if (g_hTimerBlock != null) { KillTimer(g_hTimerBlock); g_hTimerBlock = null; }
    g_bTimerPendingDelay = false;
}

void KillIntensityTimers()
{
    if (g_hIntRebreather != null) { KillTimer(g_hIntRebreather); g_hIntRebreather = null; }
}

static bool IsRootAdmin(int client)
{
    return (client > 0 && IsClientInGame(client) && (GetUserFlagBits(client) & ADMFLAG_ROOT) != 0);
}

void PrintToRootAdmins(const char[] msg)
{
    for (int i = 1; i <= MaxClients; i++)
        if (IsRootAdmin(i))
            PrintToChat(i, msg);
}

void ShowHudToRootAdmins(const char[] msg)
{
    for (int i = 1; i <= MaxClients; i++)
        if (IsRootAdmin(i))
            PrintHintText(i, msg);
}

void DebugLog(const char[] format, any ...)
{
    if (!gC_Debug.BoolValue) return;
    char buffer[512]; VFormat(buffer, sizeof(buffer), format, 2);
    File f = OpenFile(g_sLogPath, "a");
    if (f != null)
    {
        char date[32]; FormatTime(date, sizeof(date), "%Y-%m-%d %H:%M:%S");
        f.WriteLine("[%s] %s", date, buffer); FlushFile(f); delete f;
    }
}

// Timer system
void StartTimerDelay()
{
    if (!g_bModeAllowed || !gC_TimerEnable.BoolValue || gC_TimerRebreather.FloatValue <= 0.0) return;
    if (g_bTimerPendingDelay || g_bTimerBlockActive) return;
    g_bTimerPendingDelay = true;
    g_hTimerDelay = CreateTimer(gC_TimerDelay.FloatValue, Timer_TimerDelayEnd, _, TIMER_FLAG_NO_MAPCHANGE);
    DebugLog("Timer delay started: %.1f s", gC_TimerDelay.FloatValue);
}

void StartTimerBlock()
{
    if (!g_bModeAllowed || !gC_TimerEnable.BoolValue || gC_TimerRebreather.FloatValue <= 0.0) return;
    if (g_bTimerBlockActive) return;
    KillTimerSystemTimers();
    g_bTimerBlockActive = true;
    float rebr = gC_TimerRebreather.FloatValue;
    if (gC_Chat.BoolValue)
    {
        char msg[128];
        Format(msg, sizeof(msg), "\x04[HordeIntensity] \x01Timer block \x05%.1f\x01 s.", rebr);
        PrintToRootAdmins(msg);
    }
    DebugLog("Timer block started: %.1f s", rebr);
    g_hTimerBlock = CreateTimer(rebr, Timer_TimerBlockEnd, _, TIMER_FLAG_NO_MAPCHANGE);
}

void StopTimerBlock(bool announce = true)
{
    if (!g_bTimerBlockActive) return;
    g_bTimerBlockActive = false;
    KillTimerSystemTimers();
    if (announce && gC_Chat.BoolValue)
    PrintToRootAdmins("\x04[HordeIntensity] \x01Timer block ended.");
    DebugLog("Timer block ended.");
}

public Action Timer_TimerDelayEnd(Handle timer)
{
    g_hTimerDelay = null;
    g_bTimerPendingDelay = false;
    if (!gC_Enable.BoolValue || !gC_TimerEnable.BoolValue || gC_TimerRebreather.FloatValue <= 0.0) return Plugin_Stop;
    if (!g_bEventActive || !g_bModeAllowed) return Plugin_Stop;
    StartTimerBlock();
    return Plugin_Stop;
}

public Action Timer_TimerBlockEnd(Handle timer)
{
    g_hTimerBlock = null;
    g_bTimerBlockActive = false;
    if (gC_Chat.BoolValue)
    PrintToRootAdmins("\x04[HordeIntensity] \x01Timer block ended, restarting delay.");
    DebugLog("Timer block ended, restarting delay.");
    if (g_bEventActive && g_bModeAllowed) StartTimerDelay();
    return Plugin_Stop;
}

// Intensity system
void UpdateIntensityHUD()
{
    if (!gC_HUD.BoolValue) return;
    char msg[128]; float thresh = gC_Threshold.FloatValue;
    Format(msg, sizeof(msg), "Horde Intensity: %.2f / %.2f%s", g_fIntensity, thresh,
    IsAnyBlockActive() ? " (BLOCKED)" : "");
    ShowHudToRootAdmins(msg);
}

public Action Timer_HUD(Handle timer, any data)
{
    UpdateIntensityHUD();
    return Plugin_Continue;
}

void AddIntensity(float amount)
{
    if (!g_bEventActive || !gC_TrackEnable.BoolValue || !g_bModeAllowed) return;
    float thresh = gC_Threshold.FloatValue;
    float old = g_fIntensity; g_fIntensity += amount;
    if (g_fIntensity > thresh) g_fIntensity = thresh;
    g_fLastDamageTime = GetEngineTime();
    DebugLog("Intensity changed: %.2f -> %.2f (added %.4f)", old, g_fIntensity, amount);
    EvaluateIntensityBlocking();
}

void EvaluateIntensityBlocking()
{
    if (!gC_TrackEnable.BoolValue || !gC_Enable.BoolValue || !g_bEventActive || !g_bModeAllowed) return;
    if (g_bIntensityBlockActive) return;
    if (g_bIntensityPostBlock)
    {
        if (g_fIntensity < g_fResetThreshold)
        {
            g_bIntensityPostBlock = false;
            DebugLog("Post‑block cleared.");
            if (g_fIntensity >= gC_Threshold.FloatValue) StartIntensityBlock();
        }
        return;
    }
    if (g_fIntensity >= gC_Threshold.FloatValue) StartIntensityBlock();
}

void StartIntensityBlock()
{
    if (!gC_TrackEnable.BoolValue || g_bIntensityBlockActive || !g_bEventActive || !g_bModeAllowed) return;
    KillIntensityTimers();
    g_bIntensityBlockActive = true;
    float rebr = gC_IntRebreather.FloatValue;
    if (gC_Chat.BoolValue)
    {
        char msg[128];
        Format(msg, sizeof(msg), "\x04[HordeIntensity] \x01Intensity block \x05%.1f\x01 s.", rebr);
        PrintToRootAdmins(msg);
    }
    DebugLog("Intensity block started (rebreather %.1f s).", rebr);
    g_hIntRebreather = CreateTimer(rebr, Timer_IntensityRebreatherEnd, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_IntensityRebreatherEnd(Handle timer)
{
    g_hIntRebreather = null;
    if (!g_bEventActive)
    {
        g_bIntensityBlockActive = false;
        if (gC_Chat.BoolValue)
        PrintToRootAdmins("\x04[HordeIntensity] \x01Intensity block ended (event finished).");
        DebugLog("Intensity block ended due to event end.");
        return Plugin_Stop;
    }
    if (g_fIntensity >= gC_Threshold.FloatValue)
    {
        float rebr = gC_IntRebreather.FloatValue;
        g_hIntRebreather = CreateTimer(rebr, Timer_IntensityRebreatherEnd, _, TIMER_FLAG_NO_MAPCHANGE);
        DebugLog("Intensity still at threshold, extending block.");
        return Plugin_Stop;
    }
    g_bIntensityBlockActive = false;
    if (gC_Chat.BoolValue)
        PrintToRootAdmins("\x04[HordeIntensity] \x01Intensity block ended.");
    g_bIntensityPostBlock = true;
    g_fResetThreshold = gC_Threshold.FloatValue * gC_ResetLevel.FloatValue;
    if (g_fResetThreshold < 0.0) g_fResetThreshold = 0.0;
    EvaluateIntensityBlocking();
    return Plugin_Stop;
}

void ApplyIntensityDecay()
{
    if (!gC_DecayEnable.BoolValue || !g_bEventActive || !gC_TrackEnable.BoolValue || !g_bModeAllowed) return;
    float now = GetEngineTime();
    if (now - g_fLastDamageTime < gC_DecayDelay.FloatValue) return;
    float interval = gC_DecayInterval.FloatValue;
    if (interval <= 0.0) return;
    float decay = (0.5 / interval) * 0.1;
    float old = g_fIntensity;
    g_fIntensity -= decay;
    if (g_fIntensity < 0.0) g_fIntensity = 0.0;
    if (old != g_fIntensity) DebugLog("Decay: %.2f -> %.2f", old, g_fIntensity);
    EvaluateIntensityBlocking();
}

// Damage hook
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!gC_Enable.BoolValue || !gC_TrackEnable.BoolValue || !g_bEventActive || !g_bModeAllowed) return Plugin_Continue;
    if (damage <= 0.0 || victim < 1 || victim > MaxClients || !IsClientInGame(victim)) return Plugin_Continue;
    if (GetClientTeam(victim) != 2) return Plugin_Continue;
    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) &&
    GetClientTeam(attacker) == 2 && attacker != victim) return Plugin_Continue;
    if (GetEntProp(victim, Prop_Send, "m_isIncapacitated") != 0) return Plugin_Continue;

    float divider = gC_DamageDivider.FloatValue;
    if (divider <= 0.0) divider = 1.0;
    float add = damage / divider;
    DebugLog("Damage: %N from %d (%.1f) → +%.4f", victim, attacker, damage, add);
    AddIntensity(add);
    return Plugin_Continue;
}

// Initial team stress
float ComputeTeamHealthIntensity()
{
    float totalMax = 0.0, totalMissing = 0.0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) != 2 || !IsPlayerAlive(i)) continue;
        int maxHP = GetEntProp(i, Prop_Send, "m_iMaxHealth"); if (maxHP <= 0) maxHP = 100;
        int curHP = GetClientHealth(i);
        int missing = maxHP - curHP; if (missing < 0) missing = 0;
        totalMax += maxHP; totalMissing += missing;
        DebugLog("  Health: %N  max=%d  cur=%d  missing=%d", i, maxHP, curHP, missing);
    }
    if (totalMax <= 0.0) return 0.0;
    float ratio = totalMissing / totalMax;
    DebugLog("Team health ratio: %.2f (missing %.0f / max %.0f)", ratio, totalMissing, totalMax);
    return ratio * gC_InitialWeight.FloatValue;
}

// Main tick
public Action Timer_Check(Handle timer)
{
    if (!gC_Enable.BoolValue || !g_bModeAllowed) return Plugin_Continue;

    bool bAllowEverywhere = gC_AllowEverywhere.BoolValue;
    bool bAllowEverywhereInitial = gC_AllowEverywhereInitial.BoolValue;

    if (L4D_HasMapStarted() && g_bBaselineSet)
    {
        float fMin = L4D2_GetScriptValueFloat("MobSpawnMinTime", -1.0);
        float fMax = L4D2_GetScriptValueFloat("MobSpawnMaxTime", -1.0);
        if (fMin != g_fLastMin || fMax != g_fLastMax)
        {
            DebugLog("Spawn times changed: Min %.1f->%.1f, Max %.1f->%.1f", g_fLastMin, fMin, g_fLastMax, fMax);
            if (gC_Chat.BoolValue)
            {
                char msg[256];
                Format(msg, sizeof(msg),
                "\x04[HordeIntensity] \x01Spawn times: Min \x05%.1f\x01 (was %.1f), Max \x04%.1f\x01 (was %.1f)",
                fMin, g_fLastMin, fMax, g_fLastMax);
                PrintToRootAdmins(msg);
            }

            bool bOverride = (fMin != g_fDefaultMin || fMax != g_fDefaultMin);

            if (bOverride && !g_bInOverride && gC_TrackEnable.BoolValue)
            {
                if (!bAllowEverywhere || bAllowEverywhereInitial)
                {
                    float bump = ComputeTeamHealthIntensity();
                    if (bump > 0.0)
                    {
                        g_fIntensity += bump;
                        if (g_fIntensity > gC_Threshold.FloatValue)
                        g_fIntensity = gC_Threshold.FloatValue;
                        DebugLog("Event override started, initial intensity bump +%.2f, now %.2f", bump, g_fIntensity);
                    }
                }
            }

            g_bInOverride = bOverride;

            if (!bAllowEverywhere)
            {
                g_bEventActive = bOverride;
            }

            // Timer system
            if (gC_TimerEnable.BoolValue)
            {
                if (!bOverride)
                StopTimerBlock(true);
                else if (!g_bTimerBlockActive && !g_bTimerPendingDelay && gC_TimerRebreather.FloatValue > 0.0)
                StartTimerDelay();
            }

            // Reset on baseline return
            if (!bOverride)
            {
                DebugLog("Baseline returned. Resetting all blocks.");
                if (gC_TimerEnable.BoolValue) StopTimerBlock(true);
                if (gC_TrackEnable.BoolValue)
                {
                    if (g_bIntensityBlockActive)
                    {
                        KillIntensityTimers();
                        g_bIntensityBlockActive = false;
                        if (gC_Chat.BoolValue)
                        PrintToRootAdmins("\x04[HordeIntensity] \x01Intensity block ended (baseline restored).");
                    }
                    g_bIntensityPostBlock = false;
                    g_fIntensity = 0.0;
                }
            }

            g_fLastMin = fMin;
            g_fLastMax = fMax;
        }
    }

    // Intensity system
    if (gC_TrackEnable.BoolValue && g_bEventActive && g_bModeAllowed)
    {
        ApplyIntensityDecay();
        EvaluateIntensityBlocking();
    }

    // Everywhere mode activation
    if (bAllowEverywhere && g_bBaselineSet && !g_bEventActive)
    {
        g_bEventActive = true;
        g_fIntensity = ComputeTeamHealthIntensity();
        DebugLog("Everywhere mode: intensity activated, initial %.2f", g_fIntensity);
    }

    return Plugin_Continue;
}

// Map events
public Action Timer_SetBaseline(Handle timer)
{
    if (!L4D_HasMapStarted() || !gC_Enable.BoolValue) return Plugin_Continue;
    g_fDefaultMin = L4D2_GetScriptValueFloat("MobSpawnMinTime", -1.0);
    g_fDefaultMax = L4D2_GetScriptValueFloat("MobSpawnMaxTime", -1.0);
    g_fLastMin = g_fDefaultMin;
    g_fLastMax = g_fDefaultMax;
    g_bBaselineSet = true;

    if (gC_AllowEverywhere.BoolValue)
    {
        g_bEventActive = true;
        g_fIntensity = ComputeTeamHealthIntensity();
        DebugLog("Baseline: %.1f / %.1f  |  Everywhere mode: intensity started at %.2f", g_fDefaultMin, g_fDefaultMax, g_fIntensity);
    }
    else
    {
        g_bEventActive = false;
        DebugLog("Baseline: %.1f / %.1f", g_fDefaultMin, g_fDefaultMax);
    }
    return Plugin_Stop;
}

public void Event_ClearState(Event event, const char[] name, bool dontBroadcast)
{
    DebugLog("Clear state: %s", name);
    g_bEventActive = false;
    g_bInOverride = false;
    if (gC_TimerEnable.BoolValue) StopTimerBlock(true);
    if (gC_TrackEnable.BoolValue)
    {
        if (g_bIntensityBlockActive)
        {
            KillIntensityTimers();
            g_bIntensityBlockActive = false;
        }
        g_bIntensityPostBlock = false;
        g_fIntensity = 0.0;
    }
}

public Action L4D_OnSpawnMob(int &amount)
{
    if (!gC_Enable.BoolValue || !g_bModeAllowed) return Plugin_Continue;
    if (IsAnyBlockActive())
    {
        DebugLog("Mob BLOCKED");
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

public Action Cmd_DetectTime(int client, int args)
{
    if (!L4D_HasMapStarted())
    {
        ReplyToCommand(client, "[SM] Map not fully loaded.");
        return Plugin_Handled;
    }
    float fMin = L4D2_GetScriptValueFloat("MobSpawnMinTime", -1.0);
    float fMax = L4D2_GetScriptValueFloat("MobSpawnMaxTime", -1.0);
    bool blocked = IsAnyBlockActive();
    ReplyToCommand(client, "\x04[HordeIntensity] \x01Min %.1f | Max %.1f | Intensity %.2f/%.1f | Hordes %s",
    fMin, fMax, g_fIntensity, gC_Threshold.FloatValue, blocked ? "\x03BLOCKED" : "\x04ALLOWED");
    return Plugin_Handled;
}