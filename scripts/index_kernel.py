#!/usr/bin/env python3
"""Deterministic, offline syntax index; never compiles or executes the corpus."""
from pathlib import Path
from collections import defaultdict
import hashlib, json, time, re
from tree_sitter import Language, Parser
import tree_sitter_c

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / 'Corpus/linux'
PARSER = Parser(Language(tree_sitter_c.language()))

def walk(node):
    yield node
    for child in node.named_children:
        yield from walk(child)

def function_name(node):
    d = node.child_by_field_name('declarator')
    while d is not None:
        if d.type == 'identifier':
            return d.text.decode('latin1')
        d = d.child_by_field_name('declarator')
    return None

def parse_source(data, path, file_id, start_id):
    # Normalize known historical compiler annotations only in parser input.
    # Keep byte offsets/newlines identical; the original corpus is never rewritten.
    parse_data = re.sub(rb'\basmlinkage\b', lambda m: b' '*len(m[0]), data)
    parse_data = re.sub(rb'(?m)^([ \t]*static[ \t]+inline[ \t]+)?_syscall[0-9]+[^\n]*', lambda m: b' '*len(m[0]), parse_data)
    tree = PARSER.parse(parse_data)
    symbols, calls = [], []
    errors = sum(n.type == 'ERROR' or n.is_missing for n in walk(tree.root_node))
    for node in walk(tree.root_node):
        if node.type != 'function_definition':
            continue
        name = function_name(node)
        if not name:
            continue
        body = node.child_by_field_name('body')
        if body is None:
            continue
        descendants = list(walk(body))
        sid = start_id + len(symbols)
        branches = sum(n.type in {'if_statement','for_statement','while_statement','do_statement','case_statement','conditional_expression'} for n in descendants)
        symbols.append(dict(id=sid, file=file_id, name=name,
            line=node.start_point.row+1, endLine=node.end_point.row+1,
            branches=branches, isStatic=any(c.type=='storage_class_specifier' and c.text==b'static' for c in node.children)))
        for n in descendants:
            if n.type != 'call_expression':
                continue
            f = n.child_by_field_name('function')
            if f is not None and f.type == 'identifier':
                calls.append(dict(source=sid, file=file_id, name=f.text.decode('latin1'), line=n.start_point.row+1))
    return symbols, calls, errors

def squarify(items, rect):
    """Bruls-style worst-aspect squarification. Area remains proportional to bytes."""
    x,y,w,h = rect
    total = sum(v for _,v in items)
    todo = [(key, value*w*h/total) for key,value in sorted(items,key=lambda i:(-i[1],str(i[0])))] if total else []
    result = {}
    def worst(row, side):
        if not row: return float('inf')
        s = sum(v for _,v in row)
        return max(side*side*max(v for _,v in row)/(s*s), s*s/(side*side*min(v for _,v in row)))
    while todo:
        row = [todo.pop(0)]
        side = min(w,h)
        while todo and worst(row+[todo[0]],side) <= worst(row,side):
            row.append(todo.pop(0))
        s=sum(v for _,v in row)
        if w>=h:
            width=s/h; off=y
            for key,a in row:
                height=a/width; result[key]=[x,off,width,height]; off+=height
            x+=width; w=max(1e-9,w-width)
        else:
            height=s/w; off=x
            for key,a in row:
                width=a/height; result[key]=[off,y,width,height]; off+=width
            y+=height; h=max(1e-9,h-height)
    return result

GROUPS = {
 'drivers':('Device drivers','E9B971','The kernel meets the physical world.'),
 'fs':('Filesystems','69C8B1','One interface. Many ways to store a world.'),
 'net':('Networking','7EABEE','Follow a packet from socket to wire.'),
 'kernel':('Kernel core','BAA0DE','Time, tasks, signals, and the rules of execution.'),
 'mm':('Memory','E38D89','Turn a finite machine into a virtual address space.'),
 'include':('Interfaces','99C8D4','The shared vocabulary of the operating system.'),
 'boot':('Boot','E6D298','From a boot sector to a running kernel.'),
 'init':('Initialization','E6D298','The first C code that brings Linux to life.'),
 'lib':('Library','A9BCEC','Small primitives used everywhere.'),
 'tools':('Build tools','D3A59C','Assembling a bootable system.'),
 'zBoot':('Compressed boot','DAC19F','Unpack the kernel before it can run.'),
 'root':('Project files','8296B0','Build configuration, history, and the license.'),
}

def main():
    started=time.perf_counter()
    paths=sorted(p for p in CORPUS.rglob('*') if p.is_file())
    total_bytes=sum(p.stat().st_size for p in paths)
    assert total_bytes<20_000_000, f'Corpus exceeds 20 MB: {total_bytes}'
    files, symbols, raw_calls = [], [], []
    for path in paths:
        data=path.read_bytes(); rel=path.relative_to(CORPUS).as_posix(); fid=len(files)
        group=rel.split('/')[0] if '/' in rel else 'root'
        ss,cc,errors=parse_source(data,rel,fid,len(symbols)) if path.suffix in {'.c','.h'} else ([],[],0)
        symbols+=ss; raw_calls+=cc
        files.append(dict(id=fid,path=rel,name=path.name,group=group,bytes=len(data),
            lines=data.count(b'\n') + int(bool(data) and not data.endswith(b'\n')),functions=len(ss),branches=sum(s['branches'] for s in ss),
            parseErrors=errors,sha256=hashlib.sha256(data).hexdigest(),rect=[0,0,0,0]))
    byname=defaultdict(list)
    for s in symbols: byname[s['name']].append(s)
    edges=[]; unresolved=0
    for c in raw_calls:
        defs=byname[c['name']]
        local=[d for d in defs if d['file']==c['file']]
        candidates=local or [d for d in defs if not d['isStatic']]
        if len(candidates)==1:
            edges.append(dict(source=c['source'],target=candidates[0]['id'],line=c['line']))
        else: unresolved+=1
    # Recursively preserve the source directory hierarchy.
    directories=[]
    def layout(subset,prefix,rect,depth):
        partitions=defaultdict(list)
        for f in subset:
            rest=f['path'][len(prefix):]; key=rest.split('/')[0]
            partitions[key].append(f)
        boxes=squarify([(k,sum(max(1,f['bytes']) for f in v)) for k,v in partitions.items()],rect)
        for key, members in partitions.items():
            box=boxes[key]
            if len(members)==1 and members[0]['path']==prefix+key:
                members[0]['rect']=[round(v,6) for v in box]
            else:
                path=prefix+key; directories.append(dict(path=path,group=members[0]['group'],depth=depth,rect=box))
                x,y,w,h=box; pad=min(.52,w*.025,h*.025)
                layout(members,path+'/',[x+pad,y+pad,w-2*pad,h-2*pad],depth+1)
    layout(files,'',[0,0,120,94],0)
    groups=[]
    for name in sorted(set(f['group'] for f in files)):
        title,color,desc=GROUPS.get(name,(name,'8296B0','Source files.'))
        ff=[f for f in files if f['group']==name]
        groups.append(dict(id=name,title=title,color=color,description=desc,bytes=sum(f['bytes'] for f in ff),files=len(ff)))
    groups.sort(key=lambda g:-g['bytes'])
    index=dict(schema=1,title='Linux 1.0',release='14 March 1994',sourceURL='https://www.kernel.org/pub/linux/kernel/v1.0/linux-1.0.tar.xz',
        archiveSHA256=hashlib.sha256((ROOT/'downloads/linux-1.0.tar.xz').read_bytes()).hexdigest(),
        totalBytes=total_bytes,totalLines=sum(f['lines'] for f in files),
        unresolvedCalls=unresolved,parseErrors=sum(f['parseErrors'] for f in files),
        files=files,symbols=symbols,edges=edges,groups=groups,directories=directories)
    (ROOT/'Corpus/index.json').write_text(json.dumps(index,separators=(',',':')))
    receipt=dict(bytes=total_bytes,files=len(files),functions=len(symbols),namedCallSites=len(edges),
        unresolvedCallSites=unresolved,syntaxErrorNodes=index['parseErrors'],indexSeconds=time.perf_counter()-started,
        indexBytes=(ROOT/'Corpus/index.json').stat().st_size)
    (ROOT/'evidence/index-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps(receipt,indent=2))

if __name__=='__main__':main()
