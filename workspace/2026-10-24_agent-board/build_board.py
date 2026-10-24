"""Builds the live data for the Agent board card.

Reads the Claude Code session registry (~/.claude/sessions), the tail of each
live session's transcript, recent background jobs (~/.claude/jobs) and the
repository's Git state, then writes live/board-data.js, which index.html loads
every 20 seconds. A coordinator may add live/notes.json to name tasks, sort a
quiet session into a lane and record the commit lock; a note only applies while
the session has been quiet since the note was written.

The live/ folder holds prompt excerpts and stays out of Git.

    python build_board.py              write the data once
    python build_board.py --install    run it every minute (Windows Task Scheduler)
                                       and add an "Agent Board" desktop shortcut
    python build_board.py --uninstall  remove the task and the shortcut
"""
import ctypes, glob, json, os, re, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
LIVE = HERE / 'live'
CLAUDE = Path(os.environ.get('CLAUDE_CONFIG_DIR') or Path.home() / '.claude')
TASK = 'Mr Mak Agent Board'
SHORTCUT = Path(os.environ.get('USERPROFILE', str(Path.home()))) / 'Desktop' / 'Agent Board.lnk'
TAIL = 3 * 1024 * 1024
QUIET_AFTER = 3 * 3600
JOB_WINDOW = 12 * 3600


def now():
    return datetime.now(timezone.utc)


def parse_time(value):
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value / 1000, timezone.utc)
    try:
        return datetime.fromisoformat(str(value).replace('Z', '+00:00'))
    except ValueError:
        return None


def iso(moment):
    return moment.isoformat().replace('+00:00', 'Z') if moment else None


def clean(text, limit):
    text = re.sub(r'<[^>]{1,80}>', ' ', text or '')
    text = re.sub(r'(^|\s)#{1,6}(?=\s)|\*\*|__|`', ' ', text)
    text = ' '.join(text.split())
    return text if len(text) <= limit else text[:limit - 1].rstrip() + '…'


def alive(pid):
    if os.name != 'nt':
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    kernel = ctypes.windll.kernel32
    handle = kernel.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return False
    code = ctypes.c_ulong()
    ok = kernel.GetExitCodeProcess(handle, ctypes.byref(code))
    kernel.CloseHandle(handle)
    return bool(ok) and code.value == 259  # STILL_ACTIVE


def transcript_path(session_id, cache):
    known = cache.get('paths', {}).get(session_id)
    if known and os.path.exists(known):
        return known
    found = glob.glob(str(CLAUDE / 'projects' / '*' / f'{session_id}.jsonl'))
    if found:
        cache.setdefault('paths', {})[session_id] = found[0]
        return found[0]
    return None


def user_text(content):
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return None
    if any(isinstance(b, dict) and b.get('type') == 'tool_result' for b in content):
        return None
    return ' '.join(b.get('text', '') for b in content if isinstance(b, dict) and b.get('type') == 'text')


def scan(path, size, previous):
    """The latest prompt, reply, title and activity from the transcript's tail."""
    result = {'title': previous.get('title'), 'custom': previous.get('custom', False), 'prompt': None,
              'reply': None, 'last': None, 'pendingTool': None, 'ending': None}
    with open(path, 'rb') as handle:
        if size > TAIL:
            handle.seek(size - TAIL)
            handle.readline()
        lines = handle.read().decode('utf-8', 'replace').splitlines()
    for line in lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        kind = entry.get('type')
        if kind == 'custom-title' and entry.get('customTitle'):
            result['title'], result['custom'] = entry['customTitle'], True
        elif kind == 'ai-title' and entry.get('aiTitle') and not result['custom']:
            result['title'] = entry['aiTitle']
        if kind not in ('user', 'assistant') or entry.get('isSidechain'):
            continue
        stamp = entry.get('timestamp')
        result['last'] = stamp or result['last']
        message = entry.get('message') or {}
        if kind == 'user':
            if entry.get('isMeta') or entry.get('isCompactSummary'):
                continue
            text = user_text(message.get('content'))
            if text is None:
                result['pendingTool'], result['ending'] = None, 'tool result'
                continue
            text = text.strip()
            if not text or text.startswith('<'):
                continue
            result['prompt'] = {'at': stamp, 'text': clean(text, 240)}
            result['ending'] = 'prompt'
        else:
            for block in message.get('content') or []:
                if not isinstance(block, dict):
                    continue
                if block.get('type') == 'text' and block.get('text', '').strip():
                    result['reply'] = {'at': stamp, 'text': clean(block['text'], 320)}
                    result['ending'] = 'reply'
                elif block.get('type') == 'tool_use':
                    result['pendingTool'], result['ending'] = block.get('name'), 'tool call'
    if result['prompt'] is None:
        result['prompt'] = previous.get('prompt')
    if result['reply'] is None:
        result['reply'] = previous.get('reply')
    return result


def short_name(name, kind):
    match = re.match(r'^.+-([0-9a-z]{2})$', name or '')
    return match.group(1) if match else 'bg' if kind == 'bg' else (name or '?')[:4]


def note_applies(note, last):
    asof, last = parse_time(note.get('asOf')), parse_time(last)
    return bool(asof and last and (last - asof).total_seconds() <= 60)


def sessions(cache, notes, moment):
    cards, seen = [], set()
    for file in glob.glob(str(CLAUDE / 'sessions' / '*.json')):
        try:
            info = json.loads(Path(file).read_text(encoding='utf-8'))
        except (OSError, ValueError):
            continue
        if info.get('spare') or not info.get('sessionId') or not alive(int(info.get('pid', 0))):
            continue
        sid = info['sessionId']
        seen.add(sid)
        path = transcript_path(sid, cache)
        scanned = {}
        if path:
            stat = os.stat(path)
            stored = cache.setdefault('scans', {}).get(sid, {})
            if stored.get('size') == stat.st_size and stored.get('mtime') == stat.st_mtime:
                scanned = stored['scan']
            else:
                scanned = scan(path, stat.st_size, stored.get('scan', {}))
                cache['scans'][sid] = {'size': stat.st_size, 'mtime': stat.st_mtime, 'scan': scanned}
        name = info.get('name') or sid[:8]
        note = notes.get('agents', {}).get(name) or notes.get('agents', {}).get(sid[:8]) or {}
        status = info.get('status') or 'idle'
        last = scanned.get('last')
        since = parse_time(info.get('statusUpdatedAt')) if status == 'busy' else parse_time(last) or parse_time(info.get('statusUpdatedAt'))
        if status == 'busy':
            lane = 'working'
        elif status != 'idle':
            lane = 'waiting'
        elif scanned.get('ending') in ('prompt', 'tool call', 'tool result'):
            lane = 'stopped'
        elif since and (moment - since).total_seconds() > QUIET_AFTER:
            lane = 'done'
        else:
            lane = 'waiting'
        current = note_applies(note, last)
        if current and status == 'idle' and note.get('lane') in ('waiting', 'stopped', 'done'):
            lane = note['lane']
        cards.append({
            'id': sid[:8], 'name': name, 'short': short_name(name, info.get('kind')), 'kind': info.get('kind', 'interactive'),
            'title': note.get('task') or scanned.get('title') or name, 'lane': lane, 'status': status,
            'since': iso(since), 'started': iso(parse_time(info.get('startedAt'))),
            'note': note.get('note') if current or note.get('sticky') else None,
            'prompt': scanned.get('prompt'), 'reply': scanned.get('reply'), 'last': last,
            'stoppedAt': scanned.get('ending') if lane == 'stopped' else None,
            'pendingTool': scanned.get('pendingTool') if lane == 'stopped' else None,
            'folder': None if str(info.get('cwd', '')).lower().startswith(str(REPO).lower()) else info.get('cwd'),
        })
    for file in glob.glob(str(CLAUDE / 'jobs' / '*' / 'state.json')):
        try:
            job = json.loads(Path(file).read_text(encoding='utf-8'))
        except (OSError, ValueError):
            continue
        updated = parse_time(job.get('updatedAt'))
        if job.get('sessionId') in seen or not updated or (moment - updated).total_seconds() > JOB_WINDOW:
            continue
        if job.get('state') not in ('done', 'failed', 'error', 'stopped'):
            continue
        cards.append({
            'id': Path(file).parent.name, 'name': job.get('name') or Path(file).parent.name, 'short': 'bg',
            'kind': 'job', 'title': job.get('name') or 'Background job', 'lane': 'done', 'status': job.get('state'),
            'since': iso(updated), 'note': clean(str(job.get('detail') or ''), 240) or None,
            'prompt': {'at': job.get('createdAt'), 'text': clean(job.get('intent') or '', 240)} if job.get('intent') else None,
            'reply': None, 'last': iso(updated), 'stoppedAt': None, 'pendingTool': None, 'folder': None,
        })
    order = {'working': 0, 'stopped': 1, 'waiting': 2, 'done': 3}
    cards.sort(key=lambda c: (order.get(c['lane'], 9), c['since'] or ''))
    return cards


def git(*args):
    env = {**os.environ, 'GIT_OPTIONAL_LOCKS': '0'}
    run = subprocess.run(['git', '--no-optional-locks', '-C', str(REPO), *args], capture_output=True, text=True,
                         encoding='utf-8', errors='replace', timeout=30, env=env,
                         creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    return run.stdout.strip() if run.returncode == 0 else None


def git_state():
    head = git('log', '-1', '--format=%h%x09%s')
    if head is None:
        return None
    branch = git('rev-parse', '--abbrev-ref', 'HEAD')
    counts = git('rev-list', '--left-right', '--count', '@{u}...HEAD') or ''
    behind, ahead = (int(x) for x in counts.split()) if len(counts.split()) == 2 else (None, None)
    unpushed = git('log', '@{u}..HEAD', '--format=%h%x09%s', '-8') or ''
    status = git('status', '--porcelain=v1') or ''
    sha, subject = head.split('\t', 1)
    return {'branch': branch, 'head': sha, 'subject': subject, 'ahead': ahead, 'behind': behind,
            'uncommitted': len(status.splitlines()),
            'unpushed': [dict(zip(('sha', 'subject'), line.split('\t', 1))) for line in unpushed.splitlines() if '\t' in line]}


def read_json(path, default):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return default


def build():
    LIVE.mkdir(exist_ok=True)
    moment = now()
    cache = read_json(LIVE / 'cache.json', {})
    notes = read_json(LIVE / 'notes.json', {})
    data = {'generatedAt': iso(moment), 'cards': sessions(cache, notes, moment), 'git': git_state(),
            'lock': notes.get('lock'), 'coordinator': notes.get('coordinator')}
    for name, text in (('cache.json', json.dumps(cache)),
                       ('board.json', json.dumps(data, ensure_ascii=False, indent=1)),
                       ('board-data.js', 'window.AGENT_BOARD = ' + json.dumps(data, ensure_ascii=False) + ';\n')):
        temp = LIVE / f'.{name}.tmp'
        temp.write_text(text, encoding='utf-8')
        os.replace(temp, LIVE / name)
    return data


def browser():
    for base in (os.environ.get('ProgramFiles(x86)'), os.environ.get('ProgramFiles'), os.environ.get('LOCALAPPDATA')):
        for exe in (r'Microsoft\Edge\Application\msedge.exe', r'Google\Chrome\Application\chrome.exe'):
            if base and os.path.exists(os.path.join(base, exe)):
                return os.path.join(base, exe)
    return None


def install():
    pythonw = Path(sys.executable).with_name('pythonw.exe')
    runner = pythonw if pythonw.exists() else Path(sys.executable)
    command = f'"{runner}" "{Path(__file__).resolve()}"'
    subprocess.run(['schtasks', '/Create', '/F', '/TN', TASK, '/SC', 'MINUTE', '/MO', '1', '/TR', command], check=True)
    # schtasks cannot set these: keep running on battery, catch up after sleep, never pile up.
    settings = ('$t=Get-ScheduledTask -TaskName $env:TASK;$s=$t.Settings;$s.DisallowStartIfOnBatteries=$false;'
                '$s.StopIfGoingOnBatteries=$false;$s.StartWhenAvailable=$true;$s.ExecutionTimeLimit="PT2M";'
                '$s.MultipleInstances="IgnoreNew";Set-ScheduledTask -InputObject $t|Out-Null')
    subprocess.run(['powershell', '-NoProfile', '-Command', settings], check=True, env={**os.environ, 'TASK': TASK})
    exe = browser()
    if exe:
        page = (HERE / 'index.html').as_uri()
        script = ('$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:LNK);$s.TargetPath=$env:EXE;'
                  '$s.Arguments=$env:ARGS;$s.Description="Live board of the agents working in Mr. Mak";$s.Save()')
        env = {**os.environ, 'LNK': str(SHORTCUT), 'EXE': exe, 'ARGS': f'--app="{page}" --window-size=1500,960'}
        subprocess.run(['powershell', '-NoProfile', '-Command', script], check=True, env=env)
    build()
    print(f'Installed: task "{TASK}" every minute; shortcut {SHORTCUT if exe else "(no Edge or Chrome found)"}')


def uninstall():
    subprocess.run(['schtasks', '/Delete', '/F', '/TN', TASK])
    SHORTCUT.unlink(missing_ok=True)
    print('Removed the task and the shortcut.')


if __name__ == '__main__':
    if '--install' in sys.argv:
        install()
    elif '--uninstall' in sys.argv:
        uninstall()
    else:
        # pythonw has no console, so a failure is kept where the board can point to it.
        try:
            build()
            (LIVE / 'last-error.txt').unlink(missing_ok=True)
        except Exception:
            import traceback
            LIVE.mkdir(exist_ok=True)
            (LIVE / 'last-error.txt').write_text(f'{iso(now())}\n{traceback.format_exc()}', encoding='utf-8')
            raise
