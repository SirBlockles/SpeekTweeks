/*

 !!! THIS IS THE STAGING/DEVEL VERSION, NOT THE GITHUB ONE! MAKE SURE YOU'RE UPDATING THAT, MUDDY !!!

SpeekTweeks - a plugin that utilizes specialized or otherwise "exclusive" voicelines (basically from mvm and valve comp)
for regular play, with a focus on granular control, allowing just the parts you want, and leaving off what you don't.

CHANGELOG
1.0 - Initial release

TO-DO LIST:

* Do players who are ignored for "class is dead!" lines end the search since they're an "eligible" player? If so, we need to make the search ignore players on cooldown so that the next-nearest player can call it.

* make team wipe minimum players count players on a TEAM, rather than on the server, so a 1v1 with 6 spectators doesn't still trigger team wipe lines

* refactor "class is dead" lines - still uses overly-complicated code from original plugin.
  > we don't need class checks to make sure the player can say it - if you speak the concept on a class that doesn't have it, nothing simply happens and the world goes on.

* "SNIPER!" calls from MvM - two ideas for implementation
  1) when a sniper shoots and your character is near their crosshair (either a hit or a close miss), applicable classes will automatically shout "SNIPER!"
  2) replace the "pass to me!" voice call with "SNIPER!" in non-passtime situations (if possible) - can possibly be done by listening for voicemenu 0 8, or whatever it is for "pass to me!"

* improve "the round belongs to team!" lines - use "the match belongs to" lines when a team hits the winlimit, and make it properly count stopwatch rounds so that it only announces the winner of the half

* if a character teleports (teleporter/eureka effect) and narrowly dodges a projetile as a result, make them speak a "that was close!" line from MvM when they arrive

*/

#include <sourcemod>
#include <tf2_stocks>
#include <tf2>
#include <sdktools>

#define VERSION "1.0"

#define EVERYONE 0			//Every player
#define SAME_TEAM 1			//Every player in the same team
#define WITH_VOICE_LINES 2	//Every player in the same team AND with mvm voice lines
#define WITH_VOICE_LINES_NH 3	//Every player in the same team AND with mvm voice lines, excluding heavy (for class is dead lines)

//cvar handles
Handle g_Cvar_Enabled;
Handle g_Cvar_Teamwipe;
Handle g_Cvar_TeamwipeArena;
Handle g_Cvar_TeamwipeMin;
Handle g_Cvar_RoundstartComp;
Handle g_Cvar_RoundstartComp6s;
Handle g_Cvar_RoundstartAnnouncer;
Handle g_Cvar_RoundEnd;
Handle g_Cvar_ClassDead;
Handle g_Cvar_MaxDist;
Handle g_Cvar_MinTime;
Handle g_Cvar_BonusRoundTime;
bool g_ClassDeadCooldown = true;

bool gameActive = true; //global that will be toggled off if the game isn't in an active round (ie warmup, postround)
int roundResult = 0; //global for keeping track of the most recent round result, for storing during a round win and retrieval during round start

/*
	TFClass_Unknown = 0,
	TFClass_Scout,
	TFClass_Sniper,
	TFClass_Soldier,
	TFClass_DemoMan,
	TFClass_Medic,
	TFClass_Heavy,
	TFClass_Pyro,
	TFClass_Spy,
	TFClass_Engineer
	*/
char g_ClassNames[TFClassType][16] = { "Unknown", "Scout", "Sniper", "Soldier", "Demoman", "Medic", "Heavy", "Pyro", "Spy", "Engineer"};

public Plugin myinfo = 
{
	name = "SpeekTweeks",
	author = "muddy",
	description = "Makes the mercenaries and announcer more talkative",
	version = VERSION,
	url = ""
}


public OnPluginStart()
{
	//create CVARs
	CreateConVar("sm_speek_version", VERSION, "SpeekTweeks version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_Cvar_Enabled = CreateConVar("sm_speektweeks_enabled", "1", "Enable or disable SpeekTweeks as a whole", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_Teamwipe = CreateConVar("sm_speektweeks_teamwipe", "1", "Toggle ''Team wipe!'' announcer lines", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_TeamwipeArena = CreateConVar("sm_speektweeks_teamwipe_arena", "0", "Should ''Team wipe!'' lines play in Arena maps, where wiping the team isn't really impressive?", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_TeamwipeMin = CreateConVar("sm_speektweeks_teamwipe_min", "8", "Minimum active players required to trigger ''Team Wipe!'' lines", FCVAR_ARCHIVE, true, 0.0, true, 32.0);
	g_Cvar_RoundstartComp = CreateConVar("sm_speektweeks_roundstart_comp", "1", "Toggle Competitive mode round-start lines", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_RoundstartComp6s = CreateConVar("sm_speektweeks_roundstart_comp_6s", "0", "Toggle 6s-specific Competitive mode round-start lines", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_RoundstartAnnouncer = CreateConVar("sm_speektweeks_roundstart_announcer", "1", "Should the announcer yell ''GET FIGHTING!!'' when Setup time ends?", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_RoundEnd = CreateConVar("sm_speektweeks_roundend", "1", "Toggle announcer lines declaring who won a round, announces who won match when mp_winlimit is hit", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_ClassDead = CreateConVar("sm_speektweeks_classdead", "1", "Toggle ''<class> is dead!'' merc lines", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	g_Cvar_MaxDist = CreateConVar("sm_speektweeks_classdead_searchdist", "10000.0", "How far from the victim to find a suitable teammate to speak the ''<class> is dead!'' line", FCVAR_ARCHIVE, true, 10.0 );
	g_Cvar_MinTime = CreateConVar("sm_speektweeks_classdead_delay", "10.0" ,"Cooldown before being eligible to shout a ''<class> is dead!'' line", FCVAR_ARCHIVE, true, 0.0)
	g_Cvar_BonusRoundTime = FindConVar("mp_bonusroundtime"); //get bonus round time so that we can play round-win announcer lines halfway through
	//command handles
	//these commands are used for manually managing contexts and firing responses at will
	RegConsoleCmd("sm_addcontext", Cmd_AddContext, "Manually add talker contexts to target"); //shorter command alias
	RegConsoleCmd("sm_speektweeks_addcontext", Cmd_AddContext, "Manually add talker contexts to target");
	RegConsoleCmd("sm_removecontext", Cmd_RemoveContext, "Manually remove talker contexts from target; pass ''all'' to clear all contexts from target"); //shorter command alias
	RegConsoleCmd("sm_speektweeks_removecontext", Cmd_RemoveContext, "Manually remove talker contexts from target; pass ''all'' to clear all contexts from target");
	RegConsoleCmd("sm_speakresponseconcept", Cmd_SpeakResponseConcept, "Manually make target speak selected response concept"); //shorter command alias
	RegConsoleCmd("sm_speektweeks_speakresponseconcept", Cmd_SpeakResponseConcept, "Manually make target speak selected response concept");
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

public OnMapStart() {
	roundResult = 0; //make sure the first round of a map is properly the "first round" for battle cry lines.
}

public Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
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
	//This is a slightly modified version of ClassicGuzzi's original class is dead response logic, the plugin which this one was originally derived.
	//TODO: rewrite the logic for "class is dead" lines using a switch statement checking hard-coded numbers intead of enums, since the TFClass IDs are very, very unlikely to change, ever
	if (GetConVarBool(g_Cvar_ClassDead) && g_ClassDeadCooldown && !silentKill) //oh neat, it ignores kills from weapons marked with "silent killer"
	{
		int nearPlayer  = FindNearestPlayer(victim, WITH_VOICE_LINES);
		if(nearPlayer != -1 && CheckClient(nearPlayer))
		{
			PlayClassDead(nearPlayer,victimClass);
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
		for(new i = 1; i <= MaxClients; i++) {
			if(!IsClientInGame(i)) { continue; }
			plyCount = plyCount + 1; //keep track of how many valid clients have reached this checkpoint to check if we have enough candidates to actually play the line. for some reason plyCount++ refuses to work but plyCount + 1 does. weird world.
			if(GetClientTeam(i) == pTeam && IsPlayerAlive(i) && i != victim) teamIsWiped = false; //if even a single living player is on the same team as the victim, it's not a wipe. The victim is considered alive when event fires, so ignore them - we know they're dead anyway since they're the victim of the death event.
		}
		if(teamIsWiped && plyCount >= GetConVarInt(g_Cvar_TeamwipeMin)) { //at this point, the victim's team has wiped with their death. if we meet the minimum player cvar, let's play the sound.
			for(new i = 1; i <= MaxClients; i++) {
				if(!IsClientInGame(i)) continue;
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

public Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	gameActive = true;
	//BEGIN ROUND START VOICELINE LOGIC
	int gameTied = 0;
	if(GetTeamScore(2) == GetTeamScore(3) && GetTeamScore(2) > 0) { gameTied = 1; } //if the teams have an equal score above 0, it's tied. We only check if RED's score is more than 0, since the first condition should imply BLU's will be, too.
	CreateTimer(4.0, DeterminePregameLine, gameTied); //originally i made this timer to make the lines less immediate and be forgiving for classchanges/latespawns, but i think i fucked something up cause moving the function's logic back here didn't work LOL
}

public Event_SetupFinished(Handle event, const char[] name, bool dontBroadcast) //how do i 
{
	gameActive = true; //just in case
	//BEGIN SETUP ANNOUNCER VOICE LOGIC
	if(g_Cvar_RoundstartAnnouncer) {
		for(new i = 1; i <= MaxClients; i++) {
			if(!IsClientInGame(i)) continue;
			ClientCommand(i, "playgamesound Announcer.CompGameBeginsFight"); //"GET FIGHTING ALREADY!!" when setup time ends
		}
	}
}

public Event_RoundWin(Handle event, const char[] name, bool dontBroadcast)
{
	roundResult = GetEventInt(event, "winning_team");
	
	if(gameActive) {
		//BEGIN ROUND WIN ANNOUNCER LOGIC
		float speakDelay = GetConVarFloat(g_Cvar_BonusRoundTime) / 2.0; //make the announcer speak her line halfway past the post-round time. makes her say it quickly in competitive (where it lasts ~5 sec), but long enough for the music to stop in regular play
		if(GetConVarInt(g_Cvar_RoundEnd)) {
			CreateTimer(view_as<float>(speakDelay), AnnounceRoundResult, roundResult);
		}
	}
	//special support for tDetailWinPanel, which replaces the default winpanel with a winpanel from Arena mode (shows lifetime, damage, healing, as well as top scorers)
	//but this event still fires even though the winpanel is swapped out, so if we set this to false here it won't do the voiceline a 2nd time when the arena winpanel fires.
	gameActive = false;
}

public Event_WaitingForPlayers(Handle event, const char[] name, bool dontBroadcast)
{
	gameActive = false;
	roundResult = 0;
}

public Event_MatchEnd(Handle event, const char[] name, bool dontBroadcast)
{
	gameActive = false;
	roundResult = 0;
}

public Action Cmd_AddContext(client, args)
{
	char arg[128];
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml; //i have no idea what this does but it's in the API as well as basecommands so i guess we just include it?
	GetCmdArg(1, arg, sizeof(arg));
	target_count = ProcessTargetString(arg, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof(target_name), tn_is_ml);
	char addedContexts[256];
	
	if(GetCmdArgs() == 0 || (target_count == 1 && GetCmdArgs() == 1)) { ReplyToCommand(client, "[SM] Usage: sm_addcontext <contexts> OR sm_addcontext <target> <contexts>"); return Plugin_Handled; } //i'd do this BEFORE the stuff above, but we need to define target_count to handle a case like sm_addcontext @me
	if(target_count == 0) { target_list[0] = client; Format(target_name, sizeof(target_name), "yourself"); } //if no proper targets were selected, assume first arg was a context to add and set target as self
	
	for(new i = 0; target_list[i] != 0; i++) { //for each targeted client...
		for(new z = 1; z <= GetCmdArgs(); z++) { //for each passed arg...
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

public Action Cmd_RemoveContext(client, args)
{
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
	
	for(new i = 0; target_list[i] != 0; i++) { //for each targeted client...
		for(new z = 1; z <= GetCmdArgs(); z++) { //for each passed arg...
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

public Action Cmd_SpeakResponseConcept(client, args)
{
	char arg[128];
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	GetCmdArg(1, arg, sizeof(arg));
	target_count = ProcessTargetString(arg, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof(target_name), tn_is_ml);
	
	if(GetCmdArgs() == 0 || (target_count == 1 && GetCmdArgs() == 1)) ReplyToCommand(client, "[SM] Usage: sm_speakresponseconcept <concept> OR sm_speakresponseconcept <target> <concept>"); return Plugin_Handled;
	if(target_count == 0) { //since we're only accepting one arg after target, we can make this one a lot simpler
		SpeakResponseConcept(client, arg);
		Format(target_name, sizeof(target_name), "yourself");
	} else {
		GetCmdArg(2, arg, sizeof(arg));
		for(new i = 0; target_list[i] != 0; i++) {
			SpeakResponseConcept(target_list[i], arg);
		}
	}
	
	ReplyToCommand(client, "[SM] Spoke concept %s through %s.", arg, target_name);
	return Plugin_Handled;
}

public Action DeterminePregameLine(Handle timer, bool gameTied) //determine which line should be spoken per client, and call to speak it
{
	for(new i = 1; i <= MaxClients; i++) {
		if(!CheckClient(i)) { continue; } //CheckClient() checks if they're in game, as well as alive and not under cloak or disguise effects. not that you need to be sneaky for battle cries, but still.
		if(g_Cvar_RoundstartComp) {
			if(roundResult == 0 && !gameTied) { PlayPregameLine(i, GetConVarInt(g_Cvar_RoundstartComp6s), 0, 2); }
			else if(roundResult == GetClientTeam(i)) { PlayPregameLine(i, GetConVarInt(g_Cvar_RoundstartComp6s), 1, 0); }
			else if(gameTied) { PlayPregameLine(i, GetConVarInt(g_Cvar_RoundstartComp6s), 1, 2); }
			else { PlayPregameLine(i, GetConVarInt(g_Cvar_RoundstartComp6s), 1, 1); }
		}
	}
	return Plugin_Stop;
}

public Action AnnounceRoundResult(Handle timer, result)
{
	for(new i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i)) { continue; }
		if(result == 3) { ClientCommand(i, "playgamesound Announcer.CompRoundWinBlu"); }
		else if(result == 2) { ClientCommand(i, "playgamesound Announcer.CompRoundWinRed"); }
	}
	return Plugin_Stop;
}

public Action Timer_Wait(Handle timer)
{
	g_ClassDeadCooldown = true;
}

FindNearestPlayer(client,const type)
{
	float pVec[3];
	float nVec[3];
	GetClientEyePosition(client, pVec); 
	int found = -1;
	float found_dist = GetConVarFloat(g_Cvar_MaxDist);
	float aux_dist; 
	
	switch(type)
	{
		case EVERYONE:
		{
			for (new i = 1; i <= MaxClients; i++)
			{
				if(i != client && CheckClient(i))
				{
					GetClientEyePosition(i, nVec);
					aux_dist = GetVectorDistance(pVec, nVec, false)
					if(aux_dist < found_dist)
					{
						found = i;
						found_dist = aux_dist;
					}
				}
			}
		}
		
		case SAME_TEAM:
		{
			int pTeam = GetClientTeam(client);
			for (new i = 1; i <= MaxClients; i++)
			{
				if(i != client && CheckClient(i) && pTeam == GetClientTeam(i))
				{
					GetClientEyePosition(i, nVec);
					aux_dist = GetVectorDistance(pVec, nVec, false)
					if(aux_dist < found_dist)
					{
						found = i;
						found_dist = aux_dist;
					}
				}
			}
		}
		case WITH_VOICE_LINES:
		{
			int pTeam = GetClientTeam(client);
			for (new i = 1; i <= MaxClients; i++)
			{
				if(i != client && CheckClient(i) && pTeam == GetClientTeam(i) && ClientHasMvMLines(i))
				{
					GetClientEyePosition(i, nVec);
					aux_dist = GetVectorDistance(pVec, nVec, false)
					if(aux_dist < found_dist)
					{
						found = i;
						found_dist = aux_dist;
					}
				}
			}
		}
		case WITH_VOICE_LINES_NH:
		{
			int pTeam = GetClientTeam(client);
			for (new i = 1; i <= MaxClients; i++)
			{
				if(i != client && CheckClient(i) && pTeam == GetClientTeam(i) && ClientHasMvMLinesNH(i))
				{
					GetClientEyePosition(i, nVec);
					aux_dist = GetVectorDistance(pVec, nVec, false)
					if(aux_dist < found_dist)
					{
						found = i;
						found_dist = aux_dist;
					}
				}
			}
		}
		
	}
	return found;
}

//part of that old code from the other guy. this indexes which classes have "class is dead" lines, and includes a second function just to exclude heavy.
//heavy has no "soldier is dead!" line, which is the basis for that, but if you fire the "class is dead" response concept with invalid information, they just don't speak it.
//this entire check here is unneccesary and will be removed when i re-write the "class is dead" logic.
bool ClientHasMvMLines(client)
{
	if( TF2_GetPlayerClass(client) == TFClass_Soldier 
	|| TF2_GetPlayerClass(client) == TFClass_Medic 
	|| TF2_GetPlayerClass(client) == TFClass_Heavy 
	|| TF2_GetPlayerClass(client) == TFClass_Engineer)
	{
		return true;
	}
	return false;
}
bool ClientHasMvMLinesNH(client)
{
	if( TF2_GetPlayerClass(client) == TFClass_Soldier 
	|| TF2_GetPlayerClass(client) == TFClass_Medic 
	|| TF2_GetPlayerClass(client) == TFClass_Engineer)
	{
		return true;
	}
	return false;
}

PlayClassDead(client,TFClassType:victimClass)
{
	char victimClassContext[64];
	
	AddContext(client, "randomnum:100");
	AddContext(client, "IsMvMDefender:1");
	
	Format(victimClassContext, sizeof(victimClassContext), "victimclass:%s", g_ClassNames[victimClass]);
	AddContext(client, victimClassContext);

	SpeakResponseConcept(client, "TLK_MVM_DEFENDER_DIED");
	ClearContext(client);
}

PlayPregameLine(client, sixes, notFirstRound, lostPrevRound)
{
	char tempString[64];
	
	if(lostPrevRound == 2) { //a loss result of 2 is when the game ends up tied. for some reason, the mercs refuse to speak their lines here anyway. i have no idea why.
		ClearContext(client);
		
		AddContext(client, "randomnum:100");
		AddContext(client, "IsComp6v6:1");
		AddContext(client, "RoundsPlayed:1");
		AddContext(client, "LostRound:1");
		AddContext(client, "PrevRoundWasTie:1");
	} else { //with the comment above - if the player refuses to speak a tie line, they speak a round won line. when they do this, this IF check makes them not speak their round win lines either, and they just default to a battle cry. WHY??
		Format(tempString, sizeof(tempString), "IsComp6v6:%i", sixes);
		AddContext(client, tempString);
		
		Format(tempString, sizeof(tempString), "RoundsPlayed:%i", notFirstRound);
		AddContext(client, tempString);
		
		AddContext(client, "PrevRoundWasTie:0");
		
		Format(tempString, sizeof(tempString), "LostRound:%i", lostPrevRound);
		AddContext(client, tempString);
	}
	AddContext(client, "randomnum:100"); //regardless of which line they speak, we want them to speak it - rig the 40% chance into 100%.
	SpeakResponseConcept(client, "TLK_ROUND_START_COMP");
	ClearContext(client);
}

stock void AddContext(int client, const char[] context) //functions to condense adding context so that it looks cleaner
{
	SetVariantString(context);
	AcceptEntityInput(client, "AddContext");
}

stock void RemoveContext(int client, const char[] context)
{
	SetVariantString(context);
	AcceptEntityInput(client, "RemoveContext");
}

stock void SpeakResponseConcept(int client, const char[] concept) //same for speaking concepts
{
	SetVariantString(concept);
	AcceptEntityInput(client, "SpeakResponseConcept");
}

stock void ClearContext(int client) //ok this one is one line and i have less justification but i'm doin it
{
	AcceptEntityInput(client, "ClearContext");
}

bool CheckClient(client) //check if the client is valid, as well as if they should attempt to speak (ie alive and not cloaked or disguised)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) ||
	TF2_IsPlayerInCondition(client, TFCond_Cloaked) || TF2_IsPlayerInCondition(client, TFCond_Disguised) || 
	TF2_IsPlayerInCondition(client, TFCond_CloakFlicker) || TF2_IsPlayerInCondition(client, TFCond_Stealthed) || 
	TF2_IsPlayerInCondition(client, TFCond_StealthedUserBuffFade))	//turns out, there's logic here to make sure the player isn't cloaked or disguised. the version that did the "class is dead" lines never utilized this though, since spy doesn't have these lines.
	{																//since we're future-proofing this check for any time a character should speak, we'll keep it AND add checks for if the user is under the effects of the cloaking halloween spell.
		return false;
	}
	return true;
}
