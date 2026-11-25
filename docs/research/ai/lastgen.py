# Last — توليد إشارات من ~17 استراتيجية + Mp، مع معلومات حالة السوق الموحّدة، ونتيجة موحّدة (1R ثم 2R، وقف خلف 3 شموع)
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
src=open(S+'/ai/flow2.py').read(); exec(src[src.index('@njit'):src.index('def load')].replace('cache=True','cache=False').replace('@njit','from numba import njit\n@njit',1))
from numba import njit
def load(p):
    d=pd.read_csv(p); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'})
    d['time']=pd.to_datetime(d.time,utc=True,errors='coerce'); return d.dropna(subset=['time']).sort_values('time').reset_index(drop=True)
@njit
def supertrend(h,l,c,a,m):
    n=len(c); dirn=np.ones(n,np.int64); up=np.zeros(n); dn=np.zeros(n)
    for i in range(n):
        hl=(h[i]+l[i])/2; bu=hl-m*a[i]; bd=hl+m*a[i]
        if i==0: up[i]=bu; dn[i]=bd; continue
        up[i]=max(bu,up[i-1]) if c[i-1]>up[i-1] else bu
        dn[i]=min(bd,dn[i-1]) if c[i-1]<dn[i-1] else bd
        if dirn[i-1]==-1 and c[i]>dn[i-1]: dirn[i]=1
        elif dirn[i-1]==1 and c[i]<up[i-1]: dirn[i]=-1
        else: dirn[i]=dirn[i-1]
    return dirn
@njit
def pivots(h,l,k):
    n=len(h); ph=np.zeros(n,np.bool_); pl=np.zeros(n,np.bool_)
    for j in range(k,n-k):
        hh=True; ll=True
        for q in range(j-k,j+k+1):
            if q==j: continue
            if h[q]>=h[j]: hh=False
            if l[q]<=l[j]: ll=False
        ph[j]=hh; pl[j]=ll
    return ph,pl
@njit
def sd_events(o,h,l,c,a):
    # عرض/طلب طازج: أول رجوع + شمعة رفض/ابتلاع
    n=len(c); sig=np.zeros(n,np.int64)
    zd=np.zeros(200,np.int64); zlo=np.zeros(200); zhi=np.zeros(200); zb=np.zeros(200,np.int64); zn=0
    for i in range(10,n-1):
        ai=a[i]
        if ai<=0: continue
        for bn in range(1,4):
            b0=i-3-bn+1; b1=i-3
            mx=h[b0]; mn=l[b0]
            for q in range(b0,b1+1):
                mx=max(mx,h[q]); mn=min(mn,l[q])
            if mx-mn>a[b1] or mx-mn<0.25*a[b1]: continue
            imp=c[i]-c[b1]
            dd=0
            if imp>=2*a[b1] and c[i]>mx+a[b1]: dd=1
            elif -imp>=2*a[b1] and c[i]<mn-a[b1]: dd=-1
            if dd!=0:
                if zn==200:
                    for q in range(199): zd[q]=zd[q+1]; zlo[q]=zlo[q+1]; zhi[q]=zhi[q+1]; zb[q]=zb[q+1]
                    zn=199
                zd[zn]=dd; zlo[zn]=mn; zhi[zn]=mx; zb[zn]=i; zn+=1
            break
        q=0
        while q<zn:
            dd=zd[q]; lo=zlo[q]; hi=zhi[q]; dead=False
            if i>zb[q]+2:
                if (dd>0 and c[i]<lo-0.25*ai) or (dd<0 and c[i]>hi+0.25*ai) or i-zb[q]>500: dead=True
                elif (dd>0 and l[i]<=hi) or (dd<0 and h[i]>=lo):
                    rng=max(h[i]-l[i],1e-12)
                    if dd>0: ok=((min(o[i],c[i])-l[i])/rng>=0.5 or (c[i]>o[i] and c[i-1]<o[i-1] and c[i]>=o[i-1])) and c[i]>lo
                    else: ok=((h[i]-max(o[i],c[i]))/rng>=0.5 or (c[i]<o[i] and c[i-1]>o[i-1] and c[i]<=o[i-1])) and c[i]<hi
                    if ok: sig[i]=dd
                    dead=True
            if dead:
                for r in range(q,zn-1): zd[r]=zd[r+1]; zlo[r]=zlo[r+1]; zhi[r]=zhi[r+1]; zb[r]=zb[r+1]
                zn-=1
            else: q+=1
    return sig
def build(mk,tf,f,mp_rows):
    d=load(f'{S}/{f}.csv'); o,h,l,c,v=[d[x].values.astype(np.float64) for x in ['open','high','low','close','volume']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    E=lambda s,p: pd.Series(s).ewm(span=p,adjust=False).mean().values
    W=lambda s,p: pd.Series(s).ewm(alpha=1/p,adjust=False).mean().values
    a=W(tr,14); a5=W(tr,5); a50=W(tr,50)
    e8,e20,e21,e25,e30,e35,e50,e200=[E(c,p) for p in (8,20,21,25,30,35,50,200)]
    dl=np.diff(c,prepend=c[0]); rsi=lambda p: 100-100/(1+W(np.clip(dl,0,None),p)/np.maximum(W(np.clip(-dl,0,None),p),1e-12))
    r14=rsi(14); r2=rsi(2)
    upm=np.diff(h,prepend=h[0]); dnm=-np.diff(l,prepend=l[0])
    pdm=np.where((upm>dnm)&(upm>0),upm,0.0); mdm=np.where((dnm>upm)&(dnm>0),dnm,0.0)
    pdi=100*W(pdm,14)/np.maximum(W(tr,14),1e-12); mdi=100*W(mdm,14)/np.maximum(W(tr,14),1e-12)
    adx=W(100*abs(pdi-mdi)/np.maximum(pdi+mdi,1e-12),14)
    cs=pd.Series(c); m20=cs.rolling(20).mean().values; sd20=cs.rolling(20).std(ddof=0).values
    bbu=m20+2*sd20; bbl=m20-2*sd20; bw=(bbu-bbl)/np.maximum(m20,1e-12); bwmin=pd.Series(bw).rolling(120).min().values
    hh20=pd.Series(h).rolling(20).max().shift(1).values; ll20=pd.Series(l).rolling(20).min().shift(1).values
    hh55=pd.Series(h).rolling(55).max().shift(1).values; ll55=pd.Series(l).rolling(55).min().shift(1).values
    hh50=pd.Series(h).rolling(50).max().values; ll50=pd.Series(l).rolling(50).min().values
    hh200=pd.Series(h).rolling(200).max().values; ll200=pd.Series(l).rolling(200).min().values
    vma=pd.Series(v).rolling(20).mean().values
    st=supertrend(h,l,c,W(tr,10),3.0)
    macd=E(c,12)-E(c,26); msig=E(macd,9)
    ph,pl=pivots(h,l,3)
    # آخر قمة/قاع مؤكدة (تُعرف بعد 3 شموع)
    lph=np.full(n,np.nan); lpl=np.full(n,np.nan); pph=np.full(n,np.nan); ppl=np.full(n,np.nan)
    cur_h=cur_l=prv_h=prv_l=np.nan
    for i in range(n):
        j=i-3
        if j>=0 and ph[j]: prv_h=cur_h; cur_h=h[j]
        if j>=0 and pl[j]: prv_l=cur_l; cur_l=l[j]
        lph[i]=cur_h; lpl[i]=cur_l; pph[i]=prv_h; ppl[i]=prv_l
    day=d.time.dt.floor('D'); dh=d.groupby(day).high.max().shift(1); dlw=d.groupby(day).low.min().shift(1)
    pdh=day.map(dh).values; pdl=day.map(dlw).values
    dc=d.groupby(day).close.last(); de200=dc.ewm(span=200,adjust=False).mean().shift(1); dclose=dc.shift(1)
    dtrend=np.sign((day.map(dclose)-day.map(de200)).values)
    hr=d.time.dt.hour.values; wd=d.time.dt.weekday.values; yr=d.time.dt.year.values
    ordU=(e20>e25)&(e25>e30)&(e30>e35); ordD=(e20<e25)&(e25<e30)&(e30<e35)
    sh=lambda x,k=1: np.r_[x[:k],x[:-k]]
    rng=np.maximum(h-l,1e-12); body=c-o
    ev={}
    def two(b,s): x=np.where(b,1,np.where(s,-1,0)); return x
    def first(x): p=sh(x); return np.where((x!=0)&(x!=p),x,0)
    ev['اندفاع يكسر 20']=two((c>hh20)&(rng>=1.5*a)&((c-l)/rng>=0.75),(c<ll20)&(rng>=1.5*a)&((h-c)/rng>=0.75))
    ev['بداية الشريط']=two(ordU&~sh(ordU),ordD&~sh(ordD))
    ev['استراحة ثم استمرار']=two(ordU&(c>e50)&(sh(c)<sh(o))&(c>sh(h))&(c>o),ordD&(c<e50)&(sh(c)>sh(o))&(c<sh(l))&(c<o))
    ev['كسر آخر قمة/قاع']=two(ordU&(c>lph)&(sh(c)<=lph),ordD&(c<lpl)&(sh(c)>=lpl))
    ev['بولينجر ارتداد']=two((sh(c)<sh(bbl))&(c>bbl)&(c>o),(sh(c)>sh(bbu))&(c<bbu)&(c<o))
    ev['بولينجر انضغاط']=first(two((sh(bw)<=sh(bwmin)*1.1)&(c>bbu),(sh(bw)<=sh(bwmin)*1.1)&(c<bbl)))
    ev['RSI2 مع الترند']=first(two((c>e200)&(r2<10),(c<e200)&(r2>90)))
    ev['تيرتل 55']=two((c>hh55)&(sh(c)<=sh(hh55)),(c<ll55)&(sh(c)>=sh(ll55)))
    ev['ارتداد EMA21 مع الترند']=two((c>e200)&(e21>e200)&(pd.Series(l).rolling(3).min().values<=e21+0.2*a)&(c>e21)&(c>o)&(c>sh(h)),
                                    (c<e200)&(e21<e200)&(pd.Series(h).rolling(3).max().values>=e21-0.2*a)&(c<e21)&(c<o)&(c<sh(l)))
    ev['عرض/طلب + رفض']=sd_events(o,h,l,c,a)
    ev['سحب قاع/قمة أمس']=two((l<pdl)&(c>pdl),(h>pdh)&(c<pdh))
    ev['سحب آخر قاع/قمة']=two((l<lpl)&(c>lpl)&(c>o),(h>lph)&(c<lph)&(c<o))
    ev['ابتلاع عند الطرف']=two((l<=ll20)&(c>o)&(sh(c)<sh(o))&(c>=sh(o))&(o<=sh(c)),(h>=hh20)&(c<o)&(sh(c)>sh(o))&(c<=sh(o))&(o>=sh(c)))
    ev['ماكد مع الترند']=two((c>e200)&(macd>msig)&(sh(macd)<=sh(msig))&(macd<0),(c<e200)&(macd<msig)&(sh(macd)>=sh(msig))&(macd>0))
    ev['قلب سوبرترند']=two((st==1)&(sh(st)==-1),(st==-1)&(sh(st)==1))
    ev['شمعة داخلية ثم كسر']=two((sh(h)<sh(h,2))&(sh(l)>sh(l,2))&(c>sh(h)),(sh(h)<sh(h,2))&(sh(l)>sh(l,2))&(c<sh(l)))
    ev['AIC تطابق']=first(two((c>e200)&(e50>e200)&(st==1)&(adx>25)&(r14>50)&(r14<70)&(v>1.2*vma),(c<e200)&(e50<e200)&(st==-1)&(adx>25)&(r14<50)&(r14>30)&(v>1.2*vma)))
    mp=np.zeros(n,np.int64)
    for i,dd in mp_rows:
        if 0<=i<n: mp[i]=dd
    ev['Mp (مؤشراتنا)']=mp
    rows=[]
    yr0=210
    for si,(name,sig) in enumerate(ev.items()):
        s=sig.astype(np.int64).copy(); s[:yr0]=0
        w=np.full(n,-1,np.int64); r=np.zeros(n); w2=np.full(n,-1,np.int64); r2_=np.zeros(n)
        simall(o,h,l,c,a,s,np.full(n,np.nan),w,r,w2,r2_)
        idx=np.where((s!=0)&(w>=0))[0]
        for i in idx:
            dd=s[i]; ai=a[i]
            rows.append([mk,tf,int(yr[i]),name,int(dd),int(w[i]),r[i],
                np.log(a5[i]/a50[i]),np.log(sd20[i]*4/ai+1e-9),bw[i]/max(bwmin[i],1e-12),
                (c[i]-c[i-5])/ai*dd,(c[i]-c[i-20])/ai*dd,(c[i]-c[i-50])/ai*dd,
                (c[i]-e20[i])/ai*dd,(c[i]-e50[i])/ai*dd,(c[i]-e200[i])/ai*dd,(e50[i]-e50[i-10])/ai*dd,(e200[i]-e200[i-20])/ai*dd,
                (e20[i]-e35[i])/ai*dd, (1 if (ordU[i] and dd>0) or (ordD[i] and dd<0) else (-1 if (ordU[i] or ordD[i]) else 0)),
                adx[i],(pdi[i]-mdi[i])*dd,(r14[i]-50)*dd,(r2[i]-50)*dd,((c[i]-bbl[i])/max(bbu[i]-bbl[i],1e-12)-0.5)*dd,
                ((c[i]-ll50[i])/max(hh50[i]-ll50[i],1e-12)-0.5)*dd,((c[i]-ll200[i])/max(hh200[i]-ll200[i],1e-12)-0.5)*dd,
                st[i]*dd,np.sign(macd[i]-msig[i])*dd,
                (1 if lph[i]>pph[i] and lpl[i]>ppl[i] else (-1 if lph[i]<pph[i] and lpl[i]<ppl[i] else 0))*dd,
                ((pdh[i]-c[i])/ai if dd>0 else (c[i]-pdl[i])/ai) if not np.isnan(pdh[i]) else 0,
                ((c[i]-pdl[i])/ai if dd>0 else (pdh[i]-c[i])/ai) if not np.isnan(pdl[i]) else 0,
                ((lph[i]-c[i])*dd/ai) if not np.isnan(lph[i]) else 0,((c[i]-lpl[i])*dd/ai) if not np.isnan(lpl[i]) else 0,
                body[i]/ai*dd,(h[i]-l[i])/ai,(min(o[i],c[i])-l[i] if dd>0 else h[i]-max(o[i],c[i]))/rng[i],
                v[i]/max(vma[i],1e-9),dtrend[i]*dd if not np.isnan(dtrend[i]) else 0,
                np.sin(2*np.pi*hr[i]/24),np.cos(2*np.pi*hr[i]/24),wd[i]])
        print(mk,tf,name,len(idx),file=sys.stderr,flush=True)
    return rows
cols=['market','tf','year','src','dir','win','r','volr','sq','bwr','ret5','ret20','ret50','d20','d50','d200','s50','s200','ribw','ribok',
      'adx','di','rsi','rsi2','bbpos','pos50','pos200','st','macd','struct','to_pdh','to_pdl','to_ph','to_pl','body','range','wick','vol','dtrend','hs','hc','wd']
key=pd.read_csv(S+'/ai/sdkey.csv')
out=[]
for mk,tf,f in [('gold20','15m','gold20/xau20_15m'),('gold20','1h','gold20/xau20_1h'),('gold20','4h','gold20/xau20_4h'),
                ('btc','15m','gold10/btc10_15m'),('btc','1h','gold10/btc10_1h'),('btc','4h','gold10/btc10_4h')]:
    k=key[(key.market==mk)&(key.tf==tf)]
    out+=build(mk,tf,f,list(zip(k.i.values,k.dir.values)))
R=pd.DataFrame(out,columns=cols); R['tfm']=R.tf.map({'15m':15,'1h':60,'4h':240}); R['gold']=(R.market=='gold20').astype(int)
R.to_parquet(S+'/ai/last.parquet') if False else R.to_csv(S+'/ai/last.csv',index=False)
print(R.groupby('src').size())
