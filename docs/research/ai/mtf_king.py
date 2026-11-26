# King متعدد الفريمات على الذهب: إشارات King من 5m و15m و1h على شارت واحد (2021-2026، سنين لم يرها أي نموذج)
import pandas as pd, numpy as np, re, json
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
exec(open(S+'/ai/king_tiers.py').read().split("src=open('/home/user/AAB/lib/analysis/king_model.dart')")[0])
src=open('/home/user/AAB/lib/analysis/king_model.dart').read()
feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
mm=load_model('/home/user/AAB/lib/analysis/king_model.dart','king'); ml=load_model('/home/user/AAB/lib/analysis/king_model_lt.dart','kingLt')
Q70,Q85=0.5680950185109677,0.5909170281481894; L70,L85=0.62190283,0.66465394
SP=0.25
# 5m (نموذج الفريمات الصغيرة + حد الوقف 0.06%)
g5=pd.read_csv(S+'/ai/signals_g5.csv')
g5['p']=predict(ml,g5[feat].values.astype(np.float32))
c5=pd.read_csv(S+'/m1/xau_5m.csv'); c5['time']=pd.to_datetime(c5.time)
g5['time']=pd.to_datetime(g5.tms,unit='ms')
px=np.interp(g5.tms.values/1000, c5.time.astype('int64').values/1e9, c5.close.values)
g5=g5[(g5.riskp>=px*0.0006)]
g5['k']=g5.p>=L70; g5['k2']=g5.p>=L85
g5['net']=g5.r-SP/g5.riskp
# 15m و1h (النموذج الأساسي) — الوقت من ملف الشموع عبر رقم الشمعة
s2=pd.read_csv(S+'/ai/signals2.csv'); key=pd.read_csv(S+'/ai/sdkey.csv')
s2['p']=predict(mm,s2[feat].values.astype(np.float32))
rows=[]
for tf,f in [('15m','gold20/xau20_15m.csv'),('1h','gold20/xau20_1h.csv')]:
    c=pd.read_csv(S+'/'+f); c['time']=pd.to_datetime(c.time)
    m=((key.market=='gold20')&(key.tf==tf)).values
    x=s2[m].copy(); x['time']=c.time.values[key.i.values[m]]; x['tf']=tf
    rows.append(x)
hi=pd.concat(rows); hi['k']=hi.p>=Q70; hi['k2']=hi.p>=Q85
# نفس الفترة: 2021-2026
g5=g5[g5.time.dt.year>=2021]; hi=hi[hi.time.dt.year>=2021]
days=len(pd.bdate_range('2021-01-01',max(g5.time.max(),hi.time.max())))
def show(lab,x,col='win'):
    print(f'  {lab:34s} n={len(x):5d} ({len(x)/days:4.2f}/يوم) | نجاح {x[col].mean()*100:5.1f}% | R{x.r.mean():+.3f}')
print('== ذهب 2021-2026 — King ⭐+ (أعلى 30%)')
show('5m (بعد السبريد)',g5[g5.k].assign(win=lambda d:(d.net>0).astype(int)))
for tf in ['15m','1h']: show(tf,hi[hi.k&(hi.tf==tf)])
A=pd.concat([g5[g5.k].assign(win=lambda d:(d.net>0).astype(int))[['time','dir','win','r']].assign(tf='5m'),hi[hi.k][['time','dir','win','r','tf']]]).sort_values('time')
show('الكل معاً (متعدد الفريمات)',A)
# تكرار: نفس الاتجاه خلال ساعة من فريمين → نحسبها مرة
A['bucket']=A.time.dt.floor('1h'); dup=A.duplicated(['bucket','dir'])
show('الكل بعد حذف التكرار (نفس الساعة والاتجاه)',A[~dup])
# التعارض: إشارة 5m عكس آخر إشارة King على 1h خلال 8 ساعات
h1=hi[hi.k&(hi.tf=='1h')].sort_values('time')
g=g5[g5.k].sort_values('time').copy()
idx=np.searchsorted(h1.time.values,g.time.values,side='right')-1
ok=idx>=0
lastdir=np.where(ok,h1.dir.values[np.clip(idx,0,None)],0); age=np.where(ok,(g.time.values-h1.time.values[np.clip(idx,0,None)])/np.timedelta64(1,'h'),999)
rec=age<=8
g['agree']=np.where(rec,np.sign(lastdir*g.dir.values),0)
for v,nm in [(1,'مع آخر إشارة 1h'),(-1,'عكس آخر إشارة 1h'),(0,'لا إشارة 1h قريبة')]:
    x=g[g.agree==v]; print(f'  5m {nm:22s} n={len(x):5d} صافي نجاح {(x.net>0).mean()*100:5.1f}% R{x.net.mean():+.3f}')
