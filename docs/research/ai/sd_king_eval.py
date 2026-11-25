import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
df=pd.read_csv(S+'/ai/signals_sd.csv'); df=df[df.market.isin(['gold20','btc'])].reset_index(drop=True)
ZC=[c for c in df.columns if c.startswith('z_')]
base=[c for c in df.columns if c not in ['market','tf','year','dir','win','r','src'] and not c.startswith(('i_','z_'))]
safe=['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
gold=(df.market=='gold20').values
trm=((gold)&(df.year>=2010)&(df.year<=2018))|((~gold)&(df.year<=2020))
test=(~trm&~(gold&(df.year<2010))).values; trm=trm.values
y=df.win.values; r=df.r.values
print('=== إشارات Mp حسب المنطقة (اختبار)')
for lab,m in [('الكل',np.ones(len(df),bool)),('داخل منطقة داعمة',df.z_in_sup==1),('داخل منطقة معاكسة',df.z_in_opp==1),
              ('منطقة معاكسة قريبة (<1 ATR)',df.z_d_opp<1),('لا منطقة معاكسة قريبة (>3)',df.z_d_opp>3),('منطقة داعمة قريبة (<1)',df.z_d_sup<1)]:
    m=np.asarray(m)&test
    print(f'  {lab:30s} {y[m].mean()*100:5.1f}% R {r[m].mean():+.3f} n={m.sum()} | ذهب {y[m&gold].mean()*100:5.1f}% n={(m&gold).sum()}')
def run(fs,lab):
    out=[]
    for sd in range(1,6):
        m=RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=sd).fit(df[fs].values[trm].astype(np.float32),y[trm])
        ptr=m.predict_proba(df[fs].values[trm].astype(np.float32))[:,1]; p=m.predict_proba(df[fs].values[test].astype(np.float32))[:,1]
        out.append((ptr,p,m))
    yt,rt,gt=y[test],r[test],gold[test]; s=f'{lab:28s}'
    for top in (30,15,7):
        A=[yt[p>=np.quantile(q,1-top/100)].mean() for q,p,_ in out]; G=[yt[(p>=np.quantile(q,1-top/100))&gt].mean() for q,p,_ in out]
        R=[rt[p>=np.quantile(q,1-top/100)].mean() for q,p,_ in out]
        s+=f' | {top}%: {np.mean(A)*100:.1f}±{np.std(A)*100:.1f} R{np.mean(R):+.3f} (ذهب {np.mean(G)*100:.1f})'
    print(s,flush=True); return out
print()
run(base+safe,'King الحالي')
o=run(base+safe+ZC,'King + مناطق العرض والطلب')
imp=np.mean([m.feature_importances_ for _,_,m in o],axis=0); fs=base+safe+ZC
print('  ترتيب معلومات المناطق:',sorted([(round(float(imp[fs.index(z)])*100,2),z) for z in ZC],reverse=True))
