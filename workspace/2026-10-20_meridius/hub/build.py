"""Meridius game guide: rebuilds hub.html, the card's first tab, from the Godot game data.

One page with its own section menu, laid out like the Mr. Mak 64 starter: overview,
characters, factions, abilities, animations, terrain and the card's other tabs. Reads
data/*.json, the battle frames in assets/sprites/anim/, assets/icons/ and
assets/sprites/blender/, and reuses the unit roster's figures, alt texts and faction
lists (unit-roster/build.py). Writes hub.html next to this folder, and poses/ and props/
here. Run it again after the game data changes (rebuild the roster first if units
changed):

    python workspace/2026-10-20_meridius/hub/build.py
"""
import importlib.util
import json
import re
from datetime import date
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
CARD = HERE.parent
REPO = HERE.parents[2]
GAME = REPO / 'projects' / 'meridius' / 'source' / 'godot'
ANIM = GAME / 'assets/sprites/anim'

_spec = importlib.util.spec_from_file_location('unit_roster', CARD / 'unit-roster' / 'build.py')
roster = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(roster)
esc = roster.esc

SECTIONS = [
    ('overview', 'Overview'), ('characters', 'Characters'), ('factions', 'Factions'), ('abilities', 'Abilities'),
    ('animations', 'Animations'), ('terrain', 'Terrain'), ('pages', 'More pages'),
]

# The roster's three pages are the three sides; the hub keeps its split.
FACTIONS = [
    {'id': 'garrison', 'name': 'Amberfeld Garrison', 'roster': 'Garrison'},
    {'id': 'allies', 'name': 'Allies and crews', 'roster': 'Allies and crews'},
    {'id': 'host', 'name': 'Hillsvain Host', 'roster': 'Hillsvain Host'},
]

KINDS = [('stance', 'Stances'), ('attack', 'Attacks'), ('shout', 'Shouts'), ('spell', 'Spells')]
FACINGS = {'f': 'front', 'fs': 'front side', 'b': 'back', 'bs': 'back side'}

# Front view, first soldier. soldier_anim.gd draws idle, walk 0..2, wind and hit; death lies in between.
POSES = [('idle_f_0', 'Idle 1'), ('idle_f_1', 'Idle 2'), ('idle_f_2', 'Idle 3'), ('walk_f_0', 'Walk 1'),
         ('walk_f_1', 'Walk 2'), ('walk_f_2', 'Walk 3'), ('strike_f_wind', 'Wind-up'), ('strike_f_hit', 'Strike'),
         ('death_f_kneel', 'Falling'), ('death_f_down', 'Down')]
ENGINE_POSES = [('idle_f', 'At rest'), ('atk_f', 'Loosing')]
# soldier_anim.gd: a breath frame shows IDLE_FRAME (0.42 s) in the loop 0 1 2 1; a stride (two steps,
# _gait.json) plays walk 0 1 2 1; a blow winds up about 0.18 s, cuts and holds about 0.2 s.
IDLE_FRAME = 0.42

# The Character rigs subgroups that are rigs of a unit in units.json.
RIG_UNITS = {'Footman': 'footman', 'Crossbowman': 'crossbowman', 'Spearman': 'spearman', 'Mage': 'battle_mage',
             'Goblin Rabble': 'goblin_rabble'}

HERO = 'media/horde-stand-dawn.jpg'

SVG_BODY = re.compile(r'<svg[^>]*>(.*)</svg>', re.S)


def load(name):
    return json.loads((GAME / 'data' / name).read_text(encoding='utf-8'))


def gait_stride(unit_id, gait):
    """A type's walk cycle in seconds: 'default', then its 'types' entry ('like' copies another first)."""
    types = gait.get('types', {})

    def resolve(type_id, seen=()):
        entry = types.get(type_id, {})
        out = dict(resolve(entry['like'], seen + (type_id,))) if entry.get('like') and entry['like'] not in seen else {}
        out.update({k: v for k, v in entry.items() if k != 'like'})
        return out

    return {**gait['default'], **resolve(unit_id)}['stride']


def anim_table(unit_id):
    return json.loads((ANIM / f'{unit_id}.json').read_text(encoding='utf-8'))


def pose_strip(unit_id, table):
    """Every pose of the first soldier side by side, feet on one line, as poses/<id>.webp."""
    frames = table['frames']
    poses = POSES if 'walk_f_0' in frames else ENGINE_POSES
    poses = [(key, label) for key, label in poses if key in frames]
    sheet = Image.open(ANIM / f'{unit_id}.png').convert('RGBA')
    cuts = []
    for key, _ in poses:
        f = frames[key][0]
        x, y, w, h = f['region']
        cuts.append((sheet.crop((x, y, x + w, y + h)), f['ax'], f['ay']))
    pad = 8
    left = max(ax for _, ax, _ in cuts)
    right = max(c.width - ax for c, ax, _ in cuts)
    top = max(ay for _, _, ay in cuts)
    bottom = max(c.height - ay for c, _, ay in cuts)
    cw, ch = round(left + right) + 2 * pad, round(top + bottom) + 2 * pad
    strip = Image.new('RGBA', (cw * len(cuts), ch), (0, 0, 0, 0))
    for i, (crop, ax, ay) in enumerate(cuts):
        strip.alpha_composite(crop, (i * cw + round(pad + left - ax), round(pad + top - ay)))
    (HERE / 'poses').mkdir(exist_ok=True)
    strip.save(HERE / 'poses' / f'{unit_id}.webp', quality=88, method=6)
    return {'labels': [label for _, label in poses], 'cw': cw, 'ch': ch, 'engine': 'walk_f_0' not in frames}


def prop_image(sprite):
    """A prop's first Blender render, at most 260 px, as props/<sprite>.webp; None when it has none."""
    source = GAME / 'assets/sprites/blender' / f'{sprite}_0.webp'
    if not source.exists():
        return None
    image = Image.open(source).convert('RGBA')
    image = image.crop(image.getbbox())
    image.thumbnail((260, 260))
    (HERE / 'props').mkdir(exist_ok=True)
    image.save(HERE / 'props' / f'{sprite}.webp', quality=88, method=6)
    return f'hub/props/{sprite}.webp', image.size


def icon_symbols(abilities):
    out = []
    for name in sorted({a['icon'] for a in abilities.values()}):
        svg = (GAME / 'assets/icons' / f'{name}.svg').read_text(encoding='utf-8')
        view = re.search(r'viewBox="([^"]+)"', svg).group(1)
        out.append(f'<symbol id="icon-{name}" viewBox="{view}">{SVG_BODY.search(svg).group(1).strip()}</symbol>')
    return '<svg class="icon-sprite" aria-hidden="true">' + ''.join(out) + '</svg>'


def icon(name):
    return f'<span class="icon-tile" aria-hidden="true"><svg><use href="#icon-{name}"></use></svg></span>'


def tab_link(step):
    # Another tab of the card. In Mr. Mak hub.js asks the app to open it; from disk it opens the page.
    return f'<a class="tab-link" href="{esc(step["path"])}" data-step="{esc(step["path"])}">{esc(step["name"])}</a>'


def rig_line(rig):
    return f'3D rig: Character rigs ▸ {esc(rig["subgroup"])} ({", ".join(tab_link(t) for t in rig["tabs"])})'


def chip(unit_id, units, page='characters', note=''):
    u = units[unit_id]
    extra = f' <small>{esc(note)}</small>' if note else ''
    return (f'<button type="button" class="unit-chip" data-goto="{page}:{unit_id}">'
            f'<span class="chip-face" style="background-image:url(\'unit-roster/img/{unit_id}.png\')"></span>'
            f'{esc(u["name"])}{extra}</button>')


def span(values):
    return f'{values[0]}–{values[1]}'


def ability_numbers(a):
    out = [dict(KINDS)[a['kind']][:-1]]
    if a.get('reach'):
        out.append(f'reach {a["reach"]}')
    if a.get('range'):
        out.append(f'range {a["minRange"]}–{a["range"]}' if a.get('minRange') else f'range {a["range"]}')
    if a.get('cooldown'):
        out.append(f'cooldown {a["cooldown"]}')
    return ' · '.join(out)


def stat_grid(u):
    base = u['base']
    cells = [('HP', base['hp']), ('Morale', base['morale']), ('Melee', base['melee']),
             ('Defense', f'{base["defense"]}' + (f' <small>+{u["shieldFront"]} shield</small>' if u.get('shieldFront') else '')),
             ('Ranged def.', base['rangedDefense']), ('Armour', base['armor']), ('Move', base['move'])]
    shot = u.get('shot')
    if shot:
        cells.append(('Shot', f'{span(shot["damage"])} <small>{shot["minRange"]}–{shot["range"]} tiles</small>'))
    elif not u.get('primary'):
        cells.append(('Damage', span(u['melee'])))
    return '<dl class="stat-grid">' + ''.join(f'<div><dt>{k}</dt><dd>{v}</dd></div>' for k, v in cells) + '</dl>'


def per_level(u):
    grow = u.get('perLevel') or {}
    names = {'hp': 'HP', 'melee': 'melee', 'ranged': 'ranged', 'defense': 'defense', 'morale': 'morale'}
    return ', '.join(f'+{v} {names.get(k, k)}' for k, v in grow.items())


def encounter_units(e):
    ids = [row[0] for row in e.get('units', [])]
    for wave in e.get('waves', []):
        ids += [row[0] for row in wave.get('units', [])]
    return list(dict.fromkeys(ids))


# ── pages ──────────────────────────────────────────────────────────────────────


def page_overview(ctx):
    camp = ctx['campaign']
    stats = [(len(ctx['order']), 'figures on the field'), (len(ctx['abilities']), 'abilities'),
             (len(ctx['encounters']), 'encounters'), (len(ctx['terrain']), 'kinds of ground')]
    stat_html = ''.join(f'<div><strong>{n:02d}</strong><span>{esc(t)}</span></div>' for n, t in stats)
    guide = ''.join(
        f'<li><button type="button" class="text-action" data-open="{sid}">{esc(name)}</button> {esc(text)}</li>'
        for sid, name, text in [
            ('characters', 'Characters', 'every unit with its stats, abilities, poses and where it fights.'),
            ('factions', 'Factions', 'the garrison, its allies and the host, side by side.'),
            ('abilities', 'Abilities', 'all abilities by kind, and which units carry them.'),
            ('animations', 'Animations', 'the drawn battle poses, playing at game timing, and the 3D rigs.'),
            ('terrain', 'Terrain', 'ground, obstacles and the five battlefields.'),
            ('pages', 'More pages', 'the card\'s other tabs and where to find them.'),
        ])
    encounters = []
    for e in ctx['encounters']:
        units = encounter_units(e)
        allies = [row[0] for row in e.get('allies', [])]
        goal = e.get('goal', {})
        maps = ', '.join(ctx['maps'][m]['name'] for m in e.get('maps', []) if m in ctx['maps'])
        chips = ''.join(chip(i, ctx['units']) for i in units + allies if i in ctx['units'])
        flags = list(dict.fromkeys([e['kind']] + (['objective'] if e.get('objective') else []) + (['ambush'] if e.get('ambush') else [])))
        encounters.append(f"""<article class="encounter">
            <span class="encounter-kind">{esc(' · '.join(flags))}</span>
            <h3>{esc(e['name'])}</h3>
            <p>{esc(goal.get('brief') or e.get('intel') or '')}</p>
            <p class="muted">{esc(goal.get('title', ''))}{' · ' if goal.get('title') and maps else ''}{esc(maps)}</p>
            <div class="chip-row">{chips}</div>
          </article>""")
    return f"""
      <div class="page-heading">
        <div><p class="hub-eyebrow">Isometric roguelike tactics</p><h1>Hold the line<br>until dawn.</h1></div>
        <p>{esc(ctx['entity']['description'])}</p>
      </div>
      <figure class="hub-hero">
        <img src="{HERO}" alt="Battle capture of the last stand at Brannsted: the garrison's blue squads hold a palisaded steading by a river while the host's red-marked goblins and orcs press in from the north" width="1920" height="1080">
        <div class="hero-overlay">
          <div class="hero-kicker">{esc(camp['name'])} · {esc(camp['region'])}</div>
          <div class="hero-wordmark">MERIDIUS</div>
          <div class="hero-line">Hold Brannsted until the Margrave's riders come.</div>
        </div>
        <figcaption>Battle capture · The last stand at Brannsted</figcaption>
      </figure>
      <div class="hub-actions">
        <button type="button" class="primary-action" data-open="characters">Meet the units <span>→</span></button>
        <button type="button" class="secondary-action" data-open="abilities">Abilities <span>→</span></button>
        <button type="button" class="secondary-action" data-open="terrain">Terrain <span>→</span></button>
      </div>
      <div class="hub-stats">{stat_html}</div>
      <div class="editorial-grid">
        <section class="note-card">
          <p class="hub-eyebrow">The campaign</p>
          <h2>{esc(camp['name'])}</h2>
          <p>{esc(camp['blurb'])}</p>
          <p class="muted">{camp['stages']} stages · {camp['unitSlots']} squads in the company · {camp['commandPoints']} command points · tier {camp['tier']}, {esc(camp['tierName'].lower())}</p>
        </section>
        <section class="note-card">
          <p class="hub-eyebrow">In this guide</p>
          <h2>Everything the game knows, in one place.</h2>
          <ul class="guide-list">{guide}</ul>
        </section>
      </div>
      <div class="section-heading"><h2>Encounters</h2><span>{len(ctx['encounters'])} in the campaign · units listed include later waves and allies</span></div>
      <div class="encounter-grid">{''.join(encounters)}</div>"""


def unit_card(unit_id, ctx):
    u = ctx['units'][unit_id]
    faction = ctx['faction_of'][unit_id]
    path = f'unit-roster/img/{unit_id}.png'
    with Image.open(CARD / path) as image:
        w, h = image.size
    if unit_id in roster.EXTRA:
        stats = f'<p class="facts">{" · ".join(esc(x) for x in roster.EXTRA[unit_id]["facts"])}</p>'
    else:
        lines = [roster.facts(unit_id, u)[0]]
        if faction == 'garrison':
            lines.append(f'{u["recruitCost"]} silver, {u["commandCost"]} command')
        grow = per_level(u)
        if grow:
            lines.append(f'per level {grow}')
        if u.get('leader'):
            lines.append('leads the host as warchief')
        stats = stat_grid(u) + f'<p class="facts">{esc(" · ".join(lines))}</p>'
    source = roster.GARRISON_SOURCE.get(unit_id) or roster.ALLY_SOURCE.get(unit_id)
    rows = []
    for ability_id, promo in [(a, False) for a in u.get('abilities', [])] + ([(u['promotion'], True)] if u.get('promotion') else []):
        a = ctx['abilities'][ability_id]
        tag = ' <em>promotion</em>' if promo else ''
        rows.append(f"""<li>{icon(a['icon'])}<div>
              <button type="button" class="ability-name" data-goto="abilities:{ability_id}">{esc(a['name'])}</button>{tag}
              <span class="ability-meta">{esc(ability_numbers(a))}</span>
              <p>{esc(a['description'])}</p></div></li>""")
    abilities = f'<ul class="ability-list">{"".join(rows)}</ul>' if rows else '<p class="muted">No abilities of its own.</p>'
    anim = ctx['anim'][unit_id]
    links = [f'<button type="button" class="text-action" data-goto="animations:{unit_id}">{len(anim["labels"])} battle poses</button>'
             f' · {esc(", ".join(FACINGS[f] for f in anim["facings"]))}']
    for rig in ctx['rigs'].get(unit_id, []):
        links.append(rig_line(rig))
    seen = ctx['seen_in'].get(unit_id)
    if seen:
        links.append('Fights in: ' + esc(', '.join(seen)))
    if source:
        links.append(esc(source))
    return f"""<article class="unit-card" id="unit-{unit_id}" data-faction="{faction}">
          <figure class="unit-figure"><img src="{path}" alt="{esc(roster.ALT[unit_id])}" width="{w}" height="{h}" loading="lazy"></figure>
          <div class="unit-info">
            <span class="faction-tag" data-faction="{faction}">{esc(ctx['faction_name'][faction])}</span>
            <h3>{esc(u['name'])}</h3>
            <span class="role">{esc(u['role'])}</span>
            <p>{esc(u['blurb'])}</p>
            {stats}
            <ul class="unit-links">{''.join(f'<li>{x}</li>' for x in links)}</ul>
          </div>
          <div class="unit-abilities"><p class="hub-eyebrow">Abilities</p>{abilities}</div>
        </article>"""


def page_characters(ctx):
    filters = [('all', 'All', len(ctx['order']))] + [(f['id'], f['name'], len(ctx['members'][f['id']])) for f in FACTIONS]
    buttons = ''.join(f'<button type="button" data-filter="{fid}" aria-pressed="{str(fid == "all").lower()}">{esc(name)} <span>{n}</span></button>'
                      for fid, name, n in filters)
    cards = '\n'.join(unit_card(i, ctx) for i in ctx['order'])
    return f"""
      <div class="page-heading">
        <div><p class="hub-eyebrow">02 · Characters</p><h1>Every figure on the field.</h1></div>
        <p>The in-game battle frame of each unit, with its rules from the game data. Stats are per soldier at level 1. Ability names open the ability; poses open its animations.</p>
      </div>
      <div class="filter-row" role="group" aria-label="Show units of">{buttons}</div>
      <div class="unit-list">
{cards}
      </div>
      <p class="hub-footnote">The succubus and wolf scout rigs under Character rigs are prototypes without a unit entry, so they are not listed here.</p>"""


def page_factions(ctx):
    blocks = []
    for f in FACTIONS:
        ids = ctx['members'][f['id']]
        spec = next(p for p in roster.PAGES if p['title'] == f['roster'])
        groups = []
        for heading, group in spec['sections']:
            faces = ''.join(
                f'<button type="button" class="faction-unit" data-goto="characters:{i}">'
                f'<span class="faction-face" style="background-image:url(\'unit-roster/img/{i}.png\')"></span>'
                f'<b>{esc(ctx["units"][i]["name"])}</b><small>{esc(ctx["units"][i]["role"])}</small></button>'
                for i in group)
            groups.append(f'<h3>{esc(heading)}</h3><div class="faction-units">{faces}</div>')
        extra = ''
        if f['id'] == 'host':
            camp = ctx['campaign']
            extra = f'<p class="muted">{esc(camp["blurb"])}</p>'
        blocks.append(f"""<section class="faction-block" data-faction="{f['id']}">
          <div class="faction-head">
            <span class="faction-tag" data-faction="{f['id']}">{len(ids)} units</span>
            <h2>{esc(f['name'])}</h2>
            <p>{esc(spec['lead'].format(n=len(ids)))}</p>{extra}
          </div>
          {''.join(groups)}
        </section>""")
    return f"""
      <div class="page-heading">
        <div><p class="hub-eyebrow">03 · Factions</p><h1>Three sides of one war.</h1></div>
        <p>The garrison the player commands, the friends who fight beside it and the host it has to outlast. Pick a unit to open its card.</p>
      </div>
      {''.join(blocks)}"""


def page_abilities(ctx):
    users = {}
    for unit_id in ctx['order']:
        u = ctx['units'][unit_id]
        for a in u.get('abilities', []):
            users.setdefault(a, []).append((unit_id, ''))
        if u.get('promotion'):
            users.setdefault(u['promotion'], []).append((unit_id, 'promotion'))
    sections = []
    for kind, heading in KINDS:
        cards = []
        for ability_id, a in ctx['abilities'].items():
            if a['kind'] != kind:
                continue
            who = users.get(ability_id, [])
            chips = ''.join(chip(i, ctx['units'], note=n) for i, n in who) or '<span class="muted">No unit carries it yet.</span>'
            cards.append(f"""<article class="ability-card" id="ability-{ability_id}">
              <div class="ability-head">{icon(a['icon'])}<div><h3>{esc(a['name'])}</h3><span class="ability-meta">{esc(ability_numbers(a))}</span></div></div>
              <p>{esc(a['description'])}</p>
              <div class="chip-row">{chips}</div>
            </article>""")
        sections.append(f'<div class="section-heading"><h2>{heading}</h2><span>{len(cards)}</span></div><div class="ability-grid">{"".join(cards)}</div>')
    return f"""
      <div class="page-heading">
        <div><p class="hub-eyebrow">04 · Abilities</p><h1>What each squad can do.</h1></div>
        <p>All {len(ctx['abilities'])} abilities in the game data, with the in-game icon and the units that carry them. A promotion is learned when the squad is promoted.</p>
      </div>
      {''.join(sections)}"""


def anim_row(unit_id, ctx):
    u = ctx['units'][unit_id]
    a = ctx['anim'][unit_id]
    n = len(a['labels'])
    strip = f'hub/poses/{unit_id}.webp'
    if a['engine']:
        previews = [('At rest', [0], [1.0]), ('Loosing', [0, 1, 0], [0.9, 0.55, 0.25])]
        timing = 'Engines are drawn at rest and loosing.'
    else:
        stride = a['stride']
        step = round(stride / 4, 3)
        previews = [('Idle', [0, 1, 2, 1], [IDLE_FRAME] * 4), ('Walk', [3, 4, 5, 4], [step] * 4),
                    ('Strike', [0, 6, 7, 0], [0.7, 0.18, 0.26, 0.3])]
        timing = f'Idle frames hold {IDLE_FRAME} s; a stride takes {stride} s.'
    boxes = ''.join(
        f'<div class="pose-box"><div class="pose-preview" role="img" aria-label="{esc(u["name"])}, {label.lower()} preview" '
        f'style="background-image:url(\'{strip}\');background-size:{n * 100}% 100%;aspect-ratio:{a["cw"]}/{a["ch"]}" '
        f'data-n="{n}" data-seq="{",".join(map(str, seq))}" data-times="{",".join(map(str, times))}"></div>'
        f'<span>{label}</span></div>'
        for label, seq, times in previews)
    labels = ''.join(f'<span>{esc(x)}</span>' for x in a['labels'])
    rigs = ''.join(f'<li>{rig_line(r)}</li>' for r in ctx['rigs'].get(unit_id, []))
    faction = ctx['faction_of'][unit_id]
    return f"""<article class="anim-row" id="anim-{unit_id}" data-faction="{faction}">
          <div class="anim-head">
            <span class="faction-tag" data-faction="{faction}">{esc(ctx['faction_name'][faction])}</span>
            <h3><button type="button" class="ability-name" data-goto="characters:{unit_id}">{esc(u['name'])}</button></h3>
            <ul class="unit-links"><li>{a['soldiers']} drawn {'soldier' if a['soldiers'] == 1 else 'soldiers'} · {esc(', '.join(FACINGS[f] for f in a['facings']))}</li><li>{esc(timing)}</li>{rigs}</ul>
          </div>
          <div class="pose-previews">{boxes}</div>
          <figure class="pose-strip"><img src="{strip}" alt="{esc(u['name'])}: {n} battle poses of the first soldier, front view, left to right: {esc(', '.join(a['labels']).lower())}" width="{a['cw'] * n}" height="{a['ch']}" loading="lazy">
            <figcaption class="strip-labels" style="grid-template-columns:repeat({n},minmax(0,1fr))">{labels}</figcaption></figure>
        </article>"""


def page_animations(ctx):
    rig_cards = []
    for sub, rig in ctx['rig_groups'].items():
        unit = RIG_UNITS.get(sub)
        who = chip(unit, ctx['units']) if unit else '<span class="muted">Prototype or shared tooling, no unit entry</span>'
        rig_cards.append(f'<article class="rig-card"><h3>{esc(sub)}</h3><ul>{"".join(f"<li>{tab_link(t)}</li>" for t in rig)}</ul><div class="chip-row">{who}</div></article>')
    rows = '\n'.join(anim_row(i, ctx) for i in ctx['order'])
    return f"""
      <div class="page-heading">
        <div><p class="hub-eyebrow">05 · Animations</p><h1>How the squads move.</h1></div>
        <p>Battle figures are drawn poses. <code>soldier_anim.gd</code> plays them and adds the stride, bounce, breathing and lean from <code>_gait.json</code>, so in battle they move more than these previews.</p>
      </div>
      <div class="section-heading"><h2>3D rigs in progress</h2><span>click a tab to open it · Meridius in the rail, then Game guide, brings you back</span></div>
      <div class="rig-grid">{''.join(rig_cards)}</div>
      <div class="section-heading"><h2>Battle poses</h2><span>first soldier, front view · previews cycle the poses at game timing</span></div>
      <div class="anim-list">
{rows}
      </div>"""


def page_terrain(ctx):
    rows = []
    for t in ctx['terrain'].values():
        move = str(t['moveCost']) if t['passable'] else 'impassable'
        sight = {0: '—', 0.5: 'half', 0.75: 'three quarters'}.get(t['losBlock'], str(t['losBlock']))
        defense = f'{t["defenseMod"]:+d}'.replace('-', '−') if t['defenseMod'] else '—'
        cover = f'−{t["rangedCover"]}%' if t['rangedCover'] else '—'
        rows.append(f'<tr><td><span class="swatch" style="background:{t["color"]}"></span>{esc(t["name"])}</td>'
                    f'<td><code>{t["id"]}</code></td><td>{move}</td><td>{defense}</td><td>{cover}</td><td>{sight}</td></tr>')
    props = []
    for p in ctx['props'].values():
        if p['id'].endswith('_y') and p['id'][:-2] in ctx['props']:
            continue
        art = prop_image(p['sprite'])
        img = (f'<img src="{art[0]}" alt="{esc(p["name"])}: battlefield prop rendered in Blender" width="{art[1][0]}" height="{art[1][1]}" loading="lazy">'
               if art else '<span class="muted">No render</span>')
        sight = {2: 'blocks sight', 1: 'partly blocks sight', 0: 'open sight'}[p['los']]
        notes = [('blocks movement' if p['blocksMove'] else 'walkable'), sight]
        if p.get('cover'):
            notes.append(f'−{p["cover"]}% to shots past it')
        if p.get('defense'):
            notes.append(f'+{p["defense"]} defense')
        props.append(f'<article class="prop-card"><figure>{img}</figure><h3>{esc(p["name"])}</h3><p>{esc(" · ".join(notes))}</p></article>')
    maps = []
    for m in ctx['maps'].values():
        used = [e['name'] for e in ctx['encounters'] if m['id'] in e.get('maps', [])]
        maps.append(f"""<article class="note-card map-card"><p class="hub-eyebrow">{m['w']} × {m['h']} tiles · {esc(m['biome'])}</p>
          <h3>{esc(m['name'])}</h3><p>{esc(m['description'])}</p><p class="muted">{esc('Used by: ' + ', '.join(used)) if used else 'No encounter uses it.'}</p></article>""")
    return f"""
      <div class="page-heading">
        <div><p class="hub-eyebrow">06 · Terrain</p><h1>The ground decides the fight.</h1></div>
        <p>Ground types, obstacles and battlefields from <code>terrain.json</code> and <code>maps.json</code>. Height, which raises the line of sight, comes from each map.</p>
      </div>
      <div class="section-heading"><h2>Ground</h2><span>{len(ctx['terrain'])} kinds</span></div>
      <div class="table-scroll"><table class="terrain-table">
        <thead><tr><th>Ground</th><th>Id</th><th>Move cost</th><th>Defense</th><th>Ranged cover</th><th>Blocks sight</th></tr></thead>
        <tbody>{''.join(rows)}</tbody></table></div>
      <p class="hub-footnote">Ranged cover lowers the chance to hit a squad standing there. Sight blocking adds up along the line: two tiles of thicket, or one of woods plus anything leafy, hide what lies behind.</p>
      <div class="section-heading"><h2>Obstacles</h2><span>Blender renders used in battle</span></div>
      <div class="prop-grid">{''.join(props)}</div>
      <div class="section-heading"><h2>Battlefields</h2><span>{len(ctx['maps'])} maps</span></div>
      <div class="map-grid">{''.join(maps)}</div>"""


def page_more(ctx):
    groups = {}
    for step in ctx['entity']['steps']:
        if step['path'] == 'hub.html':
            continue
        key = step.get('group') or 'Meridius'
        groups.setdefault(key, {}).setdefault(step.get('subgroup') or '', []).append(step)
    blocks = []
    for name, subs in groups.items():
        items = []
        for sub, tabs in subs.items():
            inner = ''.join(f'<li>{tab_link(t)}</li>' for t in tabs)
            items.append(f'<li><b>{esc(sub)}</b><ul>{inner}</ul></li>' if sub else inner)
        count = sum(len(t) for t in subs.values())
        blocks.append(f'<section class="note-card"><p class="hub-eyebrow">{count} tabs</p><h2>{esc(name)}</h2><ul class="page-list">{"".join(items)}</ul></section>')
    return f"""
      <div class="page-heading">
        <div><p class="hub-eyebrow">07 · More pages</p><h1>The rest of the card.</h1></div>
        <p>Design notes, labs and rigs live in their own tabs. Click one to open it. To come back, pick Meridius in the rail left of the page, then Game guide in the bar above.</p>
      </div>
      <div class="pages-grid">{''.join(blocks)}</div>"""


def document(ctx, today):
    later = ' tabindex="-1"'
    nav = ''.join(
        f'<button type="button" role="tab" id="nav-{sid}" data-page="{sid}" aria-controls="{sid}" '
        f'aria-selected="{str(i == 0).lower()}"{"" if i == 0 else later}><span>{i + 1:02d}</span>{esc(name)}</button>'
        for i, (sid, name) in enumerate(SECTIONS))
    builders = [page_overview, page_characters, page_factions, page_abilities, page_animations, page_terrain, page_more]
    pages = ''.join(
        f'\n    <div class="hub-page" id="{sid}" role="tabpanel" aria-labelledby="nav-{sid}" tabindex="-1"{"" if i == 0 else " hidden"}>{build(ctx)}\n    </div>'
        for i, ((sid, _), build) in enumerate(zip(SECTIONS, builders)))
    return f"""<!doctype html>
<html lang="en" data-mak-report="document">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Meridius · Game guide</title>
  <link rel="stylesheet" href="../_shared/report.css">
  <link rel="stylesheet" href="../_shared/examples.css">
  <link rel="stylesheet" href="hub/hub.css">
  <script defer src="../_shared/report.js"></script>
  <script defer src="hub/hub.js"></script>
</head>
<body class="hub-document">
{icon_symbols(ctx['abilities'])}
<div class="hub-shell">
  <aside class="hub-rail">
    <a class="hub-brand" href="#overview"><span class="brand-mark" aria-hidden="true">M</span><span>MERIDIUS<small>Amberfeld against the host</small></span></a>
    <div class="rail-label">Game guide</div>
    <nav role="tablist" aria-label="Game guide sections" aria-orientation="vertical">{nav}</nav>
    <div class="rail-note"><span class="dot"></span>Built from the game data<br>{today}</div>
  </aside>
  <main class="hub-main">
    <div class="hub-topline"><span>Project / Meridius</span><span class="hub-pill">Godot build · game data</span></div>{pages}
    <p class="hub-footnote">Source: <code>projects/meridius/source/godot/data/</code>, <code>assets/sprites/anim/</code>, <code>assets/icons/</code> and <code>assets/sprites/blender/</code>.
      Rebuild with <code>python workspace/2026-10-20_meridius/hub/build.py</code>.</p>
  </main>
</div>
</body>
</html>
"""


def main():
    units = dict(load('units.json')['UNIT_TYPES'])
    units.update(roster.EXTRA)
    abilities = load('abilities.json')['ABILITIES']
    terrain = load('terrain.json')
    encounters = load('encounters.json')['ENCOUNTERS']
    gait = json.loads((ANIM / '_gait.json').read_text(encoding='utf-8'))
    registry = json.loads((REPO / 'workspace/workspace.json').read_text(encoding='utf-8'))
    entity = next(e for e in registry['entities'] if e['id'] == 'meridius')

    members, faction_of = {}, {}
    for f in FACTIONS:
        spec = next(p for p in roster.PAGES if p['title'] == f['roster'])
        members[f['id']] = [i for _, group in spec['sections'] for i in group]
        for i in members[f['id']]:
            faction_of[i] = f['id']
    order = [i for f in FACTIONS for i in members[f['id']]]
    missing = sorted(set(units) - set(order))
    if missing:
        raise SystemExit(f'units the roster does not place (add them to unit-roster/build.py): {", ".join(missing)}')

    anim = {}
    for unit_id in order:
        table = anim_table(unit_id)
        anim[unit_id] = {**pose_strip(unit_id, table), 'facings': table['facings'], 'soldiers': table['soldiers'],
                         'stride': gait_stride(unit_id, gait)}

    rig_groups, rigs = {}, {}
    for step in entity['steps']:
        if step.get('group') == 'Character rigs':
            rig_groups.setdefault(step.get('subgroup') or 'Other', []).append(step)
    for sub, tabs in rig_groups.items():
        if sub in RIG_UNITS:
            rigs.setdefault(RIG_UNITS[sub], []).append({'subgroup': sub, 'tabs': tabs})

    seen_in = {}
    for e in encounters:
        for i in encounter_units(e) + [row[0] for row in e.get('allies', [])]:
            seen_in.setdefault(i, []).append(e['name'])

    ctx = {
        'units': units, 'abilities': abilities, 'terrain': terrain['TERRAIN'], 'props': terrain['PROPS'],
        'encounters': encounters, 'maps': load('maps.json')['BATTLE_MAPS'], 'campaign': load('campaigns.json')['CAMPAIGNS'][0],
        'entity': entity, 'members': members, 'faction_of': faction_of, 'order': order,
        'faction_name': {f['id']: f['name'] for f in FACTIONS}, 'anim': anim, 'rig_groups': rig_groups, 'rigs': rigs,
        'seen_in': seen_in,
    }
    today = date.today().strftime('%d %B %Y').lstrip('0')
    (CARD / 'hub.html').write_text(document(ctx, today), encoding='utf-8', newline='\n')
    print(f'{len(order)} units, {len(abilities)} abilities, {len(ctx["terrain"])} ground types, {len(rig_groups)} rig groups')


if __name__ == '__main__':
    main()
