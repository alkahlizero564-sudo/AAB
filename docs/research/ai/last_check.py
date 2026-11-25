import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
import lightgbm as lgb
from sklearn.ensemble import RandomForestClassifier
R=pd.read_csv('last.csv'); M=R[R.src=='Mp (مؤشراتنا)'].reset_index(drop=True)
s2=pd.read_csv('signals2.csv'); key=pd.read_csv('sdkey.csv')
s2=s2[s2.market.isin(['gold20','btc'])].reset_index(drop=True); key=key[key.market.isin(['gold20','btc'])].reset_index(drop=True)
print(len(M),len(s2),len(key))
# ترتيب صفوف M هو ترتيب sdkey لكل (سوق، فريم)؛ نربط بالترتيب داخل كل مجموعة
M['k']=M.groupby(['market','tf']).cumcount(); s2['k']=s2.groupby(['market','tf']).cumcount()
# تأكد: نفس الاتجاه
J=M.merge(s2,on=['market','tf','k'],suffixes=('','_s'))
print('تطابق الاتجاه',(J.dir==J.dir_s).mean(), 'تطابق نتيجة Dart مع بايثون', (J.win==J.win_s).mean(), 'نجاح Dart',J.win_s.mean().round(3),'نجاح بايثون',J.win.mean().round(3))
base=[c for c in s2.columns if c not in ['market','tf','year','dir','win','r','src','k'] and not c.startswith('i_')]
safe=['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
KF=[c+'_s' if c in M.columns else c for c in base+safe]
PF=[c for c in R.columns if c not in ['market','tf','year','src','win','r']]
g=J.market=='gold20'; trm=((g&(J.year>=2010)&(J.year<=2018))|(~g&(J.year<=2020))).values; te=((g&(J.year>=2019))|(~g&(J.year>=2021))).values
def run(F,y,lab):
    A=[]
    for sd in (1,2,3):
        m=RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=sd).fit(J[F].values[trm].astype(np.float32),J[y].values[trm])
        ptr=m.predict_proba(J[F].values[trm].astype(np.float32))[:,1]; p=m.predict_proba(J[F].values[te].astype(np.float32))[:,1]
        k=p>=np.quantile(ptr,0.85); A.append((J[y].values[te][k].mean(),k.sum()))
    print(f'{lab}: أعلى 15% {np.mean([a[0] for a in A])*100:.1f}% n={np.mean([a[1] for a in A]):.0f}')
run(KF,'win','King (معلومات King) — نتيجة بايثون')
run(PF,'win','Last-Mp (معلومات Last) — نتيجة بايثون')
run(KF,'win_s','King — نتيجة Dart (التطبيق)')
run(PF,'win_s','Last-Mp — نتيجة Dart (التطبيق)')
run(KF+PF,'win_s','King + Last — نتيجة Dart')
