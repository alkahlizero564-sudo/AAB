import pandas as pd, numpy as np, re, json, warnings
warnings.filterwarnings('ignore')
import lightgbm as lgb
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
D=pd.read_pickle(S+'/ai/more.pkl')
cols=[c for c in D.columns if c not in ('w','r','year','i','d','mk','tf')]
for c_ in cols:
    if D[c_].dtype==np.float64: D[c_]=D[c_].astype(np.float32)
import gc; gc.collect()
tr=(((D.mk=='ذهب')&(D.year<=2018))|((D.mk=='بيتكوين')&(D.year<=2020))).values
te=(((D.mk=='ذهب')&(D.year>=2019))|((D.mk=='بيتكوين')&(D.year>=2021))).values
y=D.w.values
# عينة تدريب متوازنة الحجم
rs=np.random.RandomState(0); tri=np.sort(rs.choice(np.where(tr)[0],min(int(tr.sum()),300000),replace=False))
Xtr=D[cols].iloc[tri].values; ytr=y[tri]
tei=np.where(te)[0]; Xte=np.concatenate([D[cols].iloc[tei[k:k+100000]].values for k in range(0,len(tei),100000)])
P=[];PA=[]
for sd in [1,2]:
    m=lgb.LGBMClassifier(n_estimators=600,learning_rate=0.03,num_leaves=31,min_child_samples=400,subsample=0.7,subsample_freq=1,colsample_bytree=0.3,reg_lambda=5,verbose=-1,random_state=sd)
    m.fit(Xtr,ytr); P.append(m.predict_proba(Xte)[:,1]); PA.append(m.predict_proba(Xtr)[:,1])
p=np.mean(P,0); pa=np.mean(PA,0)
T=D.loc[te,['w','r','year','mk','tf']].copy(); T['p']=p; del D,Xtr; gc.collect()
# King في نفس الأسواق والفترة
exec(open(S+'/ai/king_tiers.py').read().split("src=open('/home/user/AAB/lib/analysis/king_model.dart')")[0])
src=open('/home/user/AAB/lib/analysis/king_model.dart').read(); feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
mm=load_model('/home/user/AAB/lib/analysis/king_model.dart','king')
s2=pd.read_csv(S+'/ai/signals2.csv'); key=pd.read_csv(S+'/ai/sdkey.csv'); s2['p']=predict(mm,s2[feat].values.astype(np.float32))
Q70,Q85=0.5680950185109677,0.5909170281481894
mkmap={'ذهب':'gold20','بيتكوين':'btc'}
print(f'كل المرشحين (اختبار): {te.sum()} | دقة خام {y[te].mean()*100:.1f}%')
for (mk,tf),G in T.groupby(['mk','tf'],sort=False):
    ty=2019 if mk=='ذهب' else 2021
    days=len(pd.bdate_range(f'{ty}-01-01','2026-10-31')) if mk=='ذهب' else (pd.Timestamp('2026-10-31')-pd.Timestamp(f'{ty}-01-01')).days
    m=((key.market==mkmap[mk])&(key.tf==tf)).values&(s2.year>=ty).values
    K=s2[m]; k30=K[K.p>=Q70]; k15=K[K.p>=Q85]
    print(f'== {mk} {tf} | King أعلى 30%: {len(k30)/days:.2f}/يوم بدقة {k30.win.mean()*100:.1f}% | أعلى 15%: {len(k15)/days:.2f}/يوم بدقة {k15.win.mean()*100:.1f}% | المرشحون {len(G)/days:.1f}/يوم بدقة {G.w.mean()*100:.1f}%')
    for top in [20,10,5,2,1,0.5]:
        th=np.quantile(pa,1-top/100); x=G[G.p>=th]
        if len(x)<30: continue
        print(f'     الذكاء الجديد أعلى {top:>4}%: {len(x)/days:5.2f}/يوم | دقة {x.w.mean()*100:5.1f}% | R {x.r.mean():+.3f}')
