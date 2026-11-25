import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
hi=pd.read_csv('signals2.csv'); lt=pd.read_csv('signals_lt2.csv')
base=[c for c in hi.columns if c not in ['market','tf','year','dir','win','r','src'] and not c.startswith('i_')]
safe=['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
F=base+safe; SP=0.25
trH=(((hi.market=='gold20')&(hi.year>=2010)&(hi.year<=2018))|((hi.market=='btc')&(hi.year<=2020))).values
g=(lt.market=='gold').values; trL=g&(lt.year<=2020).values
rp=lt.riskp.values; net=lt.r.values-SP/rp; ynet=(net>0).astype(int)
def fit(X,y,sd): return RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=sd).fit(X.astype(np.float32),y)
X=lt[F].values.astype(np.float32); Xr=np.c_[X,np.log(rp)]  # + مسافة الوقف بالدولار (تعرف السبريد)
variants={}
for sd in (1,2,3):
    m=fit(hi[F].values[trH],hi.win.values[trH],sd); variants.setdefault('King الحالي',[]).append((m.predict_proba(hi[F].values[trH].astype(np.float32))[:,1],m.predict_proba(X)[:,1]))
    m=fit(X[trL],lt.win.values[trL],sd); variants.setdefault('King للفريمات الصغيرة',[]).append((m.predict_proba(X[trL])[:,1],m.predict_proba(X)[:,1]))
    m=fit(Xr[trL],ynet[trL],sd); variants.setdefault('King صغير + يعرف السبريد',[]).append((m.predict_proba(Xr[trL])[:,1],m.predict_proba(Xr)[:,1]))
for tf,mn in [('1m',1),('5m',2)]:
    bm=g&(lt.tf==tf).values&(lt.year>=2021).values; days=lt[bm].year.nunique()*252
    print(f'\n== ذهب {tf} 2021+ صافي بعد سبريد {SP}$')
    for nm,ps in variants.items():
        for top in (30,15):
            for flt in (0,mn):
                A=[];R=[];N=[]
                for ptr,p in ps:
                    k=bm&(p>=np.quantile(ptr,1-top/100))&(rp>=flt)
                    A.append((net[k]>0).mean()); R.append(net[k].mean()); N.append(k.sum())
                print(f'  {nm:24s} أعلى {top}% وقف≥{flt}$: {np.mean(A)*100:4.1f}% R{np.mean(R):+.3f} ({np.mean(N)/days:4.1f}/يوم)')
