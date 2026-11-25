import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
df=pd.read_csv(S+'/ai/signals2.csv')
base=[c for c in df.columns if c not in ['market','tf','year','dir','win','r','src'] and not c.startswith('i_')]
safe=['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
trm=((df.market=='gold20')&(df.year>=2010)&(df.year<=2018))|((df.market=='btc')&(df.year<=2020))
test=(~trm&~((df.market=='gold20')&(df.year<2010))).values
gold=(df.market=='gold20').values
ps=[]
for sd in range(1,4):
    m=RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=sd).fit(df[trm][base+safe].values.astype(np.float32),df.win[trm])
    ptr=m.predict_proba(df[trm][base+safe].values.astype(np.float32))[:,1]; p=m.predict_proba(df[base+safe].values.astype(np.float32))[:,1]
    ps.append((ptr,p))
y=df.win.values; r=df.r.values
groups={'Mp (كل الإشارات)':np.ones(len(df),bool),'Alka':(df.src=='Alka').values,'0.1':(df.src=='0.1').values,'AAB':(df.src=='AAB').values,
 'النجوم (نجمة+)':(df.i_stars>=1).values,'النجوم (نجمتان+)':(df.i_stars>=2).values,'ST (أعلى 30% ثقة)':(df.i_st>=0.5648).values,'SM':(df.i_sm==1).values,'KM':(df.i_km==1).values,'ALL (AAB+Alka)':(df.src!='0.1').values}
print(f"{'المؤشر':20s} | بدون فهم التوقيت | + فهم التوقيت (King 50%) | (King 30%) | ذهب: بدون → 30%")
for nm,g in groups.items():
    b=g&test
    out=f"{nm:20s} | {y[b].mean()*100:4.1f}% R{r[b].mean():+.2f} n={b.sum():5d}"
    for top in (50,30):
        acc=[];rr=[];nn=[];ga=[]
        for ptr,p in ps:
            k=b&(p>=np.quantile(ptr,1-top/100)); acc.append(y[k].mean()); rr.append(r[k].mean()); nn.append(k.sum()); ga.append(y[k&gold].mean())
        out+=f" | {np.mean(acc)*100:4.1f}% R{np.mean(rr):+.2f} ({np.mean(nn)/b.sum()*100:.0f}% منها)"
    out+=f" | {y[b&gold].mean()*100:4.1f} → {np.mean(ga)*100:4.1f}"
    print(out)
