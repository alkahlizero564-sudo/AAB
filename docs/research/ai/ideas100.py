# 100 فكرة المستخدم: ~60 مؤشراً قابلاً للحساب من OHLCV (الإشارة الموجبة = صعودي). اختبار كل مؤشر وحده + نموذج يجمعها + إضافتها لـ King
import pandas as pd, numpy as np, sys, warnings
warnings.filterwarnings('ignore')
exec(open('novel.py').read().split("out=[]")[0])           # outcomes() (نصف 1R ونصف 2R، سبريد)
def R_(x,p): return pd.Series(x).rolling(p,min_periods=p)
def EM(x,p): return pd.Series(x).ewm(span=p,adjust=False).mean().values
def RM(x,p): return pd.Series(x).ewm(alpha=1/p,adjust=False).mean().values
def sh(x,k=1): return np.r_[np.full(k,np.nan),x[:-k]]
def feats(t,o,h,l,c,v):
    n=len(c); pc=sh(c); pc[0]=c[0]; tr=np.maximum(h-l,np.maximum(abs(h-pc),abs(l-pc)))
    A=RM(tr,14); A=np.where(A>0,A,np.nan); A5=RM(tr,5); A50=RM(tr,50)
    rng=np.maximum(h-l,1e-12); body=c-o; up=h-np.maximum(o,c); dn=np.minimum(o,c)-l; pos=(c-l)/rng-0.5
    vr=v/np.maximum(R_(v,20).mean().values,1e-12)
    hh20=R_(h,20).max().values; ll20=R_(l,20).min().values; F={}
    F['01 الجهد مقابل النتيجة (شمعة مستهلكة)']=-np.sign(body)*(rng/A)*(1-abs(body)/rng)*vr
    F['02 تناسق الذيول (رفض متكرر)']=R_((dn-up)/A,5).sum().values
    ov=np.maximum(0,np.minimum(h,sh(h))-np.maximum(l,sh(l)))/rng
    F['03 كثافة التداخل']=R_(ov,10).mean().values*np.sign(c-sh(c,10))
    F['04 الإغلاق نحو الطرف × السرعة']=pos*(rng/A)
    F['05 الفجوات المجهرية المتراكمة']=R_((o-pc)/A,10).sum().values
    imp=(abs(sh(body))>1.5*sh(A)); F['06 انهيار زخم الشمعة الثانية']=np.where(imp,body/np.maximum(abs(sh(body)),1e-12),0)*np.sign(sh(body))
    alt=(np.sign(body)!=np.sign(sh(body))).astype(float); F['07 التناوب الإيقاعي']=(R_(alt,10).mean().values-R_(alt,40).mean().values)*np.sign(c-sh(c,10))
    F['08 تمدد الجسم مقابل التذبذب']=body/A
    bd=body/A; same4=(np.sign(bd)==np.sign(sh(bd)))&(np.sign(bd)==np.sign(sh(bd,2)))&(np.sign(bd)==np.sign(sh(bd,3)))
    F['09 الاستنزاف المتدرج']=np.where(same4,-(abs(bd)-abs(sh(bd,3)))*np.sign(bd)*-1,0)
    ph=sh(hh20); pl=sh(ll20)
    F['10 الانعكاس بعد الاختراق الوهمي']=np.where((h>ph)&(c<ph),-1,0)+np.where((l<pl)&(c>pl),1,0)
    F['11 ضغط الإغلاق المتراكم']=R_(pos,10).sum().values
    F['12 التشوه عند القمم والقيعان']=np.where(h>=hh20,-up/rng,0)+np.where(l<=ll20,dn/rng,0)
    ub=np.where(body>0,body,0); db=np.where(body<0,-body,0)
    F['13 التوازن الحراري']=np.log((R_(ub,20).sum().values+1e-9)/(R_(db,20).sum().values+1e-9))
    nr=(rng<sh(rng))&(sh(rng)<sh(rng,2))&(sh(rng,2)<sh(rng,3)); F['14 انكماش النطاق قبل الانطلاق']=np.where(nr,1,0)*np.sign(c-sh(c,20))
    F['15 كفاءة المسار داخل الشمعة']=body/rng
    F['16 انعكاس الهيمنة اللحظية']=np.where((np.sign(body)!=np.sign(sh(body)))&(abs(body)>abs(sh(body))),np.sign(body),0)
    x=np.arange(20); xm=x.mean(); den=((x-xm)**2).sum()
    slope=R_(c,20).apply(lambda y: ((x-xm)*(y-y.mean())).sum()/den,raw=True).values if n<250000 else (c-sh(c,19))/19
    F['17 التشتت عن الاتجاه المحلي']=-R_(c,20).std().values/A*np.sign(slope)
    e20=EM(c,20); F['18 الحجم المرجح بالانحراف']=(c-e20)/A*vr
    quiet=sh(A5/A50)<0.6; F['19 نبض السيولة بعد التوقف']=np.where(quiet&(abs(body)>A),np.sign(body),0)
    F['20 التآكل الهيكلي']=((hh20-sh(hh20,10))-(sh(hh20,10)-sh(hh20,20)))/A
    eqh=R_(h,30).apply(lambda y: (np.abs(y-y.max())<0.1*np.nanmean(np.abs(np.diff(y)))*3).sum(),raw=True).values if n<250000 else np.zeros(n)
    F['21 مصائد السيولة القريبة']=np.where((h>ph)&(c<ph),-1,0)*np.minimum(eqh,5)+np.where((l<pl)&(c>pl),1,0)
    F['22 عمق الاختراق الوهمي']=np.where((h>ph)&(c<ph),-(h-ph)/A,0)+np.where((l<pl)&(c>pl),(pl-l)/A,0)
    F['23 امتصاص الضغط عند المستويات']=np.where(c-ll20<A,1,0)*(R_(tr,5).sum().values/A)/(abs(c-sh(c,5))/A+0.5)-np.where(hh20-c<A,1,0)*(R_(tr,5).sum().values/A)/(abs(c-sh(c,5))/A+0.5)
    fvgu=np.where(l>sh(h,2),1,0); fvgd=np.where(h<sh(l,2),1,0); F['24 الفراغ السعري النشط']=R_(fvgu-fvgd,20).sum().values
    mom=(c-sh(c,10))/A
    F['25 احتمالية الكسر الكاذب']=np.where(h>ph,-1/(abs(mom)+0.5),0)+np.where(l<pl,1/(abs(mom)+0.5),0)
    F['26 مغناطيس السيولة غير المحصلة']=((hh20-c)-(c-ll20))/A*-1
    p5h=R_(h,5).max().values; p5l=R_(l,5).min().values
    dbl_b=(abs(sh(ll20,5)-sh(ll20,15))<0.3*A)&(l<sh(ll20))&(c>sh(ll20)); dbl_t=(abs(sh(hh20,5)-sh(hh20,15))<0.3*A)&(h>sh(hh20))&(c<sh(hh20))
    F['27 الانعكاس بعد سحب القاع/القمة المزدوجة']=dbl_b.astype(float)-dbl_t.astype(float)
    imp_o=np.where(abs(body)>2*A,o,np.nan); last_o=pd.Series(imp_o).ffill().values; last_d=pd.Series(np.where(abs(body)>2*A,np.sign(body),np.nan)).ffill().values
    F['28 الارتداد من نقطة الاختلال']=np.where(abs(c-last_o)<0.5*A,last_d,0)
    rn=np.where(c>5000,1000,np.where(c>500,10,0.01)); dr=(c/rn-np.round(c/rn))*rn
    F['29 الأرقام النفسية']=-dr/A
    F['30 فشل الاستمرار بعد الكسر']=np.where(sh(c)>sh(ph),-(1-(c-sh(c))/A),0)+np.where(sh(c)<sh(pl),(1+(c-sh(c))/A),0)
    sweep_dn=(sh(l,2)<sh(pl,2)); sweep_up=(sh(h,2)>sh(ph,2))
    F['31 الاندفاع المعاكس بعد الصيد']=np.where(sweep_dn,(c-sh(c,2))/A,0)+np.where(sweep_up,(c-sh(c,2))/A,0)
    r14=100-100/(1+RM(np.clip(c-pc,0,None),14)/np.maximum(RM(np.clip(pc-c,0,None),14),1e-12))
    F['32 التنافر بين الكسر والزخم']=np.where(c>ph,-(R_(r14,20).max().values-r14)/10,0)+np.where(c<pl,(r14-R_(r14,20).min().values)/10,0)
    F['33 استنزاف المشترين/البائعين']=np.where(h>=hh20,-1,0)*(1-(c-sh(c,3))/(3*A))+np.where(l<=ll20,1,0)*(1+(c-sh(c,3))/(3*A))
    F['36 كشف الخداع الاتجاهي (ADX يتغير)']=np.sign(c-sh(c,5))*(EM(abs(c-pc),14)/A-sh(EM(abs(c-pc),14)/A,5))
    dpos=(c-ll20)/np.maximum(hh20-ll20,1e-12)
    F['38 الانعكاس من أطراف النطاق']=np.where(dpos<0.15,np.sign(body),0)+np.where(dpos>0.85,np.sign(body),0)*-1*-1
    F['39 ضغط التصفية']=(A5/A-1)*np.sign(c-sh(c,3))
    F['40 مصداقية الكسر الهيكلي']=np.where(c>ph,pos*abs(body)/A,0)+np.where(c<pl,pos*abs(body)/A,0)
    er10=abs(c-sh(c,10))/np.maximum(R_(abs(c-pc),10).sum().values,1e-12); er30=abs(c-sh(c,30))/np.maximum(R_(abs(c-pc),30).sum().values,1e-12)
    F['41/42 كفاءة الحركة الاتجاهية']=er10*np.sign(c-sh(c,10))
    sd=R_(c,20).std().values; F['43 رادار الانضغاط']=-(2*sd/(1.5*A))*np.sign(c-sh(c,20))
    F['44 فلتر الضوضاء']=(1-er30)*np.sign(c-sh(c,30))
    F['46 من الهدوء للعاصفة']=np.where((sh(A5/A50,3)<0.8)&(A5/A50>1.1),np.sign(c-sh(c,3)),0)
    F['48 استقرار الاتجاه']=np.sign(c-sh(c,20))/(R_(np.sign(c-pc),20).std().values+0.1)
    roc=(c-sh(c,10))/A; F['49 التباطؤ الهيكلي']=roc-sh(roc,5)
    F['50 تباين التذبذب عبر النوافذ']=(A5/A50-1)*np.sign(c-sh(c,5))
    obv=np.cumsum(np.sign(c-pc)*v); F['52/53 التجميع الصامت / التصريف الخفي']=(obv-sh(obv,20))/np.maximum(R_(v,20).sum().values,1e-12)-(c-sh(c,20))/(A*5)
    F['54 حرارة السوق']=(abs(body)/A)*(A5/A50)*np.sign(body)
    F['55 التوتر السعري']=(R_(rng,10).sum().values/np.maximum(R_(h,10).max().values-R_(l,10).min().values,1e-12))*np.sign(c-sh(c,10))
    e50=EM(c,50); e100=EM(c,100); al=(np.sign(c-e20)+np.sign(e20-e50)+np.sign(e50-e100))/3
    F['57 وضوح الرؤية الاتجاهية']=al
    F['58 التحول من التذبذب للاتجاه']=(er10-sh(er10,10))*np.sign(c-sh(c,10))
    ret=np.diff(c,prepend=c[0]); ac=pd.Series(ret).rolling(20).corr(pd.Series(sh(ret))).values
    F['59 معامل التماسك']=ac*np.sign(c-sh(c,20))
    F['60 درع التقلبات المفاجئة']=-(R_(abs(ret)/A,5).max().values)*np.sign(ret)
    g4=np.arange(n)//4; cc4=pd.Series(c).groupby(g4).last().values; t4=np.sign(cc4-EM(cc4,50))[np.maximum((np.arange(n)+1)//4-1,0)]
    g16=np.arange(n)//16; cc16=pd.Series(c).groupby(g16).last().values; t16=np.sign(cc16-EM(cc16,50))[np.maximum((np.arange(n)+1)//16-1,0)]
    F['81/83 التوافق متعدد الفريمات']=(np.sign(c-e50)+t4+t16)/3
    F['82 التضارب بين الفريمات']=np.sign(body)*(np.sign(body)!=t16)
    sw=(hh20-ll20)/A; F['84 امتداد الموجة']=-(sw/R_(sw,200).mean().values-1)*np.sign(c-sh(c,20))
    F['87 نبض الجلسات']=(rng/A)*(vr)*np.sign(body)
    F['88 الفتور بعد موجة قوية']=np.where(abs(sh(c,10)-sh(c,30))>5*A,-np.sign(sh(c,10)-sh(c,30))*(1-A5/A),0)
    F['90 شدة الانعكاس المحتمل']=-(c-sh(c,3))/A*np.sign(sh(c,3)-sh(c,20))*-1
    F['92 الفجوة بين السعر والزخم']=((c-ll20)/np.maximum(hh20-ll20,1e-12)-r14/100)*-1
    F['96 سرعة التغير في الزخم']=r14-sh(r14,3)
    F['97 الحركة الممدودة أكثر من اللازم']=-(c-e50)/A
    F['98 التماسك بعد الاختراق']=np.where(sh(c,5)>sh(ph,5),(c-sh(ph,5))/A,0)+np.where(sh(c,5)<sh(pl,5),(c-sh(pl,5))/A,0)
    F['99 قوة الرفض السعري']=(dn-up)/A*(rng/A)
    return F
