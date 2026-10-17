"""Raw immutable Git objects. No commit command, index writes or ref movement."""
from pathlib import Path
import hashlib, io, json, os, re, stat, subprocess, tarfile, uuid, zlib
from isolated_git import GitSandbox, IsolationError, physical

sha=lambda b:hashlib.sha256(b).hexdigest()
def require(ok, why):
    if not ok: raise IsolationError(why)

def relative(value):
    require(isinstance(value,str) and value and '\\' not in value and ':' not in value and not value.startswith('/') and all(x not in ('','.','..') for x in value.split('/')) and not any(ord(c)<32 for c in value),'unsafe relative path')
    return value

def run(box,args,data=None):
    box.verify()
    allowed={'hash-object','cat-file','ls-tree','archive'}
    require(args and args[0] in allowed,'object-only Git operation required')
    proc=subprocess.run(['git','-c','core.autocrlf=false',*args],input=data,cwd=box.workspace,env=box.environment(),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    require(proc.returncode==0,'private Git failed: '+proc.stderr.decode('utf-8',errors='replace')[:300])
    return proc.stdout

def object_write(box,kind,data):
    require(kind in ('blob','tree','commit'),'unsupported Git object')
    # Pure object construction avoids one Git process per asset, while later
    # actual cat-file/archive validates Git's interpretation of these objects.
    physical(box.git_dir,box.root)
    marker=json.loads((box.git_dir/'codex-isolated.json').read_text())
    require(marker=={'workspace':str(box.workspace),'git_dir':str(box.git_dir),'index':str(box.index),'ceiling':str(box.root)},'private repository marker mismatch')
    require(all((box.git_dir/x).exists() for x in ('HEAD','refs','objects','config')),'incomplete private repository')
    raw=(kind+' '+str(len(data))+'\0').encode()+data
    oid=hashlib.sha1(raw).hexdigest();dst=physical(box.git_dir/'objects'/oid[:2]/oid[2:],box.root)
    dst.parent.mkdir(exist_ok=True)
    if dst.exists():require(zlib.decompress(dst.read_bytes())==raw,'existing private object differs')
    else:
        with dst.open('xb') as handle:handle.write(zlib.compress(raw))
    return oid

def custody(box):
    box.verify()
    result={}
    for name in ['HEAD','config','private.index','packed-refs','logs/HEAD']:
        p=box.git_dir/name
        result[name]=sha(p.read_bytes()) if p.is_file() else None
    for base in ['refs','logs/refs']:
        root=box.git_dir/base
        if root.exists():
            for p in root.rglob('*'):
                physical(p,box.root)
                if p.is_file():result[p.relative_to(box.git_dir).as_posix()]=sha(p.read_bytes())
    return result

def baseline_modes(box,parent):
    require(re.fullmatch('[0-9a-f]{40}',parent)!=None,'exact parent commit required')
    require(run(box,['cat-file','-t',parent]).strip()==b'commit','parent is not a commit')
    result={}
    for item in run(box,['ls-tree','-rz','--full-tree',parent]).split(b'\0'):
        if not item:continue
        meta,path=item.split(b'\t',1);mode,kind,oid=meta.split(b' ')
        result[path.decode('utf-8')]=mode.decode()
    return result

ROOT_FILES={'project.godot','export_presets.cfg','.gitattributes','.gitignore','icon.svg','icon.svg.import','icon.png','icon.png.import'}
TOPS={'scripts','scenes','assets','native','tests','tools','addons'}
BLOCK_DIRS={'.git','.godot','outputs','dev_art_sources','node_modules','__pycache__','.venv','venv','android-build','android-sdk','sdk','downloads','download','godot','godot-4.7','godot-4.6','engine','engines','build','dist'}
BLOCK_SUFFIXES={'.exe','.dll','.so','.aar','.apk','.aab','.zip','.7z','.rar','.pck','.jks','.keystore','.p12','.pfx','.pem','.key','.pyc','.obj','.lib','.pdb','.log'}
def selected(rel):
    relative(rel);parts=rel.split('/')
    if any(x.lower() in BLOCK_DIRS for x in parts):return False
    if any(x.lower().startswith(('godot-','android-sdk','local-tools')) for x in parts[:-1]):return False
    name=parts[-1].lower()
    if name=='.env' or name.startswith('.env.') or name in ('credentials','credentials.json','secrets.json','.git-credentials','local.properties','export_credentials.cfg'):return False
    if Path(name).suffix in BLOCK_SUFFIXES:return False
    return rel in ROOT_FILES or parts[0] in TOPS

def inventory(source):
    source=Path(source).absolute();physical(source,source)
    rows=[];seen=set()
    def visit(folder):
        physical(folder,source)
        for p in sorted(folder.iterdir(),key=lambda x:x.name):
            rel=p.relative_to(source).as_posix()
            # No traversal into excluded trees, including shared local junctions.
            if p.name.lower() in BLOCK_DIRS or (p.is_dir() and p.name.lower().startswith(('godot-','android-sdk','local-tools'))):continue
            if p.is_symlink() or getattr(p.lstat(),'st_file_attributes',0)&getattr(stat,'FILE_ATTRIBUTE_REPARSE_POINT',1024):raise IsolationError('reparse source entry refused: '+rel)
            if p.is_dir():
                if rel.split('/')[0] in TOPS:visit(p)
            elif p.is_file() and selected(rel):
                physical(p,source);relative(rel)
                require(rel.casefold() not in seen,'case-colliding source path');seen.add(rel.casefold())
                data=p.read_bytes()
                require(b'-----BEGIN PRIVATE KEY-----' not in data and b'-----BEGIN RSA PRIVATE KEY-----' not in data,'private key material refused: '+rel)
                if p.suffix.lower()=='.cfg':
                    require(not re.search(rb'(?mi)^\s*(?:keystore/(?:debug|release)_password|password)\s*=\s*"[^"\r\n]+"',data),'embedded export password refused: '+rel)
                rows.append({'path':rel,'bytes':len(data),'sha256':sha(data)})
    visit(source)
    return sorted(rows,key=lambda r:r['path'])

def build_from_rows(box,source,rows,parent,message='HardCore v115 immutable raw-byte build input'):
    before=custody(box);modes=baseline_modes(box,parent);source=Path(source).absolute()
    paths=set();entries={}
    for row in rows:
        rel=relative(row['path']);require(selected(rel),'excluded object input: '+rel)
        require(rel.casefold() not in paths,'duplicate source path');paths.add(rel.casefold())
        p=physical(source/rel,source);data=p.read_bytes()
        require(len(data)==row['bytes'] and sha(data)==row['sha256'],'input drift: '+rel)
        mode=modes.get(rel,'100644');require(mode in ('100644','100755'),'symlink/submodule mode refused')
        node=entries
        parts=rel.split('/')
        for part in parts[:-1]:
            require(not isinstance(node.get(part),tuple),'file/directory conflict')
            node=node.setdefault(part,{})
        require(parts[-1] not in node,'tree entry conflict')
        node[parts[-1]]=(mode,object_write(box,'blob',data))
    def tree(node):
        children=[]
        for name,value in node.items():
            mode,oid=('40000',tree(value)) if isinstance(value,dict) else value
            children.append((name.encode('utf-8')+(b'/' if mode=='40000' else b''),mode.encode()+b' '+name.encode()+b'\0'+bytes.fromhex(oid)))
        return object_write(box,'tree',b''.join(x[1] for x in sorted(children)))
    tree_id=tree(entries)
    require('\n' not in message and '\r' not in message,'single-line commit description required')
    # Fixed author/time makes identical parent+raw tree deterministic. No refs.
    commit=('tree '+tree_id+'\nparent '+parent+'\nauthor HardCore Build Snapshot <build@invalid.local> 0 +0000\ncommitter HardCore Build Snapshot <build@invalid.local> 0 +0000\n\n'+message+'\n').encode()
    commit_id=object_write(box,'commit',commit)
    require(inventory(source)==rows,'source roster/content drift during object build')
    require(custody(box)==before,'private HEAD/index/refs changed during object build')
    return {'commit':commit_id,'tree':tree_id,'parent':parent,'files':rows,'custody':before}

def verify_archive(box,commit,rows):
    box.verify();expected={r['path']:r for r in rows};actual={}
    # This is actual Git archive output, not a synthetic zip or tree decoder.
    proc=subprocess.Popen(['git','-c','core.autocrlf=false','archive','--format=tar',commit],cwd=box.workspace,env=box.environment(),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    try:
        with tarfile.open(fileobj=proc.stdout,mode='r|') as archive:
            for member in archive:
                if member.isdir():continue
                require(member.isfile(),'non-regular archive member')
                rel=relative(member.name);require(rel not in actual,'duplicate archive member')
                stream=archive.extractfile(member);digest=hashlib.sha256();size=0
                while True:
                    data=stream.read(1024*1024)
                    if not data:break
                    digest.update(data);size+=len(data)
                actual[rel]={'path':rel,'bytes':size,'sha256':digest.hexdigest()}
        error=proc.stderr.read();code=proc.wait()
        require(code==0,'archive failed: '+error.decode(errors='replace')[:200])
        require(actual==expected,'Git archive raw bytes/roster differ (attributes/export filters may be active)')
        return {'status':'PASS','files':len(actual),'commit':commit,'raw_bytes_verified':True}
    finally:
        if proc.poll() is None:proc.kill();proc.wait()

def loose_object(path):
    raw=zlib.decompress(path.read_bytes());header,data=raw.split(b'\0',1);kind,size=header.split(b' ')
    require(kind in (b'blob',b'tree',b'commit') and int(size)==len(data),'invalid loose object')
    oid=hashlib.sha1(raw).hexdigest()
    require(path.parent.name+path.name==oid,'loose object path/digest mismatch')
    return oid,raw

def publish_additive(box,destination,authorized_objects):
    """Only additive loose objects; caller must separately prove production gate."""
    box.verify();destination=Path(destination).absolute();authorized_objects=Path(authorized_objects).absolute()
    require(destination==authorized_objects,'wrong destination objects root')
    physical(destination,destination);require(destination.is_dir(),'existing destination object DB required')
    added=[]
    for fan in sorted((box.git_dir/'objects').iterdir()):
        if not re.fullmatch('[0-9a-f]{2}',fan.name):continue
        physical(fan,box.root)
        for src in sorted(fan.iterdir()):
            physical(src,box.root);oid,raw=loose_object(src)
            dst=physical(destination/oid[:2]/oid[2:],destination)
            dst.parent.mkdir(exist_ok=True)
            if dst.exists():
                require(loose_object(dst)[1]==raw,'existing destination object differs');continue
            tmp=dst.parent/('.codex-object-'+uuid.uuid4().hex)
            try:
                with tmp.open('xb') as handle:handle.write(src.read_bytes());handle.flush();os.fsync(handle.fileno())
                try:os.link(tmp,dst) # Atomic no-overwrite publication, even with a racing writer.
                except FileExistsError:require(loose_object(dst)[1]==raw,'racing destination object differs')
                require(loose_object(dst)[1]==raw,'published object verification failed');added.append(oid)
            finally:
                if tmp.exists():tmp.unlink()
    return {'status':'PASS','added_objects':added,'refs_or_index_written':False}
