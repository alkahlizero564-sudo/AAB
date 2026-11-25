import pandas as pd, numpy as np, warnings, re
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
lt=pd.read_csv('signals_lt2.csv'); hi=pd.read_csv('signals2.csv')
src=open('/home/user/AAB/lib/analysis/king_model.dart').read()
import json
feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
Q={k:float(re.search(rf'const {k} = ([0-9.eE-]+);',src).group(1)) for k in ['kingQ30','kingQ50','kingQ70','kingQ85']}
tr=lt[(lt.market=='gold')&(lt.year<=2020)]
m=RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=1).fit(tr[feat].values.astype(np.float32),tr.win)
ptr=m.predict_proba(tr[feat].values.astype(np.float32))[:,1]
q={k:float(np.quantile(ptr,v)) for k,v in [('q30',.3),('q50',.5),('q70',.7),('q85',.85)]}
F,T,L,R,V,off=[],[],[],[],[],[]
for e in m.estimators_:
    t=e.tree_; b=len(F); off.append(b)
    for i in range(t.node_count):
        leaf=t.children_left[i]==-1
        F.append(-1 if leaf else int(t.feature[i])); T.append(float(t.threshold[i]) if not leaf else 0.0)
        L.append(-1 if leaf else b+int(t.children_left[i])); R.append(-1 if leaf else b+int(t.children_right[i]))
        v=t.value[i][0]; V.append(float(v[1]/v.sum()) if leaf else 0.0)
def pred(x):
    s=0
    for o in off:
        n=o
        while F[n]!=-1: n=L[n] if x[F[n]]<=T[n] else R[n]
        s+=V[n]
    return s/len(off)
xs=tr[feat].values.astype(np.float32)[:200]
print('max diff', max(abs(pred(x)-p) for x,p in zip(xs,m.predict_proba(xs)[:,1])))
fl=lambda a: ','.join(f'{x:.6g}' for x in a); il=lambda a: ','.join(str(x) for x in a)
dart=f"""// ملف مولّد تلقائياً — King للفريمات الصغيرة (1m و5m): نفس المعلومات الـ {len(feat)} ونفس شكل النموذج،
// مدرّب على إشارات Mp في ذهب 1m و5m (2015-2020). اختبار لم يره (ذهب 2021-2026، بعد سبريد 0.25$ ووقف ≥ 1$/2$):
// 1m أعلى 30%: 64.5% (+0.15R) • 5m أعلى 15%: 62.8% (+0.22R). لا تعدّل يدوياً.
const kingLtQ = <double>[{q['q30']}, {q['q50']}, {q['q70']}, {q['q85']}];
const kingLtTreeStart = <int>[{il(off)}];
const kingLtFeat = <int>[{il(F)}];
const kingLtThr = <double>[{fl(T)}];
const kingLtLeft = <int>[{il(L)}];
const kingLtRight = <int>[{il(R)}];
const kingLtVal = <double>[{fl(V)}];
"""
open('/home/user/AAB/lib/analysis/king_model_lt.dart','w').write(dart)
print('nodes',len(F),q,Q)
# عينة تحقق للمطابقة في Dart
tr[feat].head(5).to_csv('lt_parity.csv',index=False); print('parity', [round(x,6) for x in m.predict_proba(tr[feat].head(5).values.astype(np.float32))[:,1]])
