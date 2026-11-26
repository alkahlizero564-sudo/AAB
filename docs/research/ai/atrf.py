# ATRF-20: 4 نماذج فرعية (زخم / بنية وسيولة / حالة السوق / الكل) + دمج تكيفي بتعلم ذاتي (بلا نظر للمستقبل) + ممر توقع (كوانتايل) لأفق 5/12/20
exec(open('nextbar.py').read().split("out=[]; vol=[]")[0])
import lightgbm as lgb
MOM=['04','08','11','15','N02','N03','N05','N20','N58','N64','96','49','58','41/42','54','06','09']
STR=['10','12','20','21','22','25','26','27','28','30','31','33','40','98','99','02','24','N04','N12','29','23','38','97','84']
REG=['03','07','14','17','19','36','39','43','44','46','48','50','55','57','59','60','81/83','82','87','88','13','18','52/53','92','90','01','05','16','N27','N45']
def grp(names,pre): return [k for k in names if k.split(' ')[0] in pre]
res=[]
for mk,tf,f,ty,SP in [('ذهب','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c,v=[d[x].values.astype(float) for x in ['open','high','low','close','volume']]; n=len(c)
    pc=np.r_[c[0],c[:-1]]; A=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    F=extra(o,h,l,c,v,feats(t,o,h,l,c,v)); names=list(F)
    X=np.column_stack([np.asarray(F[k],np.float32) for k in names]); X[~np.isfinite(X)]=np.nan
    col={k:i for i,k in enumerate(names)}
    G={'زخم':[col[k] for k in grp(names,MOM)],'بنية وسيولة':[col[k] for k in grp(names,STR)],'حالة السوق':[col[k] for k in grp(names,REG)],'الكل':list(range(len(names)))}
    yr=t.dt.year.values; Rk=outcomes(o,h,l,c,A,SP)
    fut={H:np.r_[(c[H:]-c[:-H])/A[:-H],np.full(H,np.nan)] for H in (5,12,20)}
    tr=(yr<ty)&((yr>=2008) if mk=='ذهب' else True)&~np.isnan(fut[20]); te=(yr>=ty)&~np.isnan(fut[20])
    rs=np.random.RandomState(0); itr=rs.choice(np.where(tr)[0],min(int(tr.sum()),250000),replace=False); ite=np.where(te)[0]
    days=(yr.max()-ty+1)*(260 if mk=='ذهب' else 365)
    for H in (5,12,20):
        y=fut[H]
        P={}; PT={}
        for gname,ci in G.items():
            m=lgb.LGBMClassifier(n_estimators=300,learning_rate=0.03,num_leaves=31,min_child_samples=500,subsample=0.7,subsample_freq=1,colsample_bytree=0.5,verbose=-1,random_state=1)
            m.fit(X[itr][:,ci],(y[itr]>0).astype(int)); P[gname]=m.predict_proba(X[ite][:,ci])[:,1]; PT[gname]=m.predict_proba(X[itr][:,ci])[:,1]
        yt=(y[ite]>0).astype(int)
        acc={g:((P[g]>0.5)==yt).mean()*100 for g in P}
        # دمج ثابت ودمج تكيفي (أوزان أُسية حسب خطأ آخر 500 توقع اكتملت نافذته — بلا نظر للمستقبل)
        st=np.mean([P[g] for g in ['زخم','بنية وسيولة','حالة السوق']],0)
        keys=['زخم','بنية وسيولة','حالة السوق','الكل']; M=np.column_stack([P[g] for g in keys])
        L=-(yt[:,None]*np.log(np.clip(M,1e-6,1))+(1-yt[:,None])*np.log(np.clip(1-M,1e-6,1)))
        cum=np.cumsum(L,0); w=np.zeros_like(M); eta=20.0
        for q in range(len(yt)):
            k2=q-H                                 # آخر توقع اكتمل
            if k2<=0: w[q]=1/4; continue
            lo_=max(0,k2-500); loss=(cum[k2]-(cum[lo_-1] if lo_>0 else 0))/(k2-lo_+1)
            e=np.exp(-eta*(loss-loss.min())); w[q]=e/e.sum()
        ad=(w*M).sum(1)
        res.append([mk,tf,H,'دقة الاتجاه',{**{g:round(a,1) for g,a in acc.items()},'دمج ثابت':round(((st>0.5)==yt).mean()*100,1),'دمج تكيفي (تعلم ذاتي)':round(((ad>0.5)==yt).mean()*100,1)}])
        if H==20:
            # دقة أوضح التوقعات + تداول (1R/2R، سبريد) عند ثقة عالية
            pt_ad=PT['الكل']; th=np.quantile(np.abs(pt_ad-0.5),0.95)
            sel=np.abs(ad-0.5)>=th; dd=np.where(ad>=0.5,1,-1)
            idx=ite[sel]; r=np.where(dd[sel]>0,Rk[idx,0],Rk[idx,1]); r=r[~np.isnan(r)]
            res.append([mk,tf,H,'ثقة عالية (أعلى 5%)',{'دقة 20 شمعة':round(((ad[sel]>0.5)==yt[sel]).mean()*100,1),'إشارات/يوم':round(sel.sum()/days,2),'صفقة 1R/2R بعد السبريد R':round(r.mean(),3)}])
            # ممر التوقع: كوانتايل 10% و90%
            q10=lgb.LGBMRegressor(objective='quantile',alpha=0.1,n_estimators=200,learning_rate=0.05,num_leaves=31,min_child_samples=500,verbose=-1).fit(X[itr],y[itr]).predict(X[ite])
            q90=lgb.LGBMRegressor(objective='quantile',alpha=0.9,n_estimators=200,learning_rate=0.05,num_leaves=31,min_child_samples=500,verbose=-1).fit(X[itr],y[itr]).predict(X[ite])
            cov=((y[ite]>=q10)&(y[ite]<=q90)).mean()*100
            res.append([mk,tf,H,'ممر التوقع 10-90%',{'السعر داخل الممر %':round(cov,1),'عرض الممر (ATR)':round(np.median(q90-q10),1)}])
    print('done',mk,tf,file=sys.stderr,flush=True)
for r in res: print(r[0],r[1],f'أفق {r[2]}',r[3],r[4])
