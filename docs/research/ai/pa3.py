# فيديو "Price Action 3 خطوات": اتجاه الفريم الأكبر (آخر كسر هيكل) + أول CHoCH في جلسة لندن/نيويورك بنفس الاتجاه + دخول معلّق عند FVG
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
@njit
def lim(h,l,c,start,d,e,st,rr,wait,maxb):
    n=len(h); k0=-1
    for j in range(start,min(n,start+wait)):
        if (d>0 and l[j]<=e) or (d<0 and h[j]>=e): k0=j; break
    if k0<0: return np.nan
    r=(e-st)*d
    if r<=0: return np.nan
    t=e+d*rr*r
    for j in range(k0,min(n,k0+maxb)):
        if (d>0 and l[j]<=st) or (d<0 and h[j]>=st): return -1.0
        if j==k0: continue
        if (d>0 and h[j]>=t) or (d<0 and l[j]<=t): return rr
    return (c[min(n-1,k0+maxb-1)]-e)*d/r
@njit
def mkt(o,h,l,c,i,d,r,rr,maxb):
    n=len(c); e=o[i+1]; st=e-d*r; t=e+d*rr*r
    for j in range(i+1,min(n,i+maxb)):
        if (d>0 and l[j]<=st) or (d<0 and h[j]>=st): return -1.0
        if (d>0 and h[j]>=t) or (d<0 and l[j]<=t): return rr
    return (c[min(n-1,i+maxb-1)]-e)*d/r
def structure_dir(h,l,c,k):
    n=len(c); out=np.zeros(n,int); res=np.nan; sup=np.nan; last=0; brk=np.zeros(n,int)
    for i in range(2*k,n):
        j=i-k
        if h[j]==h[j-k:j+k+1].max(): res=h[j]
        if l[j]==l[j-k:j+k+1].min(): sup=l[j]
        if not np.isnan(res) and c[i]>res: brk[i]=1; res=np.nan
        elif not np.isnan(sup) and c[i]<sup: brk[i]=-1; sup=np.nan
        if brk[i]!=0: last=brk[i]
        out[i]=last
    return out,brk
rows=[]
for tf,f,m,SP,maxb in [('5m','m1/xau_5m.csv',12,0.25,600),('15m','gold20/xau20_15m.csv',4,0.25,300)]:
    d=pd.read_csv(f'{S}/{f}'); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; n=len(c)
    pc=np.r_[c[0],c[:-1]]; a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    # الاتجاه من الساعة: آخر كسر هيكل على الشموع المجمعة (المكتملة فقط)
    g=np.arange(n)//m
    H=pd.DataFrame({'g':g,'h':h,'l':l,'c':c}).groupby('g').agg(h=('h','max'),l=('l','min'),c=('c','last'))
    hd,_=structure_dir(H.h.values,H.l.values,H.c.values,5); htf=hd[np.maximum((np.arange(n)+1)//m-1,0)]
    # هيكل الفريم الصغير: CHoCH = كسر عكس الكسر السابق
    k=3; res=np.nan; sup=np.nan; last=0; resi=suppi=-1
    hr=t.dt.hour.values; day=t.dt.date.values; yr=t.dt.year.values
    used=set(); rs=np.random.RandomState(9)
    for i in range(50,n-2):
        j=i-k
        if h[j]==h[j-k:j+k+1].max(): res=h[j]; resi=j
        if l[j]==l[j-k:j+k+1].min(): sup=l[j]; suppi=j
        dd=0
        if not np.isnan(res) and c[i]>res: dd=1; res=np.nan
        elif not np.isnan(sup) and c[i]<sup: dd=-1; sup=np.nan
        if dd==0: continue
        choch=(last==-dd); last=dd
        if yr[i]<2019 or not choch or htf[i]!=dd: continue
        # الجلسة بتوقيت البيانات (≈ +3): لندن 10-13، نيويورك 16-19
        sess='لندن' if 10<=hr[i]<13 else ('نيويورك' if 16<=hr[i]<19 else None)
        if sess is None or (day[i],sess) in used: continue
        used.add((day[i],sess))
        # FVG داخل حركة الكسر (آخر 10 شموع)
        e=np.nan
        for q in range(i,i-10,-1):
            if dd>0 and l[q]>h[q-2]: e=l[q]; break
            if dd<0 and h[q]<l[q-2]: e=h[q]; break
        sw=l[i-15:i+1].min() if dd>0 else h[i-15:i+1].max()
        st=sw-dd*0.1*a[i]
        if np.isnan(e) or (e-st)*dd<=0.3*a[i]: continue
        r=(e-st)*dd
        for rr in (2.0,3.0):
            g1=lim(h,l,c,i+1,dd,e,st,rr,24,maxb)
            gm=mkt(o,h,l,c,i,dd,r,rr,maxb)
            rd=1 if rs.rand()<0.5 else -1
            gx=mkt(o,h,l,c,i,rd,r,rr,maxb)
            rows.append([tf,sess,yr[i],rr,g1-SP/r if not np.isnan(g1) else np.nan,gm-SP/r,gx-SP/r])
    print('done',tf,file=sys.stderr,flush=True)
T=pd.DataFrame(rows,columns=['tf','sess','year','rr','g','gm','gx'])
for (tf,rr),G in T.groupby(['tf','rr'],sort=False):
    print(f'== ذهب {tf} — هدف {rr}R (2019-2025، بعد السبريد)')
    for sess,X in list(G.groupby('sess'))+[('الجلستين',G)]:
        x=X.g.dropna()
        print(f'   {sess:8s} أيام فيها إعداد {len(X):4d} | دخل من FVG {len(x):4d} | نجاح {(x>0).mean()*100:4.1f}% | {x.mean():+.3f}R | دخول مباشر بدل FVG: {X.gm.mean():+.3f}R | عشوائي: {X.gx.mean():+.3f}R')
