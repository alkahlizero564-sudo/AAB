# تدريب كل مؤشر على آلاف الأفكار: ~1000+ معلومة (مؤشرات عالمية بفترات كثيرة × 3 فريمات + 138 استراتيجية + هيكل السوق + معلومات King)
import pandas as pd, numpy as np, re, json, sys, warnings
warnings.filterwarnings('ignore')
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
exec(open(S+'/ai/mass.py').read().split("SEL=[")[0])
src=open('/home/user/AAB/lib/analysis/king_model.dart').read()
feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
s=pd.read_csv(S+'/ai/signals_sr.csv')   # إشارات Mp + معلومات King + هيكل السوق (ذهب/بيتكوين)
NF=[x for x in s.columns if x.startswith('sr_')]
files={('gold20','15m'):'gold20/xau20_15m.csv',('gold20','1h'):'gold20/xau20_1h.csv',('gold20','4h'):'gold20/xau20_4h.csv',
       ('btc','15m'):'gold10/btc10_15m.csv',('btc','1h'):'gold10/btc10_1h.csv',('btc','4h'):'gold10/btc10_4h.csv'}
P=[3,5,8,14,21,34,55,89,144,233]
def fam(o,h,l,c,v):
    """يرجع dict: اسم → (مصفوفة، هل تُضرب في الاتجاه)"""
    F={}; pc=sh(c); pc[0]=c[0]
    tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=RMA(tr,14); a=np.where(a>0,a,np.nan)
    dl=np.diff(c,prepend=c[0]); a50=RMA(tr,50)
    tp=(h+l+c)/3; mf=tp*v
    for p in P:
        rs=100-100/(1+RMA(np.clip(dl,0,None),p)/np.maximum(RMA(np.clip(-dl,0,None),p),1e-12))
        sm=SMA(c,p); em=E(c,p); sd=STD(c,p); hh=HH(h,p); ll=LL(l,p)
        F[f'rsi{p}']=(rs-50,1)
        F[f'dsma{p}']=((c-sm)/a,1); F[f'dema{p}']=((c-em)/a,1); F[f'semа{p}']=((em-sh(em,3))/a,1)
        F[f'bbp{p}']=((c-sm)/np.maximum(2*sd,1e-12),1); F[f'bbw{p}']=(2*sd/a,0)
        F[f'roc{p}']=((c-sh(c,p))/a,1)
        F[f'stoch{p}']=((c-ll)/np.maximum(hh-ll,1e-12)-0.5,1)
        tsm=SMA(tp,p); md=pd.Series(tp).rolling(p).apply(lambda x: np.mean(np.abs(x-x.mean())),raw=True).values if p<=34 else STD(tp,p)
        F[f'cci{p}']=((tp-tsm)/np.maximum(0.015*md,1e-12)/100,1)
        up=np.where(tp>sh(tp),mf,0); dn=np.where(tp<sh(tp),mf,0)
        F[f'mfi{p}']=(pd.Series(up).rolling(p).sum().values/np.maximum(pd.Series(up+dn).rolling(p).sum().values,1e-12)-0.5,1)
        upm=h-sh(h); dnm=sh(l)-l; pdm=np.where((upm>dnm)&(upm>0),upm,0); mdm=np.where((dnm>upm)&(dnm>0),dnm,0)
        atp=RMA(tr,p); pdi=RMA(pdm,p)/np.maximum(atp,1e-12); mdi=RMA(mdm,p)/np.maximum(atp,1e-12)
        dx=np.abs(pdi-mdi)/np.maximum(pdi+mdi,1e-12)
        F[f'adx{p}']=(RMA(np.nan_to_num(dx),p),0); F[f'di{p}']=(pdi-mdi,1)
        F[f'zs{p}']=((c-sm)/np.maximum(sd,1e-12),1)
        F[f'vr{p}']=(v/np.maximum(SMA(v,p),1e-12),0)
        x=np.arange(p); xm=x.mean(); den=((x-xm)**2).sum()
        F[f'lr{p}']=(pd.Series(c).rolling(p).apply(lambda y: ((x-xm)*(y-y.mean())).sum()/den,raw=True).values/a if p<=55 else (sm-sh(sm,max(1,p//4)))/a,1)
        F[f'atrr{p}']=(atp/np.where(a50>0,a50,np.nan),0)
        F[f'tohh{p}']=((hh-c)/a,1); F[f'toll{p}']=((c-ll)/a,1)
        F[f'upc{p}']=(pd.Series((dl>0)*1.0).rolling(p).mean().values-0.5,1)
        F[f'kel{p}']=((c-em)/(2*atp),1)
    return F
rows=[]; names=None
for (mk,tf),f in files.items():
    d=load(f'{S}/{f}')
    o,h,l,c,v=[d[x].values.astype(np.float64) for x in ['open','high','low','close','volume']]
    sub=s[(s.market==mk)&(s.tf==tf)]
    # تحقق المحاذاة مع رقم الشمعة في ملف الإشارات
    raw=pd.read_csv(f'{S}/{f}'); raw.columns=[x.lower() for x in raw.columns]
    rt=pd.to_datetime(raw.iloc[:,0],utc=True,errors='coerce').values; tmap=pd.Series(np.arange(len(d)),index=d.time.values)
    ii=tmap.reindex(rt[sub.i.values]).values
    ok=~np.isnan(ii); ii=np.where(ok,ii,0).astype(int)
    cols={}
    for m,lab in [(1,'B_'),(4,'H4x_'),(16,'H16x_'),(64,'H64x_')]:
        if m==1: F=fam(o,h,l,c,v); idx=ii
        else:
            g=np.arange(len(c))//m
            dd=pd.DataFrame({'g':g,'o':o,'h':h,'l':l,'c':c,'v':v}).groupby('g').agg(o=('o','first'),h=('h','max'),l=('l','min'),c=('c','last'),v=('v','sum'))
            F=fam(*[dd[x].values for x in ['o','h','l','c','v']]); idx=np.maximum((ii+1)//m-1,0)   # آخر شمعة أعلى مكتملة
        for nm,(arr,sg) in F.items():
            x=arr[idx]; cols[lab+nm]=x*sub.d.values if sg else x
    st,_=strategies(d)
    for nm,arr in st.items():
        if nm.endswith(('مع الترند','ADX>25','عكس الترند')): continue
        nz=np.where(arr!=0,np.arange(len(arr)),-1); last=np.maximum.accumulate(nz)
        li=last[ii]; val=np.where((li>=0)&(ii-li<=10),arr[np.maximum(li,0)],0)
        cols['S_'+nm]=val*sub.d.values
        cols['S1_'+nm]=arr[ii]*sub.d.values
    B=pd.DataFrame(cols,index=sub.index); B=B[ok]
    rows.append(B); print('done',mk,tf,B.shape,file=sys.stderr,flush=True)
B=pd.concat(rows)
X=s.join(B,how='inner')
X.to_pickle(S+'/ai/big.pkl')
BIG=list(B.columns)
print('عدد المعلومات:',len(feat),'(King) +',len(NF),'(هيكل) +',len(BIG),'(مؤشرات/فريمات/استراتيجيات) =',len(feat)+len(NF)+len(BIG))
