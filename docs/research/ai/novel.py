# 3 مؤشرات غير مألوفة: (1) بصمة الشموع DNA (2) ساعة السوق (3) الفوضى بالضغط — تعلم من التدريب فقط، اختبار على سنين لم تُرَ
import pandas as pd, numpy as np, sys, zlib, warnings
warnings.filterwarnings('ignore')
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
@njit
def outcomes(o,h,l,c,a,SP):
    # لكل شمعة: نتيجة شراء وبيع (دخول افتتاح التالية، وقف خلف 3 شموع 0.7-2.5 ATR، نصف 1R ونصف 2R، الوقف للدخول) بعد السبريد
    n=len(c); R=np.full((n,2),np.nan)
    for i in range(3,n-2):
        if not a[i]>0: continue
        for q in range(2):
            d=1 if q==0 else -1
            e=o[i+1]; ext=l[i] if d>0 else h[i]
            for j in range(i-2,i+1): ext=min(ext,l[j]) if d>0 else max(ext,h[j])
            rk=min(max((e-ext)*d+0.1*a[i],0.7*a[i]),2.5*a[i]); st=e-d*rk; t1=e+d*rk; t2=e+2*d*rk; got=False; stop=st
            for j in range(i+1,min(n,i+400)):
                if (d>0 and l[j]<=stop) or (d<0 and h[j]>=stop):
                    R[i,q]=(0.5 if got else -1.0)-SP/rk; break
                if not got and ((d>0 and h[j]>=t1) or (d<0 and l[j]<=t1)): got=True; stop=e
                if got and ((d>0 and h[j]>=t2) or (d<0 and l[j]<=t2)): R[i,q]=1.5-SP/rk; break
    return R
out=[]
for mk,tf,f,ty,SP in [('ذهب','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; n=len(c); pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    R=outcomes(o,h,l,c,a,SP); yr=t.dt.year.values; tr=yr<ty; te=yr>=ty
    if mk=='ذهب': tr&=yr>=2008
    # (1) DNA: اتجاه × حجم الجسم (3) × مكان الإغلاق (3) — حدود الحجم من التدريب
    body=abs(c-o)/np.maximum(a,1e-12); q1,q2=np.quantile(body[tr],[1/3,2/3])
    bs=np.where(body<q1,0,np.where(body<q2,1,2)); pos=(c-l)/np.maximum(h-l,1e-12); ps=np.where(pos<1/3,0,np.where(pos<2/3,1,2))
    sym=(np.sign(c-o)>0).astype(int)*9+bs*3+ps
    key=sym.copy()
    for k in range(1,4): key=key*18+np.r_[np.zeros(k,int),sym[:-k]]
    # (2) الساعة × يوم الأسبوع
    hk=t.dt.dayofweek.values*24+t.dt.hour.values
    # (3) الفوضى: نسبة ضغط اتجاهات آخر 64 شمعة (أقل = أكثر نظاماً) + اتجاه آخر 20 شمعة
    dirs=(np.sign(c-o)+1).astype(np.int8).tobytes()
    cr=np.full(n,np.nan)
    for i in range(64,n,1 if n<200000 else 1):
        cr[i]=len(zlib.compress(dirs[i-63:i+1],9))
    mom=np.sign(c-np.r_[np.full(20,np.nan),c[:-20]])
    crq=np.nanquantile(cr[tr],0.2)
    for name,K in [('🧬 بصمة الشموع DNA',key),('🕐 ساعة السوق',hk)]:
        D=pd.DataFrame({'k':K,'rl':R[:,0],'rs':R[:,1]})
        st=D[tr].groupby('k').agg(n=('rl','size'),ml=('rl','mean'),ms=('rs','mean'))
        st=st[st.n>=(60 if name.startswith('🧬') else 100)]
        for thr in [0.05,0.10]:
            bl=set(st.index[st.ml>=thr]); bsh=set(st.index[st.ms>=thr])
            idx=np.where(te)[0]
            L=[R[i,0] for i in idx if K[i] in bl]; Sh=[R[i,1] for i in idx if K[i] in bsh]
            v=np.array(L+Sh); v=v[~np.isnan(v)]
            days=(yr.max()-ty+1)*(260 if mk=='ذهب' else 365)
            out.append([mk,tf,name,f'تعلم ≥{thr}R',len(v)/days,(v>0).mean()*100 if len(v) else np.nan,v.mean() if len(v) else np.nan])
    # الفوضى: سوق مرتب (أقل 20% ضغطاً) + مع اتجاه آخر 20 شمعة
    idx=np.where(te&(cr<=crq)&~np.isnan(mom))[0]
    v=np.array([R[i,0] if mom[i]>0 else R[i,1] for i in idx]); v=v[~np.isnan(v)]
    w=np.array([R[i,1] if mom[i]>0 else R[i,0] for i in idx]); w=w[~np.isnan(w)]
    days=(yr.max()-ty+1)*(260 if mk=='ذهب' else 365)
    out.append([mk,tf,'🌀 الفوضى (مرتب + مع الاتجاه)','',len(v)/days,(v>0).mean()*100,v.mean()])
    out.append([mk,tf,'🌀 الفوضى (مرتب + عكس الاتجاه)','',len(w)/days,(w>0).mean()*100,w.mean()])
    allr=R[te].ravel(); allr=allr[~np.isnan(allr)]
    out.append([mk,tf,'عشوائي (كل شمعة، أي اتجاه)','',np.nan,(allr>0).mean()*100,allr.mean()])
    print('done',mk,tf,file=sys.stderr,flush=True)
O=pd.DataFrame(out,columns=['mk','tf','ind','var','perday','win','r'])
for (mk,tf),G in O.groupby(['mk','tf'],sort=False):
    print(f'== {mk} {tf} (اختبار على سنين لم تُرَ، بعد السبريد)')
    for _,x in G.iterrows():
        print(f'   {x.ind:30s} {x["var"]:10s} | {"" if np.isnan(x.perday) else f"{x.perday:5.1f}/يوم"} | نجاح {x.win:5.1f}% | {x.r:+.3f}R')
