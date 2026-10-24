#!/bin/bash
# Render clips in the four facings, one background Blender at a time (memory watchdog in
# blender_env.sh). Frames go to WORK/renders/<clip>_<facing>/; pack them with pack_sheets.py.
#
#   [CAPE_CACHE=<dir>] tools/render_clips.sh <work dir> <clip> [<clip> ...]
#
# The cape plays CAPE_CACHE (default art/spearman_3d/cape_cache). idle_rest renders every
# 2nd frame, the rest every frame. render_preview.py also reads CLIP_SCALE / CLIP_Z.
source "$(dirname "$0")/blender_env.sh"
shift
export CAPE_CACHE=$(cape_cache)

for c in "$@"; do
    step=1; [ "$c" = idle_rest ] && step=2
    log="$WORK/logs/render_$c.log"
    watch_blender "$log" -b "$AW\\spearman_rig.blend" --python "$AW\\tools\\render_preview.py" -- "$WW\\renders" clip "$c" $step se,sw,ne,nw
    [ $? -eq 99 ] && exit 1
    if grep -q PREVIEW_DONE "$log"; then
        echo "done $c ${SECS}s, Blender peak ${PEAK} MB"
    else
        echo "FAILED $c (see $log)"; tail -5 "$log"; exit 1
    fi
done
echo RENDER_DONE
