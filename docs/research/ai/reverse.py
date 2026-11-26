# إشارة عكسية أثناء صفقة مفتوحة: (A) تجاهلها واترك الصفقة للوقف/الهدف (B) أغلق القديمة عند افتتاح الشمعة بعد الإشارة العكسية
import pandas as pd, numpy as np
from numba import njit
exec(open('spread.py').read().split("for tf,f in")[0])
Q93=0.6105149837333336
@njit
def run(o,h,l,c,a,i,d,SP,t1m,t2m,forced):
    # forced: شمعة إغلاق إجباري (افتتاحها) أو -1. يرجع (R، شمعة الخروج)
    n=len(c); e=o[i+1]; ext=l[i] if d>0 else h[i]
    for j in range(i-2,i+1): ext=min(ext,l[j]) if d>0 else max(ext,h[j])
    rk=min(max((e-ext)*d+0.1*a[i],0.7*a[i]),2.5*a[i]); st=e-d*rk; t1=e+d*t1m*rk; t2=e+d*t2m*rk; got=False; stop=st
    for j in range(i+1,min(n,i+2000)):
        if forced>0 and j==forced:
            px=o[j]; return ((0.5*t1m*rk+0.5*(px-e)*d) if got else (px-e)*d)/rk-SP/rk, j
        if (d>0 and l[j]<=stop) or (d<0 and h[j]>=stop): return ((0.5*t1m if got else -1.0)-SP/rk), j
        if not got and ((d>0 and h[j]>=t1) or (d<0 and l[j]<=t1)): got=True; stop=e
        if got and ((d>0 and h[j]>=t2) or (d<0 and l[j]<=t2)): return (0.5*t1m+0.5*t2m)-SP/rk, j
    return np.nan, -1
for tf,f in [('15m','gold20/xau20_15m.csv'),('1h','gold20/xau20_1h.csv')]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; yr=pd.to_datetime(d.iloc[:,0]).dt.year.values
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    m=((key.market=='gold20')&(key.tf==tf)).values&(s.p.values>=Q70)
    ii=key.i.values[m]; dd=key.dir.values[m]; pp=s.p.values[m]
    sel=yr[ii]>=2021; ii,dd,pp=ii[sel],dd[sel],pp[sel]; o_=np.argsort(ii); ii,dd,pp=ii[o_],dd[o_],pp[o_]
    stars=np.where(pp>=Q93,3,np.where(pp>=Q85,2,1))
    base=[]; exits=[]
    for i,di in zip(ii,dd):
        r,x=run(o,h,l,c,a,int(i),int(di),0.25,1.0,3.0,-1); base.append(r); exits.append(x)
    base=np.array(base); exits=np.array(exits)
    # الصفقات التي جاءتها إشارة عكسية وهي مفتوحة
    def first_opp(q,need_stars):
        for k in range(q+1,len(ii)):
            if ii[k]>=exits[q]: return -1
            if dd[k]!=dd[q] and stars[k]>=need_stars(stars[q]): return k
        return -1
    for lab,need in [('أي إشارة عكسية',lambda s:1),('عكسية بنجوم ≥ القديمة',lambda s:s),('عكسية أقوى (نجوم أكثر)',lambda s:s+1)]:
        B=base.copy(); hit=[]
        for q in range(len(ii)):
            if np.isnan(base[q]): continue
            k=first_opp(q,need)
            if k<0: continue
            r,_=run(o,h,l,c,a,int(ii[q]),int(dd[q]),0.25,1.0,3.0,int(ii[k])+1); B[q]=r; hit.append(q)
        hit=np.array(hit,int)
        ok=~np.isnan(base)
        print(f'== ذهب {tf} King ⭐+ 2021+ ({ok.sum()} صفقة) — {lab}: جاءت عكسية لـ {len(hit)} صفقة')
        print(f'     في الصفقات المتأثرة: الإبقاء {base[hit].mean():+.3f}R ← الإغلاق عند العكسية {B[hit].mean():+.3f}R')
        print(f'     كل الصفقات: الإبقاء {np.nanmean(base):+.3f}R/صفقة (مجموع {np.nansum(base):+.0f}R) ← الإغلاق {np.nanmean(B):+.3f}R/صفقة (مجموع {np.nansum(B):+.0f}R)')
