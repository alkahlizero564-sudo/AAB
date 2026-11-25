# Apex Institutional Confluence (AIC) — كما وصفه المستخدم، ثم اختبار عادل
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
src=open(S+'/ai/flow2.py').read(); exec(src[src.index('@njit'):src.index('def load')].replace('cache=True','cache=False').replace('@njit','from numba import njit\n@njit',1))
def load(p):
    d=pd.read_csv(p); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'})
    d['time']=pd.to_datetime(d.time,utc=True,errors='coerce'); return d.dropna(subset=['time']).sort_values('time').drop_duplicates('time').reset_index(drop=True)
@njit
def supertrend(h,l,c,a,m):
    n=len(c); dirn=np.ones(n,np.int64); up=np.zeros(n); dn=np.zeros(n)
    for i in range(n):
        hl=(h[i]+l[i])/2; bu=hl-m*a[i]; bd=hl+m*a[i]
        if i==0: up[i]=bu; dn[i]=bd; continue
        up[i]=max(bu,up[i-1]) if c[i-1]>up[i-1] else bu
        dn[i]=min(bd,dn[i-1]) if c[i-1]<dn[i-1] else bd
        if dirn[i-1]==-1 and c[i]>dn[i-1]: dirn[i]=1
        elif dirn[i-1]==1 and c[i]<up[i-1]: dirn[i]=-1
        else: dirn[i]=dirn[i-1]
    return dirn
@njit
def aicsim(h,l,o,c,sig,a,sp,out):
    # الدخول: إغلاق شمعة الإشارة (كما في الوصف) — نستخدم افتتاح التالية (أواقعي). وقف 1.5 ATR، TP1 1.5R، TP2 3R
    n=len(c)
    for i in range(n-1):
        d=sig[i]
        if d==0: continue
        e=o[i+1]; rk=1.5*a[i]; st=e-d*rk; t1=e+d*1.5*rk; t2=e+d*3*rk; cost=sp/rk
        r15=np.nan; r3=np.nan; rmix=np.nan; got=False
        for j in range(i+1,min(n,i+1000)):
            hitS=(d>0 and l[j]<=st) or (d<0 and h[j]>=st)
            h1=(d>0 and h[j]>=t1) or (d<0 and l[j]<=t1)
            h2=(d>0 and h[j]>=t2) or (d<0 and l[j]<=t2)
            if np.isnan(r15):
                if hitS and not got: r15=-1.0
                elif h1: r15=1.5
            if np.isnan(r3):
                if (d>0 and l[j]<=e-d*rk) or (d<0 and h[j]>=e-d*rk): r3=-1.0
                elif h2: r3=3.0
            # إدارة النصفين: نصف عند TP1 ثم الوقف للدخول، النصف الآخر حتى TP2
            if np.isnan(rmix):
                if not got:
                    if hitS: rmix=-1.0
                    elif h1:
                        got=True; st=e
                        if h2: rmix=0.75+1.5
                else:
                    if (d>0 and l[j]<=st) or (d<0 and h[j]>=st): rmix=0.75
                    elif h2: rmix=0.75+1.5
            if not np.isnan(r15) and not np.isnan(r3) and not np.isnan(rmix): break
        out[i,0]=r15-cost; out[i,1]=r3-cost; out[i,2]=rmix-cost
sets=[('gold','1m',['m1/xau_1m'],0.25),('gold','5m',['m1/xau_5m'],0.25),('gold','15m',['gold20/xau20_15m'],0.25),('gold','1h',['gold20/xau20_1h'],0.25),('gold','4h',['gold20/xau20_4h'],0.25),
      ('btc','5m',['data/btc_5m'],0.0),('btc','15m',['gold10/btc10_15m'],0.0),('btc','1h',['gold10/btc10_1h'],0.0),('btc','4h',['gold10/btc10_4h'],0.0)]
rows=[]
for mk,tf,fs,SP in sets:
    d=pd.concat([load(f'{S}/{f}.csv') for f in fs]).sort_values('time').reset_index(drop=True)
    if tf=='1m': d=d[d.time>='2019-01-01'].reset_index(drop=True)
    o,h,l,c,v=[d[x].values.astype(np.float64) for x in ['open','high','low','close','volume']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    a10=pd.Series(tr).ewm(alpha=1/10,adjust=False).mean().values
    cs=pd.Series(c); e50=cs.ewm(span=50,adjust=False).mean().values; e200=cs.ewm(span=200,adjust=False).mean().values
    dl=cs.diff(); u_=dl.clip(lower=0).ewm(alpha=1/14,adjust=False).mean(); d_=(-dl.clip(upper=0)).ewm(alpha=1/14,adjust=False).mean()
    rsi=(100-100/(1+u_/d_.replace(0,1e-12))).values
    upm=pd.Series(h).diff(); dnm=-pd.Series(l).diff()
    pdm=np.where((upm>dnm)&(upm>0),upm,0.0); mdm=np.where((dnm>upm)&(dnm>0),dnm,0.0)
    trs=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean()
    pdi=100*pd.Series(pdm).ewm(alpha=1/14,adjust=False).mean()/trs; mdi=100*pd.Series(mdm).ewm(alpha=1/14,adjust=False).mean()/trs
    dx=100*abs(pdi-mdi)/(pdi+mdi).replace(0,1e-12); adx=dx.ewm(alpha=1/14,adjust=False).mean().values
    st=supertrend(h,l,c,a10,3.0)
    vma=pd.Series(v).rolling(20).mean().values
    day=d.time.dt.floor('D'); tp=(h+l+c)/3
    vw=(pd.Series(tp*v).groupby(day.values).cumsum()/pd.Series(v).groupby(day.values).cumsum().replace(0,np.nan)).values
    buy=(c>e200)&(e50>e200)&(st==1)&(adx>25)&(rsi>50)&(rsi<70)&(v>1.2*vma)&(c>vw)
    sell=(c<e200)&(e50<e200)&(st==-1)&(adx>25)&(rsi<50)&(rsi>30)&(v>1.2*vma)&(c<vw)
    cond=np.where(buy,1,np.where(sell,-1,0)); cond[:250]=0
    prev=np.r_[0,cond[:-1]]
    sig=np.where((cond!=0)&(cond!=prev),cond,0).astype(np.int64)   # أول شمعة يكتمل فيها التطابق (بدون تكرار)
    out=np.full((n,3),np.nan); aicsim(h,l,o,c,sig,a,SP,out)
    w=np.full(n,-1,np.int64); r=np.zeros(n); w2=np.full(n,-1,np.int64); r2=np.zeros(n)
    simall(o,h,l,c,a,sig,np.full(n,np.nan),w,r,w2,r2)   # المقياس العادل لمؤشراتنا (1R)
    yr=d.time.dt.year.values
    for i in np.where(sig!=0)[0]:
        if np.isnan(out[i,2]) or w[i]<0: continue
        rk=1.5*a[i]
        rows.append([mk,tf,int(yr[i]),int(sig[i]),out[i,0],out[i,1],out[i,2],int(w[i]),r[i]-SP/max(rk/1.5,1e-9)*0, adx[i],rsi[i],v[i]/max(vma[i],1e-9),(c[i]-e200[i])/a[i]*sig[i],(c[i]-vw[i])/a[i]*sig[i],rk])
    print('done',mk,tf,int((sig!=0).sum()),file=sys.stderr,flush=True)
R=pd.DataFrame(rows,columns=['market','tf','year','dir','r15','r3','rmix','win1r','r1r','adx','rsi','volr','d200','dvw','riskp'])
R.to_csv(S+'/ai/aic.csv',index=False)
print('التعادل: هدف 1.5R ← 40% • هدف 3R ← 25% • نصف/نصف (1.5R ثم 3R) ← R>0 • للمقارنة 1R (مقياس مؤشراتنا) ← 50%')
for (mk,tf),g in R.groupby(['market','tf'],sort=False):
    for ph,m in [('كل السنين',np.ones(len(g),bool)),('اختبار (ذهب 2021+ / بيتكوين 2023+)',(g.year>=(2021 if mk=='gold' else 2023)).values)]:
        x=g[m]
        if len(x)==0: continue
        print(f"{mk} {tf:3s} {ph:34s} n={len(x):5d} | 1.5R {(x.r15>0).mean()*100:5.1f}% R{x.r15.mean():+.3f} | 3R {(x.r3>0).mean()*100:5.1f}% R{x.r3.mean():+.3f} | نصف/نصف R{x.rmix.mean():+.3f} (رابحة {(x.rmix>0).mean()*100:.0f}%) | 1R {x.win1r.mean()*100:5.1f}%")
