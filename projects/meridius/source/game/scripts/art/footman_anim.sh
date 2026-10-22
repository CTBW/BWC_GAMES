#!/usr/bin/env sh
# Rebuild the footman animations from the generated keyframe edits.
# Run from projects/meridius/source/game. Inputs are the gitignored working
# files under art/raw/higgsfield/footman_squad (poses/, keyframes/, figs/);
# the jobs behind them are in art/receipts/footman_squad_higgsfield.json.
set -e
PY=.venv-art/Scripts/python.exe
A="$PY scripts/art/anim.py"
# The edits are drawn without shadows: keep grey hair and steel that the shadow key would drop.
cut() { $A cut "$@" --no-shadows; }
R=art/raw/higgsfield/footman_squad
F=$R/frames
L=$R/layouts
O=$R/anim_out
PAL=$R/palette.png

rm -rf "$F" "$O"
mkdir -p "$L"
for v in sw se ne nw; do $A legacy $R/figs $v $L/grid_$v.json; done
$A palette $R/figs $PAL

# Edits of the 3 x 2 idle grids. Split lines part blades that touch a neighbour.
cut $R/poses/atk_sw_raw.png $L/grid_sw.json $F atk_sw \
  --split 159,136,159,151 --split 159,151,166,160 --split 166,160,182,167 \
  --split 338,126,338,153 --split 338,153,346,161 --split 346,161,362,168 \n  --split 164,422,164,442 --split 164,442,178,452
for p in atk_se:se atk_ne:ne atk_nw:nw; do cut $R/poses/${p%%:*}_raw.png $L/grid_${p##*:}.json $F ${p%%:*}; done
for v in sw se ne nw; do
  for s in a b; do cut $R/keyframes/walk_${v}_${s}_raw.png $L/grid_$v.json $F walk_${v}_$s; done
done
cut $R/keyframes/windup_sw_raw.png $L/grid_sw.json $F windup_sw --split 157,348,157,374 --split 157,374,165,374
cut $R/keyframes/windup_ne_v2_raw.png $L/grid_ne.json $F windup_ne
cut $R/keyframes/follow_se_raw.png $L/grid_se.json $F follow_se
cut $R/keyframes/follow_nw_v2_raw.png $L/grid_nw.json $F follow_nw
cut $R/keyframes/kneel_sw_raw.png $L/grid_sw.json $F kneel_sw --split 341,206,354,180
cut $R/keyframes/kneel_ne_raw.png $L/grid_ne.json $F kneel_ne

# Chained edits of the kneel frames, laid out 3 x 2 on a 3:2 sheet with room to fall.
$A sheet $F $R/anim/collapse_in_sw.png kneel_sw --grid 3x2 --cell 900x900 --base 240
$A sheet $F $R/anim/collapse_in_ne.png kneel_ne --grid 3x2 --cell 900x900 --base 150
cut $R/keyframes/collapse_sw_raw.png $R/anim/collapse_in_sw.json $F collapse_sw --keep-y
cut $R/keyframes/collapse_ne_raw.png $R/anim/collapse_in_ne.json $F slump_ne

play() { $A play $R/figs $F $O "$@" --palette $PAL; }
for v in sw se ne nw; do
  $A breathe $R/figs $F $v
  play idle_$v idle_${v}_0,idle_${v}_1,idle_${v}_2,idle_${v}_1 --ms 320
  play walk_$v walk_${v}_a,$v,walk_${v}_b,$v --ms 170
done
play strike_sw sw,windup_sw,atk_sw,atk_sw,sw --ms 220,200,110,260,200
play strike_ne ne,windup_ne,atk_ne,atk_ne,ne --ms 220,200,110,260,200
play strike_se se,atk_se,follow_se,follow_se,se --ms 220,200,110,260,200
play strike_nw nw,atk_nw,follow_nw,follow_nw,nw --ms 220,200,110,260,200
play death_sw sw,kneel_sw,collapse_sw --ms 160,320,1200
play death_ne ne,kneel_ne,slump_ne --ms 160,320,1200

# Game keys: _f SW, _fs mirrored true SE, _b NE, _bs mirrored true NW (battleScene poseKey).
rm -rf art/sprites/footman_anim
$A export $O art/sprites/footman_anim \
  idle_sw=footman_idle_f idle_se=footman_idle_fs:m idle_ne=footman_idle_b idle_nw=footman_idle_bs:m \
  walk_sw=footman_walk_f walk_se=footman_walk_fs:m walk_ne=footman_walk_b walk_nw=footman_walk_bs:m \
  strike_sw=footman_strike_f strike_se=footman_strike_fs:m strike_ne=footman_strike_b strike_nw=footman_strike_bs:m \
  death_sw=footman_death_f death_ne=footman_death_b
