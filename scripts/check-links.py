#!/usr/bin/env python3
"""Check local Markdown file links without crawling external sites."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

root = Path(__file__).resolve().parents[1]
errors = []
documents = sorted(root.glob('*.md')) + sorted((root / 'docs').rglob('*.md'))
documents += [root / 'llms.txt', root / 'llms-full.txt']
for document in documents:
    for target in re.findall(r'\]\(([^)]+)\)', document.read_text()):
        url = urlsplit(target)
        if url.scheme or url.netloc or not url.path:
            continue
        if not (document.parent / unquote(url.path)).exists():
            errors.append(f'{document.relative_to(root)}: missing link target {target}')
if errors:
    sys.exit('\n'.join(errors))
print('Local Markdown file links passed.')
