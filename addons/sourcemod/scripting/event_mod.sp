#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <store>
#include "colors_csgo.inc"
#include "emitsoundany.inc"

/*
* Plugin Information - Please do not change this
*/
public Plugin:myinfo =
{
	name        = "Event Mod",
	author      = "Invex | Byte",
	description = "Modifies players and their enviroments to create custom event days.",
	version     = "1.23",
	url         = "http://www.invexgaming.com.au"
};

/*
* Global Variables
*/
//Enumerations
enum EVENTS
{
   NUM_OF_EVENTS = 17,
   EVENT_NOEVENT = 0,
   EVENT_NORMAL = 0,
   EVENT_FREEFORALL = 1,
   EVENT_SLAP = 2,
   EVENT_DRUG = 3,
   EVENT_KNIFEONLY = 4,
   EVENT_DEAGLEONLY = 5,
   EVENT_TEC9ONLY = 6,
   EVENT_NEGEVONLY = 7,
   EVENT_SSGONLY = 8,
   EVENT_AWPONLY = 9,
   EVENT_DAKDAKONLY = 10,
   EVENT_ZEUSONLY = 11,
   EVENT_HEONLY = 12,
   EVENT_1HPDECOY = 13,
   EVENT_HSONLY = 14,
   EVENT_PISTOLHSONLY = 15,
   EVENT_LIFEDRAIN = 16
};


//Strings
new String:PREFIX[] = "[{olive}EventMod{default}] ";
new String:eventList[NUM_OF_EVENTS][] = 
{ 
  "Normal Round (No Event)",   
  "Free For All Round",
  "Slap Round (30 seconds)",
  "Drug Round (30 seconds)",
  "Knife Only Round",
  "Deagle Only Round",
  "Tec9 Only Round",
  "Negev Only Round",
  "SSG08 Only Round",
  "AWP Only Round",
  "G3SG1 (DAK DAK) Only Round",
  "Zeus Only Round",
  "HE Grenade Only Round",
  "1HP Decoy Only Round",
  "Headshot Only Round",
  "Random Pistol Headshot Only Round",
  "Lifedrain Round (FFA)"
}

new String:eventDesc[NUM_OF_EVENTS][] = 
{
  "", //blank for normal rounds
  "Last man standing wins! Prize Pool: {green}100{default} credits.",
  "Prepare to get slapped for {green}30{default} seconds!",
  "Prepare to be drugged {green}30{default} seconds!",
  "Stab em where it hurts! Prize Pool: {green}75{default} credits.",
  "One Deag it up. Prize Pool: {green}75{default} credits.",
  "I heard this weapon is hard to use. Prize Pool: {green}75{default} credits.",
  "Oh boy..... Prize Pool: {green}75{default} credits.",
  "Scoutz n Knives! Prize Pool: {green}75{default} credits.",
  "Don't leg em. Prize Pool: {green}85{default} credits.",
  "Bring out your inner Silver. Prize Pool: {green}50{default} credits.",
  "Don't miss your first shot. Prize Pool: {green}115{default} credits.",
  "Kabooooom! Prize Pool: {green}85{default} credits.",
  "Bonus points for headshots! Prize Pool: {green}115{default} credits.",
  "AWPs won't help you in this round friend. Prize Pool: {green}85{default} credits.",
  "If you got the Tec9 then you are officially cheating! Prize Pool: {green}115{default} credits.",
  "Survive by getting kills quickly. Friendly fire is on. Each kill gives you a HP boost! Prize Pool: {green}150{default} credits."
}

//Definitions
#define DMG_HEADSHOT (1 << 30)
#define LIFEDRAIN_SOUND_1 "invex_gaming/surf/male_death_1.mp3"
#define LIFEDRAIN_SOUND_2 "invex_gaming/surf/witch_death_scream_1.mp3"
#define LIFEDRAIN_SOUND_3 "invex_gaming/surf/witch_death_scream_2.mp3"
#define LIFEDRAIN_SOUND_4 "invex_gaming/surf/zombie_in_pain.mp3"
#define LIFEDRAIN_SOUND_5 "invex_gaming/surf/zombie_slow_death_1.mp3"

//Booleans
new bool:isEnabled;
new bool:stopEvent; //stops timer based events
new bool:returnWeapons; //if true, weapons from weapon store are returned on round start
new bool:isSpawnTime; //if true, late spawned players are given event weapons, isSpawnTime is true between Round_Start and Round_End only
new bool:isRoundDraw;

//Ints
new currentRound;
new currentRoundNoDraw;
new lastEventRound;
new EVENTS:eventDay = EVENT_NOEVENT; //default no event
new EVENTS:eventDayNext = EVENT_NOEVENT;

//Handles
new Handle:g_eventmod_enabled = INVALID_HANDLE;
new Handle:g_eventmod_VoteMenu = INVALID_HANDLE;
new Handle:g_eventmod_vote_duration = INVALID_HANDLE;
new Handle:g_eventmod_round_offset = INVALID_HANDLE;
new Handle:g_eventmod_he_health = INVALID_HANDLE;
new Handle:g_eventmod_he_armour = INVALID_HANDLE;
new Handle:g_eventmod_lifedrain_maxhp = INVALID_HANDLE;
new Handle:g_eventmod_lifedrain_min_drain = INVALID_HANDLE;
new Handle:g_eventmod_lifedrain_max_drain = INVALID_HANDLE;
new Handle:g_eventmod_lifedrain_drain_interval = INVALID_HANDLE;
new Handle:g_eventmod_lifedrain_kill_hp_boost = INVALID_HANDLE;

new Handle:g_RedieState = INVALID_HANDLE;
new Handle:timerHandle = INVALID_HANDLE;

new g_ExplosionSprite;

//Information Storage
new String:weaponStore[MAXPLAYERS+1][384];

/*
* Plugin Start
*/
public OnPluginStart()
{
  //Load translation
  LoadTranslations("event_mod.phrases");

  //Console Comands
  RegConsoleCmd("sm_voteevent", Command_Vote_Event, "Trigger an event round vote.");
  RegConsoleCmd("sm_eventvote", Command_Vote_Event, "Trigger an event round vote.");
  RegAdminCmd("sm_setevent", Command_Set_Event, ADMFLAG_KICK, "Sets an event round");
  RegConsoleCmd("sm_nextevent", Command_Next_Event, "Print out the next event round name.");
  
  //ConVar List
  g_eventmod_enabled = CreateConVar("sm_eventmod_enabled", "1", "Enable Event Mod (0 off, 1 on, def. 1)");
  g_eventmod_vote_duration = CreateConVar("sm_eventmod_vote_duration", "25", "Vote duration (def. 25)");
  g_eventmod_round_offset = CreateConVar("sm_eventmod_round_offset", "2", "Number of rounds until another event round can occur (def. 2)");
  g_eventmod_he_health = CreateConVar("sm_eventmod_he_health", "65", "Health of each player during HE only rounds (def. 65)");
  g_eventmod_he_armour = CreateConVar("sm_eventmod_he_armour", "0", "Armour of each player during HE only rounds (def. 0)");
  g_eventmod_lifedrain_maxhp = CreateConVar("sm_eventmod_lifedrain_maxhp", "250", "Amount of HP players start with on lifedrain rounds (def. 250)");
  g_eventmod_lifedrain_min_drain = CreateConVar("sm_eventmod_lifedrain_min_drain", "1", "Minimum amount of HP that can be taken away during a drain (def. 1)");
  g_eventmod_lifedrain_max_drain = CreateConVar("sm_eventmod_lifedrain_max_drain", "5", "Maximum amount of HP that can be taken away during a drain (def. 5)");
  g_eventmod_lifedrain_drain_interval = CreateConVar("sm_eventmod_lifedrain_drain_interval", "1.0", "Interval of time between every drain (def. 1.0)");
  g_eventmod_lifedrain_kill_hp_boost = CreateConVar("sm_eventmod_lifedrain_kill_hp_boost", "35", "Amount of HP that is awarded for killing another player (def. 35)");
  
  
  //Get redie state
  g_RedieState = CreateGlobalForward("redieIsGhost", ET_Single, Param_Cell);
  
  //EVENT Hooks
  HookEvent("round_start", Event_RoundStart);
  HookEvent("round_end", Event_RoundEnd);
  HookEvent("player_spawn", Event_PlayerSpawn);
  HookEvent("weapon_fire", Event_GrenadeThrow);
  HookEvent("player_death", Event_PlayerDeath);
  
  //Enable status hook
  HookConVarChange(g_eventmod_enabled, ConVarChange_enabled);
  
  //Set Variable Values
  isEnabled = true;
  
  //Create config file
  AutoExecConfig(true, "event_mod");
}

/*
* Some SDK Hooks for certain events
*/
public OnClientPutInServer(client)
{
    SDKHook(client, SDKHook_WeaponCanUse, BlockPickup);
    SDKHook(client, SDKHook_PostThinkPost, Hook_PostThinkPost);
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage)
}

/*
* On Map Start
*/
public OnMapStart()
{
  //Initilise variables
  currentRound = 0;
  currentRoundNoDraw = 1; //will not be incremented in initial round (map load round)
  lastEventRound = -10; //Large negative offset is needed initially
  eventDay = EVENT_NOEVENT;
  eventDayNext = EVENT_NOEVENT;
  
  //Clear weapon store
  for (new i = 0; i <= MAXPLAYERS; ++i) {
    weaponStore[i] = "";
  }
  
  //Precache sounds
  AddFileToDownloadsTable("sound/invex_gaming/surf/male_death_1.mp3");
  PrecacheSoundAny(LIFEDRAIN_SOUND_1);
  AddFileToDownloadsTable("sound/invex_gaming/surf/witch_death_scream_1.mp3");
  PrecacheSoundAny(LIFEDRAIN_SOUND_2);
  AddFileToDownloadsTable("sound/invex_gaming/surf/witch_death_scream_2.mp3");
  PrecacheSoundAny(LIFEDRAIN_SOUND_3);
  AddFileToDownloadsTable("sound/invex_gaming/surf/zombie_in_pain.mp3");
  PrecacheSoundAny(LIFEDRAIN_SOUND_4);
  AddFileToDownloadsTable("sound/invex_gaming/surf/zombie_slow_death_1.mp3");
  PrecacheSoundAny(LIFEDRAIN_SOUND_5);
  
  //Precache materials
  g_ExplosionSprite = PrecacheModel("sprites/sprite_flames.vmt");
  
  //Set bools
  stopEvent = false;
  returnWeapons = false;
  isRoundDraw = false;
  isSpawnTime = true;
}

/*
* If enable convar is changed, use this to turn the plugin off or on
*/
public ConVarChange_enabled(Handle:convar, const String:oldValue[], const String:newValue[])
{
  isEnabled = bool:StringToInt(newValue) ;
}


/*
* Print out the name of the current or next event
*/
public Action:Command_Next_Event(client, args) 
{
  if (!isEnabled) 
    return Plugin_Handled;
  
  new EVENTS:nextEvent = eventDay;
  
  //If eventday is not set but next event day is, show that event day
  if (eventDay == EVENT_NOEVENT && eventDayNext != EVENT_NOEVENT) {
   nextEvent = eventDayNext;
  }
  
  //If no event, show pending vote
  if (nextEvent == EVENT_NOEVENT)
    CPrintToChat(client, "%s%t", PREFIX, "Event Pending Vote");
  //If event round is selected
  else if (currentRound == lastEventRound - 1)
    CPrintToChat(client, "%s%t", PREFIX, "Alert Next Event Round", eventList[nextEvent], eventDesc[nextEvent]);
  //Current round is event round
  else if (currentRound == lastEventRound)
    CPrintToChat(client, "%s%t", PREFIX, "Alert Event Round", eventList[nextEvent], eventDesc[nextEvent]);
  //Otherwise
  else
    CPrintToChat(client, "%s%t", PREFIX, "Event Pending Vote");

  return Plugin_Handled;  
}


/*
* Allows admins to forcefully set an event round
*/
public Action:Command_Set_Event(client, args)
{
  if (!isEnabled) 
    return Plugin_Handled;

  if (client == 0) {	// Prevent command usage from server input and via RCON
    PrintToConsole(client, "Can't use this command from server input.");
    return Plugin_Handled;
  }
  
  //Create menu
  new Handle:setEventMenu = CreateMenu(SetEventMenuHandler);
  SetMenuTitle(setEventMenu, "Set an Event for the Next Round");
  
  //Add all events to menu
  for (new i = 0; i < sizeof(eventList); ++i) {
    new String:option[10] = "Option";
    new String:number[3];
    IntToString(i, number, sizeof(number));
    StrCat(option, sizeof(option), number);
    AddMenuItem(setEventMenu, option, eventList[i]);
  }
  
  DisplayMenu(setEventMenu, client, GetConVarInt(g_eventmod_vote_duration));
    
  return Plugin_Handled;
}

/*
* Set Event Menu Handler
*/
public SetEventMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select)
	{
    new winner = param2;

    //Set eventDayNext if we are already in an event round or next event has already been set
    if (currentRound == lastEventRound || eventDayNext != EVENT_NOEVENT) {
      //Set eventDayNext to winner
      eventDayNext = EVENTS:winner;
    }
    //Check how to deal with Event being set
    else if (currentRound == lastEventRound - 1) {
      //Set event round forcefully
      
      //Set eventDay to winner
      eventDay = EVENTS:winner;
      
      //Set last event round
      lastEventRound = currentRound + 1;
    }
    else {
      //Set event round forcefully
      
      //Set eventDay to winner
      eventDay = EVENTS:winner;
      
      //Set last event round
      lastEventRound = currentRound + 1;
    }
    
    //Get client name who initiated the vote
    new String:name[MAX_NAME_LENGTH+1];
    GetClientName(param1, name, sizeof(name));
    
    //Print out set event message
    if (eventDayNext != EVENT_NOEVENT)
      CPrintToChatAll("%s%t", PREFIX, "Set Event Round", name, eventList[eventDayNext]);
    else
      CPrintToChatAll("%s%t", PREFIX, "Set Event Round", name, eventList[eventDay]);
	}
	// If the menu has ended, destroy it 
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

/*
* If user has correct flag, they are able to trigger an event vote.
*/
public Action:Command_Vote_Event(client, args) 
{
  if (!isEnabled) 
    return Plugin_Handled;

  if (client == 0) {	// Prevent command usage from server input and via RCON
    PrintToConsole(client, "Can't use this command from server input.");
    return Plugin_Handled;
  }
  
  //Check that VIP player is correctly accessing command
  new isVIP = CheckCommandAccess(client, "", ADMFLAG_CUSTOM3);
  
  if (!isVIP) {
    CPrintToChat(client, "%s%t", PREFIX, "Must be VIP");
    return Plugin_Handled;
  }
  
  //Check if vote is already in progress
  if (IsVoteInProgress(g_eventmod_VoteMenu)) {
    CPrintToChat(client, "%s%t", PREFIX, "Event Vote In Progress");
    return Plugin_Handled;
  }
  
  //Check if vote can be triggered in this round
  if (currentRound <= lastEventRound + (GetConVarInt(g_eventmod_round_offset) - 1) ) {
    
    //Show message if event day was already selected ot its too early to vote for an event day
    if (currentRound == lastEventRound - 1)
      CPrintToChat(client, "%s%t", PREFIX, "Event Day Already Selected");
    else if (currentRound == lastEventRound)
      CPrintToChat(client, "%s%t", PREFIX, "Event Day Already Occuring");
    else
      CPrintToChat(client, "%s%t", PREFIX, "Cannot Vote For Event");
      
    return Plugin_Handled;
  }
  
  //Check if this is last round
  new Handle:maxRounds = FindConVar("mp_maxrounds");
  
  //Check currentRoundNoDraw as we dont want to consider draw rounds
  if (currentRoundNoDraw == GetConVarInt(maxRounds)) {
    CPrintToChat(client, "%s%t", PREFIX, "Cannot Vote Last Round");
    return Plugin_Handled;
  }

  //Get client name who initiated the vote
  new String:name[MAX_NAME_LENGTH+1];
  GetClientName(client, name, sizeof(name));
  
  LogAction(client, -1, "\"%L\" initiated a event vote.", client);
  CPrintToChatAll("%s%t", PREFIX, "Initiated Event Vote", name);
  
  g_eventmod_VoteMenu = CreateMenu(Handle_VoteMenu);
  SetVoteResultCallback(g_eventmod_VoteMenu, Handler_VoteEventCallback);
  
  //Add menu items
  SetMenuTitle(g_eventmod_VoteMenu, "Vote for an Event for the Next Round");
  
  //Add all events to menu
  for (new i = 0; i < sizeof(eventList); ++i) {
    new String:option[10] = "Option";
    new String:number[3];
    IntToString(i, number, sizeof(number));
    StrCat(option, sizeof(option), number);
    
    AddMenuItem(g_eventmod_VoteMenu, option, eventList[i]);
  }
  
  //Dont allow exit option
  SetMenuExitButton(g_eventmod_VoteMenu, false);
  VoteMenuToAll(g_eventmod_VoteMenu, GetConVarInt(g_eventmod_vote_duration)); //Set vote duration

  return Plugin_Handled;
}

public Handle_VoteMenu(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End) {
		/* This is called after VoteEnd */
		CloseHandle(menu);
	}
}

/*
* Vote handler
*/
public Handler_VoteEventCallback(Handle:menu, num_votes, num_clients, const client_info[][2], num_items, const item_info[][2])
{
  // Determine winner of votes
  new winner = 0;
  new percentage = 0;

  for (new i = 0; i < num_items; ++i) {
    if (item_info[i][VOTEINFO_ITEM_VOTES] >= percentage) {
      winner = item_info[i][VOTEINFO_ITEM_INDEX];
      percentage = item_info[i][VOTEINFO_ITEM_VOTES];
    }
  }
  
  //Calculate final percentage for winning option
  new Float:percentageFloat = float(percentage)/ float(num_votes) * 100;
  
  //Set last event round
  lastEventRound = currentRound + 1;
  
  //Set eventDay to winner
  eventDay = EVENTS:winner;
  
  CPrintToChatAll("%s%t", PREFIX, "Winning Event Vote", eventList[eventDay], RoundToFloor(percentageFloat));
}


/************************************* EVENT HOOKS ****************************************/

/*
* Event Round Start
*/

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
  if (!isEnabled) 
    return;
    
  //Increment Current Round if last round wasn't a draw
  if (isRoundDraw) {
    isRoundDraw = false;
  }
  else {
    ++currentRoundNoDraw;
  }

  ++currentRound; //inc current round either way
  
  //Special Case: Return weapons
  if (returnWeapons)
  {
    //For each client
    new iMaxClients = GetMaxClients();
 
    for (new i = 1; i <= iMaxClients; ++i)
    {
      //Check if player is truly alive
      if (IsAlive(i))
      {         
        //Give weapons back to player (from weapon storage)
        new String:part[384];
        Format(part, sizeof(part), "%s", weaponStore[i]);
        
        //If this player has no set weapon flag, they didnt play in knife round
        if (strcmp(part, "") == 0)
          continue;
        
         //Remove all weapons, without adding to weapon storage
        removeAllWeapons(i, false);
        
        new String:weaponBuffer[12][32];
        ExplodeString(part, ";", weaponBuffer, 12, 32);
        
        //Give the player all the items that they should have
        for (new count = 0; count < 12; ++count) {
          GivePlayerItem(i, weaponBuffer[count]);
        }
    
        weaponStore[i] = ""; //reset weapon storage string
        
        //Display returned item message
        CPrintToChat(i, "%s%t", PREFIX, "Items Returned");
      }
      //Reset weapon store for dead players too
      else {
        weaponStore[i] = ""; //reset weapon storage string
      }
    }

    returnWeapons = false; //reset returnWeapons bool
  }
  
  //Enable isSpawnTime
  isSpawnTime = true;
  
  //Check if eventDayNext is set
  if (eventDayNext != EVENT_NOEVENT) {
    eventDay = eventDayNext;
    eventDayNext = EVENT_NOEVENT;
    
    //Set correct last event round
    lastEventRound = currentRound;
  }
  
  //Return if no event
  if (eventDay == EVENT_NOEVENT)
    return;
  
  //Print out event round
  CPrintToChatAll("%s%t", PREFIX, "Alert Event Round", eventList[eventDay], eventDesc[eventDay]);
  
  //Hsay event round
  CreateTimer(2.0, Timer_ShowHint, eventDay);
  
  //Check if event is set
  switch (eventDay)
  {
    case EVENT_FREEFORALL:
    {
      //Set friendly fire CVARS to on for free for all round
      new Handle:friendlyfire = FindConVar("mp_friendlyfire");
      new Handle:teammatesAsEnemies = FindConVar("mp_teammates_are_enemies");
      
      //Enable CVARS
      SetConVarBool(friendlyfire, true);
      SetConVarBool(teammatesAsEnemies, true);
    }
    case EVENT_SLAP:
    {
      //Set stop event
      stopEvent = false;
          
      //Create required Timers
      timerHandle = CreateTimer(0.175, Timer_SlapRound, _, TIMER_REPEAT);
      CreateTimer(30.0, Timer_StopEvent);
    }
    case EVENT_DRUG:
    {
      //Toggle Drug on all players
      ServerCommand("sm_drug @all");
      
      //Create required Timers (to turn off drug event)
      timerHandle = CreateTimer(30.0, Timer_StopDrugEvent);
    }
    case EVENT_KNIFEONLY:
    {
      giveAllPlayerOnlyWeapon("weapon_knife", "");
    }
    case EVENT_DEAGLEONLY:
    {
      giveAllPlayerOnlyWeapon("weapon_knife", "weapon_deagle");
    }
    case EVENT_TEC9ONLY:
    {
      giveAllPlayerOnlyWeapon("weapon_knife", "weapon_tec9");
    }
    case EVENT_NEGEVONLY:
    {
      giveAllPlayerOnlyWeapon("weapon_knife", "weapon_negev");
    }
    case EVENT_SSGONLY:
    {
      giveAllPlayerOnlyWeapon("weapon_knife", "weapon_ssg08");
    }
    case EVENT_AWPONLY:
    {
      giveAllPlayerOnlyWeapon("weapon_knife", "weapon_awp");
    }
    case EVENT_DAKDAKONLY:
    {
      giveAllPlayerOnlyWeapon("weapon_knife", "weapon_g3sg1");
    }
    case EVENT_ZEUSONLY:
    {
      giveAllPlayerOnlyWeapon("weapon_taser", "");
      
      //Enable infinite ammo cvar
      new Handle:infiniteAmmo = FindConVar("sv_infinite_ammo");
      
      //Enable CVARS
      SetConVarInt(infiniteAmmo, 1);
      
      //Disable !knife cvar
      new Handle:knifeOn = FindConVar("sm_knifeupgrade_on");
      SetConVarBool(knifeOn, false);
      
    }
    case EVENT_HEONLY:
    {
      giveAllPlayerOnlyWeapon("weapon_hegrenade", "");
      
      new iMaxClients = GetMaxClients();
      
      //For all clients
      for (new i = 1; i <= iMaxClients; ++i)
      {
        //Check if player is truly alive
        if (IsAlive(i))
        {
          //Set HP
          SetEntityHealth(i, GetConVarInt(g_eventmod_he_health));
          
          //Set Armor to 0
          SetEntProp(i, Prop_Send, "m_ArmorValue", GetConVarInt(g_eventmod_he_armour), 1 );  
        }
      }
      
      //Disable !knife cvar
      new Handle:knifeOn = FindConVar("sm_knifeupgrade_on");
      SetConVarBool(knifeOn, false);
    }
    case EVENT_1HPDECOY:
    {
      giveAllPlayerOnlyWeapon("weapon_decoy", "");
      
      new iMaxClients = GetMaxClients();
      
      //For all clients
      for (new i = 1; i <= iMaxClients; ++i)
      {
        //Check if player is truly alive
        if (IsAlive(i))
        {
          //Set HP
          SetEntityHealth(i, 1);
          
          //Set Armor to 0
          SetEntProp(i, Prop_Send, "m_ArmorValue", 0, 1 );
        }
      }
      
      //Create required Timers
      //Ensure that health relics are nullified by constantly setting hp to 1
      timerHandle = CreateTimer(1.0, Timer_SetHP, 1, TIMER_REPEAT);
      
      //Disable !knife cvar
      new Handle:knifeOn = FindConVar("sm_knifeupgrade_on");
      SetConVarBool(knifeOn, false);
    }
    case EVENT_PISTOLHSONLY:
    {
      new iMaxClients = GetMaxClients();
      
      //Pistol weapon array
      new String:pistols[9][] = {"weapon_p250",
                           "weapon_deagle",
                           "weapon_elite",
                           "weapon_fiveseven",
                           "weapon_glock",
                           "weapon_usp_silencer",
                           "weapon_tec9",
                           "weapon_cz75a",
                           "weapon_hkp2000"
                          };
      
      //Set armor to 100
      for (new i = 1; i <= iMaxClients; ++i)
      {
        //Check if player is truly alive
        if (IsAlive(i))
        {
          //Remove all weapons, adding to weapon storage
          removeAllWeapons(i, true);

          //Give player a random pistol
          new randInt = GetRandomInt(0, 8);
         
          givePlayerOnlyWeapon(i, pistols[randInt], "");
          
          //Set Armor to 100
          SetEntProp(i, Prop_Send, "m_ArmorValue", 100, 1 );
        }
      }
      
      //Set return weapon boolean (so all players weapons can be returned later on)
      returnWeapons = true;
    }
    case EVENT_LIFEDRAIN:
    {
    
      //Set friendly fire CVARS to on for free for all round
      new Handle:friendlyfire = FindConVar("mp_friendlyfire");
      new Handle:teammatesAsEnemies = FindConVar("mp_teammates_are_enemies");
      
      //Enable CVARS
      SetConVarBool(friendlyfire, true);
      SetConVarBool(teammatesAsEnemies, true);
    
      new iMaxClients = GetMaxClients();
      
      //For all clients
      for (new i = 1; i <= iMaxClients; ++i)
      {
        //Check if player is truly alive
        if (IsAlive(i))
        {
          //Set HP for all
          SetEntityHealth(i, GetConVarInt(g_eventmod_lifedrain_maxhp));
          
          //Set Armor to 0
          SetEntProp(i, Prop_Send, "m_ArmorValue", 0, 1 );
        }
      }
      
      //Set timer to drain players HP
      timerHandle = CreateTimer(GetConVarFloat(g_eventmod_lifedrain_drain_interval), Timer_DrainHP, _, TIMER_REPEAT);
    }
  } 
  
}

/*
* Event Round End
*/

public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
  if (!isEnabled) 
    return;
  
  //If Round Draw, decrement current round (as to repeat the round)
  new roundWinner = GetEventInt(event, "winner");
    
  //Check if round was a draw
  if (roundWinner != 2 && roundWinner != 3) {
    isRoundDraw = true;
  }
  
  //Disable isSpawnTime
  isSpawnTime = false;
    
  //Return if no event
  if (eventDay == EVENT_NOEVENT)
    return;
    
  //Return if not end of event round as to not undo an event which has not occured
  if (currentRound == lastEventRound - 1)
    return;
  
  //Set prize pool
  new prizePool = 0;
  
  //Check if event is set and undo changes
  switch (eventDay)
  {
    case EVENT_FREEFORALL:
    {
      //Find friendly fire CVARS
      new Handle:friendlyfire = FindConVar("mp_friendlyfire");
      new Handle:teammatesAsEnemies = FindConVar("mp_teammates_are_enemies");
      
      //Disable CVARS
      SetConVarBool(friendlyfire, false);
      SetConVarBool(teammatesAsEnemies, false);
      
      prizePool = 100;
    }
    case EVENT_SLAP:
    {
      //Kill timer
      KillTimer(timerHandle);
    }
    case EVENT_DRUG:
    {
      //Kill timer
      KillTimer(timerHandle);
      ServerCommand("sm_drug @all"); //Toggle Drug on all players
    }
    case EVENT_KNIFEONLY:
    {
      //Set prize pool
      prizePool = 75;
    }
    case EVENT_DEAGLEONLY:
    {
      //Set prize pool
      prizePool = 75;    
    }
    case EVENT_TEC9ONLY:
    {
      //Set prize pool
      prizePool = 75;
    }
    case EVENT_NEGEVONLY:
    {
      //Set prize pool
      prizePool = 75;        
    }
    case EVENT_SSGONLY:
    {
      //Set prize pool
      prizePool = 75;    
    }
    case EVENT_AWPONLY:
    {
      //Set prize pool
      prizePool = 85;
    }
    case EVENT_DAKDAKONLY:
    {
      //Set prize pool
      prizePool = 50; 
    }
    case EVENT_ZEUSONLY:
    {
      //Disable infinite ammo cvar
      new Handle:infiniteAmmo = FindConVar("sv_infinite_ammo");
      
      //Disable CVAR
      SetConVarInt(infiniteAmmo, 0);
    
      //Enable !knife cvar
      new Handle:knifeOn = FindConVar("sm_knifeupgrade_on");
      SetConVarBool(knifeOn, true);
    
      //Set prize pool
      prizePool = 115;
    }
    case EVENT_HEONLY:
    {
      //Enable !knife cvar
      new Handle:knifeOn = FindConVar("sm_knifeupgrade_on");
      SetConVarBool(knifeOn, true);
    
      //Set prize pool
      prizePool = 85;
    }
    case EVENT_1HPDECOY:
    {
      //Enable !knife cvar
      new Handle:knifeOn = FindConVar("sm_knifeupgrade_on");
      SetConVarBool(knifeOn, true);
    
      //Kill timer
      KillTimer(timerHandle);
    
      //Set prize pool
      prizePool = 115;
    }
    case EVENT_HSONLY:
    {
      //Set prize pool
      prizePool = 85;
    }
    case EVENT_PISTOLHSONLY:
    {
      //Set prize pool
      prizePool = 115;
    }
    case EVENT_LIFEDRAIN:
    {
      //Find friendly fire CVARS
      new Handle:friendlyfire = FindConVar("mp_friendlyfire");
      new Handle:teammatesAsEnemies = FindConVar("mp_teammates_are_enemies");
      
      //Disable CVARS
      SetConVarBool(friendlyfire, false);
      SetConVarBool(teammatesAsEnemies, false);
    
      //Kill timer
      KillTimer(timerHandle);
      
      //Set prize pool
      prizePool = 150;
    }
  }
  
  //If a prizepool is set, distribute rewards
  if (prizePool != 0)
  {  
    new iMaxClients = GetMaxClients();
    new winnerList[iMaxClients];
    new numWinners = 0;
    
    //Get Winners
    for (new i = 1; i <= iMaxClients; ++i)
    {
      //Check if player is truly alive
      if (IsAlive(i))
      {
        winnerList[numWinners] = i;
        ++numWinners;
      }
    }
    
    //Calculate how much each winner gets
    new prizePoolProportion =  RoundToFloor(float(prizePool)/ float(numWinners));
    
    //Award prize to winners
    for (new j = 0; j < numWinners; ++j)
    {
      new winner = winnerList[j];
      
      //Award Winner their Money
      Store_GiveCredits(GetSteamAccountID(winner), prizePoolProportion);
      CPrintToChat(winner, "%s%t", PREFIX, "Player Won Prize", prizePoolProportion);
    }
  }
  
  //Print message that event round is over
  CPrintToChatAll("%s%t", PREFIX, "Alert Event Stopped", eventList[eventDay]);

  //Reset event day
  eventDay = EVENT_NOEVENT;
}


/*
* Player Spawn - Give late spawners event only weapons and apply neccesary restrictions
*/
public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
  if (!isEnabled) 
    return Plugin_Continue;
   
  //Check if this is a late spawn, otherwise ignore spawn
  if (!isSpawnTime)
    return Plugin_Continue;
    
  //Return if not event round
  if (currentRound != lastEventRound)
    return Plugin_Continue;
  
  new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
  //Check if event is set
  switch (eventDay)
  {
    case EVENT_KNIFEONLY:
    {
      givePlayerOnlyWeapon(client, "weapon_knife", "");
    }
    case EVENT_DEAGLEONLY:
    {
      givePlayerOnlyWeapon(client, "weapon_knife", "weapon_deagle");
    }
    case EVENT_TEC9ONLY:
    {
      givePlayerOnlyWeapon(client, "weapon_knife", "weapon_tec9");
    }
    case EVENT_NEGEVONLY:
    {
      givePlayerOnlyWeapon(client, "weapon_knife", "weapon_negev");
    }
    case EVENT_SSGONLY:
    {
      givePlayerOnlyWeapon(client, "weapon_knife", "weapon_ssg08");
    }
    case EVENT_AWPONLY:
    {
      givePlayerOnlyWeapon(client, "weapon_knife", "weapon_awp");
    }
    case EVENT_DAKDAKONLY:
    {
      givePlayerOnlyWeapon(client, "weapon_knife", "weapon_g3sg1");    
    }
    case EVENT_ZEUSONLY:
    {
      givePlayerOnlyWeapon(client, "weapon_taser", "");
    }
    case EVENT_HEONLY:
    {
      givePlayerOnlyWeapon(client, "weapon_hegrenade", "");

      //Check if player is truly alive
      if (IsAlive(client))
      {
        //Set HP
        SetEntityHealth(client, GetConVarInt(g_eventmod_he_health));
        
        //Set Armor to 0
        SetEntProp( client, Prop_Send, "m_ArmorValue", GetConVarInt(g_eventmod_he_armour), 1 );  
      }
    }
    case EVENT_1HPDECOY:
    {
      givePlayerOnlyWeapon(client, "weapon_decoy", "");

      //Check if player is truly alive
      if (IsAlive(client))
      {
        //Set HP
        SetEntityHealth(client, 1);
        
        //Set Armor to 0
        SetEntProp(client, Prop_Send, "m_ArmorValue", 0, 1 );  
      }
    }
    case EVENT_PISTOLHSONLY:
    {
      //Pistol weapon array
      new String:pistols[9][] = {"weapon_p250",
                           "weapon_deagle",
                           "weapon_elite",
                           "weapon_fiveseven",
                           "weapon_glock",
                           "weapon_usp_silencer",
                           "weapon_tec9",
                           "weapon_cz75a",
                           "weapon_hkp2000"
                          };
      //Check if player is truly alive
      if (IsAlive(client))
      {
        //Give player a random pistol
        new randInt = GetRandomInt(0, 8);
       
        givePlayerOnlyWeapon(client, pistols[randInt], "");
        
        //Set Armor to 100
        SetEntProp(client, Prop_Send, "m_ArmorValue", 100, 1 );
      }
    }
    case EVENT_LIFEDRAIN:
    {
      //Check if player is truly alive
      if (IsAlive(client))
      {
        //Set HP
        SetEntityHealth(client, GetConVarInt(g_eventmod_lifedrain_maxhp));
        
        //Set Armor to 0
        SetEntProp(client, Prop_Send, "m_ArmorValue", 0, 1 );
      }
    }
  }

  return Plugin_Continue;
}

/*
* Simulate out of buyzone error
*/
public Hook_PostThinkPost(client) 
{ 
  if (!isEnabled) 
    return;
  
  //Return if not knife only event
  if (eventDay != EVENT_KNIFEONLY && eventDay != EVENT_DEAGLEONLY && eventDay != EVENT_TEC9ONLY && eventDay != EVENT_NEGEVONLY && eventDay != EVENT_SSGONLY && eventDay != EVENT_AWPONLY && eventDay != EVENT_DAKDAKONLY && eventDay != EVENT_ZEUSONLY && eventDay != EVENT_HEONLY && eventDay != EVENT_1HPDECOY && eventDay != EVENT_PISTOLHSONLY)
    return;
    
  //Return if not an active event day
  if (currentRound != lastEventRound)
    return;
    
  SetEntProp(client, Prop_Send, "m_bInBuyZone", 0);
} 

/*
* Block the picking up of weapons in certain event rounds
*/
public Action:BlockPickup(client, weapon)
{
  if (!isEnabled) 
    return Plugin_Continue;
  
  //Return if not knife only event
  if (eventDay != EVENT_KNIFEONLY && eventDay != EVENT_DEAGLEONLY && eventDay != EVENT_TEC9ONLY && eventDay != EVENT_NEGEVONLY && eventDay != EVENT_SSGONLY && eventDay != EVENT_AWPONLY && eventDay != EVENT_DAKDAKONLY && eventDay != EVENT_ZEUSONLY && eventDay != EVENT_HEONLY && eventDay != EVENT_1HPDECOY && eventDay != EVENT_PISTOLHSONLY)
    return Plugin_Continue;
    
  //Return if not an active event day
  if (currentRound != lastEventRound)
    return Plugin_Continue;

  
  new String:weaponClass[64];
  GetEntityClassname(weapon, weaponClass, sizeof(weaponClass));
  
  //Switch each event day
  switch (eventDay)
  {
    case EVENT_KNIFEONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_DEAGLEONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife") || StrEqual(weaponClass, "weapon_deagle"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_TEC9ONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife") || StrEqual(weaponClass, "weapon_tec9"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_NEGEVONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife") || StrEqual(weaponClass, "weapon_negev"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_SSGONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife") || StrEqual(weaponClass, "weapon_ssg08"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_AWPONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife") || StrEqual(weaponClass, "weapon_awp"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_DAKDAKONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife") || StrEqual(weaponClass, "weapon_g3sg1"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_ZEUSONLY:
    {
      if (StrEqual(weaponClass, "weapon_taser"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_HEONLY:
    {
      if (StrEqual(weaponClass, "weapon_hegrenade"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_1HPDECOY:
    {
      if (StrEqual(weaponClass, "weapon_decoy"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_PISTOLHSONLY:
    {
      if (StrEqual(weaponClass, "weapon_p250") || StrEqual(weaponClass, "weapon_deagle") || StrEqual(weaponClass, "weapon_elite") || StrEqual(weaponClass, "weapon_fiveseven") || StrEqual(weaponClass, "weapon_glock") || StrEqual(weaponClass, "weapon_usp_silencer") || StrEqual(weaponClass, "weapon_tec9") || StrEqual(weaponClass, "weapon_cz75a") || StrEqual(weaponClass, "weapon_hkp2000"))
      {
          return Plugin_Continue;
      }
    }
  }

  return Plugin_Handled;
}

/*
* Check if player is truely alive, not a bot and not in redie mode
*/
public bool:IsAlive(client)
{
  decl bool:isGhost;

  Call_StartForward(g_RedieState);
  Call_PushCell(client);
  Call_Finish(_:isGhost);

  //Ensure player is alive and is not a redie ghost
  if (IsClientInGame(client) && IsPlayerAlive(client) && (!IsFakeClient(client)) && !isGhost)
    return true;

  return false;
}

/*
* Stop an event by setting stop event bool
*/
public Action:Timer_StopEvent(Handle:timer)
{
	stopEvent = true;
}

/*
* Show the hint text for the current event round
*/
public Action:Timer_ShowHint(Handle:timer, any:eventID)
{
  PrintHintTextToAll("This round is an event round!\nEvent: %s", eventList[eventID]);
}

/*
* Stop drug event
*/
public Action:Timer_StopDrugEvent(Handle:timer)
{
  //Toggle Drug on all players
  ServerCommand("sm_drug @all");
  
  //Print end message
  CPrintToChatAll("%s%t", PREFIX, "Alert Event Stopped", eventList[eventDay]);
  
  eventDay = EVENT_NOEVENT; //reset event day
  
  //Check if eventDayNext is set
  if (eventDayNext != EVENT_NOEVENT) {
    //Set correct last event round
    lastEventRound = currentRound + 1;
  }
}


/*
* Slap timer, slaps users in game
*/
public Action:Timer_SlapRound(Handle:timer)
{
  //If stop event is triggered, stop slap day
  if (stopEvent) {
    CPrintToChatAll("%s%t", PREFIX, "Alert Event Stopped", eventList[eventDay]);
    eventDay = EVENT_NOEVENT; //reset event day
    
    //Check if eventDayNext is set
    if (eventDayNext != EVENT_NOEVENT) {
      //Set correct last event round
      lastEventRound = currentRound + 1;
    }
    
    return Plugin_Stop;
  }
  
  //Slap all users in game
  ServerCommand("sm_slap @all");
  
  return Plugin_Continue;
}

/*
* Remove all weapons a player has
*/
removeAllWeapons(client, bool:addToWeaponStore)
{
  new EntityIndex = 0;
  new Slot = 0;
  new iMyWeapons = FindSendPropOffs("CBaseCombatCharacter", "m_hMyWeapons");

  for (Slot = 0; Slot <= (32 * 4); Slot += 4)
  {
    EntityIndex = GetEntDataEnt2(client, (iMyWeapons + Slot));
    if (EntityIndex != 0 && IsValidEdict(EntityIndex))
    {
      //Add weapons to storage
      if (addToWeaponStore)
      {
        //Get weapon name
        new String:weaponName[32];
        GetEntityClassname(EntityIndex, weaponName, sizeof(weaponName));
        
        StrCat(weaponName, sizeof(weaponName), ";");
        
        //Get current weapon string for this client
        new String:tempWeaponString[384];
        Format(tempWeaponString, sizeof(tempWeaponString), "%s", weaponStore[client]);
        
        //Add this weapon to end of string
        StrCat(tempWeaponString, sizeof(tempWeaponString), weaponName);
        
        weaponStore[client] = tempWeaponString;
      }
      
      //Remove weapon
      RemovePlayerItem(client, EntityIndex);
      RemoveEdict(EntityIndex);
    }
  }
}

/*
* Give all players a specifc weapon and remove and saves all other weapons to weapon store
*/
giveAllPlayerOnlyWeapon(String:weapon[], String:weapon2[])
{
  //For each client
  new iMaxClients = GetMaxClients();

  for (new i = 1; i <= iMaxClients; ++i)
  {
    //Check if player is truly alive
    if (IsAlive(i))
    {    
      //Remove all weapons, adding to weapon storage
      removeAllWeapons(i, true);
      
      //Give player 2 weapons
      GivePlayerItem(i, weapon);
      GivePlayerItem(i, weapon2);
    }
  }
  
  //Set return weapon boolean (so all players weapons can be returned later on)
  returnWeapons = true;
  
}

/*
* Give player a specifc weapon and removes and saves all other weapons to weapon store
*/
givePlayerOnlyWeapon(any:client, String:weapon[], String:weapon2[])
{
  //Check if player is truly alive
  if (IsAlive(client))
  {
    //Remove all weapons, adding to weapon storage
    removeAllWeapons(client, true);
    
    //Give player 2 weapons
    GivePlayerItem(client, weapon);
    GivePlayerItem(client, weapon2);
  }
}

/*
* Give client a grenade after they throw it, used in some events
*/
public Action:Event_GrenadeThrow(Handle:event, const String:name[], bool:dontBroadcast)
{
  if (!isEnabled) 
    return Plugin_Continue;
  
  //Return if not event round
  if (currentRound != lastEventRound)
    return Plugin_Continue;
    
  //Return if event is not grenade event
  if (eventDay != EVENT_HEONLY && eventDay != EVENT_1HPDECOY)
    return Plugin_Continue;

  new String:weapon[32]; 
  GetEventString(event, "weapon", weapon, sizeof(weapon));

  if(StrEqual(weapon, "hegrenade", false) || StrEqual(weapon, "decoy", false)) 
  { 
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    CreateTimer(1.75, Timer_GiveGrenade, client);
    return Plugin_Handled;
  }
  
  return Plugin_Handled;
}


/*
* Timer - Give client a grenade based on event day
*/
public Action:Timer_GiveGrenade(Handle:timer, any:client)
{
  if (eventDay == EVENT_HEONLY)
    GivePlayerItem(client, "weapon_hegrenade");
  else if (eventDay == EVENT_1HPDECOY)
    GivePlayerItem(client, "weapon_decoy");
}

/*
* Timer - Set all clients HP to specific hp
*/
public Action:Timer_SetHP(Handle:timer, any:hp)
{
  //For each client
  new iMaxClients = GetMaxClients();

  for (new i = 1; i <= iMaxClients; ++i)
  {
    //Check if player is truly alive
    if (IsAlive(i))
    {
      new remainingHP = GetEntProp(i, Prop_Send, "m_iHealth");
      
      //If this user gained some HP
      if (remainingHP > 1) {
        //Set HP of client to hp
        SetEntityHealth(i, 1);
        
        //Set Armor to 0
        SetEntProp(i, Prop_Send, "m_ArmorValue", 0, 1 );
        
        //Display message to let use know you cant gain more HP
        CPrintToChat(i, "%s%t", PREFIX, "HP Fixed This Round", 1);
      }
    }
  } 
}

/*
* Timer - Continously remove HP from all clients
*/
public Action:Timer_DrainHP(Handle:timer)
{
  //For each client
  new iMaxClients = GetMaxClients();

  for (new i = 1; i <= iMaxClients; ++i)
  {
    //Check if player is truly alive
    if (IsAlive(i))
    {
      new currentHP = GetEntProp(i, Prop_Send, "m_iHealth");
      new drainAmount = GetRandomInt(GetConVarInt(g_eventmod_lifedrain_min_drain), GetConVarInt(g_eventmod_lifedrain_max_drain));
      
      //If player should die
      if (drainAmount > currentHP) {
        new Float:dead_player_vec[3];
        GetClientAbsOrigin(i, dead_player_vec);
        
        //Generate random num for random death sound
        new randNum = GetRandomInt(0, 4);
        new String:deathSounds[5][] = {LIFEDRAIN_SOUND_1,LIFEDRAIN_SOUND_2,LIFEDRAIN_SOUND_3,LIFEDRAIN_SOUND_4,LIFEDRAIN_SOUND_5};
        
        //Play explosion sounds
        EmitSoundToAllAny(deathSounds[randNum], i, SNDCHAN_USER_BASE, SNDLEVEL_NORMAL); //SNDLEVEL_NORMAL so only nearby players hear them
        TE_SetupExplosion(dead_player_vec, g_ExplosionSprite, 10.0, 1, 0, 250, 5000);
        TE_SendToAll();
        
        //Kill the player
        ForcePlayerSuicide(i);
      }
      //Othwerwise drain their HP
      else {
        SetEntityHealth(i, currentHP - drainAmount);
      }
    }
  } 
}

/*
* Called when a player takes damage
*/
public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3])
{
  if (!isEnabled) 
    return Plugin_Continue;
  
  //Return if not event round
  if (currentRound != lastEventRound)
    return Plugin_Continue;
    
  //Return if event is not grenade event
  if (eventDay != EVENT_HSONLY && eventDay != EVENT_PISTOLHSONLY)
    return Plugin_Continue;
    
  //Only apply damage if HS is landed
  if(victim > 0 && victim <= MaxClients && IsClientInGame(victim))
  {
    if(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
    {
      if(!(damagetype & DMG_HEADSHOT))
      {
        return Plugin_Handled;
      }
    }
  }

  return Plugin_Continue;
}

/*
* Called when players die
*/
public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
  if (!isEnabled) 
    return Plugin_Continue;
  
  //Return if not event round
  if (currentRound != lastEventRound)
    return Plugin_Continue;
    
  //Return if event is not lifedrain
  if (eventDay != EVENT_LIFEDRAIN)
    return Plugin_Continue;
    
  //Get event vars
  new client = GetClientOfUserId(GetEventInt(event, "userid"));
  new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
  
  //If attacker is not the client itself
  if (client != attacker) {
    new currentHP = GetEntProp(attacker, Prop_Send, "m_iHealth");
    SetEntityHealth(attacker, currentHP + GetConVarInt(g_eventmod_lifedrain_kill_hp_boost));
  }
  
  return Plugin_Continue;
}

/*
* Called whenever an entity is created, used to delete map generated entities (like weapons) that we don't want
*/
public OnEntityCreated(entity, const String:classname[])
{
  //Check if enabled
  if (!isEnabled) 
    return;
  
  //Return if not knife only event
  if (eventDay != EVENT_KNIFEONLY && eventDay != EVENT_DEAGLEONLY && eventDay != EVENT_TEC9ONLY && eventDay != EVENT_NEGEVONLY && eventDay != EVENT_SSGONLY && eventDay != EVENT_AWPONLY && eventDay != EVENT_DAKDAKONLY && eventDay != EVENT_ZEUSONLY && eventDay != EVENT_HEONLY && eventDay != EVENT_1HPDECOY && eventDay != EVENT_PISTOLHSONLY)
    return;
    
  //Return if not an active event day
  if (currentRound != lastEventRound)
    return;

  //Never safe to delete entities in here, use SDKHook to kill entity
  if(StrEqual(classname, "game_player_equip")) { 
      SDKHook(entity, SDKHook_Spawn, Hook_OnEntitySpawn); 
  }
}

/*
* Removes spawned entity when called
*/
public Action:Hook_OnEntitySpawn(entity) {
  //Get name of weapon stored in game_player_equip
  new String:weaponClass[64];
  GetEntPropString(entity, Prop_Data, "m_weaponNames", weaponClass, sizeof(weaponClass));
 
  //Check if we should delete this entity
  
  //Switch each event day
  switch (eventDay)
  {
    case EVENT_KNIFEONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_DEAGLEONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife") || StrEqual(weaponClass, "weapon_deagle"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_TEC9ONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife") || StrEqual(weaponClass, "weapon_tec9"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_NEGEVONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife") || StrEqual(weaponClass, "weapon_negev"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_SSGONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife") || StrEqual(weaponClass, "weapon_ssg08"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_AWPONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife") || StrEqual(weaponClass, "weapon_awp"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_DAKDAKONLY:
    {
      if (StrEqual(weaponClass, "weapon_knife") || StrEqual(weaponClass, "weapon_g3sg1"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_ZEUSONLY:
    {
      if (StrEqual(weaponClass, "weapon_taser"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_HEONLY:
    {
      if (StrEqual(weaponClass, "weapon_hegrenade"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_1HPDECOY:
    {
      if (StrEqual(weaponClass, "weapon_decoy"))
      {
          return Plugin_Continue;
      }
    }
    case EVENT_PISTOLHSONLY:
    {
      if (StrEqual(weaponClass, "weapon_p250") || StrEqual(weaponClass, "weapon_deagle") || StrEqual(weaponClass, "weapon_elite") || StrEqual(weaponClass, "weapon_fiveseven") || StrEqual(weaponClass, "weapon_glock") || StrEqual(weaponClass, "weapon_usp_silencer") || StrEqual(weaponClass, "weapon_tec9") || StrEqual(weaponClass, "weapon_cz75a") || StrEqual(weaponClass, "weapon_hkp2000"))
      {
          return Plugin_Continue;
      }
    }
  }
  
  //If we reached this point then this isn't an acceptable entity
  //Remove it
  AcceptEntityInput(entity, "Kill"); 
  return Plugin_Handled; 
}