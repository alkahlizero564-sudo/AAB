# منطقة الاتجاه بهيكل السوق: أخضر (قمة أعلى + قاع أعلى)، أحمر (قمة أدنى + قاع أدنى)، رمادي غير ذلك — ونسخة "آخر كسر هيكل"
import pandas as pd, numpy as np, sys
exec(open('spread.py').read().split("for tf,f in")[0])      # sim + King (s,key,Q70)
def zones(h,l,c,k):
    n=len(c); hh=[];ll=[]; z1=np.zeros(n,int); z2=np.zeros(n,int); res=np.nan; sup=np.nan; last=0
    for i in range(2*k,n):
        j=i-k                                         # القمة/القاع تتأكد بعد k شموع (بلا نظر للمستقبل)
        if h[j]==h[j-k:j+k+1].max(): hh.append(h[j]); res=h[j]
        if l[j]==l[j-k:j+k+1].min(): ll.append(l[j]); sup=l[j]
        if len(hh)>=2 and len(ll)>=2:
            if hh[-1]>hh[-2] and ll[-1]>ll[-2]: z1[i]=1
            elif hh[-1]<hh[-2] and ll[-1]<ll[-2]: z1[i]=-1
        if not np.isnan(res) and c[i]>res: last=1; res=np.nan
        elif not np.isnan(sup) and c[i]<sup: last=-1; sup=np.nan
        z2[i]=last
    return z1,z2
for mk,mkk,tf,f,ty,SP in [('ذهب','gold20','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','gold20','1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين','btc','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','btc','1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; n=len(c); pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    yr=t.dt.year.values; te=yr>=ty
    fwd=np.r_[(c[20:]-c[:-20])/a[:-20],np.full(20,np.nan)]
    # King
    m=((key.market==mkk)&(key.tf==tf)).values&(s.p.values>=Q70)
    KI=[];KD=[];KR=[]
    for i,di in zip(key.i.values[m],key.dir.values[m]):
        if yr[i]<ty or i+2>=n: continue
        g,rk=sim(o,h,l,c,a,int(i),int(di),0.0,SP,1.0,3.0); KI.append(i); KD.append(di); KR.append(g/rk)
    KI=np.array(KI); KD=np.array(KD); KR=np.array(KR); ok=~np.isnan(KR); KI,KD,KR=KI[ok],KD[ok],KR[ok]
    print(f'\n== {mk} {tf} (اختبار) — King كل الإشارات: {KR.mean():+.3f}R ({len(KR)} صفقة)')
    for k in (3,5,10):
        z1,z2=zones(h,l,c,k)
        for nm,z in [(f'هيكل (قمم وقيعان، k={k})',z1),(f'آخر كسر هيكل (k={k})',z2)]:
            zt=z[te]; ft=fwd[te]
            g=(zt==1).mean()*100; r=(zt==-1).mean()*100
            runs=np.diff(np.flatnonzero(np.r_[True,zt[1:]!=zt[:-1],True])); 
            ok2=~np.isnan(ft)
            right=np.r_[(ft[(zt==1)&ok2]>0),(ft[(zt==-1)&ok2]<0)].mean()*100
            mv=np.r_[ft[(zt==1)&ok2],-ft[(zt==-1)&ok2]].mean()
            kz=z[KI]*KD
            w=KR[kz==1]; ag=KR[kz==-1]; gr=KR[kz==0]
            print(f'   {nm:28s} أخضر {g:4.1f}% أحمر {r:4.1f}% رمادي {100-g-r:4.1f}% | تقعد {runs.mean():5.1f} شمعة | صحة بعد 20 شمعة {right:4.1f}% ({mv:+.2f} ATR) | King: مع المنطقة {w.mean():+.3f}R ({len(w)}) • عكسها {ag.mean() if len(ag) else np.nan:+.3f}R ({len(ag)}) • رمادي {gr.mean() if len(gr) else np.nan:+.3f}R ({len(gr)})')
