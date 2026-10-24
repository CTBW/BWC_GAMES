#!/bin/bash
# Bake the cloth cape, one background Blender per clip (memory watchdog in blender_env.sh).
#
#   tools/bake_cape.sh <work dir> <clip> [<clip> ...]
#
# Simulates on a fresh copy of spearman_rig.blend (WORK/rig_sim.blend) into WORK/cape_cache.
# Check the CAPE_SIM "lowest" values (>= 0.01 m) and compare with pc2_check.py before
# copying the .pc2 files into art/spearman_3d/cape_cache/.
source "$(dirname "$0")/blender_env.sh"
shift
mkdir -p "$WORK/cape_cache"
cp "$A/spearman_rig.blend" "$WORK/rig_sim.blend"

for c in "$@"; do
    log="$WORK/logs/bake_$c.log"
    watch_blender "$log" -b "$WW\\rig_sim.blend" --python "$AW\\tools\\cape_cloth.py" -- sim "$WW\\cape_cache" "$c"
    [ $? -eq 99 ] && exit 1
    line=$(grep CAPE_SIM "$log")
    if [ -n "$line" ]; then
        echo "$line | ${SECS}s, Blender peak ${PEAK} MB, commit low ${LOW} MB"
    else
        echo "FAILED $c (see $log)"; tail -5 "$log"; exit 1
    fi
done
echo BAKE_DONE
