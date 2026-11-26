# هل منطقة الدخول (رجوع 50% خلال 12 شمعة) تقلب الاستراتيجيات الفاشلة لرابحة؟ — 139 استراتيجية × ذهب/بيتكوين
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
exec(open(S+'/ai/mass.py').read().split("SEL=[")[0])
@njit
def batch(o,h,l,c,a,sig,frac,wait,SP,start):
    n=len(c); R=np.full(n,np.nan)
    for i in range(max(start,3),n-2):
        d=sig[i]
        if d==0 or not a[i]>0: continue
        e0=o[i+1]; ext=l[i] if d>0 else h[i]
        for j in range(i-2,i+1): ext=min(ext,l[j]) if d>0 else max(ext,h[j])
        rk=min(max((e0-ext)*d+0.1*a[i],0.7*a[i]),2.5*a[i])
        st=e0-d*rk; tp1=e0+d*rk; tp2=e0+2*d*rk; e=e0-d*frac*rk; k0=i+1
        if frac>0:
            k0=-1
            for j in range(i+1,min(n,i+1+wait)):
                # الدخول أولاً: السعر يمر بالمنطقة قبل الوقف دائماً (الوقف أبعد)، فإن لمس الوقف في نفس الشمعة تُحسب خسارة
                if (d>0 and l[j]<=e) or (d<0 and h[j]>=e): k0=j; break
            if k0<0: continue
        r=(e-st)*d; got=False; stop=st; res=np.nan
        for j in range(k0,min(n,k0+300)):
            # محافظ: الوقف يُفحص أولاً حتى في شمعة الدخول، والأهداف لا تُحسب في شمعة الدخول
            if (d>0 and l[j]<=stop) or (d<0 and h[j]>=stop): res=(0.5*(tp1-e)*d/r if got else -1.0); break
            if j==k0: continue
            if not got and ((d>0 and h[j]>=tp1) or (d<0 and l[j]<=tp1)): got=True; stop=e
            if got and ((d>0 and h[j]>=tp2) or (d<0 and l[j]<=tp2)): res=(0.5*(tp1-e)*d+0.5*(tp2-e)*d)/r; break
        if not np.isnan(res): R[i]=res-SP/r
    return R
rows=[]
for label,f,ty,SP in [('ذهب 15m','gold20/xau20_15m.csv',2019,0.25),('ذهب 1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين 15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين 1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=load(f'{S}/{f}'); st,(o,h,l,c,a)=strategies(d)
    yr=d.time.dt.year.values; start=int(np.argmax(yr>=ty))
    rng_=np.random.RandomState(7)
    for q in range(5):
        rs=np.zeros(len(c),np.int64); idx=rng_.choice(np.arange(300,len(c)-3),size=max(1,len(c)//20),replace=False); rs[idx]=rng_.choice([-1,1],size=len(idx))
        st[f'عشوائي {q+1}']=rs
    for nm,s in st.items():
        if nm.endswith(('مع الترند','ADX>25','عكس الترند')): continue
        s=s.astype(np.int64)
        r0=batch(o,h,l,c,a,s,0.0,0,SP,start); r5=batch(o,h,l,c,a,s,0.5,12,SP,start)
        n=int((s[start:]!=0).sum())
        if n<50: continue
        a0=r0[~np.isnan(r0)]; a5=r5[~np.isnan(r5)]
        rows.append([label,nm,n,a0.mean(),a0.sum(),len(a5)/n,a5.mean() if len(a5) else np.nan,a5.sum()])
    print('done',label,file=sys.stderr,flush=True)
T=pd.DataFrame(rows,columns=['سوق','استراتيجية','إشارات','مباشر R','مباشر مجموع','دخلت المنطقة','منطقة R','منطقة مجموع'])
T.to_csv(S+'/ai/zones_failed3.csv',index=False)
print('اختبار (ذهب 2019+ بعد السبريد، بيتكوين 2021+)')
for lab,G in T.groupby('سوق',sort=False):
    print(f"== {lab}: {len(G)} استراتيجية | مباشر موجب: {(G['مباشر R']>0).sum()} | منطقة موجبة: {(G['منطقة R']>0).sum()} | متوسط مباشر R{G['مباشر R'].mean():+.3f} ← منطقة R{G['منطقة R'].mean():+.3f}")
# الثبات: استراتيجيات موجبة بالمنطقة في الأسواق الأربعة
P=T.pivot_table(index='استراتيجية',columns='سوق',values='منطقة R')
good=P[(P>0.05).all(axis=1)]
print('\nموجبة بالمنطقة (> +0.05R) في الأسواق الأربعة كلها:',len(good))
print(good.round(3).sort_values(by=list(good.columns)[0],ascending=False).head(20).to_string())
P0=T.pivot_table(index='استراتيجية',columns='سوق',values='مباشر R')
print('\nللمقارنة — موجبة بالدخول المباشر في الأربعة:',int(((P0>0.05).all(axis=1)).sum()))

R=T[T['استراتيجية'].str.startswith('عشوائي')]
print('\nالتحقق — إشارات عشوائية:'); print(R[['سوق','استراتيجية','مباشر R','دخلت المنطقة','منطقة R']].round(3).to_string(index=False))
