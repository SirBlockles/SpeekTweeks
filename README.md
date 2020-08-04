# SpeekTweeks
SourceMod plugin for TF2 that makes the mercenaries and the announcer more talkative.

### Usage
This plugin was written with granular control in mind, and basically every function can be enabled and disabled separately. Only enable what you want! The value in [brackets] is the default value for the CVAR.

#### CVARs

`sm_speektweeks_enabled <0/[1]>` - Enable or disable the plugin as a whole

`sm_speektweeks_teamwipe <0/[1]>` - Makes the announcer call "team wipe, you've killed them all!" lines from Valve matchmaking. If a player is in spec, it will instead use "RED/BLU team has been wiped out!" lines.

`sm_speektweeks_teamwipe_arena <[0]/1>` - By default, team wipe lines are disabled in Arena mode since wiping the team is a win condition and nobody respawns. Set this to `1` to override this behavior.

`sm_speektweeks_teamwipe_min [8]` - Minimum amount of players required on the server to enable team wipe lines (prevents them in 1v1 or 2v2 scenarios)

`sm_speektweeks_roundstart_comp <0/[1]>` - Replaces (in most circumstances) the default battle cries at the start of a round with those from Valve Casual/Competitive mode. If a player spawns just between the round starting and their character speaking, they'll most likely still speak default battle cries.

`sm_speektweeks_roundstart_comp_6s <[0]/1>` - Stacks with above CVAR - when speaking competitive lines, this will also enable lines explicitly referencing 6v6 ("Just six guys, alone in the desert, tryin'ta kill each other... Happens all the time." -Scout)

`sm_speektweeks_roundstart_announcer <0/[1]>` - When Setup time ends, the announcer will yell "Get fighting already!," or any other of her lines when a Casual game initiates ("Move!" "Get going!" "Begin!").

`sm_speektweeks_roundend_announcer <0/[1]>` - When a round ends, the announcer will proclaim that the round belongs to RED or BLU to spectators (and SourceTV).

`sm_speektweeks_roundend_players <0/[1]>` - When a round ends, characters on the winning team will speak a round win line from casual/competitive.

`sm_speektweeks_classdead <0/[1]>` - When a player dies, their nearest teammate will call out that their teammate has died, like they do in MvM. This will only be spoken by the nearest teammate who has applicable lines (Solly/Heavy/Engy/Medic), and will still be triggered with feigned deaths from the Dead Ringer.

`sm_speektweeks_classdead_searchdist [10000]` - When a player dies, search for the nearest player within range of the victim who can speak a line. If nobody is found within this distance, nothing happens. Distance is in Hammer Units.

`sm_speektweeks_classdead_delay [10]` - Cooldown (in seconds) between a player being able to speak a "teammate is dead!" line, to avoid vocal spam.

#### Commands

`sm_addcontext <target> <context(s)>` - Adds vocal contexts to targets. If no player is specified, it will add it to the command user. Note that this command should be done in console, with each context in quotes, since the `:` character splits the arguments.

**Example:** `sm_addcontext @all "IsMvMDefender:1"` **Alias:** `sm_speektweeks_addcontext`

<br>
`sm_removecontext <target> <context(s)>` - Removes vocal contexts from targets. If no target is specified, it will remove it from the command user. Note that this command should be done in console, with each context in quotes, since the `:` character splits the arguments. Additionally, passing `all` or `clear` as a context will clear all contexts from target.

**Example:** `sm_removecontext @all "IsMvMDefender:1"` **Alias:** `sm_speektweeks_removecontext`

<br>
`sm_speakresponseconcept <target> <concept>` - Manually speak a response concept through target. If no target is provided, the concept will be spoke through the command user.

**Example:** `sm_speakresponseconcept @red TLK_PLAYER_BATTLECRY` **Alias:** `sm_speektweeks_speakresponseconcept`

#### Changelog

1.0 - Initial release

1.1 - Internal code cleanup, split `sm_speektweeks_roundend` into two CVARs: `sm_speektweeks_roundend_announcer`, which has announcer lines play for spectators, and `sm_speektweeks_roundend_players`, which has the winning player characters speak their round win lines.