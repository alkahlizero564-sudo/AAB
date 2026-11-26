import pandas as pd, numpy as np, re, json
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
exec(open(S+'/ai/king_tiers.py').read().split("src=open('/home/user/AAB/lib/analysis/king_model.dart')")[0])
src=open('/home/user/AAB/lib/analysis/king_model.dart').read()
feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
mm=load_model('/home/user/AAB/lib/analysis/king_model.dart','king')
Q70=0.5680950185109677
s2=pd.read_csv(S+'/ai/signals2.csv'); key=pd.read_csv(S+'/ai/sdkey.csv'); key['p']=predict(mm,s2[feat].values.astype(np.float32))
Z=pd.read_csv(S+'/ai/zfib2.csv')
mp={'ذهب':'gold20','بيتكوين':'btc'}
for (mk,tf),G in Z.groupby(['mk','tf'],sort=False):
    K=key[(key.market==mp[mk])&(key.tf==tf)]
    mpd={}; kd={}
    for i,d,p in zip(K.i,K.dir,K.p):
        for q in range(i,i+4): mpd[(q,d)]=1; 
        if p>=Q70:
            for q in range(i,i+4): kd[(q,d)]=1
    G=G.copy(); G['mp']=[mpd.get((i,d),0) for i,d in zip(G.i,G.dir)]; G['k']=[kd.get((i,d),0) for i,d in zip(G.i,G.dir)]
    ty=2019 if mk=='ذهب' else 2021; T=G[G.year>=ty]; days=(T.year.max()-ty+1)*260
    print(f'== {mk} {tf}')
    for lab,x in [('كل إشارات المنطقة',T),('+ Mp بنفس الاتجاه (آخر 3 شموع)',T[T.mp==1]),('+ King بنفس الاتجاه',T[T.k==1]),('ارتداد + Mp',T[(T.mp==1)&(T.kind=='ارتداد')]),('كسر + Mp',T[(T.mp==1)&(T.kind=='كسر')])]:
        print(f'   {lab:32s} n={len(x):5d} ({len(x)/days:4.2f}/يوم) | دقة 1R {x.w.mean()*100:5.1f}% | R {x.r.mean():+.3f}')
