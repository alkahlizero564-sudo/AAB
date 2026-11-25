# TSBSE: ترند (EMA200 + قمم/قيعان) + مستويات دعم/مقاومة (قمم/قيعان متكررة) + كسر أو ارتداد بتأكيد
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
def load(p):
    d=pd.read_csv(p); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'})
    d['time']=pd.to_datetime(d.time,utc=True,errors='coerce'); return d.dropna(subset=['time']).sort_values('time').drop_duplicates('time').reset_index(drop=True)
@njit
def ex(h,l,o,i,d,stop,tp):
    n=len(h); e=o[i+1]
    for j in range(i+1,min(n,i+1500)):
        if (d>0 and l[j]<=stop) or (d<0 and h[j]>=stop): return -1.0
        if j>i+1 and ((d>0 and h[j]>=tp) or (d<0 and l[j]<=tp)): return (tp-e)*d/((e-stop)*d)
    return 0.0
sets=[('gold','5m','m1/xau_5m',0.25),('gold','15m','gold20/xau20_15m',0.25),('gold','1h','gold20/xau20_1h',0.25),('gold','4h','gold20/xau20_4h',0.25),
      ('btc','15m','gold10/btc10_15m',0.0),('btc','1h','gold10/btc10_1h',0.0),('btc','4h','gold10/btc10_4h',0.0)]
rows=[]
for mk,tf,f,SP in sets:
    d=load(f'{S}/{f}.csv'); o,h,l,c,v=[d[x].values.astype(np.float64) for x in ['open','high','low','close','volume']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    cs=pd.Series(c); e200=cs.ewm(span=200,adjust=False).mean().values
    dl=cs.diff(); u_=dl.clip(lower=0).ewm(alpha=1/14,adjust=False).mean(); d_=(-dl.clip(upper=0)).ewm(alpha=1/14,adjust=False).mean(); rsi=(100-100/(1+u_/d_.replace(0,1e-12))).values
    vma=pd.Series(v).rolling(20).mean().values
    yr=d.time.dt.year.values
    PH=[];PL=[]   # قمم/قيعان مؤكدة (5 يمين/يسار) — تُعرف بعد 5 شموع
    last=-99
    for i in range(210,n-2):
        j=i-5
        if h[j]==h[j-5:j+6].max(): PH.append((j,h[j]))
        if l[j]==l[j-5:j+6].min(): PL.append((j,l[j]))
        ai=a[i]
        if ai<=0 or len(PH)<2 or len(PL)<2: continue
        # الترند: EMA200 + بنية القمم والقيعان
        up=c[i]>e200[i] and PH[-1][1]>PH[-2][1] and PL[-1][1]>PL[-2][1]
        dn=c[i]<e200[i] and PH[-1][1]<PH[-2][1] and PL[-1][1]<PL[-2][1]
        if not (up or dn) or i-last<3: continue
        # مستويات: قمم/قيعان آخر 300 شمعة لمسها السعر مرتين على الأقل (±0.3 ATR)
        piv=[p for p in PH+PL if p[0]>=i-300]
        lv=[]
        for p in piv:
            t=sum(1 for q in piv if abs(q[1]-p[1])<0.3*ai)
            if t>=2: lv.append(p[1])
        if not lv: continue
        res=[x for x in lv if x>=c[i-1]]; sup=[x for x in lv if x<=c[i-1]]
        body=abs(c[i]-o[i]); rng=max(h[i]-l[i],1e-12)
        sig=None
        if up:
            r0=min(res) if res else None; s0=max(sup) if sup else None
            if r0 is not None and c[i]>r0 and c[i-1]<=r0 and c[i]>o[i] and body>=0.6*ai and (v[i]>vma[i] or rsi[i]>55):
                sig=('كسر مقاومة',1,min(r0-0.5*ai,c[i]-1.5*ai),[x for x in res if x>c[i]+0.5*ai])
            elif s0 is not None and l[i]<=s0+0.2*ai and c[i]>s0 and ((min(o[i],c[i])-l[i])/rng>=0.5 or (c[i]>o[i] and c[i-1]<o[i-1] and c[i]>=o[i-1])):
                sig=('ارتداد من دعم',1,min(s0,l[i])-0.25*ai,[x for x in res if x>c[i]+0.5*ai])
        else:
            s0=max(sup) if sup else None; r0=min(res) if res else None
            if s0 is not None and c[i]<s0 and c[i-1]>=s0 and c[i]<o[i] and body>=0.6*ai and (v[i]>vma[i] or rsi[i]<45):
                sig=('كسر دعم',-1,max(s0+0.5*ai,c[i]+1.5*ai),[x for x in sup if x<c[i]-0.5*ai])
            elif r0 is not None and h[i]>=r0-0.2*ai and c[i]<r0 and ((h[i]-max(o[i],c[i]))/rng>=0.5 or (c[i]<o[i] and c[i-1]>o[i-1] and c[i]<=o[i-1])):
                sig=('رفض من مقاومة',-1,max(r0,h[i])+0.25*ai,[x for x in sup if x<c[i]-0.5*ai])
        if sig is None: continue
        kind,dd,stop,nxt=sig; last=i
        e=o[i+1]; rk=(e-stop)*dd
        if rk<=0.2*ai: continue
        cost=SP/rk
        tpl=(min(nxt) if dd>0 else max(nxt)) if nxt else e+dd*3*rk
        if (tpl-e)*dd<0.5*rk: tpl=e+dd*2*rk
        rows.append([mk,tf,int(yr[i]),kind,dd,ex(h,l,o,i,dd,stop,e+dd*2*rk)-cost,ex(h,l,o,i,dd,stop,e+dd*3*rk)-cost,ex(h,l,o,i,dd,stop,e+dd*rk)-cost,ex(h,l,o,i,dd,stop,tpl)-cost])
    print('done',mk,tf,file=sys.stderr,flush=True)
R=pd.DataFrame(rows,columns=['market','tf','year','kind','dir','r2','r3','r1','rl'])
R.to_csv(S+'/ai/tsbse.csv',index=False)
print('التعادل: 1R ← 50% • 2R ← 33.3% • 3R ← 25% (الذهب بعد سبريد 0.25$)')
for (mk,tf),g in R.groupby(['market','tf'],sort=False):
    te=g[g.year>=(2021 if mk=='gold' else 2023)]
    for k in ['كسر مقاومة','كسر دعم','ارتداد من دعم','رفض من مقاومة']:
        x=te[te.kind==k]
        if len(x)<10: continue
        print(f"{mk} {tf:3s} {k:14s} n={len(x):5d} | 1R {(x.r1>0).mean()*100:5.1f}% R{x.r1.mean():+.3f} | 2R {(x.r2>0).mean()*100:5.1f}% R{x.r2.mean():+.3f} | 3R {(x.r3>0).mean()*100:5.1f}% R{x.r3.mean():+.3f} | للمستوى التالي R{x.rl.mean():+.3f}")
    x=te; print(f"{mk} {tf:3s} {'الكل':14s} n={len(x):5d} | 1R {(x.r1>0).mean()*100:5.1f}% R{x.r1.mean():+.3f} | 2R {(x.r2>0).mean()*100:5.1f}% R{x.r2.mean():+.3f} | 3R R{x.r3.mean():+.3f} | للمستوى التالي R{x.rl.mean():+.3f}")
