"""Render encyclopedic article furniture from portable Markdown metadata."""
from html import escape
from pathlib import Path
import posixpath
import re
import shutil


def relative(page, target):
    folder = page.url.rstrip('/') if page.url.endswith('/') else posixpath.dirname(page.url)
    return posixpath.relpath(target, folder or '.')


def on_page_content(html, page, config, files):
    title = re.search(r'<h1\b[^>]*>.*?</h1>', html, re.S)
    heading = title.group(0) if title else '<h1>{}</h1>'.format(escape(page.title))
    body = html[:title.start()] + html[title.end():] if title else html
    src = relative(page, '_sources/' + page.file.src_uri + '.txt')
    en = page.meta.get('lang') == 'en'
    tabs = ('Article tools', 'Article', 'Read', 'View source') if en else ('词条工具', '条目', '阅读', '查看源文件')
    header = '<div class="wiki-article-heading">' + heading + '</div>'
    header += '<nav class="wiki-article-tabs" aria-label="{}"><span class="wiki-tab-active">{}</span><div><span class="wiki-tab-active">{}</span><a href="{}">{}</a></div></nav>'.format(tabs[0], tabs[1], tabs[2], escape(src, quote=True), tabs[3])
    if page.meta.get('description'):
        header += '<p class="wiki-description">{}</p>'.format(escape(str(page.meta['description'])))
    rows = page.meta.get('infobox', [])
    box = ''
    if rows:
        box = '<aside class="wiki-infobox" aria-label="{}"><table><caption>{}</caption><tbody>'.format('Article facts' if en else '词条资料', escape(page.title))
        for row in rows:
            value = escape(str(row['value']))
            if row.get('link'):
                href = relative(page, row['link'])
                if row['link'].endswith('/') and not href.endswith('/'): href += '/'
                value = '<a href="{}">{}</a>'.format(escape(href, quote=True), value)
            box += '<tr><th scope="row">{}</th><td>{}</td></tr>'.format(escape(str(row['label'])), value)
        box += '</tbody></table></aside>'
    category = escape(str(page.meta.get('category', 'Article' if en else '词条')))
    footer = '<div class="wiki-category-box" data-search-exclude>{}：{}</div>'.format('Category' if en else '分类', category)
    return header + '<div class="wiki-article-body">' + box + body + '</div>' + footer


def on_post_build(config):
    # Real source-view links; the reader receives the same Markdown used to build.
    source = Path(config['docs_dir'])
    target = Path(config['site_dir']) / '_sources'
    for path in source.rglob('*.md'):
        destination = target / (str(path.relative_to(source)) + '.txt')
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)
