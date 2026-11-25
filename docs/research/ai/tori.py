# استراتيجية خطوط الاتجاه (Tori): ارتداد من الخط (اللمسة الثالثة+) + كسر الخط ثم إعادة الاختبار
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
src=open(S+'/ai/flow2.py').read(); exec(src[src.index('@njit'):src.index('def load')].replace('cache=True','cache=False').replace('@njit','from numba import njit\n@njit',1))
from numba import njit
@njit
def simrr(h,l,o,sig,stp,RR,w,r):
    n=len(h)
    for i in range(n-1):
        d=sig[i]
        if d==0: continue
        e=o[i+1]; sp=stp[i]; rk=(e-sp)*d
        if rk<=0: continue
        tp=e+RR*d*rk; w[i]=0; r[i]=-1.0
        for j in range(i+1,min(n,i+400)):
            if (d>0 and l[j]<=sp) or (d<0 and h[j]>=sp): break
            if j>i+1 and ((d>0 and h[j]>=tp) or (d<0 and l[j]<=tp)): w[i]=1; r[i]=RR; break
def load(p):
    d=pd.read_csv(p); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'})
    d['time']=pd.to_datetime(d.time,utc=True,errors='coerce'); return d.dropna(subset=['time']).sort_values('time').reset_index(drop=True)
sets=[('gold',f'gold20/xau20_{t}',t) for t in ['15m','1h','4h']]+[('btc',f'gold10/btc10_{t}',t) for t in ['15m','1h','4h']]
rows=[]
for mk,f,tf in sets:
    d=load(f'{S}/{f}.csv'); o,h,l,c=[d[x].values.astype(np.float64) for x in ['open','high','low','close']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values; a50=pd.Series(tr).ewm(alpha=1/50,adjust=False).mean().values
    e50=pd.Series(c).ewm(span=50,adjust=False).mean().values; e200=pd.Series(c).ewm(span=200,adjust=False).mean().values
    dl=pd.Series(c).diff(); up=dl.clip(lower=0).ewm(alpha=1/14,adjust=False).mean(); dn=(-dl.clip(upper=0)).ewm(alpha=1/14,adjust=False).mean()
    rsi=(100-100/(1+up/dn.replace(0,1e-12))).values
    hh50=pd.Series(h).rolling(50).max().values; ll50=pd.Series(l).rolling(50).min().values
    yr=d.time.dt.year.values; hr=d.time.dt.hour.values
    K=['bounce','retest']
    sig={k:np.zeros(n,np.int64) for k in K}; stp={k:np.full(n,np.nan) for k in K}; fv={k:{} for k in K}
    PL=[];PH=[]
    lines=[]   # [dir, j1,p1, j2,p2, slope, away, touches, broken_at, lastsig]
    for i in range(210,n-1):
        j=i-3
        if l[j]==l[j-3:j+4].min() and (l[j]<l[j-3:j]).all(): PL.append((j,l[j]))
        if h[j]==h[j-3:j+4].max() and (h[j]>h[j-3:j]).all(): PH.append((j,h[j]))
        ai=a[i]
        if ai<=0: continue
        # خط جديد من آخر قاعين صاعدين / آخر قمتين هابطتين
        for P,dd in ((PL,1),(PH,-1)):
            if len(P)>=2 and P[-1][0]==j:
                (j1,p1),(j2,p2)=P[-2],P[-1]
                if 5<=j2-j1<=150 and (p2-p1)*dd>0.3*a[j2]:
                    sl_=(p2-p1)/(j2-j1)
                    # سليم بين القاعين: لا إغلاق خلف الخط
                    ok=all((c[k]-(p1+sl_*(k-j1)))*dd>=0 for k in range(j1,j2+1))
                    if ok: lines.append([dd,j1,p1,j2,p2,sl_,0.0,2,-1,-999])
        keep=[]
        for L in lines:
            dd,j1,p1,j2,p2,sl_,away,tch,brk,last=L
            lv=p1+sl_*(i-j1)
            if brk<0:
                dist=((l[i] if dd>0 else h[i])-lv)*dd/ai
                if (c[i]-lv)*dd< -0.1*ai:      # كسر بإغلاق
                    L[8]=i; keep.append(L); continue
                if dist<=0.15 and away>=1.0 and i-j2>=3 and (c[i]-lv)*dd>0 and i-last>5:
                    L[7]=tch+1; L[6]=0.0; L[9]=i
                    if sig['bounce'][i]==0:
                        sig['bounce'][i]=dd; stp['bounce'][i]=min(lv-0.3*ai,l[i]-0.1*ai) if dd>0 else max(lv+0.3*ai,h[i]+0.1*ai)
                        fv['bounce'][i]=(L[7],sl_/ai*dd,i-j1,j2-j1,away)
                else:
                    L[6]=max(away,dist)
                if i-j2<=400: keep.append(L)
            else:
                # بعد الكسر: إعادة اختبار الخط من الجهة الأخرى خلال 30 شمعة → عكس الاتجاه
                if i-brk>30: continue
                if (c[i]-lv)*dd>0.5*ai: continue   # رجع فوق الخط بوضوح: أُلغي
                touch=(h[i]>=lv-0.15*ai) if dd>0 else (l[i]<=lv+0.15*ai)
                if i>brk+1 and touch and (c[i]-lv)*dd<0 and (c[i]-o[i])*dd<0:
                    if sig['retest'][i]==0:
                        sig['retest'][i]=-dd; stp['retest'][i]=(max(h[i],lv)+0.2*ai) if dd>0 else (min(l[i],lv)-0.2*ai)
                        fv['retest'][i]=(tch,sl_/ai*dd,i-j1,j2-j1,i-brk)
                    continue
                keep.append(L)
        lines=keep[-40:]
    for k in K:
        s=sig[k]; w=np.full(n,-1,np.int64); r=np.zeros(n); w2=np.full(n,-1,np.int64); r2=np.zeros(n)
        simall(o,h,l,c,a,s,stp[k],w,r,w2,r2)
        w3=np.full(n,-1,np.int64); r3=np.zeros(n); simrr(h,l,o,s,stp[k],3.0,w3,r3)
        for i,x in fv[k].items():
            if w[i]<0: continue
            dd=s[i]; e=o[i+1]
            rows.append([mk,tf,k,int(yr[i]),int(dd),int(w[i]),r[i],int(w2[i]),r2[i],int(w3[i]),r3[i],
                mk=='gold',{'15m':15,'1h':60,'4h':240}[tf],*x,abs(e-stp[k][i])/a[i],
                (c[i]-e50[i])/a[i]*dd,(c[i]-e200[i])/a[i]*dd,(e50[i]-e50[i-10])/a[i]*dd,(rsi[i]-50)/50*dd,np.log(a[i]/a50[i]),
                (c[i]-c[i-5])/a[i]*dd,(c[i]-c[i-20])/a[i]*dd,((c[i]-ll50[i])/max(hh50[i]-ll50[i],1e-9)-0.5)*dd,
                (c[i]-o[i])/a[i]*dd,np.sin(2*np.pi*hr[i]/24),np.cos(2*np.pi*hr[i]/24)])
    print('done',mk,tf,len(rows),file=sys.stderr,flush=True)
cols=['market','tf','mode','year','dir','win','r','vwin','vr','w3','r3','isgold','tfm','touch_n','lslope','lage','lspan','x5','risk',
      'e50','e200','slope','rsi','volr','mom5','mom20','pos50','body','hs','hc']
pd.DataFrame(rows,columns=cols).to_csv(S+'/ai/tori.csv',index=False)
