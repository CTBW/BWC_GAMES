import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import {readFile,writeFile} from 'node:fs/promises';
const dir=new URL('../../../../workspace/2026-10-20_meridius/sovereign-kiss/',import.meta.url);
const content=renderToStaticMarkup(React.createElement(ReactMarkdown,{remarkPlugins:[remarkGfm]},await readFile(new URL('blender-handoff-fog.md',dir),'utf8')));
await writeFile(new URL('blender-handoff.html',dir),`<!doctype html><html lang="en" data-mak-report="document"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Sovereign Kiss — Pink fog Blender handoff</title><link rel="stylesheet" href="../../_shared/report.css"><script defer src="../../_shared/report.js"></script><style>table{margin-bottom:28px}td{border-bottom:1px solid var(--mak-border)}.container{max-width:1200px!important}a{margin-right:18px}</style></head><body><main class="container"><nav><a href="../sovereign-kiss.html">Back to the visual schematic</a><a href="blender-handoff-fog.md" download>Download Markdown source</a></nav>${content}</main></body></html>`);
console.log('Built blender-handoff.html from editable Markdown.');
