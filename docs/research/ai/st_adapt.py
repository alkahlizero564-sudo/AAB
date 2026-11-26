# Adaptive SuperTrend AI (Regime-Tuned): مضاعف ATR حسب الحالة (ADX + Choppiness + نسبة ATR) — اختبار الدخول عند الانقلاب
import pandas as pd, numpy as np, sys
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
def RMA(x,p): return pd.Series(x).ewm(alpha=1/p,adjust=False).mean().values
@njit
def stv(h,l,c,atr,fac):
    n=len(c); up=np.zeros(n); dn=np.zeros(n); d=np.ones(n,np.int64); line=np.zeros(n)
    for i in range(1,n):
        m=(h[i]+l[i])/2; u=m-fac[i]*atr[i]; w=m+fac[i]*atr[i]
        up[i]=max(u,up[i-1]) if c[i-1]>up[i-1] else u
        dn[i]=min(w,dn[i-1]) if c[i-1]<dn[i-1] else w
        if d[i-1]==1 and c[i]<up[i]: d[i]=-1
        elif d[i-1]==-1 and c[i]>dn[i]: d[i]=1
        else: d[i]=d[i-1]
        line[i]=up[i] if d[i]==1 else dn[i]
    return d,line
@njit
def trade(o,h,l,c,i,d,st,rr,SP,maxb):
    n=len(c); e=o[i+1]; r=(e-st)*d
    if r<=0: return np.nan,np.nan
    t=e+d*rr*r
    for j in range(i+1,min(n,i+maxb)):
        if (d>0 and l[j]<=st) or (d<0 and h[j]>=st): return -1.0-SP/r, r
        if (d>0 and h[j]>=t) or (d<0 and l[j]<=t): return rr-SP/r, r
    return (c[min(n-1,i+maxb-1)]-e)*d/r-SP/r, r
def build(d,atrlen,F):
    h,l,c=[d[x].values.astype(float) for x in ['high','low','close']]
    pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    atr=RMA(tr,atrlen); a14=RMA(tr,14)
    upm=h-np.r_[h[0],h[:-1]]; dnm=np.r_[l[0],l[:-1]]-l
    pdm=np.where((upm>dnm)&(upm>0),upm,0); mdm=np.where((dnm>upm)&(dnm>0),dnm,0)
    pdi=RMA(pdm,14)/a14; mdi=RMA(mdm,14)/a14; adx=RMA(np.nan_to_num(abs(pdi-mdi)/np.maximum(pdi+mdi,1e-12)),14)*100
    chop=100*np.log10(pd.Series(tr).rolling(14).sum().values/np.maximum(pd.Series(h).rolling(14).max().values-pd.Series(l).rolling(14).min().values,1e-12))/np.log10(14)
    ar=atr/pd.Series(atr).rolling(100).mean().values
    reg=np.where(ar>1.5,2,np.where((adx>25)&(chop<50),0,np.where((chop>61.8)|(adx<20),1,3)))   # 0 ترند، 1 تذبذب، 2 متقلب، 3 غير واضح
    fac=np.array([F[k] for k in reg],float); fac=pd.Series(fac).rolling(5,min_periods=1).mean().values
    dd,line=stv(h,l,c,np.nan_to_num(atr),fac)
    return dd,line,adx,chop
rows=[]
for mk,tf,f,ty,SP,maxb in [('ذهب','5m','m1/xau_5m.csv',2019,0.25,600),('ذهب','15m','gold20/xau20_15m.csv',2019,0.25,400),('ذهب','1h','gold20/xau20_1h.csv',2019,0.25,300),('بيتكوين','15m','gold10/btc10_15m.csv',2021,0.0,400),('بيتكوين','1h','gold10/btc10_1h.csv',2021,0.0,300)]:
    d=pd.read_csv(f'{S}/{f}'); d.columns=[x.lower() for x in d.columns]
    yr=pd.to_datetime(d.iloc[:,0]).dt.year.values
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]
    rs=np.random.RandomState(4)
    for setn,atrlen,F in [('الأصلية (ATR10: 2.5/3.5/4.5/3)',10,(2.5,3.5,4.5,3.0)),('الفيديو (ATR27: 2/1.7/2.5/2.75)',27,(2.0,1.7,2.5,2.75)),('SuperTrend عادي (10، 3)',10,(3.0,3.0,3.0,3.0))]:
        dd,line,adx,chop=build(d,atrlen,F)
        fl=np.where((dd[1:]!=dd[:-1]))[0]+1
        for i in fl:
            if i<300 or i+2>=len(c): continue
            di=int(dd[i]); st=line[i]
            for rr in (1.0,1.5,2.0):
                g,r=trade(o,h,l,c,i,di,st,rr,SP,maxb)
                rd_=1 if rs.rand()<0.5 else -1
                gx,_=trade(o,h,l,c,i,rd_,c[i]-rd_*abs(c[i]-st),rr,SP,maxb)
                rows.append([mk,tf,setn,yr[i],rr,g,gx,adx[i]])
    print('done',mk,tf,file=sys.stderr,flush=True)
T=pd.DataFrame(rows,columns=['mk','tf','set','year','rr','g','gx','adx']).dropna()
T.to_pickle(S+'/ai/ast.pkl')
for (mk,tf),G in T.groupby(['mk','tf'],sort=False):
    ty=2019 if mk=='ذهب' else 2021; X=G[G.year>=ty]; days=(X.year.max()-ty+1)*260
    print(f'== {mk} {tf} (اختبار، بعد السبريد)')
    for setn,H in X.groupby('set',sort=False):
        print(f'   {setn:34s} '+' | '.join(f'هدف {rr}R: نجاح {(x.g>0).mean()*100:4.1f}% {x.g.mean():+.3f}R (عشوائي {x.gx.mean():+.3f})' for rr,x in H.groupby('rr'))+f' | {len(H)/3/days:.1f}/يوم')
