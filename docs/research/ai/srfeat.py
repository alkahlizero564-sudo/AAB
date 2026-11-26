# King + قراءة هيكل السوق (مستويات دعم/مقاومة متعددة، الكسر، إعادة الاختبار، القمم/القيعان) — مقارنة عادلة
import pandas as pd, numpy as np, re, json, sys
from sklearn.ensemble import RandomForestClassifier
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
src=open('/home/user/AAB/lib/analysis/king_model.dart').read()
feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
s=pd.read_csv(S+'/ai/signals2.csv'); key=pd.read_csv(S+'/ai/sdkey.csv')
s['market']=key.market.values; s['tf']=key.tf.values; s['i']=key.i.values; s['d']=key.dir.values
files={('gold20','15m'):'gold20/xau20_15m.csv',('gold20','1h'):'gold20/xau20_1h.csv',('gold20','4h'):'gold20/xau20_4h.csv',
       ('btc','15m'):'gold10/btc10_15m.csv',('btc','1h'):'gold10/btc10_1h.csv',('btc','4h'):'gold10/btc10_4h.csv'}
NF=['sr_a1','sr_a2','sr_b1','sr_b2','sr_ta','sr_tb','sr_at','sr_room','sr_nA','sr_bw','sr_bwage','sr_ba','sr_rt','sr_hh','sr_hl']
rows=[]
for (mk,tf),f in files.items():
    d=pd.read_csv(f'{S}/{f}'); d.columns=[x.lower() for x in d.columns]
    h,l,c=[d[x].values.astype(float) for x in ['high','low','close']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    k=5
    ph=np.array([j for j in range(k,n-k) if h[j]==h[j-k:j+k+1].max()]); pl=np.array([j for j in range(k,n-k) if l[j]==l[j-k:j+k+1].min()])
    sub=s[(s.market==mk)&(s.tf==tf)]
    for idx,i,dd in zip(sub.index,sub.i.values,sub.d.values):
        A=a[i] if a[i]>0 else 1e-9; px=c[i]
        H=ph[(ph<=i-k)&(ph>=i-500)]; L=pl[(pl<=i-k)&(pl>=i-500)]
        lv=np.r_[h[H],l[L]]
        if len(lv)<4: continue
        touch=np.array([(np.abs(lv-x)<=0.25*A).sum() for x in lv])
        up=lv[lv>px]; dn=lv[lv<px]; tu=touch[lv>px]; tdn=touch[lv<px]
        ou=np.argsort(up-px); od=np.argsort(px-dn)
        au=(up[ou]-px)/A if len(up) else np.array([50.]); ad=(px-dn[od])/A if len(dn) else np.array([50.])
        tU=tu[ou][0] if len(up) else 0; tD=tdn[od][0] if len(dn) else 0
        ah,bh=(au,ad) if dd>0 else (ad,au); ta,tb=(tU,tD) if dd>0 else (tD,tU)
        a1,a2=ah[0],(ah[1] if len(ah)>1 else 50.); b1,b2=bh[0],(bh[1] if len(bh)>1 else 50.)
        at=np.abs(lv-px).min()/A
        nA=((ah<=3)).sum()
        # الكسر خلال آخر 10 شموع: إغلاق عبر مستوى
        bw=0;bwage=20;ba=0;rt=0
        for t in range(i,max(i-10,1),-1):
            crossU=((c[t-1]<=lv)&(c[t]>lv)); crossD=((c[t-1]>=lv)&(c[t]<lv))
            w=crossU if dd>0 else crossD; ag=crossD if dd>0 else crossU
            if w.any() and bw==0:
                bw=1; bwage=i-t; lvl=lv[w][0]
                rt=1 if abs((l[i] if dd>0 else h[i])-lvl)<=0.3*A else 0
            if ag.any(): ba=1
        hh=np.sign(h[H[-1]]-h[H[-2]]) if len(H)>=2 else 0; hl=np.sign(l[L[-1]]-l[L[-2]]) if len(L)>=2 else 0
        rows.append([idx,min(a1,50),min(a2,50),min(b1,50),min(b2,50),ta,tb,min(at,50),min(a1,50)/(min(b1,50)+0.1),nA,bw,bwage,ba,rt,hh*dd,hl*dd])
    print('done',mk,tf,file=sys.stderr,flush=True)
F=pd.DataFrame(rows,columns=['idx']+NF).set_index('idx')
X=s.join(F,how='inner')
X.to_csv(S+'/ai/signals_sr.csv',index=False)
g=X.market=='gold20'
tr=((g&(X.year>=2010)&(X.year<=2018))|((X.market=='btc')&(X.year<=2020))).values
te=((g&(X.year>=2019))|((X.market=='btc')&(X.year>=2021))).values
y=X.win.values
def run(cols,lab,seed=1):
    m=RandomForestClassifier(n_estimators=150,min_samples_leaf=120,max_depth=10,max_features=0.3,n_jobs=-1,random_state=seed).fit(X.loc[tr,cols],y[tr])
    pa=m.predict_proba(X.loc[tr,cols])[:,1]; pt=m.predict_proba(X.loc[te,cols])[:,1]
    out=[]
    for top in [30,15,7]:
        th=np.quantile(pa,1-top/100); k=pt>=th; out.append((y[te][k].mean()*100,k.sum()))
    return out,m
print(f'بيانات: تدريب {tr.sum()} | اختبار {te.sum()} (ذهب 2019+ وبيتكوين 2021+) | Mp خام {y[te].mean()*100:.1f}%')
for lab,cols in [('King الحالي (54 معلومة)',feat),('King + قراءة الدعم والمقاومة',feat+NF),('قراءة الدعم والمقاومة وحدها',NF)]:
    R=[run(cols,lab,sd)[0] for sd in [1,2,3]]
    print(f'  {lab:32s} '+' | '.join(f'أعلى {t}%: {np.mean([r[q][0] for r in R]):5.1f}% (n={R[0][q][1]})' for q,t in enumerate([30,15,7])))
_,m=run(feat+NF,'x')
imp=pd.Series(m.feature_importances_,index=feat+NF).sort_values(ascending=False)
print('أهم المعلومات الجديدة:',', '.join(f'{k} {v*100:.1f}%' for k,v in imp[NF].sort_values(ascending=False).head(6).items()))
