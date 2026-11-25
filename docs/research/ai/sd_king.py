# معلومات مناطق العرض والطلب لكل إشارة في بيانات King (signals2) ثم: هل تحسّن King؟
import pandas as pd, numpy as np, warnings
warnings.filterwarnings('ignore')
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
key=pd.read_csv(S+'/ai/sdkey.csv'); df=pd.read_csv(S+'/ai/signals2.csv')
assert len(key)==len(df) and (key.win.values==df.win.values).all()
def load(p):
    d=pd.read_csv(p); d.columns=[x.lower() for x in d.columns]; d=d.rename(columns={d.columns[0]:'time'})
    d['time']=pd.to_datetime(d.time,utc=True,errors='coerce'); return d.dropna(subset=['time']).sort_values('time').reset_index(drop=True)
files={('gold20',t):f'gold20/xau20_{t}' for t in ['15m','1h','4h']}
files.update({('btc',t):f'gold10/btc10_{t}' for t in ['15m','1h','4h']})
ZC=['z_in_sup','z_in_opp','z_d_sup','z_d_opp','z_n_sup','z_n_opp','z_imp_sup','z_fresh_sup']
Z=np.full((len(df),len(ZC)),np.nan)
for (mk,tf),f in files.items():
    d=load(f'{S}/{f}.csv'); o,h,l,c=[d[x].values.astype(np.float64) for x in ['open','high','low','close']]
    n=len(c); pc=np.r_[c[0],c[:-1]]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    a=pd.Series(tr).ewm(alpha=1/14,adjust=False).mean().values
    sel=np.where((key.market==mk)&(key.tf==tf))[0]
    want={}
    for r in sel: want.setdefault(int(key.i[r]),[]).append(r)
    bad=sum(abs(c[int(key.i[r])]-key.close[r])>1e-6*max(1,key.close[r]) for r in sel[:200])
    print(mk,tf,'rows',len(sel),'mismatch',bad,flush=True)
    zones=[]
    for i in range(10,n):
        ai=a[i]
        if ai<=0: continue
        for bn in (1,2,3):
            b0=i-3-bn+1; b1=i-3
            if b0<1: continue
            if h[b0:b1+1].max()-l[b0:b1+1].min()>a[b1] or any(abs(c[k]-o[k])>0.6*a[k] for k in range(b0,b1+1)): continue
            blo=l[b0:b1+1].min(); bhi=h[b0:b1+1].max(); imp=c[i]-c[b1]
            if imp>=2*a[b1] and c[i]>bhi+a[b1]: zones.append([1,blo,bhi,i,imp/a[b1],0]); break
            if -imp>=2*a[b1] and c[i]<blo-a[b1]: zones.append([-1,blo,bhi,i,-imp/a[b1],0]); break
        zones=[z for z in zones if not ((z[0]>0 and c[i]<z[1]-0.1*ai) or (z[0]<0 and c[i]>z[2]+0.1*ai)) and i-z[3]<=300][-60:]
        if i in want:
            for r in want[i]:
                dd=int(key.dir[r]); p=c[i]
                sup=[z for z in zones if z[0]==dd and z[3]<i]; opp=[z for z in zones if z[0]==-dd and z[3]<i]
                def dist(z):  # المسافة من السعر للمنطقة بوحدات ATR (0 = داخلها)
                    if z[1]<=p<=z[2]: return 0.0
                    return min(abs(p-z[1]),abs(p-z[2]))/ai
                ds=[dist(z) for z in sup if (p-(z[1]+z[2])/2)*dd>=-0.5*ai] or [10.0]   # الداعمة: خلف الدخول
                do=[dist(z) for z in opp if ((z[1]+z[2])/2-p)*dd>=-0.5*ai] or [10.0]   # المعاكسة: أمام الدخول
                js=int(np.argmin(ds)) if sup else -1
                bs=[z for z in sup if (p-(z[1]+z[2])/2)*dd>=-0.5*ai]
                Z[r]=[float(min(ds)<=0.3),float(min(do)<=0.3),min(min(ds),10),min(min(do),10),
                      sum(x<=3 for x in ds if x<10),sum(x<=3 for x in do if x<10),
                      (bs[int(np.argmin(ds))][4] if bs else 0.0),((i-bs[int(np.argmin(ds))][3]) if bs else 300)/300]
        # آخر تحديث للمنطقة بعد الفحص (لا نستخدم شمعة i نفسها في إلغاء قبل القرار — كلاهما سببي)
for k,cn in enumerate(ZC): df[cn]=Z[:,k]
df.to_csv(S+'/ai/signals_sd.csv',index=False)
print('saved')
