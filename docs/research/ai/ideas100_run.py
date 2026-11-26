exec(open('ideas100.py').read())
import lightgbm as lgb
res=[]; AIres=[]
for mk,tf,f,ty,SP in [('ذهب','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c,v=[d[x].values.astype(float) for x in ['open','high','low','close','volume']]; n=len(c)
    pc=np.r_[c[0],c[:-1]]; a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    R=outcomes(o,h,l,c,a,SP); yr=t.dt.year.values; tr=(yr<ty)&((yr>=2008) if mk=='ذهب' else True); te=yr>=ty
    F=feats(t,o,h,l,c,v); names=list(F)
    days=(yr.max()-ty+1)*(260 if mk=='ذهب' else 365)
    allr=R[te].ravel(); allr=allr[~np.isnan(allr)]
    for nm in names:
        x=np.array(F[nm],dtype=float,copy=True); x[~np.isfinite(x)]=np.nan
        xt=x[tr]; xt=xt[~np.isnan(xt)]
        if len(xt)<1000 or np.nanstd(xt)==0: continue
        lo,hi=np.quantile(xt,[0.05,0.95])
        if lo==hi: lo,hi=np.quantile(xt[xt!=np.median(xt)],[0.05,0.95]) if (xt!=np.median(xt)).sum()>100 else (lo,hi)
        def ev(mask,sgn):
            L=R[mask&(x>=hi)&(x!=0),0 if sgn>0 else 1]; Sx=R[mask&(x<=lo)&(x!=0),1 if sgn>0 else 0]
            vv=np.r_[L,Sx]; vv=vv[~np.isnan(vv)]; return vv
        a1=ev(tr,1); a2=ev(tr,-1)
        sg=1 if (a1.mean() if len(a1) else -9)>=(a2.mean() if len(a2) else -9) else -1
        trv=a1 if sg>0 else a2; tev=ev(te,sg)
        res.append([mk,tf,nm,sg,trv.mean() if len(trv) else np.nan,len(tev)/days,tev.mean() if len(tev) else np.nan,(tev>0).mean()*100 if len(tev) else np.nan])
    # نموذج يجمع كل المؤشرات (لجنة): صفوف شراء وبيع (المؤشرات معكوسة للبيع)
    X=np.column_stack([np.asarray(F[k],np.float32) for k in names]); X[~np.isfinite(X)]=np.nan
    idx_tr=np.where(tr&~np.isnan(R[:,0])&~np.isnan(R[:,1]))[0]; rs=np.random.RandomState(0); idx_tr=rs.choice(idx_tr,min(len(idx_tr),250000),replace=False)
    Xtr=np.r_[X[idx_tr],-X[idx_tr]]; ytr=np.r_[R[idx_tr,0]>0,R[idx_tr,1]>0].astype(int)
    m=lgb.LGBMClassifier(n_estimators=400,learning_rate=0.03,num_leaves=31,min_child_samples=400,subsample=0.7,subsample_freq=1,colsample_bytree=0.4,verbose=-1,random_state=1).fit(Xtr,ytr)
    ptr=m.predict_proba(Xtr)[:,1]
    idx_te=np.where(te&~np.isnan(R[:,0])&~np.isnan(R[:,1]))[0]
    pl=m.predict_proba(X[idx_te])[:,1]; ps=m.predict_proba(-X[idx_te])[:,1]
    for top in [5,1,0.3]:
        th=np.quantile(ptr,1-top/100)
        vv=np.r_[R[idx_te[pl>=th],0],R[idx_te[ps>=th],1]]
        AIres.append([mk,tf,top,len(vv)/days,(vv>0).mean()*100,vv.mean()])
    AIres.append([mk,tf,'عشوائي',np.nan,(allr>0).mean()*100,allr.mean()])
    print('done',mk,tf,file=sys.stderr,flush=True)
D=pd.DataFrame(res,columns=['mk','tf','ind','sign','trR','perday','teR','win'])
D.to_csv('ideas100.csv',index=False)
P=D.pivot_table(index='ind',columns=['mk','tf'],values='teR')
P['متوسط']=P.mean(axis=1); P['موجب في الأربعة']=(P.iloc[:,:4]>0).sum(axis=1)
pd.set_option('display.width',250); pd.set_option('display.max_rows',200)
print('كل مؤشر وحده (اختبار، R لكل صفقة بعد السبريد) — مرتبة')
print(P.sort_values('متوسط',ascending=False).round(3).to_string())
print('\nالعشوائي: ذهب 15m/1h وبيتكوين — انظر أسفل')
for r in AIres: print('  ',r[0],r[1],('نموذج يجمع الكل أعلى '+str(r[2])+'%') if r[2]!='عشوائي' else 'عشوائي',f'{r[3]:.1f}/يوم' if r[3]==r[3] else '',f'نجاح {r[4]:.1f}%',f'{r[5]:+.3f}R')
