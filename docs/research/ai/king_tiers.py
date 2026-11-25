# حدود النجوم من نموذج التطبيق نفسه (king_model.dart و king_model_lt.dart) + دقة كل مستوى
import re, json, numpy as np, pandas as pd
def load_model(path,prefix):
    s=open(path).read()
    g=lambda k,t: np.array([t(x) for x in re.search(rf'const {prefix}{k} = <\w+>\[(.*?)\];',s,re.S).group(1).split(',')])
    return g('TreeStart',int),g('Feat',int),g('Thr',float),g('Left',int),g('Right',int),g('Val',float)
def predict(m,X):
    st,f,t,L,R,V=m; out=np.zeros(len(X))
    for o in st:
        n=np.full(len(X),o)
        for _ in range(40):
            leaf=f[n]==-1
            if leaf.all(): break
            fi=np.where(leaf,0,f[n]); go=X[np.arange(len(X)),fi]<=t[n]
            n=np.where(leaf,n,np.where(go,L[n],R[n]))
        out+=V[n]
    return out/len(st)
src=open('/home/user/AAB/lib/analysis/king_model.dart').read()
feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
hi=pd.read_csv('signals2.csv'); lt=pd.read_csv('signals_lt2.csv')
mm=load_model('/home/user/AAB/lib/analysis/king_model.dart','king'); ml=load_model('/home/user/AAB/lib/analysis/king_model_lt.dart','kingLt')
ph=predict(mm,hi[feat].values.astype(np.float32)); pl=predict(ml,lt[feat].values.astype(np.float32))
g=hi.market=='gold20'
trH=((g&(hi.year>=2010)&(hi.year<=2018))|((hi.market=='btc')&(hi.year<=2020))).values
teH=(~trH&~(g&(hi.year<2010))).values
Q=np.quantile(ph[trH],[0.7,0.85,0.93]); print('main q70/q85/q93',Q, 'Dart:',re.search(r'kingQ70 = ([0-9.]+)',src).group(1),re.search(r'kingQ85 = ([0-9.]+)',src).group(1))
trL=((lt.market=='gold')&(lt.year<=2020)).values
QL=np.quantile(pl[trL],[0.7,0.85,0.93]); print('lt q',QL)
y=hi.win.values
for lab,m in [('⭐ (30%-15%)',(ph>=Q[0])&(ph<Q[1])),('⭐⭐ (15%-7%)',(ph>=Q[1])&(ph<Q[2])),('⭐⭐⭐ (أعلى 7%)',ph>=Q[2]),('الكل ⭐+',ph>=Q[0])]:
    k=m&teH; print(f'15m+ {lab}: {y[k].mean()*100:.1f}% n={k.sum()} ذهب {y[k&g.values].mean()*100:.1f}%')
net=(lt.r-np.where(lt.market=='gold',0.25,0)/lt.riskp)>0
wide=(((lt.tf=='1m')&(lt.riskp>=lt.px*0.0003))|((lt.tf=='5m')&(lt.riskp>=lt.px*0.0006))|(lt.market!='gold')).values
for lab,m in [('⭐',(pl>=QL[0])&(pl<QL[1])),('⭐⭐',(pl>=QL[1])&(pl<QL[2])),('⭐⭐⭐',pl>=QL[2])]:
    k=m&~trL&wide; print(f'1m/5m {lab}: {net[k].mean()*100:.1f}% n={k.sum()}')
print('Q93 main',Q[2],'LT q93 (لتحويله) ',QL[2])
