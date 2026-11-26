# أفكار فيديوهات المستخدم الجديدة: CRT، سحب سيولة خارجية→FVG داخلية→خارجية، قناة الانحدار 100/2، امتصاص الحجم — + SM مع ميل القناة
import pandas as pd, numpy as np, re, json, warnings
warnings.filterwarnings('ignore')
from numba import njit
exec(open('spread.py').read().split("for tf,f in")[0])   # sim, s, key, predict...
@njit
def fixed(o,h,l,c,i,d,e,st,tp,SP,maxb,limit):
    # صفقة بهدف ووقف ثابتين. limit=True: أمر معلّق عند e (وقف في شمعة الدخول = خسارة، لا هدف فيها)
    n=len(c); r=(e-st)*d
    if r<=0 or (tp-e)*d<=0: return np.nan
    k0=i+1
    if limit:
        k0=-1
        for j in range(i+1,min(n,i+25)):
            if (d>0 and l[j]<=e) or (d<0 and h[j]>=e): k0=j; break
        if k0<0: return np.nan
    else:
        e=o[i+1]; r=(e-st)*d
        if r<=0 or (tp-e)*d<=0: return np.nan
    for j in range(k0,min(n,k0+maxb)):
        if (d>0 and l[j]<=st) or (d<0 and h[j]>=st): return -1.0-SP/r
        if limit and j==k0: continue
        if (d>0 and h[j]>=tp) or (d<0 and l[j]<=tp): return (tp-e)*d/r-SP/r
    return (c[min(n-1,k0+maxb-1)]-e)*d/r-SP/r
def lrc(c,p=100):
    x=np.arange(len(c),dtype=float); S=pd.Series
    mx=S(x).rolling(p).mean(); my=S(c).rolling(p).mean()
    cov=S(x*c).rolling(p).mean()-mx*my; var=S(x*x).rolling(p).mean()-mx*mx
    b=(cov/var).values; a=(my-b*mx).values; mid=a+b*x
    res=c-mid; sd=S(res).rolling(p).std().values
    return mid,b,sd
out=[]
for mk,mkk,tf,f,ty,SP in [('ذهب','gold20','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','gold20','1h','gold20/xau20_1h.csv',2019,0.25),('ذهب','gold20','4h','gold20/xau20_4h.csv',2019,0.25),('بيتكوين','btc','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','btc','1h','gold10/btc10_1h.csv',2021,0.0),('بيتكوين','btc','4h','gold10/btc10_4h.csv',2021,0.0)]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; yr=pd.to_datetime(d.iloc[:,0]).dt.year.values
    o,h,l,c,v=[d[x].values.astype(float) for x in ['open','high','low','close','volume']]; n=len(c); pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    te=np.where(yr>=ty)[0]; te=te[(te>120)&(te<n-3)]
    rs=np.random.RandomState(1); R={}
    def add(k,x):
        if x==x: R.setdefault(k,[]).append(x)
    hh=pd.Series(h).rolling(20).max().shift(1).values; ll=pd.Series(l).rolling(20).min().shift(1).values
    mid,b,sd=lrc(c); vma=pd.Series(v).rolling(20).mean().values
    pos20=(c-ll)/np.maximum(hh-ll,1e-12)
    for i in te:
        A=a[i]
        # CRT: الشمعة تكسر طرف السابقة وتغلق داخل مداها → الهدف الطرف المقابل
        if l[i]<l[i-1] and c[i]>l[i-1] and c[i]<h[i-1]: add('CRT (كسر وعودة داخل الشمعة السابقة)',fixed(o,h,l,c,i,1,o[i+1],l[i]-0.1*A,h[i-1],SP,200,False))
        if h[i]>h[i-1] and c[i]<h[i-1] and c[i]>l[i-1]: add('CRT (كسر وعودة داخل الشمعة السابقة)',fixed(o,h,l,c,i,-1,o[i+1],h[i]+0.1*A,l[i-1],SP,200,False))
        # خارجية→داخلية→خارجية: سحب قاع 20 شمعة ثم FVG صاعدة خلال 10 شموع → دخول معلّق عند FVG، الوقف تحت القاع المسحوب، الهدف قمة 20
        for q in range(max(1,i-10),i):
            if l[q]<ll[q] and c[q]>ll[q]: 
                if l[i]>h[i-2] and l[i]>l[q]:
                    add('سيولة خارجية → FVG → خارجية',fixed(o,h,l,c,i,1,l[i],l[q:i+1].min()-0.1*A,hh[q],SP,300,True))
                break
        for q in range(max(1,i-10),i):
            if h[q]>hh[q] and c[q]<hh[q]:
                if h[i]<l[i-2] and h[i]<h[q]:
                    add('سيولة خارجية → FVG → خارجية',fixed(o,h,l,c,i,-1,h[i],h[q:i+1].max()+0.1*A,ll[q],SP,300,True))
                break
        # قناة الانحدار 100، 2σ: ارتداد من الحد مع ميل القناة، واختراق الحد مع الميل
        if sd[i]==sd[i] and sd[i]>0:
            lo=mid[i]-2*sd[i]; up=mid[i]+2*sd[i]
            if b[i]>0 and l[i]<=lo and c[i]>lo: g,rk=sim(o,h,l,c,a,i,1,0.0,SP,1.0,3.0); add('قناة الانحدار: ارتداد من الحد مع الميل',g/rk)
            if b[i]<0 and h[i]>=up and c[i]<up: g,rk=sim(o,h,l,c,a,i,-1,0.0,SP,1.0,3.0); add('قناة الانحدار: ارتداد من الحد مع الميل',g/rk)
            if c[i]>up and c[i-1]<=mid[i-1]+2*sd[i-1]: g,rk=sim(o,h,l,c,a,i,1,0.0,SP,1.0,3.0); add('قناة الانحدار: اختراق الحد',g/rk)
            if c[i]<lo and c[i-1]>=mid[i-1]-2*sd[i-1]: g,rk=sim(o,h,l,c,a,i,-1,0.0,SP,1.0,3.0); add('قناة الانحدار: اختراق الحد',g/rk)
        # امتصاص: حجم ≥ 2× المتوسط، مدى صغير، عند طرف النطاق
        if v[i]>=2*vma[i] and (h[i]-l[i])<0.8*A:
            if pos20[i]<0.2: g,rk=sim(o,h,l,c,a,i,1,0.0,SP,1.0,3.0); add('امتصاص الحجم عند الطرف',g/rk)
            elif pos20[i]>0.8: g,rk=sim(o,h,l,c,a,i,-1,0.0,SP,1.0,3.0); add('امتصاص الحجم عند الطرف',g/rk)
        if rs.rand()<0.05:
            dd=1 if rs.rand()<0.5 else -1; g,rk=sim(o,h,l,c,a,i,dd,0.0,SP,1.0,3.0); add('عشوائي',g/rk)
    days=len(te)/( {'15m':96,'1h':24,'4h':6}[tf] )/ (1 if mk=='بيتكوين' else 0.92)
    for k,x in R.items():
        x=np.array(x); out.append([mk,tf,k,len(x)/days,(x>-0.99).mean()*100,x.mean()])
    # SM مع ميل قناة الانحدار
    m=((key.market==mkk)&(key.tf==tf)).values&(s.i_sm.values==1)&(s.year.values>=ty)
    ii=key.i.values[m]; dd=key.dir.values[m]; w=s.win.values[m]
    ag=np.sign(b[ii])*dd
    out.append([mk,tf,'SM كله (دقة 1R)',np.nan,w.mean()*100,np.nan])
    out.append([mk,tf,'SM مع ميل القناة (دقة 1R)',np.nan,w[ag>0].mean()*100,np.nan])
    out.append([mk,tf,'SM عكس ميل القناة (دقة 1R)',np.nan,w[ag<0].mean()*100,np.nan])
    print('done',mk,tf,flush=True)
O=pd.DataFrame(out,columns=['mk','tf','idea','perday','nostop','R'])
O.to_csv('vid10.csv',index=False)
pd.set_option('display.width',250)
print(O.pivot_table(index='idea',columns=['mk','tf'],values='R').round(3).to_string())
print('\nالصفقات/يوم:'); print(O.pivot_table(index='idea',columns=['mk','tf'],values='perday').round(1).to_string())
print('\nSM (دقة 1R %):'); print(O[O.idea.str.startswith('SM')].pivot_table(index='idea',columns=['mk','tf'],values='nostop').round(1).to_string())
