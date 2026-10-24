# Sourced by the spearman runners (Git Bash on Windows): bake_cape.sh, render_clips.sh, poke_cape.sh.
#
#   WORK      work dir from the runner's first argument: logs, the Blender profile, outputs
#   A / AW    art/spearman_3d as a POSIX / Windows path
#   B         Blender executable (BLENDER overrides)
#   BLENDER_USER_RESOURCES  defaults to WORK/blender_profile. Never run background Blender on
#             the user profile: -b --factory-startup there once deleted the extension wheels.
#
# watch_blender runs one background Blender and kills it when system commit headroom drops
# below MIN_COMMIT_MB (default 1200): other sessions share the RAM.
T=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
A=$(dirname "$T"); AW=$(cygpath -w "$A")
B=${BLENDER:-"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"}
MIN_COMMIT_MB=${MIN_COMMIT_MB:-1200}

[ -n "$1" ] || { echo "usage: $(basename "$0") <work dir> <clip> [<clip> ...]"; exit 2; }
mkdir -p "$1/logs"; WORK=$(cd "$1" && pwd); WW=$(cygpath -w "$WORK")
if [ -z "$BLENDER_USER_RESOURCES" ]; then
    mkdir -p "$WORK/blender_profile"; export BLENDER_USER_RESOURCES="$WW\\blender_profile"
fi

mem() {  # prints "<commit free MB> <private MB of Windows pid $1>"
    powershell -NoProfile -Command "\$o=Get-CimInstance Win32_OperatingSystem; \$p=Get-Process -Id $1 -EA SilentlyContinue; '{0} {1}' -f [int](\$o.FreeVirtualMemory/1KB), [int](\$p.PrivateMemorySize64/1MB)"
}

# watch_blender <log> <blender args...>: Blender's exit code, or 99 when the watchdog killed it.
# Sets PEAK (Blender private MB), LOW (lowest commit free MB) and SECS.
watch_blender() {
    local log=$1 bp wp free priv t0=$SECONDS; shift
    "$B" "$@" > "$log" 2>&1 &
    bp=$!
    sleep 1
    wp=$(cat /proc/$bp/winpid 2>/dev/null)
    PEAK=0; LOW=999999
    while kill -0 $bp 2>/dev/null; do
        read free priv < <(mem "$wp" | tr -d '\r')
        [ -n "$priv" ] && [ "$priv" -gt "$PEAK" ] && PEAK=$priv
        [ -n "$free" ] && [ "$free" -lt "$LOW" ] && LOW=$free
        if [ -n "$free" ] && [ "$free" -lt "$MIN_COMMIT_MB" ]; then
            taskkill //PID "$wp" //F > /dev/null 2>&1; kill $bp 2>/dev/null; wait $bp 2>/dev/null
            echo "ABORT: commit free ${free} MB < ${MIN_COMMIT_MB} (Blender peak ${PEAK} MB, log $log)"
            SECS=$((SECONDS - t0)); return 99
        fi
        sleep 3
    done
    wait $bp; local rc=$?
    SECS=$((SECONDS - t0)); return $rc
}

# Blender reads env paths as given, so CAPE_CACHE must be a Windows path.
cape_cache() { cygpath -w "${CAPE_CACHE:-$A/cape_cache}"; }
