# Meridius: the owner's sound picks

The owner's verdicts on the audition page (2026-10-24), what each chosen sound
does in the game now and what the saved ones are kept for. The ids are the
audio library's (`local/audio-library/candidates.json` at the repository
root, gitignored; listen on
`audition.html` there). The game's takes are rendered from these by
`source/godot/tools/audio/recipe.json` (`build_bank.py`); plan:
[plan-audio.md](plan-audio.md).

Rules followed: a liked take replaces the unrated ones of the same sound; a
rejected take leaves the game; a take saved for later is kept out of the game
until its feature exists. Sounds the owner has not reviewed yet keep the
earlier choices.

## Voices (Higgsfield)

| Take | Verdict | In the game | Edit |
| --- | --- | --- | --- |
| `03_commander_knox` | Liked: only the first "Shield wall!" | Shield Wall stance (`stance_shieldwall`): "Shield wall!" + shields locking 0.5 s later | Cut at 1.49 s (before "Hold the line…") |
| `09_orc_barrett_down5st` | Liked, without the final "KRAGH! KRAGH!" | The Orc Warlord's War Cry (`warcry_orc_warlord`): "RRAAAGH! Blood for the Warlord! CRUSH THEM!" | Cut at 5.1 s (before "KRAGH! KRAGH!" at 5.27 s) |
| Goblins `11_goblin_benji`, `12_goblin_archie` (and pitched) | Rejected: none of the goblins | — | New goblin voices needed |
| Other commanders and orcs | Not chosen | — | — |

Round 2 (24 Oct, `voices/higgsfield/round2`) is not reviewed yet. Placed in the
game until the owner listens, by the rule above (Knox was liked): Spearwall
(`stance_spearwall`), Square, Defend (`stance_footman`) and Overwatch, each
Knox's call with its gear; the player's rout ("Fall back!", "Run!" with men
running) and victory (Knox's "Amberfeld!" answered by five men's "Hurrah!
Amberfeld!"). The squads answer orders in his voice: picking a squad
("Orders?", "Ready."), a march ("Moving!", "On the double!"), an attack ("At
them!", "For Amberfeld!"), Charge ("Forward, shields!", "Drive them back!")
and Aimed Shot (only the "Loose!" of "Steady... loose!", so it comes with the
bolt). After a first listen the owner asked for the order answers quieter:
-14 dB instead of -8. The goblin takes wait for a verdict.

## Combat

| Sound | What it is | Verdict | In the game | Saved for |
| --- | --- | --- | --- | --- |
| `sword_swing_03` | Heavy melee swing (David Dumais) | Good | Swings (`swing`); trolls' swing pitched down (`swing_troll`); orcs' swing with a grunt (`swing_orc_*`) | |
| `sword_swing_04` | Designed swing (David Dumais) | Good | Swings (`swing`), misses (`miss`), orcs' swing | |
| `sword_swing_06` | Short bamboo-stick whooshes | Saved | — | **Throwing-dagger ability** |
| `sword_swing_08` | Fast cable swoosh | Saved | — | **Throwing-dagger ability** |
| `blade_armor_01` | Hard hit on chainmail | A thud hit | Hits on armoured squads (`hit_metal`) | Thud hits in general |
| `blade_armor_02` | Hard hit on plate | A thud hit | Hits on armoured squads (`hit_metal`) | Thud hits in general |
| `parry_block_01` | Weapon parry impact | Good | Blocks (`block`), with two wooden shield knocks | |
| `miss_whoosh_05` | Rod/pole whoosh | Good | Misses (`miss`); trolls' swing | |
| All `sword_clash_*` | Sword-on-sword clashes | Rejected: too high and loud | Removed from hits and blocks | — |

## Fire and magic

| Sound | What it is | Verdict | In the game | Saved for |
| --- | --- | --- | --- | --- |
| `fire_whoosh_s26_01` | Deep growling fire whoosh | Good | Fireball launch (`fireball`) | |
| `fire_whoosh_03` | Fire whoosh | Okay | Fireball launch (`fireball`) | |
| `fire_cast_01` | Fire spell | Saved | Removed from casting | **Dragon sounds** |
| `fire_explosion_03` | Large layered fireball ignition | Cool, saved | Removed from explosions | **Mystic sounds** |

## Camp

| Sound | What it is | Verdict | In the game | Saved for |
| --- | --- | --- | --- | --- |
| `forest_day_bed_06` | Baltic pine forest, calm wind | Selected for camp, 24 Oct | The only camp background; continuous loop, at -10.5 dB (30%) since the owner asked for it quieter on 24 Oct | |
| `forest_day_bed_01` | Woodland: wind, robin, blackbird | Liked, not selected for camp | — | Preserved for comparison |
| `forest_day_bed_09` | Lake birdlife, Kristdala, Sweden | Liked, not selected for camp | — | Preserved for comparison |
| `bird_chaffinch_01` | Chaffinch high in a tree | Liked; requested less often | Camp songbird calls, every 10–25 s, including the first call | |
| `bird_great_tit_03` | Great tit, single call | Now and then | One shared pool with raven and axe: one sound every 12–35 s | |
| `bird_raven_crow_03` | Common ravens | Now and then | Camp, occasional | |
| `wood_chop_02` | Axe chopping wood | Liked: tree loggers | Camp, occasional axe strikes | |
| `camp_murmur_02` | Group murmur outdoors | Good to 0:35; requested quieter and intermittent | Peak -6 dB relative to previous mix; 8 s fade in, 8–16 s hold, 8 s fade out, 20–40 s fully silent gaps | |
| `campfire_04` | Campfire, two spaced mics | Liked | Configured; inactive in painted camp because it has no fire anchor | |
| `forest_day_bed_07` | Wind in pines | Saved | Removed from the camp | **Storms** |

The camp changes above follow the owner's 24 October follow-up. Source audio
is unchanged; the engine controls murmur volume and gaps. The recipe retains
these settings on future bank builds. Great tit, raven and axe choices remain
open; this follow-up did not change their shared pool. Audition and inventory:
`workspace/2026-10-20_meridius/audio.html` (relative to the repository root).

## Movement

| Sound | What it is | Verdict | In the game | Saved for |
| --- | --- | --- | --- | --- |
| `boot_step_grass_04` | Boots through long grass and heather | Really good | Soldiers' footsteps (`step`): treads of two steps from it plus a little leather | Grass walking |
| `boot_step_dirt_08` | Single dirt footstep | Okay | Soldiers' footsteps (one tread) | |
| `armor_jingle_11` | Leather gear step layer | Okay | Under the soldiers' steps and the Shield Wall | |
| `march_group_01` | Group marching through mud | Okay | Campaign march (`march`) | |
| `armor_jingle_07` | Chain rattle | Saved | — | **Wagons** |

## Trolls and monsters

| Sound | What it is | Verdict | In the game | Saved for |
| --- | --- | --- | --- | --- |
| `troll_stomp_01` | Heavy creature footstep | Okay, lower and more thud | Troll footsteps (`step_troll`): pitched down 3–5 semitones, low-passed at 800 Hz, +8 dB at 70 Hz; also a troll's body landing when it dies | |
| `troll_roar_01` | Troll long growl | Good | Troll death (`death_troll`) | |
| `troll_roar_02` | Troll taunt/roar | Good | The horde's wave roar (`roar_wave`) | |
| `troll_grunt_breath_02` | Troll death vocal | Usable, slower and lower | Troll death: 0.8× speed and pitch (`death_troll`) | |
| `troll_grunt_breath_03` | Large monster breathing | Okay | Troll regeneration (`mend_troll`) | |
| `troll_grunt_breath_07` | Camel grunts | Okay for orcs | Orcs' attack grunt (`swing_orc_*`) | |
| `troll_roar_06` | Demon/lion growl-roar | Saved | — | **Another monster** |
| `troll_roar_08` | Deep layered monster growl | Saved | — | **Another monster** |
| `troll_roar_s26_01` | T-Rex roar | Saved | — | **A monster** |
| `troll_stomp_s26_01` | Trailer boom | Saved | Removed from large footsteps | **Entering a cave or dungeon** |
| `log_smash_05` | Conifer creaks and crashes down | Saved | — | **Falling trees** |

## Battle moments

| Sound | What it is | Verdict | In the game | Saved for |
| --- | --- | --- | --- | --- |
| `bird_raven_crow_07` | Crow cawing loudly while flying off | Saved | Removed from battle crows | **Arriving in an area: crows fly away** |
| `bird_raven_crow_08` | Crows cawing | Saved | Removed from battle crows | **After a battle, the fallen lying on the field** |

Day battles now have only the field wind (`wind_open_field_06`, Winds of
Dovrefjell) until those two moments get their hooks. The owner found it too
loud on 24 Oct: it now plays at -10.5 dB, 30% of its former level. The night
wind (`wind_open_field_03`) is unchanged.

## Night and the UI (24 Oct, second listen)

| Sound | What it is | Verdict | In the game |
| --- | --- | --- | --- |
| `owl_tawny_02` | Tawny owl calls, 23 s (Freesound CC0 preview) | Liked: the night owl | Night battles: its four calls cut apart (at 2.3, 7.4, 14.5 and 19.85 s, each with its tail; rumble below 300 Hz filtered out), one at a time every 10–45 s, panned at random. Replaces `owl_tawny_03` and `_04` |
| `ui_page_turn_01`, `ui_page_turn_02` | Parchment page turn, page turn | Liked | Page turns |
| `ui_page_turn_10` | Short book page flip | Liked: now and then | Page turns, at weight 0.25: about one turn in six |
| `ui_click_04`, `ui_click_s26_01` | UI click, vintage analog button | Rejected | Clicks are now `ui_click_03` and `_07` |
| `ui_click_05` | UI select | Rejected | Selecting is now the two armour jingles |
| `ui_coins_03` | Coins jingling in hand | Rejected: wants coins that really clink | — |
| `ui_building_02`, `ui_building_04` | Hammering a nail | Rejected | Building is now `ui_building_01` alone |

Gold spent or earned (`coin`) is new: four takes of coins clinking, replacing
the handled coins (`ui_coins_01`, `_10`, `_11`, not rejected, kept in the
library). One is the ting of coins together (`ui_coins_s26_01`, Sonniss GDC
2026, *Ting Coins*), two are single coins counted onto others (`ui_coins_02`,
cut at 1.06, 1.56, 2.26 and 2.86 s) dropped two or three at a time 70–150 ms
apart, one is the ting with a counted coin after it; ±0.3 semitones at random.
Not heard by the owner yet.

Day into night: on the owner's word, the sounds of one part of the day ebb
out slowly as the other's come in, over 6 s. The camp's Night button now
brings a night of its own (`camp_night`): the crickets come in at -8 dB, the owl calls as in night battles, and the
chaffinches, distant calls and murmur fade away, calls still coming, ever
quieter, until the fade ends. Day brings them back the same way. A night
battle's dawn does the same.

The night wind, heard in the camp the same day: the owner wanted it lower
sounding and quieter. It is now its own take, `camp_night_wind`: the day's
pine wind (`forest_day_bed_06`, the same cut) pitched down about 3.9
semitones, which also slows its gusts, with everything above 1.2 kHz rolled
off. Heard at -16.5 dB (about 7 dB under the day's) the owner found the
night good; after 70% of the day wind's level (-12.8 dB) they settled on
50%: -15.7 dB, -44.7 against the day's -38.7 LUFS (the night take on its
own is 0.8 dB quieter than the day's). The day wind fades into it over the same 6 s. The
night battle's wind (`wind_open_field_03`) is unchanged.

## Not reviewed yet

Still the earlier choices (from descriptions, not by ear): blade into flesh,
the round-2 voices, deaths of men, orcs, goblins, wolves and
hounds, the hounds' growl and lick, wolves, horns and drums, bows, crossbows
and war engines, lightning, frost, heal, hex, bloodlust, explosions, casting,
goblin and wolf footsteps, the rest of the night (wind, crickets, wolf howl), the
new coins and the UI's armour-jingle select.
