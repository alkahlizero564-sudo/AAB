# حل السبريد: (1) حد أدنى للوقف بالدولار (2) تجاهل الصفقات ذات الوقف الصغير — King ⭐+ ذهب 15m/1h من 2021، سبريد 0.25$
import pandas as pd, numpy as np, re, json
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
exec(open(S+'/ai/king_tiers.py').read().split("src=open('/home/user/AAB/lib/analysis/king_model.dart')")[0])
src=open('/home/user/AAB/lib/analysis/king_model.dart').read(); feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
mm=load_model('/home/user/AAB/lib/analysis/king_model.dart','king')
Q70,Q85=0.5680950185109677,0.5909170281481894
s=pd.read_csv(S+'/ai/signals2.csv'); key=pd.read_csv(S+'/ai/sdkey.csv'); s['p']=predict(mm,s[feat].values.astype(np.float32))
@njit
def sim(o,h,l,c,a,i,d,minst,SP,t1m,t2m):
    n=len(c); e=o[i+1]; ext=l[i] if d>0 else h[i]
    for j in range(i-2,i+1): ext=min(ext,l[j]) if d>0 else max(ext,h[j])
    rk=min(max((e-ext)*d+0.1*a[i],0.7*a[i]),2.5*a[i]); rk=max(rk,minst)
    st=e-d*rk; t1=e+d*t1m*rk; t2=e+d*t2m*rk; got=False; stop=st
    for j in range(i+1,min(n,i+600)):
        if (d>0 and l[j]<=stop) or (d<0 and h[j]>=stop): return ((0.5*t1m*rk if got else -rk)-SP), rk
        if not got and ((d>0 and h[j]>=t1) or (d<0 and l[j]<=t1)): got=True; stop=e
        if got and ((d>0 and h[j]>=t2) or (d<0 and l[j]<=t2)): return (0.5*t1m*rk+0.5*t2m*rk-SP), rk
    return np.nan, rk
for tf,f in [('15m','gold20/xau20_15m.csv'),('1h','gold20/xau20_1h.csv')]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    m=((key.market=='gold20')&(key.tf==tf)).values&(s.p.values>=Q70)
    ii=key.i.values[m]; dd=key.dir.values[m]; pp=s.p.values[m]
    sel=t.dt.year.values[ii]>=2021; ii,dd,pp=ii[sel],dd[sel],pp[sel]
    print(f'\n== ذهب {tf} King ⭐+ (2021 → 2025): {len(ii)} إشارة | النتيجة بالدولار لكل أوقية (= لوت 0.01) بعد السبريد')
    for minst in [0,2,3,4,5,6]:
        for t1m,t2m in [(1,2),(1,3)]:
            R=[];RK=[]
            for i,di in zip(ii,dd):
                if i+2>=len(c): continue
                r,rk=sim(o,h,l,c,a,int(i),int(di),float(minst),0.25,float(t1m),float(t2m)); R.append(r); RK.append(rk)
            R=np.array(R); RK=np.array(RK); k=~np.isnan(R)
            print(f'   أقل وقف {minst}$ | أهداف {t1m}R/{t2m}R: نجاح {(R[k]>0).mean()*100:5.1f}% | {R[k].mean():+.2f}$/صفقة | بالـR {(R[k]/RK[k]).mean():+.3f} | مجموع لوت 0.01: {R[k].sum():+.0f}$')
    # الفلتر: تجاهل الوقف الصغير (بدون توسيع)
    R=[];RK=[]
    for i,di in zip(ii,dd):
        if i+2>=len(c): continue
        r,rk=sim(o,h,l,c,a,int(i),int(di),0.0,0.25,1.0,2.0); R.append(r); RK.append(rk)
    R=np.array(R); RK=np.array(RK)
    for lim in [2,3,4]:
        k=(~np.isnan(R))&(RK>=lim)
        print(f'   فلتر: فقط الصفقات بوقف ≥ {lim}$: {k.sum()} صفقة | نجاح {(R[k]>0).mean()*100:5.1f}% | {R[k].mean():+.2f}$/صفقة | مجموع {R[k].sum():+.0f}$')
