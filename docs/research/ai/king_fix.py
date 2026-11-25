import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
hi=pd.read_csv('signals2.csv')
base=[c for c in hi.columns if c not in ['market','tf','year','dir','win','r','src'] and not c.startswith('i_')]
safe=['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
F=base+safe
g=hi.market=='gold20'
trm=((g&(hi.year>=2010)&(hi.year<=2018))|((hi.market=='btc')&(hi.year<=2020))).values
val=((g&(hi.year>=2016)&(hi.year<=2018))|((hi.market=='btc')&(hi.year==2020))).values
fit=trm&~val
te=(~trm&~(g&(hi.year<2010))).values
print('ADX:',hi.adx.describe()[['25%','50%','75%']].round(3).to_dict())
y=hi.win.values; X=hi[F].values.astype(np.float32)
def score(mask_fit):
    P=[];Q=[]
    for sd in (1,2,3):
        m=RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=sd).fit(X[mask_fit],y[mask_fit])
        ptr=m.predict_proba(X[mask_fit])[:,1]; P.append(m.predict_proba(X)[:,1]); Q.append(np.quantile(ptr,[0.7,0.85,0.93]))
    return np.mean(P,axis=0),np.mean(Q,axis=0)
pv,qv=score(fit)     # لاختيار القاعدة على سنين التحقق
pt,qt=score(trm)     # للاختبار النهائي
vol=hi.atr_ratio.values; t1,t2=np.quantile(vol[trm],[1/3,2/3])
mid=(vol>=t1)&(vol<t2); z=(hi.src=='0.1').values
adxq=np.quantile(hi.adx.values[trm],[0.33,0.67]); weak_adx=hi.adx.values<adxq[0]
def rule(p,q,name):
    k15=p>=q[1]; k7=p>=q[2]
    return {'King 15%':k15,
            '0.1 يحتاج 7%':np.where(z,k7,k15),
            'التذبذب العادي يحتاج 7%':np.where(mid,k7,k15),
            'الاثنين':np.where(z|mid,k7,k15),
            'ADX ضعيف يحتاج 7%':np.where(weak_adx,k7,k15)}[name]
for name in ['King 15%','0.1 يحتاج 7%','التذبذب العادي يحتاج 7%','الاثنين','ADX ضعيف يحتاج 7%']:
    kv=rule(pv,qv,name)&val; kt=rule(pt,qt,name)&te
    print(f'{name:26s} تحقق: {y[kv].mean()*100:.1f}% (n={kv.sum()}) | اختبار: {y[kt].mean()*100:.1f}% (n={kt.sum()}) ذهب {y[kt&g.values].mean()*100:.1f}%')
