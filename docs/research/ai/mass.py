# بحث آلي: 1000+ استراتيجية بأسلوب TradingView على كل الأسواق — تدريب/اختبار/أسواق محجوزة
import pandas as pd, numpy as np, sys, warnings, itertools, json
warnings.filterwarnings('ignore')
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
src=open(S+'/ai/flow2.py').read(); exec(src[src.index('@njit'):src.index('def load')].replace('cache=True','cache=False').replace('@njit','from numba import njit\n@njit',1))

def load(p,yf=False):
    if yf:
        d=pd.read_csv(p,skiprows=3,header=None,names=['time','close','high','low','open','volume'])
    else:
        d=pd.read_csv(p); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'})
    d['time']=pd.to_datetime(d.time,utc=True,errors='coerce')
    d=d.dropna(subset=['time','open','high','low','close']).sort_values('time').drop_duplicates('time').reset_index(drop=True)
    if 'volume' not in d: d['volume']=0
    return d

# ───────────── مؤشرات (نفس تعريفات TradingView الشائعة) ─────────────
def E(x,p): return pd.Series(x).ewm(span=p,adjust=False).mean().values
def RMA(x,p): return pd.Series(x).ewm(alpha=1/p,adjust=False).mean().values
def SMA(x,p): return pd.Series(x).rolling(p).mean().values
def STD(x,p): return pd.Series(x).rolling(p).std(ddof=0).values
def HH(x,p): return pd.Series(x).rolling(p).max().values
def LL(x,p): return pd.Series(x).rolling(p).min().values
def sh(x,k=1): return np.r_[np.full(k,np.nan),x[:-k]]
def WMA(x,p):
    w=np.arange(1,p+1); return pd.Series(x).rolling(p).apply(lambda v: np.dot(v,w)/w.sum(),raw=True).values
def HMA(x,p): return WMA(2*WMA(x,p//2)-WMA(x,p),int(np.sqrt(p)))
@njit
def st_dir(h,l,c,a,m):
    n=len(c); dirn=np.ones(n,np.int64); up=np.zeros(n); dn=np.zeros(n)
    for i in range(n):
        hl=(h[i]+l[i])/2; bu=hl-m*a[i]; bd=hl+m*a[i]
        if i==0 or np.isnan(a[i]): up[i]=bu; dn[i]=bd; continue
        up[i]=max(bu,up[i-1]) if c[i-1]>up[i-1] else bu
        dn[i]=min(bd,dn[i-1]) if c[i-1]<dn[i-1] else bd
        if dirn[i-1]==-1 and c[i]>dn[i-1]: dirn[i]=1
        elif dirn[i-1]==1 and c[i]<up[i-1]: dirn[i]=-1
        else: dirn[i]=dirn[i-1]
    return dirn
@njit
def psar_dir(h,l,af0,afm):
    n=len(h); d=np.ones(n,np.int64); sar=l[0]; ep=h[0]; af=af0; up=True
    for i in range(1,n):
        sar=sar+af*(ep-sar)
        if up:
            sar=min(sar,l[i-1],l[i-2] if i>1 else l[i-1])
            if l[i]<sar: up=False; sar=ep; ep=l[i]; af=af0
            elif h[i]>ep: ep=h[i]; af=min(af+af0,afm)
        else:
            sar=max(sar,h[i-1],h[i-2] if i>1 else h[i-1])
            if h[i]>sar: up=True; sar=ep; ep=h[i]; af=af0
            elif l[i]<ep: ep=l[i]; af=min(af+af0,afm)
        d[i]=1 if up else -1
    return d
@njit
def kama(c,p,f,s):
    n=len(c); out=np.full(n,np.nan); fc=2/(f+1); sc=2/(s+1)
    out[p]=c[p]
    for i in range(p+1,n):
        ch=abs(c[i]-c[i-p]); vol=0.0
        for k in range(i-p+1,i+1): vol+=abs(c[k]-c[k-1])
        er=ch/vol if vol>0 else 0
        sm=(er*(fc-sc)+sc)**2
        out[i]=out[i-1]+sm*(c[i]-out[i-1])
    return out

def cross_up(a,b): return (a>b)&(sh(a)<=sh(b))
def cross_dn(a,b): return (a<b)&(sh(a)>=sh(b))
def sig(b,s): return np.where(b,1,np.where(s,-1,0))
def flip(d): return np.where((d==1)&(sh(d)==-1),1,np.where((d==-1)&(sh(d)==1),-1,0))

def strategies(d):
    o,h,l,c,v=[d[x].values.astype(np.float64) for x in ['open','high','low','close','volume']]
    n=len(c); pc=sh(c); pc[0]=c[0]
    tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=RMA(tr,14)
    out={}
    def add(name,s): out[name]=np.nan_to_num(s).astype(np.int64)
    dl=np.diff(c,prepend=c[0])
    def rsi(p): return 100-100/(1+RMA(np.clip(dl,0,None),p)/np.maximum(RMA(np.clip(-dl,0,None),p),1e-12))
    for p in (2,7,14,21):
        r=rsi(p)
        for lo,hi in ((30,70),(20,80),(10,90)):
            add(f'RSI{p} رجوع من تشبع {lo}/{hi}',sig(cross_up(r,np.full(n,lo)),cross_dn(r,np.full(n,hi))))
            add(f'RSI{p} دخول تشبع {lo}/{hi} (زخم)',sig(cross_up(r,np.full(n,hi)),cross_dn(r,np.full(n,lo))))
        add(f'RSI{p} عبور 50',sig(cross_up(r,np.full(n,50)),cross_dn(r,np.full(n,50))))
    for kp,dp in ((5,3),(14,3),(21,5)):
        k=100*(c-LL(l,kp))/np.maximum(HH(h,kp)-LL(l,kp),1e-12); k=SMA(k,3); dd=SMA(k,dp)
        add(f'ستوكاستك {kp},{dp} تقاطع في التشبع',sig(cross_up(k,dd)&(dd<20),cross_dn(k,dd)&(dd>80)))
        add(f'ستوكاستك {kp},{dp} تقاطع',sig(cross_up(k,dd),cross_dn(k,dd)))
    for f_,s_,g_ in ((12,26,9),(8,21,5),(5,35,5),(24,52,9)):
        m=E(c,f_)-E(c,s_); sg=E(m,g_); hs=m-sg
        add(f'MACD {f_},{s_},{g_} تقاطع الإشارة',sig(cross_up(m,sg),cross_dn(m,sg)))
        add(f'MACD {f_},{s_},{g_} عبور الصفر',sig(cross_up(m,np.zeros(n)),cross_dn(m,np.zeros(n))))
        add(f'MACD {f_},{s_},{g_} انعطاف الهيستوغرام',sig((hs>sh(hs))&(sh(hs)<=sh(hs,2))&(hs<0),(hs<sh(hs))&(sh(hs)>=sh(hs,2))&(hs>0)))
    tp=(h+l+c)/3
    for p in (14,20,50):
        md=pd.Series(tp).rolling(p).apply(lambda x: np.mean(np.abs(x-x.mean())),raw=True).values
        cci=(tp-SMA(tp,p))/np.maximum(0.015*md,1e-12)
        add(f'CCI{p} رجوع من ±100',sig(cross_up(cci,np.full(n,-100)),cross_dn(cci,np.full(n,100))))
        add(f'CCI{p} اختراق ±100',sig(cross_up(cci,np.full(n,100)),cross_dn(cci,np.full(n,-100))))
        add(f'CCI{p} عبور الصفر',sig(cross_up(cci,np.zeros(n)),cross_dn(cci,np.zeros(n))))
    for p in (14,28):
        wr=-100*(HH(h,p)-c)/np.maximum(HH(h,p)-LL(l,p),1e-12)
        add(f'Williams%R{p} رجوع',sig(cross_up(wr,np.full(n,-80)),cross_dn(wr,np.full(n,-20))))
        add(f'Williams%R{p} اختراق',sig(cross_up(wr,np.full(n,-20)),cross_dn(wr,np.full(n,-80))))
    for p,k in ((20,2),(20,2.5),(50,2),(10,1.5)):
        mid=SMA(c,p); sd=STD(c,p); ub=mid+k*sd; lb=mid-k*sd
        add(f'بولينجر {p},{k} رجوع للداخل',sig(cross_up(c,lb),cross_dn(c,ub)))
        add(f'بولينجر {p},{k} اختراق',sig(cross_up(c,ub),cross_dn(c,lb)))
        add(f'بولينجر {p},{k} عبور الوسط',sig(cross_up(c,mid),cross_dn(c,mid)))
        z=(c-mid)/np.maximum(sd,1e-12)
        add(f'Z-Score {p} ±{k} ارتداد',sig(cross_up(z,np.full(n,-k)),cross_dn(z,np.full(n,k))))
    for p,k in ((20,1.5),(20,2),(50,2.5)):
        mid=E(c,p); ku=mid+k*a; kl=mid-k*a
        add(f'كيلتنر {p},{k} اختراق',sig(cross_up(c,ku),cross_dn(c,kl)))
        add(f'كيلتنر {p},{k} رجوع',sig(cross_up(c,kl),cross_dn(c,ku)))
    for p in (10,20,55):
        add(f'دونشيان {p} اختراق',sig(c>sh(HH(h,p)),c<sh(LL(l,p))))
        add(f'دونشيان {p} فشل الاختراق',sig((l<sh(LL(l,p)))&(c>sh(LL(l,p))),(h>sh(HH(h,p)))&(c<sh(HH(h,p)))))
    for p,m in ((7,3),(10,3),(14,2),(20,4)):
        add(f'سوبرترند {p},{m} انقلاب',flip(st_dir(h,l,c,RMA(tr,p),float(m))))
    for af,mx in ((0.02,0.2),(0.01,0.1),(0.04,0.4)):
        add(f'PSAR {af},{mx} انقلاب',flip(psar_dir(h,l,af,mx)))
    for f_,s_ in ((5,20),(9,21),(20,50),(50,200),(8,34)):
        add(f'تقاطع EMA {f_}/{s_}',sig(cross_up(E(c,f_),E(c,s_)),cross_dn(E(c,f_),E(c,s_))))
        add(f'تقاطع SMA {f_}/{s_}',sig(cross_up(SMA(c,f_),SMA(c,s_)),cross_dn(SMA(c,f_),SMA(c,s_))))
    for p in (9,21,55):
        hm=HMA(c,p); add(f'Hull {p} انعطاف',sig((hm>sh(hm))&(sh(hm)<=sh(hm,2)),(hm<sh(hm))&(sh(hm)>=sh(hm,2))))
    for p in (10,21):
        km=kama(c,p,2,30); add(f'KAMA {p} عبور السعر',sig(cross_up(c,km),cross_dn(c,km)))
    upm=np.diff(h,prepend=h[0]); dnm=-np.diff(l,prepend=l[0])
    pdi=100*RMA(np.where((upm>dnm)&(upm>0),upm,0.0),14)/np.maximum(a,1e-12); mdi=100*RMA(np.where((dnm>upm)&(dnm>0),dnm,0.0),14)/np.maximum(a,1e-12)
    adx=RMA(100*abs(pdi-mdi)/np.maximum(pdi+mdi,1e-12),14)
    add('DI تقاطع',sig(cross_up(pdi,mdi),cross_dn(pdi,mdi)))
    add('DI تقاطع + ADX>25',sig(cross_up(pdi,mdi)&(adx>25),cross_dn(pdi,mdi)&(adx>25)))
    for p in (14,25):
        au=100*(p-pd.Series(h).rolling(p+1).apply(lambda x: p-np.argmax(x),raw=True).values)/p
        ad=100*(p-pd.Series(l).rolling(p+1).apply(lambda x: p-np.argmin(x),raw=True).values)/p
        add(f'Aroon {p} تقاطع',sig(cross_up(au,ad),cross_dn(au,ad)))
    mf=tp*v; pos=pd.Series(np.where(tp>sh(tp),mf,0)).rolling(14).sum().values; neg=pd.Series(np.where(tp<sh(tp),mf,0)).rolling(14).sum().values
    mfi=100-100/(1+pos/np.maximum(neg,1e-12))
    add('MFI14 رجوع 20/80',sig(cross_up(mfi,np.full(n,20)),cross_dn(mfi,np.full(n,80))))
    obv=np.cumsum(np.sign(dl)*v); add('OBV عبور متوسطه 20',sig(cross_up(obv,E(obv,20)),cross_dn(obv,E(obv,20))))
    ten=(HH(h,9)+LL(l,9))/2; kij=(HH(h,26)+LL(l,26))/2; sa=sh((ten+kij)/2,26); sb=sh((HH(h,52)+LL(l,52))/2,26)
    add('إيشيموكو TK تقاطع',sig(cross_up(ten,kij),cross_dn(ten,kij)))
    add('إيشيموكو اختراق السحابة',sig(cross_up(c,np.maximum(sa,sb)),cross_dn(c,np.minimum(sa,sb))))
    hc=(o+h+l+c)/4; ho=np.zeros(n); ho[0]=o[0]
    for i in range(1,n): ho[i]=(ho[i-1]+hc[i-1])/2
    hd=np.sign(hc-ho); add('هايكن آشي انقلاب',sig((hd>0)&(sh(hd)<0),(hd<0)&(sh(hd)>0)))
    add('هايكن آشي شمعتان',sig((hd>0)&(sh(hd)>0)&(sh(hd,2)<0),(hd<0)&(sh(hd)<0)&(sh(hd,2)>0)))
    for p in (10,20): r_=c-sh(c,p); add(f'Momentum {p} عبور الصفر',sig(cross_up(r_,np.zeros(n)),cross_dn(r_,np.zeros(n))))
    tx=E(E(E(np.log(c),15),15),15); trix=np.diff(tx,prepend=tx[0])*1e4; add('TRIX تقاطع الإشارة',sig(cross_up(trix,E(trix,9)),cross_dn(trix,E(trix,9))))
    ao=SMA((h+l)/2,5)-SMA((h+l)/2,34); add('Awesome عبور الصفر',sig(cross_up(ao,np.zeros(n)),cross_dn(ao,np.zeros(n))))
    add('Awesome صحن',sig((ao>0)&(ao>sh(ao))&(sh(ao)<sh(ao,2)),(ao<0)&(ao<sh(ao))&(sh(ao)>sh(ao,2))))
    for p,m in ((22,3),(14,2)):
        lc=HH(h,p)-m*RMA(tr,p); sc_=LL(l,p)+m*RMA(tr,p)
        add(f'Chandelier {p},{m} اختراق',sig(cross_up(c,sh(sc_)),cross_dn(c,sh(lc))))
    vp=pd.Series(abs(h-sh(l))).rolling(14).sum().values; vm=pd.Series(abs(l-sh(h))).rolling(14).sum().values; trs=pd.Series(tr).rolling(14).sum().values
    add('Vortex تقاطع',sig(cross_up(vp/trs,vm/trs),cross_dn(vp/trs,vm/trs)))
    e13=E(c,13); bp=h-e13; bep=l-e13
    add('Elder-Ray',sig((e13>sh(e13))&(bep<0)&(bep>sh(bep)),(e13<sh(e13))&(bp>0)&(bp<sh(bp))))
    rng=np.maximum(h-l,1e-12); body=c-o
    add('ابتلاع',sig((body>0)&(sh(body)<0)&(c>=sh(o))&(o<=sh(c)),(body<0)&(sh(body)>0)&(c<=sh(o))&(o>=sh(c))))
    add('بن بار',sig((np.minimum(o,c)-l)/rng>0.6,(h-np.maximum(o,c))/rng>0.6))
    add('كسر الشمعة الداخلية',sig((sh(h)<sh(h,2))&(sh(l)>sh(l,2))&(c>sh(h)),(sh(h)<sh(h,2))&(sh(l)>sh(l,2))&(c<sh(l))))
    add('نجمة الصباح/المساء',sig((sh(body,2)<-0.6*sh(a,2))&(abs(sh(body))<0.3*sh(a))&(body>0.6*a),(sh(body,2)>0.6*sh(a,2))&(abs(sh(body))<0.3*sh(a))&(body<-0.6*a)))
    add('3 جنود/غربان',sig((body>0)&(sh(body)>0)&(sh(body,2)>0)&(c>sh(c))&(sh(c)>sh(c,2)),(body<0)&(sh(body)<0)&(sh(body,2)<0)&(c<sh(c))&(sh(c)<sh(c,2))))
    add('NR7 اختراق',sig((sh(rng)<=pd.Series(rng).rolling(7).min().shift(2).values)&(c>sh(h)),(sh(rng)<=pd.Series(rng).rolling(7).min().shift(2).values)&(c<sh(l))))
    mid=SMA(c,20); sd=STD(c,20); sq=(mid+2*sd<E(c,20)+1.5*a)&(mid-2*sd>E(c,20)-1.5*a)
    mom=c-(HH(h,20)+LL(l,20)+2*SMA(c,20))/4
    sqf=sq.astype(float); rel=(sh(sqf)==1)&(sqf==0)
    add('Squeeze انطلاق',sig(rel&(mom>0),rel&(mom<0)))
    day=d.time.dt.floor('D'); g=d.groupby(day)
    ph_=day.map(g.high.max().shift(1)).values; pl_=day.map(g.low.min().shift(1)).values; pc_=day.map(g.close.last().shift(1)).values
    pp=(ph_+pl_+pc_)/3; r1=2*pp-pl_; s1=2*pp-ph_
    add('Pivot S1/R1 ارتداد',sig((l<=s1)&(c>s1),(h>=r1)&(c<r1)))
    add('Pivot R1/S1 اختراق',sig(cross_up(c,r1),cross_dn(c,s1)))
    add('Pivot PP عبور',sig(cross_up(c,pp),cross_dn(c,pp)))
    # دايفرجنس RSI14 بسيط: قاع أدنى في السعر (20) مع RSI أعلى
    r=rsi(14); llp=LL(l,20); hhp=HH(h,20)
    add('دايفرجنس RSI',sig((l<=llp)&(r>sh(LL(r,20),5))&(r<40),(h>=hhp)&(r<sh(HH(r,20),5))&(r>60)))
    # فلاتر لكل قاعدة: بلا فلتر / مع ترند EMA200 / مع ADX>25 / ضد الترند
    e200=E(c,200); up=c>e200
    base=dict(out); final={}
    for nm,s in base.items():
        final[nm]=s
        final[nm+' + مع الترند']=np.where(((s>0)&up)|((s<0)&~up),s,0)
        final[nm+' + ADX>25']=np.where(adx>25,s,0)
        final[nm+' + عكس الترند']=np.where(((s>0)&~up)|((s<0)&up),s,0)
    return final,(o,h,l,c,a)

SEL=[('ذهب 15m','gold20/xau20_15m.csv',2018,0.25),('ذهب 1h','gold20/xau20_1h.csv',2018,0.25),
     ('بيتكوين 15m','gold10/btc10_15m.csv',2020,0.0),('بيتكوين 1h','gold10/btc10_1h.csv',2020,0.0),
     ('برنت 15m','fx/brent_15m.csv',2011,0.03),('برنت 1h','fx/brent_1h.csv',2011,0.03)]
HOLD=[('إيثيريوم 1h','data/eth_1h_1819.csv+data/eth_1h_2526.csv',0.0),('يورو 2019 1h','data/EUR_USD_1h.csv',0.00012),('يورو 2024-26 1h','fx/EURUSD_1H_ModelTest/EURUSD_H1_2years_yfinance.csv',0.00012),
      ('باوند 1h','data/GBP_USD_1h.csv',0.00015),('أسترالي 1h','data/AUD_USD_1h.csv',0.00012),('كندي 1h','data/USD_CAD_1h.csv',0.00015),
      ('ناسداك 2019 1h','data/NAS100_USD_1h.csv',1.0),('نفط WTI 1h','data/WTICO_USD_1h.csv',0.03),('ذهب 5m','m1/xau_5m.csv',0.25)]
res={}   # (strategy, set, phase) -> (n, sumR, wins)
def run(label,d,SP,split_year=None):
    st,(o,h,l,c,a)=strategies(d)
    yr=d.time.dt.year.values
    for nm,s in st.items():
        s=s.copy(); s[:250]=0
        if not s.any(): continue
        w=np.full(len(c),-1,np.int64); r=np.zeros(len(c)); w2=np.full(len(c),-1,np.int64); r2=np.zeros(len(c))
        simall(o,h,l,c,a,s,np.full(len(c),np.nan),w,r,w2,r2)
        m=w>=0
        cost=SP/np.maximum(1.2*a,1e-12)
        net=r-cost
        if split_year is None:
            res[(nm,label,'hold')]=(int(m.sum()),float(net[m].sum()),int(w[m].sum()))
        else:
            for ph,mm in (('train',m&(yr<=split_year)),('test',m&(yr>split_year))):
                res[(nm,label,ph)]=(int(mm.sum()),float(net[mm].sum()),int(w[mm].sum()))
    print('done',label,len(st),file=sys.stderr,flush=True)
for label,f,yr_,SP in SEL: run(label,load(f'{S}/{f}'),SP,yr_)
for label,f,SP in HOLD:
    if '+' in f: d=pd.concat([load(f'{S}/{x}') for x in f.split('+')]).sort_values('time').reset_index(drop=True)
    else: d=load(f'{S}/{f}',yf='yfinance' in f)
    if label=='ذهب 5m': d=d[d.time.dt.year>=2019].reset_index(drop=True)
    run(label,d,SP)
json.dump({'|'.join(k):v for k,v in res.items()},open(S+'/ai/mass_res.json','w'),ensure_ascii=False)
names=sorted({k[0] for k in res})
print('عدد الاستراتيجيات المختبرة:',len(names))
rows=[]
for nm in names:
    def R(lbl,ph):
        x=res.get((nm,lbl,ph)); return (x[1]/x[0] if x and x[0]>=30 else np.nan, x[0] if x else 0)
    tr=[R(l,'train')[0] for l,_,_,_ in SEL]; te=[R(l,'test')[0] for l,_,_,_ in SEL]; ho=[R(l,'hold')[0] for l,_,_ in HOLD]
    rows.append([nm,np.nanmean(tr),np.sum(np.array(tr)>0),np.nanmean(te),np.sum(np.array(te)>0),np.nanmean(ho),np.sum(np.array(ho)>0),sum(R(l,'test')[1] for l,_,_,_ in SEL)])
T=pd.DataFrame(rows,columns=['name','train','trpos','test','tepos','hold','hopos','ntest'])
T.to_csv(S+'/ai/mass_table.csv',index=False)
print('\nالمرحلة 1 — نجحت في التدريب (متوسط > +0.03R وموجبة في ≥ 4 من 6):',((T.train>0.03)&(T.trpos>=4)).sum())
s1=T[(T.train>0.03)&(T.trpos>=4)]
print('المرحلة 2 — ونجحت في الاختبار (> +0.03R و ≥ 4 من 6):',((s1.test>0.03)&(s1.tepos>=4)).sum())
s2=s1[(s1.test>0.03)&(s1.tepos>=4)]
print('المرحلة 3 — ونجحت في الأسواق المحجوزة (> 0 و ≥ 6 من 9):',((s2.hold>0)&(s2.hopos>=6)).sum())
print('\nأفضل 25 حسب الاختبار (بين الناجحة في التدريب):')
print(s1.sort_values('test',ascending=False).head(25).round(3).to_string(index=False))
print('\nالناجون من المراحل الثلاث:')
print(s2[(s2.hold>0)&(s2.hopos>=6)].sort_values('test',ascending=False).round(3).to_string(index=False))
