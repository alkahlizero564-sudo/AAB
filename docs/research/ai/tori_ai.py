import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
import lightgbm as lgb
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
df=pd.read_csv(S+'/ai/tori.csv')
meta=['market','tf','mode','year','win','r','vwin','vr','w3','r3']
feat=[c for c in df.columns if c not in meta]
gold=df.market=='gold'
trm=(gold&(df.year>=2010)&(df.year<=2018))|((~gold)&(df.year<=2020))
test=~trm&~(gold&(df.year<2010))
val=(gold&(df.year>=2016)&(df.year<=2018))|((~gold)&(df.year==2020)); fit=trm&~val
def line(lab,m):
    m2=m&(df.vwin>=0); m3=m&(df.w3>=0)
    print(f"{lab:26s} 1R {df.win[m].mean()*100:5.1f}% | 2:1 {df.vwin[m2].mean()*100:5.1f}% R{df.vr[m2].mean():+.3f} | 3:1 {df.w3[m3].mean()*100:5.1f}% R{df.r3[m3].mean():+.3f} | n={m.sum()}")
print('=== القاعدة وحدها — اختبار لم يره (التعادل: 1R 50% • 2:1 33.3% • 3:1 25%)')
for md,nm in [('bounce','ارتداد من الخط'),('retest','كسر + إعادة اختبار')]:
    sel=df['mode']==md
    line(nm+' الكل',sel&test); line('  ذهب',sel&test&gold); line('  بيتكوين',sel&test&~gold)
    for tf in ['15m','1h','4h']: line(f'  {tf} ذهب',sel&test&gold&(df.tf==tf)); line(f'  {tf} بيتكوين',sel&test&~gold&(df.tf==tf))
    if md=='bounce':
        for t in [3,4,5]: line(f'  لمسة {t}',sel&test&(df.touch_n==t))
print()
for md in ['bounce','retest']:
    sel=df['mode']==md
    for tgt,rr,lab in [('win','r','1R'),('vwin','vr','2:1'),('w3','r3','3:1')]:
        ok=df[tgt]>=0
        F,V,T,TR=df[sel&fit&ok],df[sel&val&ok],df[sel&test&ok],df[sel&trm&ok]
        mk=lambda nm: RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=1) if nm=='RF' else lgb.LGBMClassifier(n_estimators=400,learning_rate=0.015,num_leaves=15,min_child_samples=200,subsample=0.8,subsample_freq=1,colsample_bytree=0.7,verbose=-1,random_state=1)
        best=None
        for nm in ['RF','LGB']:
            m=mk(nm).fit(F[feat].values.astype(np.float32),F[tgt].values); pv=m.predict_proba(V[feat].values.astype(np.float32))[:,1]
            vs=V[tgt].values[pv>=np.quantile(pv,0.7)].mean()
            if best is None or vs>best[0]: best=(vs,nm)
        m=mk(best[1]).fit(TR[feat].values.astype(np.float32),TR[tgt].values)
        ptr=m.predict_proba(TR[feat].values.astype(np.float32))[:,1]; p=m.predict_proba(T[feat].values.astype(np.float32))[:,1]
        g=(T.market=='gold').values; y=T[tgt].values; R=T[rr].values
        s=f'[{md} {lab} {best[1]}] بدون {y.mean()*100:.1f}%'
        for top in [30,15,7]:
            k=p>=np.quantile(ptr,1-top/100)
            s+=f' | {top}%: {y[k].mean()*100:.1f}% R{R[k].mean():+.3f} n={k.sum()} ذهب {y[k&g].mean()*100:.1f}%'
        print(s,flush=True)
