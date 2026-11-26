# SMC (LuxAlgo): CHoCH (كسر عكس الاتجاه السابق) ثم دخول معلّق عند الأوردر بلوك، الوقف خلفه، 3 أهداف — مقابل BOS وعشوائي
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
exec(open('zfv.py').read().split("rows=[]")[0])
@njit
def trade3(h,l,start,d,e,st,wait):
    # دخول معلّق، 3 أهداف 1R/2R/3R (ثلث عند كل هدف)، الوقف للدخول بعد TP1، محافظ (وقف في شمعة الدخول = خسارة)
    n=len(h); k0=-1
    for j in range(start,min(n,start+wait)):
        if (d>0 and l[j]<=e) or (d<0 and h[j]>=e): k0=j; break
    if k0<0: return np.nan
    r=(e-st)*d
    if r<=0: return np.nan
    got=0; stop=st; acc=0.0
    for j in range(k0,min(n,k0+800)):
        if (d>0 and l[j]<=stop) or (d<0 and h[j]>=stop): return acc+(3-got)/3*((stop-e)*d/r)
        if j==k0: continue
        while got<3 and ((d>0 and h[j]>=e+d*(got+1)*r) or (d<0 and l[j]<=e+d*(got+1)*r)):
            got+=1; acc+=(got)/3.0
            if got==1: stop=e
        if got==3: return acc
    return np.nan
rows=[]
for mk,tf,f,ty,SP in [('ذهب','5m','m1/xau_5m.csv',2019,0.25),('ذهب','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=pd.read_csv(f'{S}/{f}'); d.columns=[x.lower() for x in d.columns]
    o,h,l,c=[d[x].values.astype(np.float64) for x in ['open','high','low','close']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    yr=pd.to_datetime(d.iloc[:,0]).dt.year.values
    k=5; res=np.nan; sup=np.nan; last=0; rs=np.random.RandomState(6)
    for i in range(300,n-2):
        j=i-k
        if h[j]==h[j-k:j+k+1].max(): res=h[j]
        if l[j]==l[j-k:j+k+1].min(): sup=l[j]
        dd=0
        if not np.isnan(res) and c[i]>res and c[i-1]<=res: dd=1; res=np.nan
        elif not np.isnan(sup) and c[i]<sup and c[i-1]>=sup: dd=-1; sup=np.nan
        if dd==0: continue
        kind='CHoCH' if last==-dd else 'BOS'; last=dd
        if yr[i]<ty: continue
        ob=-1
        for q in range(i,i-15,-1):
            if (dd>0 and c[q]<o[q]) or (dd<0 and c[q]>o[q]): ob=q; break
        if ob<0: continue
        A=a[i]; e=h[ob] if dd>0 else l[ob]; st=(l[ob]-0.1*A) if dd>0 else (h[ob]+0.1*A)
        r=(e-st)*dd
        if not (0.2*A<=r<=4*A): continue
        cost=SP/r
        g=trade3(h,l,i+1,dd,e,st,40)
        rd=1 if rs.rand()<0.5 else -1
        gx=trade3(h,l,i+1,rd,e,e-rd*r,40)
        rows.append([mk,tf,kind,g-cost if not np.isnan(g) else np.nan,gx-cost if not np.isnan(gx) else np.nan])
    print('done',mk,tf,file=sys.stderr,flush=True)
T=pd.DataFrame(rows,columns=['mk','tf','kind','g','gx'])
for (mk,tf),G in T.groupby(['mk','tf'],sort=False):
    print(f'== {mk} {tf} (اختبار، بعد السبريد، 3 أهداف 1R/2R/3R)')
    for kd,X in G.groupby('kind'):
        x=X.g.dropna(); xr=X.gx.dropna()
        print(f'   {kd:6s} دخلت {len(x):5d} | لم يضرب الوقف كاملاً {(x>-0.99).mean()*100:5.1f}% | {x.mean():+.3f}R/صفقة | عشوائي {xr.mean():+.3f}R')
