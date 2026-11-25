# من فريم كبير لفريم صغير: منطقة/مستوى على الساعة أو اليوم السابق → تأكيد كسر هيكل على 5m → دخول بوقف صغير
# الذهب 2015-2026 (5m مجمّع من 1m). كل النتائج بعد سبريد 0.25$.
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
SP=0.25
d=pd.read_csv(S+'/m1/xau_5m.csv'); d['time']=pd.to_datetime(d.time)
o,h,l,c,v=[d[x].values.astype(np.float64) for x in ['open','high','low','close','volume']]
t=d.time.values; n=len(c)
pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a5=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
# فريم الساعة
H=d.set_index('time').resample('1h',label='left',closed='left').agg({'open':'first','high':'max','low':'min','close':'last','volume':'sum'}).dropna().reset_index()
ho,hh,hl,hc=[H[x].values for x in ['open','high','low','close']]
hpc=np.r_[hc[0],hc[:-1]]; htr=np.maximum(hh-hl,np.maximum(abs(hh-hpc),abs(hl-hpc))); ha=pd.Series(htr).ewm(alpha=1/14,adjust=False).mean().values
he50=pd.Series(hc).ewm(span=50,adjust=False).mean().values
hend=(H.time+pd.Timedelta(hours=1)).values   # المنطقة تُعرف بعد إغلاق شمعة الساعة
# مناطق الساعة: [dir, lo, hi, valid_from_time, kind, impulse]
zones=[]
for i in range(20,len(hc)):
    ai=ha[i]
    if ai<=0: continue
    # عرض/طلب: قاعدة 1-3 شموع صغيرة ثم انطلاق ≥ 2 ATR خلال 3 شموع
    for bn in (1,2,3):
        b0=i-3-bn+1; b1=i-3
        if b0<1: continue
        if hh[b0:b1+1].max()-hl[b0:b1+1].min()>ha[b1]: continue
        blo=hl[b0:b1+1].min(); bhi=hh[b0:b1+1].max(); imp=hc[i]-hc[b1]
        if imp>=2*ha[b1] and hc[i]>bhi+ha[b1]: zones.append((1,blo,bhi,hend[i],'SD',imp/ha[b1])); break
        if -imp>=2*ha[b1] and hc[i]<blo-ha[b1]: zones.append((-1,blo,bhi,hend[i],'SD',-imp/ha[b1])); break
    # أوردر بلوك: شمعة إزاحة ≥ 1.5 ATR تكسر أعلى/أدنى 10 شموع → آخر شمعة عكسية قبلها
    rg=hh[i]-hl[i]
    if rg>=1.5*ai:
        if hc[i]>hh[i-10:i].max() and hc[i]>ho[i]:
            for k in range(i-1,i-6,-1):
                if hc[k]<ho[k]: zones.append((1,hl[k],max(ho[k],hc[k]),hend[i],'OB',rg/ai)); break
        if hc[i]<hl[i-10:i].min() and hc[i]<ho[i]:
            for k in range(i-1,i-6,-1):
                if hc[k]>ho[k]: zones.append((-1,min(ho[k],hc[k]),hh[k],hend[i],'OB',rg/ai)); break
Z=pd.DataFrame(zones,columns=['dir','lo','hi','vt','kind','imp']).sort_values('vt').reset_index(drop=True)
print('مناطق الساعة',Z.kind.value_counts().to_dict(),file=sys.stderr)
# مستويات اليوم السابق: قمة/قاع (سيولة) + فوليوم بروفايل (POC، VAH، VAL)
d['day']=d.time.dt.floor('D')
lv=[]
days=d.groupby('day')
prev=None
for day,g in days:
    if prev is not None and len(prev)>100:
        lo_,hi_=prev.low.min(),prev.high.max()
        bins=np.arange(np.floor(lo_),np.ceil(hi_)+0.5,0.5)
        tp=(prev.high.values+prev.low.values+prev.close.values)/3
        hist,_=np.histogram(tp,bins=bins,weights=prev.volume.values+1e-9)
        k=int(np.argmax(hist)); poc=(bins[k]+bins[k+1])/2
        # منطقة القيمة 70% حول POC
        tot=hist.sum(); lo_k=hi_k=k; s=hist[k]
        while s<0.7*tot and (lo_k>0 or hi_k<len(hist)-1):
            up_=hist[hi_k+1] if hi_k<len(hist)-1 else -1; dn_=hist[lo_k-1] if lo_k>0 else -1
            if up_>=dn_: hi_k+=1; s+=up_
            else: lo_k-=1; s+=dn_
        lv.append((day,hi_,lo_,poc,bins[hi_k+1],bins[lo_k]))
    prev=g
LV=pd.DataFrame(lv,columns=['day','pdh','pdl','poc','vah','val']).set_index('day')
dl=d.day.map(LV.pdh).values, d.day.map(LV.pdl).values, d.day.map(LV.poc).values, d.day.map(LV.vah).values, d.day.map(LV.val).values
pdh,pdl,poc,vah,val=[np.nan_to_num(x,nan=np.nan) for x in dl]
# اتجاه الساعة (EMA50) عند كل شمعة 5m
hidx=np.searchsorted(hend,t,side='right')-1
htrend=np.where(hidx>=0,np.sign(hc[np.clip(hidx,0,None)]-he50[np.clip(hidx,0,None)]),0)
hatr=np.where(hidx>=0,ha[np.clip(hidx,0,None)],np.nan)
yr=d.time.dt.year.values; hr=d.time.dt.hour.values

@njit
def confirm(o,h,l,c,a5,start,dd,lim_lo,lim_hi,maxw):
    # بعد لمس المنطقة عند start: انتظر كسر هيكل صغير (إغلاق فوق أعلى قمة منذ start-3) — يرجع (entry_i, stop) أو (-1,0)
    n=len(c)
    ext=l[start] if dd>0 else h[start]
    ref=-1e18 if dd>0 else 1e18
    for k in range(max(0,start-3),start+1):
        ref=max(ref,h[k]) if dd>0 else min(ref,l[k])
    for j in range(start+1,min(n-1,start+maxw)):
        if dd>0:
            if c[j]<lim_lo: return -1,0.0
            ext=min(ext,l[j])
            if c[j]>ref and c[j]>o[j]: return j,ext-0.1*a5[j]
            ref=min(ref,max(h[j],ref)) if False else ref
            if h[j]<ref: pass
        else:
            if c[j]>lim_hi: return -1,0.0
            ext=max(ext,h[j])
            if c[j]<ref and c[j]<o[j]: return j,ext+0.1*a5[j]
    return -1,0.0
@njit
def exitR(h,l,o,i,dd,stop,RR):
    n=len(h); e=o[i+1]; rk=(e-stop)*dd
    if rk<=0: return np.nan,0.0
    tp=e+RR*dd*rk
    for j in range(i+1,min(n,i+600)):
        if (dd>0 and l[j]<=stop) or (dd<0 and h[j]>=stop): return -1.0,rk
        if (dd>0 and h[j]>=tp) or (dd<0 and l[j]<=tp): return RR,rk
    return 0.0,rk
rows=[]
zi=0; act=[]
used_lv={}
for i in range(300,n-2):
    # تفعيل المناطق التي اكتملت
    while zi<len(Z) and Z.vt[zi]<=t[i]:
        act.append([Z.dir[zi],Z.lo[zi],Z.hi[zi],Z.kind[zi],Z.imp[zi],0,i]); zi+=1
    if i%2000==0: act=[z for z in act if i-z[6]<12*24*10][-80:]
    ai=hatr[i]
    if not (ai>0): continue
    evs=[]
    keep=[]
    for z in act:
        dd,lo,hi,kind,imp,tch,born=z
        if (dd>0 and c[i]<lo-0.2*ai) or (dd<0 and c[i]>hi+0.2*ai): continue   # كُسرت
        inside=(l[i]<=hi) if dd>0 else (h[i]>=lo)
        was=(l[i-1]<=hi) if dd>0 else (h[i-1]>=lo)
        if inside and not was:
            z[5]+=1
            if z[5]==1: evs.append((dd,kind,lo,hi,imp))
            if z[5]>=2: continue
        keep.append(z)
    act=keep
    # سيولة: كسر قاع/قمة اليوم السابق ثم الإغلاق داخل
    for dd,lvl,nm in ((1,pdl[i],'سحب قاع أمس'),(-1,pdh[i],'سحب قمة أمس')):
        if np.isnan(lvl): continue
        key=(nm,d.day.values[i])
        if key in used_lv: continue
        if (dd>0 and l[i]<lvl and c[i]>lvl) or (dd<0 and h[i]>lvl and c[i]<lvl):
            used_lv[key]=1; evs.append((dd,nm,lvl-0.5*ai if dd>0 else lvl,lvl if dd>0 else lvl+0.5*ai,0.0))
    # فوليوم بروفايل أمس: أول لمس لـ VAL/POC من فوق (شراء) و VAH/POC من تحت (بيع)
    for dd,lvl,nm in ((1,val[i],'VAL أمس'),(-1,vah[i],'VAH أمس'),(1,poc[i],'POC أمس ↑'),(-1,poc[i],'POC أمس ↓')):
        if np.isnan(lvl): continue
        key=(nm,d.day.values[i])
        if key in used_lv: continue
        if (dd>0 and l[i]<=lvl and o[i]>lvl) or (dd<0 and h[i]>=lvl and o[i]<lvl):
            used_lv[key]=1; evs.append((dd,nm,lvl-0.3*ai,lvl+0.3*ai,0.0))
    for dd,kind,lo,hi,imp in evs:
        j,stop=confirm(o,h,l,c,a5,i,dd,lo-0.2*ai,hi+0.2*ai,36)
        if j<0: continue
        e=o[j+1]; rk=(e-stop)*dd
        if rk<1.0: stop=e-dd*1.0; rk=1.0          # أقل وقف 1$ (السبريد)
        res={}
        for RR in (1.0,2.0,3.0):
            r,_=exitR(h,l,o,j,dd,stop,RR); res[RR]=r
        if np.isnan(res[1.0]): continue
        rows.append([kind,int(yr[j]),dd,int(hr[j]),rk,rk/ai,imp,int(htrend[j]*dd),res[1.0]-SP/rk,res[2.0]-SP/rk,res[3.0]-SP/rk,j-i])
    if i%100000==0: print(i,len(rows),file=sys.stderr,flush=True)
R=pd.DataFrame(rows,columns=['kind','year','dir','hour','risk','risk_atr','imp','with_trend','r1','r2','r3','wait'])
R.to_csv(S+'/ai/topdown.csv',index=False)
def show(lab,m):
    x=R[m]
    print(f"{lab:26s} n={len(x):6d} | 1R {(x.r1>0).mean()*100:5.1f}% R{x.r1.mean():+.3f} | 2R {(x.r2>0).mean()*100:5.1f}% R{x.r2.mean():+.3f} | 3R {(x.r3>0).mean()*100:5.1f}% R{x.r3.mean():+.3f}")
print('بعد سبريد 0.25$ — التعادل: 1R 50%+ • 2R 33%+ • 3R 25%+ (حسب السبريد)')
for ph,mm in [('تدريب 2015-2020',R.year<=2020),('اختبار 2021-2026',R.year>=2021)]:
    print('==',ph)
    for k in R.kind.unique(): show(k,mm&(R.kind==k))
    show('الكل',mm); show('الكل مع ترند الساعة',mm&(R.with_trend>0)); show('الكل ضد ترند الساعة',mm&(R.with_trend<0))
    show('لندن/نيويورك (7-17 UTC)',mm&(R.hour>=7)&(R.hour<=17))
