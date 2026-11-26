# مؤشر مناطق الفيبو: ارتداد من المنطقة الذهبية (مع الموجة) أو كسرها (عكس الموجة) — دخول بالسوق بعد التأكيد
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
@njit
def sim(o,h,l,c,a,i,d,SP):
    n=len(c); e=o[i+1]; ext=l[i] if d>0 else h[i]
    for j in range(i-2,i+1): ext=min(ext,l[j]) if d>0 else max(ext,h[j])
    rk=min(max((e-ext)*d+0.1*a[i],0.7*a[i]),2.5*a[i])
    st=e-d*rk; t1=e+d*rk; t2=e+2*d*rk; got=False; stop=st
    w1=-1
    for j in range(i+1,min(n,i+400)):
        hs=(d>0 and l[j]<=stop) or (d<0 and h[j]>=stop)
        if hs:
            if w1<0: w1=0
            return w1,(0.5 if got else -1.0)-SP/rk
        if not got and ((d>0 and h[j]>=t1) or (d<0 and l[j]<=t1)):
            got=True; stop=e
            if w1<0: w1=1
        if got and ((d>0 and h[j]>=t2) or (d<0 and l[j]<=t2)): return w1,1.5-SP/rk
    return -1,np.nan
rows=[]
for mk,tf,f,SP in [('ذهب','15m','gold20/xau20_15m.csv',0.25),('ذهب','1h','gold20/xau20_1h.csv',0.25),('بيتكوين','15m','gold10/btc10_15m.csv',0.0),('بيتكوين','1h','gold10/btc10_1h.csv',0.0)]:
    d=pd.read_csv(f'{S}/{f}'); d.columns=[x.lower() for x in d.columns]
    o,h,l,c=[d[x].values.astype(np.float64) for x in ['open','high','low','close']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    yr=pd.to_datetime(d.iloc[:,0]).dt.year.values
    k=5; ph=pl=-1; rs=np.random.RandomState(7)
    Z=None  # منطقة فعّالة: (dir, z5, z618, z786, endbar, entered, done)
    for i in range(300,n-2):
        j=i-k
        newp=False
        if h[j]==h[j-k:j+k+1].max(): ph=j; newp=True
        if l[j]==l[j-k:j+k+1].min(): pl=j; newp=True
        if newp and ph>0 and pl>0:
            dd=1 if pl<ph else -1; hi,lo=h[ph],l[pl]; leg=hi-lo; s1=max(ph,pl)
            if leg>=3*a[s1]:
                fib=(lambda x: hi-x*leg) if dd>0 else (lambda x: lo+x*leg)
                Z=[dd,fib(0.5),fib(0.618),fib(0.786),s1,False]
        if Z is None: continue
        dd,z5,z6,z7,s1,ent=Z
        if i-s1>80: Z=None; continue
        # دخول المنطقة
        if (dd>0 and l[i]<=z5) or (dd<0 and h[i]>=z5): Z[5]=ent=True
        sig=0; kind=''
        if ent and ((dd>0 and c[i]<z7) or (dd<0 and c[i]>z7)): sig=-dd; kind='كسر'; Z=None
        elif ent and ((dd>0 and c[i]>z5 and l[i]>z7) or (dd<0 and c[i]<z5 and h[i]<z7)) and ((dd>0 and c[i]>o[i]) or (dd<0 and c[i]<o[i])): sig=dd; kind='ارتداد'; Z=None
        if sig==0: continue
        w,r=sim(o,h,l,c,a,i,sig,SP)
        rd=1 if rs.rand()<0.5 else -1
        wr,rr=sim(o,h,l,c,a,i,rd,SP)
        rows.append([mk,tf,int(yr[i]),kind,w,r,wr,rr])
    print('done',mk,tf,file=sys.stderr,flush=True)
R=pd.DataFrame(rows,columns=['mk','tf','year','kind','w','r','wr','rr']); R=R[R.w>=0]
for (mk,tf),G in R.groupby(['mk','tf'],sort=False):
    ty=2019 if mk=='ذهب' else 2021; T=G[G.year>=ty]; Tr=G[G.year<ty]
    days=(T.year.max()-ty+1)*260
    print(f'== {mk} {tf}')
    for kd in ['ارتداد','كسر']:
        x=T[T.kind==kd]; y=Tr[Tr.kind==kd]
        print(f'   {kd:7s} n={len(x):5d} ({len(x)/days:4.2f}/يوم) | دقة 1R {x.w.mean()*100:5.1f}% | R {x.r.mean():+.3f}   [تدريب دقة {y.w.mean()*100:5.1f}%]')
    x=T; print(f'   الاثنين  n={len(x):5d} | دقة 1R {x.w.mean()*100:5.1f}% | R {x.r.mean():+.3f} || عشوائي بنفس الأوقات: دقة {x.wr.mean()*100:5.1f}% R {x.rr.mean():+.3f}')
