# مناطق بدل علامات: بعد إشارة King تُرسم منطقة دخول (بين الدخول والوقف) — هل الدخول عند رجوع السعر لها أفضل؟
import pandas as pd, numpy as np, re, json
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
exec(open(S+'/ai/king_tiers.py').read().split("src=open('/home/user/AAB/lib/analysis/king_model.dart')")[0])
src=open('/home/user/AAB/lib/analysis/king_model.dart').read()
feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
mm=load_model('/home/user/AAB/lib/analysis/king_model.dart','king')
Q70,Q85=0.5680950185109677,0.5909170281481894
@njit
def sim(o,h,l,c,a,i,d,frac,wait,SP):
    # الإشارة عند إغلاق i. الوقف خلف أدنى/أعلى 3 شموع (مثل اختباراتنا). الدخول المباشر: افتتاح i+1.
    # المنطقة: من الدخول المباشر نحو الوقف بنسبة frac من المخاطرة — أمر معلّق ينتظر wait شمعة.
    n=len(c); e0=o[i+1]
    ext=l[i] if d>0 else h[i]
    for j in range(i-2,i+1):
        ext=min(ext,l[j]) if d>0 else max(ext,h[j])
    rk=min(max((e0-ext)*d+0.1*a[i],0.7*a[i]),2.5*a[i])
    st=e0-d*rk; tp1=e0+d*rk; tp2=e0+2*d*rk
    e=e0-d*frac*rk
    k0=i+1
    if frac>0:
        k0=-1
        for j in range(i+1,min(n,i+1+wait)):
            if (d>0 and l[j]<=e) or (d<0 and h[j]>=e): k0=j; break   # الدخول أولاً (المنطقة قبل الوقف دائماً)
        if k0<0: return np.nan,np.nan                                          # لم يرجع للمنطقة
    r=(e-st)*d
    got=False; stop=st
    for j in range(k0,min(n,k0+300)):
        if (d>0 and l[j]<=stop) or (d<0 and h[j]>=stop): return (0.5*(tp1-e)*d/r if got else -1.0)-SP/r, (0.5*(tp1-e)*d if got else -r)-SP
        if j==k0 and frac>0: continue
        if not got and ((d>0 and h[j]>=tp1) or (d<0 and l[j]<=tp1)): got=True; stop=e
        if got and ((d>0 and h[j]>=tp2) or (d<0 and l[j]<=tp2)): return (0.5*(tp1-e)*d+0.5*(tp2-e)*d)/r-SP/r, 0.5*(tp1-e)*d+0.5*(tp2-e)*d-SP
    return np.nan,np.nan
s2=pd.read_csv(S+'/ai/signals2.csv'); key=pd.read_csv(S+'/ai/sdkey.csv')
s2['p']=predict(mm,s2[feat].values.astype(np.float32))
print('النتيجة بالـ R (لكل صفقة) وبالدولار مقسوماً على مخاطرة الدخول المباشر (ربح فعلي مقارن)')
for mk,tf,f,SP in [('gold20','15m','gold20/xau20_15m.csv',0.25),('gold20','1h','gold20/xau20_1h.csv',0.25),('btc','15m','gold10/btc10_15m.csv',0.0),('btc','1h','gold10/btc10_1h.csv',0.0)]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]
    o,h,l,c=[d[x].values.astype(np.float64) for x in ['open','high','low','close']]
    pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    m=((key.market==mk)&(key.tf==tf)).values&((s2.year>=(2019 if mk=='gold20' else 2021)).values)&(s2.p.values>=Q70)
    ii=key.i.values[m]; dd=key.dir.values[m]; strong=s2.p.values[m]>=Q85
    print(f'== {mk} {tf} (King ⭐+، اختبار) إشارات {m.sum()}')
    for frac,wait,lab in [(0,0,'دخول مباشر (العلامة)'),(0.25,6,'منطقة: رجوع 25% خلال 6 شموع'),(0.5,6,'منطقة: رجوع 50% خلال 6 شموع'),(0.5,12,'منطقة: رجوع 50% خلال 12 شمعة'),(0.75,12,'منطقة: رجوع 75% خلال 12 شمعة')]:
        R=[];U=[];base=[]
        for i,dir_ in zip(ii,dd):
            if i+2>=len(c): continue
            r,usd=sim(o,h,l,c,a,int(i),int(dir_),frac,wait,SP)
            r0,u0=sim(o,h,l,c,a,int(i),int(dir_),0.0,0,SP)
            if np.isnan(r0): continue
            base.append(abs(u0) if r0<0 else 1)
            if np.isnan(r): continue
            R.append(r); U.append(usd)
        R=np.array(R); n=len(ii)
        print(f'  {lab:32s} دخلت {len(R)/max(n,1)*100:5.1f}% | نجاح {(R>0).mean()*100:5.1f}% | R/صفقة {R.mean():+.3f} | الربح الكلي نسبة للمباشر: ' + (f'{np.sum(U):+.0f}$' ))
