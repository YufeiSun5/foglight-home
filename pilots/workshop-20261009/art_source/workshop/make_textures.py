from PIL import Image, ImageFilter
import numpy as np, os
D=os.path.join(os.path.dirname(__file__),'textures'); os.makedirs(D,exist_ok=True)
rng=np.random.default_rng(1291); N=1024
y,x=np.mgrid[0:N,0:N]/N

def noise(sx,sy):
 a=Image.fromarray((rng.random((sy,sx))*255).astype('uint8')).resize((N,N),Image.Resampling.BICUBIC)
 return np.asarray(a).astype(float)/255-.5

def write(name,base,height,rough=.7,amp=.6):
 b=np.clip(base,0,1); Image.fromarray((b*255).astype('uint8'),'RGB').save(D+'/'+name+'_basecolor.png')
 rr=np.clip(rough+height*.16,0,1); Image.fromarray((rr*255).astype('uint8'),'L').save(D+'/'+name+'_roughness.png')
 gy,gx=np.gradient(height); nr=np.stack([-gx*N*amp,-gy*N*amp,np.ones_like(gx)],-1); nr/=np.linalg.norm(nr,axis=-1)[...,None]
 Image.fromarray(((nr*.5+.5)*255).astype('uint8'),'RGB').save(D+'/'+name+'_normal.png')

# Original seamless directional grain. Two metres vertically and half a metre across.
w=noise(24,6)*.22+noise(110,16)*.12+noise(340,25)*.05
warp=noise(8,4)*.07
fib=np.sin((x+warp)*280+np.sin(y*10)*1.8)*.05
pores=noise(700,50)*.08
h=w+fib+pores
base=np.zeros((N,N,3))+[.29,.185,.085]; base+=h[...,None]*[.44,.32,.17]
write('aged_oak',base,h,.76,.10)
# Patinated teal sheet: long brushed streaks, stains and fine hammered response.
h=noise(40,8)*.28+noise(250,45)*.035+noise(512,512)*.018
streak=noise(180,8)*.065
base=np.zeros((N,N,3))+[.125,.395,.425]; base+=(h+streak)[...,None]*[.30,.42,.39]
write('teal_patina',base,h,.58,.04)
# Warm lime plaster: chalk clouding, pitted but restrained.
h=noise(5,5)*.36+noise(40,40)*.12+noise(350,350)*.05
base=np.zeros((N,N,3))+[.64,.59,.455];base+=h[...,None]*[.36,.35,.31]
write('lime_plaster',base,h,.89,.06)
# Chalk sandstone used on individually modelled chimney blocks.
h=noise(10,10)*.2+noise(60,60)*.12+noise(400,400)*.045
base=np.zeros((N,N,3))+[.48,.48,.405];base+=h[...,None]*[.44,.43,.39]
write('limestone',base,h,.9,.08)
# Handwoven unbleached linen with subtle fibres; mesh provides drape.
f=(np.sin(x*2*np.pi*260)+np.sin(y*2*np.pi*256))*.012
h=noise(12,12)*.10+noise(350,350)*.02+f
base=np.zeros((N,N,3))+[.78,.695,.50];base+=h[...,None]*.40
write('linen',base,h,.93,.02)
print(D)
