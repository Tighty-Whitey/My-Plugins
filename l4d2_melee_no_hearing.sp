#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

ConVar g_cvEnable;
ConVar g_cvDebug;

ConVar g_cvCommonsDuration;
ConVar g_cvWitchDuration;

ConVar g_cvMeleeRange;

ConVar g_cvWitchMeleeHearRadius;

ConVar g_cvGunfire;
ConVar g_cvWitchHear;

int   g_iCommonsCount = 0;
int   g_iWitchCount   = 0;

int   g_iSavedGunfire   = -1;
int   g_iSavedWitchHear = -1;

char  g_sLogPath[PLATFORM_MAX_PATH];

public Plugin myinfo =
{
	name        = "L4D2 Melee: Disable Hearing Ranges",
	author      = "Tighty-Whitey",
	description = "Temporarily forces z_hear_gunfire_range and z_witch_wander_hear_radius during melee, with independent durations.",
	version     = "1.0",
	url         = ""
};

public void OnPluginStart()
{

	g_cvEnable               = CreateConVar("l4d2_melee_nohear_enable", "1", "1=Enable, 0=Disable.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDebug                = CreateConVar("l4d2_melee_nohear_debug", "0", "1=Write debug log file in addons/sourcemod/logs/.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvCommonsDuration      = CreateConVar("l4d2_melee_nohear_commons_duration", "1.0", "Seconds to keep z_hear_gunfire_range forced after melee trigger (default 1.0).", FCVAR_NOTIFY, true, 0.0, true, 10.0);
	g_cvWitchDuration        = CreateConVar("l4d2_melee_nohear_witch_duration", "0.5", "Seconds to keep z_witch_wander_hear_radius forced after melee trigger (default 0.5).", FCVAR_NOTIFY, true, 0.0, true, 10.0);

	g_cvMeleeRange           = CreateConVar("l4d2_melee_nohear_melee_range", "72", "What to set z_hear_gunfire_range to during melee window (default 72).", FCVAR_NOTIFY, true, 0.0, true, 1000000.0);

	g_cvWitchMeleeHearRadius = CreateConVar("l4d2_melee_nohear_witch_melee_radius", "72", "What to set z_witch_wander_hear_radius to during melee window (default 72).", FCVAR_NOTIFY, true, 0.0, true, 1000000.0);

	AutoExecConfig(true, "l4d2_melee_no_hearing");

	BuildPath(Path_SM, g_sLogPath, sizeof(g_sLogPath), "logs/l4d2_melee_no_hearing.log");

	g_cvGunfire = FindConVar("z_hear_gunfire_range");
	if (g_cvGunfire == null)
	{
		DebugLog("ERROR: FindConVar('z_hear_gunfire_range') failed. Plugin cannot work.");
		return;
	}

	g_cvWitchHear = FindConVar("z_witch_wander_hear_radius");
	if (g_cvWitchHear == null)
	{
		DebugLog("WARN: FindConVar('z_witch_wander_hear_radius') failed. Witch muting disabled.");
	}

	bool okWeaponFire = HookEventEx("weapon_fire", Event_WeaponFire, EventHookMode_Post);
	DebugLog("HookEventEx weapon_fire=%d (1=hooked, 0=missing)", okWeaponFire);

	AddNormalSoundHook(Hook_NormalSound);
	DebugLog("NormalSoundHook installed.");

	DebugLog("Startup: gunfire=%d melee_range=%d commons_dur=%.3f | witch=%s witch_melee=%d witch_dur=%.3f",
		g_cvGunfire.IntValue,
		g_cvMeleeRange.IntValue,
		g_cvCommonsDuration.FloatValue,
		(g_cvWitchHear != null ? "FOUND" : "MISSING"),
		g_cvWitchMeleeHearRadius.IntValue,
		g_cvWitchDuration.FloatValue);
}

public void OnMapEnd()
{
	ForceRestoreAll("OnMapEnd");
}

public void OnPluginEnd()
{
	ForceRestoreAll("OnPluginEnd");
}

static void DebugLog(const char[] fmt, any ...)
{
	if (g_cvDebug == null || !g_cvDebug.BoolValue)
		return;

	char buffer[512];
	VFormat(buffer, sizeof(buffer), fmt, 2);
	LogToFileEx(g_sLogPath, "%s", buffer);
}

static bool IsSurvivorClient(int client)
{
	return (client >= 1 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}

static bool StrEqI(const char[] a, const char[] b)
{
	return (strcmp(a, b, false) == 0);
}

static bool LooksLikeMeleeSound(const char[] sample)
{
	if (StrContains(sample, "weapons/melee/", false) != -1) return true;
	if (StrContains(sample, "melee_swing", false) != -1) return true;
	if (StrContains(sample, "melee_hit", false) != -1) return true;
	if (StrContains(sample, "weapon_melee", false) != -1) return true;
	if (StrContains(sample, "knife", false) != -1) return true;
	return false;
}

static void ApplyConVarInt(ConVar cv, int value, const char[] name, const char[] why)
{
	if (cv == null)
		return;

	int before = cv.IntValue;
	cv.SetInt(value, true, false);
	int after = cv.IntValue;

	if (after != value)
		DebugLog("WARN: %s SetInt(%d) failed? before=%d after=%d why=%s (sv_cheats enforcement?)", name, value, before, after, why);
	else
		DebugLog("Set %s: before=%d after=%d why=%s", name, before, after, why);
}

static void Commons_EnterWindow(const char[] reason, int client, float seconds)
{
	if (g_cvGunfire == null)
		return;

	if (g_iCommonsCount == 0)
	{
		g_iSavedGunfire = g_cvGunfire.IntValue;
		ApplyConVarInt(g_cvGunfire, g_cvMeleeRange.IntValue, "z_hear_gunfire_range", "commons-melee-start");
		DebugLog("COMMONS start: client=%N reason=%s dur=%.3f saved=%d now=%d",
			client, reason, seconds, g_iSavedGunfire, g_cvGunfire.IntValue);
	}
	else
	{
		DebugLog("COMMONS stacked: client=%N reason=%s count=%d dur=%.3f", client, reason, g_iCommonsCount, seconds);
	}

	g_iCommonsCount++;
	CreateTimer(seconds, Timer_CommonsEnd, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_CommonsEnd(Handle timer)
{
	if (g_iCommonsCount <= 0)
		return Plugin_Stop;

	g_iCommonsCount--;

	if (g_iCommonsCount == 0)
	{
		if (g_cvGunfire != null && g_iSavedGunfire != -1)
		{
			int restore = g_iSavedGunfire;
			g_iSavedGunfire = -1;
			ApplyConVarInt(g_cvGunfire, restore, "z_hear_gunfire_range", "commons-melee-end-restore");
			DebugLog("COMMONS end: restored=%d current=%d", restore, g_cvGunfire.IntValue);
		}
	}

	return Plugin_Stop;
}

static void Witch_EnterWindow(const char[] reason, int client, float seconds)
{
	if (g_cvWitchHear == null)
		return;

	int meleeWitch = g_cvWitchMeleeHearRadius.IntValue;

	if (g_iWitchCount == 0)
	{
		int curWitch = g_cvWitchHear.IntValue;

		if (curWitch != meleeWitch)
			g_iSavedWitchHear = curWitch;
		else
			g_iSavedWitchHear = -1;

		ApplyConVarInt(g_cvWitchHear, meleeWitch, "z_witch_wander_hear_radius", "witch-melee-start");

		DebugLog("WITCH start: client=%N reason=%s dur=%.3f saved=%d now=%d",
			client, reason, seconds, g_iSavedWitchHear, g_cvWitchHear.IntValue);
	}
	else
	{
		DebugLog("WITCH stacked: client=%N reason=%s count=%d dur=%.3f", client, reason, g_iWitchCount, seconds);
	}

	g_iWitchCount++;
	CreateTimer(seconds, Timer_WitchEnd, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_WitchEnd(Handle timer)
{
	if (g_iWitchCount <= 0)
		return Plugin_Stop;

	g_iWitchCount--;

	if (g_iWitchCount == 0)
	{
		if (g_cvWitchHear != null && g_iSavedWitchHear != -1)
		{
			int restore = g_iSavedWitchHear;
			g_iSavedWitchHear = -1;
			ApplyConVarInt(g_cvWitchHear, restore, "z_witch_wander_hear_radius", "witch-melee-end-restore");
			DebugLog("WITCH end: restored=%d current=%d", restore, g_cvWitchHear.IntValue);
		}
	}

	return Plugin_Stop;
}

static void TriggerMeleeWindows(const char[] reason, int client)
{
	if (!g_cvEnable.BoolValue)
		return;

	if (!IsSurvivorClient(client))
		return;

	float cdur = g_cvCommonsDuration.FloatValue;
	if (cdur > 0.0)
		Commons_EnterWindow(reason, client, cdur);

	if (g_cvWitchHear != null)
	{
		float wdur = g_cvWitchDuration.FloatValue;
		if (wdur > 0.0)
			Witch_EnterWindow(reason, client, wdur);
	}
}

static void ForceRestoreAll(const char[] why)
{
	DebugLog("ForceRestoreAll: why=%s commonsCount=%d witchCount=%d", why, g_iCommonsCount, g_iWitchCount);

	g_iCommonsCount = 0;
	g_iWitchCount = 0;

	if (g_cvGunfire != null && g_iSavedGunfire != -1)
	{
		int restore = g_iSavedGunfire;
		g_iSavedGunfire = -1;
		ApplyConVarInt(g_cvGunfire, restore, "z_hear_gunfire_range", why);
	}

	if (g_cvWitchHear != null && g_iSavedWitchHear != -1)
	{
		int restoreW = g_iSavedWitchHear;
		g_iSavedWitchHear = -1;
		ApplyConVarInt(g_cvWitchHear, restoreW, "z_witch_wander_hear_radius", why);
	}
}

public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
		return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsSurvivorClient(client))
		return;

	char weapon[64];
	event.GetString("weapon", weapon, sizeof(weapon));

	if (StrEqI(weapon, "melee"))
	{
		DebugLog("Event weapon_fire: client=%N weapon=%s -> TriggerMeleeWindows", client, weapon);
		TriggerMeleeWindows("weapon_fire:melee", client);
	}
}

public Action Hook_NormalSound(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH],
	int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
	char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (!g_cvEnable.BoolValue)
		return Plugin_Continue;

	if (!IsSurvivorClient(entity))
		return Plugin_Continue;

	if (!LooksLikeMeleeSound(sample))
		return Plugin_Continue;

	DebugLog("SoundHook: client=%N sample=%s level=%d vol=%.2f -> TriggerMeleeWindows",
		entity, sample, level, volume);

	TriggerMeleeWindows("soundhook:melee", entity);
	return Plugin_Continue;
}
