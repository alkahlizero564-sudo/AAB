import pandas as pd, numpy as np, re, json
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
exec(open(S+'/ai/king_tiers.py').read().split("src=open('/home/user/AAB/lib/analysis/king_model.dart')")[0])
src=open('/home/user/AAB/lib/analysis/king_model.dart').read()
feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
mm=load_model('/home/user/AAB/lib/analysis/king_model.dart','king')
Q={30:0.5680950185109677,15:0.5909170281481894,50:0.5467471078476811}
s=pd.read_csv(S+'/ai/signals2.csv'); key=pd.read_csv(S+'/ai/sdkey.csv'); s['p']=predict(mm,s[feat].values.astype(np.float32)); s['market']=key.market.values
test=((s.market.str.startswith('gold'))&(s.year>=2019))|((~s.market.str.startswith('gold'))&(s.year>=2021))
T=s[test]
def row(lab,x):
    print(f'  {lab:22s} خام: {x.win.mean()*100:5.1f}% (n={len(x):5d}) | ذكاء أعلى 50%: {x[x.p>=Q[50]].win.mean()*100:5.1f}% (n={(x.p>=Q[50]).sum():5d}) | أعلى 30%: {x[x.p>=Q[30]].win.mean()*100:5.1f}% (n={(x.p>=Q[30]).sum():5d})')
row('Mp',T); row('0.1',T[T.src_01==1]); row('AAB',T[T.src_aab==1]); row('Alka',T[T.src_alka==1])
from sklearn.ensemble import RandomForestClassifier
Tr=s[~test]
for nm,col in [('0.1','src_01'),('AAB','src_aab'),('Alka','src_alka')]:
    a=Tr[Tr[col]==1]; b=T[T[col]==1]
    rf=RandomForestClassifier(300,min_samples_leaf=40,max_features=0.3,n_jobs=-1,random_state=1).fit(a[feat],a.win)
    pb=rf.predict_proba(b[feat])[:,1]; pa=rf.predict_proba(a[feat])[:,1]
    for top in [50,30]:
        th=np.quantile(pa,1-top/100)
        x=b[pb>=th]; print(f'  نموذج خاص {nm:5s} أعلى {top}%: {x.win.mean()*100:5.1f}% (n={len(x)})  مقابل King: {b[b.p>=Q[top]].win.mean()*100:5.1f}%')
