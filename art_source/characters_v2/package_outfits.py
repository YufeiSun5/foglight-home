"""Package image_gen art into runtime atlases, with technical palette masks.
No drawing or synthesis. Pillow reads alpha geometry; ImageMagick performs only
crop, nearest resampling, registration, packing, and deterministic mask extraction.
"""
from PIL import Image
from pathlib import Path
import subprocess,json,shutil,hashlib
ROOT=Path(__file__).resolve().parents[2];ART=ROOT/'art_source/characters_v2';OUT=ROOT/'assets/characters_v2/cen_xingyao/outfits';GEN=ROOT.parent/'generated_images'
SOURCES={
 'trousers':{'down':ART/'trousers_walk_down_source.png','right':ART/'xingyao_walk_right_source.png','up':ART/'trousers_walk_up_source.png','idle':ART/'trousers_idle_source.png'},
 'culottes':{'down':GEN/'exec-12eb20fb-78e7-416f-9e3a-48da66749980.png','right':ART/'culottes_right_source.png','up':GEN/'exec-30ac006f-c667-43d7-82f7-8ab5dd1c266f.png','idle':GEN/'exec-6def2b82-e843-4c51-97d4-7bacacfb9091.png'}
,
 'long_skirt':{'down':GEN/'exec-f26d925d-f079-4eea-a3fd-1169b65cc714.png','right':GEN/'exec-cf66d233-87c4-4700-8c80-5b26d52ad38c.png','up':GEN/'exec-d5e49de8-3f4f-443e-ba2e-0708322cf908.png','idle':GEN/'exec-f39c5f1b-b203-4aad-a606-75be1c741538.png'},
 'short_skirt':{'down':GEN/'exec-6012b0dc-4010-417e-b58c-3ae935fd2934.png','right':GEN/'exec-9e99a86e-07aa-421f-843b-0c27e7dc22f1.png','up':GEN/'exec-680210b0-cdd1-4571-937f-0eca84e3bd16.png','idle':GEN/'exec-2f293dfa-a3dd-4069-a045-170b562714e5.png'}
}
def run(cmd):subprocess.run(['magick']+[str(x) for x in cmd],check=True)
def extract(src,dst,kind,records):
 im=Image.open(src);cols,rows=(2,4) if kind=='idle' else (3,2)
 for index in range(cols*rows):
  row,col=divmod(index,cols);rect=(round(col*im.width/cols),round(row*im.height/rows),round((col+1)*im.width/cols),round((row+1)*im.height/rows))
  cell=im.crop(rect);a=cell.getchannel('A');b=a.point(lambda x:255 if x>100 else 0).getbbox()
  if b is None:raise ValueError((src,index,'empty'))
  x,y=rect[0]+b[0],rect[1]+b[1];w,h=b[2]-b[0],b[3]-b[1]
  sx=sy=0
  for yy in range(b[1],b[1]+round(h*.43)):
   for xx in range(b[0],b[2]):
    aa=a.getpixel((xx,yy))
    if aa>100:sx+=xx*aa;sy+=aa
  head_x=sx/sy-b[0];scale=64/h;ox=round(40-head_x*scale);oy=12
  temp=dst/f'.{kind}_{index}.tmp.png';frame=dst/f'{kind}_{index:02d}.png'
  run([src,'-crop',f'{w}x{h}+{x}+{y}','+repage','-filter','point','-resize','x64',temp])
  run(['-size','80x80','xc:none',temp,'-geometry',f'+{ox}+{oy}','-composite',frame]);temp.unlink()
  records.append({'kind':kind,'frame':index,'source_rect':[x,y,w,h],'destination':[ox,oy],'head_registration':round(head_x,4)})
 if kind=='idle':
  rowfiles=[]
  for row in range(4):
   rp=dst/f'.idle_row{row}.png';run([dst/f'idle_{row*2:02d}.png',dst/f'idle_{row*2+1:02d}.png','+append',rp]);rowfiles.append(rp)
  run([*rowfiles,'-append',dst/'idle.png'])
  for p in rowfiles:p.unlink()
 else:run([*[dst/f'{kind}_{i:02d}.png' for i in range(6)],'+append',dst/f'{kind}.png'])
 # Pixels are in approved image's blue-cloth gamut and torso region only.
 # Excludes warm skin/gold/hair and indigo lower garments; binary mask has true alpha.
 source=dst/f'{kind}.png';mask=dst/f'{kind}_topmask.png'
 lower='(floor(j/80)==3?47:41)' if kind=='idle' else ('47' if kind=='walk_up' else '41')
 expr=f'(a>0.39 && mod(j,80)>={lower} && mod(j,80)<=57 && (mod(j,80)<=52 || (g>0.28 && b>0.42 && (g-r)/(b-r+0.00001)>0.22)) && b>r+0.045 && g>r+0.015 && b>g-0.015 && (b-r)/max(b,0.001)>0.17 && (g-r)/(b-r+0.00001)>0.15 && (g-r)/(b-r+0.00001)<0.91) ? 1 : 0'
 run([source,'-alpha','on','-channel','RGBA','-fx',expr,'-define','png:color-type=6',mask])
 # Source frame files useful for checking; atlasses are runtime entry points.

def build(bottom):
 dst=OUT/bottom;dst.mkdir(parents=True,exist_ok=True);records=[]
 for d,source in SOURCES[bottom].items():
  target=ART/f'{bottom}_{d}_source.png'
  if source.resolve()!=target.resolve():shutil.copy2(source,target)
  extract(target,dst,'idle' if d=='idle' else f'walk_{d}',records)
 (ART/f'{bottom}_packaging.json').write_text(json.dumps(records,indent=2)+'\n')
 # Review all three walks at native64px height and then4x for visual inspection.
 run([dst/'walk_down.png',dst/'walk_right.png',dst/'walk_up.png','-append','-filter','point','-resize','400%','-background','#263744','-alpha','remove',ART/f'{bottom}_walk_review_4x.png'])
 run([dst/'idle.png','-filter','point','-resize','400%','-background','#263744','-alpha','remove',ART/f'{bottom}_idle_review_4x.png'])
 manifest={'version':2,'bottom_id':bottom,'frame_size':[80,80],'effective_height':64,'foot_anchor':[40,75],'walk':{'directions':['down','right','up'],'size':[480,80],'frames':6,'fps':8,'left':'Use walk_right plus horizontal flip. This mirrors asymmetric satchel and hair ornament; first-version limitation.'},'idle':{'size':[160,320],'columns':2,'rows':['down','left','right','up'],'column_states':['neutral/open','blink/local relaxation'],'durations_seconds':[2.6,.12],'up_note':'Localized fingers/shoulders, no visible eye blink from behind.'},'mask':'Each atlas has identical-size _topmask.png; only blue upper cloth pixels selected. No global hue change.','creator':'AI-original image_gen artwork,2026-10-06','license':'No open-source license added or implied.'}
 (dst/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 print('Packaged',bottom)
if __name__=='__main__':
 import sys
 for b in sys.argv[1:] or list(SOURCES):build(b)
