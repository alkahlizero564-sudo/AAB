_r=open('reverse.py').read(); exec(_r[:_r.index("for tf,f in [('15m'")])
def load(tf,f):
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    m=((key.market=='gold20')&(key.tf==tf)).values&(s.p.values>=Q70)
    ii=key.i.values[m]; dd=key.dir.values[m]; pp=s.p.values[m]
    sel=t.dt.year.values[ii]>=2021; ii,dd,pp=ii[sel],dd[sel],pp[sel]; q=np.argsort(ii)
    return dict(t=t.values,o=o,h=h,l=l,c=c,a=a,ii=ii[q],dd=dd[q],st=np.where(pp[q]>=Q93,3,np.where(pp[q]>=Q85,2,1)))
M={'15m':load('15m','gold20/xau20_15m.csv'),'1h':load('1h','gold20/xau20_1h.csv')}
dur={'15m':np.timedelta64(15,'m'),'1h':np.timedelta64(60,'m')}
for me,other in [('15m','1h'),('1h','15m')]:
    A=M[me]; B=M[other]
    # وقت ظهور إشارات الفريم الآخر (عند إغلاق شمعتها) → أول شمعة في فريمي تفتح بعدها
    bt=B['t'][B['ii']]+dur[other]
    base=[];B2=[];hit=0;hitB=[];hitK=[]
    for i,di,sx in zip(A['ii'],A['dd'],A['st']):
        r,x=run(A['o'],A['h'],A['l'],A['c'],A['a'],int(i),int(di),0.25,1.0,3.0,-1)
        if np.isnan(r): continue
        t0=A['t'][i]+dur[me]; t1=A['t'][x]
        k=np.where((bt>t0)&(bt<=t1)&(B['dd']!=di))[0]
        rr=r
        if len(k):
            fj=int(np.searchsorted(A['t'],bt[k[0]]))
            if fj<x:
                rr,_=run(A['o'],A['h'],A['l'],A['c'],A['a'],int(i),int(di),0.25,1.0,3.0,fj); hitB.append(r); hitK.append(rr)
        base.append(r); B2.append(rr)
    base=np.array(base);B2=np.array(B2)
    print(f'== صفقات King ذهب {me} وجاءتها إشارة King عكسية من {other}: {len(hitB)} من {len(base)} صفقة')
    print(f'     في الصفقات المتأثرة: الإبقاء {np.mean(hitB):+.3f}R ← الإغلاق عند العكسية {np.mean(hitK):+.3f}R')
    print(f'     كل الصفقات: الإبقاء {base.mean():+.3f}R (مجموع {base.sum():+.0f}R) ← الإغلاق {B2.mean():+.3f}R (مجموع {B2.sum():+.0f}R)')
