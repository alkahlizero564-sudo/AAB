# MA — تداول السيولة: سحب سيولة (أمس/آسيا/قمم متساوية/آخر قمة) → كسر هيكل → دخول (مباشر/FVG/POC) → هدف السيولة المعاكسة
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
from numba import njit
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
@njit
def fill_and_exit(h,l,o,start,d,entry,stop,tp,limit,maxwait):
    # limit=True: أمر معلّق عند entry ينتظر حتى maxwait شمعة؛ False: دخول بافتتاح start
    n=len(h); j0=start
    if limit:
        filled=-1
        for j in range(start,min(n,start+maxwait)):
            if (d>0 and l[j]<=stop) or (d<0 and h[j]>=stop): return np.nan,-1   # الوقف قبل الدخول → إلغاء
            if (d>0 and l[j]<=entry) or (d<0 and h[j]>=entry): filled=j; break
        if filled<0: return np.nan,-1
        j0=filled
        e=entry
    else:
        e=o[start]
    rk=(e-stop)*d
    if rk<=0: return np.nan,-1
    for j in range(j0,min(n,j0+2000)):
        if (d>0 and l[j]<=stop) or (d<0 and h[j]>=stop): return -1.0,j0
        if j>j0 and ((d>0 and h[j]>=tp) or (d<0 and l[j]<=tp)): return (tp-e)*d/rk,j0
    return 0.0,j0
SP=0.25
out=[]
for tf,f in [('5m','m1/xau_5m.csv'),('15m','gold20/xau20_15m.csv')]:
    d=pd.read_csv(f'{S}/{f}'); d['time']=pd.to_datetime(d.time); d=d[d.time>='2015-01-01'].reset_index(drop=True)
    o,h,l,c,v=[d[x].values.astype(np.float64) for x in ['open','high','low','close','volume']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc))); a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    bh=d.time.dt.hour.values; utc=(bh-2)%24   # بيانات الوسيط ≈ UTC+2
    day=d.time.dt.floor('D').values
    # قمة/قاع أمس + آسيا (00-07 UTC) لليوم الحالي
    g=d.groupby(d.time.dt.floor('D'))
    dh=g.high.max(); dlw=g.low.min()
    pdh=d.time.dt.floor('D').map(dh.shift(1)).values; pdl=d.time.dt.floor('D').map(dlw.shift(1)).values
    asia=(utc>=0)&(utc<7)
    ah=np.full(n,np.nan); al=np.full(n,np.nan); cur_h=-1e18; cur_l=1e18; cd=None
    for i in range(n):
        if day[i]!=cd: cd=day[i]; cur_h=-1e18; cur_l=1e18
        if asia[i]: cur_h=max(cur_h,h[i]); cur_l=min(cur_l,l[i])
        elif cur_h>-1e17: ah[i]=cur_h; al[i]=cur_l
    # 1h EMA50 اتجاه (للفلتر)
    e_h=pd.Series(c).ewm(span=50*(12 if tf=='5m' else 4),adjust=False).mean().values
    PH=[];PL=[]; used=set(); last_sig=-99
    for i in range(300,n-3):
        j=i-3
        if h[j]==h[j-3:j+4].max(): PH.append((j,h[j]))
        if l[j]==l[j-3:j+4].min(): PL.append((j,l[j]))
        ai=a[i]
        if ai<=0 or i-last_sig<6: continue
        pools=[]   # (dir_of_trade, level, kind)
        if not np.isnan(pdh[i]): pools+= [(-1,pdh[i],'قمة أمس'),(1,pdl[i],'قاع أمس')]
        if not np.isnan(ah[i]): pools+= [(-1,ah[i],'قمة آسيا'),(1,al[i],'قاع آسيا')]
        rph=[p for p in PH[-12:] if i-p[0]<=120]; rpl=[p for p in PL[-12:] if i-p[0]<=120]
        for P,dd,nm in ((rph,-1,'قمم متساوية'),(rpl,1,'قيعان متساوية')):
            for x in range(len(P)-1):
                for y in range(x+1,len(P)):
                    if abs(P[x][1]-P[y][1])<0.15*ai and P[y][0]-P[x][0]>=5: pools.append((dd,(P[x][1]+P[y][1])/2,nm))
        if rph: pools.append((-1,rph[-1][1],'آخر قمة'))
        if rpl: pools.append((1,rpl[-1][1],'آخر قاع'))
        for dd,lv,kind in pools:
            key=(kind,round(lv,1))
            if key in used: continue
            swept=(dd<0 and h[i]>lv and c[i]<lv) or (dd>0 and l[i]<lv and c[i]>lv)
            if not swept: continue
            used.add(key)
            # كسر الهيكل خلال 12 شمعة: إغلاق خلف أدنى قاع (للبيع) / أعلى قمة (للشراء) لـ 10 شموع قبل السحب
            ref=(l[i-10:i].min() if dd<0 else h[i-10:i].max())
            ext=h[i] if dd<0 else l[i]; k=-1
            for t in range(i+1,min(n-2,i+13)):
                ext=max(ext,h[t]) if dd<0 else min(ext,l[t])
                if (dd<0 and c[t]<ref) or (dd>0 and c[t]>ref): k=t; break
                if (dd<0 and c[t]>ext) or (dd>0 and c[t]<ext): break
            if k<0: continue
            last_sig=i
            stop=ext+dd*(-0.1*ai) if False else (ext+0.1*ai if dd<0 else ext-0.1*ai)
            # السيولة المعاكسة: أقرب مستوى بالاتجاه الآخر
            opp=[p[1] for p in pools if p[0]==-dd and (p[1]-c[k])*dd>0]
            tpo=(min(opp) if dd>0 else max(opp)) if opp else np.nan
            # FVG في موجة الكسر
            fvg=np.nan
            for t in range(k,i,-1):
                if dd<0 and l[t-1]>h[t+1] if t+1<=k else False: fvg=h[t+1]; break
                if dd>0 and h[t-1]<l[t+1] if t+1<=k else False: fvg=l[t+1]; break
            # POC لموجة السحب→الكسر (حجم التيك)
            seg=slice(i,k+1); px=(h[seg]+l[seg]+c[seg])/3; vv=v[seg]+1e-9
            bins=np.arange(l[seg].min(),h[seg].max()+0.25*ai,0.25*ai)
            if len(bins)>2:
                hist,_=np.histogram(px,bins=bins,weights=vv); m=int(np.argmax(hist)); poc=(bins[m]+bins[m+1])/2
            else: poc=np.nan
            trend=1 if (c[k]-e_h[k])*dd>0 else 0
            kz=1 if (7<=utc[i]<=10) or (12<=utc[i]<=15) else 0
            for mode,ent,lim in (('مباشر',np.nan,False),('FVG',fvg,True),('POC',poc,True)):
                if lim and (np.isnan(ent) or (ent-stop)*dd<=0 or (c[k]-ent)*dd<=0): continue
                e0=o[k+1] if not lim else ent
                rk=(e0-stop)*dd
                if rk<max(0.2*ai,1.0 if tf=='5m' else 0):
                    stop=e0-dd*max(0.2*ai,1.0 if tf=='5m' else 0); rk=(e0-stop)*dd
                res={}
                for nm,tp in (('2R',e0+dd*2*rk),('3R',e0+dd*3*rk),('سيولة',tpo if not np.isnan(tpo) and (tpo-e0)*dd>=1.0*rk else e0+dd*2*rk)):
                    r,_=fill_and_exit(h,l,o,k+1,dd,e0,stop,tp,lim,30)
                    res[nm]=r
                if np.isnan(res['2R']): continue
                out.append([tf,int(d.time.dt.year.values[i]),kind,mode,dd,trend,kz,int(utc[i]),rk/ai,res['2R']-SP/rk,res['3R']-SP/rk,res['سيولة']-SP/rk])
        if i%100000==0: print(tf,i,len(out),file=sys.stderr,flush=True)
R=pd.DataFrame(out,columns=['tf','year','kind','mode','dir','trend','kz','hour','risk_atr','r2','r3','rl'])
R.to_csv(S+'/ai/ma.csv',index=False)
def show(lab,x):
    if len(x)<20: return
    print(f"  {lab:30s} n={len(x):5d} | 2R {(x.r2>0).mean()*100:5.1f}% R{x.r2.mean():+.3f} | 3R {(x.r3>0).mean()*100:5.1f}% R{x.r3.mean():+.3f} | هدف السيولة {(x.rl>0).mean()*100:5.1f}% R{x.rl.mean():+.3f}")
print('ذهب بعد سبريد 0.25$ — التعادل: 2R 33% • 3R 25%')
for tf in ['5m','15m']:
    for ph,m in [('تدريب 2015-2020',R.year<=2020),('اختبار 2021-2026',R.year>=2021)]:
        x=R[(R.tf==tf)&m]; print(f'== {tf} {ph}')
        for md in ['مباشر','FVG','POC']: show(f'دخول {md}',x[x['mode']==md])
        for k in x.kind.unique(): show(f'  سيولة: {k} (POC)',x[(x.kind==k)&(x['mode']=='POC')])
        show('POC + أوقات لندن/نيويورك',x[(x['mode']=='POC')&(x.kz==1)])
        show('POC + مع الترند',x[(x['mode']=='POC')&(x.trend==1)])
        show('POC + الوقتين + الترند',x[(x['mode']=='POC')&(x.kz==1)&(x.trend==1)])
        show('FVG + الوقتين + الترند',x[(x['mode']=='FVG')&(x.kz==1)&(x.trend==1)])
