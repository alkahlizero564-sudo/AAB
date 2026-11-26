exec(open('spread.py').read().split("for tf,f in")[0])
for tf,f in [('15m','gold10/btc10_15m.csv'),('1h','gold10/btc10_1h.csv')]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    m=((key.market=='btc')&(key.tf==tf)).values&(s.p.values>=Q70)
    R=[]
    for i,di in zip(key.i.values[m],key.dir.values[m]):
        if t.iloc[i].year<2021 or i+2>=len(c): continue
        g,rk=sim(o,h,l,c,a,int(i),int(di),0.0,0.0,1.0,2.0); R.append(g/rk)
    R=np.array(R); R=R[~np.isnan(R)]; days=(t.dt.year.max()-2021+1)*365
    print(f'King ⭐+ بيتكوين {tf}: {len(R)/days:.2f}/يوم | نجاح {(R>0).mean()*100:.1f}% | {R.mean():+.3f}R')
