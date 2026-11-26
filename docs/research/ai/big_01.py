import pandas as pd, numpy as np, re, json, sys, warnings
warnings.filterwarnings('ignore')
import lightgbm as lgb
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
exec(open(S+'/ai/king_tiers.py').read().split("src=open('/home/user/AAB/lib/analysis/king_model.dart')")[0].replace("hi=pd.read_csv","#"))
src=open('/home/user/AAB/lib/analysis/king_model.dart').read()
feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
mm=load_model('/home/user/AAB/lib/analysis/king_model.dart','king')
X=pd.read_pickle(S+'/ai/big.pkl')
X['pk']=predict(mm,X[feat].values.astype(np.float32))
NF=[x for x in X.columns if x.startswith('sr_')]
BIG=[x for x in X.columns if x.startswith(('S_','S1_','B_','H4x_','H16x_','H64x_'))]
ALL=feat+NF+BIG
print('المعلومات:',len(ALL))
g=X.market=='gold20'
tr=((g&(X.year>=2010)&(X.year<=2018))|((X.market=='btc')&(X.year<=2020))).values
te=((g&(X.year>=2019))|((X.market=='btc')&(X.year>=2021))).values
y=X.win.values
# حدود King من التدريب
QK={t:np.quantile(X.pk.values[tr],1-t/100) for t in [50,30,15]}
def fit(cols,mask,seed):
    m=lgb.LGBMClassifier(n_estimators=500,learning_rate=0.02,num_leaves=15,min_child_samples=150,subsample=0.8,subsample_freq=1,colsample_bytree=0.2,reg_lambda=5,verbose=-1,random_state=seed)
    m.fit(X.loc[mask,cols].values.astype(np.float32),y[mask]); return m

IND=[c for c in BIG if c.startswith(('B_','H4x_','H16x_','H64x_'))]
m=fit(ALL,tr,1); imp=pd.Series(m.booster_.feature_importance('gain'),index=ALL)
z=(X.src_01==1).values
pkt=X.pk.values
for K in [20,40,80]:
    top=[c for c in imp[IND].sort_values(ascending=False).index[:K]]
    cols=feat+top
    for nm,mask in [('عام',tr),('خاص 0.1',tr&z)]:
        P=[]
        for sd in [1,2,3]:
            mm_=fit(cols,mask,sd); P.append(mm_.predict_proba(X.loc[te&z,cols].values.astype(np.float32))[:,1])
        p=np.mean(P,0); yt=y[te&z]; kk=pkt[te&z]; out=[]
        for t in [50,30,15]:
            n=int((kk>=QK[t]).sum()); ib=np.argsort(-p)[:n]; ik=np.argsort(-kk)[:n]
            out.append(f'n={n}: King {yt[ik].mean()*100:5.1f}% ← {yt[ib].mean()*100:5.1f}%')
        print(f'  0.1 | King54 + {K} مؤشر ({nm}): '+' | '.join(out),flush=True)
