exec(open('spread.py').read().split("for tf,f in")[0])
T=[]
for tf,f in [('15m','gold20/xau20_15m.csv'),('1h','gold20/xau20_1h.csv')]:
    d=pd.read_csv(S+'/'+f); d.columns=[x.lower() for x in d.columns]; t=pd.to_datetime(d.iloc[:,0])
    o,h,l,c=[d[x].values.astype(float) for x in ['open','high','low','close']]; pc=np.r_[c[0],c[:-1]]
    a=pd.Series(np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))).ewm(alpha=1/14,adjust=False).mean().values
    m=((key.market=='gold20')&(key.tf==tf)).values&(s.p.values>=Q70)
    for i,di in zip(key.i.values[m],key.dir.values[m]):
        if t.iloc[i].year<2019 or i+2>=len(c): continue
        g,rk=sim(o,h,l,c,a,int(i),int(di),0.0,0.25,1.0,3.0)
        # وقت الدخول = إغلاق شمعة الإشارة، بتوقيت السودان (توقيت البيانات − 1 ساعة)
        te=t.iloc[i]+pd.Timedelta(minutes=15 if tf=='15m' else 60)-pd.Timedelta(hours=1)
        T.append([te,tf,g/rk])
T=pd.DataFrame(T,columns=['time','tf','r']).dropna()
T['h']=T.time.dt.hour; T['per']=np.where(T.time.dt.year<=2022,'2019-22','2023-25')
def sess(h):
    if 0<=h<9: return '1 آسيا (12 بالليل - 9 الصباح)'
    if 9<=h<14: return '2 لندن (9 الصباح - 2 الضهر)'
    if 14<=h<18: return '3 لندن + نيويورك (2 - 6 العصر)'
    return '4 نيويورك المتأخرة (6 المغرب - 12 بالليل)'
T['s']=T.h.map(sess)
print(f'King ⭐+ ذهب 15m+1h، 2019-2025، {len(T)} صفقة، هدف 1R ثم 3R، بعد السبريد — المتوسط {T.r.mean():+.3f}R')
print('\n== حسب الجلسة (توقيت السودان)')
for sname,G in T.groupby('s'):
    a1=G[G.per=='2019-22'].r; a2=G[G.per=='2023-25'].r
    print(f'   {sname[2:]:40s} n={len(G):4d} | {G.r.mean():+.3f}R | لم يضرب الوقف كاملاً {(G.r>-0.99).mean()*100:4.1f}% | 2019-22: {a1.mean():+.3f} • 2023-25: {a2.mean():+.3f}')
print('\n== حسب الساعة (توقيت السودان)')
for hh,G in T.groupby('h'):
    a1=G[G.per=='2019-22'].r; a2=G[G.per=='2023-25'].r
    bar='█'*int(max(0,G.r.mean())*40)
    print(f'   {hh:02d}:00  n={len(G):3d} | {G.r.mean():+.3f}R | 2019-22: {a1.mean():+.3f} • 2023-25: {a2.mean():+.3f} {bar}')
print()
for lab,X in [('كل الساعات',T),('بدون 10 بالليل - 12 بالليل',T[~T.h.isin([22,23])])]:
    X=X[X.time.dt.year>=2021].sort_values('time')
    print(f'{lab:28s} 2021-25: {len(X)} صفقة | {X.r.mean():+.3f}R/صفقة | مجموع {X.r.sum():+.0f}R')
