#!/bin/bash
# Count body points showing through the cape (cape_poke.py), per clip, in the four facings.
#
#   [CAPE_CACHE=<dir>] [STEP=4] tools/poke_cape.sh <work dir> <clip> [<clip> ...]
#
# Prints "POKEALL <clip> total <n> worst (<n>, (<frame>, <yaw>))". 2026-10-24, STEP 4:
# worst view 2-3 points, 9 in walk f5 at yaw -45 (his left forearm past the cape's edge).
source "$(dirname "$0")/blender_env.sh"
shift
export CAPE_CACHE=$(cape_cache) STEP=${STEP:-4}

for c in "$@"; do
    log="$WORK/logs/poke_$c.log"
    export CLIP=$c
    watch_blender "$log" -b "$AW\\spearman_rig.blend" --python "$AW\\tools\\cape_poke.py"
    [ $? -eq 99 ] && exit 1
    grep POKEALL "$log" || { echo "FAILED $c (see $log)"; tail -5 "$log"; exit 1; }
done
