# مؤشرات واستراتيجيات TradingView من صور المستخدم غير المختبرة سابقاً (~55) — نفس طريقة البحث الكبير: دخول مباشر، وقف خلف 3 شموع، نصف 1R ونصف 2R، سبريد
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
exec(open('zones_failed.py').read().split("rows=[]")[0])          # load, strategies helpers + batch()
def tv2(d):
    o,h,l,c,v=[d[x].values.astype(np.float64) for x in ['open','high','low','close','volume']]
    n=len(c); pc=sh(c); pc[0]=c[0]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=RMA(tr,14)
    hl2=(h+l)/2; hlc3=(h+l+c)/3; out={}
    def add(k,s): out[k]=np.nan_to_num(s).astype(np.int64)
    cu=cross_up; cd=cross_dn; z=lambda x: np.zeros(n)+x
    # --- استراتيجيات TV الجاهزة
    add('Bar up/down',sig((c>o)&(sh(c)<sh(o)),(c<o)&(sh(c)>sh(o))))
    up3=(c>pc)&(sh(c)>sh(c,2))&(sh(c,2)>sh(c,3)); dn3=(c<pc)&(sh(c)<sh(c,2))&(sh(c,2)<sh(c,3))
    add('Consecutive up/down 3',sig(up3&~sh(up3.astype(float)).astype(bool),dn3&~sh(dn3.astype(float)).astype(bool)))
    add('Greedy (فجوة افتتاح)',sig(o>sh(h),o<sh(l)))
    add('Outside bar',sig((h>sh(h))&(l<sh(l))&(c>o),(h>sh(h))&(l<sh(l))&(c<o)))
    hh=HH(h,20); ll=LL(l,20); add('Price channel 20',sig(c>sh(hh),c<sh(ll)))
    pdm=np.where((h-sh(h)>sh(l)-l)&(h-sh(h)>0),h-sh(h),0); mdm=np.where((sh(l)-l>h-sh(h))&(sh(l)-l>0),sh(l)-l,0)
    atr14=RMA(tr,14); pdi=100*RMA(np.nan_to_num(pdm),14)/atr14; mdi=100*RMA(np.nan_to_num(mdm),14)/atr14
    adx=RMA(np.nan_to_num(100*abs(pdi-mdi)/np.maximum(pdi+mdi,1e-12)),14)
    add('Rob Booker ADX breakout',sig((adx<18)&(c>sh(HH(h,20))),(adx<18)&(c<sh(LL(l,20)))))
    add('Volatility expansion-close',sig(c>sh(c)+sh(a)*0.75,c<sh(c)-sh(a)*0.75))
    sma=lambda x,p: SMA(x,p)
    r14=100-100/(1+RMA(np.clip(c-pc,0,None),14)/np.maximum(RMA(np.clip(pc-c,0,None),14),1e-12))
    rating=(np.sign(c-sma(c,10))+np.sign(c-sma(c,20))+np.sign(c-sma(c,50))+np.sign(c-E(c,10))+np.sign(c-E(c,20))+np.sign(c-E(c,50))+np.where(r14<30,1,np.where(r14>70,-1,0)))/7
    add('Technical ratings عبور ±0.5',sig(cu(rating,z(0.5)),cd(rating,z(-0.5))))
    bbm=SMA(c,20); bbs=STD(c,20); add('Bollinger directed (اختراق الحد)',sig(cu(c,bbm+2*bbs),cd(c,bbm-2*bbs)))
    # --- مؤشرات مدمجة
    mfm=((c-l)-(h-c))/np.maximum(h-l,1e-12); cmf=pd.Series(mfm*v).rolling(20).sum().values/np.maximum(pd.Series(v).rolling(20).sum().values,1e-12)
    add('Chaikin money flow عبور 0.05',sig(cu(cmf,z(0.05)),cd(cmf,z(-0.05))))
    ad=np.cumsum(mfm*v); cho=E(ad,3)-E(ad,10); add('Chaikin oscillator عبور الصفر',sig(cu(cho,z(0)),cd(cho,z(0))))
    hs=HH(h,10)-1*RMA(tr,10); ls=LL(l,10)+1*RMA(tr,10); sst=HH(hs,9); lst=LL(ls,9)
    add('Chande Kroll stop',sig(cu(c,sst),cd(c,lst)))
    su=pd.Series(np.clip(c-pc,0,None)).rolling(9).sum().values; sd_=pd.Series(np.clip(pc-c,0,None)).rolling(9).sum().values
    cmo=100*(su-sd_)/np.maximum(su+sd_,1e-12); add('Chande momentum رجوع ±50',sig(cu(cmo,z(-50)),cd(cmo,z(50))))
    roc=lambda x,p: 100*(x-sh(x,p))/np.where(sh(x,p)==0,np.nan,sh(x,p))
    cop=WMA(np.nan_to_num(roc(c,14)+roc(c,11)),10); add('Coppock عبور الصفر',sig(cu(cop,z(0)),cd(cop,z(0))))
    dpo=c-sh(SMA(c,20),11); add('DPO عبور الصفر',sig(cu(dpo,z(0)),cd(dpo,z(0))))
    eom=SMA(((hl2-sh(hl2))*(h-l))/np.maximum(v,1e-12),14); add('Ease of movement عبور الصفر',sig(cu(eom,z(0)),cd(eom,z(0))))
    efi=E((c-pc)*v,13); add('Elder force index عبور الصفر',sig(cu(efi,z(0)),cd(efi,z(0))))
    mx=HH(hl2,9); mn=LL(hl2,9); val=np.zeros(n); fish=np.zeros(n)
    for i in range(1,n):
        x=0.66*((hl2[i]-mn[i])/max(mx[i]-mn[i],1e-12)-0.5)+0.67*val[i-1] if not np.isnan(mx[i]) else 0
        val[i]=min(max(x,-0.999),0.999); fish[i]=0.5*np.log((1+val[i])/(1-val[i]))+0.5*fish[i-1]
    add('Fisher transform تقاطع',sig(cu(fish,sh(fish)),cd(fish,sh(fish))))
    kst=SMA(np.nan_to_num(roc(c,10)),10)+2*SMA(np.nan_to_num(roc(c,15)),10)+3*SMA(np.nan_to_num(roc(c,20)),10)+4*SMA(np.nan_to_num(roc(c,30)),15)
    add('KST تقاطع الإشارة',sig(cu(kst,SMA(kst,9)),cd(kst,SMA(kst,9))))
    tsig=np.sign(hlc3-sh(hlc3)); vf=v*tsig; kvo=E(vf,34)-E(vf,55); add('Klinger تقاطع الإشارة',sig(cu(kvo,E(kvo,13)),cd(kvo,E(kvo,13))))
    md=np.zeros(n); md[0]=c[0]
    for i in range(1,n): md[i]=md[i-1]+(c[i]-md[i-1])/(14*(c[i]/md[i-1])**4) if md[i-1]>0 else c[i]
    add('McGinley dynamic عبور السعر',sig(cu(c,md),cd(c,md)))
    e9=E(h-l,9); mi=pd.Series(e9/np.maximum(E(e9,9),1e-12)).rolling(25).sum().values
    bulge=(sh(mi)>27)&(mi<26.5); add('Mass index انعكاس',sig(bulge&(c<E(c,9)),bulge&(c>E(c,9))))
    x=np.arange(25); xm=x.mean(); den=((x-xm)**2).sum()
    lsma=pd.Series(c).rolling(25).apply(lambda y: y.mean()+((x-xm)*(y-y.mean())).sum()/den*(24-xm),raw=True).values
    add('LSMA 25 عبور السعر',sig(cu(c,lsma),cd(c,lsma)))
    pvt=np.cumsum(np.nan_to_num((c-pc)/np.where(pc==0,np.nan,pc))*v); add('Price-volume trend عبور متوسطه',sig(cu(pvt,E(pvt,21)),cd(pvt,E(pvt,21))))
    num=SMA(c-o,10); dnm=SMA(h-l,10); rvi=num/np.maximum(dnm,1e-12); add('Relative vigor تقاطع',sig(cu(rvi,SMA(rvi,4)),cd(rvi,SMA(rvi,4))))
    m1=c-pc; tsi=100*E(E(m1,25),13)/np.maximum(E(E(abs(m1),25),13),1e-12); add('SMI ergodic تقاطع',sig(cu(tsi,E(tsi,13)),cd(tsi,E(tsi,13))))
    hh10=HH(h,10); ll10=LL(l,10); rel=c-(hh10+ll10)/2; smi=200*E(E(rel,3),3)/np.maximum(E(E(hh10-ll10,3),3),1e-12)
    add('Stochastic momentum index رجوع ±40',sig(cu(smi,z(-40)),cd(smi,z(40))))
    bp=c-np.minimum(l,pc); tr_=np.maximum(h,pc)-np.minimum(l,pc)
    uo=100*(4*pd.Series(bp).rolling(7).sum()/pd.Series(tr_).rolling(7).sum()+2*pd.Series(bp).rolling(14).sum()/pd.Series(tr_).rolling(14).sum()+pd.Series(bp).rolling(28).sum()/pd.Series(tr_).rolling(28).sum()).values/7
    add('Ultimate oscillator رجوع 30/70',sig(cu(uo,z(30)),cd(uo,z(70))))
    jaw=sh(RMA(hl2,13),8); teeth=sh(RMA(hl2,8),5); lips=sh(RMA(hl2,5),3)
    al_up=(lips>teeth)&(teeth>jaw); al_dn=(lips<teeth)&(teeth<jaw)
    add('Williams alligator استيقاظ',sig(al_up&~sh(al_up.astype(float)).astype(bool),al_dn&~sh(al_dn.astype(float)).astype(bool)))
    fu=(sh(h,2)>sh(h,4))&(sh(h,2)>sh(h,3))&(sh(h,2)>sh(h,1))&(sh(h,2)>h); fd=(sh(l,2)<sh(l,4))&(sh(l,2)<sh(l,3))&(sh(l,2)<sh(l,1))&(sh(l,2)<l)
    lastu=pd.Series(np.where(fu,sh(h,2),np.nan)).ffill().values; lastd=pd.Series(np.where(fd,sh(l,2),np.nan)).ffill().values
    add('Williams fractal اختراق',sig(cu(c,lastu),cd(c,lastd)))
    bbp=h-E(c,13); berp=l-E(c,13); add('Bull/Bear power',sig((berp<0)&(berp>sh(berp))&(c>E(c,13)),(bbp>0)&(bbp<sh(bbp))&(c<E(c,13))))
    r3=100-100/(1+RMA(np.clip(c-pc,0,None),3)/np.maximum(RMA(np.clip(pc-c,0,None),3),1e-12))
    strk=np.zeros(n)
    for i in range(1,n): strk[i]=(strk[i-1]+1 if strk[i-1]>=0 else 1) if c[i]>c[i-1] else ((strk[i-1]-1 if strk[i-1]<=0 else -1) if c[i]<c[i-1] else 0)
    rs_=100-100/(1+RMA(np.clip(np.diff(strk,prepend=0),0,None),2)/np.maximum(RMA(np.clip(-np.diff(strk,prepend=0),0,None),2),1e-12))
    pr=pd.Series(roc(c,1)).rolling(100).apply(lambda y:(y[:-1]<y[-1]).mean()*100,raw=True).values
    crsi=(r3+rs_+pr)/3; add('Connors RSI رجوع 10/90',sig(cu(crsi,z(10)),cd(crsi,z(90))))
    cci14=(hlc3-SMA(hlc3,14))/np.maximum(0.015*pd.Series(hlc3).rolling(14).apply(lambda y: np.mean(np.abs(y-y.mean())),raw=True).values,1e-12)
    add('Woodies CCI عبور الصفر 6 شموع',sig(cu(cci14,z(0))&(sh(cci14)<0),cd(cci14,z(0))&(sh(cci14)>0)))
    w=np.exp(-((np.arange(9)-0.85*8)**2)/(2*(9/6)**2)); w/=w.sum(); alma=np.convolve(c,w[::-1],'full')[:n]; alma[:8]=np.nan
    add('ALMA 9 عبور السعر',sig(cu(c,alma),cd(c,alma)))
    dema=2*E(c,20)-E(E(c,20),20); tema=3*E(c,20)-3*E(E(c,20),20)+E(E(E(c,20),20),20)
    add('DEMA/TEMA 20 تقاطع',sig(cu(tema,dema),cd(tema,dema)))
    env=SMA(c,20); add('Envelope 20 ±1% رجوع',sig(cu(c,env*0.99),cd(c,env*1.01)))
    vs=np.zeros(n); vd=np.ones(n,int); ex=c[0]
    for i in range(1,n):
        if np.isnan(a[i]): vs[i]=c[i]; continue
        if vd[i-1]==1:
            ex=max(ex,c[i]); vs[i]=ex-2*a[i]
            if c[i]<vs[i]: vd[i]=-1; ex=c[i]; vs[i]=ex+2*a[i]
            else: vd[i]=1
        else:
            ex=min(ex,c[i]); vs[i]=ex+2*a[i]
            if c[i]>vs[i]: vd[i]=1; ex=c[i]; vs[i]=ex-2*a[i]
            else: vd[i]=-1
    add('Volatility stop انقلاب',flip(vd))
    # --- مؤشرات المجتمع
    kc_u=SMA(c,20)+1.5*SMA(tr,20); kc_l=SMA(c,20)-1.5*SMA(tr,20); bb_u=SMA(c,20)+2*STD(c,20); bb_l=SMA(c,20)-2*STD(c,20)
    sqz=(bb_l>kc_l)&(bb_u<kc_u); val_=pd.Series(c-((HH(h,20)+LL(l,20))/2+SMA(c,20))/2).rolling(20).apply(lambda y: y.mean()+((np.arange(20)-9.5)*(y-y.mean())).sum()/((np.arange(20)-9.5)**2).sum()*9.5,raw=True).values
    rel_=sh(sqz.astype(float)).astype(bool)&~sqz; add('Squeeze Momentum (LazyBear) انطلاق',sig(rel_&(val_>0),rel_&(val_<0)))
    add('Squeeze Momentum عبور الصفر',sig(cu(val_,z(0)),cd(val_,z(0))))
    ap=hlc3; esa=E(ap,10); dd_=E(abs(ap-esa),10); ci=(ap-esa)/np.maximum(0.015*dd_,1e-12); wt1=E(ci,21); wt2=SMA(wt1,4)
    add('WaveTrend (LazyBear) تقاطع في التشبع ±53',sig(cu(wt1,wt2)&(wt1<-53),cd(wt1,wt2)&(wt1>53)))
    add('VuManChu (WaveTrend) تقاطع',sig(cu(wt1,wt2)&(wt1<0),cd(wt1,wt2)&(wt1>0)))
    atr10=RMA(tr,10); ts=np.zeros(n); ts[0]=c[0]
    for i in range(1,n):
        nl=1*atr10[i]
        if c[i]>ts[i-1] and c[i-1]>ts[i-1]: ts[i]=max(ts[i-1],c[i]-nl)
        elif c[i]<ts[i-1] and c[i-1]<ts[i-1]: ts[i]=min(ts[i-1],c[i]+nl)
        else: ts[i]=c[i]-nl if c[i]>ts[i-1] else c[i]+nl
    add('UT Bot (QuantNomad) 1,10',sig(cu(c,ts),cd(c,ts)))
    mfi=None
    tp=hlc3; mfu=np.where(tp>sh(tp),tp*v,0); mfd=np.where(tp<sh(tp),tp*v,0)
    mfi=100*pd.Series(mfu).rolling(14).sum().values/np.maximum(pd.Series(mfu+mfd).rolling(14).sum().values,1e-12)
    atr14s=SMA(tr,14); upT=l-atr14s; dnT=h+atr14s; at=np.zeros(n)
    for i in range(1,n): at[i]=(upT[i] if upT[i]>=at[i-1] else at[i-1]) if mfi[i]>=50 else (dnT[i] if dnT[i]<=at[i-1] else at[i-1])
    add('AlphaTrend (Kivanc) تقاطع',sig(cu(at,sh(at,2)),cd(at,sh(at,2))))
    wvf=(HH(c,22)-l)/HH(c,22)*100; ub=SMA(wvf,20)+2*STD(wvf,20); rh=HH(wvf,50)*0.85
    spike=(wvf>=ub)|(wvf>=rh); add('CM Williams Vix Fix (قاع)',sig(sh(spike.astype(float)).astype(bool)&~spike,np.zeros(n,bool)))
    e38=E(c,38); e62=E(c,62); add('CM Sling Shot',sig((e38>e62)&cu(c,e38),(e38<e62)&cd(c,e38)))
    add('Turtle 20/10',sig(c>sh(HH(h,20)),c<sh(LL(l,20))))
    add('Turtle 55/20',sig(c>sh(HH(h,55)),c<sh(LL(l,55))))
    rib=np.stack([E(c,p) for p in range(10,95,5)]); grn=(rib[:,1:]>rib[:,:-1]).sum(0); grn=np.r_[0,grn]; add('Madrid MA ribbon تحول الأغلبية',sig(cu(grn.astype(float),z(len(rib)*0.7)),cd(grn.astype(float),z(len(rib)*0.3))))
    vidya_a=2/(2+1); cm2=abs(cmo)/100; var=np.zeros(n); var[0]=c[0]
    for i in range(1,n): var[i]=vidya_a*cm2[i]*c[i]+(1-vidya_a*cm2[i])*var[i-1] if not np.isnan(cm2[i]) else c[i]
    fark=var*0.014; lup=var-fark; ldn=var+fark; mt=np.zeros(n); dirn=np.ones(n)
    for i in range(1,n):
        lup[i]=max(lup[i],lup[i-1]) if var[i]>lup[i-1] else lup[i]; ldn[i]=min(ldn[i],ldn[i-1]) if var[i]<ldn[i-1] else ldn[i]
        dirn[i]=1 if (dirn[i-1]==-1 and var[i]>ldn[i-1]) else (-1 if (dirn[i-1]==1 and var[i]<lup[i-1]) else dirn[i-1])
        mt[i]=lup[i] if dirn[i]==1 else ldn[i]
    ott=np.where(var>mt,mt*1.007,mt*0.993); add('OTT (Kivanc) تقاطع',sig(cu(var,sh(ott,2)),cd(var,sh(ott,2))))
    hullf=WMA(2*WMA(c,27)-WMA(c,55),7); add('Hull Suite 55 لون',flip(np.where(hullf>sh(hullf,2),1,-1)))
    add('CM RSI-2 (مع SMA200)',sig((SMA(c,200)<c)&(r3<10),(SMA(c,200)>c)&(r3>90)))
    mac=E(c,12)-E(c,26); add('MACD 4C لون',flip(np.where(mac>sh(mac),1,-1)*np.sign(mac)))
    add('TonyUX EMA scalper 20',sig(cu(c,E(c,20))&(c>HH(h,20)*0.995),cd(c,E(c,20))&(c<LL(l,20)*1.005)))
    lb=4; ph_=(sh(h,lb)==HH(h,2*lb+1)); pl_=(sh(l,lb)==LL(l,2*lb+1))
    lph=pd.Series(np.where(ph_,sh(h,lb),np.nan)).ffill().values; lpl=pd.Series(np.where(pl_,sh(l,lb),np.nan)).ffill().values
    add('Pivot reversal (TV)',sig(cu(c,lph),cd(c,lpl)))
    return out,(o,h,l,c,a)
rows=[]
for label,f,ty,SP in [('ذهب 15m','gold20/xau20_15m.csv',2019,0.25),('ذهب 1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين 15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين 1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=load(f'{S}/{f}'); st,(o,h,l,c,a)=tv2(d)
    yr=d.time.dt.year.values; start=int(np.argmax(yr>=ty)); days=(yr.max()-ty+1)*(260 if 'ذهب' in label else 365)
    rs=np.random.RandomState(1)
    for nm,s in st.items():
        r0=batch(o,h,l,c,a,s,0.0,0,SP,start); x=r0[~np.isnan(r0)]
        sr=np.where(s!=0,np.where(rs.rand(len(s))<0.5,1,-1),0).astype(np.int64)
        rr=batch(o,h,l,c,a,sr,0.0,0,SP,start); xr=rr[~np.isnan(rr)]
        rows.append([label,nm,len(x)/days,(x>0).mean()*100 if len(x) else np.nan,x.mean() if len(x) else np.nan,xr.mean() if len(xr) else np.nan])
    print('done',label,file=sys.stderr,flush=True)
T=pd.DataFrame(rows,columns=['سوق','مؤشر','يوم','نجاح','R','عشوائي'])
T.to_csv('tv2.csv',index=False)
P=T.pivot_table(index='مؤشر',columns='سوق',values='R'); P=P[['ذهب 15m','ذهب 1h','بيتكوين 15m','بيتكوين 1h']]
P['متوسط']=P.mean(axis=1); P['موجب في الأربعة']=(P.iloc[:,:4]>0.02).sum(axis=1)
pd.set_option('display.width',250); pd.set_option('display.max_rows',200)
print(P.sort_values('متوسط',ascending=False).round(3).to_string())
print('\nمتوسط العشوائي بنفس الأوقات:',T.groupby('سوق').عشوائي.mean().round(3).to_dict())
