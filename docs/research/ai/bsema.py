# BS EMA (فيديو): تقاطع EMA30/EMA32 مع فلتر EMA55 — ذهب 1m/5m/15m/1h، سبريد 0.25$، وقف خلف آخر 5 شموع (حد أدنى 0.06% لـ 1m/5m)، أهداف 1R/2R
import pandas as pd, numpy as np, sys
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
def E(x,p): return pd.Series(x).ewm(span=p,adjust=False).mean().values
@njit
def trade(o,h,l,c,i,d,st,rr,SP,maxb):
    n=len(c); e=o[i+1]; r=(e-st)*d
    if r<=0: return np.nan,np.nan
    t=e+d*rr*r
    for j in range(i+1,min(n,i+maxb)):
        if (d>0 and l[j]<=st) or (d<0 and h[j]>=st): return -1.0-SP/r, r
        if (d>0 and h[j]>=t) or (d<0 and l[j]<=t): return rr-SP/r, r
    return (c[min(n-1,i+maxb-1)]-e)*d/r-SP/r, r
rows=[]
for tf,f,maxb in [('1m','m1/xau_1m.csv',1500),('5m','m1/xau_5m.csv',600),('15m','gold20/xau20_15m.csv',400),('1h','gold20/xau20_1h.csv',300)]:
    d=pd.read_csv(f'{S}/{f}'); d.columns=[x.lower() for x in d.columns]; yr=pd.to_datetime(d.iloc[:,0]).dt.year.values
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]
    e1,e2,e3=E(c,30),E(c,32),E(c,55)
    up=(e1>e2)&(np.r_[False,e1[:-1]<=e2[:-1]]); dn=(e1<e2)&(np.r_[False,e1[:-1]>=e2[:-1]])
    rs=np.random.RandomState(5); minst=c*0.0006 if tf in ('1m','5m') else c*0
    for i in np.where(up|dn)[0]:
        if i<300 or i+2>=len(c) or yr[i]<2019: continue
        dd=1 if up[i] else -1
        ext=l[i-4:i+1].min() if dd>0 else h[i-4:i+1].max()
        st=ext-dd*max(abs(c[i]-ext)*0,0)
        if abs(o[i+1]-st)<minst[i]: st=o[i+1]-dd*minst[i]
        filt=int((c[i]-e3[i])*dd>0)
        rd=1 if rs.rand()<0.5 else -1
        for rr in (1.0,2.0):
            g,r=trade(o,h,l,c,i,dd,st,rr,0.25,maxb)
            gx,_=trade(o,h,l,c,i,rd,o[i+1]-rd*abs(o[i+1]-st),rr,0.25,maxb)
            rows.append([tf,yr[i],filt,rr,g,gx,r])
    print('done',tf,file=sys.stderr,flush=True)
T=pd.DataFrame(rows,columns=['tf','year','filt','rr','g','gx','risk']).dropna()
for tf,G in T.groupby('tf',sort=False):
    days=(G.year.max()-2019+1)*260
    print(f'== ذهب {tf} (2019+، بعد السبريد) — متوسط الوقف {G.risk.median():.2f}$')
    for lab,X in [('كل التقاطعات',G),('مع فلتر EMA55 (مثل الفيديو)',G[G.filt==1])]:
        print(f'   {lab:28s} '+' | '.join(f'هدف {rr}R: نجاح {(x.g>0).mean()*100:4.1f}% {x.g.mean():+.3f}R (عشوائي {x.gx.mean():+.3f})' for rr,x in X.groupby('rr'))+f' | {len(X)/2/days:.1f}/يوم')
