"""Exact private Git custody; never discover a repository through parent folders."""
from pathlib import Path
import hashlib, json, os, re, stat, subprocess

HEAD="45170d0eaf4d2c642d4a03de392f64fa2b1e25bf"
OBJECTS=Path("C:/Users/Administrator/Documents/HardCore/.git/objects")
class IsolationError(RuntimeError): pass

def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def physical(path,root):
 path=Path(os.path.abspath(path));root=Path(os.path.abspath(root))
 if path!=root and root not in path.parents:raise IsolationError("path escapes authorized output")
 for part in [path,*path.parents]:
  if part.exists() and (part.is_symlink() or getattr(part.lstat(),"st_file_attributes",0)&getattr(stat,"FILE_ATTRIBUTE_REPARSE_POINT",1024)):raise IsolationError("reparse path refused:"+str(part))
  if part==root:break
 return path

def input_rows(root,rows):
 root=Path(root)
 for row in rows:
  rel=row.get("path",row.get("relative_path",""))
  if not isinstance(rel,str) or not rel or "\\" in rel or Path(rel).is_absolute() or ".." in Path(rel).parts or ":" in rel:raise IsolationError("unsafe manifest path")
  p=physical(root/rel,root)
  expected=row.get("sha256",row.get("after",""))
  if not re.fullmatch("[0-9a-f]{64}",expected) or not p.is_file() or digest(p)!=expected:raise IsolationError("input drift:"+rel)
 return True

class GitSandbox:
 def __init__(self,workspace,authorized_root):
  self.root=physical(authorized_root,authorized_root)
  self.workspace=physical(workspace,self.root)
  if self.workspace==self.root:raise IsolationError("project must be a child of authorized output")
  self.git_dir=self.workspace/".git";self.index=self.git_dir/"private.index"
 def environment(self):
  env=os.environ.copy()
  # Ambient discovery and object/index overrides must not redirect any command.
  for key in list(env):
   if key.startswith("GIT_"):env.pop(key)
  env.update(GIT_DIR=str(self.git_dir),GIT_WORK_TREE=str(self.workspace),GIT_INDEX_FILE=str(self.index),GIT_CEILING_DIRECTORIES=str(self.root),GIT_OPTIONAL_LOCKS="0",GIT_CONFIG_NOSYSTEM="1",GIT_CONFIG_GLOBAL=os.devnull)
  return env
 def _run(self,args):
  return subprocess.run(["git",*args],cwd=self.workspace,env=self.environment(),check=True,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout.strip()
 def verify(self):
  physical(self.workspace,self.root);physical(self.git_dir,self.root);physical(self.index,self.root)
  for name in ["HEAD","config","objects","refs","codex-isolated.json"]:
   p=self.git_dir/name
   if not p.exists():raise IsolationError("incomplete private repository:"+name)
   physical(p,self.root)
  marker=json.loads((self.git_dir/"codex-isolated.json").read_text())
  if marker!={"workspace":str(self.workspace),"git_dir":str(self.git_dir),"index":str(self.index),"ceiling":str(self.root)}:raise IsolationError("private repository marker mismatch")
  values={"workspace":self._run(["rev-parse","--show-toplevel"]),"git_dir":self._run(["rev-parse","--absolute-git-dir"]),"index":self._run(["rev-parse","--git-path","index"])}
  for key,expected in [("workspace",self.workspace),("git_dir",self.git_dir),("index",self.index)]:
   if Path(values[key]).resolve()!=expected.resolve():raise IsolationError("Git resolved wrong "+key)
  return values
 def initialize(self,head=HEAD,objects=OBJECTS):
  if self.git_dir.exists():raise IsolationError("refuse to initialize existing repository")
  if not re.fullmatch("[0-9a-f]{40}",head) or not Path(objects).is_dir():raise IsolationError("exact existing commit/objects required")
  self.workspace.mkdir(parents=True,exist_ok=True)
  for name in ["objects/info","refs"]:(self.git_dir/name).mkdir(parents=True,exist_ok=True)
  (self.git_dir/"config").write_text("[core]\nrepositoryformatversion = 0\nbare = false\nfilemode = false\nlogallrefupdates = false\n",encoding="utf-8")
  (self.git_dir/"HEAD").write_bytes((head+"\n").encode())
  (self.git_dir/"objects/info/alternates").write_bytes((str(Path(objects).resolve()).replace("\\","/")+"\n").encode())
  marker={"workspace":str(self.workspace),"git_dir":str(self.git_dir),"index":str(self.index),"ceiling":str(self.root)}
  (self.git_dir/"codex-isolated.json").write_text(json.dumps(marker),encoding="utf-8")
  self.verify()
  self.mutate(["read-tree",head])
  return self.verify()
 def mutate(self,args):
  self.verify() # No mutation can precede complete local files and exact path proof.
  if not args or args[0] not in ["read-tree","hash-object","update-index"]:raise IsolationError("unapproved private Git mutation")
  return self._run(args)
