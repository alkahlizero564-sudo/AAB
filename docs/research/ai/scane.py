# SCANE — لجنة 4 خبراء بأوزان تتعلم ذاتياً (مكافأة/عقاب + نسيان) — بلا نظر للمستقبل
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
@njit
def engine(o,h,l,c,a,E,eta,lam,thr,gate,k):
    # E: (n,4) إشارات الخبراء −1/0/+1 عند إغلاق الشمعة. صفقة افتراضية: دخول افتتاح التالية، هدف/وقف k×ATR
    n=len(c); m=E.shape[1]
    w=np.ones(m)
    # صفقات افتراضية مفتوحة لكل خبير: (اتجاه، دخول، هدف، وقف، فعّال)
    ed=np.zeros((m,64)); ee=np.zeros((m,64)); et=np.zeros((m,64)); es=np.zeros((m,64)); ea=np.zeros((m,64),np.bool_)
    # صفقات SCANE نفسه
    sd=np.zeros(4096); se=np.zeros(4096); st=np.zeros(4096); ss=np.zeros(4096); sa=np.zeros(4096,np.bool_); si=np.zeros(4096,np.int64); ns=0
    res=np.full(n,-9.0); conf=np.zeros(n); sig=np.zeros(n,np.int64); dom=np.zeros(n,np.int64)
    hist=np.zeros(50); hn=0; hp=0
    last=-99
    for i in range(1,n-1):
        # 1) تحديث نتائج الصفقات الافتراضية بالشمعة i (مغلقة) ثم الأوزان
        for x in range(m):
            for q in range(64):
                if not ea[x,q]: continue
                d=ed[x,q]
                hitT=(d>0 and h[i]>=et[x,q]) or (d<0 and l[i]<=et[x,q])
                hitS=(d>0 and l[i]<=es[x,q]) or (d<0 and h[i]>=es[x,q])
                if hitS or hitT:
                    win=hitT and not hitS
                    w[x]=w[x]*np.exp(eta if win else -eta)
                    ea[x,q]=False
        # نسيان: الأوزان ترجع تدريجياً نحو 1
        for x in range(m): w[x]=w[x]**(1-lam)
        for q in range(ns):
            if not sa[q]: continue
            d=sd[q]
            hitT=(d>0 and h[i]>=st[q]) or (d<0 and l[i]<=st[q]); hitS=(d>0 and l[i]<=ss[q]) or (d<0 and h[i]>=ss[q])
            if hitS or hitT:
                r=1.0 if (hitT and not hitS) else -1.0
                res[si[q]]=r; sa[q]=False
                hist[hp]=1.0 if r>0 else 0.0; hp=(hp+1)%50; hn=min(hn+1,50)
        if not a[i]>0 or i>=n-1: continue
        # 2) إشارات الخبراء الجديدة → صفقات افتراضية
        e=o[i+1]; dd=k*a[i]
        for x in range(m):
            s=E[i,x]
            if s==0: continue
            for q in range(64):
                if not ea[x,q]:
                    ed[x,q]=s; ee[x,q]=e; et[x,q]=e+s*dd; es[x,q]=e-s*dd; ea[x,q]=True; break
        # 3) الإجماع الموزون
        num=0.0; den=0.0; best=0; bw=-1.0
        for x in range(m):
            den+=w[x]; num+=w[x]*E[i,x]
            if w[x]>bw: bw=w[x]; best=x
        sc=num/den; conf[i]=abs(sc); dom[i]=best
        okrate=True
        if gate>0 and hn>=20:
            okrate=hist[:hn].mean()>=gate
        if abs(sc)>=thr and okrate and i-last>=3:
            s=1 if sc>0 else -1
            sig[i]=s; last=i
            if ns<4096:
                sd[ns]=s; se[ns]=e; st[ns]=e+s*dd; ss[ns]=e-s*dd; sa[ns]=True; si[ns]=i; ns+=1
            else:
                # إعادة استعمال الخانات المغلقة
                for q in range(4096):
                    if not sa[q]:
                        sd[q]=s; se[q]=e; st[q]=e+s*dd; ss[q]=e-s*dd; sa[q]=True; si[q]=i; break
    return sig,res,conf,dom
sets=[('gold','5m','m1/xau_5m.csv',0.25),('gold','15m','gold20/xau20_15m.csv',0.25),('gold','1h','gold20/xau20_1h.csv',0.25),
      ('btc','15m','gold10/btc10_15m.csv',0.0),('btc','1h','gold10/btc10_1h.csv',0.0)]
names=['زخم/اختراق','ارتداد/سحب','كفاءة الاتجاه','تذبذب/حجم']
print('SCANE (اختبار: ذهب 2019+ بعد سبريد 0.25$، بيتكوين 2021+) — الهدف = الوقف = 1.5 ATR (التعادل 50%)')
for mk,tf,f,SP in sets:
    d=pd.read_csv(f'{S}/{f}'); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'}); d['time']=pd.to_datetime(d.time)
    d=d.sort_values('time').drop_duplicates('time').reset_index(drop=True)
    o,h,l,c,v=[d[x].values.astype(np.float64) for x in ['open','high','low','close','volume']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    cs=pd.Series(c); e20=cs.ewm(span=20,adjust=False).mean().values; e50=cs.ewm(span=50,adjust=False).mean().values
    hh=pd.Series(h).rolling(20).max().shift(1).values; ll=pd.Series(l).rolling(20).min().shift(1).values
    dl=np.diff(c,prepend=c[0]); W=lambda s,p: pd.Series(s).ewm(alpha=1/p,adjust=False).mean().values
    r2=100-100/(1+W(np.clip(dl,0,None),2)/np.maximum(W(np.clip(-dl,0,None),2),1e-12))
    er=np.abs(c-np.r_[c[:20],c[:-20]])/np.maximum(pd.Series(np.abs(dl)).rolling(20).sum().values,1e-12)
    vr=v/np.maximum(pd.Series(v).rolling(50).mean().values,1e-9); rng=h-l
    sh=lambda x: np.r_[x[:1],x[:-1]]
    E1=np.where((c>hh)&(sh(c)<=sh(hh)),1,np.where((c<ll)&(sh(c)>=sh(ll)),-1,0))
    E2=np.where(((l<ll)&(c>ll))|(r2<5),1,np.where(((h>hh)&(c<hh))|(r2>95),-1,0))
    tU=(er>0.3)&(e20>e50); tD=(er>0.3)&(e20<e50)
    E3=np.where(tU&~sh(tU),1,np.where(tD&~sh(tD),-1,0))
    E4=np.where((rng>1.5*a)&(vr>1.5)&(c>o),1,np.where((rng>1.5*a)&(vr>1.5)&(c<o),-1,0))
    E=np.nan_to_num(np.column_stack([E1,E2,E3,E4])).astype(np.float64); E[:250]=0
    yr=d.time.dt.year.values; ty=2019 if mk=='gold' else 2021; days=len(np.unique(yr[yr>=ty]))*(252 if mk=='gold' else 365)
    for thr,gate,eta,lam in [(0.65,0.0,0.1,0.02),(0.65,0.45,0.1,0.02),(0.7,0.45,0.2,0.05),(0.65,0.5,0.05,0.01)]:
        sig,res,conf,dom=engine(o,h,l,c,a,E,eta,lam,thr,gate,1.5)
        m=(sig!=0)&(res>-9)&(yr>=ty)
        r=res[m]; cost=SP/(1.5*a[m]); net=r-cost
        dm=np.bincount(dom[m],minlength=4)/max(m.sum(),1)
        print(f"  {mk} {tf:3s} ثقة≥{thr} بوابة≥{gate} تعلم {eta}/{lam}: n={m.sum():6d} ({m.sum()/days:5.2f}/يوم) | نجاح {(r>0).mean()*100:5.1f}% صافي R{net.mean():+.3f} | المسيطر: {names[int(np.argmax(dm))]} {dm.max()*100:.0f}%")
    # كل خبير وحده (للمقارنة)
    for x in range(4):
        Ex=np.zeros_like(E); Ex[:,x]=E[:,x]
        sig,res,_,_=engine(o,h,l,c,a,Ex,0.0,0.0,0.99,0.0,1.5)
        m=(sig!=0)&(res>-9)&(yr>=ty); r=res[m]
        print(f"      خبير {names[x]:12s} وحده: n={m.sum():6d} نجاح {(r>0).mean()*100:5.1f}% صافي R{(r-SP/(1.5*a[m])).mean():+.3f}")
    sys.stdout.flush()
