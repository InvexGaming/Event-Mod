EventMod
=========================
Modifies players and their enviroments to create custom event days.

This plugin is best used on Counter-Strike:Global Offensive servers running the surf game mode.
It allows specific rounds to occur with restrictions and powerups.

This plugin was developed and tested on sourcemod version 1.6.4-dev+4625.

List of Events
----------
* Free For All Round
* Slap Round
* Drug Round
* Knife Only Round
* Deagle Only Round
* Tec9 Only Round
* Negev Only Round
* SSG08 Only Round
* AWP Only Round
* DAK DAK Only Round
* Zeus Only Round
* HE Only Round
* 1HP Decoy Only Round
* Headshot Only Round
* Random Pistol Headshot Only Round
* Lifedrain Only Round

Integration with other plugins
----------
This plugin disabled the !knife plugin on certain rounds.
This plugin also uses a global forward with the redie Plugin.
It required that a bool function called *redieIsGhost* exists that takes a client and returns true if client is a ghost (in redie) and false otherwise.

License
----
All rights reserved.
Contact me before using this plugin or parts of this plugin.
