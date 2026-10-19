import json, math, random, struct
from pathlib import Path
P=Path(__file__).parent
rng=random.Random(20051017)
layers=[]; roads=[]; lifts=[]
heights=[0,-3.5,-7.8,-11.4]
for level,(span,count) in enumerate(zip([12,10,7.8,5.5],[rng.randint(23,28),rng.randint(17,22),rng.randint(12,16),rng.randint(7,10)])):
    nodes=[]
    center=(rng.uniform(-.6,.6),rng.uniform(-.6,.6))
    clusters=[(rng.uniform(-span*.27,span*.27),rng.uniform(-span*.27,span*.27)) for _ in range(3)]
    for attempt in range(12000):
        if len(nodes)==count:break
        if rng.random()<.58:
            cx,cz=rng.choice(clusters);x=rng.gauss(cx,span*.19);z=rng.gauss(cz,span*.19)
        else:x=rng.uniform(-span*.5,span*.5);z=rng.uniform(-span*.5,span*.5)
        if abs(x)>span*.52 or abs(z)>span*.52:continue
        sx=rng.uniform(.56,.98);sz=rng.uniform(.56,.98)
        if any(((x-q['p'][0])/(sx+q['s'][0]+.24))**2+((z-q['p'][2])/(sz+q['s'][2]+.24))**2<1 for q in nodes):continue
        nodes.append({'p':[round(x,3),round(heights[level]+rng.uniform(-.17,.17),3),round(z,3)],'s':[round(sx,3),round(rng.uniform(.4,.68),3),round(sz,3)]})
    for q in nodes:q['p'][0]=round(q['p'][0]+center[0],3);q['p'][2]=round(q['p'][2]+center[1],3)
    layers.append(nodes)
    # A connected local network, followed by irregular short loops.
    edges=set();reached={0}
    dist=lambda i,j:sum((nodes[i]['p'][k]-nodes[j]['p'][k])**2 for k in [0,2])
    while len(reached)<len(nodes):
        _,a,b=min((dist(a,b)*rng.uniform(.95,1.05),a,b) for a in reached for b in range(len(nodes)) if b not in reached)
        edges.add(tuple(sorted((a,b))));reached.add(b)
    def cross(a,b,c,d):
        def orient(p,q,r):return (q[0]-p[0])*(r[2]-p[2])-(q[2]-p[2])*(r[0]-p[0])
        return orient(a,b,c)*orient(a,b,d)<0 and orient(c,d,a)*orient(c,d,b)<0
    candidates=sorted((dist(a,b),a,b) for a in range(len(nodes)) for b in range(a+1,len(nodes)) if (a,b) not in edges)
    extra=0
    for ds,a,b in candidates:
        if extra>=round(len(nodes)*.55):break
        if ds>span*span*.22 or rng.random()<.28:continue
        if any(cross(nodes[a]['p'],nodes[b]['p'],nodes[c]['p'],nodes[d]['p']) for c,d in edges if len({a,b,c,d})==4):continue
        edges.add((a,b));extra+=1
    for a,b in sorted(edges):roads.append({'a':nodes[a]['p'],'b':nodes[b]['p'],'l':level})
for level in range(len(layers)-1):
    low=layers[level+1]; chosen=rng.sample(low,min(len(low),rng.choice([1,2,2,3,4])))
    for node in chosen:
        b=node['p']; a=[round(b[0]+rng.uniform(-.5,.5),3),heights[level],round(b[2]+rng.uniform(-.5,.5),3)]
        near=min(layers[level],key=lambda q:(q['p'][0]-a[0])**2+(q['p'][2]-a[2])**2)
        b=[a[0],b[1],a[2]]
        roads.append({'a':a,'b':near['p'],'l':level})
        roads.append({'a':b,'b':node['p'],'l':level+1})
        lifts.append({'a':a,'b':b,'l':level})
data={'layers':layers,'roads':roads,'lifts':lifts,'heights':heights}
(P/'scene.json').write_text(json.dumps(data),encoding='utf-8')
template=(P/'template.html').read_text(encoding='utf-8')
(P/'alibe-city.html').write_text(template.replace('__SCENE__',json.dumps(data)),encoding='utf-8')
# Self-contained glTF binary, with actual sphere and tube meshes.
doc={'asset':{'version':'2.0','generator':'Alibe spatial concept study'},'scene':0,'scenes':[{'nodes':[]}],'nodes':[],'meshes':[],'materials':[{'name':name,'pbrMetallicRoughness':{'baseColorFactor':color,'metallicFactor':.15,'roughnessFactor':.7}} for name,color in [('Bubbles',[.27,.49,.58,1]),('Roads',[.47,.56,.59,1]),('Elevators',[.95,.52,.18,1])]],'buffers':[],'bufferViews':[],'accessors':[]}
blob=bytearray()
def accessor(values,kind,ctype):
    while len(blob)%4:blob.append(0)
    offset=len(blob);flat=[v for row in values for v in row] if kind=='VEC3' else values
    blob.extend(struct.pack('<'+('f' if ctype==5126 else 'I')*len(flat),*flat))
    vi=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(blob)-offset})
    ac={'bufferView':vi,'componentType':ctype,'count':len(values),'type':kind}
    if kind=='VEC3':ac.update(min=[min(v[i] for v in values) for i in range(3)],max=[max(v[i] for v in values) for i in range(3)])
    doc['accessors'].append(ac);return len(doc['accessors'])-1
def mesh(name,verts,inds,mat):
    pi=accessor(verts,'VEC3',5126);ii=accessor(inds,'SCALAR',5125)
    mi=len(doc['meshes']);doc['meshes'].append({'name':name,'primitives':[{'attributes':{'POSITION':pi},'indices':ii,'material':mat}]})
    ni=len(doc['nodes']);doc['nodes'].append({'name':name,'mesh':mi});doc['scenes'][0]['nodes'].append(ni)
def sphere(p,s):
    v=[];ind=[];nx=16;ny=10
    for i in range(ny+1):
        t=math.pi*i/ny
        for j in range(nx+1):
            f=2*math.pi*j/nx
            v.append([p[0]-s[0]*math.cos(f)*math.sin(t),p[1]+s[1]*math.cos(t),p[2]+s[2]*math.sin(f)*math.sin(t)])
    for i in range(ny):
        for j in range(nx):
            a=i*(nx+1)+j;b=a+nx+1;ind.extend([a,b,a+1,b,b+1,a+1])
    return v,ind
def tube(a,b,r):
    d=[b[i]-a[i] for i in range(3)];length=math.sqrt(sum(x*x for x in d))
    if length<.001:return [],[]
    d=[x/length for x in d];ref=[0,1,0] if abs(d[1])<.9 else [1,0,0]
    u=[d[1]*ref[2]-d[2]*ref[1],d[2]*ref[0]-d[0]*ref[2],d[0]*ref[1]-d[1]*ref[0]];norm=math.sqrt(sum(x*x for x in u));u=[x/norm for x in u]
    w=[d[1]*u[2]-d[2]*u[1],d[2]*u[0]-d[0]*u[2],d[0]*u[1]-d[1]*u[0]]
    v=[[p[k]+r*(math.cos(j*math.tau/8)*u[k]+math.sin(j*math.tau/8)*w[k]) for k in range(3)] for p in [a,b] for j in range(8)]
    ind=[]
    for j in range(8):q=(j+1)%8;ind.extend([j,q,j+8,q,q+8,j+8])
    return v,ind
for l,nodes in enumerate(layers):
    for j,n in enumerate(nodes):v,i=sphere(n['p'],n['s']);mesh(f'L{l+1}_Bubble_{j+1:02}',v,i,0)
for kind,items,r,mat in [('Road',roads,.085,1),('Lift',lifts,.13,2)]:
    for j,e in enumerate(items):
        v,i=tube(e['a'],e['b'],r)
        if v:mesh(f'{kind}_{j+1:03}',v,i,mat)
doc['buffers']=[{'byteLength':len(blob)}]
js=json.dumps(doc,separators=(',',':')).encode();js+=b' ' *((-len(js))%4);blob+=b'\0'*((-len(blob))%4)
out=struct.pack('<III',0x46546c67,2,12+8+len(js)+8+len(blob))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(blob),0x004e4942)+blob
(P/'alibe-city.glb').write_bytes(out)
print(f'{sum(map(len,layers))} bubbles, {len(roads)} roads, {len(lifts)} lifts; GLB {len(out)} bytes')
