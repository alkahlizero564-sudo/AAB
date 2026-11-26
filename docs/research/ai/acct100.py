# حساب 100$ يتداول إشارات King على الذهب (15m + 1h) من 2021 — لوت أدنى 0.01 (أوقية = 1$ لكل 1$ حركة)، سبريد 0.25$/أوقية
import pandas as pd, numpy as np, re, json
S='/tmp/claude-0/-home-user-AAB/e2bd39c3-f0fb-5895-8329-383fc758e763/scratchpad'
exec(open(S+'/ai/king_tiers.py').read().split("src=open('/home/user/AAB/lib/analysis/king_model.dart')")[0])
src=open('/home/user/AAB/lib/analysis/king_model.dart').read(); feat=json.loads(re.search(r'const kingFeatures = (\[.*?\]);',src).group(1))
mm=load_model('/home/user/AAB/lib/analysis/king_model.dart','king')
Q70,Q85,Q93=0.5680950185109677,0.5909170281481894,0.6105149837333336
s=pd.read_csv(S+'/ai/signals2.csv'); key=pd.read_csv(S+'/ai/sdkey.csv'); s['p']=predict(mm,s[feat].values.astype(np.float32))
rows=[]
for tf,f in [('15m','gold20/xau20_15m.csv'),('1h','gold20/xau20_1h.csv')]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]
    h,l,c=[d[x].values for x in ['high','low','close']]; pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    m=((key.market=='gold20')&(key.tf==tf)).values
    x=s[m].copy(); ii=key.i.values[m]
    x['time']=pd.to_datetime(d.iloc[ii,0].values); x['stop$']=x.risk.values*a[ii]   # مسافة الوقف بالدولار لكل أوقية
    rows.append(x)
X=pd.concat(rows); X=X[(X.time.dt.year>=2021)&(X.p>=Q70)].sort_values('time')
X['stars']=np.where(X.p>=Q93,3,np.where(X.p>=Q85,2,1))
print(f'إشارات King (ذهب 15m+1h، 2021 → {X.time.max():%Y-%m}): {len(X)} صفقة | نجاح {X.win.mean()*100:.1f}% | متوسط الوقف {X["stop$"].median():.2f}$ للأوقية')
def run(rule,lab,minlot=0.01):
    bal=100.0; peak=100; dd=0; n=0; skipped=0; over=0; hist=[]
    for _,t in X.iterrows():
        if rule=='lot': rp={3:0.01,2:0.0075,1:0.005}[t.stars]
        else: rp=rule
        want=bal*rp/(t['stop$']*100)                       # لوت (1 لوت = 100 أوقية)
        lot=np.floor(want/0.01)*0.01
        if lot<minlot: lot=minlot
        risk_real=lot*100*t['stop$']
        if risk_real>bal*0.10: skipped+=1; continue        # لا ندخل صفقة مخاطرتها أكبر من 10% من الحساب
        if risk_real>bal*rp*1.5: over+=1
        pnl=lot*100*(t.r*t['stop$']) - lot*100*0.25        # النتيجة بالـ R × الوقف − السبريد
        bal+=pnl; n+=1; peak=max(peak,bal); dd=max(dd,(peak-bal)/peak); hist.append((t.time,bal))
        if bal<=5: break
    H=pd.DataFrame(hist,columns=['t','b']).set_index('t').b
    yr=H.groupby(H.index.year).last()
    print(f'\n== {lab}')
    print(f'   الرصيد: 100$ ← {bal:,.0f}$ | صفقات {n} | أكبر نزول {dd*100:.0f}% | صفقات مخاطرتها الفعلية أكبر من المطلوب (لوت 0.01): {over} | تُركت (مخاطرة >10%): {skipped}')
    print('   نهاية كل سنة: '+' • '.join(f'{y}: {v:,.0f}$' for y,v in yr.items()))
for rule,lab in [('lot','قواعد حاسبة اللوت (⭐ 0.5% • ⭐⭐ 0.75% • ⭐⭐⭐ 1%)'),(0.01,'مخاطرة 1% ثابتة'),(0.02,'مخاطرة 2% ثابتة')]:
    run(rule,lab)
# أسوأ سلسلة خسائر
w=X.win.values; mx=cur=0
for v in w:
    cur=cur+1 if v==0 else 0; mx=max(mx,cur)
print(f'\nأطول سلسلة خسائر متتالية: {mx} صفقات')
print('\n--- مقارنات')
for tf in ['15m','1h']:
    x=X[X.tf==tf]; g=x.r*x['stop$']-0.25
    print(f'{tf}: {len(x)} صفقة | متوسط الوقف {x["stop$"].median():.2f}$ | ربح قبل السبريد {(x.r*x["stop$"]).mean():+.2f}$ للأوقية | بعد السبريد {g.mean():+.2f}$ | سنوياً بلوت 0.01: {g.sum()/4.5:+.0f}$')
X0=X
for start in [100,1000]:
    for keep,lab in [(['15m','1h'],'15m+1h'),(['1h'],'1h فقط'),(['15m'],'15m فقط')]:
        X=X0[X0.tf.isin(keep)]
        bal=start; peak=start; dd=0
        for _,t in X.iterrows():
            lot=max(0.01,np.floor(bal*0.01/(t['stop$']*100)/0.01)*0.01)
            bal+=lot*100*(t.r*t['stop$']-0.25); peak=max(peak,bal); dd=max(dd,(peak-bal)/peak)
        print(f'  بداية {start}$ ({lab}، مخاطرة 1%): ← {bal:,.0f}$ (×{bal/start:.1f}) | أكبر نزول {dd*100:.0f}%')
print('\n--- حسب النجوم (بعد السبريد، دولار للأوقية لكل صفقة)')
for tf in ['15m','1h']:
    for k in [1,2,3]:
        x=X0[(X0.tf==tf)&(X0.stars>=k)]; g=x.r*x['stop$']-0.25
        print(f'  {tf} {"⭐"*k}+: {len(x)} صفقة | نجاح بعد السبريد {(g>0).mean()*100:.1f}% | {g.mean():+.2f}$ للأوقية | بالـR بعد السبريد {(g/x["stop$"]).mean():+.3f}')
X=X0[(X0.tf=='1h')|((X0.tf=='15m')&(X0.stars>=2))]
bal=100; peak=100; dd=0; hist=[]
for _,t in X.iterrows():
    lot=max(0.01,np.floor(bal*0.01/(t['stop$']*100)/0.01)*0.01)
    bal+=lot*100*(t.r*t['stop$']-0.25); peak=max(peak,bal); dd=max(dd,(peak-bal)/peak); hist.append((t.time,bal))
H=pd.DataFrame(hist,columns=['t','b']).set_index('t').b
print(f'\nالخطة المقترحة (1h كل النجوم + 15m ⭐⭐ وفوق، مخاطرة 1%): 100$ ← {bal:,.0f}$ | {len(X)} صفقة ({len(X)/4.5/52:.1f} في الأسبوع) | أكبر نزول {dd*100:.0f}%')
print('   نهاية كل سنة: '+' • '.join(f'{y}: {v:,.0f}$' for y,v in H.groupby(H.index.year).last().items()))
