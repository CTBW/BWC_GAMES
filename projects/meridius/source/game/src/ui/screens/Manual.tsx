import { useState } from 'react';
import { Icon } from '../common';

const PAGES: { id: string; title: string; body: React.ReactNode }[] = [
  {
    id: 'battle',
    title: 'Battle',
    body: (
      <>
        <p>
          Each turn every squad may <b>move once</b> and <b>act once</b>, in either order. Click a squad, then a blue tile to move. Click an enemy to attack. If the enemy is out of reach, the squad moves next to it first; <b>move the cursor around the enemy to choose which side you strike from</b>.
        </p>
        <p>
          A blue tile hidden behind one of your own squads can still be clicked: the move wins, and a faint ghost shows where your squad will stand. Changed your mind? <b>Redo move</b> (or <kbd>Backspace</kbd>) walks the squad back to where the turn began so you can move again, as long as it has not attacked yet. A move the enemy reacted to (a free attack, a spearwall or an overwatch shot) cannot be taken back.
        </p>
        <p>
          <b>Facing comes from marching.</b> A squad faces the way it took its <b>last step</b>, and nothing else turns it: not attacking, not being attacked. The chevron at a squad's feet shows where it faces. When you choose a destination, the gold arrow on the tile shows the facing it will arrive with. <b>Point at an edge of the tile</b> to arrive facing that edge, or press <kbd>Q</kbd>/<kbd>E</kbd> to try the other sides (faint arrows mark them). To turn without moving, point at an edge of the squad's own tile: it steps out and back, which uses its move.
        </p>
        <p>
          Attacks into the <b>flank</b> gain +10% to hit; attacks from <b>behind</b> gain +20%, deal +25% damage, ignore shields and shake morale. Shields guard the front; a shield wall also guards the flanks. Spearwall and overwatch watch the front and flanks, never the rear.
        </p>
        <p>
          <b>Zones of control.</b> Stepping away from an enemy's front or flank invites a free attack; a squad cannot strike at what moves behind its back. Orange path markers warn you. A solid line protects the crossbows behind it.
        </p>
        <p>
          <b>Ground.</b> High ground gives +8% per level to hit (and extends crossbow range); attacking uphill costs the same. Thickets and woods slow movement and hide troops from missiles. Rocks, walls and fences give cover against shots that pass them. Trees and boulders block line of sight.
        </p>
      </>
    ),
  },
  {
    id: 'horde',
    title: 'The Horde',
    body: (
      <>
        <p>
          You are always outnumbered. The host does not win by skill but by numbers: it <b>swarms round the flanks</b>, piles into any gap in your line and goes for the weakest squad it can reach. You win by <b>position</b>: hold narrow ground, keep your flanks against walls and woods, face the enemy, and let them come to you a few at a time.
        </p>
        <p>
          <b>Its troops.</b> <i>Goblin rabble</i> come nine to a squad, weak alone but deadly around a flank. <i>Goblin spearmen</i> and <i>archers</i> are the body of the host. <i>Wolf riders</i> are fast, slip away from blows and hunt your crossbowmen; set spears stop them. <i>Orc brutes</i> smash a squad back out of the line and push into the gap. A <i>horn-bearer</i> calls for help if he lives long enough.
        </p>
        <p>
          <b>Waves.</b> More of them are always coming. Squads massing beyond the edge of the field will march in soon: red markers on the edge tiles show where a wave arrives at the end of this turn, and the top of the screen counts the turns. Use the time to close the line where they will strike.
        </p>
        <p>
          <b>How battles end.</b> Each battle says what wins it (top of the screen). Small fights are won by destroying or routing every enemy, but a <b>war horn</b> sounded in time brings more of them: kill the horn-bearer first. A <b>stand</b> is won by holding until the relief arrives; the enemy must never hold the <b>ground marked in gold</b> at the end of two of its turns running. In the last stand, slaying the <b>warchief</b> breaks the whole host. If the company is destroyed or routed, the battle is lost.
        </p>
        <p>
          <b>Bigger fields.</b> Last stands are fought on large maps. Scroll to zoom out to the whole field, drag with the right mouse button or use the arrow keys to pan, and click the minimap (bottom left) to jump.
        </p>
      </>
    ),
  },
  {
    id: 'squads',
    title: 'Squads',
    body: (
      <>
        <p>
          Every unit on the field is a <b>squad</b> of <b>six soldiers</b> (moss trolls go in threes) that moves, fights and holds its ground as one. A squad is known by its sergeant's name: <i>Aldric's footmen</i>. The pips beside a squad show its strength: <b>filled</b> pips are soldiers still serving, <b>hollow</b> ones have fallen.
        </p>
        <p>
          <b>Shared health.</b> The squad has one pool of HP, split into a share per soldier (the segments of its health bar). Each time the pool drops past a share, a soldier <b>falls</b>; one heavy blow can cut down several. When the last share is gone the squad is destroyed.
        </p>
        <p>
          <b>Damage is soldiers × blows.</b> Every soldier still standing strikes: a squad of five footmen dealing 7–10 each hits for 35–50 before armour (armour is taken off each blow). A thinned squad hits softer, so wearing an enemy down pays. The forecast shows how many soldiers strike, how many of the target a hit would slay, and the chance to destroy the squad outright.
        </p>
        <p>
          <b>The dead stay dead.</b> Camps, bandages and the trip home heal the survivors, never the fallen. Only the <b>Barracks</b> at Amberfeld can refill a squad's empty places, for a little silver per soldier. A squad cut down in battle may still keep its sergeant, gravely hurt; he can rebuild it.
          <br />
          <b>Field triage.</b> Right after a battle the surgeons search the fallen. Each soldier who fell has the same chance to be found alive as a lone soldier always had (better at higher rank, with bandages and a better Infirmary, and when you hold the field). Those found rejoin their squad badly hurt. Nobody else comes back.
        </p>
      </>
    ),
  },
  {
    id: 'magic',
    title: 'Magic & Machines',
    body: (
      <>
        <p>
          <b>Spells.</b> Mages and shamans come three to a squad. Choose a spell from the squad's panel (or press its number), then click what to cast it at; right-click or <kbd>Esc</kbd> puts it away. The forecast lists every squad the spell would touch. Spells are <b>per caster</b>: three mages cast three times as hard as one, so every mage lost weakens the circle. Each spell then needs a few turns before it can be cast again; between spells the casters loose weak bolts of their own power. A wavering squad cannot cast.
        </p>
        <p>
          <Icon name="staff" /> <b>Battle Mages</b> (Amberfeld): <i>Chain Lightning</i> strikes a squad in sight and arcs on to two more foes nearby, ignoring armour. <i>Frost Blast</i> freezes a squad and those beside it: <b>chilled</b> squads move half as far, hit worse and are easier to hit until the end of their next turn. <i>Healing Light</i> closes a squad's wounds; promoted mages learn the <i>Mending Circle</i> that heals everyone close by. Healing never raises the dead.
        </p>
        <p>
          <b>Goblin Shamans</b> (the host): a <i>Fireball</i> bursts on a tile and burns <b>friend and foe</b> beside it; a miss lands a tile astray. <i>Bloodlust</i> drives a goblin squad into a frenzy (harder blows, no fear, but careless of its guard) until the end of its next turn. <i>Gutripper</i> tears at a squad's insides: it ignores armour and the squad <b>bleeds</b> at the start of its next two turns. Kill the shamans first.
        </p>
        <p>
          <Icon name="engine" /> <b>War machines</b> are one engine and its crew of three; the crew is the squad, its health and its strength, and when the last of them falls the engine is wrecked. A machine <b>cannot loose in a turn it has moved</b>: place it, then let it work. The <i>Ballista</i> shoots a great bolt that goes on through into the foe behind. The <i>Mangonel</i> lobs a stone over walls and heads (no line of sight needed, nothing closer than three tiles): it smashes the squad it lands on and half as hard everyone beside it, <b>your own squads too</b>, and a miss lands a tile astray. The host fields <i>Rock Lobbers</i>, cruder and less accurate, and <i>Spiked War Wagons</i> that ram a squad back out of the line; meet them with set spears.
        </p>
        <p>
          The Barracks offers one specialist squad each muster: battle mages, a ballista or a mangonel.
        </p>
      </>
    ),
  },
  {
    id: 'units',
    title: 'Your Troops',
    body: (
      <>
        <p>
          <Icon name="shield" /> <b>Footmen</b> hold the line. Their kite shields add defense against attacks from the front. <b>Shield Wall</b> makes them very hard to hit and protects adjacent comrades.
        </p>
        <p>
          <Icon name="spear" /> <b>Spearmen</b> punish anyone who charges in carelessly: they <b>strike first</b> when attacked from the front by an enemy who moved. <b>Spearwall</b> strikes the first enemy to step next to them at +50% damage and stops its advance on a hit. Perfect for bridges, fords and gaps in a wall.
        </p>
        <p>
          <Icon name="crossbow" /> <b>Crossbowmen</b> hit hard at range and pierce armour, best when they have not moved (<b>steady aim</b>). They cannot shoot point-blank and are weak in melee. Every shot costs a bolt; refill quivers from spare bolts. <b>Overwatch</b> shoots the first enemy that moves into sight during the enemy turn.
        </p>
        <p>
          <Icon name="shield" /> The <b>Border Collie Royal Guard</b> are rare elite squads that answer a proper Barracks (level 2). Quick, heavily armoured and hard to break, they stand in the front rank like footmen.
        </p>
        <p>
          Veteran squads can be <b>promoted</b> at the Training Yard to learn Shield Bash, Pike Thrust or Heavy Bolt.
        </p>
      </>
    ),
  },
  {
    id: 'morale',
    title: 'Morale and Rout',
    body: (
      <>
        <p>
          Every squad has <b>morale</b> (the blue bar). Wounds, flank and rear attacks, comrades falling nearby, being surrounded and a losing battle all drain it. Victories, felling foes and standing beside comrades restore it.
        </p>
        <p>
          <b>Confident</b> troops fight better. <b>Shaken</b> and <b>Wavering</b> troops fight worse; wavering troops cannot use abilities. At zero morale a unit <b>routs</b> and flees the field. It may rally if it gets clear of the enemy.
        </p>
        <p>
          Goblins break easily; orcs do not. Kill a warband's <b>leader</b> and the rest lose heart; slay the host's <b>warchief</b> and the whole horde breaks and runs.
        </p>
        <p>
          Soldiers still lying on the field after the surgeons' search are gone for good. When a whole squad is cut down its sergeant may survive, gravely wounded, with a lasting injury; carried bandages and better surgeons improve the odds. The dead stay dead.
        </p>
      </>
    ),
  },
  {
    id: 'campaign',
    title: 'Expeditions',
    body: (
      <>
        <p>
          On campaign, choose your path across the map. Every march eats <b>rations</b> (one per two squads) and tires the army. Hungry soldiers lose morale and strength, and a weak one may not survive. Wounds, fallen soldiers, morale, fatigue and spent bolts carry from one battle to the next.
        </p>
        <p>
          <b>Camps</b> let you rest (rations), keep watch (torches) and mend armour (tools). <b>Villages</b> hide loot; strongboxes need tools. <b>Lookouts</b> reveal the road ahead, including enemy numbers. <b>Encounters</b> ask for decisions that cost or reward.
        </p>
        <p>
          You may <b>retreat home</b> at any time and keep the spoils, but the objective's reward is lost. A broken army loses half its spoils.
        </p>
      </>
    ),
  },
  {
    id: 'base',
    title: 'Amberfeld',
    body: (
      <>
        <p>
          Between expeditions the company rests at Amberfeld and the survivors heal. Spend silver, timber, iron and war trophies to upgrade buildings: more command points and slots (Command Tent), better recruits and reinforcements (Barracks), drill and promotions (Training Yard), better gear (Armoury), cheaper treatment and better survival odds (Infirmary), and a bigger wagon (Quartermaster).
        </p>
        <p>
          Every expedition is capped by <b>unit slots</b> and <b>command points</b>, one slot per squad. Veteran squads cost more points than recruits, so you can never bring everyone. Refill thinned squads at the Barracks before you march. Squads who stay home recover morale; those treated or sent on leave sit out one expedition.
        </p>
      </>
    ),
  },
];

export function Manual({ onClose, start = 'battle' }: { onClose: () => void; start?: string }) {
  const [page, setPage] = useState(start);
  const p = PAGES.find((x) => x.id === page) ?? PAGES[0];
  return (
    <div className="modal-back" onClick={onClose} style={{ zIndex: 40 }}>
      <div className="panel dialog" style={{ width: 760 }} onClick={(e) => e.stopPropagation()}>
        <div className="title">Captain's Field Manual</div>
        <div className="row" style={{ gap: 6, flexWrap: 'wrap', justifyContent: 'center', marginBottom: 6 }}>
          {PAGES.map((x) => (
            <button key={x.id} className={`btn sm ${x.id === page ? 'gold' : 'ghost'}`} onClick={() => setPage(x.id)}>
              {x.title}
            </button>
          ))}
        </div>
        <div className="scroll" style={{ maxHeight: '58vh', fontSize: 16, lineHeight: 1.45 }}>
          {p.body}
        </div>
        <div className="row" style={{ justifyContent: 'center', marginTop: 10 }}>
          <button className="btn primary" onClick={onClose}>
            To the field
          </button>
        </div>
      </div>
    </div>
  );
}

const SEEN_KEY = 'meridius.manual.seen';
export function manualSeen(): boolean {
  try {
    return localStorage.getItem(SEEN_KEY) === '1';
  } catch {
    return true;
  }
}
export function markManualSeen() {
  try {
    localStorage.setItem(SEEN_KEY, '1');
  } catch {
    /* ignore */
  }
}
