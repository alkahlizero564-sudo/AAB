# بوت كسر خط الترند (فيديو): خط من آخر قاعين صاعدين (أو قمتين هابطتين)، إغلاق كاسر للخط → إشارة عكسه، الوقف خلف آخر قمة/قاع، الهدف 2R، رفض الوقف الكبير
import pandas as pd, numpy as np, sys
exec(open('vid10.py').read().split("def lrc")[0])           # fixed() + sim + King imports
out=[]
for mk,tf,f,ty,SP,maxb in [('ذهب','5m','m1/xau_5m.csv',2019,0.25,800),('ذهب','15m','gold20/xau20_15m.csv',2019,0.25,400),('ذهب','1h','gold20/xau20_1h.csv',2019,0.25,300),('بيتكوين','15m','gold10/btc10_15m.csv',2021,0.0,400),('بيتكوين','1h','gold10/btc10_1h.csv',2021,0.0,300)]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; yr=pd.to_datetime(d.iloc[:,0]).dt.year.values
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; n=len(c); pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    k=5; PL=[]; PH=[]; usedL=set(); usedH=set(); rs=np.random.RandomState(2); R={}
    def add(key,x):
        if x==x: R.setdefault(key,[]).append(x)
    for i in range(2*k+5,n-2):
        j=i-k
        if l[j]==l[j-k:j+k+1].min(): PL.append(j)
        if h[j]==h[j-k:j+k+1].max(): PH.append(j)
        if yr[i]<ty: continue
        sig=0
        # خط صاعد من آخر قاعين (الثاني أعلى) — كسره بإغلاق تحته → بيع
        if len(PL)>=2 and l[PL[-1]]>l[PL[-2]] and (PL[-2],PL[-1]) not in usedL:
            p1,p2=PL[-2],PL[-1]; sl=(l[p2]-l[p1])/(p2-p1); ln=l[p1]+sl*(i-p1); lp=l[p1]+sl*(i-1-p1)
            if c[i]<ln and c[i-1]>=lp: sig=-1; usedL.add((p1,p2))
        if sig==0 and len(PH)>=2 and h[PH[-1]]<h[PH[-2]] and (PH[-2],PH[-1]) not in usedH:
            p1,p2=PH[-2],PH[-1]; sl=(h[p2]-h[p1])/(p2-p1); ln=h[p1]+sl*(i-p1); lp=h[p1]+sl*(i-1-p1)
            if c[i]>ln and c[i-1]<=lp: sig=1; usedH.add((p1,p2))
        if sig==0: continue
        A=a[i]
        st=(h[i-10:i+1].max()+0.1*A) if sig<0 else (l[i-10:i+1].min()-0.1*A)
        e=o[i+1]; risk=abs(e-st)/A
        tp=e+sig*2*abs(e-st)
        r=fixed(o,h,l,c,i,sig,e,st,tp,SP,maxb,False)
        rd=1 if rs.rand()<0.5 else -1; str_=e-rd*abs(e-st); rr=fixed(o,h,l,c,i,rd,e,str_,e+rd*2*abs(e-st),SP,maxb,False)
        add('بدون فلتر',r); add('عشوائي',rr)
        if risk<=1.5: add('وقف ≤ 1.5 ATR (فلتر الحد المسموح)',r)
        if risk<=3: add('وقف ≤ 3 ATR',r)
    days=(n-np.argmax(yr>=ty))/({'5m':288,'15m':96,'1h':24}[tf])/(0.92 if mk=='ذهب' else 1)
    for kk,x in R.items():
        x=np.array(x); out.append([mk,tf,kk,len(x)/days,(x>0).mean()*100,x.mean()])
    print('done',mk,tf,file=sys.stderr,flush=True)
O=pd.DataFrame(out,columns=['mk','tf','v','perday','win','R'])
for (mk,tf),G in O.groupby(['mk','tf'],sort=False):
    print(f'== {mk} {tf} (هدف 2R، بعد السبريد)')
    for _,x in G.iterrows(): print(f'   {x.v:32s} {x.perday:5.1f}/يوم | نجاح {x.win:5.1f}% | {x.R:+.3f}R')
