import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
hi=pd.read_csv('signals2.csv'); lt=pd.read_csv('signals_lt2.csv')
base=[c for c in hi.columns if c not in ['market','tf','year','dir','win','r','src'] and not c.startswith('i_')]
safe=['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
F=base+safe
trH=(((hi.market=='gold20')&(hi.year>=2010)&(hi.year<=2018))|((hi.market=='btc')&(hi.year<=2020))).values
ps=[]
for sd in (1,2,3):
    m=RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=sd).fit(hi[F].values[trH].astype(np.float32),hi.win.values[trH])
    ptr=m.predict_proba(hi[F].values[trH].astype(np.float32))[:,1]; p=m.predict_proba(lt[F].values.astype(np.float32))[:,1]
    ps.append((np.quantile(ptr,0.7),np.quantile(ptr,0.85),p))
y=lt.win.values; r=lt.r.values; rp=lt.riskp.values; st=lt.i_stars.values
SPREAD=0.25   # ذهب: سبريد تقريبي 25 سنت
def sets(q30,q15):
    return {'Mp':np.ones(len(lt),bool),'AK':(lt.src=='AAB').values&q15,'King 15%':q15,'King 30%':q30,
            'النجوم':(st>=1)&(q15|((st>=2)&q30)),'KM':(lt.i_km.values==1)&q30,'ST':(lt.i_st.values>=0.5648)&q30,'Alka':(lt.src=='Alka').values&q30}
for tf in ['1m','5m']:
    base_m=(lt.market=='gold').values&(lt.tf==tf).values&(lt.year>=2021).values
    days=lt[base_m].year.nunique()*252
    print(f'\n===== ذهب {tf} (2021-2026) — سبريد {SPREAD}$ — صافي R بعد السبريد')
    for nm in ['Mp','AK','King 15%','King 30%','النجوم','KM','ST','Alka']:
        line=f'  {nm:9s}'
        for mn in [0,1,2,3,5]:
            acc=[];R=[];N=[]
            for q30v,q15v,p in ps:
                g=sets(p>=q30v,p>=q15v)[nm]&base_m&(rp>=mn)
                net=r[g]-SPREAD/rp[g]
                acc.append((net>0).mean()); R.append(net.mean()); N.append(g.sum())
            line+=f' | وقف≥{mn}$: {np.mean(acc)*100:4.1f}% R{np.mean(R):+.2f} ({np.mean(N)/days:4.1f}/يوم)'
        print(line)
