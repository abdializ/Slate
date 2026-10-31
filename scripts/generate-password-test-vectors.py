from pathlib import Path
import re,hashlib,json
root=Path(__file__).resolve().parents[1]
p=(root/'platform/macos/passwords/ApplePasswordsProtocol.swift').read_text()
s=p.split('static let group = SRPNumber(hex: """',1)[1].split('""")!',1)[0]
N=int(re.sub(r'[^A-F0-9]','',s),16);g=5;size=384
H=lambda *p:hashlib.sha256(b''.join(p)).digest()
bn=lambda n:n.to_bytes(max(1,(n.bit_length()+7)//8),'big')
pad=lambda n:n.to_bytes(size,'big')
randomTid=bytearray(range(16));randomTid[0]|=128
import base64
tid=base64.b64encode(randomTid).decode();code='123456';salt=bytes(range(1,17));a=int.from_bytes(bytes(range(32)),'big');b=int.from_bytes(bytes(range(32,64)),'big')
k=int.from_bytes(H(bn(N),pad(g)),'big');x=int.from_bytes(H(salt,H((tid+':'+code).encode())),'big');v=pow(g,x,N)
A=pow(g,a,N);B=(k*v+pow(g,b,N))%N;u=int.from_bytes(H(pad(A),pad(B)),'big')
S=pow((B-k*pow(g,x,N))%N,a+u*x,N);server=pow((A*pow(v,u,N))%N,b,N);assert S==server
K=H(bn(S));M=H(bytes(x^y for x,y in zip(H(bn(N)),H(pad(g)))),H(tid.encode()),salt,bn(A),bn(B),K);HAMK=H(bn(A),M,K)
f={'tid':tid,'publicKey':bn(A).hex(),'serverKey':bn(B).hex(),'salt':salt.hex(),'proof':M.hex(),'serverProof':HAMK.hex(),'aesKey':K[:16].hex()}
(root/'tests/fixtures/apple_passwords_vectors.json').write_text(json.dumps(f,indent=2)+'\n')
print('Independent Python SRP server/client calculation agrees.')
