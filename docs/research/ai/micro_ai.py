import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
from sklearn.ensemble import RandomForestRegressor
df=pd.read_csv('micro.csv')
meta=['market','tf','mode','year','win','r','vwin','vr','w3','r3','ride']; feat=[c for c in df.columns if c not in meta]
g=df.market=='gold'; b=df.market=='btc'
trm=(g&(df.year>=2010)&(df.year<=2018))|(b&(df.tf!='5m')&(df.year<=2020))
test=~trm&~(g&(df.year<2010))
def line(lab,m):
    m2=m&(df.vwin>=0)
    return f"{lab:24s} 1R {df.win[m].mean()*100:5.1f}% | 2:1 {df.vwin[m2].mean()*100:5.1f}% R{df.vr[m2].mean():+.3f} | 3:1 {df.w3[m].mean()*100:5.1f}% R{df.r3[m].mean():+.3f} | ركوب الترند R{df.ride[m].mean():+.3f} (رابحة {(df.ride[m]>0).mean()*100:.0f}%) | n={m.sum()}"
print('التعادل: 1R 50% • 2:1 33.3% • 3:1 25% • ركوب الترند R>0')
for md,nm in [('micro','استراحة صغيرة ثم استمرار'),('micro_strong','نفسها في حركة قوية'),('lowerlow','كسر آخر قاع/قمة')]:
    sel=df['mode']==md
    print('==',nm); print(line('  الكل (اختبار)',sel&test))
    for (mk,tf),_ in df[sel&test].groupby(['market','tf']): print(line(f'  {mk} {tf}',sel&test&(df.market==mk)&(df.tf==tf)))
    for dd,lab in [(-1,'بيع فقط'),(1,'شراء فقط')]: print(line(f'  {lab}',sel&test&(df.dir==dd)))
print()
for md in ['micro','micro_strong','lowerlow']:
    sel=df['mode']==md; TR=df[sel&trm]; T=df[sel&test]
    for tgt,rr,lab in [('win','r','1R'),('w3','r3','3:1')]:
        A=[];Rr=[];Ri=[];G=[]
        for sd in range(1,4):
            m=RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=sd).fit(TR[feat].values.astype(np.float32),TR[tgt].values)
            ptr=m.predict_proba(TR[feat].values.astype(np.float32))[:,1]; p=m.predict_proba(T[feat].values.astype(np.float32))[:,1]
            k=p>=np.quantile(ptr,0.85); A.append(T[tgt].values[k].mean()); Rr.append(T[rr].values[k].mean()); Ri.append(T.ride.values[k].mean()); G.append(T[rr].values[k&(T.market=='gold').values].mean())
        print(f'[{md} ذكاء هدف {lab}] أعلى 15%: {np.mean(A)*100:.1f}% R{np.mean(Rr):+.3f} • ركوب الترند R{np.mean(Ri):+.3f} • ذهب R{np.mean(G):+.3f}')
    m=RandomForestRegressor(n_estimators=150,min_samples_leaf=200,max_depth=8,max_features=0.3,n_jobs=-1,random_state=1).fit(TR[feat].values.astype(np.float32),TR.ride.clip(-1,8).values)
    ptr=m.predict(TR[feat].values.astype(np.float32)); p=m.predict(T[feat].values.astype(np.float32))
    for top in (30,15):
        k=p>=np.quantile(ptr,1-top/100); gg=(T.market=='gold').values
        print(f'[{md} ذكاء ركوب الترند] أعلى {top}%: R{T.ride.values[k].mean():+.3f} رابحة {(T.ride.values[k]>0).mean()*100:.0f}% n={k.sum()} • ذهب R{T.ride.values[k&gg].mean():+.3f}')
