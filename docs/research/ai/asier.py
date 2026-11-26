# ASIER — رادار الإنهاك والاختلال: الجهد مقابل النتيجة + مناطق الاختلال (FVG) + تأكيد شمعة → انعكاس
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
sets=[('gold','5m','m1/xau_5m.csv',0.25),('gold','15m','gold20/xau20_15m.csv',0.25),('gold','1h','gold20/xau20_1h.csv',0.25),
      ('btc','15m','gold10/btc10_15m.csv',0.0),('btc','1h','gold10/btc10_1h.csv',0.0)]
rows=[]
for mk,tf,f,SP in sets:
    d=pd.read_csv(f'{S}/{f}'); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'}); d['time']=pd.to_datetime(d.time)
    d=d.sort_values('time').drop_duplicates('time').reset_index(drop=True)
    o,h,l,c,v=[d[x].values.astype(np.float64) for x in ['open','high','low','close','volume']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    e200=pd.Series(c).ewm(span=200,adjust=False).mean().values
    rng=np.maximum(h-l,1e-12)
    vr=v/np.maximum(pd.Series(v).rolling(50).mean().values,1e-9)
    # الجهد: (مدى الشمعة/ATR) × (الحجم/متوسطه) — النتيجة: التقدم الصافي/المدى في اتجاه الموجة
    effort=(rng/a)*np.where(np.isnan(vr),1,np.clip(vr,0.2,5))
    run=(c-np.r_[c[:8],c[:-8]])/a        # الموجة: تقدم 8 شموع بوحدات ATR
    rs=np.sign(run)
    result=((c-o)*rs)/rng                 # كم من الشمعة تقدّم مع الموجة (سالب = رفض)
    wick=np.where(rs>0,(h-np.maximum(o,c))/rng,(np.minimum(o,c)-l)/rng)   # ذيل الرفض ضد الموجة
    hi20=pd.Series(h).rolling(20).max().values; lo20=pd.Series(l).rolling(20).min().values
    at_ext=np.where(rs>0,h>=hi20,l<=lo20)
    # رادار 0..100: ترتيب مئوي (نافذة 500) لمركّب: قوة الموجة × الجهد × (1 − النتيجة) × الذيل
    comp=np.abs(run)*effort*np.clip(1-result,0,2)*(0.5+wick)*at_ext
    radar=pd.Series(comp).rolling(500,min_periods=200).rank(pct=True).values*100
    # مناطق الاختلال (FVG): تُحفظ وتُستعمل كمستوى عند العودة
    yr=d.time.dt.year.values
    last=-99
    for i in range(520,n-2):
        if i-last<4: continue
        # الإنهاك في الشمعة i-1 (رادار ≥ 80، ضد الموجة) ثم تأكيد في i: شمعة عكسية تغلق خلف منتصف شمعة الإنهاك
        j=i-1
        if not radar[j]>=80: continue
        dd=-int(rs[j])      # اتجاه الانعكاس
        if dd==0: continue
        mid=(h[j]+l[j])/2
        conf=(c[i]<mid and c[i]<o[i]) if dd<0 else (c[i]>mid and c[i]>o[i])
        if not conf: continue
        # سياق: لا انعكاس ضد ترند قوي جداً (السعر بعيد عن EMA200 بأكثر من 6 ATR في اتجاه الموجة)
        strong=((c[i]-e200[i])*(-dd))/a[i]>6
        # FVG قريب في اتجاه الانعكاس خلال آخر 30 شمعة (فراغ تركه الاندفاع)
        fvg=0
        for k in range(i-30,i-1):
            if dd<0 and l[k+1]>h[k-1]: fvg=1
            if dd>0 and h[k+1]<l[k-1]: fvg=1
        ext=max(h[j],h[i]) if dd<0 else min(l[j],l[i])
        stop=ext-dd*0.2*a[i]
        r1,rk=ex(h,l,o,i,dd,stop,1.0)
        if np.isnan(r1): continue
        r2,_=ex(h,l,o,i,dd,stop,2.0); r3,_=ex(h,l,o,i,dd,stop,3.0)
        cost=SP/rk; last=i
        rows.append([mk,tf,int(yr[i]),dd,int(strong),fvg,radar[j],r1-cost,r2-cost,r3-cost])
    print('done',mk,tf,file=sys.stderr,flush=True)
R=pd.DataFrame(rows,columns=['mk','tf','year','dir','strong','fvg','radar','r1','r2','r3'])
R.to_csv(S+'/ai/asier.csv',index=False)
print('اختبار (ذهب 2019+ بعد سبريد 0.25$، بيتكوين 2021+ قبل العمولة) — التعادل: 1R 50% • 2R 33% • 3R 25%')
def show(lab,x,days):
    if len(x)<30: print(f'  {lab:34s} n={len(x)} (قليل)'); return
    print(f"  {lab:34s} n={len(x):5d} ({len(x)/days:4.2f}/يوم) | 1R {(x.r1>0).mean()*100:5.1f}% R{x.r1.mean():+.3f} | 2R {(x.r2>0).mean()*100:5.1f}% R{x.r2.mean():+.3f} | 3R R{x.r3.mean():+.3f}")
for (mk,tf),G in R.groupby(['mk','tf'],sort=False):
    T=G[G.year>=(2019 if mk=='gold' else 2021)]; days=T.year.nunique()*(252 if mk=='gold' else 365)
    print(f'== {mk} {tf}')
    show('الكل (رادار ≥80 + تأكيد)',T,days)
    show('بدون الانعكاس ضد ترند قوي',T[T.strong==0],days)
    show('+ منطقة اختلال (FVG) قريبة',T[(T.strong==0)&(T.fvg==1)],days)
    show('رادار ≥95',T[(T.strong==0)&(T.radar>=95)],days)
