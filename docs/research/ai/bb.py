# بولينجر كمؤشر شراء/بيع: 5 طرق مشهورة + معلومات للذكاء
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
src=open(S+'/ai/flow2.py').read(); exec(src[src.index('@njit'):src.index('def load')].replace('cache=True','cache=False').replace('@njit','from numba import njit\n@njit',1))
from numba import njit
@njit
def simmid(h,l,o,sig,stp,mid,w,r):
    # هدف = الخط الأوسط (عند الدخول)، الوقف = stp
    n=len(h)
    for i in range(n-1):
        d=sig[i]
        if d==0: continue
        e=o[i+1]; sp=stp[i]; rk=(e-sp)*d; tp=mid[i]
        if rk<=0 or (tp-e)*d<=0: continue
        w[i]=0; r[i]=-1.0
        for j in range(i+1,min(n,i+200)):
            if (d>0 and l[j]<=sp) or (d<0 and h[j]>=sp): break
            if (d>0 and h[j]>=tp) or (d<0 and l[j]<=tp): w[i]=1; r[i]=(tp-e)*d/rk; break
def load(p):
    d=pd.read_csv(p); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'})
    d['time']=pd.to_datetime(d.time,utc=True,errors='coerce'); return d.dropna(subset=['time']).sort_values('time').reset_index(drop=True)
sets=[('gold',f'gold20/xau20_{t}',t) for t in ['15m','1h','4h']]+[('btc',f'gold10/btc10_{t}',t) for t in ['15m','1h','4h']]
K=['revert','squeeze','pullback','walk','wbottom']
rows=[]
for mk,f,tf in sets:
    d=load(f'{S}/{f}.csv'); o,h,l,c=[d[x].values.astype(np.float64) for x in ['open','high','low','close']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values; a50=pd.Series(tr).ewm(alpha=1/50,adjust=False).mean().values
    cs=pd.Series(c); mid=cs.rolling(20).mean().values; sd=cs.rolling(20).std(ddof=0).values
    up=mid+2*sd; lo=mid-2*sd; bw=(up-lo)/mid
    bwmin=pd.Series(bw).rolling(120).min().values
    pb=(c-lo)/np.maximum(up-lo,1e-12)
    e50=cs.ewm(span=50,adjust=False).mean().values; e200=cs.ewm(span=200,adjust=False).mean().values
    dl=cs.diff(); u_=dl.clip(lower=0).ewm(alpha=1/14,adjust=False).mean(); d_=(-dl.clip(upper=0)).ewm(alpha=1/14,adjust=False).mean()
    rsi=(100-100/(1+u_/d_.replace(0,1e-12))).values
    yr=d.time.dt.year.values; hr=d.time.dt.hour.values
    sig={k:np.zeros(n,np.int64) for k in K}; stp={k:np.full(n,np.nan) for k in K}
    last={k:-99 for k in K}
    for i in range(210,n-1):
        ai=a[i]
        if ai<=0 or np.isnan(sd[i]): continue
        def put(k,dd,sp):
            if i-last[k]>=3: sig[k][i]=dd; stp[k][i]=sp; last[k]=i
        # 1) ارتداد: إغلاق خارج الطرف ثم إغلاق داخله → نحو الوسط
        if c[i-1]<lo[i-1] and c[i]>lo[i] and c[i]>o[i]: put('revert',1,min(l[i-1],l[i])-0.1*ai)
        if c[i-1]>up[i-1] and c[i]<up[i] and c[i]<o[i]: put('revert',-1,max(h[i-1],h[i])+0.1*ai)
        # 2) كسر بعد انضغاط: العرض قرب أدنى 120 شمعة ثم إغلاق خارج الطرف
        if bw[i-1]<=bwmin[i-1]*1.1:
            if c[i]>up[i] and c[i-1]<=up[i-1]: put('squeeze',1,mid[i]-0.1*ai)
            if c[i]<lo[i] and c[i-1]>=lo[i-1]: put('squeeze',-1,mid[i]+0.1*ai)
        # 3) ارتداد من الوسط مع الترند: الوسط صاعد + السعر فوق EMA50، ينزل يلمس الوسط ويغلق فوقه
        sl20=mid[i]-mid[i-5]
        if sl20>0 and c[i]>e50[i] and l[i]<=mid[i] and c[i]>mid[i] and c[i]>o[i] and pb[i-3:i].max()>0.8: put('pullback',1,l[i]-0.1*ai)
        if sl20<0 and c[i]<e50[i] and h[i]>=mid[i] and c[i]<mid[i] and c[i]<o[i] and pb[i-3:i].min()<0.2: put('pullback',-1,h[i]+0.1*ai)
        # 4) المشي على الطرف: 3 إغلاقات متتالية خارج/على الطرف → استمرار
        if (c[i-2:i+1]>=up[i-2:i+1]-0.1*sd[i-2:i+1]).all() and not (c[i-3]>=up[i-3]): put('walk',1,l[i-2:i+1].min()-0.1*ai)
        if (c[i-2:i+1]<=lo[i-2:i+1]+0.1*sd[i-2:i+1]).all() and not (c[i-3]<=lo[i-3]): put('walk',-1,h[i-2:i+1].max()+0.1*ai)
        # 5) قاع W / قمة M: لمس الطرف، ثم قاع ثاني أدنى أو قريب لكن داخل الحزام (%B>0)، ثم إغلاق فوق الوسط
        if c[i]>mid[i] and c[i-1]<=mid[i-1]:
            seg=pb[i-30:i]; lw=l[i-30:i]
            k1=np.where(seg<0)[0]
            if len(k1):
                j1=i-30+k1[0]; j2=i-30+int(np.argmin(lw[k1[0]+3:]))+k1[0]+3 if k1[0]+3<30 else -1
                if j2>j1+3 and pb[j2]>0.0 and l[j2]<=l[j1]+0.5*ai: put('wbottom',1,l[j2]-0.1*ai)
        if c[i]<mid[i] and c[i-1]>=mid[i-1]:
            seg=pb[i-30:i]; hw=h[i-30:i]
            k1=np.where(seg>1)[0]
            if len(k1):
                j1=i-30+k1[0]; j2=i-30+int(np.argmax(hw[k1[0]+3:]))+k1[0]+3 if k1[0]+3<30 else -1
                if j2>j1+3 and pb[j2]<1.0 and h[j2]>=h[j1]-0.5*ai: put('wbottom',-1,h[j2]+0.1*ai)
    for k in K:
        s=sig[k]; w=np.full(n,-1,np.int64); r=np.zeros(n); w2=np.full(n,-1,np.int64); r2=np.zeros(n)
        simall(o,h,l,c,a,s,stp[k],w,r,w2,r2)
        wm=np.full(n,-1,np.int64); rm=np.zeros(n); simmid(h,l,o,s,stp[k],mid,wm,rm)
        for i in np.where(s!=0)[0]:
            if w[i]<0: continue
            dd=s[i]
            rows.append([mk,tf,k,int(yr[i]),int(dd),int(w[i]),r[i],int(w2[i]),r2[i],int(wm[i]),rm[i],
                mk=='gold',{'15m':15,'1h':60,'4h':240}[tf],(pb[i]-0.5)*dd,np.log(bw[i]/max(bwmin[i],1e-12)),np.log(sd[i]*4/a[i]),
                (mid[i]-mid[i-5])/a[i]*dd,abs(o[i+1]-stp[k][i])/a[i],
                (c[i]-e50[i])/a[i]*dd,(c[i]-e200[i])/a[i]*dd,(e50[i]-e50[i-10])/a[i]*dd,(rsi[i]-50)/50*dd,np.log(a[i]/a50[i]),
                (c[i]-c[i-5])/a[i]*dd,(c[i]-c[i-20])/a[i]*dd,(c[i]-o[i])/a[i]*dd,(h[i]-l[i])/a[i],
                np.sin(2*np.pi*hr[i]/24),np.cos(2*np.pi*hr[i]/24)])
    print('done',mk,tf,len(rows),file=sys.stderr,flush=True)
cols=['market','tf','mode','year','dir','win','r','vwin','vr','wm','rm','isgold','tfm','pctb','bwrel','bwatr','midslope','risk',
      'e50','e200','slope','rsi','volr','mom5','mom20','body','rng','hs','hc']
pd.DataFrame(rows,columns=cols).to_csv(S+'/ai/bb.csv',index=False)
