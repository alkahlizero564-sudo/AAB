# تحسين CHoCH: (1) دخول بالسوق (2) مع ترند الفريم الأكبر (3) مع موافقة King (4) ذكاء يختار — 1R/2R خروج طبيعي، سبريد
import pandas as pd, numpy as np, re, json, sys, warnings
warnings.filterwarnings('ignore')
import lightgbm as lgb
exec(open('spread.py').read().split("for tf,f in")[0])          # sim + King (s, key, Q70)
exec(open('mass.py').read().split("SEL=[")[0]); src_big=open('big.py').read(); exec(src_big[src_big.index('P=[3,5'):src_big.index('rows=[]; names=None')].replace("from mass","#"))
def E(x,p): return pd.Series(x).ewm(span=p,adjust=False).mean().values
rows=[]; FE=[]
for mk,mkk,tf,f,ty,SP in [('ذهب','gold20','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','gold20','1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين','btc','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','btc','1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; yr=pd.to_datetime(d.iloc[:,0]).dt.year.values
    o,h,l,c,v=[d[x].values.astype(float) for x in ['open','high','low','close','volume']]; n=len(c); pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    # ترند فريم أكبر ×4: EMA50 على الشموع المجمعة
    m4=4; g=np.arange(n)//m4; cc=pd.Series(c).groupby(g).last().values; e50=E(cc,50); htf=np.sign(cc-e50)[np.maximum((np.arange(n)+1)//m4-1,0)]
    # King ⭐+ آخر 6 شموع
    km=((key.market==mkk)&(key.tf==tf)).values&(s.p.values>=Q70); kset=set()
    for i0,d0 in zip(key.i.values[km],key.dir.values[km]):
        for q in range(i0,i0+7): kset.add((q,d0))
    F=fam(o,h,l,c,v)
    k=5; res=np.nan; sup=np.nan; last=0; rs=np.random.RandomState(8)
    for i in range(300,n-2):
        j=i-k
        if h[j]==h[j-k:j+k+1].max(): res=h[j]
        if l[j]==l[j-k:j+k+1].min(): sup=l[j]
        dd=0
        if not np.isnan(res) and c[i]>res and c[i-1]<=res: dd=1; res=np.nan
        elif not np.isnan(sup) and c[i]<sup and c[i-1]>=sup: dd=-1; sup=np.nan
        if dd==0: continue
        kind=1 if last==-dd else 0; last=dd
        if not kind: continue
        g1,rk=sim(o,h,l,c,a,i,dd,0.0,SP,1.0,2.0)
        rd=1 if rs.rand()<0.5 else -1
        gx,rkx=sim(o,h,l,c,a,i,rd,0.0,SP,1.0,2.0)
        rows.append([mk,tf,yr[i]>=ty,yr[i],g1/rk,gx/rkx,int(htf[i]*dd>0),int((i,dd) in kset)])
        FE.append([F[nm][0][i]*(dd if F[nm][1] else 1) for nm in F])
    print('done',mk,tf,file=sys.stderr,flush=True)
T=pd.DataFrame(rows,columns=['mk','tf','test','year','r','rx','htf','king']); X=np.array(FE,dtype=np.float32)
T=T.reset_index(drop=True); ok=~T.r.isna(); T=T[ok]; X=X[ok.values]
tr=~T.test.values
P=[]
for sd in [1,2,3]:
    m=lgb.LGBMClassifier(n_estimators=400,learning_rate=0.02,num_leaves=15,min_child_samples=150,subsample=0.8,subsample_freq=1,colsample_bytree=0.3,verbose=-1,random_state=sd)
    m.fit(X[tr],(T.r.values[tr]>0).astype(int)); P.append(m.predict_proba(X)[:,1])
T['p']=np.mean(P,0); th30=np.quantile(T.p.values[tr],0.7)
for (mk,tf),G in T[T.test].groupby(['mk','tf'],sort=False):
    print(f'== {mk} {tf} CHoCH (اختبار، 1R/2R، بعد السبريد)')
    for lab,x in [('(1) دخول مباشر بعد الكسر',G),('(2) + مع ترند الفريم الأكبر',G[G.htf==1]),('(3) + King بنفس الاتجاه',G[G.king==1]),('(4) ذكاء يختار أفضل 30%',G[G.p>=th30]),('عشوائي بنفس الأوقات',G.assign(r=G.rx))]:
        print(f'   {lab:30s} n={len(x):5d} | لم يضرب الوقف كاملاً {(x.r>-0.99).mean()*100:5.1f}% | {x.r.mean():+.3f}R')
