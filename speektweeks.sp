/*

SpeekTweeks - a plugin that utilizes specialized or otherwise "exclusive" voicelines (basically from mvm and valve comp)
for regular play, with a focus on granular control, allowing just the parts you want, and leaving off what you don't.

CHANGELOG
1.0 - Initial release
1.1 - Update code to newdecls, rewrite class-is-dead logic, mercenary round win responses
1.1.1 - hotfix to make class dead lines teammates-only again cause i broke it during the logic rewrite lol

TO-DO LIST:
* make team wipe minimum players count players on a TEAM, rather than on the server, so a 1v1 with 6 spectators doesn't still trigger team wipe lines

* improve "the round belongs to team!" lines - use "the match belongs to" lines when a team hits the winlimit, and make it properly count stopwatch rounds so that it only announces the winner of the half

* if a character teleports (teleporter/eureka effect) and narrowly dodges a projetile as a result, make them speak a "that was close!" line from MvM when they arrive

*/

#include <sourcemod>
#include <tf2_stocks>
#include <tf2>
#include <sdktools>

#pragma semicolon 1

#define VERSION "1.1.1"

//cvar handles
Handle g_Cvar_Enabled;
Handle g_Cvar_Teamwipe;
Handle g_Cvar_TeamwipeArena;
Handle g_Cvar_TeamwipeMin;
Handle g_Cvar_RoundstartComp;
Handle g_Cvar_RoundstartComp6s;
Handle g_Cvar_RoundstartAnnouncer;
Handle g_Cvar_RoundEndAnnouncer;
Handle g_Cvar_RoundEndPlayers;
Handle g_Cvar_ClassDead;
Handle g_Cvar_MaxDist;
Handle g_Cvar_MinTime;
Handle g_Cvar_BonusRoundTime;
bool g_ClassDeadCooldown = true;

bool gameActive = true; //global that will be toggled off if the game isn't in an active round (ie warmup, postround)
int roundResult = 0; //global for keeping track of the most recent round result, for storing during a round win and retrieval during round start

public Plugin myinfo =  {
	name = "SpeekTweeks",
	author = "muddy",
	description = "Makes the mercenaries and announcer more talkative",
	version = VERSION,
	url = ""
}


public void OnPluginStart() {
	//create CVARs
	CreateConVar("sm_speek_version", VERSION, "SpeekTweeks version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_Cvar_Enabled = CreateConVar("sm_speektweeks_enabled", "1", "Enable or disable SpeekTweeks as a whole", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_Teamwipe = CreateConVar("sm_speektweeks_teamwipe", "1", "Toggle \"Team wipe!\" announcer lines", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_TeamwipeArena = CreateConVar("sm_speektweeks_teamwipe_arena", "0", "Should \"Team wipe!\" lines play in Arena maps, where wiping the team isn't really impressive?", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_TeamwipeMin = CreateConVar("sm_speektweeks_teamwipe_min", "8", "Minimum active players required to trigger \"Team Wipe!\" lines", FCVAR_ARCHIVE, true, 0.0, true, 32.0);
	g_Cvar_RoundstartComp = CreateConVar("sm_speektweeks_roundstart_comp", "1", "Toggle Competitive mode round-start lines", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_RoundstartComp6s = CreateConVar("sm_speektweeks_roundstart_comp_6s", "1", "Toggle 6s-specific Competitive mode round-start lines (BROKEN, DOES NOT WORK, THX VALVE)", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_RoundstartAnnouncer = CreateConVar("sm_speektweeks_roundstart_announcer", "1", "Should the announcer yell \"GET FIGHTING!!\" when Setup time ends?", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_RoundEndAnnouncer = CreateConVar("sm_speektweeks_roundend_announcer", "1", "Toggle announcer lines for who won a round for spectators and SourceTV", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_RoundEndPlayers = CreateConVar("sm_speektweeks_roundend_players", "1", "Make winning players react with victory lines", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_ClassDead = CreateConVar("sm_speektweeks_classdead", "1", "Toggle \"<class> is dead!\" merc lines", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_MaxDist = CreateConVar("sm_speektweeks_classdead_searchdist", "10000.0", "How far from the victim to find a suitable teammate to speak the \"<class> is dead!\" line", FCVAR_ARCHIVE, true, 10.0 );
	g_Cvar_MinTime = CreateConVar("sm_speektweeks_classdead_delay", "5.0" ,"Cooldown before being eligible to shout a \"<class> is dead!\" line", FCVAR_ARCHIVE, true, 0.0);
	g_Cvar_BonusRoundTime = FindConVar("mp_bonusroundtime"); //get bonus round time so that we can play round-win announcer lines halfway through
	//command handles
	//these commands are used for manually managing contexts and firing responses at will
	RegConsoleCmd("sm_addcontext", Cmd_AddContext, "Manually add talker contexts to target"); //shorter command alias
	RegConsoleCmd("sm_speektweeks_addcontext", Cmd_AddContext, "Manually add talker contexts to target");
	RegConsoleCmd("sm_removecontext", Cmd_RemoveContext, "Manually remove talker contexts from target; pass ''all'' to clear all contexts from target"); //shorter command alias
	RegConsoleCmd("sm_speektweeks_removecontext", Cmd_RemoveContext, "Manually remove talker contexts from target; pass ''all'' to clear all contexts from target");
	RegConsoleCmd("sm_speakresponseconcept", Cmd_SpeakResponseConcept, "Manually make target speak selected response concept"); //shorter command alias
	RegConsoleCmd("sm_speektweeks_speakresponseconcept", Cmd_SpeakResponseConcept, "Manually make target speak selected response concept");
	AddCommandListener(VoiceMenuHookTest, "voicemenu");
	//event hooks
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("teamplay_round_start", Event_RoundStart);
	HookEvent("arena_round_start", Event_RoundStart);
	HookEvent("teamplay_win_panel", Event_RoundWin);	//winpanels fire on round wins, and i've heard they're more reliable to retrieve info about the end-of-round from,
	HookEvent("arena_win_panel", Event_RoundWin);		//so might as well hook winpanels instead of round_win events, in case i ever need to grab some info from them later.
	HookEvent("teamplay_waiting_begins", Event_WaitingForPlayers);
	HookEvent("teamplay_setup_finished", Event_SetupFinished);
	HookEvent("tf_game_over", Event_MatchEnd);
	HookEvent("teamplay_game_over", Event_MatchEnd);
}

public void OnMapStart() {
	roundResult = 0; //make sure the first round of a map is properly the "first round" for battle cry lines.
}

public void Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)  {
	//foundational work for info required on death events
	int deathflags = GetEventInt(event, "death_flags");
	bool silentKill = GetEventBool(event, "silent_kill");
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	TFClassType victimClass = TF2_GetPlayerClass(victim);
	//int killer = GetClientOfUserId(GetEventInt(event, "attacker")); //currently unused; uncomment when needed
	//TFClassType killerClass = TF2_GetPlayerClass(killer);

	if (!GetConVarBool(g_Cvar_Enabled) || victim < 1 || victim > MaxClients) { //don't process ANYTHING if the plugin is set to disabled, or if the victim is an out-of-bounds ID
		return;
	}

	//BEGIN CLASS IS DEAD LOGIC
	if (GetConVarBool(g_Cvar_ClassDead) && g_ClassDeadCooldown && !silentKill)
	{
		int nearestPlayer = FindNearestPlayer(victim, victimClass);
		if(nearestPlayer != -1)
		{
			char victimClassStr[64];
			
			AddContext(nearestPlayer, "randomnum:100");
			AddContext(nearestPlayer, "IsMvMDefender:1");
			
			switch(victimClass) {
				case TFClass_Scout: {
					Format(victimClassStr, sizeof(victimClassStr), "victimclass:Scout");
				} case TFClass_Soldier: {
					Format(victimClassStr, sizeof(victimClassStr), "victimclass:Soldier");
				} case TFClass_Pyro: {
					Format(victimClassStr, sizeof(victimClassStr), "victimclass:Pyro");
				} case TFClass_DemoMan: {
					Format(victimClassStr, sizeof(victimClassStr), "victimclass:Demoman");
				} case TFClass_Heavy: {
					Format(victimClassStr, sizeof(victimClassStr), "victimclass:Heavy");
				} case TFClass_Engineer: {
					Format(victimClassStr, sizeof(victimClassStr), "victimclass:Engineer");
				} case TFClass_Medic: {
					Format(victimClassStr, sizeof(victimClassStr), "victimclass:Medic");
				} case TFClass_Sniper: {
					Format(victimClassStr, sizeof(victimClassStr), "victimclass:Sniper");
				} case TFClass_Spy: {
					Format(victimClassStr, sizeof(victimClassStr), "victimclass:Spy");
				}
			}
			
			AddContext(nearestPlayer, victimClassStr);

			SpeakResponseConcept(nearestPlayer, "TLK_MVM_DEFENDER_DIED");
			ClearContext(nearestPlayer);
			
			float secs = GetConVarFloat(g_Cvar_MinTime);
			if(secs > 0)
			{
				g_ClassDeadCooldown = false;
				CreateTimer(secs, Timer_Wait);
			}
		}
	}
	
	if(deathflags & TF_DEATHFLAG_DEADRINGER) return;	//Any features beyond this point will not be triggered by dead ringer feign deaths
														//this means "class is dead" lines still trigger if a teammate feigns death for extra believability ;)
	
	//BEGIN TEAM WIPE LOGIC
	//check if server operator has feature enabled, and that the round is active, since we don't want team wipe lines during postround
	//we also check if the map is on arena mode and disable it since wiping the enemy team is a win condition of arena mode, unless they use the cvar to override this
	//all in all, 3/10 if statement. would like to make this better without just making a 2nd if statement for arena checking.
	if(GetConVarInt(g_Cvar_Teamwipe) && gameActive && (g_Cvar_TeamwipeArena || FindEntityByClassname(-1, "tf_logic_arena") <= -1)) {
		int pTeam = GetClientTeam(victim);
		int plyCount = 0;
		bool teamIsWiped = true; //assume team wiped unless we determine it hasn't
		for(int i = 1; i <= MaxClients; i++) {
			if(!IsClientInGame(i)) { continue; }
			plyCount = plyCount + 1; //keep track of how many valid clients have reached this checkpoint to check if we have enough candidates to actually play the line. for some reason plyCount++ refuses to work but plyCount + 1 does. weird world.
			if(GetClientTeam(i) == pTeam && IsPlayerAlive(i) && i != victim) teamIsWiped = false; //if even a single living player is on the same team as the victim, it's not a wipe. The victim is considered alive when event fires, so ignore them - we know they're dead anyway since they're the victim of the death event.
		}
		if(teamIsWiped && plyCount >= GetConVarInt(g_Cvar_TeamwipeMin)) { //at this point, the victim's team has wiped with their death. if we meet the minimum player cvar, let's play the sound.
			for(int i = 1; i <= MaxClients; i++) {
				if(!IsClientInGame(i)) { continue; }
				if(GetClientTeam(i) == pTeam) { //if you're on the same team as the victim, your team is the one that wiped.
					int chance = GetRandomInt(1, 8);
					if(chance > 1) { ClientCommand(i, "playgamesound Announcer.YourTeamWiped"); } else { ClientCommand(i, "playgamesound Announcer.MVM_All_Dead"); } //1-in-8 chance per client to play the MvM "HOW COULD YOU ALL DIE AT ONCE??" line in lieu of traditional team wipe line
				} else if((GetClientTeam(i) == 2 && pTeam == 3) || (GetClientTeam(i) == 3 && pTeam == 2)) { //if you're opposite the team that wiped, that means you wiped them. crazy o_O
					ClientCommand(i, "playgamesound Announcer.TheirTeamWiped");
				} else { //if the player hearing the wipe line isn't on red or blu (spec/unassgined/some weird limbo state), default to team wipe lines that aren't "your" or "their" team.
					if(pTeam == 2) { ClientCommand(i, "playgamesound Announcer.TeamWipeRed"); }	//also, SourceTV is considered "in spec," so all STV clients will hear these lines too. neat!
					if(pTeam == 3) { ClientCommand(i, "playgamesound Announcer.TeamWipeBlu"); }
				}
			}
		}
	}
}

public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast) {
	gameActive = true;
	//BEGIN ROUND START VOICELINE LOGIC
	int gameTied = 0;
	if(GetTeamScore(2) == GetTeamScore(3) && GetTeamScore(2) > 0) { gameTied = 1; } //if the teams have an equal score above 0, it's tied. We only check if RED's score is more than 0, since the first condition should imply BLU's will be, too.
	CreateTimer(4.0, DeterminePregameLine, gameTied); //originally i made this timer to make the lines less immediate and be forgiving for classchanges/latespawns, but i think i fucked something up cause moving the function's logic back here didn't work LOL
}

public void Event_SetupFinished(Handle event, const char[] name, bool dontBroadcast) {
	gameActive = true; //just in case
	//BEGIN SETUP ANNOUNCER VOICE LOGIC
	if(g_Cvar_RoundstartAnnouncer) {
		for(int i = 1; i <= MaxClients; i++) {
			if(!IsClientInGame(i)) continue;
			ClientCommand(i, "playgamesound Announcer.CompGameBeginsFight"); //"GET FIGHTING ALREADY!!" when setup time ends
		}
	}
}

public void Event_RoundWin(Handle event, const char[] name, bool dontBroadcast) {
	roundResult = GetEventInt(event, "winning_team");
	
	if(gameActive) {
		//BEGIN ROUND WIN ANNOUNCER LOGIC
		float speakDelay = GetConVarFloat(g_Cvar_BonusRoundTime) / 2.0; //make the announcer speak her line halfway past the post-round time. makes her say it quickly in competitive (where it lasts ~5 sec), but long enough for the music to stop in regular play
		if(GetConVarBool(g_Cvar_RoundEndAnnouncer)) {
			CreateTimer(speakDelay, AnnounceRoundResult, roundResult);
		}
		
		//BEGIN ROUND WIN PLAYER LOGIC
		if(GetConVarBool(g_Cvar_RoundEndPlayers)) {
			for(int i = 1; i <= MaxClients; i++) {
				if(CheckClient(i) && GetClientTeam(i) == roundResult) {
					CreateTimer(2.65, roundWinTimer, i);
				}
			}
		}
	}
	
	//special support for tDetailWinPanel, which replaces the default winpanel with a winpanel from Arena mode (shows lifetime, damage, healing, as well as top scorers)
	//but this event still fires even though the winpanel is swapped out, so if we set this to false here it won't do the voiceline a 2nd time when the arena winpanel fires.
	gameActive = false;
}

public Action roundWinTimer(Handle timer, int ply) {
	AddContext(ply, "OnWinningTeam:1");
	AddContext(ply, "randomnum:100");
	SpeakResponseConcept(ply, "TLK_GAME_OVER_COMP");
	return Plugin_Stop;
}

public void Event_WaitingForPlayers(Handle event, const char[] name, bool dontBroadcast) {
	gameActive = false;
	roundResult = 0;
}

public void Event_MatchEnd(Handle event, const char[] name, bool dontBroadcast) {
	gameActive = false;
	roundResult = 0;
}

public Action Cmd_AddContext(int client, int args) {
	char arg[128];
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml; //i have no idea what this does but it's in the API as well as basecommands so i guess we just include it?
	GetCmdArg(1, arg, sizeof(arg));
	target_count = ProcessTargetString(arg, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof(target_name), tn_is_ml);
	char addedContexts[256];
	
	if(GetCmdArgs() == 0 || (target_count == 1 && GetCmdArgs() == 1)) { ReplyToCommand(client, "[SM] Usage: sm_addcontext <contexts> OR sm_addcontext <target> <contexts>"); return Plugin_Handled; } //i'd do this BEFORE the stuff above, but we need to define target_count to handle a case like sm_addcontext @me
	if(target_count == 0) { target_list[0] = client; Format(target_name, sizeof(target_name), "yourself"); } //if no proper targets were selected, assume first arg was a context to add and set target as self
	
	for(int i = 0; target_list[i] != 0; i++) { //for each targeted client...
		for(int z = 1; z <= GetCmdArgs(); z++) { //for each passed arg...
			if(z == 1 && target_count != 0) continue; //if our first arg provided targets, assume it's not a talker context to add
			GetCmdArg(z, arg, sizeof(arg));
			AddContext(target_list[i], arg);
			if(z > 2 || (z > 1 && target_count == 0)) Format(arg, sizeof(arg), ", %s", arg); else Format(arg, sizeof(arg), "%s", arg);
			if(i == 0) StrCat(addedContexts, sizeof(addedContexts), arg); //only generate the added context string during our first pass through this for loop
		}
	}
	
	ReplyToCommand(client, "[SM] Added context(s) %s to %s.", addedContexts, target_name);
	
	return Plugin_Handled;
}

public Action Cmd_RemoveContext(int client, int args) {
	char arg[128];
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	bool removeAll = false;
	GetCmdArg(1, arg, sizeof(arg));
	target_count = ProcessTargetString(arg, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof(target_name), tn_is_ml);
	char removedContexts[256];
	
	if(GetCmdArgs() == 0 || (target_count == 1 && GetCmdArgs() == 1)) { ReplyToCommand(client, "[SM] Usage: sm_removecontext <contexts> OR sm_removecontext <target> <contexts> - use 'all' as a context to clear contexts"); return Plugin_Handled; }
	if(target_count == 0) { target_list[0] = client; Format(target_name, sizeof(target_name), "yourself"); }
	
	for(int i = 0; target_list[i] != 0; i++) { //for each targeted client...
		for(int z = 1; z <= GetCmdArgs(); z++) { //for each passed arg...
			if(z == 1 && target_count != 0) continue; //if our first arg provided targets, assume it's not a talker context to remove
			GetCmdArg(z, arg, sizeof(arg));
			if(strcmp(arg, "all", false) == 0 || strcmp(arg, "clear", false) == 0) {
				ClearContext(target_list[i]);
				removeAll = true;
				break; //if we pass "all" or "clear" as a context to remove, clear the context and stop checking further args for this client
			} else {
				RemoveContext(target_list[i], arg);
			}
			if(z > 2 || (z > 1 && target_count == 0)) Format(arg, sizeof(arg), ", %s", arg); else Format(arg, sizeof(arg), "%s", arg);
			if(i == 0 && removeAll != true) StrCat(removedContexts, sizeof(removedContexts), arg); //only generate the added context string during our first pass through this for loop, and if we're removing all don't even bother with this
		}
	}
	
	if(removeAll) {
		ReplyToCommand(client, "[SM] Removed all contexts from %s.", target_name);
	} else {
		ReplyToCommand(client, "[SM] Removed context(s) %s from %s.", removedContexts, target_name);
	}
	
	return Plugin_Handled;
}

public Action Cmd_SpeakResponseConcept(int client, int args) {
	char arg[128];
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	GetCmdArg(1, arg, sizeof(arg));
	target_count = ProcessTargetString(arg, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof(target_name), tn_is_ml);
	
	if(GetCmdArgs() == 0 || (target_count == 1 && GetCmdArgs() == 1)) { ReplyToCommand(client, "[SM] Usage: sm_speakresponseconcept <concept> OR sm_speakresponseconcept <target> <concept>"); return Plugin_Handled; }
	if(target_count == 0) { //since we're only accepting one arg after target, we can make this one a lot simpler
		SpeakResponseConcept(client, arg);
		Format(target_name, sizeof(target_name), "yourself");
	} else {
		GetCmdArg(2, arg, sizeof(arg));
		for(int i = 0; target_list[i] != 0; i++) {
			SpeakResponseConcept(target_list[i], arg);
		}
	}
	
	ReplyToCommand(client, "[SM] Spoke concept %s through %s.", arg, target_name);
	return Plugin_Handled;
}

//it's been a while since i've done SM scripting, let's shake the rust off.
//this function should intercept voicemenu 0 8 ("pass to me!" in first voice menu) and instead shout the "SNIPER!" line from MvM for classes that can.
//scratch that; putting a space after voicemenu are considered args. i have to catch voicemenu as a whole, and only apply when args "0 8" are passed. makes sense.
public Action VoiceMenuHookTest(int client, const char[] command, int argc) {
	char arg[4];
	GetCmdArgString(arg, sizeof(arg));
	//check if issuing voicemenu 0 8 or voicemenu 1 8, both voice menus which harbor "Pass to me!," and instead play the MvM sniper callout.
	if(strcmp(arg, "0 8", false) == 0 || strcmp(arg, "1 8") == 0 ) {
		AddContext(client, "IsMvMDefender:1");
		AddContext(client, "randomnum:100");
		SpeakResponseConcept(client, "TLK_MVM_SNIPER_CALLOUT");
		return Plugin_Handled; //well, that was easier than i thought it'd be.
	}
	//since we return within our if statement, we'll never reach this if we clear our if condition
	return Plugin_Continue;
}

public Action DeterminePregameLine(Handle timer, bool gameTied) { //determine which line should be spoken per client, and call to speak it
	if(!GetConVarBool(g_Cvar_RoundstartComp)) { return Plugin_Stop; }
	for(int i = 1; i <= MaxClients; i++) {
		if(!CheckClient(i)) { continue; } //CheckClient() checks if they're in game, as well as alive and not under cloak or disguise effects. not that you need to be sneaky for battle cries, but still.
		if(roundResult == 0 && GetTeamScore(2) == 0 && GetTeamScore(3) == 0) { PlayPregameLine(i, 0, 0, gameTied); }
		else if(roundResult == GetClientTeam(i)) { PlayPregameLine(i, 1, 0, gameTied); }
		else if(gameTied) { PlayPregameLine(i, 1, 2, gameTied); }
		else { PlayPregameLine(i, 1, 1, gameTied); }
	}
	return Plugin_Stop;
}

public Action AnnounceRoundResult(Handle timer, int result) {
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i) || GetClientTeam(i) >= 2) { continue; }
		if(result == 3) { ClientCommand(i, "playgamesound Announcer.CompRoundWinBlu"); }
		else if(result == 2) { ClientCommand(i, "playgamesound Announcer.CompRoundWinRed"); }
	}
	return Plugin_Stop;
}

public Action Timer_Wait(Handle timer) {
	g_ClassDeadCooldown = true;
}

public int FindNearestPlayer(int ply, TFClassType plyClass) {
	
	float plyPos[3], targetPos[3], posDiff;
	float maxDist = GetConVarFloat(g_Cvar_MaxDist);
	int nearest = -1;
	GetClientAbsOrigin(ply, plyPos);
	
	for(int i = 1; i <= MaxClients; i++) {
		if(CheckClient(i) && i != ply) {
			GetClientAbsOrigin(i, targetPos);
			posDiff = GetVectorDistance(plyPos, targetPos, false);
			if(posDiff < maxDist) {
				TFClassType iClass = TF2_GetPlayerClass(i);
				//if the speaker is engy, solly, or med, we're good. if they're a heavy, make sure the vicitm isn't a soldier since heavy doesn't have a soldier is dead line.
				if(((iClass == TFClass_Engineer || iClass == TFClass_Soldier || iClass == TFClass_Medic) || (iClass == TFClass_Heavy && plyClass != TFClass_Soldier)) && GetClientTeam(i) == GetClientTeam(ply)) {
					maxDist = posDiff;
					nearest = i;
				}
			}
		}
	}
	return nearest;
}

public void PlayPregameLine(int client, int notFirstRound, int lostPrevRound, int gameTied) {	
	char tempString[64];
	int sixes = GetConVarInt(g_Cvar_RoundstartComp6s);
	
	Format(tempString, sizeof(tempString), "IsComp6v6:%i", sixes);
	AddContext(client, tempString);
	
	Format(tempString, sizeof(tempString), "RoundsPlayed:%i", notFirstRound);
	AddContext(client, tempString);
	
	Format(tempString, sizeof(tempString), "PrevRoundWasTie:%i", gameTied);
	AddContext(client, tempString);
	
	Format(tempString, sizeof(tempString), "LostRound:%i", lostPrevRound);
	AddContext(client, tempString);
	
	AddContext(client, "randomnum:100"); //regardless of which line they speak, we want them to speak it - rig the 40% chance into 100%.
	SpeakResponseConcept(client, "TLK_ROUND_START_COMP");
	ClearContext(client);
}

public Action SixesLineTimer(Handle timer, DataPack pack) {
	char vcdPath[64];
	pack.Reset();
	int ply = pack.ReadCell();
	pack.ReadString(vcdPath, sizeof(vcdPath));
	SpeakSpecificLine(ply, vcdPath);
	return Plugin_Stop;
}

stock void AddContext(int client, const char[] context) { //functions to condense adding context so that it looks cleaner
	SetVariantString(context);
	AcceptEntityInput(client, "AddContext");
}

stock void RemoveContext(int client, const char[] context) {
	SetVariantString(context);
	AcceptEntityInput(client, "RemoveContext");
}

stock void SpeakResponseConcept(int client, const char[] concept) { //same for speaking concepts 
	SetVariantString(concept);
	AcceptEntityInput(client, "SpeakResponseConcept");
}

stock void SpeakSpecificLine(int client, const char[] vcdPath) {
	int scene = CreateEntityByName("instanced_scripted_scene");
	DispatchKeyValue(scene, "SceneFile", vcdPath);
	DispatchSpawn(scene);
	SetEntPropEnt(scene, Prop_Data, "m_hOwner", client);
	ActivateEntity(scene);
	AcceptEntityInput(scene, "Start", client, client);
}

stock void ClearContext(int client) { //ok this one is one line and i have less justification but i'm doin it
	AcceptEntityInput(client, "ClearContext");
}

public bool CheckClient(int client) { //check if the client is valid, as well as if they should attempt to speak (ie alive and not cloaked or disguised)
	if (client < 1 || client >= MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) ||
	TF2_IsPlayerInCondition(client, TFCond_Cloaked) || TF2_IsPlayerInCondition(client, TFCond_Disguised) || 
	TF2_IsPlayerInCondition(client, TFCond_CloakFlicker) || TF2_IsPlayerInCondition(client, TFCond_Stealthed) || 
	TF2_IsPlayerInCondition(client, TFCond_StealthedUserBuffFade))	//turns out, there's logic here to make sure the player isn't cloaked or disguised. the version that did the "class is dead" lines never utilized this though, since spy doesn't have these lines.
	{																//since we're future-proofing this check for any time a character should speak, we'll keep it AND add checks for if the user is under the effects of the cloaking halloween spell.
		return false;
	}
	return true;
}
