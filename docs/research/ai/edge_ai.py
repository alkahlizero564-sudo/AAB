# ذكاء اصطناعي مستقل (مثل Edge Algo): يقرأ كل شمعة ويقرر شراء/بيع/لا شيء — هدف ووقف 1.5 ATR (1R) ثم 2R
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
import lightgbm as lgb
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
@njit
def race(h,l,o,a,k,H):
    # 1: +k*ATR قبل −k*ATR، 0: العكس، -1: لا هذا ولا ذاك خلال H شمعة — للشراء وللبيع
    n=len(h); up=np.full(n,-1,np.int8); dn=np.full(n,-1,np.int8); up2=np.full(n,-1,np.int8); dn2=np.full(n,-1,np.int8)
    for i in range(n-1):
        e=o[i+1]; d=k*a[i]
        if not d>0: continue
        uh=e+d; ul=e-d; u2=e+2*d
        ru=-1; rd=-1; r2u=-1; r2d=-1
        for j in range(i+1,min(n,i+1+H)):
            hu=h[j]>=uh; hd=l[j]<=ul
            if ru==-1:
                if hd and hu: ru=0
                elif hu: ru=1
                elif hd: ru=0
            if rd==-1:
                if hd and hu: rd=0
                elif hd: rd=1
                elif hu: rd=0
            if r2u==-1:
                if l[j]<=ul: r2u=0
                elif h[j]>=u2: r2u=1
            if r2d==-1:
                if h[j]>=uh: r2d=0
                elif l[j]<=e-2*d: r2d=1
            if ru!=-1 and rd!=-1 and r2u!=-1 and r2d!=-1: break
        up[i]=ru; dn[i]=rd; up2[i]=r2u; dn2[i]=r2d
    return up,dn,up2,dn2
def feats(d,tfm):
    o,h,l,c,v=[d[x].values.astype(np.float64) for x in ['open','high','low','close','volume']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    W=lambda s,p: pd.Series(s).ewm(alpha=1/p,adjust=False).mean().values
    E=lambda s,p: pd.Series(s).ewm(span=p,adjust=False).mean().values
    a=W(tr,14); a5=W(tr,5); a50=W(tr,50)
    e20,e50,e200=E(c,20),E(c,50),E(c,200)
    dl=np.diff(c,prepend=c[0]); rsi=lambda p: 100-100/(1+W(np.clip(dl,0,None),p)/np.maximum(W(np.clip(-dl,0,None),p),1e-12))
    r14=rsi(14); r2=rsi(2)
    upm=np.diff(h,prepend=h[0]); dnm=-np.diff(l,prepend=l[0])
    pdm=np.where((upm>dnm)&(upm>0),upm,0.0); mdm=np.where((dnm>upm)&(dnm>0),dnm,0.0)
    pdi=100*W(pdm,14)/np.maximum(a,1e-12); mdi=100*W(mdm,14)/np.maximum(a,1e-12); adx=W(100*abs(pdi-mdi)/np.maximum(pdi+mdi,1e-12),14)
    cs=pd.Series(c); m20=cs.rolling(20).mean().values; sd=cs.rolling(20).std(ddof=0).values
    R=lambda s,p,f: getattr(pd.Series(s).rolling(p),f)().values
    hh20,ll20,hh50,ll50,hh200,ll200=R(h,20,'max'),R(l,20,'min'),R(h,50,'max'),R(l,50,'min'),R(h,200,'max'),R(l,200,'min')
    macd=E(c,12)-E(c,26); hist=macd-E(macd,9)
    vma=R(v,20,'mean')
    t=d.time; hr=t.dt.hour.values; wd=t.dt.weekday.values
    day=t.dt.floor('D'); pdh=day.map(d.groupby(day).high.max().shift(1)).values; pdl=day.map(d.groupby(day).low.min().shift(1)).values
    # فريم أعلى (4×): EMA50 و RSI على إغلاقات مجمّعة سببياً (آخر شمعة مكتملة)
    k=4; cH=pd.Series(c).iloc[::-1].rolling(1).mean().iloc[::-1].values
    g=np.arange(n)//k; last=pd.Series(c).groupby(g).transform('last').values
    hc=pd.Series(c).groupby(g).last(); he=hc.ewm(span=50,adjust=False).mean(); hrs=pd.Series(100-100/(1+W(np.clip(np.diff(hc.values,prepend=hc.values[0]),0,None),14)/np.maximum(W(np.clip(-np.diff(hc.values,prepend=hc.values[0]),0,None),14),1e-12)))
    gi=np.maximum(g-1,0)   # آخر مجموعة مكتملة
    htf_d=(hc.values[gi]-he.values[gi])/a; htf_r=hrs.values[gi]-50
    up_run=np.zeros(n);
    s=np.sign(c-o)
    for i in range(1,n): up_run[i]=up_run[i-1]+s[i] if s[i]==np.sign(up_run[i-1]) or up_run[i-1]==0 else s[i]
    rng=np.maximum(h-l,1e-12)
    F=np.column_stack([
        (c-np.r_[c[:1],c[:-1]])/a,(c-np.r_[c[:3],c[:-3]])/a,(c-np.r_[c[:5],c[:-5]])/a,(c-np.r_[c[:10],c[:-10]])/a,(c-np.r_[c[:20],c[:-20]])/a,(c-np.r_[c[:50],c[:-50]])/a,
        (c-e20)/a,(c-e50)/a,(c-e200)/a,(e20-np.r_[e20[:5],e20[:-5]])/a,(e50-np.r_[e50[:10],e50[:-10]])/a,(e200-np.r_[e200[:20],e200[:-20]])/a,
        r14-50,r2-50,adx,pdi-mdi,(c-m20)/np.maximum(2*sd,1e-12),np.log(4*sd/a+1e-6),np.log(a5/a50),np.log(a/np.maximum(W(tr,200),1e-12)),
        (c-ll20)/np.maximum(hh20-ll20,1e-12),(c-ll50)/np.maximum(hh50-ll50,1e-12),(c-ll200)/np.maximum(hh200-ll200,1e-12),
        (c-o)/a,(h-np.maximum(o,c))/rng,(np.minimum(o,c)-l)/rng,rng/a,hist/a,v/np.maximum(vma,1e-9),up_run,
        np.sin(2*np.pi*hr/24),np.cos(2*np.pi*hr/24),wd,(pdh-c)/a,(c-pdl)/a,htf_d,htf_r,np.full(n,tfm)])
    return F,o,h,l,c,a
sets=[('gold','5m','m1/xau_5m.csv',5,0.25),('gold','15m','gold20/xau20_15m.csv',15,0.25),('gold','1h','gold20/xau20_1h.csv',60,0.25),
      ('btc','15m','gold10/btc10_15m.csv',15,0.0),('btc','1h','gold10/btc10_1h.csv',60,0.0)]
Xs=[];meta=[]
for mk,tf,f,tfm,SP in sets:
    d=pd.read_csv(f'{S}/{f}'); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'}); d['time']=pd.to_datetime(d.time)
    d=d.sort_values('time').drop_duplicates('time').reset_index(drop=True)
    F,o,h,l,c,a=feats(d,tfm)
    up,dn,up2,dn2=race(h,l,o,a,1.5,96)
    yr=d.time.dt.year.values; day=d.time.dt.floor('D').values
    keep=np.arange(n:=len(c))>=300
    Xs.append(F[keep]); meta.append(pd.DataFrame({'mk':mk,'tf':tf,'year':yr[keep],'day':day[keep],'up':up[keep],'dn':dn[keep],'up2':up2[keep],'dn2':dn2[keep],
        'cost':SP/(1.5*a[keep]),'idx':np.arange(n)[keep]}))
    print('done',mk,tf,keep.sum(),file=sys.stderr,flush=True)
X=np.vstack(Xs).astype(np.float32); M=pd.concat(meta,ignore_index=True)
g=M.mk=='gold'
trm=((g&(M.year<=2018))|(~g&(M.year<=2020))).values; te=((g&(M.year>=2019))|(~g&(M.year>=2021))).values
ok_u=M.up.values>=0; ok_d=M.dn.values>=0
P={}
for side in ('up','dn'):
    yv=M[side].values; m=trm&(yv>=0)
    mdl=lgb.LGBMClassifier(n_estimators=500,learning_rate=0.03,num_leaves=63,min_child_samples=500,subsample=0.7,subsample_freq=1,colsample_bytree=0.7,verbose=-1,random_state=1)
    mdl.fit(X[m][::2],yv[m][::2])
    P[side]=mdl.predict_proba(X)[:,1]
    print(side,'trained',file=sys.stderr,flush=True)
M['pu']=P['up']; M['pd']=P['dn']
M.to_parquet if False else None
print('الأساس (اختبار): نجاح الشراء العشوائي',f"{M.up[te&ok_u].mean()*100:.1f}%",'البيع',f"{M.dn[te&ok_d].mean()*100:.1f}%")
# إشارات: الثقة ≥ حد (من التدريب) والاتجاه الأقوى، ولا إشارة جديدة قبل 6 شموع
for top in (10,5,2,1):
    res=[]
    for (mk,tf),G in M[te].groupby(['mk','tf']):
        tr_=M[trm&(M.mk==mk)&(M.tf==tf)]
        thu=np.quantile(tr_.pu,1-top/100); thd=np.quantile(tr_.pd,1-top/100)
        G=G.sort_values('idx'); last=-99; ws=[];rs=[];r2s=[]
        pu,pdn,ix,u,dn_,u2,d2,cost=[G[x].values for x in ['pu','pd','idx','up','dn','up2','dn2','cost']]
        for q in range(len(G)):
            if ix[q]-last<6: continue
            s=1 if (pu[q]>=thu and pu[q]>=pdn[q]) else (-1 if pdn[q]>=thd else 0)
            if s==0: continue
            w=u[q] if s>0 else dn_[q]; w2=u2[q] if s>0 else d2[q]
            if w<0: continue
            last=ix[q]; ws.append(w); rs.append((1 if w==1 else -1)-cost[q]); r2s.append((2 if w2==1 else -1)-cost[q] if w2>=0 else -cost[q])
        days=len(np.unique(G.day.values))
        res.append((mk,tf,len(ws),len(ws)/max(days,1),np.mean(ws) if ws else np.nan,np.mean(rs) if rs else np.nan,np.mean(r2s) if r2s else np.nan))
    print(f'\n== أعلى {top}% ثقة (اختبار لم يره، بعد السبريد) — هدف 1R=1.5ATR / 2R')
    for mk,tf,nn,pdy,w,r,r2 in res: print(f'  {mk} {tf:3s} إشارات {nn:6d} ({pdy:5.1f}/يوم) | 1R نجاح {w*100:5.1f}% صافي R{r:+.3f} | 2R صافي R{r2:+.3f}')
