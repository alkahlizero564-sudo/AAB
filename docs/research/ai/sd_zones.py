# مناطق العرض والطلب: بناء المناطق + كل رجوع للمنطقة + نتيجته + معلومات للذكاء
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
src=open(S+'/ai/flow2.py').read(); exec(src[src.index('@njit'):src.index('def load')].replace('cache=True','cache=False').replace('@njit','from numba import njit\n@njit',1))
def load(p):
    d=pd.read_csv(p); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'})
    d['time']=pd.to_datetime(d.time,utc=True,errors='coerce'); return d.dropna(subset=['time']).reset_index(drop=True)
sets=[('gold',f'gold20/xau20_{t}',t) for t in ['15m','1h','4h']]+[('btc',f'gold10/btc10_{t}',t) for t in ['15m','1h','4h']]
rows=[]
for mk,f,tf in sets:
    d=load(f'{S}/{f}.csv'); o,h,l,c=[d[x].values.astype(np.float64) for x in ['open','high','low','close']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    a50=pd.Series(tr).ewm(alpha=1/50,adjust=False).mean().values
    e50=pd.Series(c).ewm(span=50,adjust=False).mean().values; e200=pd.Series(c).ewm(span=200,adjust=False).mean().values
    dl=pd.Series(c).diff(); up=dl.clip(lower=0).ewm(alpha=1/14,adjust=False).mean(); dn=(-dl.clip(upper=0)).ewm(alpha=1/14,adjust=False).mean()
    rsi=(100-100/(1+up/dn.replace(0,1e-12))).values
    hh50=pd.Series(h).rolling(50).max().values; ll50=pd.Series(l).rolling(50).min().values
    yr=d.time.dt.year.values; hr=d.time.dt.hour.values; wd=d.time.dt.weekday.values
    zones=[]  # [dir, lo, hi, born, base_n, impulse, touches, maxaway, used]
    sig={m:np.zeros(n,np.int64) for m in ['touch','react']}; stp={m:np.full(n,np.nan) for m in ['touch','react']}
    feats={'touch':{},'react':{}}
    for i in range(210,n-1):
        ai=a[i]
        if ai<=0: continue
        # منطقة جديدة: قاعدة 1-3 شموع صغيرة ثم انطلاق قوي ≥ 2 ATR خلال 3 شموع
        for bn in (1,2,3):
            b0=i-3-bn+1; b1=i-3
            if b0<1: continue
            rng_=h[b0:b1+1].max()-l[b0:b1+1].min()
            if rng_>1.0*a[b1] or any(abs(c[k]-o[k])>0.6*a[k] for k in range(b0,b1+1)): continue
            blo=l[b0:b1+1].min(); bhi=h[b0:b1+1].max()
            imp=c[i]-c[b1]
            if imp>=2*a[b1] and c[i]>bhi+a[b1]: zones.append([1,blo,bhi,i,bn,imp/a[b1],0,0.0,False]); break
            if -imp>=2*a[b1] and c[i]<blo-a[b1]: zones.append([-1,blo,bhi,i,bn,-imp/a[b1],0,0.0,False]); break
        keep=[]
        for z in zones:
            dd,lo,hi,born,bn,imp,tch,away,_=z
            if i<=born: keep.append(z); continue
            # أُلغيت: إغلاق خلف المنطقة
            if (dd>0 and c[i]<lo-0.1*ai) or (dd<0 and c[i]>hi+0.1*ai): continue
            if i-born>300: continue
            prox=hi if dd>0 else lo
            dist=((l[i]-prox) if dd>0 else (prox-h[i]))/ai
            touched=dist<=0
            if not touched:
                z[7]=max(away,dist); keep.append(z); continue
            if z[7]<1.5:   # لم يبتعد بعد — لا رجوع حقيقي
                keep.append(z); continue
            tch+=1; z[6]=tch; z[7]=0.0
            if tch<=3:
                # مساحة للهدف: أقرب منطقة معاكسة
                opp=[(zz[1] if dd>0 else zz[2]) for zz in zones if zz[0]==-dd and zz[3]<i]
                room=min([((x-c[i])*dd)/ai for x in opp if (x-c[i])*dd>0] or [20.0])
                fv=[mk=='gold',{'15m':15,'1h':60,'4h':240}[tf],(hi-lo)/ai,imp,bn,i-born,tch,away,
                    (c[i]-e50[i])/ai*dd,(c[i]-e200[i])/ai*dd,(e50[i]-e50[i-10])/ai*dd,(rsi[i]-50)/50*dd,
                    np.log(ai/a50[i]),(c[i]-c[i-5])/ai*dd,(c[i]-c[i-20])/ai*dd,((c[i]-ll50[i])/max(hh50[i]-ll50[i],1e-9)-0.5)*dd,
                    room,(c[i]-o[i])/ai*dd,((h[i]-max(o[i],c[i])) if dd<0 else (min(o[i],c[i])-l[i]))/ai,
                    np.sin(2*np.pi*hr[i]/24),np.cos(2*np.pi*hr[i]/24),wd[i],
                    sum(1 for zz in zones if zz[0]==dd and abs((zz[1]+zz[2])/2-(lo+hi)/2)<2*ai)]
                sl=(lo-0.1*ai) if dd>0 else (hi+0.1*ai)
                if sig['touch'][i]==0: sig['touch'][i]=dd; stp['touch'][i]=sl; feats['touch'][i]=fv
                # ارتداد: لمس + إغلاق خارج المنطقة بجسم في الاتجاه
                if ((dd>0 and c[i]>hi) or (dd<0 and c[i]<lo)) and (c[i]-o[i])*dd>0 and sig['react'][i]==0:
                    sig['react'][i]=dd; stp['react'][i]=sl; feats['react'][i]=fv
            keep.append(z)
        zones=keep[-60:]
    for md in ['touch','react']:
        s=sig[md]; w=np.full(n,-1,np.int64); r=np.zeros(n); w2=np.full(n,-1,np.int64); r2=np.zeros(n)
        simall(o,h,l,c,a,s,stp[md],w,r,w2,r2)
        for i,fv in feats[md].items():
            if w[i]<0: continue
            rows.append([mk,tf,md,int(yr[i]),int(s[i]),int(w[i]),r[i],int(w2[i]),r2[i]]+list(map(float,fv)))
    print('done',mk,tf,len(rows),file=sys.stderr,flush=True)
cols=['market','tf','mode','year','dir','win','r','vwin','vr','isgold','tfm','width','impulse','base_n','age','touch_n','away',
      'e50','e200','slope','rsi','volr','mom5','mom20','pos50','room','body','wick','hs','hc','wd','stack']
pd.DataFrame(rows,columns=cols).to_csv(S+'/ai/sdz.csv',index=False)
