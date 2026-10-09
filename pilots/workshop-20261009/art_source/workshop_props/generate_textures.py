"""Original authored procedural timber and forged-metal PBR maps, no external imagery."""
from PIL import Image, ImageFilter
from pathlib import Path
import numpy as np
P=Path(__file__).parent/'textures'; P.mkdir(exist_ok=True)
rng=np.random.default_rng(23094)
N=1024; yy,xx=np.mgrid[0:N,0:N]/N

def noise(n,blur=0):
    a=Image.fromarray(np.uint8(rng.random((n,n))*255)).resize((N,N),Image.Resampling.BICUBIC)
    if blur: a=a.filter(ImageFilter.GaussianBlur(blur))
    v=np.array(a,dtype=float)/255
    return v-v.mean()

def rgb(name,base,value):
    a=np.clip(np.array(base)[None,None,:]+value[:,:,None],0,255).astype('uint8')
    Image.fromarray(a).save(P/(name+'.png'))

def scalar(name,a):Image.fromarray(np.uint8(np.clip(a,0,1)*255)).save(P/(name+'.png'))
def normal(name,h,amount):
    dy,dx=np.gradient(h)
    a=np.stack((-dx*amount,-dy*amount,np.ones_like(h)),axis=-1);a/=np.linalg.norm(a,axis=-1)[:,:,None]
    Image.fromarray(np.uint8((a*.5+.5)*255)).save(P/(name+'.png'))
# Longitudinal grain, broad annual-ring bands, occasional gentle knots, restrained patina.
warp=.007*np.sin(xx*11)+.004*np.sin(xx*23+yy*17)+noise(7)*.016
v=yy+warp
gr=np.sin(v*350+3*np.sin(v*24)); narrow=np.maximum(0,np.sin(v*1200+np.sin(xx*8)))**12
wo=noise(24)*8+noise(120)*2+gr*3.4-narrow*5
for kx,ky in [(.19,.24),(.66,.76),(.82,.43)]:
    rad=np.sqrt(((xx-kx)/.15)**2+((yy-ky)/.033)**2)
    wo+=np.sin(rad*21)*np.exp(-rad*2)*4.0
rgb('wood_oak_color',(146,109,62),wo)
rgb('wood_old_color',(111,82,49),wo*.8)
rgb('wood_olive_color',(95,107,59),wo*.65)
scalar('wood_roughness',.69+wo/200)
normal('wood_normal',gr*.2-narrow*.35+noise(90)*.25,3)
# Forged iron is readable blue-gray with broad scale and fine peening, not black dirt.
me=noise(10)*13+noise(48)*6+noise(260)*3
rgb('metal_iron_color',(74,84,83),me)
rgb('metal_edge_color',(121,132,126),me*.65)
rgb('metal_brass_color',(153,118,59),me*.5)
scalar('metal_roughness',.43+noise(36)*.16+noise(210)*.06)
normal('metal_normal',noise(140),1.4)
