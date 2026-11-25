# نقاط ضعف King: الدقة حسب الفريم/السوق/الاتجاه/الوقت/حالة السوق/السنة (اختبار لم يره)
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestClassifier
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
hi=pd.read_csv(S+'/ai/signals2.csv'); lt=pd.read_csv(S+'/ai/signals_lt2.csv')
base=[c for c in hi.columns if c not in ['market','tf','year','dir','win','r','src'] and not c.startswith('i_')]
safe=['i_st','i_stars','i_near','i_hot','i_held','i_sm','i_smstrong','i_km','i_daily200','i_sr_behind','i_sr_ahead','i_ribage','i_lt']
F=base+safe
def rf(X,y,sd): return RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=sd).fit(X.astype(np.float32),y)
# الفريمات الكبيرة: King الأساسي
trH=(((hi.market=='gold20')&(hi.year>=2010)&(hi.year<=2018))|((hi.market=='btc')&(hi.year<=2020))).values
teH=(~trH&~((hi.market=='gold20')&(hi.year<2010))).values
pH=[];qH=[]
for sd in (1,2,3):
    m=rf(hi[F].values[trH],hi.win.values[trH],sd); ptr=m.predict_proba(hi[F].values[trH].astype(np.float32))[:,1]
    pH.append(m.predict_proba(hi[F].values.astype(np.float32))[:,1]); qH.append((np.quantile(ptr,0.7),np.quantile(ptr,0.85)))
hi['p']=np.mean(pH,axis=0); q70=np.mean([q[0] for q in qH]); q85=np.mean([q[1] for q in qH])
# الفريمات الصغيرة: King الصغير (ذهب ≤2020)
trL=((lt.market=='gold')&(lt.year<=2020)).values
pL=[];qL=[]
for sd in (1,2,3):
    m=rf(lt[F].values[trL],lt.win.values[trL],sd); ptr=m.predict_proba(lt[F].values[trL].astype(np.float32))[:,1]
    pL.append(m.predict_proba(lt[F].values.astype(np.float32))[:,1]); qL.append((np.quantile(ptr,0.7),np.quantile(ptr,0.85)))
lt['p']=np.mean(pL,axis=0); l70=np.mean([q[0] for q in qL]); l85=np.mean([q[1] for q in qL])
hi['k30']=hi.p>=q70; hi['k15']=hi.p>=q85; lt['k30']=lt.p>=l70; lt['k15']=lt.p>=l85
# صافي بعد السبريد للفريمات الصغيرة (ذهب) مع حد الوقف
lt['net']=lt.r-np.where(lt.market=='gold',0.25,0)/lt.riskp.clip(lower=1e-9)
lt['wide']=((lt.tf=='1m')&(lt.riskp>=lt.px*0.0003))|((lt.tf=='5m')&(lt.riskp>=lt.px*0.0006))|(lt.market!='gold')
T=hi[teH].copy(); T['grp']=np.where(T.market.isin(['gold20','btc','eth']),T.market,'عملات/مؤشرات')
L=lt[(~trL)&lt.wide].copy()
def tab(D,col,lab,k='k15',y='win'):
    print(f'\n--- {lab}')
    for v,g in D.groupby(col):
        x=g[g[k]]
        if len(x)<40: continue
        flag=' ⚠️ ضعيف' if x[y].mean()<0.56 else ''
        print(f'  {str(v):22s} King قوي: {x[y].mean()*100:5.1f}% (n={len(x):5d}) | King 30%: {g[g.k30][y].mean()*100:5.1f}% | كل الإشارات {g[y].mean()*100:5.1f}%{flag}')
print(f'المرجع: King قوي (15%) على الفريمات الكبيرة = {T[T.k15].win.mean()*100:.1f}%')
tab(T,'tf','الفريم (15m/1h/4h)')
tab(T,'grp','السوق')
T['اتجاه']=np.where(T.dir>0,'شراء','بيع'); tab(T,'اتجاه','الاتجاه')
T['ترند']=np.where(T.d_e200>0.5,'مع الترند',np.where(T.d_e200<-0.5,'عكس الترند','قرب EMA200')); tab(T,'ترند','مع/عكس الترند الكبير')
T['سوق']=np.where(T.adx<20,'عرضي (ADX<20)',np.where(T.adx>30,'ترند قوي (ADX>30)','متوسط')); tab(T,'سوق','حالة السوق')
T['تذبذب']=pd.qcut(T.atr_ratio,3,labels=['هادئ','عادي','متحرك']); tab(T,'تذبذب','التذبذب')
hr=np.round(np.degrees(np.arctan2(T.hour_s,T.hour_c))/15)%24
T['جلسة']=np.select([(hr>=2)&(hr<9),(hr>=9)&(hr<14),(hr>=14)&(hr<19)],['آسيا','لندن','نيويورك'],'آخر الليل'); tab(T,'جلسة','الجلسة (ساعات البيانات)')
T['يوم']=T.wday.astype(int); tab(T,'يوم','يوم الأسبوع (0=الاثنين)')
tab(T,'year','السنة')
tab(T,'src','مصدر الإشارة')
print(f'\n=== الفريمات الصغيرة (بعد السبريد والحد الأدنى للوقف) — King الصغير قوي: {L[L.k15].net.gt(0).mean()*100:.1f}%')
L['ok']=(L.net>0).astype(int)
tab(L,'tf','الفريم (1m/5m)',y='ok')
L['grp']=L.market; tab(L,'grp','السوق',y='ok')
L['اتجاه']=np.where(L.dir>0,'شراء','بيع'); tab(L,'اتجاه','الاتجاه',y='ok')
L['سوق']=np.where(L.adx<20,'عرضي',np.where(L.adx>30,'ترند قوي','متوسط')); tab(L,'سوق','حالة السوق',y='ok')
hr=np.round(np.degrees(np.arctan2(L.hour_s,L.hour_c))/15)%24
L['جلسة']=np.select([(hr>=2)&(hr<9),(hr>=9)&(hr<14),(hr>=14)&(hr<19)],['آسيا','لندن','نيويورك'],'آخر الليل'); tab(L,'جلسة','الجلسة',y='ok')
tab(L,'year','السنة',y='ok')
hi.to_csv(S+'/ai/hi_scored.csv',index=False); lt.to_csv(S+'/ai/lt_scored.csv',index=False)
