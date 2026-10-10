#!/usr/bin/env python3
"""Check local Markdown file links without crawling external sites."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

root = Path(__file__).resolve().parents[1]
errors = []
for document in root.glob('*.md'):
    for target in re.findall(r'\]\(([^)]+)\)', document.read_text()):
        url = urlsplit(target)
        if url.scheme or url.netloc or not url.path:
            continue
        if not (document.parent / unquote(url.path)).exists():
            errors.append(f'{document.name}: missing link target {target}')
if errors:
    sys.exit('\n'.join(errors))
print('Local Markdown file links passed.')
