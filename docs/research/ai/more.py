# إشارات أكثر بنفس الدقة: مرشحون من 138 استراتيجية (أي شمعة فيها إشارة) + ذكاء يختار — مقارنة إشارات/يوم عند دقة King
import pandas as pd, numpy as np, re, json, sys, warnings
warnings.filterwarnings('ignore')
import lightgbm as lgb
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
exec(open(S+'/ai/mass.py').read().split("SEL=[")[0])
exec(open(S+'/ai/big.py').read().split("rows=[]; names=None")[0].split("P=[3,5")[1].join(["P=[3,5",""]) if False else '')
src_big=open(S+'/ai/big.py').read(); exec(src_big[src_big.index('P=[3,5'):src_big.index('rows=[]; names=None')])
@njit
def lab(o,h,l,c,a,ii,dd,SP):
    n=len(c); W=np.full(len(ii),-1); R=np.full(len(ii),np.nan)
    for q in range(len(ii)):
        i=ii[q]; d=dd[q]
        if i+2>=n or not a[i]>0: continue
        e=o[i+1]; ext=l[i] if d>0 else h[i]
        for j in range(i-2,i+1): ext=min(ext,l[j]) if d>0 else max(ext,h[j])
        rk=min(max((e-ext)*d+0.1*a[i],0.7*a[i]),2.5*a[i])
        st=e-d*rk; t1=e+d*rk; t2=e+2*d*rk; got=False; stop=st; w=-1
        for j in range(i+1,min(n,i+400)):
            if (d>0 and l[j]<=stop) or (d<0 and h[j]>=stop):
                if w<0: w=0
                R[q]=(0.5 if got else -1.0)-SP/rk; break
            if not got and ((d>0 and h[j]>=t1) or (d<0 and l[j]<=t1)):
                got=True; stop=e
                if w<0: w=1
            if got and ((d>0 and h[j]>=t2) or (d<0 and l[j]<=t2)): R[q]=1.5-SP/rk; break
        W[q]=w
    return W,R
out=[]
for mk,tf,f,ty,SP in [('ذهب','15m','gold20/xau20_15m.csv',2019,0.25),('ذهب','1h','gold20/xau20_1h.csv',2019,0.25),('بيتكوين','15m','gold10/btc10_15m.csv',2021,0.0),('بيتكوين','1h','gold10/btc10_1h.csv',2021,0.0)]:
    d=load(f'{S}/{f}'); yr=d.time.dt.year.values
    st,(o,h,l,c,a)=strategies(d); v=d.volume.values.astype(float)
    names=[k for k in st if not k.endswith(('مع الترند','ADX>25','عكس الترند'))]
    M=np.stack([st[k] for k in names],1).astype(np.int8)          # شموع × استراتيجيات
    up=(M>0).sum(1); dn=(M<0).sum(1)
    ev_i=np.r_[np.where(up>0)[0],np.where(dn>0)[0]]; ev_d=np.r_[np.ones((up>0).sum(),int),-np.ones((dn>0).sum(),int)]
    keep=(ev_i>300)&((yr[ev_i]>=2010) if mk=='ذهب' else True); ev_i=ev_i[keep]; ev_d=ev_d[keep]
    W,R=lab(o,h,l,c,a,ev_i,ev_d,SP)
    F={}
    for m,labp in [(1,'B_'),(4,'H4x_'),(16,'H16x_')]:
        if m==1: FF=fam(o,h,l,c,v); idx=ev_i
        else:
            g=np.arange(len(c))//m
            dd_=pd.DataFrame({'g':g,'o':o,'h':h,'l':l,'c':c,'v':v}).groupby('g').agg(o=('o','first'),h=('h','max'),l=('l','min'),c=('c','last'),v=('v','sum'))
            FF=fam(*[dd_[x].values for x in ['o','h','l','c','v']]); idx=np.maximum((ev_i+1)//m-1,0)
        for nm,(arr,sg) in FF.items():
            x=arr[idx].astype(np.float32); F[labp+nm]=x*ev_d if sg else x
        del FF
    F['v_with']=np.where(ev_d>0,up[ev_i],dn[ev_i]).astype(np.float32); F['v_against']=np.where(ev_d>0,dn[ev_i],up[ev_i]).astype(np.float32)
    # أي الاستراتيجيات أطلقت (بالاتجاه)
    for q,k in enumerate(names): F['S'+str(q)]=(M[ev_i,q]*ev_d).astype(np.int8)
    D=pd.DataFrame(F); D['w']=W; D['r']=R; D['year']=yr[ev_i]; D['i']=ev_i; D['d']=ev_d; D['mk']=mk; D['tf']=tf
    D=D[D.w>=0]
    out.append(D); print('done',mk,tf,len(D),file=sys.stderr,flush=True)
    del M
D=pd.concat(out,ignore_index=True)
D.to_pickle(S+'/ai/more.pkl')
