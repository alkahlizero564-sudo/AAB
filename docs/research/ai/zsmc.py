# مناطق من: دعم/مقاومة + كسرها + أوردر بلوك + FVG — محاكاة محافظة + مقارنة عشوائية/عكسية
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
exec(open('zfv.py').read().split("rows=[]")[0])
rows=[]
for mk,tf,f,ty,SP in [('ذهب','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=pd.read_csv(f'{S}/{f}'); d.columns=[x.lower() for x in d.columns]
    o,h,l,c=[d[x].values.astype(np.float64) for x in ['open','high','low','close']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    yr=pd.to_datetime(d.iloc[:,0]).dt.year.values
    k=5; res=np.nan; sup=np.nan; rs=np.random.RandomState(5)
    for i in range(300,n-2):
        j=i-k
        if h[j]==h[j-k:j+k+1].max(): res=h[j]
        if l[j]==l[j-k:j+k+1].min(): sup=l[j]
        dd=0
        if not np.isnan(res) and c[i]>res and c[i-1]<=res: dd=1; lev=res; res=np.nan
        elif not np.isnan(sup) and c[i]<sup and c[i-1]>=sup: dd=-1; lev=sup; sup=np.nan
        if dd==0: continue
        A=a[i]
        # أوردر بلوك: آخر شمعة عكسية خلال 15 شمعة قبل الكسر
        ob=-1
        for q in range(i,i-15,-1):
            if (dd>0 and c[q]<o[q]) or (dd<0 and c[q]>o[q]): ob=q; break
        if ob<0: continue
        ob_hi,ob_lo=h[ob],l[ob]
        stop=ob_lo-0.1*A if dd>0 else ob_hi+0.1*A
        ob_e=ob_hi if dd>0 else ob_lo
        # FVG داخل حركة الكسر (بعد الأوردر بلوك)
        fv=np.nan
        for q in range(i,ob+1,-1):
            if dd>0 and l[q]>h[q-2]: fv=l[q]; fvb=h[q-2]; break
            if dd<0 and h[q]<l[q-2]: fv=h[q]; fvb=l[q-2]; break
        def go(e,dirn=dd,st=stop,wait=40,start=i+1):
            r=(e-st)*dirn
            if not (0.3*A<=r<=4*A): return np.nan
            return trade(h,l,start,dirn,e,st,e+dirn*r,e+2*dirn*r,wait)-SP/r
        r_dir=go(o[i+1],wait=1)
        r_lev=go(lev)
        r_ob=go(ob_e)
        r_fvg=go(fv) if not np.isnan(fv) else np.nan
        conf=(not np.isnan(fv)) and (min(fv,fvb)<=max(ob_hi,lev) if dd>0 else max(fv,fvb)>=min(ob_lo,lev)) and abs(lev-ob_e)<=1.0*A
        r_conf=go(lev if dd>0 and lev<ob_e or dd<0 and lev>ob_e else ob_e) if conf else np.nan
        # عكسي: نفس مستوى الدخول بالمستوى، اتجاه معاكس ونفس المسافة
        r_rev=go(lev,dirn=-dd,st=lev+(lev-stop))
        r_rnd=r_lev if rs.rand()<0.5 else r_rev
        rows.append([mk,tf,int(yr[i]),dd,r_dir,r_lev,r_ob,r_fvg,r_conf,r_rev,r_rnd])
    print('done',mk,tf,file=sys.stderr,flush=True)
R=pd.DataFrame(rows,columns=['mk','tf','year','dir','dir_','lev','ob','fvg','conf','rev','rnd'])
R.to_csv('zsmc.csv',index=False)
def show(lab,x):
    x=x.dropna()
    if len(x)<30: print(f'    {lab:34s} n={len(x)} (قليل)'); return
    print(f'    {lab:34s} n={len(x):5d} | نجاح {(x>0).mean()*100:5.1f}% | R/صفقة {x.mean():+.3f}')
for (mk,tf),G in R.groupby(['mk','tf'],sort=False):
    ty=2019 if mk=='ذهب' else 2021; T=G[G.year>=ty]; Tr=G[G.year<ty]
    print(f'== {mk} {tf}  (اختبار؛ [تدريب] بين قوسين)')
    for col,lab in [('dir_','دخول مباشر بعد الكسر'),('lev','إعادة اختبار المستوى المكسور'),('ob','الأوردر بلوك'),('fvg','الـ FVG'),('conf','تجمّع المستوى+OB+FVG'),('rev','عكس الاتجاه (مقارنة)'),('rnd','عشوائي (مقارنة)')]:
        x=T[col].dropna(); y=Tr[col].dropna()
        print(f'    {lab:30s} n={len(x):5d} | نجاح {(x>0).mean()*100:5.1f}% | R {x.mean():+.3f}   [تدريب R {y.mean():+.3f}]')
