# علامات SM «بداية صعود/هبوط» (ترتيب EMA 20/25/30/35 ينقلب) كإشارات — 1R/2R خروج طبيعي، سبريد ذهب 0.25$، مقارنة بالعكس والعشوائي
import pandas as pd, numpy as np, sys
exec(open('spread.py').read().split("s=pd.read_csv")[0])
exec(open('spread.py').read().split("@njit")[1].split("for tf,f in")[0].join(["@njit",""]))
def E(x,p): return pd.Series(x).ewm(span=p,adjust=False).mean().values
rows=[]
for mk,tf,f,ty,SP in [('ذهب','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','1h','gold20/xau20_1h.csv',2019,0.25),('ذهب','4h','gold20/xau20_4h.csv',2019,0.25),('بيتكوين','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','1h','gold10/btc10_1h.csv',2021,0.0),('بيتكوين','4h','gold10/btc10_4h.csv',2021,0.0)]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; yr=pd.to_datetime(d.iloc[:,0]).dt.year.values
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    R=np.stack([E(c,p) for p in [20,25,30,35]]); R55=np.stack([E(c,p) for p in [20,25,30,35,40,45,50,55]])
    up=(R[:-1]>R[1:]).all(0); dn=(R[:-1]<R[1:]).all(0); rd=np.where(up,1,np.where(dn,-1,0))
    e200=E(c,200)
    prev=0; rs=np.random.RandomState(2)
    for i in range(300,len(c)-2):
        if rd[i]!=0 and rd[i-1]!=rd[i]:
            if prev==-rd[i]:
                dd=rd[i]
                g,rk=sim(o,h,l,c,a,i,dd,0.0,SP,1.0,2.0)
                gr,rkr=sim(o,h,l,c,a,i,-dd,0.0,SP,1.0,2.0)
                rd_=1 if rs.rand()<0.5 else -1
                gx,rkx=sim(o,h,l,c,a,i,rd_,0.0,SP,1.0,2.0)
                wide=(R55[0,i]-R55[-1,i])*dd/a[i]
                rows.append([mk,tf,yr[i],dd,g/rk,gr/rkr,gx/rkx,int((c[i]-e200[i])*dd>0),(c[i]-R[0,i])*dd/a[i],wide])
            prev=rd[i]
    print('done',mk,tf,file=sys.stderr,flush=True)
T=pd.DataFrame(rows,columns=['mk','tf','year','d','r','rrev','rrnd','trend','late','wide']).dropna()
def show(lab,x):
    print(f'   {lab:34s} n={len(x):5d} | نجاح (لم يضرب الوقف كاملاً) {(x.r>-0.99).mean()*100:5.1f}% | R/صفقة بعد السبريد {x.r.mean():+.3f}')
for (mk,tf),G in T.groupby(['mk','tf'],sort=False):
    ty=2019 if mk=='ذهب' else 2021; X=G[G.year>=ty]
    print(f'== {mk} {tf} (اختبار) — عكس: {X.rrev.mean():+.3f}R | عشوائي: {X.rrnd.mean():+.3f}R')
    show('كل علامات بداية صعود/هبوط',X)
    show('مع الترند (فوق/تحت EMA200)',X[X.trend==1])
    show('عكس الترند',X[X.trend==0])
    show('غير متأخرة (السعر < 1 ATR من الشريط)',X[X.late<1])
