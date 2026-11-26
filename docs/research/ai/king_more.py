# King مدرّب على أسواق أكثر (ذهب + بيتكوين + برنت + إيثيريوم + عينات فوركس/مؤشرات 2019) مقابل King الحالي — اختبار على سنين وأسواق لم يرها
import pandas as pd, numpy as np, re, json, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
a=pd.read_csv(S+'/ai/signals2.csv'); b=pd.read_csv(S+'/ai/signals_brent.csv')
df=pd.concat([a,b],ignore_index=True)
base=[c for c in a.columns if c not in ['market','tf','year','dir','win','r','src'] and not c.startswith('i_')]
feat=base+['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
g=df.market=='gold20'; btc=df.market=='btc'; br=df.market=='brent'; eth=df.market=='eth'
s19=df.market.isin(['eurusd19','gbpusd19','audusd19','usdcad19','nas19','oil19'])
trA=((g&(df.year>=2010)&(df.year<=2018))|(btc&(df.year<=2020))).values
trB=trA|(br&(df.year<=2012)).values|(eth&(df.year<=2019)).values|s19.values
tests={'ذهب 2019+':(g&(df.year>=2019)).values,'بيتكوين 2021+':(btc&(df.year>=2021)).values,'برنت 2013-15 (جديد)':(br&(df.year>=2013)).values,
       'إيثيريوم 2025-26':(eth&(df.year>=2025)).values,'فوركس/مؤشرات/فضة 2026':df.market.str.endswith('26').values}
y=df.win.values; X=df[feat].values.astype(np.float32)
def fit(tr,seed):
    return RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=seed).fit(X[tr],y[tr])
print(f'تدريب A (الحالي): {trA.sum()} إشارة | تدريب B (أسواق أكثر): {trB.sum()} إشارة')
res={}
for lab,tr in [('A الحالي',trA),('B أسواق أكثر',trB)]:
    P=[];Q=[]
    for sd in [1,2,3]:
        m=fit(tr,sd); P.append(m.predict_proba(X)[:,1])
    p=np.mean(P,0); q={t:np.quantile(p[tr],1-t/100) for t in [30,15]}
    res[lab]=(p,q)
for tn,mask in tests.items():
    line=f'== {tn} (n={mask.sum()}, خام {y[mask].mean()*100:.1f}%)'
    for lab,(p,q) in res.items():
        line+=' | '+lab+': '+' '.join(f'أعلى {t}% {y[mask&(p>=q[t])].mean()*100:5.1f}% (n={(mask&(p>=q[t])).sum()})' for t in [30,15])
    print(line)
# مقارنة عادلة بنفس عدد الإشارات
print('\nبنفس عدد الإشارات (أفضل N من كل نموذج):')
for tn,mask in tests.items():
    pa=res['A الحالي'][0][mask]; pb=res['B أسواق أكثر'][0][mask]; yy=y[mask]
    out=[]
    for frac in [0.3,0.15]:
        N=max(1,int(len(yy)*frac)); out.append(f'أفضل {int(frac*100)}%: A {yy[np.argsort(-pa)[:N]].mean()*100:5.1f}% ← B {yy[np.argsort(-pb)[:N]].mean()*100:5.1f}%')
    print(f'   {tn:24s} '+' | '.join(out))
