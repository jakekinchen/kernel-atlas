import unittest, sys, json, hashlib, math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from index_kernel import parse_source, squarify

class IndexTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.d=json.loads((ROOT/'Corpus/index.json').read_text())
    def test_complete_unchanged_corpus_under_budget(self):
        files=self.d['files']
        paths=[p for p in (ROOT/'Corpus/linux').rglob('*') if p.is_file()]
        self.assertEqual(len(paths),len(files))
        self.assertEqual(sum(p.stat().st_size for p in paths),self.d['totalBytes'])
        self.assertLess(self.d['totalBytes'],20_000_000)
        for f in files:
            p=ROOT/'Corpus/linux'/f['path']
            self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),f['sha256'])
        self.assertEqual(hashlib.sha256((ROOT/'downloads/linux-1.0.tar.xz').read_bytes()).hexdigest(),self.d['archiveSHA256'])
    def test_edges_are_source_backed_and_in_scope(self):
        syms=self.d['symbols'];files=self.d['files']
        source={f['id']:(ROOT/'Corpus/linux'/f['path']).read_bytes().decode('latin1').split('\n') for f in files}
        for edge in self.d['edges']:
            a,b=syms[edge['source']],syms[edge['target']]
            self.assertLessEqual(a['line'],edge['line']);self.assertLessEqual(edge['line'],a['endLine'])
            self.assertIn(b['name'],source[a['file']][edge['line']-1])
            if b['isStatic']:self.assertEqual(a['file'],b['file'])
    def test_parser_ignores_comments_strings_and_declarations(self):
        data=b'''int helper(int x) { return x; }
static int real(void) {
// pretend();
char *s = "fake()";
if (helper(1)) return helper(2);
return 0;
}
int declared(int x);
'''
        ss,cc,errors=parse_source(data,'fixture.c',0,0)
        self.assertEqual([s['name'] for s in ss],['helper','real'])
        self.assertEqual([c['name'] for c in cc],['helper','helper'])
        self.assertTrue(ss[1]['isStatic']);self.assertEqual(ss[1]['branches'],1)
        self.assertEqual(errors,0)
    def test_layout_preserves_area_and_non_overlap(self):
        boxes=squarify([(str(i),i+1) for i in range(60)],[0,0,120,94])
        self.assertAlmostEqual(sum(w*h for x,y,w,h in boxes.values()),120*94,places=6)
        items=list(boxes.items())
        for key,(x,y,w,h) in items:
            self.assertAlmostEqual(w*h/(120*94),(int(key)+1)/sum(range(1,61)),places=6)
            for other,(a,b,c,d) in items:
                if key==other:continue
                self.assertLessEqual(min(x+w,a+c)-max(x,a),1e-8) if min(y+h,b+d)-max(y,b)>1e-8 else None
        for f in self.d['files']:
            x,y,w,h=f['rect'];self.assertGreater(w,0);self.assertGreater(h,0)
            self.assertGreaterEqual(x,0);self.assertGreaterEqual(y,0)
            self.assertLessEqual(x+w,120.00001);self.assertLessEqual(y+h,94.00001)
    def test_historical_entrypoints_exist(self):
        pairs={(self.d['files'][s['file']]['path'],s['name']) for s in self.d['symbols']}
        for pair in [('init/main.c','start_kernel'),('kernel/sched.c','schedule'),('mm/memory.c','do_page_fault'),('net/inet/ip.c','ip_rcv'),('net/inet/tcp.c','tcp_rcv')]:self.assertIn(pair,pairs)

if __name__=='__main__':unittest.main()
