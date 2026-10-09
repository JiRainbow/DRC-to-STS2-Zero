#!/usr/bin/env python3
"""Build the character-select立绘 from the TWO DRC plotdrawing atlases.

极夜绮梦's select display spine (S_Plotdrawing_ling) references regions from
TWO atlases: its own scene/stage atlas (S_Plotdrawing_ling: curtains,
columns, candles, desk — NO character pieces) AND the character atlas
(Plotdrawing_ling: the character's face/body/dress pieces). DRC layers the
two spines as separate materials; we merge the region lists into ONE shipped
atlas file with all 5 page textures.

Output (mod _pcksrc/animations/character_select/silent/):
  pd_ling.atlas   merged: spd pages (spd_pageN.png) + pd pages (pdchar_pageN.png)
  pd_ling.json    the SPD skeleton, sanitized (see below), single animation
  spd_pageN.png / pdchar_pageN.png
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))

import build_ling_assets as bla  # noqa: E402
import numpy as np  # noqa: E402


def fix_black_bg(png_path):
    """立绘图集页的解码清理。ASTC 解码产物两类脏东西:
    1) 未写入空白块 = 半透明暗灰膜(alpha ~40-48, rgb ~35-40, r≈g≈b)——盖在
       场景上就是一层暗色蒙版/黑块;
    2) 真实软像素(辉光/羽化边)是低 alpha + 亮 rgb(196-251),彩色件暗边
       (蓝绸 rgb 37,64,75)通道极差 ~38。
    所以不能全局按 alpha 阈值清理(会灭掉 halo/lamp/snow 的软辉光),按
    「低 alpha + 通道均匀灰噪声」判膜,并让所有近透明像素 rgb 归零——
    spine-godot 的 multiply 混合对透明区按 dst*src_rgb 计算,rgb 残留会让
    每个阴影槽的整个 quad 渲染成实心黑带(黑色缺失材质的根因)。
    DRC 原生解码两者都近透明。"""
    from PIL import Image
    im = Image.open(png_path).convert('RGBA')
    arr = np.array(im)
    mx = arr[..., :3].max(axis=2)
    spread = mx - arr[..., :3].min(axis=2)
    # 膜 = 低 alpha + 通道均匀的灰噪声(r≈g≈b);蓝绸暗边(rgb 极差~38)、
    # 亮色辉光(rgb 196+)等真实软像素极差/亮度不满足,保留
    film = (arr[..., 3] < 128) & (mx < 160) & (spread < 26)
    arr[film] = 0
    # 透明像素 rgb 归零(含原生透明区残留的垃圾 rgb)
    arr[arr[..., 3] < 8] = 0
    Image.fromarray(arr).save(png_path)
    return int(film.sum())
import az_spine_extract as ase  # noqa: E402
import spine41_parse as sp  # noqa: E402
import spine42_emit as em  # noqa: E402

SPD_DIR = ROOT / 'render_work/pd_ling2/s_plotdrawing/spd_ling'
SPD_STEM = 's_plotdrawing_ling'
PD_DIR = ROOT / 'render_work/pd_ling/plotdrawing/pd_ling'
PD_STEM = 'plotdrawing_ling'
OUT = ROOT / 'sts2_work/LingSilentSkin_mod/_pcksrc/animations/character_select/silent'
OUT.mkdir(parents=True, exist_ok=True)

DROP_SLOTS = {'air', 'BGD', 'path', 'windows_1', 'windows_2', 'windows_light'}


def convert_skeleton(char_dir, stem):
    uexp = (char_dir / f'{stem}-data.uexp').read_bytes()
    skel_bytes, _ = ase.locate_spine(uexp)
    sk = sp.parse_skeleton(skel_bytes)
    assert sk['leftover'] == 0, f"parse leftover {sk['leftover']}"
    return em.emit_json(sk, anim_rename={}, extra_animations={})


def atlas_text(char_dir, stem):
    return bla.extract_atlas(char_dir / f'{stem}-atlas.uexp')


def decode_pages(char_dir, stem, atlas_text, out_dir, prefix):
    pages = re.findall(r'[\w\-.]+\.png', atlas_text)
    for i, page in enumerate(pages):
        name = page[:-4]
        tex = char_dir / 'textures' / f'{name}.uexp'
        _, w, h, fmt = bla.decode_astc_texture(tex, out_dir / f'{prefix}{i + 1}.png')
        print(f'  decoded {name} -> {prefix}{i + 1}.png ({w}x{h}, {fmt})')
    return pages


def page_chunks(text, pages, prefix):
    """Split an atlas text into per-page (header+regions) chunks with pages
    renamed to prefixN."""
    chunks = []
    for i, page in enumerate(pages):
        m = re.search(r'(^|\n)' + re.escape(page) + r'\n', text)
        start = m.end() - len(page) - 1
        nxt = [mm.start() for mm in re.finditer(r'^[\w\-.]+\.png$', text, re.M) if mm.start() > start]
        end = nxt[0] if nxt else len(text)
        chunk = text[start:end]
        chunk = chunk.replace(page + '\n', f'{prefix}{i + 1}.png\n')
        chunks.append(chunk)
    return chunks


def main():
    scene_atlas = atlas_text(SPD_DIR, SPD_STEM)
    scene_pages = re.findall(r'[\w\-.]+\.png', scene_atlas)
    # 解码即终点:decode_astc_texture 输出与龙卡运行时上传的 ASTC 解码结果
    # 逐位一致(2026-10-04 对拍 game_tex265/264),透明底原生即净,不做任何
    # 擦膜/清理处理。曾经的 fix_black_bg 擦掉的其实是运行时里真实存在的
    # 极低 alpha 软像素(a≈12-48),属于多余偏差,已删。
    for i, page in enumerate(scene_pages):
        name = page[:-4]
        bla.decode_astc_texture(SPD_DIR / 'textures' / f'{name}.uexp',
                                OUT / f'spd_page{i + 1}.png')
        print(f'  spd_page{i + 1}: raw decode (no cleanup)')
    scene_json = convert_skeleton(SPD_DIR, SPD_STEM)

    char_atlas = atlas_text(PD_DIR, PD_STEM)
    char_pages = re.findall(r'[\w\-.]+\.png', char_atlas)
    for i, page in enumerate(char_pages):
        name = page[:-4]
        bla.decode_astc_texture(PD_DIR / 'textures' / f'{name}.uexp',
                                OUT / f'pdchar_page{i + 1}.png')
        print(f'  pdchar_page{i + 1}: raw decode (no cleanup)')

    # sanitize the scene skeleton (spine-cpp compatibility + visual hygiene)
    # additive 槽修复(蓝光二分第八轮+blend_add 实测定案):spine-godot 内置
    # additive=(ONE,ONE) 预乘约定,直通 alpha 贴图下槽位/时间轴 alpha 完全
    # 不生效(雪花/光晕把整块 rgb 无视 alpha 全强度叠加=左上青蓝光斑)。
    # 修复=tscn 的 SpineSprite 挂 additive_material(additive_fix.gdshader:
    # blend_add + 直通色输出,四象限实测 out=tex.rgb*slot.rgb*(tex.a*slot.a)
    # +dst,alpha 线性生效),全部 additive 槽恢复(halo/snow×4/boom/lamp_L_G/
    # windows_light);windows_1/2 窗格、air 柔雾、BGD 空槽 normal 混合保留。
    DROP_SLOTS = {'path'}

    def is_dropped(name):
        return name in DROP_SLOTS

    scene_json.pop('path', None)
    scene_json['slots'] = [s for s in scene_json['slots'] if not is_dropped(s['name'])]
    for skin in scene_json['skins']:
        atts = skin.get('attachments', {})
        for sname in list(atts.keys()):
            if is_dropped(sname):
                del atts[sname]
            else:
                for an, att in list(atts[sname].items()):
                    if att.get('type') == 'path':
                        del atts[sname][an]
    for a in scene_json['animations'].values():
        sl = a.get('slots', {})
        for sname in list(sl.keys()):
            if is_dropped(sname):
                del sl[sname]
            elif 'rgba2' in sl[sname]:
                frames = sl[sname].pop('rgba2')
                # curve 是两色 14 对控制点,与 4 分量 rgba 不兼容,线性化丢弃
                sl[sname]['rgba'] = [
                    {'time': f['time'], 'color': f.get('light', '#ffffffff')}
                    for f in frames]
        if 'path' in a:
            del a['path']

    # --- multiply 槽保持原生 blend,由 multiply_fix.gdshader 渲染 ---
    # 曾经的 multiply->normal 黑影等价变换(区域像素 rgb=0/alpha=a*(1-rgb))
    # 已废弃:图集打包矩形存在重叠(如 desk_M_blue_1_shadow 落在 curtain
    # 矩形内),原地黑化误伤了普通槽(帐篷左沿)采样的纹素。现方案 =
    # 槽位保留 blend:'multiply',SpineSprite.multiply_material 挂
    # multiply_fix(blend_mul + 预乘输出),与 spine/UE multiply(PMA)
    # out=dst*(rgb_pma+1-a) 逐像素一致。

    # keep exactly ONE animation: the longest (the assembled showcase)
    anims = scene_json['animations']

    def max_time(o):
        m = 0
        if isinstance(o, dict):
            for k, v in o.items():
                if k == 'time' and isinstance(v, (int, float)):
                    m = max(m, v)
                else:
                    m = max(m, max_time(v))
        elif isinstance(o, list):
            for v in o:
                m = max(m, max_time(v))
        return m

    durs = {name: round(max_time(a), 2) for name, a in anims.items()}
    keep = max(anims, key=lambda n: durs[n])
    # 双动画方案:12s 循环版 -> "animation"(纯循环,无染色);2s 进场版 -> "entry"
    # (独有 209+ 槽 rgba2 全图染色,压暗->释放)。进场染色只在进入页面时播一次,
    # 由 entry_player.gd 驱动:entry(loop=false) 播完接 animation(loop=true)。
    # 曾经的"染色合并进 12s 头部"方案会让每个循环都压暗一次,已废弃。
    # (NSpineAutoPlayer 要求动画数必须为 1,已从 tscn 换成 entry_player.gd。)
    assert keep == 'animation2', f'unexpected longest animation {keep}'
    anims['entry'] = anims.pop('animation')
    anims['animation'] = anims.pop('animation2')
    names_now = list(anims.keys())
    assert set(names_now) == {'animation', 'entry'}, names_now
    print(f'animations: {names_now} (entry={durs.get("animation", 0)}s idle={durs.get("entry", 0)}s)')

    # --- 灯光/雪花稳态(已回退废弃:用户实测该版让帐篷半透明 bug 回归,
    # 2026-10-06 定案回退到 fade 版;保留代码仅作记录,默认不启用) ---
    if False:
        # idle 自带 6 条槽 rgba(halo/snow×4/windows_light):雪花恒隐、
        # windows_light/halo 按 12s 脉冲(6.33s 才亮、9s 熄灭)。双轨道下 idle
        # 一生效就覆盖 entry 保持态 → 2s 处蓝光骤灭(帐篷半透明 bug 观感回归)、
        # 蓝光迟到+亮暗循环。DRC 时装屏稳态 = 蓝光常亮、雪花常驻。处置:
        #   1) idle 剥掉全部 6 条 rgba(只留骨骼动画);
        #   2) entry 增补 windows_light 常亮(alpha 0.11=其点亮值)——track 0
        #      保持末帧 → 永久生效;
        #   3) entry 的 snow 闪绽(0.27s 全亮→0.33s 消隐)去掉消隐键 → 绽放后
        #      常驻左上区;snow_back 保留 1s 内淡出(柔光背板)。
        idle_anim = anims['animation']
        idle_slots = idle_anim.setdefault('slots', {})
        for sname in ('halo', 'snow', 'snow_back', 'snow_ball', 'snow_ball2', 'windows_light'):
            idle_slots.pop(sname, None)
        entry_anim = anims['entry']
        entry_slots = entry_anim.setdefault('slots', {})
        entry_slots.setdefault('windows_light', {})['rgba'] = [
            {'time': 0, 'color': 'ffffff1d'}]
        snow_tl = entry_slots.get('snow', {}).get('rgba')
        if snow_tl:
            entry_slots['snow']['rgba'] = [f for f in snow_tl if f['time'] < 0.3]
        print('lights/snow steady-state applied')

    # --- 雪花入场节奏(用户定案):淡入 -> 短保持 -> 淡出,峰值砍半 ---
    # 原始数据是 0.267s 直接全亮(峰值1.0)后 0.33s 即消隐的"闪现";改为
    # 线性淡入至 0.5 峰值,短保持后淡出。
    _e = anims['entry'].setdefault('slots', {}).setdefault('snow', {})
    _e['rgba'] = [
        {'time': 0, 'color': 'ffffff00'},
        {'time': 0.267, 'color': 'ffffff80'},
        {'time': 0.6, 'color': 'ffffff80'},
        {'time': 1.1, 'color': 'ffffff00'},
    ]
    print('snow entry timeline reshaped (fade-in, peak 0.5)')

    # --- 衔接对齐(用户实测:左臂错位+硬切+衔接亮度不一致) ---
    # 全量比对证明:entry 末值与 animation 首值在所有共享骨骼通道上逐值
    # 相等(0 处 mismatch,作者按无缝衔接设计);错位全部来自 entry 独有
    # 内容——12 条独有骨骼轨道(xiaobi_L 左前臂 rotate 11.11°、datui_L/R
    # 大腿、lamp/lamp2-4、boom)加 4 条共享骨骼上的独有 rotate 通道
    # (dabi_L/R、xiaotui_L/R),这些在切到 idle 的瞬间弹回 setup pose。
    # 处置:entry 骨骼与 idle 取交集、通道级对齐,entry 全程保持 idle
    # 姿态(共享骨骼本身仍按 entry 关键帧运动)。雪花链(snow_*)豁免:
    # 1.1s 后已全透明,切点弹回不可见,且绽开动画需要这些骨骼。
    # 染色槽 1.1s 前已释放到 ffffffff,衔接点无颜色突变;残余差异
    # (idle 独有的 eye/halo/zui 等)由 entry_player 对 idle 入场
    # set_mix_duration 平滑。
    idle_bones = anims['animation'].setdefault('bones', {})
    entry_bones = anims['entry'].setdefault('bones', {})
    _stripped = []
    for _b in [_b for _b in entry_bones if _b not in idle_bones and not _b.startswith('snow')]:
        del entry_bones[_b]
        _stripped.append(_b)
    for _b, _tl in entry_bones.items():
        if _b in idle_bones:
            for _ch in [_ch for _ch in _tl if _ch not in idle_bones[_b]]:
                del _tl[_ch]
                _stripped.append(f'{_b}.{_ch}')
    print(f'entry bones aligned to idle: stripped {_stripped}')

    # --- 衔接对齐第二段:idle 独有骨骼钉到 idle@0(单帧跳变主凶) ---
    # 本地逐帧帧差实测(repro_stage cut_probe):即使做了上一段对齐+mix,
    # 硬切仍有单帧尖峰(全屏均值 0.0307,灯柱足迹只占 0.0039)——大头是
    # idle 独有骨骼(eye_L/R、eyelash_L/R、meimao_R、halo、windows_light、
    # zui)的骨骼 setup 值与 idle@0 值差异巨大(eye_L.translate setup
    # (179,166) vs idle@0 (0,0)),entry 期间停在 setup,切点瞬间弹到
    # idle@0;mix 只能把它摊成"五官滑动 0.25s",依然可见。处置:entry
    # 补写这些通道的恒定关键帧(值=idle@0),entry 全程即 idle 起始姿态,
    # 切点两侧逐像素一致,任何 mix 语义下都无缝。
    _pinned = []
    for _b, _tl in idle_bones.items():
        if _b in entry_bones:
            continue
        _new_tl = {}
        for _ch, _keys in _tl.items():
            _k0 = dict(_keys[0])
            _k0['time'] = 0
            _k0.pop('curve', None)
            _new_tl[_ch] = [_k0]
        entry_bones[_b] = _new_tl
        _pinned.append(_b)
    print(f'entry bones pinned to idle@0: {_pinned}')

    # --- lamp_L_G 尾部淡出(单帧跳变次凶) ---
    # additive 光柱(610x1628)在 entry 末保持 11111fff(微弱蓝光加法),
    # idle/setup 全隐(ffffff00)→ 切点整块消失。处置:末键延到 2.0s 的
    # setup 色,1.0s→2.0s 线性衰减,切点两侧全隐。
    _lg = anims['entry'].setdefault('slots', {}).setdefault('lamp_L_G', {}).get('rgba')
    if _lg and _lg[-1]['time'] < 2.0:
        _lg_setup = 'ffffffff'
        for _s in scene_json.get('slots', []):
            if _s.get('name') == 'lamp_L_G':
                _lg_setup = _s.get('color', 'ffffffff')
                break
        _lg.append({'time': 2.0, 'color': _lg_setup})
        print(f'lamp_L_G tail fade appended (1.0->2.0 to setup {_lg_setup})')

    # merged atlas = scene page chunks + character page chunks
    scene_chunks = page_chunks(scene_atlas, scene_pages, 'spd_page')
    char_chunks = page_chunks(char_atlas, char_pages, 'pdchar_page')
    merged = ''.join(scene_chunks) + ''.join(char_chunks)
    (OUT / 'pd_ling.atlas').write_text(merged, encoding='utf-8', newline='')

    # spine-cpp 的时间轴颜色解析疑似不接受 '#' 前缀(spine-ts 宽容,
    # hash 版在游戏里时间轴 alpha 不生效);输出无 # 变体为正式版,
    # hash 版留档对照。
    def strip_hash(o):
        if isinstance(o, dict):
            return {k: (v[1:] if isinstance(v, str) and v.startswith('#')
                        and len(v) in (7, 9) else strip_hash(v)) for k, v in o.items()}
        if isinstance(o, list):
            return [strip_hash(v) for v in o]
        return o

    (OUT / 'pd_ling.json').write_text(
        json.dumps(strip_hash(scene_json), ensure_ascii=False, separators=(',', ':')),
        encoding='utf-8')
    (OUT / 'pd_ling_hashcolors.json.bak').write_text(
        json.dumps(scene_json, ensure_ascii=False, separators=(',', ':')),
        encoding='utf-8')
    print('merged atlas written; scene pages:', len(scene_pages), 'char pages:', len(char_pages))


if __name__ == '__main__':
    main()
