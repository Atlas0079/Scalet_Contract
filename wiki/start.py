#!/usr/bin/env python3
"""Install the local Wiki environment and preview or build its Markdown pages."""
import argparse
import hashlib
from pathlib import Path
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import venv
import webbrowser

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description='铁眼游戏设定 Wiki')
    parser.add_argument('mode', choices=('serve', 'build'), default='serve', nargs='?')
    parser.add_argument('--no-browser', action='store_true')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    env = ROOT / '.venv'
    python = env / ('Scripts/python.exe' if sys.platform == 'win32' else 'bin/python')
    if not python.exists():
        print('正在创建 Wiki 的 Python 环境……', flush=True)
        venv.EnvBuilder(with_pip=True).create(env)
    requirements = ROOT / 'requirements.txt'
    digest = hashlib.sha256(requirements.read_bytes()).hexdigest()
    stamp = env / 'wiki-requirements.sha256'
    if not stamp.exists() or stamp.read_text(encoding='utf-8') != digest:
        subprocess.run([str(python), '-m', 'pip', 'install', '-r', str(requirements)], check=True)
        stamp.write_text(digest, encoding='utf-8')
    command = [str(python), '-m', 'mkdocs', args.mode, '--strict']
    if args.mode == 'build':
        return subprocess.call(command, cwd=ROOT)
    url = 'http://127.0.0.1:{}/'.format(args.port)
    try:
        with socket.socket() as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('127.0.0.1', args.port))
    except OSError:
        print('端口 {} 已被使用。请关闭已有预览，或使用 --port 指定其他端口。'.format(args.port), file=sys.stderr)
        return 1
    command += ['--dev-addr', '127.0.0.1:{}'.format(args.port)]
    print('本地 Wiki：{}\n编辑 wiki/docs/ 内的 Markdown 即可更新。按 Ctrl+C 停止。'.format(url), flush=True)
    process = subprocess.Popen(command, cwd=ROOT)
    if not args.no_browser:
        def open_when_ready():
            for _ in range(150):
                if process.poll() is not None:
                    return
                try:
                    with urllib.request.urlopen(url, timeout=1) as response:
                        if response.status == 200:
                            webbrowser.open(url)
                            return
                except OSError:
                    time.sleep(0.2)
        threading.Thread(target=open_when_ready, daemon=True).start()
    try:
        return process.wait()
    except KeyboardInterrupt:
        process.terminate()
        process.wait()
        return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        print('Wiki 准备失败，请查看上面的依赖安装信息。', file=sys.stderr)
        raise SystemExit(error.returncode)
