from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import webbrowser

parser=argparse.ArgumentParser(description='阿利贝泡内地图生成器与查看器')
parser.add_argument('--port',type=int,default=8770)
parser.add_argument('--no-open',action='store_true')
args=parser.parse_args()
directory=Path(__file__).resolve().parent
handler=partial(SimpleHTTPRequestHandler,directory=str(directory))
with ThreadingHTTPServer(('127.0.0.1',args.port),handler) as server:
    url=f'http://127.0.0.1:{args.port}/'
    print(f'阿利贝地图查看器：{url}\n按 Ctrl+C 停止服务。',flush=True)
    if not args.no_open:webbrowser.open(url)
    try:server.serve_forever()
    except KeyboardInterrupt:pass
