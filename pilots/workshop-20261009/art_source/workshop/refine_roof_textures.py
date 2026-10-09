from PIL import Image
import numpy as np, os
D=os.path.join(os.path.dirname(__file__),'textures')
a=np.asarray(Image.open(D+'/teal_patina_basecolor.png')).astype(float)/255
l=(a*np.array([.2126,.7152,.0722])).sum(axis=-1,keepdims=True)
b=(a*.65+l*.35)*np.array([.95,.81,.74]);b=np.clip(b,0,1)
Image.fromarray(np.uint8(b*255)).save(D+'/teal_refined_basecolor.png')
r=np.asarray(Image.open(D+'/teal_patina_roughness.png')).astype(float)/255
Image.fromarray(np.uint8(np.clip(r+.14,0,1)*255)).save(D+'/teal_refined_roughness.png')
Image.open(D+'/teal_patina_normal.png').save(D+'/teal_refined_normal.png')
