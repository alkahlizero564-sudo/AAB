# بداية الاندفاع: هل نلقط بداية الهبوط/الصعود القوي؟ أحداث + خروج ثابت + ركوب الترند + ذكاء
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
src=open(S+'/ai/flow2.py').read(); exec(src[src.index('@njit'):src.index('def load')].replace('cache=True','cache=False').replace('@njit','from numba import njit\n@njit',1))
from numba import njit
@njit
def simrr(h,l,o,sig,stp,RR,w,r):
    n=len(h)
    for i in range(n-1):
        d=sig[i]
        if d==0: continue
        e=o[i+1]; sp=stp[i]; rk=(e-sp)*d
        if rk<=0: continue
        tp=e+RR*d*rk; w[i]=0; r[i]=-1.0
        for j in range(i+1,min(n,i+400)):
            if (d>0 and l[j]<=sp) or (d<0 and h[j]>=sp): break
            if j>i+1 and ((d>0 and h[j]>=tp) or (d<0 and l[j]<=tp)): w[i]=1; r[i]=RR; break
@njit
def simride(h,l,c,o,e20,sig,stp,r):
    # ركوب الترند: الوقف الأصلي، والخروج بإغلاق عكس EMA20 (أو بعد 300 شمعة)
    n=len(h)
    for i in range(n-1):
        d=sig[i]
        if d==0: continue
        e=o[i+1]; sp=stp[i]; rk=(e-sp)*d
        if rk<=0: continue
        r[i]=np.nan
        for j in range(i+1,min(n,i+300)):
            if (d>0 and l[j]<=sp) or (d<0 and h[j]>=sp): r[i]=-1.0; break
            if (c[j]-e20[j])*d<0: r[i]=(c[j]-e)*d/rk; break
        if np.isnan(r[i]): r[i]=(c[min(n-1,i+299)]-e)*d/rk
def load(p):
    d=pd.read_csv(p); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'})
    d['time']=pd.to_datetime(d.time,utc=True,errors='coerce'); return d.dropna(subset=['time']).sort_values('time').drop_duplicates('time').reset_index(drop=True)
sets=[('gold','15m',['gold20/xau20_15m']),('gold','1h',['gold20/xau20_1h']),('btc','15m',['gold10/btc10_15m']),('btc','1h',['gold10/btc10_1h']),
      ('btc','5m',['data/btc_5m']),('eth','5m',['data/eth_5m_1819','data/eth_5m_2526']),('eth','15m',['data/eth_15m_1819','data/eth_15m_2526'])]
K=['impulse','flip','impulse_trend']
rows=[]
for mk,tf,fs in sets:
    d=pd.concat([load(f'{S}/{f}.csv') for f in fs]).sort_values('time').reset_index(drop=True)
    o,h,l,c=[d[x].values.astype(np.float64) for x in ['open','high','low','close']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values; a50=pd.Series(tr).ewm(alpha=1/50,adjust=False).mean().values
    cs=pd.Series(c); E={p:cs.ewm(span=p,adjust=False).mean().values for p in (20,25,30,35,50,200)}
    ll20=pd.Series(l).rolling(20).min().shift(1).values; hh20=pd.Series(h).rolling(20).max().shift(1).values
    dl=cs.diff(); u_=dl.clip(lower=0).ewm(alpha=1/14,adjust=False).mean(); d_=(-dl.clip(upper=0)).ewm(alpha=1/14,adjust=False).mean()
    rsi=(100-100/(1+u_/d_.replace(0,1e-12))).values
    yr=d.time.dt.year.values; hr=d.time.dt.hour.values
    ordU=(E[20]>E[25])&(E[25]>E[30])&(E[30]>E[35]); ordD=(E[20]<E[25])&(E[25]<E[30])&(E[30]<E[35])
    sig={k:np.zeros(n,np.int64) for k in K}; stp={k:np.full(n,np.nan) for k in K}
    for i in range(210,n-1):
        ai=a[i]
        if ai<=0: continue
        rg=h[i]-l[i]
        big=rg>=1.5*ai
        for dd in (1,-1):
            brk=(c[i]>hh20[i]) if dd>0 else (c[i]<ll20[i])
            near=((c[i]-l[i])/max(rg,1e-12)>=0.75) if dd>0 else ((h[i]-c[i])/max(rg,1e-12)>=0.75)
            sp=(l[i]-0.1*ai) if dd>0 else (h[i]+0.1*ai)
            if brk and big and near:
                sig['impulse'][i]=dd; stp['impulse'][i]=sp
                if (E[20][i]-E[50][i])*dd>0: sig['impulse_trend'][i]=dd; stp['impulse_trend'][i]=sp
            fl=(ordU[i] and not ordU[i-1]) if dd>0 else (ordD[i] and not ordD[i-1])
            if fl:
                sig['flip'][i]=dd; stp['flip'][i]=(min(l[i-2:i+1].min(),E[35][i]-0.5*ai)-0.1*ai) if dd>0 else (max(h[i-2:i+1].max(),E[35][i]+0.5*ai)+0.1*ai)
    for k in K:
        s=sig[k]; w=np.full(n,-1,np.int64); r=np.zeros(n); w2=np.full(n,-1,np.int64); r2=np.zeros(n)
        simall(o,h,l,c,a,s,stp[k],w,r,w2,r2)
        w3=np.full(n,-1,np.int64); r3=np.zeros(n); simrr(h,l,o,s,stp[k],3.0,w3,r3)
        rr=np.full(n,np.nan); simride(h,l,c,o,E[20],s,stp[k],rr)
        for i in np.where(s!=0)[0]:
            if w[i]<0 or w3[i]<0 or np.isnan(rr[i]): continue
            dd=s[i]
            rows.append([mk,tf,k,int(yr[i]),int(dd),int(w[i]),r[i],int(w2[i]),r2[i],int(w3[i]),r3[i],rr[i],
                {'5m':5,'15m':15,'1h':60}[tf],mk=='gold',(h[i]-l[i])/a[i],abs(o[i+1]-stp[k][i])/a[i],
                (c[i]-E[50][i])/a[i]*dd,(c[i]-E[200][i])/a[i]*dd,(E[50][i]-E[50][i-10])/a[i]*dd,(rsi[i]-50)/50*dd,np.log(a[i]/a50[i]),
                (c[i]-c[i-5])/a[i]*dd,(c[i]-c[i-20])/a[i]*dd,(c[i]-o[i])/a[i]*dd,(E[20][i]-E[35][i])/a[i]*dd,
                np.sin(2*np.pi*hr[i]/24),np.cos(2*np.pi*hr[i]/24)])
    print('done',mk,tf,len(rows),file=sys.stderr,flush=True)
cols=['market','tf','mode','year','dir','win','r','vwin','vr','w3','r3','ride','tfm','isgold','rng','risk','e50','e200','slope','rsi','volr','mom5','mom20','body','ribw','hs','hc']
pd.DataFrame(rows,columns=cols).to_csv(S+'/ai/impulse.csv',index=False)
