# ISDE: مناطق عرض/طلب طازجة + شمعة رفض/ابتلاع عند أول رجوع + وقف خلف المنطقة + أهداف 2R/3R أو المنطقة المعاكسة
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
    d=load(f'{S}/{f}.csv'); o,h,l,c=[d[x].values.astype(np.float64) for x in ['open','high','low','close']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    cs=pd.Series(c); e200=cs.ewm(span=200,adjust=False).mean().values; e50=cs.ewm(span=50,adjust=False).mean().values
    dl=cs.diff(); u_=dl.clip(lower=0).ewm(alpha=1/14,adjust=False).mean(); d_=(-dl.clip(upper=0)).ewm(alpha=1/14,adjust=False).mean(); rsi=(100-100/(1+u_/d_.replace(0,1e-12))).values
    yr=d.time.dt.year.values
    zones=[]   # [dir, lo, hi, born, impulse, touched]
    for i in range(210,n-2):
        ai=a[i]
        if ai<=0: continue
        # منطقة جديدة: قاعدة 1-3 شموع (مدى < 1 ATR) ثم انطلاق ≥ 2 ATR خلال 3 شموع
        for bn in (1,2,3):
            b0=i-3-bn+1; b1=i-3
            if b0<1: continue
            if h[b0:b1+1].max()-l[b0:b1+1].min()>a[b1]: continue
            blo=l[b0:b1+1].min(); bhi=h[b0:b1+1].max(); imp=c[i]-c[b1]
            if bhi-blo<0.25*a[b1]: break   # منطقة ضيقة جداً
            if imp>=2*a[b1] and c[i]>bhi+a[b1]: zones.append([1,blo,bhi,i,imp/a[b1],0]); break
            if -imp>=2*a[b1] and c[i]<blo-a[b1]: zones.append([-1,blo,bhi,i,-imp/a[b1],0]); break
        keep=[]
        for z in zones:
            dd,lo,hi,born,imp,tch=z
            if i<=born+2: keep.append(z); continue
            if (dd>0 and c[i]<lo-0.25*ai) or (dd<0 and c[i]>hi+0.25*ai): continue      # مكسورة بإغلاق واضح
            if i-born>500: continue
            inside=(l[i]<=hi) if dd>0 else (h[i]>=lo)
            if inside and tch==0:
                # شمعة رفض: ابتلاعية أو ذيل طويل (≥ 50% من مدى الشمعة) في اتجاه المنطقة، وإغلاق خارج/فوق المنطقة
                rng=max(h[i]-l[i],1e-12)
                if dd>0:
                    eng=c[i]>o[i] and c[i-1]<o[i-1] and c[i]>=o[i-1] and o[i]<=c[i-1]
                    pin=(min(o[i],c[i])-l[i])/rng>=0.5 and c[i]>=o[i]-0.1*ai
                    ok=(eng or pin) and c[i]>lo
                else:
                    eng=c[i]<o[i] and c[i-1]>o[i-1] and c[i]<=o[i-1] and o[i]>=c[i-1]
                    pin=(h[i]-max(o[i],c[i]))/rng>=0.5 and c[i]<=o[i]+0.1*ai
                    ok=(eng or pin) and c[i]<hi
                if ok:
                    z[5]=1
                    e=o[i+1]; stop=(min(lo,l[i])-0.25*ai) if dd>0 else (max(hi,h[i])+0.25*ai)
                    rk=(e-stop)*dd
                    if rk>0:
                        cost=SP/rk
                        opp=[(zz[1] if dd>0 else zz[2]) for zz in zones if zz[0]==-dd and zz[3]<i and ((zz[1] if dd>0 else zz[2])-e)*dd>0.5*rk]
                        tpz=(min(opp) if dd>0 else max(opp)) if opp else e+dd*3*rk
                        r2=ex(h,l,o,i,dd,stop,e+dd*2*rk)-cost; r3=ex(h,l,o,i,dd,stop,e+dd*3*rk)-cost; rz=ex(h,l,o,i,dd,stop,tpz)-cost
                        trend=1 if ((c[i]-e200[i])*dd>0 and (e50[i]-e200[i])*dd>0) else 0
                        rows.append([mk,tf,int(yr[i]),dd,r2,r3,rz,trend,int(eng),imp,(rsi[i]-50)*dd])
                    continue
                z[5]=1; continue     # لمس بدون رفض: استُهلكت (ليست طازجة بعد الآن)
            keep.append(z)
        zones=keep[-80:]
    print('done',mk,tf,file=sys.stderr,flush=True)
R=pd.DataFrame(rows,columns=['market','tf','year','dir','r2','r3','rz','trend','eng','imp','mom'])
R.to_csv(S+'/ai/isde.csv',index=False)
print('التعادل: 2R ← 33.3% • 3R ← 25% (الذهب بعد سبريد 0.25$؛ البيتكوين قبل العمولة)')
for (mk,tf),g in R.groupby(['market','tf'],sort=False):
    te=g[g.year>=(2021 if mk=='gold' else 2023)]
    for lab,x in [('اختبار',te),('اختبار + مع الترند',te[te.trend==1]),('كل السنين',g)]:
        if len(x)==0: continue
        print(f"{mk} {tf:3s} {lab:18s} n={len(x):5d} | 2R {(x.r2>0).mean()*100:5.1f}% R{x.r2.mean():+.3f} | 3R {(x.r3>0).mean()*100:5.1f}% R{x.r3.mean():+.3f} | للمنطقة المعاكسة R{x.rz.mean():+.3f}")
