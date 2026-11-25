import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import lightgbm as lgb
from sklearn.ensemble import RandomForestClassifier
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
R=pd.read_csv(S+'/ai/last.csv')
R['srcc']=R.src.astype('category').cat.codes
meta=['market','tf','year','src','win','r']
F=[c for c in R.columns if c not in meta]
g=R.gold==1
trm=(g&(R.year>=2010)&(R.year<=2018))|(~g&(R.year<=2020))
val=(g&(R.year>=2016)&(R.year<=2018))|(~g&(R.year==2020))
test=(g&(R.year>=2019))|(~g&(R.year>=2021))
fit=trm&~val
print('الإشارات:',len(R),'تدريب',trm.sum(),'اختبار',test.sum())
print('\n=== كل استراتيجية وحدها (اختبار لم يره، 1R ثم 2R)')
base=R[test].groupby('src').agg(n=('win','size'),win=('win','mean'),R=('r','mean')).sort_values('win',ascending=False)
print(base.round(3).to_string())
X=lambda m: R.loc[m,F].values.astype(np.float32)
def mk(kind,sd):
    if kind=='LGB': return lgb.LGBMClassifier(n_estimators=600,learning_rate=0.02,num_leaves=31,min_child_samples=300,subsample=0.8,subsample_freq=1,colsample_bytree=0.6,verbose=-1,random_state=sd)
    return RandomForestClassifier(n_estimators=200,min_samples_leaf=150,max_depth=12,max_features=0.3,n_jobs=-1,random_state=sd)
best=None
for kind in ['LGB','RF']:
    m=mk(kind,1).fit(X(fit),R.win[fit]); pv=m.predict_proba(X(val))[:,1]; k=pv>=np.quantile(pv,0.85)
    s=R.win[val].values[k].mean(); print(f'[تحقق] {kind} أعلى 15%: {s*100:.1f}%')
    if best is None or s>best[0]: best=(s,kind)
kind=best[1]
days={}
for mkt in ['gold20','btc']:
    t=R[test&(R.market==mkt)]
    days[mkt]=t.groupby('tf').year.nunique().mean()*(252 if mkt=='gold20' else 365)
ps=[]
for sd in (1,2,3):
    m=mk(kind,sd).fit(X(trm),R.win[trm]); ptr=m.predict_proba(X(trm))[:,1]; p=m.predict_proba(X(test))[:,1]; ps.append((ptr,p,m))
T=R[test].reset_index(drop=True)
print(f'\n=== Last ({kind}) على كل الاستراتيجيات — اختبار لم يره')
for top in (30,15,7,3):
    A=[];RR=[];G=[];N=[];mix=[]
    for ptr,p,_ in ps:
        k=p>=np.quantile(ptr,1-top/100); A.append(T.win[k].mean()); RR.append(T.r[k].mean()); G.append(T.win[k&(T.gold==1).values].mean()); N.append(k.sum())
        mix.append(T[k].src.value_counts(normalize=True).head(4).round(2).to_dict())
    print(f'أعلى {top}%: {np.mean(A)*100:.1f}% R{np.mean(RR):+.3f} | ذهب {np.mean(G)*100:.1f}% | صفقات {np.mean(N):.0f} | الأكثر: {mix[0]}')
# Last بدون Mp (هل يفهم الاستراتيجيات الأخرى؟) و Mp فقط بنفس المعلومات
for lab,sel in [('Mp فقط',R.src=='Mp (مؤشراتنا)'),('بدون Mp',R.src!='Mp (مؤشراتنا)')]:
    A=[];RR=[]
    for sd in (1,2,3):
        m=mk(kind,sd).fit(X(trm&sel),R.win[trm&sel]); ptr=m.predict_proba(X(trm&sel))[:,1]; p=m.predict_proba(X(test&sel))[:,1]
        y=R.win[test&sel].values; r=R.r[test&sel].values
        for top in (15,):
            k=p>=np.quantile(ptr,1-top/100); A.append(y[k].mean()); RR.append(r[k].mean())
    print(f'{lab}: أعلى 15% → {np.mean(A)*100:.1f}% R{np.mean(RR):+.3f}')
imp=np.mean([m.feature_importances_ for _,_,m in ps],axis=0)
print('أهم المعلومات:',[f for _,f in sorted(zip(imp,F),reverse=True)[:12]])
print('مرجع King (signals2، نفس فترة الاختبار): أعلى 30% 59.6% • أعلى 15% 62.4% • أعلى 7% 64.6%')
