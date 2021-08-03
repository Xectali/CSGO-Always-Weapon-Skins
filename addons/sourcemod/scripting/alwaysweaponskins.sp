/**
 * ==============================================================================
 * Always Weapon Skins for SourceMod (C)2018 Matthew J Dunn. All rights reserved.
 * ==============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */
#include <dhooks>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.3.0 PŠΣ™"

/***************************************************
 * STATIC / GLOBALS STUFF
 **************************************************/
static Handle s_hGiveNamedItem = null;
static Handle s_hGiveNamedItemPost = null;
static bool s_HookInUse = false;
static Handle s_hMapWeapons = null;
static int s_OriginalClientTeam;
static bool s_TeamWasSwitched = false;

static Handle hSDKGEconItemSchema = null;
static Handle hSDKGetItemDefinitionByName = null;
static Handle hSDKGetLoadoutSlot = null;
static Handle hSDKGetItemInLoadout = null;
static Handle hSDKCEconItemViewGetItemDefinition = null;

int g_iLastItemDefinition[MAXPLAYERS+1][2];

/***************************************************
 * PLUGIN STUFF
 **************************************************/
public Plugin myinfo =
{
	name = "Always Weapon Skins",
	author = "Neuro Toxin & PŠΣ™ SHUFEN",
	description = "Players always get their weapon skins!",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=237114",
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("alwaysweaponskins");
	return APLRes_Success;
}

public void OnPluginStart()
{
	if (!StartSDKCall())
	{
		SetFailState("Unable to start SDKCall using sdktools");
		return;
	}

	if (!HookOnGiveNamedItem())
	{
		SetFailState("Unable to hook GiveNamedItem using DHooks");
		return;
	}

	if (!BuildItems())
	{
		SetFailState("Unable to load items data from 'items_game.txt'");
		return;
	}

	HookEvent("round_prestart", Event_RoundPreStart);

	CreateConvars();
}

public bool StartSDKCall()
{
	//GEconItemSchema(Linux), ItemSystem(Windows) - A1 ?? ?? ?? ?? 85 C0 75 ?? A1 ?? ?? ?? ?? 56
	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(GetCStrikeGameConfig(), SDKConf_Signature, "GetItemSchema")) {
		LogError("Unable to find signature 'GetItemSchema' in game data 'sm-cstrike.games'");
		return false;
	}
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);	//Returns address of CEconItemSchema
	if ((hSDKGEconItemSchema = EndPrepSDKCall()) == null) {
		LogError("Unable to setup SDKCall 'GEconItemSchema'");
		return false;
	}

	//CEconItemSchema::GetItemDefinitionByName
	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetFromConf(GetCStrikeGameConfig(), SDKConf_Virtual, "GetItemDefintionByName")) {
		LogError("Unable to find offset 'GetItemDefintionByName' in game data 'sm-cstrike.games'");
		return false;
	}
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain); //Returns address of CEconItemDefinition
	hSDKGetItemDefinitionByName = EndPrepSDKCall();
	if (hSDKGetItemDefinitionByName == null) {
		LogError("Unable to setup SDKCall 'CEconItemSchema::GetItemDefinitionByName'");
		return false;
	}

	//CCStrike15ItemDefinition::GetLoadoutSlot
	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetFromConf(GetPluginGameConfig(), SDKConf_Signature, "CCStrike15ItemDefinition::GetLoadoutSlot")) {
		LogError("Unable to find signature 'CCStrike15ItemDefinition::GetLoadoutSlot' in game data 'alwaysweaponskins.games'");
		return false;
	}
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hSDKGetLoadoutSlot = EndPrepSDKCall();
	if (hSDKGetLoadoutSlot == null) {
		LogError("Unable to setup SDKCall 'CCStrike15ItemDefinition::GetLoadoutSlot'");
		return false;
	}

	//CCSPlayerInventory::GetItemInLoadout
	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetFromConf(GetCStrikeGameConfig(), SDKConf_Virtual, "GetItemInLoadout")) {
		LogError("Unable to find offset 'GetItemInLoadout' in game data 'sm-cstrike.games'");
		return false;
	}
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);	//Returns address of CEconItemView
	hSDKGetItemInLoadout = EndPrepSDKCall();
	if (hSDKGetItemInLoadout == null) {
		LogError("Unable to setup SDKCall 'CCSPlayerInventory::GetItemInLoadout'");
		return false;
	}

	//CEconItemView::GetItemDefinition
	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetFromConf(GetPluginGameConfig(), SDKConf_Virtual, "CEconItemView::GetItemDefinition")) {
		LogError("Unable to find offset 'CEconItemView::GetItemDefinition' in game data 'alwaysweaponskins.games'");
		return false;
	}
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain); //Returns address of CEconItemDefinition
	hSDKCEconItemViewGetItemDefinition = EndPrepSDKCall();
	if (hSDKCEconItemViewGetItemDefinition == null) {
		LogError("Unable to setup SDKCall 'CEconItemView::GetItemDefinition'");
		return false;
	}

	return true;
}

stock Address GetItemSchema() {
	static Address pItemSchema = Address_Null;
	if (pItemSchema == Address_Null) {
		if (hSDKGEconItemSchema != null) {
			Address _pItemSchema = SDKCall(hSDKGEconItemSchema);
			int offset = GetPluginGameConfig().GetOffset("pItemSchema");
			if (offset == -1) {
				offset = 0;
			}
			else {
				offset *= 4;
			}

			pItemSchema = _pItemSchema != Address_Null ? (_pItemSchema + view_as<Address>(offset)) : Address_Null;
		}
	}

	return pItemSchema;
}

stock Address GetItemDefinitionByName(const char[] szName) {
	if (hSDKGetItemDefinitionByName == null)
		return Address_Null;

	Address pItemSchema = GetItemSchema();
	if (pItemSchema == Address_Null)
		return Address_Null;

	return SDKCall(hSDKGetItemDefinitionByName, pItemSchema, szName);
}

stock int GetLoadoutSlot(Address pItemDef, int iTeam) {
	if (pItemDef == Address_Null)
		return -1;

	if (hSDKGetLoadoutSlot == null)
		return -1;

	if (iTeam != CS_TEAM_T && iTeam != CS_TEAM_CT)
		return -1;

	return SDKCall(hSDKGetLoadoutSlot, pItemDef, iTeam);
}

stock int GetInventoryOffset() {
	static int iOffs = -1;
	static Address pHandleCommandBuy = Address_Null;
	static int byteOffset = -1;
	if (iOffs == -1) {
		if (GetPluginGameConfig() != null && GetCStrikeGameConfig() != null) {
			pHandleCommandBuy = GetPluginGameConfig().GetAddress("HandleCommand_Buy_Internal");
			byteOffset = GetCStrikeGameConfig().GetOffset("CCSPlayerInventoryOffset");
			if (pHandleCommandBuy != Address_Null && byteOffset != -1)
				iOffs = LoadFromAddress(pHandleCommandBuy + view_as<Address>(byteOffset), NumberType_Int32);
		}
	}

	return iOffs;
}

stock Address GetItemDefinitionInLoadout(int client, int iTeam, int iLoadoutSlot) {
	if (hSDKGetItemInLoadout == null || hSDKCEconItemViewGetItemDefinition == null)
		return Address_Null;

	if (!IsClientInGame(client))
		return Address_Null;

	Address pEnt = GetEntityAddress(client);
	if (pEnt == Address_Null)
		return Address_Null;

	int iOffs = GetInventoryOffset();
	if (iOffs == -1)
		return Address_Null;

	Address pCEconItemView = SDKCall(hSDKGetItemInLoadout, pEnt + view_as<Address>(iOffs), iTeam, iLoadoutSlot);
	if (pCEconItemView == Address_Null)
		return Address_Null;

	return SDKCall(hSDKCEconItemViewGetItemDefinition, pCEconItemView);
}

stock GameData GetSDKToolsGameConfig() {
	static GameData hGameConf = null;
	if (hGameConf == null) {
		hGameConf = new GameData("sdktools.games");
		if (hGameConf == null)
			LogError("Unable to load game config file: sdktools.games");
	}

	return hGameConf;
}

stock GameData GetCStrikeGameConfig() {
	static GameData hGameConf = null;
	if (hGameConf == null) {
		hGameConf = new GameData("sm-cstrike.games");
		if (hGameConf == null)
			LogError("Unable to load game config file: sm-cstrike.games");
	}

	return hGameConf;
}

stock GameData GetPluginGameConfig() {
	static GameData hGameConf = null;
	if (hGameConf == null) {
		hGameConf = new GameData("alwaysweaponskins.games");
		if (hGameConf == null)
			LogError("Unable to load game config file: alwaysweaponskins.games");
	}

	return hGameConf;
}

/***************************************************
 * CONVAR STUFF
 **************************************************/
static ConVar s_ConVar_Enable;
static ConVar s_ConVar_SkipMapWeapons;
static ConVar s_ConVar_SkipNamedWeapons;
static ConVar s_ConVar_DebugMessages;

static bool s_bEnable = false;
static bool s_bSkipMapWeapons = true;
static bool s_bSkipNamedWeapons = true;
static bool s_bDebugMessages = false;

stock void CreateConvars()
{
	s_ConVar_Enable = CreateConVar("aws_enable", "1", "Enables plugin");
	s_ConVar_SkipMapWeapons = CreateConVar("aws_skipmapweapons", "0", "Disables replacement of map weapons");
	s_ConVar_SkipNamedWeapons = CreateConVar("aws_skipnamedweapons", "1", "Disables replacement of map weapons which have names (special weapons)");
	s_ConVar_DebugMessages = CreateConVar("aws_debugmessages", "0", "Display debug messages in client console");

	s_ConVar_Enable.AddChangeHook(OnCvarChanged);
	s_ConVar_SkipMapWeapons.AddChangeHook(OnCvarChanged);
	s_ConVar_SkipNamedWeapons.AddChangeHook(OnCvarChanged);
	s_ConVar_DebugMessages.AddChangeHook(OnCvarChanged);

	ConVar version = CreateConVar("aws_version", PLUGIN_VERSION);
	int flags = version.Flags;
	flags |= FCVAR_NOTIFY;
	version.Flags = flags;
	delete version;
}

stock void LoadConvars()
{
	s_bEnable = s_ConVar_Enable.BoolValue;
	s_bSkipMapWeapons = s_ConVar_SkipMapWeapons.BoolValue;
	s_bSkipNamedWeapons = s_ConVar_SkipNamedWeapons.BoolValue;
	s_bDebugMessages = s_ConVar_DebugMessages.BoolValue;
}

public void OnCvarChanged(Handle cvar, const char[] oldVal, const char[] newVal)
{
	if (cvar == s_ConVar_Enable)
		s_bEnable = StringToInt(newVal) == 0 ? false : true;
	else if (cvar == s_ConVar_SkipMapWeapons)
		s_bSkipMapWeapons = StringToInt(newVal) == 0 ? false : true;
	else if (cvar == s_ConVar_SkipNamedWeapons)
		s_bSkipNamedWeapons = StringToInt(newVal) == 0 ? false : true;
	else if (cvar == s_ConVar_DebugMessages)
		s_bDebugMessages = StringToInt(newVal) == 0 ? false : true;
}

/***************************************************
 * DHOOKS STUFF
 **************************************************/
public bool HookOnGiveNamedItem()
{
	GameData config = GetSDKToolsGameConfig();
	if (config == null)
	{
		LogError("Unable to load game config file: sdktools.games");
		return false;
	}

	int offset = config.GetOffset("GiveNamedItem");
	if (offset == -1)
	{
		LogError("Unable to find offset 'GiveNamedItem' in game data 'sdktools.games'");
		return false;
	}

	/* POST HOOK */
	s_hGiveNamedItemPost = DHookCreate(offset, HookType_Entity, ReturnType_CBaseEntity, ThisPointer_CBaseEntity, OnGiveNamedItemPost);
	if (s_hGiveNamedItemPost == INVALID_HANDLE)
	{
		LogError("Unable to post hook 'int CCSPlayer::GiveNamedItem(char const*, int, CEconItemView*, bool)'");
		return false;
	}

	DHookAddParam(s_hGiveNamedItemPost, HookParamType_CharPtr, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItemPost, HookParamType_Int, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItemPost, HookParamType_Int, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItemPost, HookParamType_Bool, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItemPost, HookParamType_Unknown, -1, DHookPass_ByVal);

	/* PRE HOOK */
	s_hGiveNamedItem = DHookCreate(offset, HookType_Entity, ReturnType_CBaseEntity, ThisPointer_CBaseEntity, OnGiveNamedItemPre);
	if (s_hGiveNamedItem == INVALID_HANDLE)
	{
		LogError("Unable to hook 'int CCSPlayer::GiveNamedItem(char const*, int, CEconItemView*, bool)'");
		return false;
	}

	DHookAddParam(s_hGiveNamedItem, HookParamType_CharPtr, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItem, HookParamType_Int, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItem, HookParamType_Int, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItem, HookParamType_Bool, -1, DHookPass_ByVal);
	DHookAddParam(s_hGiveNamedItem, HookParamType_Unknown, -1, DHookPass_ByVal);
	return true;
}

/***************************************************
 * EVENT STUFF
 **************************************************/
public void OnConfigsExecuted()
{
	LoadConvars();
}

public void OnMapStart()
{
	if (s_hMapWeapons != null)
		ClearArray(s_hMapWeapons);
	else
		s_hMapWeapons = CreateArray();

	for (int client = 1; client < MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;

		if (!IsClientAuthorized(client))
			continue;

		OnClientPutInServer(client);
	}
}

public void OnClientPutInServer(int client)
{
	if (IsFakeClient(client))
		return;

	DHookEntity(s_hGiveNamedItem, false, client);
	DHookEntity(s_hGiveNamedItemPost, true, client);
	SDKHook(client, SDKHook_WeaponEquipPost, OnPostWeaponEquip);
}

/***************************************************
 * ROUND CHANGE FIX STUFF
 **************************************************/
public void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
	int weapon;
	int itemdefinition;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && IsPlayerAlive(i)) {
			for (int slot = CS_SLOT_PRIMARY; slot <= CS_SLOT_SECONDARY; slot++) {
				weapon = GetPlayerWeaponSlot(i, slot);
				if (weapon != -1) {
					itemdefinition = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
					if (itemdefinition == 23 || itemdefinition == 60 ||
						itemdefinition == 61 || itemdefinition == 63 || itemdefinition == 64)
						g_iLastItemDefinition[i][slot] = itemdefinition;
					else
						g_iLastItemDefinition[i][slot] = 0;
				}
				else
					g_iLastItemDefinition[i][slot] = 0;
			}
		}
		else {
			g_iLastItemDefinition[i][CS_SLOT_PRIMARY] = 0;
			g_iLastItemDefinition[i][CS_SLOT_SECONDARY] = 0;
		}
	}
}

/***************************************************
 * DHOOK CALLS
 **************************************************/
public MRESReturn OnGiveNamedItemPre(int client, Handle hReturn, Handle hParams)
{
	char classname[64];
	DHookGetParamString(hParams, 1, classname, sizeof(classname));
	if (s_bDebugMessages)
		PrintToConsole(client, "[AWS] OnGiveNamedItemPre(int client, char[] classname='%s')", classname);

	if (!s_bEnable)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Plugin Disabled");
		return MRES_Ignored;
	}

	s_TeamWasSwitched = false;
	s_HookInUse = true;

	int itemdefinition = GetItemDefinitionByClassname(classname);
	if (s_bDebugMessages)
		PrintToConsole(client, "[AWS] -> Item Definition: %d", itemdefinition);

	if (itemdefinition == -1)
		return MRES_Ignored;

	if (IsItemDefinitionKnife(itemdefinition))
		return MRES_Ignored;

	bool bRoundChangeFix = false;
	if ((itemdefinition == 16 || /* weapon_m4a1 (M4A4) <Round Change Glitch by m4a1_silencer> */
		itemdefinition == 33) && /* weapon_mp7 <Round Change Glitch by mp5sd> */
		g_iLastItemDefinition[client][CS_SLOT_PRIMARY] != 0 && g_iLastItemDefinition[client][CS_SLOT_PRIMARY] != itemdefinition) {
		bRoundChangeFix = true;
		itemdefinition = g_iLastItemDefinition[client][CS_SLOT_PRIMARY];
		g_iLastItemDefinition[client][CS_SLOT_PRIMARY] = 0;
		if (itemdefinition == 23)
			strcopy(classname, sizeof(classname), "weapon_mp5sd");

		else if (itemdefinition == 60)
			strcopy(classname, sizeof(classname), "weapon_m4a1_silencer");
	}
	else if ((itemdefinition == 1 || /* weapon_deagle <Round Change Glitch by revolver> */
			itemdefinition == 32 || /* weapon_hkp2000 <Round Change Glitch by usp_silencer> */
			itemdefinition == 36) && /* weapon_p250 <Round Change Glitch by cz75a> */
			g_iLastItemDefinition[client][CS_SLOT_SECONDARY] != 0 && g_iLastItemDefinition[client][CS_SLOT_SECONDARY] != itemdefinition) {
		bRoundChangeFix = true;
		itemdefinition = g_iLastItemDefinition[client][CS_SLOT_SECONDARY];
		g_iLastItemDefinition[client][CS_SLOT_SECONDARY] = 0;
		if (itemdefinition == 61)
			strcopy(classname, sizeof(classname), "weapon_usp_silencer");
		else if (itemdefinition == 63)
			strcopy(classname, sizeof(classname), "weapon_cz75a");
		else if (itemdefinition == 64)
			strcopy(classname, sizeof(classname), "weapon_revolver");
	}

	if (bRoundChangeFix) {
		DHookSetParamString(hParams, 1, classname);
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Round Change Fix: %d ('%s')", itemdefinition, classname);
	}

	s_OriginalClientTeam = GetEntProp(client, Prop_Data, "m_iTeamNum");
	if (s_bDebugMessages)
	{
		static char teamname[24];
		GetCSTeamName(s_OriginalClientTeam, teamname, sizeof(teamname));
		PrintToConsole(client, "[AWS] -> Player Team: %s", teamname);
	}

	int weaponteam = CS_TEAM_NONE;

	if (itemdefinition == 32 /* weapon_hkp2000 */ ||
		itemdefinition == 1 /* weapon_deagle */ ||
		itemdefinition == 23 /* weapon_mp5sd */ ||
		itemdefinition == 33 /* weapon_mp7 */ ||
		itemdefinition == 63 /* weapon_cz75a */ ||
		itemdefinition == 64 /* weapon_revolver */)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Detected: Checking Loadout Slot for '%s'", classname);

		int loadoutteam = (itemdefinition == 32) ? CS_TEAM_CT : s_OriginalClientTeam;

		Address pItemDefinition = GetItemDefinitionByName(classname);
		int iLoadoutSlot = GetLoadoutSlot(pItemDefinition, loadoutteam);
		Address _pItemDefinition = GetItemDefinitionInLoadout(client, loadoutteam, iLoadoutSlot);

		if (s_bDebugMessages)
		{
			static char teamname[24];
			GetCSTeamName(loadoutteam, teamname, sizeof(teamname));
			PrintToConsole(client, "[AWS] -> Item Definition of '%s'=%d, Item Definition in %s Loadout=%d -> %s", classname, pItemDefinition, teamname, _pItemDefinition, pItemDefinition == _pItemDefinition ? "Same" : "Different");
		}

		if (pItemDefinition != _pItemDefinition)
		{
			if (itemdefinition == 32)
			{
				weaponteam = CS_TEAM_T;

				if (s_bDebugMessages)
				{
					static char teamname[24];
					GetCSTeamName(weaponteam, teamname, sizeof(teamname));
					PrintToConsole(client, "[AWS] -> Forced Player Team to %s for spawning '%s' correctly", teamname, classname);
				}
			}
			else
			{
				int iAnotherTeam = view_as<int>(loadoutteam == 2) + 2;
				iLoadoutSlot = GetLoadoutSlot(pItemDefinition, iAnotherTeam);
				_pItemDefinition = GetItemDefinitionInLoadout(client, iAnotherTeam, iLoadoutSlot);

				if (pItemDefinition == _pItemDefinition)
				{
					weaponteam = iAnotherTeam;

					if (s_bDebugMessages)
					{
						static char teamname[24];
						GetCSTeamName(weaponteam, teamname, sizeof(teamname));
						PrintToConsole(client, "[AWS] -> Forced Player Team to %s because a matching item was found", teamname);
					}
				}
			}
		}
	}

	if (weaponteam == CS_TEAM_NONE)
		weaponteam = GetWeaponTeamByItemDefinition(itemdefinition);
	if (s_bDebugMessages)
	{
		static char teamname[24];
		GetCSTeamName(weaponteam, teamname, sizeof(teamname));
		PrintToConsole(client, "[AWS] -> Item Team: %s", teamname);
	}

	if (weaponteam == CS_TEAM_NONE)
		return bRoundChangeFix ? MRES_Handled : MRES_Ignored;

	if (s_OriginalClientTeam == weaponteam)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Skipped: Item and Player Teams match");
		return bRoundChangeFix ? MRES_Handled : MRES_Ignored;
	}

	SetEntProp(client, Prop_Data, "m_iTeamNum", weaponteam);
	s_TeamWasSwitched = true;
	if (s_bDebugMessages)
	{
		static char teamname[24];
		GetCSTeamName(weaponteam, teamname, sizeof(teamname));
		PrintToConsole(client, "[AWS] -> Set Player Team: %s", teamname);
	}
	return bRoundChangeFix ? MRES_Handled : MRES_Ignored;
}

public MRESReturn OnGiveNamedItemPost(int client, Handle hReturn, Handle hParams)
{
	if (s_bDebugMessages)
	{
		char classname[64];
		DHookGetParamString(hParams, 1, classname, sizeof(classname));
		PrintToConsole(client, "[AWS] OnGiveNamedItemPost(int client, char[] classname='%s')", classname);
	}

	if (!s_bEnable)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Plugin Disabled");
		return MRES_Ignored;
	}

	if (!s_TeamWasSwitched)
	{
		s_HookInUse = false;
		return MRES_Ignored;
	}

	s_TeamWasSwitched = false;
	SetEntProp(client, Prop_Data, "m_iTeamNum", s_OriginalClientTeam);
	if (s_bDebugMessages)
	{
		static char teamname[24];
		GetCSTeamName(s_OriginalClientTeam, teamname, sizeof(teamname));
		PrintToConsole(client, "[AWS] -> Set Player Team: %s", teamname);
	}

	s_HookInUse = false;
	return MRES_Ignored;
}

public Action OnPostWeaponEquip(int client, int weapon)
{
	if (s_HookInUse)
		return Plugin_Continue;

	if (s_bDebugMessages)
		PrintToConsole(client, "[AWS] OnPostWeaponEquip(weapon=%d)", weapon);

	if (!s_bEnable)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Plugin Disabled");
		return Plugin_Continue;
	}

	if (s_bSkipMapWeapons)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Skipped: Convar aws_skipmapweapons is 1");
		return Plugin_Continue;
	}

	// Skip utilities
	int itemdefinition = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	if (itemdefinition == 43 || itemdefinition == 44 || itemdefinition == 45 ||
		itemdefinition == 46 || itemdefinition == 47 || itemdefinition == 48 ||
		itemdefinition == 57 || itemdefinition == 68)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Skipped: IsUtility(defindex=%d)", itemdefinition);
		return Plugin_Continue;
	}

	if (s_bDebugMessages)
		PrintToConsole(client, "[AWS] -> Item Definition: %d", itemdefinition);

	// Check for map weapon
	if (!IsMapWeapon(weapon, true))
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Skipped: IsMapWeapon(weapon=%d) is false", weapon);
		return Plugin_Continue;
	}

	// Remake weapon string for m4a1_silencer, usp_silencer, cz75a, revolver and mp5sd
	char classname[64];
	switch (itemdefinition)
	{
		case 60:
		{
			if (s_bDebugMessages)
				PrintToConsole(client, "[AWS] -> Index 60: Classname reset to: weapon_m4a1_silencer from: %s", classname);
			classname = "weapon_m4a1_silencer";
		}
		case 61:
		{
			if (s_bDebugMessages)
				PrintToConsole(client, "[AWS] -> Index 61: Classname reset to: weapon_usp_silencer from: %s", classname);
			classname = "weapon_usp_silencer";
		}
		case 63:
		{
			if (s_bDebugMessages)
				PrintToConsole(client, "[AWS] -> Index 63: Classname reset to: weapon_cz75a from: %s", classname);
			classname = "weapon_cz75a";
		}
		case 64:
		{
			if (s_bDebugMessages)
				PrintToConsole(client, "[AWS] -> Index 64: Classname reset to: weapon_revolver from: %s", classname);
			classname = "weapon_revolver";
		}
		case 23:
		{
			if (s_bDebugMessages)
				PrintToConsole(client, "[AWS] -> Index 23: Classname reset to: weapon_mp5sd from: %s", classname);
			classname = "weapon_mp5sd";
		}
		default:
		{
			GetEdictClassname(weapon, classname, sizeof(classname));
		}
	}

	if (s_bDebugMessages)
		PrintToServer("[AWS] -> OnEntityClearedFromMapWeapons(entity=%d, classname=%s, mapweaponarraysize=%d)", weapon, classname, GetArraySize(s_hMapWeapons));

	// Skip if previously owned
	int m_hPrevOwner = GetEntProp(weapon, Prop_Send, "m_hPrevOwner");
	if (m_hPrevOwner > 0)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Skipped: Weapon previously owned by %d", m_hPrevOwner);
		return Plugin_Continue;
	}

	// Skip if the weapon is named while CvarSkipNamedWeapons is enabled
	if (s_bSkipNamedWeapons)
	{
		if (s_bDebugMessages)
			PrintToConsole(client, "[AWS] -> Convar: aws_skipnamedweapons is 1");

		char entname[64];
		GetEntPropString(weapon, Prop_Data, "m_iName", entname, sizeof(entname));
		if (!StrEqual(entname, ""))
		{
			if (s_bDebugMessages)
				PrintToConsole(client, "[AWS] -> Skipped: Weapon has name '%s'", entname);
			return Plugin_Continue;
		}
	}

	// Debug logging
	if (s_bDebugMessages)
		PrintToConsole(client, "[AWS] Respawning '%s' (definitionindex=%d)", classname, itemdefinition);

	// Processing weapon switch
	// Remove current weapon from player
	RemoveEntity(weapon);
	//AcceptEntityInput(weapon, "Kill");

	DataPack pack = new DataPack();
	RequestFrame(Frame_GivePlayerItem, pack);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteString(classname);

	return Plugin_Handled;
}

void Frame_GivePlayerItem(DataPack pack)
{
	if (pack == null)
		return;

	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	char classname[64];
	pack.ReadString(classname, sizeof(classname));
	delete pack;

	if (!client || classname[0] == '\0')
		return;

	// Give player new weapon so the GNI hook can set the correct team inside the GiveNamedItemEx call
	GivePlayerItem(client, classname);
}

/***************************************************
 * MAP WEAPON STUFF
 **************************************************/
stock bool IsMapWeapon(int entity, bool remove=false)
{
	if (s_hMapWeapons == null)
		return false;

	int count = GetArraySize(s_hMapWeapons);
	for (int i = 0; i < count; i++)
	{
		if (GetArrayCell(s_hMapWeapons, i) != entity)
			continue;

		if (remove)
			RemoveFromArray(s_hMapWeapons, i);
		return true;
	}
	return false;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// Skip if plugin is disabled
	if (!s_bEnable)
		return;

	// Skip if map weapons are not being replaced
	if (s_bSkipMapWeapons)
		return;

	// Skip if hook is in use!
	if (s_HookInUse)
		return;

	// Skip if map weapons array is null
	if (s_hMapWeapons == null)
		return;

	// Skip if GNI doesn't know the item definition
	int itemdefinition = GetItemDefinitionByClassname(classname);
	if (itemdefinition == -1)
		return;

	// Skip knives
	if (IsItemDefinitionKnife(itemdefinition))
		return;

	// Store the entity index as this is a map weapon
	PushArrayCell(s_hMapWeapons, entity);

	if (s_bDebugMessages)
		PrintToServer("[AWS] OnEntityCreated(entity=%d, classname=%s, itemdefinition=%d, mapweaponarraysize=%d)", entity, classname, itemdefinition, GetArraySize(s_hMapWeapons));
}

public void OnEntityDestroyed(int entity)
{
	if (IsMapWeapon(entity, true) && s_bDebugMessages)
		PrintToServer("[AWS] OnEntityDestroyed(entity=%d, mapweaponarraysize=%d)", entity, GetArraySize(s_hMapWeapons));
}

/***************************************************
 * ITEMS_GAME DATA STUFF
 **************************************************/
static Handle s_hWeaponClassname = null;
static Handle s_hWeaponItemDefinition = null;
static Handle s_hWeaponIsKnife = null;
static Handle s_hWeaponTeam = null;

stock int GetWeaponIndexOfClassname(const char[] classname)
{
	int count = GetArraySize(s_hWeaponClassname);
	char buffer[128];
	for (int i = 0; i < count; i++)
	{
		GetArrayString(s_hWeaponClassname, i, buffer, sizeof(buffer));
		if (StrEqual(buffer, classname))
			return i;
	}
	return -1;
}

public int GetItemDefinitionByClassname(const char[] classname)
{
	if (StrEqual(classname, "weapon_knife"))
		return 42;
	if (StrEqual(classname, "weapon_knife_t"))
		return 59;

	int count = GetArraySize(s_hWeaponItemDefinition);
	char buffer[64];
	for (int i = 0; i < count; i++)
	{
		GetArrayString(s_hWeaponClassname, i, buffer, sizeof(buffer));
		if (StrEqual(classname, buffer))
		{
			return GetArrayCell(s_hWeaponItemDefinition, i);
		}
	}
	return -1;
}

static int GetWeaponTeamByItemDefinition(int itemdefinition)
{
	// weapon_knife
	if (itemdefinition == 42)
		return CS_TEAM_CT;

	// weapon_knife_t
	if (itemdefinition == 59)
		return CS_TEAM_T;

	int count = GetArraySize(s_hWeaponTeam);
	for (int i = 0; i < count; i++)
	{
		if (GetArrayCell(s_hWeaponItemDefinition, i) == itemdefinition)
			return GetArrayCell(s_hWeaponTeam, i);
	}
	return CS_TEAM_NONE;
}

static bool IsItemDefinitionKnife(int itemdefinition)
{
	if (itemdefinition == 42 || itemdefinition == 59)
		return true;

	int count = GetArraySize(s_hWeaponItemDefinition);
	for (int i = 0; i < count; i++)
	{
		if (GetArrayCell(s_hWeaponItemDefinition, i) == itemdefinition)
		{
			if (GetArrayCell(s_hWeaponIsKnife, i))
				return true;
			else
				return false;
		}
	}
	return false;
}

stock bool BuildItems()
{
	Handle kv = CreateKeyValues("items_game");
	if (!FileToKeyValues(kv, "scripts/items/items_game.txt"))
	{
		LogError("Unable to open/read file at 'scripts/items/items_game.txt'.");
		delete kv;
		return false;
	}

	if (!KvJumpToKey(kv, "prefabs")) {
		delete kv;
		return false;
	}

	if (!KvGotoFirstSubKey(kv, false)) {
		delete kv;
		return false;
	}

	s_hWeaponClassname = CreateArray(128);
	s_hWeaponItemDefinition = CreateArray();
	s_hWeaponIsKnife = CreateArray();
	s_hWeaponTeam = CreateArray();

	// Loop through all prefabs
	char buffer[128];
	char classname[128];
	int len;
	do
	{
		// Get prefab value and check for weapon_base
		KvGetString(kv, "prefab", buffer, sizeof(buffer));
		if (StrEqual(buffer, "weapon_base") || StrEqual(buffer, "primary") || StrEqual(buffer, "melee"))
		{
			// This conditions are ignored
		}
		else
		{
			// Get the section name and check if its a weapon
			KvGetSectionName(kv, buffer, sizeof(buffer));
			if (StrContains(buffer, "weapon_") == 0)
			{
				// Remove _prefab to get the classname
				len = StrContains(buffer, "_prefab");
				if (len == -1) continue;
				strcopy(classname, len+1, buffer);

				// Store data
				PushArrayString(s_hWeaponClassname, classname);
				PushArrayCell(s_hWeaponItemDefinition, -1);
				PushArrayCell(s_hWeaponIsKnife, 0);

				if (!KvJumpToKey(kv, "used_by_classes"))
				{
					PushArrayCell(s_hWeaponTeam, CS_TEAM_NONE);
					continue;
				}

				int team_ct = KvGetNum(kv, "counter-terrorists");
				int team_t = KvGetNum(kv, "terrorists");

				if (team_ct)
				{
					if (team_t)
						PushArrayCell(s_hWeaponTeam, CS_TEAM_NONE);
					else
						PushArrayCell(s_hWeaponTeam, CS_TEAM_CT);
				}
				else if (team_t)
					PushArrayCell(s_hWeaponTeam, CS_TEAM_T);
				else
					PushArrayCell(s_hWeaponTeam, CS_TEAM_NONE);

				KvGoBack(kv);
			}
		}
	} while (KvGotoNextKey(kv));

	KvGoBack(kv);
	KvGoBack(kv);

	if (!KvJumpToKey(kv, "items")) {
		delete kv;
		return false;
	}

	if (!KvGotoFirstSubKey(kv, false)) {
		delete kv;
		return false;
	}

	char weapondefinition[12]; char weaponclassname[128]; char weaponprefab[128];
	do
	{
		KvGetString(kv, "name", weaponclassname, sizeof(weaponclassname));
		int index = GetWeaponIndexOfClassname(weaponclassname);

		// This item was not listed in the prefabs
		if (index == -1)
		{
			KvGetString(kv, "prefab", weaponprefab, sizeof(weaponprefab));

			// Skip knives
			if (!StrEqual(weaponprefab, "melee") && !StrEqual(weaponprefab, "melee_unusual"))
				continue;

			// Get weapon data
			KvGetSectionName(kv, weapondefinition, sizeof(weapondefinition));

			// Store weapon data
			PushArrayString(s_hWeaponClassname, weaponclassname);
			PushArrayCell(s_hWeaponItemDefinition, StringToInt(weapondefinition));
			PushArrayCell(s_hWeaponIsKnife, 1); // only knives are detected here
			PushArrayCell(s_hWeaponTeam, CS_TEAM_NONE);
		}

		// This item was found in prefabs. We just need to store the weapon index
		else
		{
			// Get weapon data
			KvGetSectionName(kv, weapondefinition, sizeof(weapondefinition));

			// Set weapon data
			SetArrayCell(s_hWeaponItemDefinition, index, StringToInt(weapondefinition));
		}

	} while (KvGotoNextKey(kv));

	delete kv;
	return true;
}

/***************************************************
 * CS_TEAM HELPERS
 **************************************************/
stock void GetCSTeamName(int team, char[] buffer, int size)
{
	switch (team)
	{
		case CS_TEAM_NONE:
		{
			strcopy(buffer, size, "CS_TEAM_NONE");
		}
		case CS_TEAM_SPECTATOR:
		{
			strcopy(buffer, size, "CS_TEAM_SPECTATOR");
		}
		case CS_TEAM_T:
		{
			strcopy(buffer, size, "CS_TEAM_T");
		}
		case CS_TEAM_CT:
		{
			strcopy(buffer, size, "CS_TEAM_CT");
		}
	}
}
