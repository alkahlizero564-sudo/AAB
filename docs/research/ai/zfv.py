# مناطق خضراء/حمراء من الفيبوناتشي (0.5-0.618) والفوليوم بروفايل (POC الموجة) — محاكاة محافظة + مقارنة عشوائية
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
@njit
def trade(h,l,start,d,e,st,tp1,tp2,wait):
    # أمر معلّق عند e: الدخول أولاً، ولو لمست شمعة الدخول الوقف = خسارة؛ لا أهداف في شمعة الدخول. نصف عند TP1 والوقف للدخول ثم TP2.
    n=len(h); k0=-1
    for j in range(start,min(n,start+wait)):
        if (d>0 and l[j]<=e) or (d<0 and h[j]>=e): k0=j; break
    if k0<0: return np.nan
    r=(e-st)*d
    if r<=0: return np.nan
    got=False; stop=st
    for j in range(k0,min(n,k0+500)):
        if (d>0 and l[j]<=stop) or (d<0 and h[j]>=stop): return 0.5*(tp1-e)*d/r if got else -1.0
        if j==k0: continue
        if not got and ((d>0 and h[j]>=tp1) or (d<0 and l[j]<=tp1)): got=True; stop=e
        if got and ((d>0 and h[j]>=tp2) or (d<0 and l[j]<=tp2)): return (0.5*(tp1-e)*d+0.5*(tp2-e)*d)/r
    return np.nan
rows=[]
for mk,tf,f,ty,SP in [('ذهب','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=pd.read_csv(f'{S}/{f}'); d.columns=[x.lower() for x in d.columns]
    o,h,l,c,v=[d[x].values.astype(np.float64) for x in ['open','high','low','close','volume']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    yr=pd.to_datetime(d.iloc[:,0]).dt.year.values
    k=5; PH=[];PL=[]; used=set(); rs=np.random.RandomState(3)
    for i in range(300,n-2):
        j=i-k
        if h[j]==h[j-k:j+k+1].max(): PH.append(j)
        if l[j]==l[j-k:j+k+1].min(): PL.append(j)
        if not PH or not PL: continue
        ph,pl=PH[-1],PL[-1]
        # الموجة المكتملة الأخيرة: صاعدة (قاع ثم قمة) أو هابطة (قمة ثم قاع)، طولها ≥ 3 ATR
        if pl<ph: dd=1; lo,hi=l[pl],h[ph]; s0,s1=pl,ph
        else: dd=-1; lo,hi=l[pl],h[ph]; s0,s1=ph,pl
        leg=hi-lo
        if leg<3*a[s1] or (s1,dd) in used or i-s1>40: continue
        used.add((s1,dd))
        # مستويات الفيبو (الرجوع من نهاية الموجة)
        fib=lambda x: hi-x*leg if dd>0 else lo+x*leg
        z_top,z_bot=fib(0.5),fib(0.618)          # المنطقة الذهبية
        stop=fib(0.786)-dd*0.1*a[s1]
        tp1=hi if dd>0 else lo                    # نهاية الموجة (100%)
        tp2=fib(-0.272)                           # امتداد 1.272
        # الفوليوم بروفايل للموجة: POC
        seg=slice(min(s0,s1),max(s0,s1)+1); px=(h[seg]+l[seg]+c[seg])/3
        bins=np.linspace(lo,hi,31); hist,_=np.histogram(px,bins=bins,weights=v[seg]+1e-9); m=int(np.argmax(hist)); poc=(bins[m]+bins[m+1])/2
        poc_in=(min(z_top,z_bot)-0.2*a[s1])<=poc<=(max(z_top,z_bot)+0.2*a[s1])
        # الدخول عند حافة المنطقة القريبة (0.5)، ينتظر 60 شمعة من الآن
        start=i+1
        r_fib=trade(h,l,start,dd,z_top,stop,tp1,tp2,60)
        r_poc=trade(h,l,start,dd,poc,stop,tp1,tp2,60) if (poc-stop)*dd>0.3*a[s1] and (tp1-poc)*dd>0.3*a[s1] else np.nan
        r_rev=trade(h,l,start,-dd,z_top,fib(0.382)+dd*0.1*a[s1] if False else z_top+(z_top-stop),z_top-(tp1-z_top),z_top-(tp2-z_top),60)  # عكس الاتجاه (للمقارنة)
        # عشوائي: نفس المنطقة لكن اتجاه عشوائي
        rd=1 if rs.rand()<0.5 else -1
        r_rnd=trade(h,l,start,dd,z_top,stop,tp1,tp2,60) if rd==dd else trade(h,l,start,-dd,z_top,z_top+(z_top-stop),z_top-(tp1-z_top),z_top-(tp2-z_top),60)
        cost=SP/max(abs(z_top-stop),1e-9)
        rows.append([mk,tf,int(yr[i]),int(poc_in),r_fib-cost,r_poc-cost if not np.isnan(r_poc) else np.nan,r_rev-cost,r_rnd-cost])
    print('done',mk,tf,file=sys.stderr,flush=True)
R=pd.DataFrame(rows,columns=['mk','tf','year','poc_in','fib','poc','rev','rnd'])
R.to_csv(S+'/ai/zfv.csv',index=False)
def show(lab,x):
    x=x.dropna()
    if len(x)<30: print(f'    {lab:38s} n={len(x)} (قليل)'); return
    print(f'    {lab:38s} n={len(x):5d} | نجاح {(x>0).mean()*100:5.1f}% | R/صفقة {x.mean():+.3f}')
print('اختبار (ذهب 2019+ بعد السبريد، بيتكوين 2021+) — محاكاة محافظة')
for (mk,tf),G in R.groupby(['mk','tf'],sort=False):
    T=G[G.year>=(2019 if mk=='ذهب' else 2021)]; Tr=G[G.year<(2019 if mk=='ذهب' else 2021)]
    print(f'== {mk} {tf}')
    show('فيبو 0.5-0.618 (المنطقة الذهبية)',T.fib)
    show('فيبو + POC داخل المنطقة',T[T.poc_in==1].fib)
    show('الدخول عند POC الموجة',T.poc)
    show('عكس الاتجاه (للمقارنة)',T.rev)
    show('اتجاه عشوائي (للمقارنة)',T.rnd)
    show('[تدريب] فيبو + POC',Tr[Tr.poc_in==1].fib)
