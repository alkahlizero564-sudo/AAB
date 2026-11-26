exec(open('spread.py').read().split("for tf,f in")[0])
Q93=0.6105149837333336
T=[]
for tf,f in [('15m','gold20/xau20_15m.csv'),('1h','gold20/xau20_1h.csv')]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    m=((key.market=='gold20')&(key.tf==tf)).values&(s.p.values>=Q70)
    for i,di,p in zip(key.i.values[m],key.dir.values[m],s.p.values[m]):
        if t.iloc[i].year<2021 or i+2>=len(c): continue
        for tp in [(0.35,2.0),(1.0,2.0),(1.0,3.0)]:
            r,rk=sim(o,h,l,c,a,int(i),int(di),0.0,0.0,tp[0],tp[1])
            T.append([t.iloc[i],tf,p,tp,r,rk])
T=pd.DataFrame(T,columns=['time','tf','p','tp','g','rk']).dropna().sort_values('time')
for tp in [(0.35,2.0),(1.0,2.0),(1.0,3.0)]:
    X=T[T.tp==tp]
    for start in [100,1000]:
        bal=start; peak=start; dd=0; yr={}
        for _,x in X.iterrows():
            lot=max(0.01,np.floor(bal*0.01/(x.rk*100)/0.01)*0.01)
            bal+=lot*100*(x.g-0.25); peak=max(peak,bal); dd=max(dd,(peak-bal)/peak); yr[x.time.year]=bal
        print(f'TP1={tp[0]}R TP2={tp[1]}R | بداية {start}$ ← {bal:,.0f}$ (×{bal/start:.1f}) | أكبر نزول {dd*100:.0f}% | '+' • '.join(f'{y}: {v:,.0f}' for y,v in yr.items()))
