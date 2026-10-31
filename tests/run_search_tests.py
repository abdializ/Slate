#!/usr/bin/env python3
"""Local fake search engine: tests never send typed text to a public service."""
import http.server,json,subprocess,sys,threading,time,urllib.parse
requests=[]
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  requests.append((self.path,dict(self.headers)))
  if self.path.startswith('/redirect'):
   self.send_response(302);self.send_header('Location','/unexpected');self.end_headers();return
  if self.path.startswith('/slow'):time.sleep(1.5)
  words=urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get('q',[''])[0]
  data=json.dumps([words,[words+' beans']]).encode()
  try:
   self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Set-Cookie','tracking=1');self.end_headers();self.wfile.write(data)
  except BrokenPipeError:pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
result=subprocess.run([sys.argv[1],f'http://127.0.0.1:{server.server_port}'],timeout=60)
server.shutdown()
assert result.returncode==0, result.returncode
assert len(requests)==3, requests
assert not any(path.startswith('/unexpected') for path,_ in requests)
assert not any('Cookie' in headers or 'Authorization' in headers or 'Referer' in headers for _,headers in requests)
print('PASS: requests suppressed, redirects blocked, no cookies or credentials')
