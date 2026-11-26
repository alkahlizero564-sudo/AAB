exec(open('spread.py').read().split("for tf,f in")[0])
rs=np.random.RandomState(1)
for tf,f in [('15m','gold20/xau20_15m.csv'),('1h','gold20/xau20_1h.csv')]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    m=((key.market=='gold20')&(key.tf==tf)).values&(s.p.values>=Q70)&(s.year.values>=2021)
    ii=key.i.values[m]; dd=key.dir.values[m]; appstop=s.risk.values[m]*a[ii]
    for tp in [(0.35,2.0),(1.0,2.0)]:
        out={}
        for lab,dirs in [('King',dd),('عكس King',-dd),('عشوائي',np.where(rs.rand(len(dd))<0.5,1,-1))]:
            G=[];K=[]
            for i,di in zip(ii,dirs):
                if i+2>=len(c): continue
                g,rk=sim(o,h,l,c,a,int(i),int(di),0.0,0.25,tp[0],tp[1]); G.append(g); K.append(rk)
            G=np.array(G);K=np.array(K);k=~np.isnan(G); out[lab]=(G[k].mean(),(G[k]/K[k]).mean(),np.median(K))
        print(f'{tf} TP {tp}: '+' | '.join(f'{k}: {v[0]:+.2f}$ ({v[1]:+.3f}R)' for k,v in out.items())+f' | وقف المحاكاة (الوسيط) {out["King"][2]:.2f}$ مقابل وقف التطبيق {np.median(appstop):.2f}$')
