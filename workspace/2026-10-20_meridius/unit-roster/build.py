"""Meridius unit roster: rebuilds the three roster tabs from the Godot game data.

Reads data/units.json, data/abilities.json and the battle frames in
assets/sprites/anim/, crops each unit's front idle frame into img/<id>.png and
writes unit-roster-garrison.html, unit-roster-allies.html and
unit-roster-host.html next to this folder. Run it again after units change:

    python workspace/2026-10-20_meridius/unit-roster/build.py
"""
import html
import json
from datetime import date
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
CARD = HERE.parent
GAME = HERE.parents[2] / 'projects' / 'meridius' / 'source' / 'godot'

# Units drawn in battle that have no entry in units.json.
EXTRA = {
    'engineer': {
        'name': 'Engineer', 'role': 'War machine crew', 'faction': 'player',
        'blurb': 'Garrison craftsmen in leather aprons who wheel, wind and loose the ballista and the mangonel. '
                 'They come with the machine, three to a crew, and are no fighters.',
        'facts': ['Crew of the Ballista and Mangonel', 'Uses the machine\'s stats'],
    },
    'margrave_rider': {
        'name': "Margrave's Rider", 'role': 'Dawn relief', 'faction': 'player',
        'blurb': "The Margrave's lancers. If the last stand at Brannsted holds through the night, they crest the hill "
                 'at sunrise and charge into the host. The player never commands them.',
        'facts': ['Rides in at dawn', 'Drawn only: no stats or rules'],
    },
}

ALT = {
    'footman': 'Footman in a blue cloak and cream tabard with a sword and a blue kite shield bearing a white eagle',
    'spearman': 'Bearded spearman in a blue cloak holding an upright spear',
    'crossbowman': 'Crossbowman in a blue cloak holding a loaded crossbow',
    'collie_guard': 'Border collie in black plate with a sword and a black shield bearing a gold eagle',
    'battle_mage': 'Grey-bearded mage in hooded blue robes with a staff topped by a glowing orb',
    'ballista': 'Wheeled ballista carriage in blue and timber with a loaded bolt and a blue pennant',
    'mangonel': 'Blue-painted mangonel on wheels with its throwing arm loaded with a stone',
    'goblin_spear': 'Green goblin in a spiked helmet and leather straps holding a spear',
    'goblin_archer': 'Hooded goblin archer with a longbow and a quiver',
    'orc_warrior': 'Orc warrior in a crested helmet with a cleaver and a round red shield',
    'goblin_rabble': 'Lean goblin in a loincloth with a knife and a battered wooden shield',
    'wolf_rider': 'Hooded goblin with a spear riding a snarling grey wolf',
    'goblin_horn': 'Goblin blowing a long curved war horn, with a red banner on its back',
    'orc_brute': 'Orc with a red crest, spiked pauldrons and a spiked club',
    'troll': 'Hunched pale troll with a mossy log over one shoulder and green swirling markings',
    'orc_warlord': 'Orc warlord in red armour with a horned helm, a great axe and twin banners',
    'goblin_shaman': 'Goblin shaman wearing antlers, holding a staff topped with a horned skull',
    'rock_lobber': 'Crude timber catapult hung with skulls, with a sack of stones and a red flag',
    'war_wagon': 'Wooden cart bristling with iron spikes and skulls, flying red flags',
    'militia': 'Bald farmer in a brown tunic holding a pitchfork',
    'engineer': 'Bearded engineer in a leather apron carrying a large mallet',
    'margrave_rider': 'Lancer in a steel helmet on a horse with a blue star caparison, lance raised with a pennant',
}

GARRISON_SOURCE = {
    'footman': 'Barracks, every muster', 'spearman': 'Barracks, every muster',
    'crossbowman': 'Barracks, every muster', 'collie_guard': 'Barracks level 2, now and then',
    'battle_mage': 'Barracks specialist offer', 'ballista': 'Barracks specialist offer',
    'mangonel': 'Barracks specialist offer',
}
ALLY_SOURCE = {
    'militia': 'Fights beside you in Cover the refugees and The last stand at Brannsted',
}

PAGES = [
    {
        'file': 'unit-roster-garrison.html', 'title': 'Garrison',
        'lead': 'The {n} squad types the player can recruit and command. Footmen, spearmen and crossbowmen come from '
                'every muster at the Barracks; the Border Collie Royal Guard can answer once it reaches level 2; and '
                'each muster offers one specialist squad: battle mages, a ballista or a mangonel.',
        'sections': [
            ('Line troops', ['footman', 'spearman', 'crossbowman', 'collie_guard']),
            ('Specialists', ['battle_mage', 'ballista', 'mangonel']),
        ],
    },
    {
        'file': 'unit-roster-allies.html', 'title': 'Allies and crews',
        'lead': 'The {n} friendly figures that fight on the garrison\'s side without being recruited: the local militia '
                'in two encounters, the engineers who crew the war machines and the Margrave\'s riders who end the '
                'last stand at dawn.',
        'sections': [('Allies and crews', ['militia', 'engineer', 'margrave_rider'])],
    },
    {
        'file': 'unit-roster-host.html', 'title': 'Hillsvain Host',
        'lead': 'The {n} enemy units of the Hillsvain Host. Goblins make up the bulk of every wave, orcs and trolls '
                'break the line, and two crude war engines appear in their own encounter.',
        'sections': [
            ('Goblins', ['goblin_rabble', 'goblin_spear', 'goblin_archer', 'wolf_rider', 'goblin_horn', 'goblin_shaman']),
            ('Orcs and trolls', ['orc_warrior', 'orc_brute', 'orc_warlord', 'troll']),
            ('War engines', ['rock_lobber', 'war_wagon']),
        ],
    },
]

# Tints mix from the --mak-* tokens, which the light theme overrides (report.css pins --card2 dark on body).
STYLE = """
    .roster-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
    .unit { display: grid; grid-template-columns: 128px minmax(0, 1fr); gap: 16px; padding: 14px; margin: 0;
            border: 1px solid var(--mak-border); --tint: color-mix(in srgb, var(--mak-text) 7%, transparent); }
    .unit-art { margin: 0; height: 148px; display: flex; align-items: flex-end; justify-content: center;
                padding: 8px; border-radius: 9px; background: var(--tint); }
    .unit-art img { max-width: 100%; max-height: 100%; object-fit: contain; cursor: zoom-in; }
    html[data-mak-report] .unit h3 { margin: 0 0 2px; font-size: 16px; line-height: 1.4; }
    .unit .role { display: inline-block; font-size: 11px; letter-spacing: .08em; text-transform: uppercase;
                  color: var(--mak-accent); margin: 0 0 6px; }
    .unit p { margin: 0 0 8px; font-size: 13px; line-height: 1.6; }
    .unit .facts { color: var(--mak-muted); font-size: 12px; margin-bottom: 8px; }
    .unit .skills { display: flex; flex-wrap: wrap; gap: 5px; margin: 0; }
    .unit .skills span { font-size: 11px; line-height: 1.5; padding: 2px 8px; border-radius: 999px;
                         background: var(--tint); border: 1px solid var(--mak-border); cursor: help; }
    .unit .skills .promo { border-style: dashed; }
    .roster-foot { margin-top: 40px; font-size: 12px; color: var(--mak-muted); }
"""


def esc(text):
    return html.escape(str(text), quote=True)


def frame(unit_id):
    """The first soldier's front idle frame, trimmed to its pixels."""
    table = json.loads((GAME / 'assets/sprites/anim' / f'{unit_id}.json').read_text(encoding='utf-8'))
    frames = table['frames']
    x, y, w, h = (frames.get('idle_f_0') or frames['idle_f'])[0]['region']
    sheet = Image.open(GAME / 'assets/sprites/anim' / f'{unit_id}.png').convert('RGBA')
    image = sheet.crop((x, y, x + w, y + h))
    return image.crop(image.getbbox())


def span(values):
    return f'{values[0]}–{values[1]}'


def facts(unit_id, u):
    if unit_id in EXTRA:
        return EXTRA[unit_id]['facts']
    base = u['base']
    size = u.get('squad', 6)
    out = []
    if u.get('crew'):
        out.append(f'1 machine, crew of {size}')
    elif u.get('escort'):
        out.append(f'Squad of {size} with escort')
    else:
        out.append(f'Squad of {size}')
    out.append(f'{base["hp"]} HP each')
    out.append(f'Move {base["move"]}')
    out.append(f'Armour {base["armor"]}')
    shot = u.get('shot')
    if shot:
        out.append(f'Shot {span(shot["damage"])} at {shot["minRange"]}–{shot["range"]} tiles')
    elif not u.get('primary'):
        out.append(f'Melee {span(u["melee"])}')
    return out


def card(unit_id, units, abilities, faction):
    u = units.get(unit_id) or EXTRA[unit_id]
    path = f'unit-roster/img/{unit_id}.png'
    with Image.open(CARD / path) as image:
        w, h = image.size
    lines = list(facts(unit_id, u))
    source = GARRISON_SOURCE.get(unit_id) or ALLY_SOURCE.get(unit_id)
    if faction == 'garrison' and unit_id in units:
        lines.append(f'{u["recruitCost"]} silver, {u["commandCost"]} command')
    skills = []
    for ability in u.get('abilities', []):
        a = abilities[ability]
        skills.append(f'<span title="{esc(a["description"])}">{esc(a["name"])}</span>')
    if u.get('promotion'):
        a = abilities[u['promotion']]
        skills.append(f'<span class="promo" title="Promotion. {esc(a["description"])}">{esc(a["name"])} · promotion</span>')
    alt = ALT[unit_id]
    return f"""      <article class="card unit" id="{unit_id}">
        <figure class="unit-art"><img src="{path}" alt="{esc(alt)}" width="{w}" height="{h}" loading="lazy"></figure>
        <div>
          <h3>{esc(u['name'])}</h3>
          <span class="role">{esc(u['role'])}</span>
          <p>{esc(u['blurb'])}</p>
          <p class="facts">{' · '.join(esc(x) for x in lines)}</p>
          {f'<p class="facts">{esc(source)}</p>' if source else ''}
          {f'<p class="skills">{"".join(skills)}</p>' if skills else ''}
        </div>
      </article>"""


def page(spec, units, abilities, today):
    faction = {'Garrison': 'garrison', 'Allies and crews': 'allies'}.get(spec['title'], 'host')
    ids = [i for _, group in spec['sections'] for i in group]
    sections = []
    for heading, group in spec['sections']:
        cards = '\n'.join(card(i, units, abilities, faction) for i in group)
        title = f'    <h2>{esc(heading)}</h2>\n' if len(spec['sections']) > 1 else ''
        sections.append(f'{title}    <div class="roster-grid">\n{cards}\n    </div>')
    body = '\n'.join(sections)
    return f"""<!doctype html>
<html lang="en" data-mak-report="document">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Meridius · Unit roster · {esc(spec['title'])}</title>
  <link rel="stylesheet" href="../_shared/report.css">
  <link rel="stylesheet" href="../_shared/examples.css">
  <script defer src="../_shared/report.js"></script>
  <style>{STYLE}  </style>
</head>
<body>
  <main class="container">
    <p class="eyebrow">Meridius · Unit roster</p>
    <h1>{esc(spec['title'])}</h1>
    <p class="lead">{esc(spec['lead'].format(n=len(ids)))}</p>
    <p class="meta">Images are the in-game battle frames (front idle, first soldier of the squad). Descriptions and
      numbers come from the game data as of {today}. Stats are per soldier at level 1; hover an ability for its rules.</p>
{body}
    <p class="roster-foot">Source: <code>projects/meridius/source/godot/data/units.json</code>, <code>abilities.json</code> and
      <code>assets/sprites/anim/</code>. The succubus and wolf scout rigs under Character rigs are prototypes without a
      unit entry, so they are not listed. Rebuild with <code>python workspace/2026-10-20_meridius/unit-roster/build.py</code>.</p>
  </main>
</body>
</html>
"""


def main():
    units = json.loads((GAME / 'data/units.json').read_text(encoding='utf-8'))['UNIT_TYPES']
    abilities = json.loads((GAME / 'data/abilities.json').read_text(encoding='utf-8'))['ABILITIES']
    listed = [i for spec in PAGES for _, group in spec['sections'] for i in group]
    missing = sorted(set(units) - set(listed))
    if missing:
        raise SystemExit(f'units.json has units the roster does not place: {", ".join(missing)}')
    (HERE / 'img').mkdir(exist_ok=True)
    for unit_id in listed:
        frame(unit_id).save(HERE / 'img' / f'{unit_id}.png', optimize=True)
    today = date.today().strftime('%d %B %Y').lstrip('0')
    for spec in PAGES:
        (CARD / spec['file']).write_text(page(spec, units, abilities, today), encoding='utf-8', newline='\n')
    print(f'{len(listed)} units, {len(PAGES)} pages')


if __name__ == '__main__':
    main()
