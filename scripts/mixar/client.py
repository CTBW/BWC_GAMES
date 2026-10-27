"""Exercise the official Mixar MCP transport without restarting an agent chat.

Use Mixar's bundled Python. Results and tool schemas stay in .cache, not Git.
Calls are never automatically retried; preserve returned call IDs after errors.
"""
import argparse
import asyncio
import base64
import json
from pathlib import Path
import sys
import uuid

from mcp import Client, StdioServerParameters, Implementation

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / '.cache/mixar/checks'


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--call')
    parser.add_argument('--arguments', type=Path, help='JSON file containing tool arguments')
    parser.add_argument('--schema', help='Print one tool schema instead of names')
    parser.add_argument('--session', help='Pin the scene UUID returned by mixar_scene_new')
    parser.add_argument('--request-id', help='Reuse a recorded UUID only for an explicitly requested retry')
    args = parser.parse_args()
    params = StdioServerParameters(
        command='powershell.exe',
        args=['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ROOT / 'scripts/mixar/mcp.ps1')]
             + (['--session', args.session] if args.session else []),
        cwd=ROOT,
    )
    CACHE.mkdir(parents=True, exist_ok=True)
    async with Client(params, client_info=Implementation(name='workspace-mixar-check', version='1')) as client:
        catalog = await client.list_tools()
        schema = catalog.model_dump(by_alias=True, exclude_none=True)
        (CACHE / 'tools.json').write_text(json.dumps(schema, indent=2), encoding='utf-8')
        if args.schema:
            print(json.dumps(next(t for t in schema['tools'] if t['name'] == args.schema), indent=2))
        elif not args.call:
            print(json.dumps({'transport': 'connected', 'tools': [t['name'] for t in schema['tools']]}, indent=2))
        else:
            arguments = json.loads(args.arguments.read_text(encoding='utf-8-sig')) if args.arguments else {}
            call_id = str(uuid.UUID(args.request_id)) if args.request_id else str(uuid.uuid4())
            receipt = CACHE / (call_id + '.json')
            receipt.write_text(json.dumps({'tool': args.call, 'call_id': call_id, 'state': 'submitted'}), encoding='utf-8')
            print(json.dumps({'call_id': call_id, 'receipt': str(receipt)}), flush=True)
            result = await client.call_tool(args.call, arguments, read_timeout_seconds=610,
                                           meta={'mixar/request-id': call_id})
            payload = result.model_dump(by_alias=True, exclude_none=True)
            for index, content in enumerate(payload.get('content', [])):
                if content.get('type') == 'image':
                    ext = '.png' if content.get('mimeType') == 'image/png' else '.jpg'
                    path = CACHE / (call_id + '-' + str(index) + ext)
                    path.write_bytes(base64.b64decode(content.pop('data')))
                    content['saved_image'] = str(path)
            receipt.write_text(json.dumps(payload, indent=2), encoding='utf-8')
            summary = payload.get('structuredContent')
            images = [c['saved_image'] for c in payload.get('content', []) if c.get('saved_image')]
            print(json.dumps({'isError': payload.get('isError', False), **summary, 'images': images} if summary else payload, indent=2))
            return 1 if payload.get('isError') else 0
    return 0


if __name__ == '__main__':
    sys.exit(asyncio.run(main()))
