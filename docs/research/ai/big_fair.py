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

P=[]
for sd in [1,2,3]:
    m=fit(ALL,tr,sd); P.append(m.predict_proba(X.loc[te,ALL].values.astype(np.float32))[:,1])
pt=np.mean(P,0); pkt=X.pk.values[te]; yt=y[te]
segs=[('Mp (الكل)',np.ones(len(X),bool)),('Alka',(X.src_alka==1).values),('AAB',(X.src_aab==1).values),('0.1',(X.src_01==1).values),('SM',(X.i_sm==1).values),('KM',(X.i_km==1).values),('النجوم',(X.i_stars>=1).values)]
print('مقارنة عادلة بنفس عدد الإشارات (أفضل N من كل نموذج داخل نفس المؤشر)')
for lab,seg in segs:
    sg=seg[te]; out=[]
    for t in [50,30,15]:
        n=int((sg&(pkt>=QK[t])).sum())
        if n<30: continue
        ik=np.argsort(-np.where(sg,pkt,-9))[:n]; ib=np.argsort(-np.where(sg,pt,-9))[:n]
        out.append(f'n={n}: King {yt[ik].mean()*100:5.1f}% ← الجديد {yt[ib].mean()*100:5.1f}%')
    print(f'  {lab:10s} '+' | '.join(out),flush=True)
