import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
import lightgbm as lgb
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
df=pd.read_csv(S+'/ai/sdz.csv')
meta=['market','tf','mode','year','win','r','vwin','vr']
feat=[c for c in df.columns if c not in meta]
gold=df.market=='gold'
trm=(gold&(df.year>=2010)&(df.year<=2018))|((~gold)&(df.year<=2020))
test=~trm&~(gold&(df.year<2010))
val=(gold&(df.year>=2016)&(df.year<=2018))|((~gold)&(df.year==2020))
fit=trm&~val
def line(lab,m):
    m2=m&(df.vwin>=0)
    print(f"{lab:34s} 1R: {df.win[m].mean()*100:5.1f}% R {df.r[m].mean():+.3f} | 2:1: {df.vwin[m2].mean()*100:5.1f}% R {df.vr[m2].mean():+.3f} | n={m.sum()}")
print('=== المناطق وحدها (بدون ذكاء) — اختبار لم يره')
for md in ['touch','react']:
    sel=df['mode']==md
    line(f'{md} الكل',sel&test); line(f'{md} ذهب',sel&test&gold); line(f'{md} بيتكوين',sel&test&~gold)
    for tf in ['15m','1h','4h']: line(f'   {tf} ذهب',sel&test&gold&(df.tf==tf))
    for t in [1,2,3]: line(f'   لمسة رقم {t}',sel&test&(df.touch_n==t))
print()
for md in ['touch','react','both']:
    sel=(df['mode']==md) if md!='both' else (df['mode']=='react')|(df['mode']=='touch')
    F,V,T,TR=df[sel&fit],df[sel&val],df[sel&test],df[sel&trm]
    for tgt,rr,lab in [('win','r','1R'),('vwin','vr','2:1')]:
        Fm=F[F[tgt]>=0] if tgt=='vwin' else F
        models={
          'RF':RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=1),
          'LGB':lgb.LGBMClassifier(n_estimators=400,learning_rate=0.015,num_leaves=15,min_child_samples=200,subsample=0.8,subsample_freq=1,colsample_bytree=0.7,verbose=-1,random_state=1)}
        best=None
        for nm,m in models.items():
            m.fit(Fm[feat].values.astype(np.float32),Fm[tgt].values)
            pv=m.predict_proba(V[feat].values.astype(np.float32))[:,1]; k=pv>=np.quantile(pv,0.7)
            vv=V[tgt].values; vs=vv[k&(vv>=0)].mean()
            print(f'[{md} {lab}] {nm} تحقق أعلى 30%: {vs*100:.1f}%')
            if best is None or vs>best[0]: best=(vs,nm)
        # الأفضل على التحقق يُعاد تدريبه على كل التدريب ثم يُختبر
        nm=best[1]; m=models[nm]; TRm=TR[TR[tgt]>=0] if tgt=='vwin' else TR
        m.fit(TRm[feat].values.astype(np.float32),TRm[tgt].values)
        ptr=m.predict_proba(TRm[feat].values.astype(np.float32))[:,1]; p=m.predict_proba(T[feat].values.astype(np.float32))[:,1]
        ok=T[tgt].values>=0; g=(T.market=='gold').values
        base=T[tgt].values[ok].mean()
        print(f'  >> {md} {lab} بـ {nm}: بدون ذكاء {base*100:.1f}%')
        for top in [50,30,15,7]:
            k=(p>=np.quantile(ptr,1-top/100))&ok
            print(f'     أعلى {top}%: {T[tgt].values[k].mean()*100:.1f}% R {T[rr].values[k].mean():+.3f} n={k.sum()} | ذهب {T[tgt].values[k&g].mean()*100:.1f}% (n={(k&g).sum()}) | بيتكوين {T[tgt].values[k&~g].mean()*100:.1f}%')
        if nm=='RF': print('     أهم:',[f for _,f in sorted(zip(m.feature_importances_,feat),reverse=True)[:8]])
