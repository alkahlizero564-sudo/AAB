# AALR — مذبذب السيولة والزخم التكيفي: حالة السوق + سحب سيولة واندفاع + مذبذب −100..+100 — اختبار عادل
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
@njit
def ex(h,l,o,i,d,stop,RR):
    n=len(h); e=o[i+1]; rk=(e-stop)*d
    if rk<=0: return np.nan,0.0
    tp=e+RR*d*rk
    for j in range(i+1,min(n,i+1000)):
        if (d>0 and l[j]<=stop) or (d<0 and h[j]>=stop): return -1.0,rk
        if (d>0 and h[j]>=tp) or (d<0 and l[j]<=tp): return RR,rk
    return 0.0,rk
@njit
def adapt_ema(x,span):
    out=np.empty_like(x); out[0]=x[0]
    for i in range(1,len(x)):
        al=2.0/(span[i]+1); out[i]=out[i-1]+al*(x[i]-out[i-1])
    return out
sets=[('gold','5m','m1/xau_5m.csv',0.25),('gold','15m','gold20/xau20_15m.csv',0.25),('gold','1h','gold20/xau20_1h.csv',0.25),
      ('btc','15m','gold10/btc10_15m.csv',0.0),('btc','1h','gold10/btc10_1h.csv',0.0)]
MODES={'محافظ':(1.0,40),'متوازن':(0.8,30),'هجومي':(0.6,20)}   # (مضاعف الاندفاع × ATR، حد المذبذب)
rows=[]
for mk,tf,f,SP in sets:
    d=pd.read_csv(f'{S}/{f}'); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'}); d['time']=pd.to_datetime(d.time)
    d=d.sort_values('time').drop_duplicates('time').reset_index(drop=True)
    o,h,l,c=[d[x].values.astype(np.float64) for x in ['open','high','low','close']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    W=lambda s,p: pd.Series(s).ewm(alpha=1/p,adjust=False).mean().values
    a=W(tr,14); a5=W(tr,5); a50=W(tr,50)
    # حالة السوق: كفاءة الاتجاه (Kaufman ER 20) + عرض بولينجر (نسبي لآخر 200)
    ch=np.abs(c-np.r_[c[:20],c[:-20]]); vol=pd.Series(np.abs(np.diff(c,prepend=c[0]))).rolling(20).sum().values
    er=ch/np.maximum(vol,1e-12)
    sd=pd.Series(c).rolling(20).std(ddof=0).values; bw=4*sd/np.maximum(a,1e-12)
    bwp=pd.Series(bw).rolling(200).rank(pct=True).values
    regime=np.where((er>0.35)&(a5>a50*0.95),1,np.where(bwp<0.2,2,np.where(er<0.2,3,0)))   # 1 اتجاه، 2 انضغاط، 3 تذبذب، 0 عادي
    # المذبذب: زخم معدّل بالتذبذب، تنعيم تكيفي حسب الحالة، ثم tanh إلى −100..+100
    e21=pd.Series(c).ewm(span=21,adjust=False).mean().values
    raw=0.6*(c-e21)/np.maximum(a,1e-12)+0.4*(c-np.r_[c[:10],c[:-10]])/np.maximum(a*np.sqrt(10),1e-12)
    span=np.where(regime==1,5.0,np.where(regime==2,8.0,13.0))
    osc=100*np.tanh(0.6*adapt_ema(raw,span))
    yr=d.time.dt.year.values; days=d.time.dt.floor('D').values
    lo20=pd.Series(l).rolling(20).min().shift(1).values; hi20=pd.Series(h).rolling(20).max().shift(1).values
    rng=np.maximum(h-l,1e-12)
    for mode,(km,thr) in MODES.items():
        last=-99
        for i in range(260,n-2):
            ai=a[i]
            if not ai>0 or i-last<3: continue
            if mode!='هجومي' and regime[i]==3: continue          # فلتر التذبذب العشوائي
            s=0
            # سحب سيولة خلال آخر 3 شموع + شمعة اندفاع الآن + المذبذب يعبر الحد
            for k in range(max(1,i-2),i+1):
                if l[k]<lo20[k] and c[k]>lo20[k]: s=1 if s==0 else s
                if h[k]>hi20[k] and c[k]<hi20[k]: s=-1 if s==0 else s
            if s==0: continue
            body=(c[i]-o[i])*s
            disp=body>=km*ai and ((c[i]-l[i])/rng[i]>=0.7 if s>0 else (h[i]-c[i])/rng[i]>=0.7)
            cross=(osc[i]>=thr and osc[i-1]<thr) if s>0 else (osc[i]<=-thr and osc[i-1]>-thr)
            if not (disp and cross): continue
            ext=min(l[max(0,i-3):i+1]) if s>0 else max(h[max(0,i-3):i+1])
            stop=ext-s*0.25*ai
            r1,rk=ex(h,l,o,i,s,stop,1.0); r2,_=ex(h,l,o,i,s,stop,2.0); r3,_=ex(h,l,o,i,s,stop,3.0)
            if np.isnan(r1): continue
            cost=SP/rk
            last=i
            rows.append([mk,tf,mode,int(yr[i]),days[i],s,int(regime[i]),r1-cost,r2-cost,r3-cost])
    print('done',mk,tf,file=sys.stderr,flush=True)
R=pd.DataFrame(rows,columns=['mk','tf','mode','year','day','dir','regime','r1','r2','r3'])
R.to_csv(S+'/ai/aalr.csv',index=False)
print('اختبار (ذهب 2019+ بعد سبريد 0.25$، بيتكوين 2021+ قبل العمولة) — التعادل: 1R 50% • 2R 33% • 3R 25%')
for (mk,tf),G in R.groupby(['mk','tf'],sort=False):
    T=G[G.year>=(2019 if mk=='gold' else 2021)]
    nd=len(np.unique(T.day))
    for mode in MODES:
        x=T[T['mode']==mode]
        if len(x)<20: print(f'  {mk} {tf:3s} {mode:6s} n={len(x)} (قليل)'); continue
        print(f"  {mk} {tf:3s} {mode:6s} n={len(x):5d} ({len(x)/max(nd,1):4.2f}/يوم) | 1R {(x.r1>0).mean()*100:5.1f}% R{x.r1.mean():+.3f} | 2R {(x.r2>0).mean()*100:5.1f}% R{x.r2.mean():+.3f} | 3R {(x.r3>0).mean()*100:5.1f}% R{x.r3.mean():+.3f}")
    x=T[T['mode']=='هجومي']
    for rg,nm in [(1,'اتجاه'),(2,'انضغاط'),(3,'تذبذب'),(0,'عادي')]:
        y=x[x.regime==rg]
        if len(y)>=30: print(f"      حالة {nm:6s} n={len(y):4d} 2R R{y.r2.mean():+.3f}")
