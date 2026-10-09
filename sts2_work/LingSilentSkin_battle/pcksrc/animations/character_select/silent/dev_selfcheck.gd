extends Node
## dev 自检:场景就绪后把 pd_ling.atlas 实际加载的纹理页导出 PNG。
## 用途:对拍"游戏运行时加载的纹理集"与磁盘资产是否一致
## (帐篷区半透明污染排查)。产物:
##   user://dev_selfcheck/pageN_<宽>x<高>.png   (同时尽量复制到
##   D:/项目/dragonraja/render_work/dev_selfcheck/ 方便直接查看)
##   user://dev_selfcheck/report.txt            (每页来源/尺寸/写入结果)

const ATLAS_PATH := "res://animations/character_select/silent/pd_ling.atlas"
const MIRROR_DIR := "D:/项目/dragonraja/render_work/dev_selfcheck"

func _ready() -> void:
	# 仅在放置标记文件时运行(每次进场景写 4 张 2048^2 PNG 会造成可感卡顿):
	#   新建 %APPDATA%/Roaming/SlayTheSpire2/dev_selfcheck/run 即启用一次,
	#   跑完自动删除标记。
	var flag := OS.get_user_data_dir() + "/dev_selfcheck/run"
	if not FileAccess.file_exists(flag):
		return
	await get_tree().process_frame
	_run()
	DirAccess.remove_absolute(flag)

func _run() -> void:
	var lines: Array[String] = []
	var atlas = load(ATLAS_PATH)
	if atlas == null or not atlas.has_method("get_textures"):
		lines.append("FATAL: atlas load failed or no get_textures(): %s" % ATLAS_PATH)
	else:
		var dir := OS.get_user_data_dir() + "/dev_selfcheck"
		DirAccess.make_dir_recursive_absolute(dir)
		DirAccess.make_dir_recursive_absolute(MIRROR_DIR)
		var textures: Array = atlas.get_textures()
		lines.append("atlas=%s textures=%d user_dir=%s" % [ATLAS_PATH, textures.size(), OS.get_user_data_dir()])
		for i in range(textures.size()):
			var tex = textures[i]
			if tex == null:
				lines.append("page %d: NULL TEXTURE" % i)
				continue
			var img: Image = tex.get_image()
			if img == null:
				lines.append("page %d: get_image() FAILED path=%s" % [i, tex.resource_path])
				continue
			if img.is_compressed():
				img.decompress()
			var sz := img.get_size()
			var out_user := "%s/page%d_%dx%d.png" % [dir, i, sz.x, sz.y]
			var err := img.save_png(out_user)
			var mirror_note := ""
			if err == OK:
				var mirror := FileAccess.open(
					"%s/page%d_%dx%d.png" % [MIRROR_DIR, i, sz.x, sz.y], FileAccess.WRITE)
				if mirror:
					var f := FileAccess.open(out_user, FileAccess.READ)
					if f:
						mirror.store_buffer(f.get_buffer(f.get_length()))
						f.close()
					mirror.close()
					mirror_note = " mirrored"
				# alpha 摘要:最小/最大/均值,半透明污染一眼可见
				var mn := 255.0
				var mx := 0.0
				var total := 0.0
				var n := 0
				var d := img.get_data()
				var px := d.size() / 4
				for k in range(0, px, 331):
					var a := float(d[k * 4 + 3])
					mn = min(mn, a)
					mx = max(mx, a)
					total += a
					n += 1
				lines.append("page %d: %s %dx%d -> %s (err=%d)%s alpha min=%.0f max=%.0f mean=%.1f"
					% [i, tex.resource_path, sz.x, sz.y, out_user, err, mirror_note, mn, mx, total / n])
			else:
				lines.append("page %d: save_png FAILED err=%d -> %s" % [i, err, out_user])
	var f := FileAccess.open(OS.get_user_data_dir() + "/dev_selfcheck/report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	for ln in lines:
		print("[DevSelfCheck] ", ln)
