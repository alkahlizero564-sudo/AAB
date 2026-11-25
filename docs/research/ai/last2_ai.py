# Last يتعلم من كل التجارب الفاشلة: King + حالة السوق (40) + قرب 22 استراتيجية فاشلة (نفس الاتجاه/عكسه) — نتيجة التطبيق (Dart)
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
import lightgbm as lgb
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
R=pd.read_csv(S+'/ai/last2.csv')
s2=pd.read_csv(S+'/ai/signals2.csv'); s2=s2[s2.market.isin(['gold20','btc'])].reset_index(drop=True)
M=R[R.src=='Mp (مؤشراتنا)'].reset_index(drop=True)
M['k']=M.groupby(['market','tf']).cumcount(); s2['k']=s2.groupby(['market','tf']).cumcount()
J=M.merge(s2,on=['market','tf','k'],suffixes=('','_s'))
assert (J.dir==J.dir_s).mean()>0.999, (J.dir==J.dir_s).mean()
srcs=[x for x in R.src.unique() if x!='Mp (مؤشراتنا)']
prox=[]
for nm in srcs:
    a=np.full(len(J),100.0); b=np.full(len(J),100.0)
    for (mk,tf),g in J.groupby(['market','tf']):
        ev=R[(R.market==mk)&(R.tf==tf)&(R.src==nm)]
        for dd in (1,-1):
            same=np.sort(ev[ev.dir==dd].i.values); opp=np.sort(ev[ev.dir==-dd].i.values)
            rows=g.index[g.dir==dd]; ii=g.loc[rows,'i'].values
            for arr,out in ((same,a),(opp,b)):
                p=np.searchsorted(arr,ii,side='right')-1
                dist=np.where(p>=0,ii-arr[np.clip(p,0,None)],100)
                out[rows]=np.minimum(dist,100)
    J['p_'+nm]=a; J['o_'+nm]=b; prox+=['p_'+nm,'o_'+nm]
base=[c for c in s2.columns if c not in ['market','tf','year','dir','win','r','src','k'] and not c.startswith('i_')]
safe=['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
KF=[c+'_s' if c in M.columns else c for c in base+safe]
REG=[c for c in R.columns if c not in ['market','tf','i','year','src','win','r','dir']]
g=J.market=='gold20'; trm=((g&(J.year>=2010)&(J.year<=2018))|(~g&(J.year<=2020))).values; te=((g&(J.year>=2019))|(~g&(J.year>=2021))).values
gold=g.values
y=J.win_s.values; r=J.r_s.values
def run(F,lab,kind='RF'):
    res=[]
    for sd in range(1,6):
        if kind=='RF': m=RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=sd)
        else: m=lgb.LGBMClassifier(n_estimators=500,learning_rate=0.015,num_leaves=15,min_child_samples=200,subsample=0.8,subsample_freq=1,colsample_bytree=0.5,verbose=-1,random_state=sd)
        X=J[F].values.astype(np.float32); m.fit(X[trm],y[trm]); ptr=m.predict_proba(X[trm])[:,1]; p=m.predict_proba(X[te])[:,1]
        res.append((ptr,p,m))
    s=f'{lab:40s}'
    for top in (30,15,7):
        A=[y[te][p>=np.quantile(q,1-top/100)].mean() for q,p,_ in res]; G=[y[te][(p>=np.quantile(q,1-top/100))&gold[te]].mean() for q,p,_ in res]
        RR=[r[te][p>=np.quantile(q,1-top/100)].mean() for q,p,_ in res]
        s+=f' | {top}%: {np.mean(A)*100:.1f}±{np.std(A)*100:.1f} R{np.mean(RR):+.3f} (ذهب {np.mean(G)*100:.1f})'
    print(s,flush=True); return res
print('إشارات Mp:',len(J),'تدريب',trm.sum(),'اختبار',te.sum(),'• مصادر فاشلة:',len(srcs))
run(KF,'King (الحالي)')
run(KF+REG,'King + حالة السوق (40)')
res=run(KF+prox,'King + قرب 22 استراتيجية فاشلة')
run(KF+REG+prox,'Last = King + حالة السوق + الفاشلة')
run(KF+REG+prox,'Last (LightGBM)','LGB')
F=KF+prox; imp=np.mean([m.feature_importances_ for _,_,m in res],axis=0)
print('أهم معلومات الاستراتيجيات الفاشلة:',[(f,round(float(v)*100,2)) for v,f in sorted(zip(imp,F),reverse=True) if f in prox][:10])
