exec(open('spread.py').read().split("for tf,f in")[0])
from numba import njit
@njit
def single(o,h,l,c,a,i,d,SP,tm):
    n=len(c); e=o[i+1]; ext=l[i] if d>0 else h[i]
    for j in range(i-2,i+1): ext=min(ext,l[j]) if d>0 else max(ext,h[j])
    rk=min(max((e-ext)*d+0.1*a[i],0.7*a[i]),2.5*a[i]); st=e-d*rk; t=e+d*tm*rk
    for j in range(i+1,min(n,i+1500)):
        if (d>0 and l[j]<=st) or (d<0 and h[j]>=st): return -1.0-SP/rk
        if (d>0 and h[j]>=t) or (d<0 and l[j]<=t): return tm-SP/rk
    return np.nan
T=[]
for tf,f in [('15m','gold20/xau20_15m.csv'),('1h','gold20/xau20_1h.csv')]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    m=((key.market=='gold20')&(key.tf==tf)).values&(s.p.values>=Q70)
    for i,di in zip(key.i.values[m],key.dir.values[m]):
        if t.iloc[i].year<2021 or i+2>=len(c): continue
        row={'time':t.iloc[i],'tf':tf}
        for t2 in [2,3,4,5]:
            g,rk=sim(o,h,l,c,a,int(i),int(di),0.0,0.25,1.0,float(t2)); row[f'p{t2}']=g/rk; row['rk']=rk
        for tm in [1,1.5,2,3]:
            row[f's{tm}']=single(o,h,l,c,a,int(i),int(di),0.25,float(tm))
        T.append(row)
T=pd.DataFrame(T).dropna().sort_values('time')
cols=[('p2','نص عند 1R، النص التاني عند 2R'),('p3','نص عند 1R، النص التاني عند 3R'),('p4','نص عند 1R، النص التاني عند 4R'),('p5','نص عند 1R، النص التاني عند 5R'),('s1','هدف واحد 1R'),('s1.5','هدف واحد 1.5R'),('s2','هدف واحد 2R'),('s3','هدف واحد 3R')]
for tf in ['15m','1h','كلهم']:
    X=T if tf=='كلهم' else T[T.tf==tf]
    print(f'== King ⭐+ ذهب {tf} (2021-2025، {len(X)} صفقة، بعد السبريد)')
    for c_,lab in cols:
        x=X[c_]
        # حساب 100$ بمخاطرة 1%
        bal=100.0; peak=100; dd=0
        for r_,rk in zip(X[c_].values,X.rk.values):
            lot=max(0.01,np.floor(bal*0.01/(rk*100)/0.01)*0.01); bal+=lot*100*r_*rk; peak=max(peak,bal); dd=max(dd,(peak-bal)/peak)
        print(f'   {lab:32s} {x.mean():+.3f}R/صفقة | لم يضرب الوقف كاملاً {(x>-0.99).mean()*100:4.1f}% | 100$ ← {bal:,.0f}$ | أكبر نزول {dd*100:.0f}%')
