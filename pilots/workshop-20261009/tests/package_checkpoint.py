from pathlib import Path
import hashlib,json,zipfile,argparse
ap=argparse.ArgumentParser();ap.add_argument('--label',default='M2');ap.add_argument('--kind',default='all',choices=['all','source']);a=ap.parse_args()
root=Path(__file__).resolve().parents[1]
outroot=Path('/workspace/scratch/b756fd48b088');reports=[]
def archive(kind,selected):
 out=outroot/f'Foglight-Workshop-Pilot-{kind}-{a.label}-20261009.zip'
 if out.exists():raise SystemExit(f'Refusing to overwrite existing checkpoint: {out}')
 manifest={str(r):{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p,r in selected}
 with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,9) as z:
  for p,r in selected:z.write(p,'foglight-town-pilot-20261009/'+str(r))
  z.writestr('CHECKPOINT_MANIFEST.json',json.dumps(manifest,indent=2))
 with zipfile.ZipFile(out) as z:
  assert z.testzip() is None
  for r,v in manifest.items():assert hashlib.sha256(z.read('foglight-town-pilot-20261009/'+r)).hexdigest()==v['sha256']
 report={'path':str(out),'bytes':out.stat().st_size,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'files':len(selected),'crc':'pass','per_file_sha256':'pass','kind':kind}
 Path(str(out)+'.json').write_text(json.dumps(report,indent=2));reports.append(report)
source=[]
for p in root.rglob('*'):
 if not p.is_file():continue
 rel=p.relative_to(root)
 if any(x in {'.godot','.qa','archive','candidates','__pycache__','failed','cache','config','data'} or x.startswith('failed_') for x in rel.parts):continue
 if p.suffix in {'.blend1','.glb','.log','.import','.pyc'}:continue
 if p.suffix=='.blend' and p.name!='workshop_multiview_control.blend':continue
 if rel.parts[:2] in [('assets','workshop'),('assets','workshop_props')] and p.suffix=='.png':continue
 if rel.parts[:2]==('art_source','diagnostics') and (p.suffix not in {'.gd','.py','.md','.json','.txt'} or p.stat().st_size>500000):continue
 if p.name in {'workwall_props.blend1'}:continue
 if 'preview' in p.name or p.name in {'props_overview.png','flywheel_detail.png'}:continue
 if p.suffix=='.scn':continue
 source.append((p,rel))
archive('Source',source)
paths=['project.godot','run-pilot.sh','docs/REPRODUCE.md','AI_BOARD.md','assets/workshop/foglight_workshop_refined3_runtime.glb','assets/workshop/MATERIAL_CONTRACT.md','assets/workshop_props/workshop_props.glb','assets/workshop_props/workwall_props.glb','art_source/workshop_props/README.md','art_source/workshop_props/WORKWALL.md']
paths+=[str(p.relative_to(root)) for d in ['src','assets/character'] for p in (root/d).glob('*') if p.is_file() and p.suffix!='.import']
if a.kind=='all':archive('Runtime',[(root/p,Path(p)) for p in paths])
print(json.dumps(reports,indent=2))
