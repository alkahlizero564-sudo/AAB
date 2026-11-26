# 100 فكرة "الشمعة القادمة": توقع اتجاه وحجم الشمعة التالية — 63 مؤشر سابق + مؤشرات جديدة، كل مؤشر وحده + نموذج مركّب (فكرة 100)
exec(open('ideas100.py').read())
import lightgbm as lgb
def extra(o,h,l,c,v,F):
    pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); A=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    rng=np.maximum(h-l,1e-12); pos=(c-l)/rng; up=h-np.maximum(o,c); dn=np.minimum(o,c)-l
    F['N02 تسارع الإغلاق النسبي (3 شموع)']=pos-sh(pos,2)
    F['N03 توازن دفع القاع والقمة']=(c-l-(h-c))/rng
    F['N04 كفاءة الاختراق (بقاء خارج الشمعة السابقة)']=np.where(c>sh(h),(c-sh(h))/A,0)+np.where(c<sh(l),(c-sh(l))/A,0)
    F['N05 استنزاف الزخم المتعاقب']=(c-pc)/A-sh((c-pc)/A)
    F['N12 سرعة كسر الطرف السابق']=np.where(h>sh(h),(h-sh(h))/A,0)-np.where(l<sh(l),(sh(l)-l)/A,0)
    F['N20 الإغلاق مقابل إغلاق السابقة']=(c-pc)/A
    F['N27 نسبة الذيل السفلي للعلوي']=np.log((dn+1e-9*A)/(up+1e-9*A)+1e-9)
    F['N45 توازن النصف العلوي والسفلي']=((c+o)/2-(h+l)/2)/rng
    F['N58 تراكم الزخم الحراري المتناقص']=pd.Series((c-pc)/A).ewm(span=5,adjust=False).mean().values
    F['N64 صافي قوة الإغلاقات']=pd.Series(np.sign(c-pc)).rolling(5).sum().values
    return F
out=[]; vol=[]
for mk,tf,f,ty,SP in [('ذهب','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c,v=[d[x].values.astype(float) for x in ['open','high','low','close','volume']]; n=len(c)
    F=extra(o,h,l,c,v,feats(t,o,h,l,c,v)); names=list(F)
    nb=np.r_[c[1:]-o[1:],np.nan]                       # جسم الشمعة التالية ($)
    nr=np.r_[h[1:]-l[1:],np.nan]
    yr=t.dt.year.values; tr=(yr<ty)&((yr>=2008) if mk=='ذهب' else True)&~np.isnan(nb); te=(yr>=ty)&~np.isnan(nb)
    pc=np.r_[c[0],c[:-1]]; A=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    for nm in names:
        x=np.array(F[nm],dtype=float,copy=True); x[~np.isfinite(x)]=np.nan
        ok_tr=tr&~np.isnan(x)&(x!=0); ok_te=te&~np.isnan(x)&(x!=0)
        if ok_tr.sum()<1000: continue
        sg=np.sign(np.corrcoef(x[ok_tr],nb[ok_tr])[0,1]) or 1
        lo,hi=np.quantile(x[ok_tr],[0.1,0.9])
        sel=ok_te&((x>=hi)|(x<=lo)); dirn=np.where(x>=hi,sg,-sg)[sel]
        pnl=dirn*nb[sel]-SP
        out.append([mk,tf,nm,(np.sign(nb[sel])==dirn).mean()*100,(pnl/A[sel]).mean()])
    # نموذج مركّب (فكرة 100): يتوقع اتجاه الشمعة التالية
    X=np.column_stack([np.asarray(F[k],np.float32) for k in names]); X[~np.isfinite(X)]=np.nan
    itr=np.where(tr)[0]; rs=np.random.RandomState(0); itr=rs.choice(itr,min(len(itr),300000),replace=False); ite=np.where(te)[0]
    m=lgb.LGBMClassifier(n_estimators=300,learning_rate=0.03,num_leaves=31,min_child_samples=500,subsample=0.7,subsample_freq=1,colsample_bytree=0.4,verbose=-1,random_state=1).fit(X[itr],(nb[itr]>0).astype(int))
    p=m.predict_proba(X[ite])[:,1]; ptr=m.predict_proba(X[itr])[:,1]
    for top in [100,20,5,1]:
        lo,hi=np.quantile(ptr,[top/200,1-top/200]) if top<100 else (0.5,0.5)
        sel=(p>=hi)|(p<lo); dirn=np.where(p>=hi,1,-1)[sel]; nbs=nb[ite][sel]
        out.append([mk,tf,f'★ النموذج المركّب (أوضح {top}%)',(np.sign(nbs)==dirn).mean()*100,((dirn*nbs-SP)/A[ite][sel]).mean()])
    # حجم الشمعة التالية: هل يمكن توقعه؟
    mr=lgb.LGBMRegressor(n_estimators=200,learning_rate=0.05,num_leaves=31,min_child_samples=500,verbose=-1).fit(X[itr],nr[itr]/A[itr])
    pr=mr.predict(X[ite]); y=nr[ite]/A[ite]; k=~np.isnan(y)
    vol.append([mk,tf,np.corrcoef(pr[k],y[k])[0,1]])
    print('done',mk,tf,file=sys.stderr,flush=True)
D=pd.DataFrame(out,columns=['mk','tf','ind','acc','r'])
P=D.pivot_table(index='ind',columns=['mk','tf'],values='acc'); P['متوسط الدقة']=P.mean(axis=1)
Q=D.pivot_table(index='ind',columns=['mk','tf'],values='r'); 
pd.set_option('display.width',250); pd.set_option('display.max_rows',200)
print('دقة توقع اتجاه الشمعة التالية % (اختبار) — أعلى 15 وأدنى 5')
S2=P.sort_values('متوسط الدقة',ascending=False).round(1); print(S2.head(15).to_string()); print('...'); print(S2.tail(5).to_string())
print('\nالربح بعد السبريد لو دخلت الشمعة التالية فقط (بالـ ATR لكل صفقة) — النموذج المركّب:')
print(Q[Q.index.str.startswith('★')].round(3).to_string())
print('\nتوقع حجم الشمعة التالية (ارتباط التوقع بالحقيقة):'); [print('  ',x[0],x[1],f'{x[2]:.2f}') for x in vol]
