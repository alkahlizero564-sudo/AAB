import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
df=pd.read_csv(S+'/ai/signals2.csv')
base=[c for c in df.columns if c not in ['market','tf','year','dir','win','r','src'] and not c.startswith('i_')]
safe=['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
trm=((df.market=='gold20')&(df.year>=2010)&(df.year<=2018))|((df.market=='btc')&(df.year<=2020))
test=(~trm&~((df.market=='gold20')&(df.year<2010))).values; gold=(df.market=='gold20').values
ps=[]
for sd in range(1,4):
    m=RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=sd).fit(df[trm][base+safe].values.astype(np.float32),df.win[trm])
    ptr=m.predict_proba(df[trm][base+safe].values.astype(np.float32))[:,1]; p=m.predict_proba(df[base+safe].values.astype(np.float32))[:,1]
    ps.append((ptr,p))
y=df.win.values; r=df.r.values
st=df.i_stars.values; sm=df.i_sm.values==1
G={'PQ القوية (نجمة+ أو SM)':(st>=1)|sm,'PQ: SM فقط بلا نجوم':sm&(st<1),'النجوم 1+':st>=1,'النجوم 2+':st>=2,'النجوم 3':st>=3,
   'نجوم 1+ و SM':(st>=1)&sm,'نجوم 2+ أو (1+ و SM)':(st>=2)|((st>=1)&sm),'نجوم 1+ + ضغط':(st>=1)&(df.i_hot.values==1),
   'نجوم 1+ + قريب':(st>=1)&(df.i_near.values==1),'نجوم 1+ + KM':(st>=1)&(df.i_km.values==1),'نجوم 1+ + اليومي 200':(st>=1)&(df.i_daily200.values==1)}
print(f"{'المجموعة':28s} | بدون | King 50% | King 30% | King 15% | ذهب بدون→30%")
for nm,g in G.items():
    b=g&test; s=f"{nm:28s} | {y[b].mean()*100:4.1f}% n={b.sum():5d}"
    for top in (50,30,15):
        a=[];n=[];ga=[]
        for ptr,p in ps:
            k=b&(p>=np.quantile(ptr,1-top/100)); a.append(y[k].mean()); n.append(k.sum()); ga.append(y[k&gold].mean())
        s+=f" | {np.mean(a)*100:4.1f}% ({np.mean(n)/max(b.sum(),1)*100:.0f}%)"
        if top==30: g30=np.mean(ga)
    s+=f" | {y[b&gold].mean()*100:4.1f}→{g30*100:4.1f}"
    print(s,flush=True)
print()
hot=df.i_hot.values==1; near=df.i_near.values==1; km=df.i_km.values==1
def K(top,ptr,p): return p>=np.quantile(ptr,1-top/100)
rules={
 'King 30% (الحالي للنجوم)':lambda k30,k15,k50: k30,
 'King 15%':lambda k30,k15,k50: k15,
 'King 30% أو ضغط':lambda k30,k15,k50: k30|hot,
 '(نجوم2+ و King30) أو King15':lambda k30,k15,k50: ((st>=2)&k30)|k15,
 '(نجوم2+ و King30) أو King15 أو ضغط':lambda k30,k15,k50: ((st>=2)&k30)|k15|hot,
 '(نجوم3 و King50) أو (نجوم2+ و King30) أو King15 أو ضغط':lambda k30,k15,k50: ((st>=3)&k50)|((st>=2)&k30)|k15|hot,
 'King 30% و (KM أو قريب أو نجوم2+)':lambda k30,k15,k50: k30&(km|near|(st>=2)),
 'King15 أو ضغط أو (King30 و (KM أو قريب))':lambda k30,k15,k50: k15|hot|(k30&(km|near)),
}
for gname,g in [('النجوم 1+',st>=1),('PQ القوية',(st>=1)|sm)]:
    print('==',gname)
    for nm,f in rules.items():
        a=[];n=[];ga=[];rr=[]
        for ptr,p in ps:
            k=g&test&f(K(30,ptr,p),K(15,ptr,p),K(50,ptr,p)); a.append(y[k].mean()); n.append(k.sum()); ga.append(y[k&gold].mean()); rr.append(r[k].mean())
        print(f"  {nm:58s} {np.mean(a)*100:4.1f}% R{np.mean(rr):+.3f} يبقى {np.mean(n)/(g&test).sum()*100:3.0f}% | ذهب {np.mean(ga)*100:4.1f}%")
