# صندوق الهيكل: الحد العلوي = آخر قمة مؤكدة، السفلي = آخر قاع مؤكد. كسر + إعادة اختبار → إشارة. 1R ثم 3R، سبريد، مقارنة بالعشوائي والدخول عند الكسر
import pandas as pd, numpy as np, sys
exec(open('spread.py').read().split("for tf,f in")[0])
from numba import njit
for mk,tf,f,ty,SP in [('ذهب','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; n=len(c); pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    yr=t.dt.year.values; rs=np.random.RandomState(3)
    print(f'\n== {mk} {tf} (اختبار، 1R ثم 3R، بعد السبريد)')
    for k in (5,10):
        top=bot=np.nan; H=[];L=[]; pend=[]   # pend: (dir, level, bar_of_break)
        R=[];RB=[];RX=[];Z=[]
        for i in range(2*k,n-2):
            j=i-k
            if h[j]==h[j-k:j+k+1].max(): H.append(h[j]); top=h[j]
            if l[j]==l[j-k:j+k+1].min(): L.append(l[j]); bot=l[j]
            zone=0
            if len(H)>=2 and len(L)>=2:
                zone=1 if (H[-1]>H[-2] and L[-1]>L[-2]) else (-1 if (H[-1]<H[-2] and L[-1]<L[-2]) else 0)
            # إعادة الاختبار للكسرات المعلقة
            keep=[]
            for (dd,lev,b,zb) in pend:
                if i-b>20: continue
                touched=(l[i]<=lev+0.1*a[i]) if dd>0 else (h[i]>=lev-0.1*a[i])
                back=(c[i]>lev) if dd>0 else (c[i]<lev)
                broke_back=(c[i]<lev-0.5*a[i]) if dd>0 else (c[i]>lev+0.5*a[i])
                if broke_back: continue
                if touched and back and i>b:
                    if yr[i]>=ty:
                        g,rk=sim(o,h,l,c,a,i,dd,0.0,SP,1.0,3.0); R.append(g/rk); Z.append(zb*dd)
                        rd=1 if rs.rand()<0.5 else -1; gx,rkx=sim(o,h,l,c,a,i,rd,0.0,SP,1.0,3.0); RX.append(gx/rkx)
                    continue
                keep.append((dd,lev,b,zb))
            pend=keep
            # كسر جديد للصندوق
            if not np.isnan(top) and c[i]>top and c[i-1]<=top:
                pend.append((1,top,i,zone))
                if yr[i]>=ty: g,rk=sim(o,h,l,c,a,i,1,0.0,SP,1.0,3.0); RB.append(g/rk)
            if not np.isnan(bot) and c[i]<bot and c[i-1]>=bot:
                pend.append((-1,bot,i,zone))
                if yr[i]>=ty: g,rk=sim(o,h,l,c,a,i,-1,0.0,SP,1.0,3.0); RB.append(g/rk)
        R=np.array(R); RB=np.array(RB); RX=np.array(RX); Z=np.array(Z)
        R2=R[~np.isnan(R)]; RB=RB[~np.isnan(RB)]; RX=RX[~np.isnan(RX)]
        days=(yr.max()-ty+1)*(260 if mk=='ذهب' else 365)
        zz=Z[~np.isnan(R)]
        print(f'   k={k:2d} كسر + إعادة اختبار: {len(R2)/days:4.2f}/يوم | لم يضرب الوقف كاملاً {(R2>-0.99).mean()*100:4.1f}% | {R2.mean():+.3f}R  (مع لون المنطقة {R2[zz==1].mean():+.3f} • رمادي {R2[zz==0].mean():+.3f} • عكسها {R2[zz==-1].mean():+.3f}) | الدخول عند الكسر مباشرة {RB.mean():+.3f}R | عشوائي {RX.mean():+.3f}R')
