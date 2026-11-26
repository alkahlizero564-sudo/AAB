import pandas as pd, numpy as np, warnings, sys
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
exec(open('mass.py').read().split("SEL=[")[0])
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
s2=pd.read_csv(S+'/ai/signals2.csv'); key=pd.read_csv(S+'/ai/sdkey.csv')
keep=s2.market.isin(['gold20','btc']).values
s2=s2[keep].reset_index(drop=True); key=key[keep].reset_index(drop=True)
files={('gold20','15m'):'gold20/xau20_15m.csv',('gold20','1h'):'gold20/xau20_1h.csv',('gold20','4h'):'gold20/xau20_4h.csv',
       ('btc','15m'):'gold10/btc10_15m.csv',('btc','1h'):'gold10/btc10_1h.csv',('btc','4h'):'gold10/btc10_4h.csv'}
feat=None; X=None
for (mk,tf),f in files.items():
    d=load(f'{S}/{f}'); st,_=strategies(d)
    base={k:v for k,v in st.items() if not k.endswith(('مع الترند','ADX>25','عكس الترند'))}
    if feat is None: feat=sorted(base); X=np.zeros((len(s2),len(feat)),np.float32)
    rows=np.where((key.market==mk)&(key.tf==tf))[0]
    ii=key.i.values[rows]; dd=key.dir.values[rows]
    for j,nm in enumerate(feat):
        s=base[nm].astype(float); s[s==0]=np.nan
        last=pd.Series(s).ffill(limit=4).fillna(0).values   # آخر إشارة خلال 5 شموع
        X[rows,j]=last[np.clip(ii,0,len(last)-1)]*dd          # +1 موافق، −1 معاكس
    print('done',mk,tf,file=sys.stderr,flush=True)
b=[c for c in s2.columns if c not in ['market','tf','year','dir','win','r','src'] and not c.startswith('i_')]
safe=['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
K=s2[b+safe].values.astype(np.float32)
g=s2.market=='gold20'; trm=((g&(s2.year>=2010)&(s2.year<=2018))|(~g&(s2.year<=2020))).values; te=((g&(s2.year>=2019))|(~g&(s2.year>=2021))).values
y=s2.win.values; r=s2.r.values
agree=(X>0).sum(1); opp=(X<0).sum(1)
print('توافق استراتيجيات TradingView مع إشارات Mp (اختبار):')
for lo,hi in [(0,0),(1,5),(6,15),(16,40),(41,200)]:
    m=te&(agree>=lo)&(agree<=hi)
    if m.sum()>100: print(f'  موافق {lo}-{hi}: {y[m].mean()*100:.1f}% n={m.sum()}')
def run(F,lab):
    A=[]
    for sd in range(1,6):
        m=RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=sd).fit(F[trm],y[trm])
        ptr=m.predict_proba(F[trm])[:,1]; p=m.predict_proba(F[te])[:,1]
        A.append([y[te][p>=np.quantile(ptr,1-t/100)].mean() for t in (30,15,7)])
    A=np.array(A)*100; print(f'{lab:44s} 30%: {A[:,0].mean():.1f}±{A[:,0].std():.1f} | 15%: {A[:,1].mean():.1f}±{A[:,1].std():.1f} | 7%: {A[:,2].mean():.1f}±{A[:,2].std():.1f}',flush=True)
run(K,'King الحالي')
run(np.hstack([K,X]),f'King + {len(feat)} استراتيجية TradingView')
run(np.hstack([K,np.c_[agree,opp]]),'King + عدد الموافقين/المعاكسين')
