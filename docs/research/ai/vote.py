import pandas as pd, numpy as np, re, json
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
exec(open(S+'/ai/king_tiers.py').read().split("src=open('/home/user/AAB/lib/analysis/king_model.dart')")[0])
src=open('/home/user/AAB/lib/analysis/king_model.dart').read()
feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
mm=load_model('/home/user/AAB/lib/analysis/king_model.dart','king')
Q70,Q85=0.5680950185109677,0.5909170281481894
s=pd.read_csv(S+'/ai/signals2.csv'); key=pd.read_csv(S+'/ai/sdkey.csv'); s['p']=predict(mm,s[feat].values.astype(np.float32)); s['market']=key.market.values
V=pd.DataFrame({'Alka':s.src_alka,'AAB':s.src_aab,'0.1':s.src_01,'النجوم':(s.i_stars>=1)*1,'SM':s.i_sm,'KM':s.i_km,'ST':(s.i_st>=0.5648245769585736)*1,'King':(s.p>=Q70)*1,'AK':((s.src_aab==1)&(s.p>=Q85))*1})
s['votes']=V.sum(axis=1)
test=((s.market.str.startswith('gold'))&(s.year>=2019))|((~s.market.str.startswith('gold'))&(s.year>=2021))
T=s[test]; Tr=s[~test]
print('عدد المؤشرات الموافقة (من 9) — كل إشارة Mp هي الحدث الأساسي')
print(f'  {"":12s} اختبار: عدد | دقة 1R | R          تدريب: دقة')
for k in range(0,10):
    x=T[T.votes>=k]; y=Tr[Tr.votes>=k]
    if len(x)<30: break
    print(f'  ≥{k} مؤشرات   {len(x):6d} ({len(x)/len(T)*100:5.1f}%) | {x.win.mean()*100:5.1f}% | {x.r.mean():+.3f}     {y.win.mean()*100:5.1f}%')
print('للمقارنة King وحده (أعلى 30%):', f"{T[T.p>=Q70].win.mean()*100:.1f}% n={int((T.p>=Q70).sum())}")
print('King ⭐⭐ (أعلى 15%):', f"{T[T.p>=Q85].win.mean()*100:.1f}%")
for k in [3,4,5]:
    x=T[(T.votes>=k)&(T.p>=Q70)]; print(f'  ≥{k} مع King: n={len(x)} دقة {x.win.mean()*100:.1f}% R {x.r.mean():+.3f}')
