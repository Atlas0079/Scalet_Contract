"""Correct Material 9.7.7's Chinese whole-word segmentation boundary."""
from pathlib import Path


def on_post_build(config):
    # Upstream query/segment/index.ts uses j < query.length, excluding the
    # complete query. For 中继防务 it can then select only the shorter 中 token.
    # The dependency is pinned; fail visibly if its worker implementation changes.
    old = 'for(let o=s+1;o<t.length;o++)t.slice(s,o)in e&&(n[s]=o-s)'
    new = 'for(let o=s+1;o<=t.length;o++)t.slice(s,o)in e&&(n[s]=o-s)'
    workers = list((Path(config['site_dir']) / 'assets/javascripts/workers').glob('search.*.min.js'))
    if len(workers) != 1:
        raise RuntimeError('Expected the pinned Material search worker.')
    worker = workers[0]
    source = worker.read_text(encoding='utf-8')
    if source.count(old) != 1:
        raise RuntimeError('Material search changed; review the Chinese segmentation fix.')
    worker.write_text(source.replace(old, new, 1), encoding='utf-8')
