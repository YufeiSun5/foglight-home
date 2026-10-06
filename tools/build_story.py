"""Author-reviewed CH01 dialogue data. Rebuild with Python stdlib only."""
import json
from pathlib import Path
nodes = {}
def chain(prefix, lines, end='', effect=None):
    for i, row in enumerate(lines, 1):
        who, text, *mood = row
        nodes[f'{prefix}{i}'] = {'speaker':who,'text':text,'expression':mood[0] if mood else 'calm','next':f'{prefix}{i+1}' if i < len(lines) else end}
    if effect: nodes[f'{prefix}{len(lines)}']['effect'] = effect
def choices(node, rows):
    nodes[node]['choices'] = [{'id':f'{node}.{key}','text':text,'next':next_id} for key,text,next_id in rows]

chain('g', [
 ('star','确认已经拿到了。东西也领到了。可一听见家里的声音，我又想把它们藏到最下面。','hurt'),
 ('star','母亲的信压在图袋里：“先别开始，回来再说。家里还盼着以后。”'),
 ('star','今晚，我先把那封信收好。我的名字，不用再藏到最下面。'),
 ('star','要招绘图的人……名字写在这儿。岑星遥。'),
 ('star','两次正常钟声之后，第三声错位。又是刚才那艘船……'),
 ('star','不是潮在绕，是灯把船引回来了。去引灯台看看吧。')
], effect={'stage':'meet'})
chain('m', [
 ('shen','别碰左边的栏杆，它比我还不可靠。','smile'),
 ('star','那你怎么站在旁边？','wary'),
 ('shen','它至少还肯替我挡风。你听见钟声了吗？'),
 ('star','第三声早了。把灯转回来半格，先别动底座。'),
 ('shen','好。听你的。你叫什么？')
])
choices('m5', [('name','岑星遥。你可以叫我星遥。','ma1'),('work','先救船，名字等会儿说。','mb1'),('careful','我没修过这东西。你别因为我说得像就全信。','mc1')])
chain('ma',[('shen','星遥，我是沈砚舟。今晚借一下你的耳朵。','smile')], 'm6')
chain('mb',[('shen','好。等他们靠岸，我再好好问。')], 'm6')
chain('mc',[('shen','那我们一起核对。你听，我看灯影。')], 'm6')
nodes['m6'] = {'speaker':'shen','text':'前面是灯盘。只碰有木柄的那块；其余的，我们一起来。','expression':'calm','next':'','effect':{'stage':'repair'}}
chain('r', [
 ('star','先长，再短……最后一段被盖住了。这里有块灯片装反了。'),
 ('shen','我稳住外圈。你只碰有木柄的那块。'),
 ('xu','停。先别转最里面那一层。','wary'),
 ('xu','它在空转。你们越用力，船会越觉得岸在另一边。'),
 ('shen','知微，来得正好。','smile'),
 ('qi','你每次说这句，通常都说明事情不太好。她是谁？','wary'),
 ('star','在下面听见灯不对的人。'),
 ('qi','听见就敢上来？','wary'),
 ('star','下面没有人回应。'),
 ('xu','这句够了。姑娘，把木柄往你那边压住。名字等灯亮了再吵。','smile'),
 ('narrator','知微卡住齿轮，星遥握住木柄，砚舟拉稳外圈，祁岚系紧支柱上的绳索。四个人各守住一处。'),
 ('star','现在。第一声……第二声……松一点。'),
 ('shen','看见岸了。','smile'),
 ('narrator','灯光连成一束。远处船鸣两声，船影进入港湾。潮声恢复稳定。'),
 ('xu','不错。你听见的是齿轮之间那点空隙。','smile'),
 ('star','我以为你会让我下去。','hurt'),
 ('xu','你做对了，为什么要下去？'),
 ('qi','也不能因为一盏灯，就把整条船都交出去。','wary'),
 ('shen','没人说要交船。先请她喝一杯热的。','smile'),
 ('narrator','星遥松开僵硬的手，接过砚舟递来的干布。知微听了听齿轮；祁岚转头望向港湾。船舱的灯已经亮了。')
], effect={'stage':'cabin'})
nodes['r13']['effect'] = {'flag':'relit'}
chain('c', [
 ('narrator','船舱里，砚舟先把干布盖住知微的工具，再把热茶推给祁岚，最后在星遥面前放一只空杯。'),
 ('shen','都是热的。岚，今天没放你不喜欢的那种叶子。','smile'),
 ('xu','我的备用衣服。要吗？袖子应该不碍你画图。'),
 ('star','我穿成这样也可以？','wary'),
 ('xu','哪样？衣服是给你穿的。你自己喜欢就可以。','smile')
])
choices('c5',[('accept','想收下，但我自己挑颜色和款式。','ca1'),('later','先放在衣柜里吧。今天这套就很舒服。','cb1'),('decline','谢谢。我暂时不想换衣服。','cc1')])
chain('ca',[('xu','当然。衣柜里那些都能直接拿，你想看时再看。','smile')], 'c6')
chain('cb',[('xu','好。不用急着决定，也不用为了谢我穿上它。')], 'c6')
chain('cc',[('xu','好，那先收起来。热茶仍是你的。','smile')], 'c6')
chain('cx',[], '')
for i,(who,text,mood) in enumerate([
 ('narrator','知微将衣服搭在空椅上，退开。星遥摸了一下衣角。祁岚的脸色变冷。','calm'),
 ('qi','你倒总知道别人该用什么。','angry'),
 ('xu','我问了她。','wary'),
 ('shen','先喝茶，冷了就——','wary'),
 ('qi','又喝茶。','hurt'),
 ('narrator','他没能用体贴消除旧事。星遥看向椅子，暂不追问。','calm'),
 ('shen','我们还要去沉钟岛找旧图。愿意做同行绘图师吗？报酬按份额算。先说清楚，知微和祁岚都是我的妻子。','calm'),
 ('xu','你先只考虑工作。','calm')
], 6): nodes[f'c{i}']={'speaker':who,'text':text,'expression':mood,'next':f'c{i+1}'}
choices('c13',[('time','我想试试，但可能需要一点适应的时间。','ct1'),('terms','把报酬和轮值写下来，我再上船。','cu1'),('private','有些自己的事，我暂时不想解释。','cv1')])
chain('ct',[('xu','可以。衣服也不用急着还。')],'c14')
chain('cu',[('qi','这个要求合理。纸给我。')],'c14')
chain('cv',[('shen','那就先不解释。工作需要的，我们一件件问。')],'c14')
nodes['c14']={'speaker':'star','text':'请写岑星遥。星星的星，遥远的遥。','expression':'smile','next':'c15'}
nodes['c15']={'speaker':'narrator','text':'知微把纸转过来供她确认；祁岚拿走压在折椅上的救援带，星遥坐下。窗外雾色淡了一点。出发前，还可以在港里走走。','expression':'calm','next':'','effect':{'stage':'depart'}}
chain('d',[
 ('narrator','近黎明的船边，星遥看着自己的名字，把那封家书与确认单分开收好。'),
 ('shen','出发前都还可以改主意。'),
 ('star','你希望我来吗？'),
 ('shen','希望。但别为了让我高兴就答应。','smile'),
 ('star','今晚这件衣服，很暖。','smile'),
 ('narrator','他笑了一下，挂好备用灯后退开。星遥自己提灯。四道窗光落在水面。'),
 ('star','雾还在前面。但我的名字，已经写下了。','smile'),
 ('narrator','第一章结束 · 雾港没有出口\n今夜只约定同行。数月里的变化、旧怨和四人的未来，会在后续章节慢慢展开。')
], effect={'stage':'complete','flag':'CH01_COMPLETE'})
chain('mirror',[
 ('star','这层里料好软。以前只顾着它耐不耐磨。'),
 ('star','好像真的是我。可刚才，我差一点又把衣襟拢紧了。','hurt'),
 ('xu','想留就留。大衣也可以一起穿着。今天更喜欢工裤，也很好。','smile')
])
choices('mirror3',[('alone','想独自照会儿镜子。','mirror_alone1'),('stay','请知微留下，陪我看一会儿。','mirror_stay1'),('back','今天先穿更熟悉的那套。','mirror_back1')])
chain('mirror_alone',[('xu','当然。我在门外，需要时再叫我。')])
chain('mirror_stay',[('xu','好。你自己慢慢看，不用给我一个确定的答案。')])
chain('mirror_back',[('xu','好。喜欢也可以有变化。你不欠我一句“我现在一定很喜欢”。')])
for who,text in [('shen','风快停了。今晚你听见了我们都忽略的声音。谢谢。'),('xu','我的工具可以借你看。衣柜里的衣服，也由你自己挑。'),('qi','前面的木板有点滑。我提醒过你了……慢一点。'),('board','雾港招募绘图师。报酬和轮值当面议定。旁边留着你亲手写下的名字。'),('bag','认可与配给确认，已经在图袋里。家人的反对不是你的名字，也不是今晚全部的生活。')]:
    nodes['talk_'+who]={'speaker':who if who in ['shen','xu','qi'] else 'star','text':text,'expression':'calm','next':''}

Path('content/chapter01.json').write_text(json.dumps(nodes,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'{len(nodes)} dialogue nodes authored')
