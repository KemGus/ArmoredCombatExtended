import sys, numpy as np
from srcmodel import load
def islands(me):
    pos = me['pos']; tris = me['tris']
    key = np.round(pos, 3)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    par = np.arange(weld.max()+1)
    def f(a):
        while par[a]!=a:
            par[a]=par[par[a]]; a=par[a]
        return a
    for t in weld[tris]:
        a,b,c = f(t[0]),f(t[1]),f(t[2])
        par[b]=a; par[f(c)]=a
    root = np.array([f(w) for w in weld])
    labs = {r:i for i,r in enumerate(np.unique(root))}
    return np.array([labs[r] for r in root])
if __name__=='__main__':
    m = load(sys.argv[1])
    for bp in m['bodyparts'][:1] if len(sys.argv)<3 else m['bodyparts']:
        for md in bp['models']:
            for me in md['meshes']:
                lab = islands(me)
                print(bp['name'], md['name'], me['material'], 'islands', lab.max()+1)
                rows=[]
                for i in range(lab.max()+1):
                    p = me['pos'][lab==i]
                    r = np.hypot(p[:,1], p[:,2])
                    rows.append((p[:,0].min(), p[:,0].max(), r.min(), r.max(), len(p), p[:,1].mean(), p[:,2].mean(), set(map(tuple,me['bone'][lab==i][:, :1].tolist()))))
                for row in sorted(rows):
                    print('   x %8.2f..%8.2f  r %6.2f..%6.2f  n %5d  cy %6.2f cz %6.2f bones %s' % (*row[:4], row[4], row[5], row[6], row[7]))
