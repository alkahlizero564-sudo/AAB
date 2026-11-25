# كل المؤشرات على فريم الدقيقة و5 دقائق: King الحالي (مدرّب على 15m+) مقابل King مدرّب أيضاً على الفريمات الصغيرة
import pandas as pd, numpy as np, warnings, sys
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
hi=pd.read_csv(S+'/ai/signals2.csv'); lt=pd.read_csv(S+'/ai/signals_lt.csv')
base=[c for c in hi.columns if c not in ['market','tf','year','dir','win','r','src'] and not c.startswith('i_')]
safe=['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
F=base+safe
trH=(((hi.market=='gold20')&(hi.year>=2010)&(hi.year<=2018))|((hi.market=='btc')&(hi.year<=2020))).values
teH=(~trH&~((hi.market=='gold20')&(hi.year<2010))).values
gl=(lt.market=='gold').values
trL=gl&(lt.year<=2020).values           # تدريب الفريمات الصغيرة: ذهب 2015-2020
teL=~trL                                # اختبار: ذهب 2021+ والبيتكوين والإيثيريوم كلها
def rf(X,y,sd): return RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=sd).fit(X.astype(np.float32),y)
def groups(d):
    st=d.i_stars.values; sm=d.i_sm.values==1
    return {'Mp':np.ones(len(d),bool),'Alka':(d.src=='Alka').values,'AAB':(d.src=='AAB').values,'0.1':(d.src=='0.1').values,
            'ALL':(d.src!='0.1').values,'النجوم':st>=1,'PQ':(st>=1)|sm,'SM':sm,'KM':d.i_km.values==1,'ST':d.i_st.values>=0.5648}
# قاعدة كل مؤشر في التطبيق: (المجموعة، الفلتر) — 0 بلا فلتر، 30/15 أعلى King، 'g' متدرّج (نجمتان 30%، غيرها 15%)
rules=[('Mp',0),('0.1',0),('Alka',30),('ALL',30),('KM',30),('ST',30),('SM',30),('AAB',30),('AK=AAB',15),('النجوم','g'),('PQ','g'),('King 30%',30),('King 15%',15)]
def evaluate(d,mask,models,lab):
    G=groups(d); y=d.win.values; r=d.r.values; X=d[F].values.astype(np.float32)
    ps=[(m.predict_proba(Xtr)[:,1],m.predict_proba(X)[:,1]) for m,Xtr in models]
    rows=[]
    for nm,flt in rules:
        key={'AK=AAB':'AAB','King 30%':'Mp','King 15%':'Mp'}.get(nm,nm)
        g=G[key]&mask
        if flt==0:
            k=[g]
        else:
            k=[]
            for ptr,p in ps:
                q30=p>=np.quantile(ptr,0.7); q15=p>=np.quantile(ptr,0.85)
                if flt=='g': k.append(g&(q15|((d.i_stars.values>=2)&q30)))
                else: k.append(g&(q30 if flt==30 else q15))
        acc=np.mean([y[x].mean() for x in k]); R=np.mean([r[x].mean() for x in k]); n=np.mean([x.sum() for x in k])
        rows.append((nm,acc,R,n,g.sum()))
    return rows
print('== تدريب النموذجين', flush=True)
old=[]; new=[]
for sd in (1,2,3):
    Xh=hi[F].values[trH]; m=rf(Xh,hi.win.values[trH],sd); old.append((m,Xh.astype(np.float32)))
    Xn=np.vstack([hi[F].values[trH],lt[F].values[trL]]); yn=np.r_[hi.win.values[trH],lt.win.values[trL]]
    m2=rf(Xn,yn,sd); new.append((m2,hi[F].values[trH].astype(np.float32)))   # نفس عتبات التطبيق (من بيانات 15m+)
    print('seed',sd,flush=True)
for (mk,tf) in [('gold','1m'),('gold','5m'),('btc','1m'),('btc','5m'),('eth','5m')]:
    m=(lt.market==mk).values&(lt.tf==tf).values&teL
    if m.sum()<200: continue
    a=evaluate(lt,m,old,'old'); b=evaluate(lt,m,new,'new')
    print(f'\n=== {mk} {tf} (اختبار، {m.sum()} إشارة Mp) — المؤشر: King الحالي → King مدرّب على الفريمات الصغيرة')
    for (nm,acc,R,n,tot),(_,acc2,R2,n2,_) in zip(a,b):
        print(f'  {nm:9s} {acc*100:5.1f}% R{R:+.3f} n={n:6.0f}  →  {acc2*100:5.1f}% R{R2:+.3f} n={n2:6.0f}')
# هل يتضرر 15m+ بالنموذج الجديد؟
a=evaluate(hi,teH,old,'old'); b=evaluate(hi,teH,new,'new')
print('\n=== 15m/1h/4h (اختبار الأصلي) — قبل → بعد')
for (nm,acc,R,n,tot),(_,acc2,R2,n2,_) in zip(a,b):
    print(f'  {nm:9s} {acc*100:5.1f}% R{R:+.3f}  →  {acc2*100:5.1f}% R{R2:+.3f}')
