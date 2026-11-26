# هل إشارات King في السوق المتذبذب أسوأ؟ (مؤشر التذبذب CHOP، ADX، كثافة الإشارات المتعاكسة، منطقة TZ رمادية)
import pandas as pd, numpy as np
exec(open('spread.py').read().split("for tf,f in")[0])
for mk,mkk,tf,f,ty,SP in [('ذهب','gold20','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','gold20','1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين','btc','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','btc','1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; yr=pd.to_datetime(d.iloc[:,0]).dt.year.values
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; pc=np.r_[c[0],c[:-1]]
    tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    chop=100*np.log10(pd.Series(tr).rolling(14).sum()/(pd.Series(h).rolling(14).max()-pd.Series(l).rolling(14).min()))/np.log10(14)
    chop=chop.values
    upm=h-np.r_[h[0],h[:-1]]; dnm=np.r_[l[0],l[:-1]]-l
    pdm=np.where((upm>dnm)&(upm>0),upm,0); mdm=np.where((dnm>upm)&(dnm>0),dnm,0)
    R=lambda x: pd.Series(x).ewm(alpha=1/14,adjust=False).mean().values
    pdi=R(pdm)/np.maximum(R(tr),1e-12); mdi=R(mdm)/np.maximum(R(tr),1e-12); adx=R(np.nan_to_num(abs(pdi-mdi)/np.maximum(pdi+mdi,1e-12)))*100
    m=((key.market==mkk)&(key.tf==tf)).values&(s.p.values>=Q70)
    ii=key.i.values[m]; dd=key.dir.values[m]; o_=np.argsort(ii); ii,dd=ii[o_],dd[o_]
    # كثافة: عدد إشارات Mp المتعاكسة في آخر 20 شمعة
    mm=((key.market==mkk)&(key.tf==tf)).values
    mpi=key.i.values[mm]; mpd=key.dir.values[mm]
    rows=[]
    for i,di in zip(ii,dd):
        if yr[i]<ty or i+2>=len(c): continue
        g,rk=sim(o,h,l,c,a,int(i),int(di),0.0,SP,1.0,3.0)
        if g!=g: continue
        opp=((mpi>=i-20)&(mpi<i)&(mpd!=di)).sum()
        rows.append([g/rk,chop[i],adx[i],opp])
    T=pd.DataFrame(rows,columns=['r','chop','adx','opp'])
    print(f'== {mk} {tf} King ⭐+ (اختبار، 1R ثم 3R، بعد السبريد): الكل {T.r.mean():+.3f}R n={len(T)}')
    for lab,x in [('متذبذب CHOP>61.8',T[T.chop>61.8]),('عادي',T[(T.chop<=61.8)&(T.chop>=38.2)]),('ترند CHOP<38.2',T[T.chop<38.2]),
                  ('ADX<20 (بلا اتجاه)',T[T.adx<20]),('ADX≥25 (ترند)',T[T.adx>=25]),
                  ('قبلها إشارة عكسية في 20 شمعة',T[T.opp>0]),('بدون عكسية قريبة',T[T.opp==0])]:
        print(f'    {lab:30s} n={len(x):4d} | {x.r.mean():+.3f}R | لم يضرب الوقف كاملاً {(x.r>-0.99).mean()*100:4.1f}%')
