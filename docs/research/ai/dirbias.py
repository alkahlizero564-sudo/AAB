import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
df=pd.read_csv('signals2.csv')
base=[c for c in df.columns if c not in ['market','tf','year','dir','win','r','src'] and not c.startswith('i_')]
safe=['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
F=base+safe
trm=((df.market=='gold20')&(df.year>=2010)&(df.year<=2018))|((df.market=='btc')&(df.year<=2020))
test=(~trm&~((df.market=='gold20')&(df.year<2010))).values; gold=(df.market=='gold20').values
m=RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=1).fit(df[trm][F].values.astype(np.float32),df.win[trm])
ptr=m.predict_proba(df[trm][F].values.astype(np.float32))[:,1]; p=m.predict_proba(df[F].values.astype(np.float32))[:,1]
k30=p>=np.quantile(ptr,0.7); y=df.win.values; d=df.dir.values
# الترند المحلي: السعر تحت EMA50 → هبوط
dn=df.d_e50.values<0
print('ملاحظة: d_e50 موجّه بالاتجاه؟', df.groupby('dir').d_e50.mean().round(3).to_dict())
for nm,mk in [('ذهب',gold&test),('بيتكوين',(df.market=='btc').values&test)]:
    for dd,lab in [(1,'شراء'),(-1,'بيع')]:
        b=mk&(d==dd)
        print(f'{nm} {lab}: كل {b.sum()} دقة {y[b].mean()*100:.1f}% | King30 يبقي {k30[b].mean()*100:.0f}% دقتها {y[b&k30].mean()*100:.1f}% | المحذوفة {y[b&~k30].mean()*100:.1f}%')
print()
al=d*df.ret20.values
for lab,mk in [('مع ترند قوي (حركة 20 شمعة في نفس الاتجاه > 3 ATR)',al>3),('مع ترند (1-3)',(al>1)&(al<=3)),('محايد',np.abs(al)<=1),('عكس الترند (1-3)',(al<-1)&(al>=-3)),('عكس ترند قوي (> 3)',al<-3)]:
    b=mk&test
    print(f'{lab:52s} n={b.sum():5d} دقة {y[b].mean()*100:.1f}% | King30 يبقي {k30[b].mean()*100:3.0f}% دقتها {y[b&k30].mean()*100:.1f}%')
print(df.ret20.describe().round(2).to_dict())
print()
print(df.htf.describe().round(2).to_dict())
for lab,mk in [('مع الفريم الأكبر',df.htf.values>0),('ضد الفريم الأكبر',df.htf.values<0),('محايد',df.htf.values==0)]:
    b=mk&test
    print(f'{lab:20s} n={b.sum():5d} دقة {y[b].mean()*100:.1f}% | King30 يبقي {k30[b].mean()*100:3.0f}% دقتها {y[b&k30].mean()*100:.1f}%')
