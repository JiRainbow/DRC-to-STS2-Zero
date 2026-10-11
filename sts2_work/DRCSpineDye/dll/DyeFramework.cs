using System;
using System.Collections.Generic;
using Godot;
using MegaCrit.Sts2.Core.Combat;
using MegaCrit.Sts2.Core.Entities.Creatures;
using MegaCrit.Sts2.Core.Modding;
using MegaCrit.Sts2.Core.Rooms;

namespace DRCSpineDye;

/// <summary>
/// DRCSpineDye framework.
///
/// Flow: self-mount the profile pck -> sweep the SceneTree for SpineSprites
/// (NodeAdded + a ProcessFrame retry pump, because skeleton data arrives
/// after tree entry) -> probe res://drc_dye/profiles/&lt;dir-suffix&gt;/config.json
/// down the skeleton path (SkinChanger's res://sts2_skin_runtime/... virtual
/// remount survives this) -> load the four blend-mode ShaderMaterials from
/// the config -> set normal/additive/multiply/screen_material. spine-godot
/// queries these per slot batch, so attaching is immediately effective.
///
/// Lighting (v2): config.shader_parameters flows straight into the four
/// materials' uniforms (ambient/point light/fog/darken/flash, all neutral by
/// default - iguf record 12.7/12.9).
///
/// Shadow (v2): a soft blob Sprite2D drawn behind the SpineSprite (the mobile
/// projects the character render target onto the ground - battlefield.lua
/// RTShadow manager; the blob is the STS2-side approximation).
///
/// Death (v2): on the configured death animation (mobile fightunitfighter.lua
/// 1518-1565: swap to MySpineLitDissolutionMaterial, Rongjie 1.2 -> 0 over
/// DieDuration=0.5 s) swap normal_material for the dissolve material, tween
/// its dissolve uniform, burst a one-shot particle emitter (fx_die
/// approximation), then restore.
/// </summary>
[ModInitializer("Initialize")]
public static class DyeFramework
{
    private static bool _inited;
    // tree-root handle: probe timers must survive the character being pulled
    // out of the scene (the game frees/removes the player visual shortly
    // after death - timers parented under it silently stop)
    internal static SceneTree? Tree;

    internal static void Log(string msg) => GD.Print($"[{Time.GetTicksMsec()}ms] [DRCSpineDye] {msg}");

    public static void Initialize()
    {
        if (_inited) return;
        _inited = true;
        try
        {
            SelfMountProfiles();
            if (Engine.GetMainLoop() is not SceneTree tree)
            {
                GD.PrintErr("[DRCSpineDye] main loop is not a SceneTree");
                return;
            }
            Tree = tree;
            tree.NodeAdded += OnNodeAdded;
            tree.ProcessFrame += OnProcessFrame;
            var found = new List<string>();
            Sweep(tree.Root, found);
            GD.Print($"[DRCSpineDye] installed; pre-existing SpineSprites: [{string.Join(", ", found)}]");
            // resource self-test: stepwise loads of everything we ship, one
            // line before AND after each - a native crash during a load leaves
            // the last "st ok" line as the culprit's name
            var st = new Timer { WaitTime = 3.0, OneShot = true, Autostart = true };
            tree.Root.AddChild(st);
            st.Timeout += () =>
            {
                string[] paths =
                {
                    "res://animations/character_select/silent/characterselect_silent_skel_data.tres",
                    "res://animations/character_select/silent/pd_ling.atlas",
                    "res://animations/character_select/silent/pd_ling.json",
                    "res://animations/character_select/silent/pd_ling_page1.png",
                    "res://animations/character_select/silent/pd_ling_page2.png",
                    "res://animations/character_select/silent/character_select_silent_bg.png",
                    "res://images/packed/character_select/char_select_silent.png",
                    "res://images/ui/top_panel/character_icon_silent.png",
                    "res://animations/rest_site/silent/rest_site_silent_skel_data.tres",
                    "res://animations/merchant/silent/silent_merchant_skel_data.tres",
                    "res://scenes/rest_site/characters/silent_rest_site.tscn",
                };
                foreach (var p in paths)
                {
                    GD.Print($"[DRCSpineDye] selftest loading {p}");
                    try
                    {
                        var res = ResourceLoader.Load(p);
                        GD.Print($"[DRCSpineDye] selftest ok: {p} -> {(res == null ? "NULL" : res.GetClass())}");
                    }
                    catch (System.Exception ex)
                    {
                        GD.Print($"[DRCSpineDye] selftest EXC: {p} -> {ex.Message}");
                    }
                }
            };
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] initialize failed: " + e);
        }
    }

    private static void SelfMountProfiles()
    {
        try
        {
            var asmDir = System.IO.Path.GetDirectoryName(typeof(DyeFramework).Assembly.Location);
            var pck = System.IO.Path.Combine(asmDir ?? ".", "DRCSpineDye.pck");
            if (System.IO.File.Exists(pck))
            {
                bool ok = ProjectSettings.LoadResourcePack(pck);
                GD.Print($"[DRCSpineDye] profile pck mounted: {ok}");
            }
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] self-mount failed: " + e);
        }
    }

    private static void OnProcessFrame()
    {
        Pump();
        HookPlayerDeath();
    }

    // --- player-death hook -------------------------------------------------
    // The game's CreatureAnimator registers a "Dead" trigger but NOTHING calls
    // it for the player (deathTrigger has no caller in sts2.dll) - the die
    // animation never plays. So we hook the game's own death signal:
    // Creature.Died. Combat state access goes through the PUBLIC events
    // CombatSetUp/TurnStarted (DebugOnlyGetState is test-only and unreliable
    // in release builds).
    public static event System.Action? PlayerDied;
    public static event System.Action? BattleWon;
    public static event System.Action? PlayerHit;
    private static readonly List<Creature> _hookedCreatures = new();
    private static CombatManager? _hookedManager;
    private static bool _hookWarned;

    // --- hit flash (受击闪红) ----------------------------------------------
    // DRC truth: hit flash = linear red (0.9216, 0.0319, 0.0762) pushed into
    // the character material (uniform loc7). Our ling_holo shaders carry
    // flash_color/flash_gain (default 0 = passthrough); this driver tweens
    // flash_gain on every hit. Materials are the profile's own, so only the
    // dyed character flashes.
    private static readonly List<ShaderMaterial> _flashMats = new();
    private static float _flashPeak = 1f;
    private static float _flashDecay = 0.25f;
    private static Tween? _flashTween;

    public static void ConfigureHitFlashMaterials(Godot.Collections.Dictionary cfg, params ShaderMaterial[] mats)
    {
        _flashMats.Clear();
        foreach (var m in mats)
            if (m != null) _flashMats.Add(m);
        if (cfg.TryGetValue("color", out var cv) && cv.VariantType == Variant.Type.Array)
        {
            var arr = cv.AsGodotArray();
            if (arr.Count == 3)
            {
                var col = new Color((float)arr[0].AsDouble(), (float)arr[1].AsDouble(), (float)arr[2].AsDouble());
                foreach (var m in _flashMats) m.SetShaderParameter("flash_color", col);
            }
        }
        _flashPeak = cfg.TryGetValue("peak", out var pk) ? (float)pk.AsDouble() : 1f;
        _flashDecay = cfg.TryGetValue("decay", out var dc) ? (float)dc.AsDouble() : 0.25f;
    }

    private static void OnPlayerHit()
    {
        try
        {
            if (_flashMats.Count == 0 || Tree == null) return;
            _flashTween?.Kill();
            foreach (var m in _flashMats) m.SetShaderParameter("flash_gain", _flashPeak);
            _flashTween = Tree.CreateTween();
            _flashTween.TweenMethod(
                Callable.From<double>(v =>
                {
                    float g = (float)((1.0 - v) * _flashPeak);
                    foreach (var m in _flashMats) m.SetShaderParameter("flash_gain", g);
                }),
                0.0, 1.0, _flashDecay);
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] hit flash failed (contained): " + e.Message);
        }
    }

    private static void HookCreaturesOf(CombatState state)
    {
        try
        {
            foreach (var c in state.PlayerCreatures)
            {
                if (c == null || _hookedCreatures.Contains(c)) continue;
                _hookedCreatures.Add(c);
                c.Died += OnPlayerCreatureDied;
                c.CurrentHpChanged += OnPlayerHpChanged;
                GD.Print($"[DRCSpineDye] death hook on player creature: {c.Name}");
            }
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] creature hook failed: " + e.Message);
        }
    }

    private static void OnPlayerHpChanged(int oldHp, int newHp)
    {
        if (newHp < oldHp)
        {
            // HP damage ALWAYS flashes (block-only chips do not - user call)
            try
            {
                DyeFramework.Log("player hp hit -> red flash");
                PlayerHit?.Invoke();
            }
            catch (System.Exception e) { GD.PrintErr("[DRCSpineDye] hit event error (contained): " + e.Message); }
        }
    }

    private static void HookPlayerDeath()
    {
        try
        {
            var cm = CombatManager.Instance;
            if (cm == null) return;
            if (ReferenceEquals(_hookedManager, cm)) return;
            UnhookPlayerDeath();
            _hookedManager = cm;
            cm.CombatSetUp += HookCreaturesOf;
            cm.TurnStarted += HookCreaturesOf;
            cm.CombatWon += OnCombatWon;
            // finalizer serialization: GC finalizers disposing Godot native
            // wrappers RACE the main thread's scene teardown at combat end ->
            // ExecutionEngineException, whole process dies (dump 23:56:
            // GodotObject.Finalize->Dispose AV on the finalizer thread). Draining
            // finalizers 1.5s AFTER CombatEnded runs them while the scene graph
            // is quiescent - the race window never opens.
            cm.CombatEnded += OnCombatEndedDrainFinalizers;
            GD.Print("[DRCSpineDye] combat events hooked (CombatSetUp/TurnStarted/CombatWon/CombatEnded)");
        }
        catch (System.Exception e)
        {
            if (!_hookWarned)
            {
                _hookWarned = true;
                GD.PrintErr("[DRCSpineDye] death hook unavailable: " + e.Message);
            }
        }
    }

    private static void OnCombatWon(CombatRoom _)
    {
        try
        {
            BattleWon?.Invoke();
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] battle-won event error (contained): " + e);
        }
    }

    private static void OnCombatEndedDrainFinalizers(CombatRoom _)
    {
        try
        {
            var t = new Timer { WaitTime = 1.5, OneShot = true, Autostart = true };
            Tree?.Root.AddChild(t);
            t.Timeout += () =>
            {
                try
                {
                    if (!GodotObject.IsInstanceValid(t)) return;
                    // drain on the main thread while the scene graph is stable:
                    // finalizers no longer race combat-scene teardown
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                    GD.Print("[DRCSpineDye] finalizers drained (post-combat)");
                }
                catch (System.Exception e)
                {
                    GD.PrintErr("[DRCSpineDye] finalizer drain failed (contained): " + e.Message);
                }
                finally
                {
                    if (GodotObject.IsInstanceValid(t)) t.QueueFree();
                }
            };
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] finalizer drain arm failed (contained): " + e.Message);
        }
    }

    private static void UnhookPlayerDeath()
    {
        if (_hookedManager != null)
        {
            try
            {
                _hookedManager.CombatSetUp -= HookCreaturesOf;
                _hookedManager.TurnStarted -= HookCreaturesOf;
                _hookedManager.CombatWon -= OnCombatWon;
                _hookedManager.CombatEnded -= OnCombatEndedDrainFinalizers;
            }
            catch { /* manager gone */ }
        }
        _hookedManager = null;
        foreach (var c in _hookedCreatures)
        {
            try { c.Died -= OnPlayerCreatureDied; } catch { /* creature gone */ }
            try { c.CurrentHpChanged -= OnPlayerHpChanged; } catch { /* creature gone */ }
        }
        _hookedCreatures.Clear();
    }

    private static void OnPlayerCreatureDied(Creature _)
    {
        // NEVER let an exception escape into the game's death command chain -
        // a throw here aborts KillWithoutCheckingWinCondition and the death
        // menu never appears (observed: ObjectDisposedException from a stale
        // watcher whose SpineSprite had been freed).
        try
        {
            GD.Print("[DRCSpineDye] player creature died -> death sequence");
            PlayerDied?.Invoke();
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] death sequence error (contained): " + e);
        }
    }

    // hit-on-target fx config (decoded from UE fx_ling_attack_01_hit), cached
    // when the ling profile attaches. The impact is tied to the GAME'S OWN
    // attack vfx: every player attack spawns a vfx_flying_slash spine that
    // flies TO the target - that is the authoritative "a hit landed here, now"
    // signal (hurt animations are not: poison/status/other monsters also hurt,
    // and Zero can attack without damaging).
    private static Godot.Collections.Dictionary? _hitFxCfg;

    private static void OnNodeAdded(Node node)
    {
        if (node.GetClass() == "SpineSprite")
        {
            if (_hitFxCfg != null && node.GetSceneFilePath().Contains("vfx_flying_slash"))
            {
                // a player-attack slash in flight: watch it and burst the
                // impact where it lands (once per slash)
                if (!node.GetMeta("drc_dye_hitfx", false).AsBool())
                {
                    node.SetMeta("drc_dye_hitfx", true);
                    var w = new SlashImpactWatcher(node, _hitFxCfg);
                    node.GetParent()?.AddChild(w);
                    w.Activate();
                }
            }
            EnqueueRetry(node);
        }
    }

    private static void Sweep(Node root, List<string> found)
    {
        if (root == null) return;
        if (root.GetClass() == "SpineSprite")
        {
            found.Add(root.GetPath());
            EnqueueRetry(root);
        }
        foreach (var child in root.GetChildren()) Sweep(child, found);
    }

    // --- retry pump: SpineSprites enter the tree before their skeleton data ---
    private static readonly List<Node> _pending = new();

    private static void EnqueueRetry(Node sprite)
    {
        if (_pending.Contains(sprite)) return;
        _pending.Add(sprite);
    }

    private static void Pump()
    {
        for (int i = _pending.Count - 1; i >= 0; i--)
        {
            var s = _pending[i];
            if (!GodotObject.IsInstanceValid(s))
            {
                _pending.RemoveAt(i);
                continue;
            }
            if (s.GetMeta("drc_dye_attached", false).AsBool())
            {
                _pending.RemoveAt(i); // our own silhouette-shadow sprite
                continue;
            }
            var res = s.Get("skeleton_data_res").AsGodotObject();
            var fileRes = res?.Get("skeleton_file_res").AsGodotObject();
            var path = SkeletonPathOf(fileRes);
            if (path != "")
            {
                _pending.RemoveAt(i);
                TryAttach(s, path);
            }
        }
    }

    private static string SkeletonPathOf(GodotObject fileRes)
    {
        if (fileRes == null) return "";
        var p = fileRes.Call("get_path").AsString();
        if (string.IsNullOrEmpty(p)) p = fileRes.Get("path").AsString();
        return p ?? "";
    }

    /// probe res://drc_dye/profiles/&lt;dir-suffix&gt;/config.json walking the
    /// skeleton directory suffixes from longest to shortest
    private static string FindConfigPath(string skelPath)
    {
        var p = skelPath.StartsWith("res://") ? skelPath.Substring("res://".Length) : skelPath;
        var slash = p.LastIndexOf('/');
        if (slash < 0) return "";
        var dir = p.Substring(0, slash + 1); // with trailing '/'
        while (dir.Length > 0)
        {
            var cand = "res://drc_dye/profiles/" + dir + "config.json";
            if (FileAccess.FileExists(cand)) return cand;
            var nextSlash = dir.IndexOf('/');
            dir = nextSlash >= 0 ? dir.Substring(nextSlash + 1) : "";
        }
        return "";
    }

    private static void TryAttach(Node sprite, string skelPath)
    {
        try
        {
            if (sprite.GetMeta("drc_dye_attached", false).AsBool()) return;

            var configPath = FindConfigPath(skelPath);
            if (configPath == "")
            {
                GD.Print($"[DRCSpineDye] {skelPath}: no dye config, leaving vanilla");
                return;
            }

            var cfg = Json.ParseString(FileAccess.Open(configPath, FileAccess.ModeFlags.Read).GetAsText());
            if (cfg.VariantType != Variant.Type.Dictionary)
            {
                GD.PrintErr($"[DRCSpineDye] Parse JSON failed: {configPath}");
                return;
            }

            var cfgDict = cfg.AsGodotDictionary();
            var filter = cfgDict["filter"].AsString();
            if (string.IsNullOrEmpty(filter) || !skelPath.Contains(filter))
            {
                GD.Print($"[DRCSpineDye] config loaded, filter '{filter}' does not match {skelPath}, leaving vanilla");
                return;
            }

            // skeleton-level spine bounds (x/y/width/height) anchor both the fx
            // emitter and the silhouette shadow to the real body - data-driven,
            // no constants
            double bx = 0, by = 0, bw = 0, bh = 0;
            try
            {
                using var sf = FileAccess.Open(skelPath, FileAccess.ModeFlags.Read);
                if (sf != null)
                {
                    var sj = Json.ParseString(sf.GetAsText());
                    if (sj.VariantType == Variant.Type.Dictionary)
                    {
                        var jd = sj.AsGodotDictionary();
                        bx = jd.TryGetValue("x", out var xv) ? xv.AsDouble() : 0;
                        by = jd.TryGetValue("y", out var yv) ? yv.AsDouble() : 0;
                        bw = jd.TryGetValue("width", out var wv) ? wv.AsDouble() : 0;
                        bh = jd.TryGetValue("height", out var hv) ? hv.AsDouble() : 0;
                    }
                }
            }
            catch (System.Exception be)
            {
                GD.PrintErr("[DRCSpineDye] skeleton bounds read failed: " + be.Message);
            }

            var matsCfg = cfgDict["materials"].AsGodotDictionary();
            var normal = LoadMaterial(matsCfg["normal"].AsString());
            var additive = LoadMaterial(matsCfg["additive"].AsString());
            var multiply = LoadMaterial(matsCfg["multiply"].AsString());
            var screen = LoadMaterial(matsCfg["screen"].AsString());
            if (normal == null || additive == null || multiply == null || screen == null)
            {
                GD.PrintErr("[DRCSpineDye] profile material missing, leaving vanilla");
                return;
            }

            sprite.Set("normal_material", normal);
            sprite.Set("additive_material", additive);
            sprite.Set("multiply_material", multiply);
            sprite.Set("screen_material", screen);

            var sp = cfgDict["shader_parameters"];
            if (sp.VariantType == Variant.Type.Dictionary)
            {
                foreach (var kv in sp.AsGodotDictionary())
                {
                    normal.SetShaderParameter(kv.Key.AsString(), kv.Value);
                    additive.SetShaderParameter(kv.Key.AsString(), kv.Value);
                    multiply.SetShaderParameter(kv.Key.AsString(), kv.Value);
                    screen.SetShaderParameter(kv.Key.AsString(), kv.Value);
                }
            }

            // death dissolve (optional key): dissolve material + animation watcher
            ShaderMaterial? dissolveMat = null;
            if (cfgDict.TryGetValue("dissolve_material", out var dmVar) && dmVar.VariantType == Variant.Type.String)
                dissolveMat = LoadMaterial(dmVar.AsString());
            var deathCfg = cfgDict.TryGetValue("death", out var dVar) && dVar.VariantType == Variant.Type.Dictionary
                ? dVar.AsGodotDictionary() : null;
            var fxCfg = cfgDict.TryGetValue("fx", out var fVar) && fVar.VariantType == Variant.Type.Dictionary
                ? fVar.AsGodotDictionary() : null;

            if (dissolveMat != null && deathCfg != null)
            {
                var watcher = new DeathWatcher(sprite, dissolveMat, deathCfg, fxCfg,
                    cfgDict.TryGetValue("win", out var winVar) ? winVar : default,
                    cfgDict.TryGetValue("entrance", out var entVar) ? entVar : default,
                    bx, by, bw, bh);
                sprite.AddChild(watcher);
                watcher.Activate();
            }

            // ground shadow (optional key): "silhouette" = skeleton-skin shadow
            // (the mobile RT shadow's true form), "blob" = soft ellipse fallback.
            // Scene gate: scenes whose ancestor names contain a disabled
            // keyword get no shadow (rest site stages the character without
            // one, like the official art)
            if (cfgDict.TryGetValue("shadow", out var shVar) && shVar.VariantType == Variant.Type.Dictionary)
            {
                var shCfg = shVar.AsGodotDictionary();
                bool shadowOff = false;
                if (shCfg.TryGetValue("disable_scene_keywords", out var dv) && dv.VariantType == Variant.Type.Array)
                {
                    foreach (var kw in dv.AsGodotArray())
                    {
                        if (HasAncestorKeyword(sprite, kw.AsString()))
                        {
                            shadowOff = true;
                            break;
                        }
                    }
                }
                if (shadowOff)
                {
                    GD.Print("[DRCSpineDye] shadow disabled by scene keyword");
                    // staged scenes (rest site) also get an explicit
                    // scale/position correction - belt and suspenders against
                    // the tscn override not being picked up by the loader
                    float stScale = 0f, stDy = 0f;
                    if (shCfg.TryGetValue("staged_scale", out var ss)) stScale = (float)ss.AsDouble();
                    if (shCfg.TryGetValue("staged_dy", out var sd)) stDy = (float)sd.AsDouble();
                    if (sprite is Node2D n2 && stScale > 0f && GodotObject.IsInstanceValid(n2))
                    {
                        n2.Scale = new Vector2(stScale, stScale);
                        n2.Position += new Vector2(0, stDy);
                        GD.Print($"[DRCSpineDye] staged scene correction: scale={stScale} dy={stDy}");
                    }
                    // diagnostic: which version of the scene file does the
                    // resource system actually serve?
                    try
                    {
                        var tscnPath = "res://scenes/rest_site/characters/silent_rest_site.tscn";
                        using var fa = FileAccess.Open(tscnPath, FileAccess.ModeFlags.Read);
                        var txt = fa?.GetAsText() ?? "";
                        GD.Print($"[DRCSpineDye] tscn read: 0.608_present={txt.Contains("0.608")} len={txt.Length}");
                    }
                    catch { /* diagnostic only */ }
                }
                else
                    AttachShadow(sprite, shCfg, by);
            }

            // hit flash (受击闪红, optional key): register the four blend
            // materials for the flash driver; HP-drop events then tween
            // flash_gain on them
            if (cfgDict.TryGetValue("hit_flash", out var hfVar) && hfVar.VariantType == Variant.Type.Dictionary)
            {
                var hf = hfVar.AsGodotDictionary();
                if (hf.TryGetValue("enabled", out var hfe) && hfe.AsBool())
                {
                    ConfigureHitFlashMaterials(hf, normal, additive, multiply, screen);
                    GD.Print($"[DRCSpineDye] hit flash armed: peak={_flashPeak:0.00} decay={_flashDecay:0.00}s");
                }
            }

            // attack fx (optional key): muzzle sparks + streak when the attack
            // animation starts, at the gun bone, two bursts (UE fx_ling_attack_01)
            if (cfgDict.TryGetValue("attack_fx", out var afVar) && afVar.VariantType == Variant.Type.Dictionary)
            {
                var af = afVar.AsGodotDictionary();
                if (af.TryGetValue("enabled", out var afe) && afe.AsBool())
                {
                    var watcher = new AttackFxWatcher(sprite, af);
                    sprite.AddChild(watcher);
                    watcher.Activate();
                    GD.Print("[DRCSpineDye] attack fx armed");
                }
            }

            // hit-on-target fx (optional key): decoded from UE
            // fx_ling_attack_01_hit - watched for on MONSTER spines (their
            // hurt animation = "this one just took our hit")
            if (cfgDict.TryGetValue("hit_fx", out var hf2Var) && hf2Var.VariantType == Variant.Type.Dictionary)
            {
                var hfx = hf2Var.AsGodotDictionary();
                if (hfx.TryGetValue("enabled", out var hfe2) && hfe2.AsBool())
                    _hitFxCfg = hfx;
            }

            sprite.SetMeta("drc_dye_attached", true);
            GD.Print($"[DRCSpineDye] dye attached: {configPath} for {skelPath}");
        }
        catch (System.Exception e)
        {
            GD.PrintErr($"[DRCSpineDye] attach failed: {e}");
        }
    }

    private static bool HasAncestorKeyword(Node node, string keyword)
    {
        if (string.IsNullOrEmpty(keyword)) return false;
        try
        {
            for (Node n = node; n != null; n = n.GetParent())
            {
                if (n.Name.ToString().ToLowerInvariant().Contains(keyword.ToLowerInvariant()))
                    return true;
            }
        }
        catch { /* tree walking is best-effort */ }
        return false;
    }

    private static ShaderMaterial? LoadMaterial(string resPath)
    {
        if (string.IsNullOrEmpty(resPath)) return null;
        return GD.Load<ShaderMaterial>(resPath);
    }

    // --- shadow ------------------------------------------------------------
    // mode dispatch: "silhouette" (default) = second SpineSprite sharing the
    // skeleton data, full pose copied every tick, mirrored+squashed about the
    // feet line - the true form of the mobile RT shadow (RTGlobalShadowActor
    // renders the units into an RT, RTGlobalShadowMat projects it on the
    // ground plane; the shadow IS the character's skin silhouette).
    // "blob" = the old soft ellipse approximation.
    private static void AttachShadow(Node sprite, Godot.Collections.Dictionary cfg, double feetSkelY)
    {
        try
        {
            if (!cfg.TryGetValue("enabled", out var en) || !en.AsBool()) return;
            var mode = cfg.TryGetValue("mode", out var m) ? m.AsString() : "silhouette";
            if (mode == "blob")
            {
                AttachShadowBlob(sprite, cfg);
                return;
            }
            // holder carries the timers and dies with the sprite; the drawn
            // node is a SIBLING of the sprite (children can be swallowed by
            // clip_children / parent redraw semantics)
            var holder = new ShadowSilhouette(sprite, cfg, (float)feetSkelY);
            sprite.AddChild(holder);
            holder.Activate();
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] shadow attach failed: " + e);
        }
    }

    private static void AttachShadowBlob(Node sprite, Godot.Collections.Dictionary cfg)
    {
        try
        {
            var texPath = cfg.TryGetValue("texture", out var tp) ? tp.AsString() : "";
            if (string.IsNullOrEmpty(texPath) || !ResourceLoader.Exists(texPath)) return;
            var tex = GD.Load<Texture2D>(texPath);
            var blob = new ShadowBlob { Texture = tex, Target = sprite };
            blob.OffsetY = cfg.TryGetValue("offset_y", out var oy) ? (float)oy.AsDouble() : 0f;
            if (cfg.TryGetValue("size", out var sz) && sz.VariantType == Variant.Type.Array)
            {
                var arr = sz.AsGodotArray();
                if (arr.Count == 2)
                {
                    var wpx = (float)arr[0].AsDouble();
                    var hpx = (float)arr[1].AsDouble();
                    blob.Scale = new Vector2(wpx / tex.GetWidth(), hpx / tex.GetHeight());
                }
            }
            var alpha = cfg.TryGetValue("alpha", out var al) ? (float)al.AsDouble() : 0.55f;
            blob.Modulate = new Color(0f, 0f, 0f, alpha);
            // same z as the SpineSprite (tree order already puts the blob just
            // before it): above the arena floor, below the character. The z999
            // diagnostic proved the earlier invisibility was a layer issue.
            blob.ZIndex = sprite is CanvasItem ci ? ci.ZIndex : 0;

            var parent = sprite.GetParent();
            if (parent != null)
            {
                parent.AddChild(blob);
                parent.MoveChild(blob, sprite.GetIndex());
            }
            else
            {
                sprite.AddChild(blob);
                blob.ShowBehindParent = true;
            }
            GD.Print($"[DRCSpineDye] shadow attached ({texPath}, alpha={alpha:0.00}, parent={parent?.Name ?? "?"}, idx={blob.GetIndex()})");

            // follow tick (no _Process: no source generators in this assembly)
            var tick = new Timer { WaitTime = 1.0 / 30.0, Autostart = true };
            blob.AddChild(tick);
            tick.Timeout += blob.Follow;
            blob.Follow();
            ReportBlobLater(blob, sprite);
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] shadow attach failed: " + e);
        }
    }

    private static void ReportBlobLater(Node blob, Node sprite)
    {
        var timer = new Timer { WaitTime = 3.0, OneShot = true, Autostart = true };
        blob.AddChild(timer);
        timer.Timeout += () =>
        {
            try
            {
                if (!GodotObject.IsInstanceValid(blob)) return;
                var n2 = blob as Node2D;
                var s2 = sprite as Node2D;
                GD.Print($"[DRCSpineDye] shadow probe: blob_gpos={n2?.GlobalPosition}, blob_gscale={n2?.GlobalScale}, " +
                         $"visible={n2?.Visible}, in_tree={blob.IsInsideTree()}, sprite_gpos={s2?.GlobalPosition}, sprite_gscale={s2?.GlobalScale}");
            }
            catch (System.Exception e)
            {
                GD.PrintErr("[DRCSpineDye] shadow probe failed: " + e);
            }
        };
    }
}

/// <summary>
/// Runs the mobile death sequence on one SpineSprite: swap to the dissolve
/// material, tween dissolve over death.duration (= the die animation's
/// morph+hold phases, extended over its near-instant hide cut), burst
/// particles. Purely event-driven: the game's own chain (StartDeathAnim ->
/// "Dead" trigger) plays the die animation and Creature.Died -> PlayerDied
/// triggers us; nothing here touches the animation state. Spine animation
/// signals are NOT usable (spine::AnimationState has a single listener slot,
/// SpineSprite.cpp:585, taken by the game's MegaSpine binding).
/// </summary>
public class DeathWatcher : Node
{
    private readonly Node _sprite;
    private readonly ShaderMaterial _dissolveMat;
    private readonly ShaderMaterial? _savedNormal;
    private readonly Variant _fxCfg;
    private readonly double _duration;
    private readonly bool _restoreAfter;
    private readonly string _deathAnim;   // the animation the game plays on death
    private readonly string _winAnim, _winLoop;         // victory chain
    private readonly string _entranceAnim, _entranceThen; // battle-start chain
    private readonly double _bx, _by, _bw, _bh;   // skeleton spine bounds
    private bool _deathDone;   // a creature dies exactly once - no replay
    private Timer? _watch;     // armed on death, fires when die actually starts
    private ulong _watchMs;

    public DeathWatcher(Node sprite, ShaderMaterial dissolveMat, Variant deathCfg, Variant fxCfg,
        Variant winCfg, Variant entranceCfg, double bx, double by, double bw, double bh)
    {
        _sprite = sprite;
        _dissolveMat = dissolveMat;
        _fxCfg = fxCfg;
        _bx = bx; _by = by; _bw = bw; _bh = bh;
        _savedNormal = sprite.Get("normal_material").As<ShaderMaterial>();
        var dc = deathCfg.AsGodotDictionary();
        _deathAnim = dc.TryGetValue("anim", out var a) ? a.AsString() : "die";
        _duration = dc.TryGetValue("duration", out var du) ? du.AsDouble() : 1.05;
        _restoreAfter = dc.TryGetValue("restore_after", out var ra) && ra.AsBool();
        var wc = winCfg.AsGodotDictionary();
        _winAnim = wc.TryGetValue("anim", out var wa) ? wa.AsString() : "win";
        _winLoop = wc.TryGetValue("loop", out var wl) ? wl.AsString() : "winloop";
        var ec = entranceCfg.AsGodotDictionary();
        _entranceAnim = ec.TryGetValue("anim", out var ea) ? ea.AsString() : "tibu";
        _entranceThen = ec.TryGetValue("then", out var et) ? et.AsString() : "idle_loop";
    }

    public void Activate()
    {
        // explicit activation: _Ready/_Process overrides are not registered in
        // this assembly (no Godot source generators). Event-driven only: the
        // game's own death chain plays the die animation; we get Creature.Died
        // -> DyeFramework.PlayerDied and run the dissolve alongside it.
        // the watcher dies with the combat scene; static events MUST be
        // unhooked here or every later BattleWon/PlayerDied pokes a disposed
        // node (log spammed ObjectDisposedException from QueueFree)
        TreeExiting += () =>
        {
            try
            {
                DyeFramework.PlayerDied -= OnPlayerDied;
                DyeFramework.BattleWon -= OnBattleWon;
            }
            catch { /* contained */ }
        };
        DyeFramework.PlayerDied += OnPlayerDied;
        DyeFramework.BattleWon += OnBattleWon;
        // entrance: wait for the game's initial idle_loop, then take over with
        // the entrance animation and queue idle behind it
        if (!string.IsNullOrEmpty(_entranceAnim))
        {
            _watchMs = Time.GetTicksMsec();
            var entranceWatch = new Timer { WaitTime = 0.05, Autostart = true };
            AddChild(entranceWatch);
            entranceWatch.Timeout += WatchEntrance;
            _watch = entranceWatch;
        }
    }

    private void OnPlayerDied()
    {
        try
        {
            if (_deathDone || _watch != null) return;
            // stale watcher: its sprite was freed (scene change) - detach and die
            if (!GodotObject.IsInstanceValid(_sprite))
            {
                DyeFramework.PlayerDied -= OnPlayerDied;
                QueueFree();
                return;
            }
            // trigger timing = the die animation STARTING, not the death
            // event: on death the game first restores status-effect size
            // changes (shrink etc.) and only then plays die - bursting at the
            // event fired on the shrunken character (user report)
            DyeFramework.Log("player death event -> waiting for die to start");
            _watchMs = Time.GetTicksMsec();
            var watch = new Timer { WaitTime = 0.05, Autostart = true };
            AddChild(watch);
            watch.Timeout += WatchDieStart;
            _watch = watch;
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] death trigger error (contained): " + e);
        }
    }

    private void WatchDieStart()
    {
        try
        {
            if (_deathDone) { StopWatch(); return; }
            if (!GodotObject.IsInstanceValid(_sprite))
            {
                DyeFramework.PlayerDied -= OnPlayerDied;
                QueueFree();
                return;
            }
            var st = _sprite.Get("animation_state").AsGodotObject()
                     ?? _sprite.Call("get_animation_state").AsGodotObject();
            var entry = st?.Call("get_current", 0).AsGodotObject();
            var ao = entry?.Call("get_animation").AsGodotObject();
            var name = ao != null ? ao.Call("get_name").AsString() : "";
            if (name == _deathAnim)
            {
                DyeFramework.Log("die started -> dissolve");
                StopWatch();
                // dense root-parented sampler: 0.1 s steps for 2.6 s - draws
                // the full pose trajectory so snap/glide/freeze is unambiguous
                var sampler = new Timer { WaitTime = 0.1, Autostart = true };
                DyeFramework.Tree?.Root.AddChild(sampler);
                int n = 0;
                sampler.Timeout += () =>
                {
                    PoseProbe($"die+{n * 0.1:0.0}");
                    if (++n >= 26) sampler.QueueFree();
                };
                StartDeath();
                return;
            }
            if (Time.GetTicksMsec() - _watchMs > 3000)
            {
                GD.PrintErr("[DRCSpineDye] die never started within 3s, dissolving anyway");
                StopWatch();
                StartDeath();
            }
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] die watch error (contained): " + e);
            try { StopWatch(); StartDeath(); } catch { /* contained */ }
        }
    }

    private void StopWatch()
    {
        if (_watch != null)
        {
            if (GodotObject.IsInstanceValid(_watch)) _watch.QueueFree();
            _watch = null;
        }
    }

    private void WatchEntrance()
    {
        try
        {
            if (_deathDone) { StopWatch(); return; }
            if (!GodotObject.IsInstanceValid(_sprite))
            {
                DyeFramework.PlayerDied -= OnPlayerDied;
                DyeFramework.BattleWon -= OnBattleWon;
                QueueFree();
                return;
            }
            var name = CurrentAnimName();
            if (name == "idle_loop" || name == _entranceThen)
            {
                StopWatch();
                // the entrance is a COMBAT flourish: every attached scene
                // (architect interlude, shops, events) shows this skeleton and
                // reaches idle_loop - only fire while a battle is in progress
                var cm = CombatManager.Instance;
                bool inCombat = cm != null && cm.IsInProgress;
                if (!inCombat)
                {
                    DyeFramework.Log($"entrance skipped: idle detected outside combat -> {name}");
                    return;
                }
                GD.Print($"[DRCSpineDye] entrance: idle detected -> {_entranceAnim}");
                PlayChain(_entranceAnim, false, _entranceThen, true);
                return;
            }
            if (Time.GetTicksMsec() - _watchMs > 3000)
            {
                GD.Print($"[DRCSpineDye] entrance: idle never detected within 3s (playing '{name}'), skipping");
                StopWatch();
            }
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] entrance watch error (contained): " + e);
            StopWatch();
        }
    }

    private void OnBattleWon()
    {
        try
        {
            if (_deathDone) return;
            if (!GodotObject.IsInstanceValid(_sprite))
            {
                DyeFramework.PlayerDied -= OnPlayerDied;
                DyeFramework.BattleWon -= OnBattleWon;
                QueueFree();
                return;
            }
            DyeFramework.Log($"battle won -> {_winAnim} + {_winLoop}");
            PlayChain(_winAnim, false, _winLoop, true);
            ArmProbe(1.0, "win+1.0");
            ArmProbe(2.5, "win+2.5");
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] battle-won error (contained): " + e);
        }
    }

    private string CurrentAnimName()
    {
        var st = _sprite.Get("animation_state").AsGodotObject()
                 ?? _sprite.Call("get_animation_state").AsGodotObject();
        var entry = st?.Call("get_current", 0).AsGodotObject();
        var ao = entry?.Call("get_animation").AsGodotObject();
        return ao != null ? ao.Call("get_name").AsString() : "";
    }

    // pose probe: what is the character skeleton actually doing at this
    // moment (animation + key bone rotations); the live silhouette shadow
    // appends its own (dst) values for follow comparison
    private void PoseProbe(string tag)
    {
        try
        {
            if (!GodotObject.IsInstanceValid(_sprite))
            {
                DyeFramework.Log($"pose[{tag}] sprite gone");
                return;
            }
            if (!_sprite.IsInsideTree()) tag += "(OUT-OF-TREE)";
            var sk = _sprite.Call("get_skeleton").AsGodotObject();
            ShadowSilhouette.ActiveShadow?.LogPair(tag, CurrentAnimName(),
                ShadowSilhouette.BoneRot(sk, "bone10"), ShadowSilhouette.BoneRot(sk, "bone11"));
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] pose probe failed: " + e.Message);
        }
    }

    // probes are parented to the tree ROOT: the game pulls the player visual
    // out of the scene shortly after death, which freezes any timers left
    // under it (the first probe round proved exactly that)
    private void ArmProbe(double delay, string tag)
    {
        var t = new Timer { WaitTime = delay, OneShot = true, Autostart = true };
        DyeFramework.Tree?.Root.AddChild(t);
        t.Timeout += () =>
        {
            PoseProbe(tag);
            t.QueueFree();
        };
    }

    // custom spine-godot binding signatures (MegaAnimationState.cs):
    // set_animation(animationName, loop, trackIndex) / add_animation(animationName, delay, loop, trackIndex)
    private void PlayChain(string first, bool firstLoop, string? then, bool thenLoop)
    {
        var st = _sprite.Get("animation_state").AsGodotObject()
                 ?? _sprite.Call("get_animation_state").AsGodotObject();
        if (st == null) return;
        st.Call("set_animation", first, firstLoop, 0);
        if (!string.IsNullOrEmpty(then))
            st.Call("add_animation", then, 0.0f, thenLoop, 0);
    }

    private void StartDeath()
    {
        if (_deathDone) return;
        _deathDone = true;   // once
        try
        {
            if (!GodotObject.IsInstanceValid(_sprite))
            {
                GD.Print("[DRCSpineDye] sprite already freed, skip dissolve visuals");
                return;
            }
            // plan B: NEVER touch the animation - the game's own death chain
            // (StartDeathAnim -> "Dead" trigger -> die) plays the die
            // animation natively, once. We only run the dissolve material +
            // fx, timed to the die animation's phase1+phase2 sum (extended
            // over the near-instant hide fade); the die animation's final
            // all-slot cut-to-transparent phase hides the character.
            _dissolveMat.SetShaderParameter("dissolve", 0.0f);
            if (_savedNormal != null)
                _sprite.Set("normal_material", _dissolveMat);

            if (_fxCfg.VariantType == Variant.Type.Dictionary)
            {
                var fx = _fxCfg.AsGodotDictionary();
                if (fx.TryGetValue("enabled", out var fe) && fe.AsBool())
                    SpawnFx();
            }

            // sampler RIDES the dissolve tween: root-level Timers went silent
            // during two death runs, this tween demonstrably runs to the end
            _deathT0 = Time.GetTicksMsec();
            ulong lastLog = 0;
            var tween = CreateTween();
            tween.TweenMethod(Callable.From<double>(v =>
            {
                _dissolveMat.SetShaderParameter("dissolve", (float)v);
                // the shadow fades with the very same value: body and shadow
                // erode in lockstep
                ShadowSilhouette.ActiveShadow?.SetDissolve((float)v);
                ulong now = Time.GetTicksMsec();
                if (now - lastLog >= 250)
                {
                    lastLog = now;
                    DeathSample(v, now);
                }
            }), 0.0, 1.0, _duration);
            tween.TweenCallback(Callable.From(FinishDeath));
        }
        catch (System.Exception e)
        {
            // contain: the game's death flow must never see our exceptions
            GD.PrintErr("[DRCSpineDye] dissolve error (contained): " + e);
            try { FinishDeath(); } catch { /* best effort */ }
        }
    }

    private ulong _deathT0;

    private void DeathSample(double v, ulong now)
    {
        try
        {
            float b10 = float.NaN;
            string anim = "";
            bool valid = GodotObject.IsInstanceValid(_sprite);
            if (valid)
            {
                var sk = _sprite.Call("get_skeleton").AsGodotObject();
                b10 = ShadowSilhouette.BoneRot(sk, "bone10");
                anim = CurrentAnimName();
            }
            DyeFramework.Log($"dsample t+{(now - _deathT0) / 1000.0:0.00}s v={v:0.000} anim={anim} b10={b10:0.0} " +
                             $"sprite_valid={valid} in_tree={valid && _sprite.IsInsideTree()} " +
                             $"paused={(DyeFramework.Tree?.Paused ?? false)} tscale={Engine.TimeScale:0.00} " +
                             $"shadow={(ShadowSilhouette.ActiveShadow != null ? "alive" : "null")}");
        }
        catch { /* contained */ }
    }

    private void SpawnFx()
    {
        try
        {
            var fx = _fxCfg.AsGodotDictionary();
            var texPath = fx.TryGetValue("texture", out var tp) ? tp.AsString() : "";
            if (string.IsNullOrEmpty(texPath) || !ResourceLoader.Exists(texPath)) return;
            if (_bw <= 0 || _bh <= 0)
            {
                GD.PrintErr("[DRCSpineDye] fx skipped: skeleton bounds (x/y/width/height) missing");
                return;
            }
            // everything below lives in SKELETON units; the emitter node scale
            // maps them into parent space, so shrink/restore tweens that run
            // while die plays are absorbed by re-reading the sprite scale
            // every frame (track timer below)
            float bodyScale = fx.TryGetValue("body_scale", out var bsc) ? (float)bsc.AsDouble() : 1.0f;
            float bodyW = (float)(_bw * bodyScale);
            float bodyH = (float)(_bh * bodyScale);
            // flight spec (user): no velocity model - the particle rises
            // 0.5 x character size over a flight time equal to the dissolve
            // duration, fading 100 -> 0 over the last 0.25 x character size
            float flightT = (float)_duration;
            float riseV = bodyH * 0.5f / flightT;   // constant rise speed
            var p = new CpuParticles2D
            {
                Texture = GD.Load<Texture2D>(texPath),
                OneShot = true,
                Explosiveness = 1.0f,
                Amount = fx.TryGetValue("amount", out var am) ? am.AsInt32() : 90,
                Lifetime = flightT,
                Spread = 0f,
                Direction = new Vector2(0, -1),
                Gravity = Vector2.Zero,
                InitialVelocityMin = riseV,
                InitialVelocityMax = riseV,
                ScaleAmountMin = 0.08f,
                ScaleAmountMax = 0.22f,
                Color = new Color(0.62f, 0.32f, 1.00f, 1.0f),
                ColorRamp = FadeRamp(),
                Emitting = true,
            };
            // binomial-ish spawn density across the body WIDTH: centre dense,
            // edges sparse (mean of 7 uniforms, user-tuned),
            // uniform over the body height;
            // points-mode emission picks uniformly from this cloud
            var rng = new System.Random();
            int n = 512;
            var pts = new System.Collections.Generic.List<Vector2>(n);
            for (int i = 0; i < n; i++)
            {
                float u = (rng.NextSingle() + rng.NextSingle() + rng.NextSingle() + rng.NextSingle() + rng.NextSingle() + rng.NextSingle() + rng.NextSingle()) / 7f;
                pts.Add(new Vector2((u - 0.5f) * bodyW, (rng.NextSingle() - 0.5f) * bodyH));
            }
            p.EmissionShape = CpuParticles2D.EmissionShapeEnum.Points;
            p.EmissionPoints = pts.ToArray();
            var mat = new CanvasItemMaterial { BlendMode = CanvasItemMaterial.BlendModeEnum.Add };
            p.Material = mat;
            var parent = _sprite.GetParent();
            if (parent != null && _sprite is Node2D n2)
            {
                parent.AddChild(p);
                // anchor = the skeleton bounding-box CENTRE: its offset from
                // the skeleton origin is (x+w/2, y+h/2) in skeleton units,
                // flipped to godot y-down and mapped by the sprite scale;
                // offset_y is a pure fine-tune (0 by default)
                float offY = fx.TryGetValue("offset_y", out var oy) ? (float)oy.AsDouble() : 0f;
                var centre = new Vector2((float)(_bx + _bw / 2), (float)(_by + _bh / 2));
                Vector2 spawnScale = n2.Scale;
                p.Scale = spawnScale;
                p.GlobalPosition = n2.GlobalPosition
                    + new Vector2(-centre.X * spawnScale.X, -centre.Y * spawnScale.Y)
                    + new Vector2(0, offY * spawnScale.Y);
                // follow shrink/restore tweens while the effect is alive
                var track = new Timer { WaitTime = 1.0 / 60.0, Autostart = true };
                p.AddChild(track);
                track.Timeout += () =>
                {
                    try
                    {
                        if (!GodotObject.IsInstanceValid(p) || !GodotObject.IsInstanceValid(n2)) return;
                        var sc = n2.Scale;
                        p.Scale = sc;
                        p.GlobalPosition = n2.GlobalPosition
                            + new Vector2(-centre.X * sc.X, -centre.Y * sc.Y)
                            + new Vector2(0, offY * sc.Y);
                    }
                    catch { /* contained */ }
                };
                GD.Print($"[DRCSpineDye] fx rect: bounds=({_bx:0},{_by:0} {_bw:0.0}x{_bh:0.0}) centre=({centre.X:0.0},{centre.Y:0.0}) spriteScale={n2.Scale} emitterGpos={p.GlobalPosition}");
                var timer = new Timer { WaitTime = flightT + 0.3f, OneShot = true, Autostart = true };
                p.AddChild(timer);
                timer.Timeout += () => p.QueueFree();
            }
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] death fx failed: " + e);
        }
    }

    private static Gradient FadeRamp()
    {
        // purple throughout; alpha holds 1 for the first half of the flight
        // (the first 0.25 x size of rise) then fades 1 -> 0 over the rest
        var g = new Gradient();
        g.SetColor(0, new Color(0.62f, 0.32f, 1.00f, 1.0f));
        g.SetColor(1, new Color(0.62f, 0.32f, 1.00f, 0.0f));
        g.AddPoint(0.5f, new Color(0.62f, 0.32f, 1.00f, 1.0f));
        return g;
    }

    private void FinishDeath()
    {
        try
        {
            if (!GodotObject.IsInstanceValid(_sprite)) return;
            ulong elapsed = Time.GetTicksMsec() - _deathT0;
            DyeFramework.Log($"dissolve finished elapsed={elapsed}ms cfg={_duration * 1000:0}ms " +
                             $"paused={(DyeFramework.Tree?.Paused ?? false)} tscale={Engine.TimeScale:0.00} " +
                             $"shadow={(ShadowSilhouette.ActiveShadow != null ? "alive" : "null")}");
            // the tween ends 0.05 s BEFORE the die animation completes: hide
            // the sprite here so the track-clear/reset on the animation's
            // completion frame can never flash one opaque setup-pose frame
            _sprite.Set("visible", false);
            if (_restoreAfter && _savedNormal != null)
                _sprite.Set("normal_material", _savedNormal);
            _dissolveMat.SetShaderParameter("dissolve", 0.0f);
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] dissolve restore failed: " + e);
        }
    }
}

/// <summary>Soft ground blob that follows the character (timer-driven;
/// C# _Process overrides are not registered in this assembly).</summary>
public class ShadowBlob : Sprite2D
{
    public Node? Target;
    public float OffsetY;

    public void Follow()
    {
        if (Target is Node2D n2 && GodotObject.IsInstanceValid(n2) && IsInsideTree())
            GlobalPosition = new Vector2(n2.GlobalPosition.X, n2.GlobalPosition.Y + OffsetY);
    }
}

/// <summary>
/// Attack muzzle FX (port of UE fx_ling_attack_01, DRC truth): when the
/// attack animation starts, fire velocity-stretched streaks + blue-purple
/// sparks at the gun bone - two bursts (t=0 / t=0.43, the animation's
/// double shot). Spark params from the decoded emitter: sphere r=25 burst,
/// speed 700-1500uu/s +X, drag 7, life 0.1-0.2, color lerp
/// (0.29,0.69,1)-(0.54,0.37,1) fading to (0.37,0.85,1).
/// Timer-driven (no source generators in this assembly).
/// 2026-10-10 A 档重构（主日志条目30）：按"有无新键"分流两条管线——
/// 新键（sparks.strip_texture / streak.texture / flash.*）走真值发射器
/// EmitSparks/EmitStreak/EmitFlash，config 速度/尺寸语义=期望屏幕 px，
/// 每拍实测父链全局缩放做补偿（×1/GlobalScale.X，约 1/0.29）；Damping
/// 用位移等效换算 DragToDamping 替换原 ×40/×60 拍脑袋系数；64px 硬上限
/// 换成 max_size_px + 面积熔断。只有旧键（textures/streak_texture）则维持
/// legacy 路径逐帧纹理发射——静默皮肤（silent profile）行为不变。
/// </summary>
public class AttackFxWatcher : Node
{
    private readonly Node _target;
    private readonly string _boneName;
    private readonly float _muzzleLen;
    private readonly float _scale;
    private readonly float[] _burstTimes;
    private readonly string[] _anims;
    private readonly Godot.Collections.Dictionary _sparksCfg, _streakCfg;
    private readonly Color _colA, _colB, _fadeTo;
    private readonly System.Collections.Generic.List<string> _sparkTexPaths;
    private readonly string _streakTexPath;
    // --- A 档新增（条目30）---
    private readonly Godot.Collections.Dictionary _flashCfg;   // flash 面片段
    private readonly string _stripTexPath;  // sparks.strip_texture（九帧 SubUV 条带）
    private readonly string _streakTexNew;  // streak.texture（ma_412_uv 遮罩移植）
    private readonly bool _truePipeline;    // 新键存在 → 真值发射器；否则 legacy
    private readonly float _maxSparkPx, _maxStreakPx, _maxFlashPx; // max_size_px（≤512）
    private bool _gscaleLogged;             // 一次性诊断日志（每 watcher 一次）
    private Timer? _poll;
    private string _prevAnim = "";
    private int _fireSeq;
    // --- 条目 43：枪口基点/枪管轴（ling.json qiang02 mesh hull 真值）---
    private readonly float[]? _muzzleOffset; // 枪口本地偏移（相对 bone104 原点，骨骼本地系）
    private readonly float[]? _muzzleDir;    // 枪管轴单位向量（骨骼本地系）；null 回退 (facing,0)
    // --- 条目 48：hull 两点差分 + 旋转跟随（第六轮打回：光束仰 30-40° 与枪管不共线）---
    // 取证实锤（tools/diag_dir6.py，主日志条目 48②）：
    //   (a) qiang02 槽位绑定骨=bone104（任务书"绑定错位"假设不成立）；
    //   (b) attack 动画 slots.attachment 轨道把 qiang02 槽位换成 **zero_qiang_C2**（带
    //       deform 平移 (20.388,-32.900)）——config 真值来源的 qiang02 hull 根本不是
    //       attack 期间渲染的几何！两 hull 长轴在 bone104 局部系固有差 -5.08°，而
    //       前端中点仅差 6.11 骨架单位（≈1.8px）——"位置碰巧对、方向差"的机制；
    //   (c) t_fire 后 streak 存活 0.1s 窗口内臂链仍旋转 ≈-26.25°（bone8 Δ-17.4°/
    //       bone9 Δ-9.5°，线性下界；bezier overshoot 98.5° 实际更快）——方向出生
    //       锁定必然过时。合计 ≈31° vs 截图观测 30-40°，定性吻合。
    // 修复：muzzle_hull（4 元素 Fx,Fy,Rkx,Rky，取 attack 实际附件 zero_qiang_C2 的
    // hull+deform 真值）→ 每帧两点差分求 dir(t)，位置与旋转全程跟随——与 UE 原版
    // "发射器挂枪口 socket、位置+旋转全跟随"语义对齐（EmitStreakSprite 处有详注）。
    private readonly float[]? _muzzleHull;   // [Fx,Fy,Rkx,Rky]（骨骼本地系）；null=走旧单点+mdir 路径
    private readonly string? _muzzleBoneCfg; // config muzzle_bone（构建期从 ling.json slots 解析写入）；null/空=用 _boneName
    private string _boneMuzzleName = "";     // Fire 时实际解析出的跟随骨名（=日志 bone= 值）
    // --- 条目 44：方向链路定案（"度当弧度"根修）---
    private readonly string _dirSource;      // "auto"（默认，骨架变换三级降级）| "facing"（强制枪管角兜底）
    private readonly float _barrelDeg;       // dir_source=="facing" 时的枪管仰角（UE 真值 muzzle_dir 反解 ≈ -10.18°）
    private bool _dirSrcWarned;              // 降级链一次性告警日志
    private static readonly System.Random _rng = new(); // flash 寿命随机（每片独立）
    // --- 条目 47：特效跟随枪口（用户反馈：面片烘焙在原位，动画中枪口在动，
    //     特效脱锚）---
    // config 键 track_muzzle（bool，缺省 true）：false 时行为=现状（出生点固定）。
    private readonly bool _trackMuzzle;
    // --- 条目 52：dir_rot_fix（渲染/C# 骨架系恒定旋转差 δ 的注入校准）---
    private readonly float _dirRotFixDeg;    // config dir_rot_fix（度，默认 0=关）
    private bool _dirFixLogged;              // 一次性生效日志（首拍 Fire 时）
    // 跟随登记表：streak/flash holder 出生时各登记一条，生命周期内每帧重算
    // 枪口世界坐标。sparks 不登记——粒子是飞散弹道，出生后物理上就该按初速
    // 飞离，跟随枪口反而失真（主日志条目 47② 有说明）。
    private readonly System.Collections.Generic.List<MuzzleFollower> _followers = new();
    // per-frame 钩子状态。注意：本 assembly 无 source generator，_Process/
    // _ExitTree 等 Node 生命周期重写不被注册（见 Activate() 注释）——跟随更新
    // 改用 SceneTree.ProcessFrame 信号挂接（引擎信号事件在 GodotSharp 内置，
    // 不依赖项目 sourcegen），挂上即每帧回调，与任务书"_Process 每帧"语义等价。
    private SceneTree? _hookedTree;
    private bool _frameHooked;

    // 跟随登记条目。设计要点：
    //   · 出生时解析一次并缓存 LocalOffset+Sc（避免每帧走三级降级链）；
    //   · 条目 48 改案：Dir0 出生锁定**作废**——UE 原版=发射器挂枪口 socket，
    //     位置+旋转全程跟随（fx_ling_attack_01 的 EmitterLocation 绑在武器
    //     muzzle socket 上，粒子发射器坐标系随 socket 姿态逐帧更新）；第五轮的
    //     "方向锁定防抖动"设计在手臂快速运动窗口（t_fire 后 0.1s 臂链 Δ≈-26°，
    //     见字段区取证注）必然过时，是第六轮打回的直接根因。现 hull 模式下
    //     每帧两点差分重算 dir(t) 并更新 holder.Rotation，位置+旋转全程共线。
    //   · LocalF/LocalB（hull 模式）：枪管轴前后端中点的骨骼本地坐标——
    //     每帧两次 local_to_world 差分，非均匀缩放先乘 sc 再归一（与 ResolveMuzzle
    //     同口径）；
    //   · FacingMode：dir_source=="facing" 时 ResolveMuzzle 不走 local_to_world
    //     （gpos = n2.GlobalPosition + offset×sc），跟随期同式复算（方向仍用
    //     出生 Dir0——facing 模式本就是观感逃生门，方向恒定枪管角）。
    //   · 条目 49 改案（第七轮打回根修）：**不再跨帧持有 SpineBone 包装对象**。
    //     取证：第七轮打回截图的光束角与各自会话日志出生角精确吻合
    //     （旧 -40.63°≈dir2deg -40.5、新 -21.92°≈dir0deg -22.0），而同帧枪管
    //     已回摆（-1.8°/-5.0°）→ follower 出生后位置+旋转双冻结；部署 dll 反
    //     编译确认旋转跟随代码在包内且日志无异常，排除漏编译/崩溃——唯一解释
    //     是 fire/burst 时 find_bone 取得的包装对象在其后失效或其 local_to_world
    //     返回冻结值（游戏自带 spine 模块的包装对象生命周期与官方运行时不同，
    //     无法从 C# 侧担保）。故跟随期每帧 get_skeleton→find_bone 重解析
    //     （fire/burst 时刻新鲜解析的 bone 已被证明读到活值——wr2/dir2 逐攻击
    //     连续变化且与枪口位置自洽）。#17 豁免注：每帧每 follower 新增 2 次非
    //     值类型 Variant 调用（get_skeleton→Object、find_bone 字符串入参/Object
    //     返回），量级受控：仅特效存活期（≤0.3s）挂载、follower ≤2、无 follower
    //     即摘钩，合计 ≤4 次/帧且字符串为短常量（"bone104"）——与 #17 事故
    //     （全量粒子×每帧×无上限）相差 3 个数量级，正确性优先（缓存方案已被
    //     实机证伪）。
    private sealed class MuzzleFollower
    {
        public Node2D Holder;      // 被跟随的面片根节点（回收仍由 Tween 回调 + FreeLater 负责）
        public Node2D N2;          // 角色视觉节点（GlobalPosition 每帧重读）
        public string BoneName;    // 枪口锚骨名（条目 49：每帧 find_bone 重解析，不再持对象）
        public Vector2 LocalOffset;// 枪口偏移（骨骼本地系，出生时缓存；非 hull 模式用）
        public Vector2 LocalF;     // hull 模式：枪管轴前端中点 F（骨骼本地系）
        public Vector2 LocalB;     // hull 模式：枪管轴后端中点 Rk（骨骼本地系）
        public bool IsHull;        // true=两点差分+旋转跟随（条目 48）；false=旧单点跟随
        public Vector2 Sc;         // 本节点 Scale（出生时缓存，#13 口径）
        public Vector2 Dir0;       // 出生方向（非 hull 模式锁定用；hull 模式仅作日志/降级参考）
        public float OffX;         // flash 枪口帽间隙（config flash.offset_x；hull 模式下已局部化进 sprite Position）
        public float ScaleMul;     // config scale
        public float Comp;         // 父链缩放补偿（每拍 Burst 实测值）
        public double ExpiresAt;   // 超时时刻（Time.GetTicksMsec/1000 时基）
        public string Kind;        // "streak" | "flash"
        public bool FacingMode;    // true=不走 local_to_world（dir_source=facing）
        public bool FollowLogged;  // 条目 49：首帧跟随诊断日志只打一次
        public Node2D SprNode;     // 条目 52：SpineSprite 渲染节点引用（出生时从 N2
                                   // 向下解析一次缓存；与 _target 同生命周期，tick1
                                   // 打印前有 IsInstanceValid 守卫兜底失效）
    }

    public AttackFxWatcher(Node target, Godot.Collections.Dictionary cfg)
    {
        _target = target;
        _boneName = cfg.TryGetValue("bone", out var bn) ? bn.AsString() : "bone9";
        _muzzleLen = cfg.TryGetValue("muzzle_len", out var ml) ? (float)ml.AsDouble() : 0f;
        // 条目 43：数据源=ling.json qiang02 mesh hull——前端中点 (137.66,-36.98)、
        // 枪管轴单位向量 (0.98424,-0.17684)（距 bone104 142.5 单位≈41.3px，与
        // 截图枪管 40-55px 吻合）。null=回退旧行为（muzzle_len 沿骨骼 X 前移）。
        _muzzleOffset = cfg.TryGetValue("muzzle_offset", out var mo)
                        && mo.VariantType == Variant.Type.Array && mo.AsGodotArray().Count >= 2
            ? new[] { (float)mo.AsGodotArray()[0].AsDouble(), (float)mo.AsGodotArray()[1].AsDouble() }
            : null;
        _muzzleDir = cfg.TryGetValue("muzzle_dir", out var mdr)
                     && mdr.VariantType == Variant.Type.Array && mdr.AsGodotArray().Count >= 2
            ? new[] { (float)mdr.AsGodotArray()[0].AsDouble(), (float)mdr.AsGodotArray()[1].AsDouble() }
            : null;
        // 条目 48：muzzle_hull（4 元素 Fx,Fy,Rkx,Rky，骨骼本地系）——轴两点取 hull
        // 本尊（attack 实际附件 zero_qiang_C2+deform 真值，见字段区取证注）。存在即
        // 走"两点差分+旋转跟随"新路径；muzzle_dir 键废弃（保留不删，仅 fallback
        // 路径即三级降级仍用它）。muzzle_bone（构建期从 ling.json slots 解析写入）：
        // 跟随骨名；空/缺=回退 _boneName（bone104）。
        _muzzleHull = cfg.TryGetValue("muzzle_hull", out var mh)
                      && mh.VariantType == Variant.Type.Array && mh.AsGodotArray().Count >= 4
            ? new[] { (float)mh.AsGodotArray()[0].AsDouble(), (float)mh.AsGodotArray()[1].AsDouble(),
                      (float)mh.AsGodotArray()[2].AsDouble(), (float)mh.AsGodotArray()[3].AsDouble() }
            : null;
        _muzzleBoneCfg = cfg.TryGetValue("muzzle_bone", out var mb) ? mb.AsString() : null;
        // 条目 44：方向源选择——默认 auto（骨架 local_to_world 两点差分 →
        // get_global_transform → DegToRad 修正公式 三级降级）；"facing" 强制
        // 用 barrel_deg 枪管角（观感校准逃生门，不经骨架变换）
        _dirSource = cfg.TryGetValue("dir_source", out var dsv) ? dsv.AsString() : "auto";
        _barrelDeg = cfg.TryGetValue("barrel_deg", out var bdv) ? (float)bdv.AsDouble() : -10.18f;
        // 条目 47：track_muzzle（bool，缺省 true）——false 时关闭跟随（行为=现状）
        _trackMuzzle = cfg.TryGetValue("track_muzzle", out var tmv) ? tmv.AsBool() : true;
        // 条目 52：dir_rot_fix（float，单位=度，默认 0=关）——渲染系与 C# 骨架系
        // 恒定旋转差 δ（条目 51 取证 γ_meas−γ_quad=+7.81°±2）的手工注入校准键。
        // 值来源=运行时 hook（follow tick1 日志的 sprrot/n2rot 节点链旋转、或
        // dirdeg 与枪管角对账），非截图反解（三链路纪律，主日志 52③）。
        // =0 时行为与条目 51 产物逐位一致（零行为变更承诺）。
        _dirRotFixDeg = cfg.TryGetValue("dir_rot_fix", out var drf) ? (float)drf.AsDouble() : 0f;
        _scale = cfg.TryGetValue("scale", out var sc) ? (float)sc.AsDouble() : 1f;
        var bl = new System.Collections.Generic.List<float>();
        if (cfg.TryGetValue("bursts", out var bv) && bv.VariantType == Variant.Type.Array)
            foreach (var b in bv.AsGodotArray()) bl.Add((float)b.AsDouble());
        if (bl.Count == 0) bl.Add(0f);
        _burstTimes = bl.ToArray();
        var al = new System.Collections.Generic.List<string>();
        if (cfg.TryGetValue("anims", out var av) && av.VariantType == Variant.Type.Array)
            foreach (var a in av.AsGodotArray()) al.Add(a.AsString());
        if (al.Count == 0) al.Add("attack");
        _anims = al.ToArray();
        _sparksCfg = cfg.TryGetValue("sparks", out var sc2) && sc2.VariantType == Variant.Type.Dictionary
            ? sc2.AsGodotDictionary() : new Godot.Collections.Dictionary();
        _streakCfg = cfg.TryGetValue("streak", out var st2) && st2.VariantType == Variant.Type.Dictionary
            ? st2.AsGodotDictionary() : new Godot.Collections.Dictionary();
        _colA = Col(cfg, "color_a", new Color(0.29f, 0.69f, 1f));
        _colB = Col(cfg, "color_b", new Color(0.54f, 0.37f, 1f));
        _fadeTo = Col(cfg, "fade_to", new Color(0.37f, 0.85f, 1f));
        _sparkTexPaths = new System.Collections.Generic.List<string>();
        if (cfg.TryGetValue("textures", out var tv) && tv.VariantType == Variant.Type.Array)
        {
            foreach (var t in tv.AsGodotArray()) _sparkTexPaths.Add(t.AsString());
        }
        if (_sparkTexPaths.Count == 0 && cfg.TryGetValue("texture", out var tp))
            _sparkTexPaths.Add(tp.AsString());
        _streakTexPath = cfg.TryGetValue("streak_texture", out var sp) ? sp.AsString() : "";
        // --- A 档新键解析（条目30）：缺失键一律走代码默认值（健壮性对齐现状）---
        _flashCfg = cfg.TryGetValue("flash", out var fv) && fv.VariantType == Variant.Type.Dictionary
            ? fv.AsGodotDictionary() : new Godot.Collections.Dictionary();
        _stripTexPath = _sparksCfg.TryGetValue("strip_texture", out var sst) ? sst.AsString() : "";
        _streakTexNew = _streakCfg.TryGetValue("texture", out var stx) ? stx.AsString() : "";
        // 新管线探测：任一新键（strip_texture / streak.texture / flash 段）存在即走
        // 真值发射器；只有旧键（textures/streak_texture）维持 legacy（静默皮肤不变）
        _truePipeline = !string.IsNullOrEmpty(_stripTexPath)
                        || !string.IsNullOrEmpty(_streakTexNew)
                        || _flashCfg.Count > 0;
        _maxSparkPx = MaxSizePx(cfg, "spark", 32f);
        _maxStreakPx = MaxSizePx(cfg, "streak", 96f);
        _maxFlashPx = MaxSizePx(cfg, "flash", 128f);
    }

    // max_size_px（A 档）：按发射器种类取上限，全局绝对上限 512px（替换原 64 硬上限）
    private static float MaxSizePx(Godot.Collections.Dictionary cfg, string kind, float def)
    {
        if (!cfg.TryGetValue("max_size_px", out var mv) || mv.VariantType != Variant.Type.Dictionary)
            return def;
        var d = mv.AsGodotDictionary();
        float v = d.TryGetValue(kind, out var kv) ? (float)kv.AsDouble() : def;
        return Mathf.Clamp(v, 1f, 512f);
    }

    // --- 条目 44：方向链路（"度当弧度"根修）--------------------------------
    // 根因：Spine 的 get_world_rotation_x() 返回【度】，旧代码六处把它直接
    // 喂给 Mathf.Cos/Sin（弧度）→ 每拍方向乱跳（日志实测 +41°/-167°/-32°，
    // 而日志反解证明真实骨骼世界旋转仅 ≈0°±3°；若旧代码单位正确，同一相位
    // 不可能出现 199° 的拍间差）。修法=改用骨架自带变换，单位无关。

    // 骨架本地点 → 骨架世界点。SpineBone::local_to_world 已在
    // libspine_godot dll strings 核实在册。方法缺失/返回类型不符一律返回
    // null（降级链接管）。
    // 调用频度约束（#17 教训）：原本只在每拍（动画上升沿/第二拍 timer）调用；
    // 条目 47 起新增"每帧"调用点——特效跟随枪口的 FollowTick（条目 48 起
    // hull 模式每 follower 每帧 2 次，fallback 单点仍 1 次；≤4 次值类型
    // Variant/帧，非堆分配 × 仅特效存活期 ≤0.3s 挂载 + 无 follower 即摘钩，
    // 频度论证见 RegisterFollower 处，风险受控）。
    // String/PackedArray/Object 等非平凡 Variant 的高频调用仍然禁止。
    private static Vector2? LocalToWorld(GodotObject bone, Vector2 local)
    {
        try
        {
            var v = bone.Call("local_to_world", local);
            if (v.VariantType != Variant.Type.Vector2) return null;
            return v.AsVector2();
        }
        catch { return null; }
    }

    // dir_source=="facing" 的兜底方向：枪管仰角 barrel_deg（=-10.18°，
    // muzzle_dir=(0.984,-0.177) 反解），facing 承担水平镜像
    private Vector2 FallbackDir(float facing)
    {
        if (_dirSource == "facing")
        {
            float b = Mathf.DegToRad(_barrelDeg);
            return new Vector2(facing * Mathf.Cos(b), Mathf.Sin(b)).Normalized();
        }
        return new Vector2(facing, 0f);
    }

    // 降级告警（每 watcher 一次性）：一级 local_to_world 不可用时留痕
    private void WarnDirSrc(string tag, string src)
    {
        if (_dirSrcWarned) return;
        _dirSrcWarned = true;
        DyeFramework.Log($"attack fx: WARN dirsrc={src} ({tag}) —— 骨架 local_to_world 不可用，已沿降级链取方向");
    }

    // --- 条目 52：dir_rot_fix 注入（δ 手工校准）--------------------------
    // 把 dir 屏上角追加旋转 _dirRotFixDeg 度。δ 的候选来源（条目 51 定性）：
    // ① SpineSprite 节点链 GlobalTransform rotation/skew（C# dir 与 wr 均为
    //    骨架空间、渲染含节点旋转）；② MegaSpine 原生 mesh 渲染管线附加变换。
    // 两者都是标量旋转差 → 共用一键。=0 时直接原样返回（逐位现状）。
    private Vector2 DirFix(Vector2 dir)
        => _dirRotFixDeg == 0f ? dir : dir.Rotated(Mathf.DegToRad(_dirRotFixDeg));

    // SpineSprite 解析（条目 52 诊断）：从 n2（含自身）向下 BFS 找第一个
    // 原生类名为 SpineSprite 的节点。仅出生时（RegisterFollower）调用一次，
    // 非每帧——#17 频度纪律不受影响；GetChildren 返回的 Array<Node> 为
    // 一次性分配，出生瞬时开销可忽略。缓存的节点引用与 _target 同生命周期
    // （SpineSprite 是角色视觉树一员），失效由 tick1 打印处 IsInstanceValid 兜底。
    private static Node2D FindSpineSprite(Node2D from)
    {
        try
        {
            var q = new System.Collections.Generic.Queue<Node>();
            q.Enqueue(from);
            while (q.Count > 0)
            {
                var n = q.Dequeue();
                if (n is Node2D nd && nd.GetClass() == "SpineSprite") return nd;
                foreach (var c in n.GetChildren()) q.Enqueue(c);
            }
        }
        catch { /* contained：诊断解析失败不影响特效主链路 */ }
        return null;
    }

    // 枪口基点 + 枪管方向统一解析（第一拍/第二拍同口径）。三级降级链：
    //   1) local_to_world 两点差分（默认）：p0=枪口尖、p1=沿枪管再走 100
    //      骨架单位 → dirSkel=(p1-p0).Normalized()（单位无关，根修）
    //   2) get_global_transform → Transform2D：BasisXform 同构两点差分
    //      （SpineBone::get_global_transform 已在 dll strings 核实在册）
    //   3) 原公式但必须 DegToRad 单位修正（参考同文件影子层 L2698 正确写法
    //      `_obliqueDeg * Mathf.Pi / 180f`）
    //      dir 退化时兜底 (facing,0)
    //   dir_source=="facing" 是强制逃生门：在取 p0 之前早退（见下方），
    //   三级降级链整体不参与，方向恒为 FallbackDir 的 barrel_deg 枪管角
    // 坐标映射保持 #13 口径：×本节点 Scale（骨骼 getter=节点系坐标）。
    // ×sc 线性映射天然处理镜像——节点负 Scale.X 时 p0/dir 的 X 分量随
    // sc.X 一起翻转，条目 42 的"sin(wr) 不镜像"TODO 就此关闭（问题随
    // R(wr) 手工旋转式一起退役）。
    // 返回 (gpos, dir, wr, src)：wr 仅留作日志诊断（度），绝不进三角函数。
    private (Vector2 gpos, Vector2 dir, float wr, string src) ResolveMuzzle(
        GodotObject bone, Node2D n2, float facing, string tag)
    {
        float wr = 0f;
        try { wr = bone.Call("get_world_rotation_x").AsSingle(); }
        catch { /* contained */ }
        var sc = n2.Scale;
        // 骨骼本地系基点/轴向：muzzle_offset/muzzle_dir 真值键；缺键回退
        // muzzle_len 沿骨骼 +X 前移（旧行为语义等价）
        var offset = _muzzleOffset != null
            ? new Vector2(_muzzleOffset[0], _muzzleOffset[1])
            : new Vector2(_muzzleLen, 0f);
        var mdir = _muzzleDir != null
            ? new Vector2(_muzzleDir[0], _muzzleDir[1])
            : new Vector2(1f, 0f);

        // dir_source=="facing"：枪管角强制逃生门（A⑤ 必修）。必须放在取 p0
        // 之前——原先只在 dir 退化时才调 FallbackDir，一级 local_to_world 一旦
        // 成功就短路返回骨架方向，barrel_deg 完全不参与，注释宣称的"强制"
        // 名存实亡。此处早退后连三号 getter 都不再调用，配置语义=真强制。
        // 注：WarnDirSrc 在此处的语义是"已按 config 强制跳过骨架 getter"，
        // 并非 getter 故障（同一行一次性告警，借 warned 位去重）。
        if (_dirSource == "facing")
        {
            WarnDirSrc(tag, "facing");
            // 条目 52：dir_rot_fix 对强制枪管角同样生效（δ 与方向来源无关，
            // 是渲染系的恒定旋转差）
            return (n2.GlobalPosition + new Vector2(offset.X * sc.X, offset.Y * sc.Y),
                    DirFix(FallbackDir(facing)), wr, "facing");
        }

        // 条目 48：hull 两点差分优先（muzzle_hull 存在且一级可用）——轴两点取
        // hull 本尊 F（前端中点=枪口尖）与 Rk（后端中点），dir=(WF-WR) 归一。
        // 与旧式（offset / offset+mdir×100）的本质区别：mdir 是 config 里的
        // 单位向量（几何真值来源还是错误的 qiang02 hull），而 hull 两点是
        // attack 实际附件 zero_qiang_C2+deform 的端点——方向与位置同源同一份
        // 几何，出生 dir 与枪管天然共线（光束方向问题的第一股偏差 -5.08° 根治）。
        if (_muzzleHull != null)
        {
            var hullF = new Vector2(_muzzleHull[0], _muzzleHull[1]);
            var hullR = new Vector2(_muzzleHull[2], _muzzleHull[3]);
            var pF = LocalToWorld(bone, hullF);
            var pR = LocalToWorld(bone, hullR);
            if (pF != null && pR != null)
            {
                var dv = pF.Value - pR.Value;
                // sc 非均匀时先乘再归一（#13 口径：骨骼 getter=节点系坐标）
                var dirS = new Vector2(dv.X * sc.X, dv.Y * sc.Y);
                var dir = dirS.LengthSquared() > 1e-6f ? dirS.Normalized() : FallbackDir(facing);
                return (n2.GlobalPosition + new Vector2(pF.Value.X * sc.X, pF.Value.Y * sc.Y),
                        DirFix(dir), wr, "hull_2pt");
            }
            // hull 一级失败 → 落到下方旧降级链（mdir 路径），不额外告警
            // （WarnDirSrc 每 watcher 一次的位由降级链自己打）
        }

        // 一级：local_to_world 两点差分（默认；muzzle_hull 缺失时的 fallback）
        var p0 = LocalToWorld(bone, offset);
        var p1 = LocalToWorld(bone, offset + mdir * 100f);
        if (p0 != null && p1 != null)
        {
            var d = p1.Value - p0.Value;
            var dirS = new Vector2(d.X * sc.X, d.Y * sc.Y);
            var dir = dirS.LengthSquared() > 1e-6f ? dirS.Normalized() : FallbackDir(facing);
            return (n2.GlobalPosition + new Vector2(p0.Value.X * sc.X, p0.Value.Y * sc.Y),
                    DirFix(dir), wr, "local_to_world");
        }

        // 二级：get_global_transform → Transform2D 两点差分
        try
        {
            var vt = bone.Call("get_global_transform");
            if (vt.VariantType == Variant.Type.Transform2D)
            {
                var t = vt.AsTransform2D();
                var q0 = t.Origin + t.BasisXform(offset);
                var q1 = t.Origin + t.BasisXform(offset + mdir * 100f);
                var d = q1 - q0;
                var dirS = new Vector2(d.X * sc.X, d.Y * sc.Y);
                var dir = dirS.LengthSquared() > 1e-6f ? dirS.Normalized() : FallbackDir(facing);
                WarnDirSrc(tag, "global_transform");
                return (n2.GlobalPosition + new Vector2(q0.X * sc.X, q0.Y * sc.Y),
                        DirFix(dir), wr, "global_transform");
            }
        }
        catch { /* contained */ }

        // 三级：原公式 + DegToRad 单位修正（wr 是度——旧代码漏这步即根因）
        float rad = Mathf.DegToRad(wr);
        float cx = Mathf.Cos(rad), sn = Mathf.Sin(rad);
        var r0 = new Vector2(cx * offset.X - sn * offset.Y, sn * offset.X + cx * offset.Y);
        var rl = new Vector2(cx * mdir.X - sn * mdir.Y, sn * mdir.X + cx * mdir.Y);
        var dirL = new Vector2(rl.X * sc.X, rl.Y * sc.Y);
        bool degen = dirL.LengthSquared() <= 1e-6f;
        var dir3 = degen ? FallbackDir(facing) : dirL.Normalized();
        WarnDirSrc(tag, degen ? "facing" : "deg_to_rad");
        return (n2.GlobalPosition + new Vector2(r0.X * sc.X, r0.Y * sc.Y), DirFix(dir3), wr,
                degen ? "facing" : "deg_to_rad");
    }

    // --- 条目 47：特效跟随枪口（用户反馈①"特效烘焙在原位，没有随枪口移动"）---
    // 设计：streak/flash 的 holder 在生命周期内每帧重算枪口世界坐标并更新
    // GlobalPosition；旋转与局部偏移保持出生时刻的 Dir0 不变——光束方向在
    // 开火瞬间已定，符合物理直觉，且避免跟随期方向抖动。
    // muzzleTipWorld(t) 复用 ResolveMuzzle 第一级 local_to_world 语义：
    //   tip = n2.GlobalPosition + (p0.X×sc.X, p0.Y×sc.Y)
    // 为避免每帧走三级降级，出生时解析一次并缓存 bone+LocalOffset+Sc；
    // 跟随期间解析失败/骨骼失效 → 立即降级为不跟随（特效保持最后位置自然
    // 消亡），异常全部就地吞掉，绝不抛到游戏。
    //
    // 调用频度论证（#17 教训，写在实现处便于审计；条目 48 更新）：
    //   · 数量上限：每拍最多 2 个 follower（streak holder + flash holder；
    //     sparks 不登记——粒子是飞散弹道，物理上不该跟随）；
    //   · 每帧开销：hull 模式每 follower 2 次 LocalToWorld（SpineBone::local_to_world
    //     返回 Vector2 Variant——值类型内联，非 String/PackedArray/Object 堆分配）
    //     + 1 次 Node2D.GlobalPosition 读取（同为 Vector2 值类型），合计 ≤4 次值
    //     类型 Variant 原生调用/帧（2 follower×2 次），无堆分配；fallback 单点
    //     模式仍是 1 次/follower（≤2 次/帧）；
    //   · 挂载时长：仅特效存活期（streak life 0.2s、flash ≤0.2s + 0.1 余量），
    //     超时即摘；无 follower 时立即摘钩，帧回调开销归零；
    //   · 对照 #17 事故（_Process 全量粒子循环 × 每粒子多次非平凡 Variant），
    //     本路径频度/分配量级低 3 个数量级（且全部是值类型 Variant），风险受控。

    // 枪口本地偏移（与 ResolveMuzzle 同口径：真值键缺省回退 muzzle_len 沿 +X）
    private Vector2 MuzzleLocalOffset()
        => _muzzleOffset != null
            ? new Vector2(_muzzleOffset[0], _muzzleOffset[1])
            : new Vector2(_muzzleLen, 0f);

    // 出生登记（EmitStreakSprite/EmitFlashSprite 成功创建 holder 后调用）。
    // 出生时解析一次：一级 local_to_world 可用才登记跟随；失败=降级不跟随
    // （保持现状行为，特效固定在出生点）。ExpiresAt = now + life + 0.1 余量
    // （flash 的每片独立随机寿命已在调用处折算成 maxLife 传入）。
    private void RegisterFollower(Node2D holder, Node2D n2, GodotObject bone,
        string kind, Vector2 dir0, float offX, float comp, double life)
    {
        // bone 空守卫（第二拍 timer 路径 b2 可能为 null 传入 Burst）
        if (bone == null)
        {
            DyeFramework.Log($"attack fx: track=dropped kind={kind} bone={_boneName} —— 锚骨缺失，特效固定在出生点");
            return;
        }
        if (!_trackMuzzle)
        {
            DyeFramework.Log($"attack fx: track=off kind={kind} bone={_boneName} —— config track_muzzle=false，特效固定在出生点");
            return;
        }
        var localOffset = MuzzleLocalOffset();
        bool facingMode = _dirSource == "facing";
        // 条目 48：hull 模式校验——两点各做一次 L2W 探测（出生一次性，非每帧）。
        // （条目 49 注：此处仍可用出生时传入的 bone——fire/burst 时刻的新鲜解析
        //  已被证明是活值；不可靠的是把它跨帧持有到 FollowTick。）
        Vector2? hullF = null, hullR = null;
        if (_muzzleHull != null && !facingMode)
        {
            hullF = LocalToWorld(bone, new Vector2(_muzzleHull[0], _muzzleHull[1]));
            hullR = LocalToWorld(bone, new Vector2(_muzzleHull[2], _muzzleHull[3]));
            if (hullF == null || hullR == null)
            {
                hullF = hullR = null; // 两点探测失败 → 退回旧单点跟随
                DyeFramework.Log($"attack fx: track=downgraded kind={kind} bone={_boneMuzzleName} —— hull 两点 L2W 不可用，退回单点跟随（旋转不跟随）");
            }
        }
        if (!facingMode && hullF == null && LocalToWorld(bone, localOffset) == null)
        {
            DyeFramework.Log($"attack fx: track=dropped kind={kind} bone={_boneName} —— 出生时 local_to_world 不可用，特效固定在出生点");
            return;
        }
        _followers.Add(new MuzzleFollower
        {
            Holder = holder,
            N2 = n2,
            // 条目 49：只存骨名，跟随期每帧 get_skeleton→find_bone 重解析
            // （根因与 #17 豁免论证见 MuzzleFollower 类头注）
            BoneName = string.IsNullOrEmpty(_boneMuzzleName) ? _boneName : _boneMuzzleName,
            LocalOffset = localOffset,
            // 条目 48：hull 两点（骨骼本地系）——FollowTick 每帧差分求 dir(t)
            LocalF = hullF != null ? new Vector2(_muzzleHull![0], _muzzleHull[1]) : default,
            LocalB = hullR != null ? new Vector2(_muzzleHull![2], _muzzleHull[3]) : default,
            IsHull = hullF != null,
            Sc = n2.Scale,
            Dir0 = dir0,
            OffX = offX,
            ScaleMul = _scale,
            Comp = comp,
            ExpiresAt = Time.GetTicksMsec() / 1000.0 + life + 0.1,
            Kind = kind,
            FacingMode = facingMode,
            // 条目 52：出生时解析一次 SpineSprite 渲染节点（诊断用，非主链路；
            // 解析失败=null，tick1 打印 sprrot=none）
            SprNode = FindSpineSprite(n2),
        });
        // 出生日志：每拍一次（可接受），不加每帧日志。hull 模式追加 dir 初值
        // （=出生时刻两点差分的实时方向，验收锚点之一）
        DyeFramework.Log($"attack fx: track=on kind={kind} bone={_boneMuzzleName} hull={hullF != null} dir0={dir0} dir0deg={Mathf.RadToDeg(dir0.Angle()):0.#}");
        if (_dirRotFixDeg != 0f && !_dirFixLogged)
        {
            _dirFixLogged = true;
            DyeFramework.Log($"attack fx: dir_rot_fix={_dirRotFixDeg:0.##}deg 已生效（条目 52 δ 手工注入，值来源=运行时 hook 日志对账）");
        }
        EnsureFrameHook();
    }

    // per-frame 钩子：本 assembly 无 source generator（Node 生命周期重写不被
    // 注册），改挂 SceneTree.ProcessFrame 引擎信号——挂上即每帧回调，语义与
    // "_Process 每帧执行"等价（anim-name 轮询的 0.05s 节流门在 _poll Timer 上，
    // 跟随更新在节流门之外，独立每帧跑）。
    private void EnsureFrameHook()
    {
        if (_frameHooked) return;
        var tree = _target.GetTree();
        if (tree == null) return;
        tree.ProcessFrame += FollowTick;
        _hookedTree = tree;
        _frameHooked = true;
    }

    private void UnhookFrame()
    {
        if (!_frameHooked) return;
        if (_hookedTree != null && GodotObject.IsInstanceValid(_hookedTree))
            _hookedTree.ProcessFrame -= FollowTick;
        _hookedTree = null;
        _frameHooked = false;
    }

    private void FollowTick()
    {
        // 守卫0：目标/watcher 失效 → 全清 + 摘钩（列表里的 bone GodotObject
        // 引用随之失效，防悬挂）
        if (!GodotObject.IsInstanceValid(_target))
        {
            _followers.Clear();
            UnhookFrame();
            return;
        }
        if (_followers.Count == 0)
        {
            UnhookFrame();
            return;
        }
        double now = Time.GetTicksMsec() / 1000.0;
        for (int i = _followers.Count - 1; i >= 0; i--)
        {
            var f = _followers[i];
            // 守卫1：holder 失效（Tween 完成回调/FreeLater 已回收）→ 仅移除
            // follower，绝不再碰节点。回收职责仍在既有 Tween 回调 + FreeLater，
            // follower 只管位置。
            // 条目 52：一次性回收日志——定案"孤儿光束滞留屏上"疑点（条目 49/51
            // 两张打回截图均摄于末次攻击后数分钟，需排除上一攻击残留干扰测角）。
            if (!GodotObject.IsInstanceValid(f.Holder))
            {
                DyeFramework.Log($"attack fx: follower recycled kind={f.Kind} —— holder 已被 Tween 回调/FreeLater 回收，follower 注销");
                _followers.RemoveAt(i); continue;
            }
            // 守卫2：超时（回收仍由既有 Tween 回调 + FreeLater 负责）
            // 条目 52：过期日志同上——expired 时刻 holder 可能仍在屏（余 0.3s），
            // 该日志给出"跟随结束/视觉消亡"的时序锚点。
            if (now > f.ExpiresAt)
            {
                DyeFramework.Log($"attack fx: follower expired kind={f.Kind} —— 跟随超时注销（holder 交既有 Tween/FreeLater 路径回收）");
                _followers.RemoveAt(i); continue;
            }
            // 守卫3（条目 49 改）：不再持跨帧 bone 对象做 IsInstanceValid 守卫——
            // 取证实锤该对象在出生后失效/陈旧（光束冻结在出生角，见类头注），
            // 改为每帧 get_skeleton→find_bone 重解析；解析失败才降级移除。
            if (!f.FacingMode && string.IsNullOrEmpty(f.BoneName)) { _followers.RemoveAt(i); continue; }
            if (f.FacingMode)
            {
                // facing 模式与 ResolveMuzzle 同式：骨架 getter 不参与
                var tipF = f.N2.GlobalPosition
                         + new Vector2(f.LocalOffset.X * f.Sc.X, f.LocalOffset.Y * f.Sc.Y);
                f.Holder.GlobalPosition = f.Kind == "flash"
                    ? tipF + f.Dir0 * (f.OffX * f.ScaleMul * f.Comp)
                    : tipF;
                continue;
            }
            // 条目 49：每帧重解析锚骨（fire/burst 时刻的新鲜解析已被证明读到
            // 活值；持有的包装对象跨帧不可靠——根因取证见 MuzzleFollower 类头注）
            GodotObject boneNow = null;
            try
            {
                var skelNow = _target.Call("get_skeleton").AsGodotObject();
                boneNow = skelNow?.Call("find_bone", f.BoneName).AsGodotObject();
            }
            catch { boneNow = null; } // contained：骨架瞬时不可用按失效处理
            if (boneNow == null) { _followers.RemoveAt(i); continue; }
            // --- 条目 48：hull 两点差分 + 旋转跟随 ---
            // 每帧 2 次 local_to_world（Vector2 值类型 Variant，非堆分配）：
            // F=枪管轴前端中点（枪口尖）、Rk=后端中点；dir(t)=normalize((WF-WR)×sc
            // 逐分量先乘再归一，与 ResolveMuzzle 同口径）。位置钉 WF；旋转每帧
            // 更新——UE 原版语义对齐：发射器挂枪口 socket，位置+旋转全程跟随
            // （替换条目 47 的"Dir0 出生锁定"设计，取证见字段区注释/主日志 48②）。
            if (f.IsHull)
            {
                var pF = LocalToWorld(boneNow, f.LocalF);
                var pR = LocalToWorld(boneNow, f.LocalB);
                // 守卫4：任一点解析失败 → 降级移除，不抛异常到游戏
                if (pF == null || pR == null) { _followers.RemoveAt(i); continue; }
                var wf = f.N2.GlobalPosition
                         + new Vector2(pF.Value.X * f.Sc.X, pF.Value.Y * f.Sc.Y);
                var dv = pF.Value - pR.Value;
                var dirS = new Vector2(dv.X * f.Sc.X, dv.Y * f.Sc.Y);
                if (dirS.LengthSquared() > 1e-6f)
                {
                    // 条目 52：dir_rot_fix 追加旋转（跟随期与 ResolveMuzzle 出生式
                    // 同口径——hull 模式下 Rotation 每帧被本处覆盖，出生式注入
                    // 若不在此处同步注入则会被逐帧冲掉）
                    var dirT = DirFix(dirS.Normalized());
                    f.Holder.GlobalPosition = wf;
                    // streak：贴图长轴=局部 +Y，Rotation = dir-π/2；flash：长轴=+X，
                    // Rotation = dir（与各自 Emit*Sprite 出生式一致，只改为每帧）
                    f.Holder.Rotation = f.Kind == "flash"
                        ? dirT.Angle()
                        : dirT.Angle() - Mathf.Pi / 2f;
                }
                // 条目 49→52：首帧跟随诊断（每 follower 一次，频度合规）。
                // 52 升级：恒等≠冻结（条目 51② 判据改写——保持段骨骼本就静止，
                // 跟随存活的正确判据=光束角随回摆段偏离 dir0deg），本行改承
                // δ 定案职责：全部为值类型读取（float/Vector2 + 一次 wr 值类型
                // Variant），打印节点链/渲染节点/骨架三层旋转对账 δ 来源。
                //   n2rot  = _target GlobalRotation（含全部祖先层旋转；C# dir/wr
                //            均为骨架空间不含节点旋转——嫌疑①的直接观测量）
                //   sprrot = SpineSprite 渲染节点 GlobalRotation（出生时解析缓存，
                //            IsInstanceValid 兜底；sprrot−n2rot=渲染节点自身局部旋转）
                //   n2gs   = _target GlobalScale（排除 skew/非均匀缩放混杂）
                //   wr     = 锚骨世界旋转（度，骨架空间基准）；fix=当前注入值
                if (!f.FollowLogged)
                {
                    f.FollowLogged = true;
                    float wrT1 = 0f;
                    try { wrT1 = boneNow.Call("get_world_rotation_x").AsSingle(); }
                    catch { /* contained：诊断字段缺失不阻塞主链路 */ }
                    var d1 = dirS.LengthSquared() > 1e-6f ? DirFix(dirS.Normalized()) : f.Dir0;
                    string sprrot = f.SprNode != null && GodotObject.IsInstanceValid(f.SprNode)
                        ? f.SprNode.GlobalRotationDegrees.ToString("0.#") : "none";
                    DyeFramework.Log($"attack fx: tick1 kind={f.Kind} dir0deg={Mathf.RadToDeg(f.Dir0.Angle()):0.#} " +
                                     $"dirdeg={Mathf.RadToDeg(d1.Angle()):0.#} wr={wrT1:0.#} " +
                                     $"n2rot={f.N2.GlobalRotationDegrees:0.#} sprrot={sprrot} " +
                                     $"n2gs={f.N2.GlobalScale} fix={_dirRotFixDeg:0.##}");
                }
                // 方向退化（两点重合，理论不可达）→ 只保持上一帧位姿，不误杀
                continue;
            }
            // 每帧 1 次 local_to_world（Vector2 值类型 Variant，频度论证见上）
            var p = LocalToWorld(boneNow, f.LocalOffset);
            // 守卫4：解析失败 → 降级移除，不抛异常到游戏
            if (p == null) { _followers.RemoveAt(i); continue; }
            var tip = f.N2.GlobalPosition
                      + new Vector2(p.Value.X * f.Sc.X, p.Value.Y * f.Sc.Y);
            // 非 hull fallback：条目 47 行为——位置跟随，旋转保持出生 Dir0 锁定
            f.Holder.GlobalPosition = f.Kind == "flash"
                ? tip + f.Dir0 * (f.OffX * f.ScaleMul * f.Comp)
                : tip;
        }
    }

    // 标量 float 读取（仅接受数值键）
    private static float Num(Godot.Collections.Dictionary d, string key, float def)
        => d.TryGetValue(key, out var v) && v.VariantType != Variant.Type.Array
            ? (float)v.AsDouble() : def;

    // 标量或数组 flex 读取（数组取末元素=上限；兼容旧 config life:[min,max]）
    private static float NumFlex(Godot.Collections.Dictionary d, string key, float def)
    {
        if (!d.TryGetValue(key, out var v)) return def;
        if (v.VariantType == Variant.Type.Array)
        {
            var a = v.AsGodotArray();
            return a.Count > 0 ? (float)a[a.Count - 1].AsDouble() : def;
        }
        return (float)v.AsDouble();
    }

    // float[2] 读取（单元素视为 min=max）
    private static float[] Arr2(Godot.Collections.Dictionary d, string key, float d0, float d1)
    {
        if (d.TryGetValue(key, out var v) && v.VariantType == Variant.Type.Array)
        {
            var a = v.AsGodotArray();
            if (a.Count >= 2) return new[] { (float)a[0].AsDouble(), (float)a[1].AsDouble() };
            if (a.Count == 1) return new[] { (float)a[0].AsDouble(), (float)a[0].AsDouble() };
        }
        return new[] { d0, d1 };
    }

    // RGBA 颜色读取（3 元素 alpha=1，4 元素含 alpha）
    private static Color ColRgba(Godot.Collections.Dictionary d, string key, Color def)
    {
        if (!d.TryGetValue(key, out var v) || v.VariantType != Variant.Type.Array) return def;
        var a = v.AsGodotArray();
        if (a.Count >= 4)
            return new Color((float)a[0].AsDouble(), (float)a[1].AsDouble(), (float)a[2].AsDouble(), (float)a[3].AsDouble());
        return a.Count == 3
            ? new Color((float)a[0].AsDouble(), (float)a[1].AsDouble(), (float)a[2].AsDouble(), 1f)
            : def;
    }

    // Curve 构造（参数 = t0,v0,t1,v1,...；只在每拍一次性段调用，不进 _Process）
    private static Curve MakeCurve(params float[] tv)
    {
        var c = new Curve();
        for (int i = 0; i + 1 < tv.Length; i += 2)
            c.AddPoint(new Vector2(tv[i], tv[i + 1]));
        return c;
    }

    // UE AccelerationDrag（指数衰减 dv/dt=-k·v）→ Godot Damping（线性 dv/dt=-d）
    // 位移等效换算：UE 生命 L 内位移 = v0·(1-e^{-kL})/k；Godot 位移 = v0·L-d·L²/2。
    // 令二者相等解出 d = 2·v0·(L-(1-e^{-kL})/k)/L²（修复原 ×40/×60 拍脑袋系数）。
    private static float DragToDamping(float k, float life, float v0)
    {
        if (k <= 0.0001f || life <= 0.0001f) return 0f;
        return 2f * v0 * (life - (1f - Mathf.Exp(-k * life)) / k) / (life * life);
    }

    // 面积熔断：单次发射覆盖面积 amount×max_size² 超过 1280x720 的 30% 拒发
    private bool BreakerTripped(string kind, float amount, float maxSizePx)
    {
        float budget = 1280f * 720f * 0.3f;
        float area = amount * maxSizePx * maxSizePx;
        if (area <= budget) return false;
        GD.Print($"attack fx: breaker tripped kind={kind} amount={amount:0} max_size={maxSizePx:0}px area={area:0} budget={budget:0}");
        return true;
    }

    private static Color Col(Godot.Collections.Dictionary d, string key, Color def)
    {
        if (!d.TryGetValue(key, out var v) || v.VariantType != Variant.Type.Array) return def;
        var a = v.AsGodotArray();
        return a.Count >= 3
            ? new Color((float)a[0].AsDouble(), (float)a[1].AsDouble(), (float)a[2].AsDouble())
            : def;
    }

    public void Activate()
    {
        _poll = new Timer { WaitTime = 0.05, Autostart = true };
        AddChild(_poll);
        _poll.Timeout += Poll;
    }

    private string CurrentAnimName()
    {
        var st = _target.Get("animation_state").AsGodotObject()
                 ?? _target.Call("get_animation_state").AsGodotObject();
        var ao = st?.Call("get_current", 0).AsGodotObject()?.Call("get_animation").AsGodotObject();
        return ao != null ? ao.Call("get_name").AsString() : "";
    }

    private void Poll()
    {
        try
        {
            if (!GodotObject.IsInstanceValid(_target))
            {
                // 条目 47：watcher 随目标失效而回收时，同步清空跟随登记表并
                // 摘除 per-frame 钩子（列表里存有 bone 的 GodotObject 引用，
                // 防悬挂；FollowTick 内亦有 IsInstanceValid 双保险）
                _followers.Clear();
                UnhookFrame();
                _poll?.QueueFree();
                _poll = null;
                QueueFree();
                return;
            }
            var name = CurrentAnimName();
            if (name != _prevAnim && System.Array.IndexOf(_anims, name) >= 0)
                Fire();
            _prevAnim = name;
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] attack fx poll error (contained): " + e.Message);
        }
    }

    private void Fire()
    {
        try
        {
            var skel = _target.Call("get_skeleton").AsGodotObject();
            // 条目 48：跟随骨解析链——muzzle_bone（构建期从 ling.json slots 段解析
            // qiang02 槽位绑定骨写入，见 build_lingchar.py）优先；空/缺=回退 config
            // bone（bone104，既有 fallback）。muzzle_bone 非空但 find_bone 失败
            // （骨架改版/改名）→ 回退 _boneName 并打一次性 WARN。
            string wantBone = string.IsNullOrEmpty(_muzzleBoneCfg) ? _boneName : _muzzleBoneCfg;
            var bone = skel?.Call("find_bone", wantBone).AsGodotObject();
            if (bone == null && wantBone != _boneName)
            {
                DyeFramework.Log($"attack fx: WARN muzzle_bone={wantBone} 解析失败，回退 bone={_boneName}（跟随骨回退）");
                wantBone = _boneName;
                bone = skel?.Call("find_bone", _boneName).AsGodotObject();
            }
            _boneMuzzleName = wantBone;
            if (bone == null || _target is not Node2D n2) return;
            // skeleton -> parent mapping. spine-godot's bone world getters
            // return NODE-convention coords (y-down, facing-flipped) - proven
            // by muzzle logs: negating them put the muzzle below the floor.
            // （条目 44 TODO 关闭：原"节点负 Scale.X 翻转场景下 sin(wr) 不
            // 镜像"的 TODO 随 R(wr) 手工旋转式一起退役——×sc 线性映射天然
            // 处理镜像，见 ResolveMuzzle 注释。）
            // facing 源（条目 42）：STS2 无原生 spine flip（C# 绑定六方法白名单
            // + dll 二进制零 flip 命中），游戏约定=节点 Scale.X 取负
            // （SurroundedPower.FlipScale/NRestSiteCharacter.FlipX/PunchOff.cs:73）。
            // GlobalScale 捕获任意祖先层负号；骨骼 getter=节点系坐标（#13 结论），
            // 坐标映射仍用本节点 Scale。
            float facing = Mathf.Sign(n2.GlobalScale.X == 0f ? 1f : n2.GlobalScale.X);
            // 条目 44：基点/方向统一走 ResolveMuzzle（度当弧度根修 + 三级降级）
            var (gpos, dir, wr, dirSrc) = ResolveMuzzle(bone, n2, facing, "shot1");
            // 条目 48：bone= 改为实际跟随骨名（muzzle_bone 解析链结论），dir= 即
            // 出生时刻实时采样值（hull 模式=两点差分，与枪管共线）
            DyeFramework.Log($"attack fx: muzzle_gpos={gpos} facing={facing} sc={n2.Scale} dir={dir} dirdeg={Mathf.RadToDeg(dir.Angle()):0.#} dirsrc={dirSrc} wr={wr:0.#} bone={_boneMuzzleName}");
            int seq = ++_fireSeq;
            for (int i = 0; i < _burstTimes.Length; i++)
            {
                if (_burstTimes[i] <= 0f)
                {
                    Burst(gpos, facing, dir, bone, n2);
                }
                else
                {
                    float delay = _burstTimes[i];
                    var t = new Timer { WaitTime = delay, OneShot = true, Autostart = true };
                    DyeFramework.Tree?.Root.AddChild(t);
                    int captured = seq;
                    t.Timeout += () =>
                    {
                        // 条目 47：当前 config 为单拍（bursts=[t_fire]，重编辑
                        // 骨架动画无第二段攻击），此回调路径仅 bursts 多元素时
                        // 触发。多拍调度逻辑保留不删——数组驱动天然支持 1..N
                        // 拍，删除会扩大 diff 面与回归风险（muzzle_gpos2 同此）。
                        try
                        {
                            if (captured == _fireSeq && GodotObject.IsInstanceValid(n2))
                            {
                                // re-read the bone: the arm moves between shots
                                // （条目 48：与第一拍同骨——_boneMuzzleName 已含
                                // muzzle_bone 解析链结论，空则回退 _boneName）
                                var sk2 = _target.Call("get_skeleton").AsGodotObject();
                                var b2 = sk2?.Call("find_bone",
                                    string.IsNullOrEmpty(_boneMuzzleName) ? _boneName : _boneMuzzleName).AsGodotObject();
                                // facing 与第一拍同源：GlobalScale.X 符号（捕获
                                // 任意祖先层负号；映射仍用本节点 Scale）
                                float facing2 = Mathf.Sign(n2.GlobalScale.X == 0f ? 1f : n2.GlobalScale.X);
                                Vector2 g2 = gpos;
                                // b2==null 回退：沿用第一拍基点 + 水平方向（旧语义）
                                Vector2 dir2 = new Vector2(facing2, 0f);
                                if (b2 != null)
                                {
                                    // 条目 44：第二拍与第一拍同口径——同一个
                                    // ResolveMuzzle（度当弧度根修 + 三级降级链
                                    // 覆盖两拍），替换原 R(mr2) 弧度手算式
                                    var (gp2, d2, wr2, src2) = ResolveMuzzle(b2, n2, facing2, "shot2");
                                    g2 = gp2;
                                    dir2 = d2;
                                    DyeFramework.Log($"attack fx: muzzle_gpos2={g2} facing2={facing2} dir2={dir2} dir2deg={Mathf.RadToDeg(dir2.Angle()):0.#} dirsrc={src2} wr2={wr2:0.#} bone={_boneName}");
                                }
                                Burst(g2, facing2, dir2, b2, n2);
                            }
                        }
                        catch { /* contained */ }
                        t.QueueFree();
                    };
                }
            }
            // freeze triage (2026-10-02): a hard main-thread freeze once landed
            // within ~1s after the muzzle log - mark the burst section as done
            DyeFramework.Log("attack fx: bursts scheduled");
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] attack fx error (contained): " + e.Message);
        }
    }

    // 条目 43：签名链加 dir（枪管轴单位向量，屏幕系）——三个 Emit* 透传；
    // legacy 路径不感知 dir（BurstLegacy 签名不变）。
    // 条目 47：签名再加 bone/n2（跟随枪口需要出生时解析一次锚骨）——
    // 仅 sprite 路线的 EmitStreakSprite/EmitFlashSprite 使用，particles
    // 路线与 sparks 不感知（sparks 不登记跟随：粒子是飞散弹道，物理上
    // 不该跟随枪口；particles 旧路线为回退保留，不加跟随）。
    private void Burst(Vector2 gpos, float facing, Vector2 dir, GodotObject bone, Node2D n2)
    {
        var parent = _target.GetParent();
        if (parent == null) return;
        if (!_truePipeline)
        {
            BurstLegacy(gpos, facing);
            return;
        }
        // 缩放补偿（A 档条目30）：0.29 是 _target（Visuals 层）自身缩放；
        // 发射器挂 parent 层（实测 gscale=1.0 → comp=1，即"config=屏幕 px"
        // 语义成立）。comp = 1/父链全局缩放，每拍用探针节点实测（不硬编码），
        // 一次性诊断日志。
        var probe = new Node2D();
        parent.AddChild(probe);
        float gsx = Mathf.Abs(probe.GlobalScale.X);
        float comp = gsx > 0.001f ? 1f / gsx : 1f;
        probe.QueueFree();
        if (!_gscaleLogged)
        {
            _gscaleLogged = true;
            DyeFramework.Log($"attack fx: parent gscale={gsx:0.####} comp={comp:0.##}");
        }
        // 条目 45：单发射器开关（sparks/streak/flash.enabled，bool，缺键=true）。
        // 用途=用户二分判别（E2 实验：关某路特效复拍，定位"画面里的线"是否
        // 归属 attack_fx）+ 运维逃生门。分发处统一跳过：streak 关=本体+halo
        // 一起关（两层都在 EmitStreak* 内）；flash 关=3 片全关（循环在
        // EmitFlash* 内）。缺键=true → silent/legacy 与旧 config 零影响。
        // 只在每拍 Burst 调用（低频），#17 合规（禁高频循环调原生方法）。
        bool sparkOn = _sparksCfg.TryGetValue("enabled", out var spEn) ? spEn.AsBool() : true;
        bool streakOn = _streakCfg.TryGetValue("enabled", out var stEn) ? stEn.AsBool() : true;
        bool flashOn = _flashCfg.TryGetValue("enabled", out var flEn) ? flEn.AsBool() : true;
        if (sparkOn)
            EmitSparks(parent, gpos, facing, comp, dir);
        // 条目 44：streak/flash 双路线——mode=="sprite"（默认）走 Sprite2D
        // 面片（贴图长轴即方向，无 align_y 初速载体依赖、渐变形状由纹理
        // 自带）；mode=="particles" 走旧 CPUParticles2D 路径（EmitStreak/
        // EmitFlash 原样保留为回退）。sparks 无 sprite 路线（一行不动）。
        string streakMode = _streakCfg.TryGetValue("mode", out var smv) ? smv.AsString() : "sprite";
        if (streakOn)
        {
            if (streakMode == "particles") EmitStreak(parent, gpos, facing, comp, dir);
            else EmitStreakSprite(parent, gpos, facing, comp, dir, bone, n2);
        }
        string flashMode = _flashCfg.TryGetValue("mode", out var fmv) ? fmv.AsString() : "sprite";
        if (flashOn)
        {
            if (flashMode == "particles") EmitFlash(parent, gpos, facing, comp, dir);
            else EmitFlashSprite(parent, gpos, facing, comp, dir, bone, n2);
        }
    }

    // 火花：fr_obj_901_3x3 3×3 网格纹理 SubUV（条目 42：方形网格，单帧内容
    // 拉伸铺满 quad；转储真值：sphere r=7.25px、speed
    // 203-435px/s、drag=7、life 0.1、蓝紫两极随机 + fade_to 渐隐、尺寸曲线
    // 0→0.233 拉满→0.467 保持→线性落 0（转储 export[36]））
    private void EmitSparks(Node parent, Vector2 gpos, float facing, float comp, Vector2 dir)
    {
        if (string.IsNullOrEmpty(_stripTexPath) || !ResourceLoader.Exists(_stripTexPath)) return;
        float amount = Num(_sparksCfg, "amount", 3f);
        if (BreakerTripped("spark", amount, _maxSparkPx)) return;
        float life = NumFlex(_sparksCfg, "life", 0.1f);
        var spd = Arr2(_sparksCfg, "speed", 203f, 435f);
        var sz = Arr2(_sparksCfg, "size", 8f, 18f);
        // size 防糊屏钳制：单帧屏幕 px ≤ 该发射器 max_size_px（MaxSizePx
        // 构造时已钳 ≤512，此处复用即覆盖全局上限）
        sz[0] = Mathf.Min(sz[0], _maxSparkPx);
        sz[1] = Mathf.Min(sz[1], _maxSparkPx);
        float spread = Num(_sparksCfg, "spread", 14f);
        float drag = Num(_sparksCfg, "drag", 7f);
        float radius = Num(_sparksCfg, "emission_sphere_radius", 7.25f);
        float angleRandom = Num(_sparksCfg, "angle_random", 1f);
        var angVel = Arr2(_sparksCfg, "angular_velocity", -360f, 360f);
        int hFrames = Mathf.Max(1, (int)Num(_sparksCfg, "h_frames", 3f));
        int vFrames = Mathf.Max(1, (int)Num(_sparksCfg, "v_frames", 3f));
        // anim_speed 语义=每 lifetime 的 0→1 offset 循环数（UE 真值
        // SubImageIndex 0→8 / lifetime 0.1s = 每 lifetime 恰 1 循环 → 1.0）
        float animSpeed = Num(_sparksCfg, "anim_speed", 1f);

        var tex = GD.Load<Texture2D>(_stripTexPath);
        // Godot particles_animation 语义（条目 42 定案）：CanvasItemMaterial 把
        // 整张纹理按 (h,v) 切网格，单帧 uv = frame_offset + uv/(h,v) —— 单帧
        // 内容被拉伸铺满整个 quad（quad 尺寸 = 粒子 ScaleAmount×整张纹理尺寸）。
        // 因此定标基准=整图宽 texW，不是旧代码假设的"单帧宽 frameW"（旧算法
        // 除以 hFrames*vFrames 导致火花被画成 9 倍超宽横条）。方形火花要求
        // 网格纹理方形：hFrames==vFrames（3×3 对齐 fr_obj_901_3x3 源纹理）。
        float texW = Mathf.Max(1f, tex.GetWidth());
        // 纵横比守卫：非方形网格会把单帧内容拉伸变形（数学上不可修，必须换纹理）
        if (hFrames != vFrames)
            DyeFramework.Log($"attack fx: WARN sparks strip {texW}x{tex.GetHeight()} h={hFrames} v={vFrames} 非方形网格 → 单帧内容将被拉伸变形");
        var p = new CpuParticles2D
        {
            Texture = tex,
            OneShot = true,
            Explosiveness = 1f,
            Direction = dir, // 条目 43：spread 锥绕枪管轴（原恒 (facing,0) 水平）
            Gravity = Vector2.Zero,
        };
        parent.AddChild(p);
        p.Amount = Mathf.Max(1, (int)amount);
        p.Lifetime = life;
        p.Spread = spread;
        p.EmissionShape = CpuParticles2D.EmissionShapeEnum.Sphere;
        p.EmissionSphereRadius = radius * _scale * comp;
        p.InitialVelocityMin = spd[0] * _scale * comp;
        p.InitialVelocityMax = spd[1] * _scale * comp;
        // 尺寸语义=单帧屏幕 px：ScaleAmount 相对整张纹理（particles_animation
        // 下单帧内容拉伸铺满 quad），按整图宽 texW 定标（条目 42：原按 frameW
        // 定标 = 除以 hFrames*vFrames，导致火花 9 倍超宽）
        p.ScaleAmountMin = sz[0] * _scale * comp / texW;
        p.ScaleAmountMax = sz[1] * _scale * comp / texW;
        // Godot 的旋转不受父链缩放影响（角度/角速度天然屏幕语义），不补偿
        p.AngleMin = -180f * angleRandom;
        p.AngleMax = 180f * angleRandom;
        p.AngularVelocityMin = angVel[0];
        p.AngularVelocityMax = angVel[1];
        // UE AccelerationDrag k=7（指数衰减）→ 线性 Damping 位移等效换算
        float v0avg = (spd[0] + spd[1]) * 0.5f * _scale * comp;
        float damp = DragToDamping(drag, life, v0avg);
        p.DampingMin = damp;
        p.DampingMax = damp;
        // SubUV 帧数/循环属 CanvasItemMaterial（在下方材质上设置，需
        // particles_animation=true；设到 CPUParticles2D 上无效）。CPUParticles2D
        // 4.x 无单一 anim_speed 属性，播放速率由 anim_speed_min/max 驱动。
        p.AnimSpeedMin = animSpeed;
        p.AnimSpeedMax = animSpeed;
        // 条目 43：SubUV 起播相位随机（UE PSUVIM_Random 真值等价）——AnimOffset
        // 决定起播帧相位，3 粒全同相=动画步进完全同步的"塌缩感"根修（amount
        // 提到 10 后同相问题会被放大，必须随机化）
        p.AnimOffsetMin = Num(_sparksCfg, "anim_offset_min", 0f);
        p.AnimOffsetMax = Num(_sparksCfg, "anim_offset_max", 1f);
        var init = new Gradient();
        init.SetColor(0, _colA);
        init.SetColor(1, _colB);
        p.ColorInitialRamp = init;
        var ramp = new Gradient();
        ramp.SetColor(0, new Color(_colA.R, _colA.G, _colA.B, 1f));
        ramp.AddPoint(0.5f, new Color(_fadeTo.R, _fadeTo.G, _fadeTo.B, 1f));
        ramp.SetColor(1, new Color(_fadeTo.R, _fadeTo.G, _fadeTo.B, 0f));
        p.ColorRamp = ramp;
        p.ScaleAmountCurve = MakeCurve(0f, 0f, 0.2333f, 1f, 0.4667f, 1f, 1f, 0f);
        // SubUV 属性属主=CanvasItemMaterial：particles_animation 开关 + 帧
        // 数/循环都在材质上（C① 勘误：原设到 CPUParticles2D 上无效，导致
        // 九帧条带被当单帧画成 8-18px 细横线）
        p.Material = new CanvasItemMaterial
        {
            BlendMode = CanvasItemMaterial.BlendModeEnum.Add,
            ParticlesAnimation = true,
            ParticlesAnimHFrames = hFrames,
            ParticlesAnimVFrames = vFrames,
            ParticlesAnimLoop = false,
        };
        p.GlobalPosition = gpos;
        p.Emitting = true;
        FreeLater(p, life + 0.4f);
    }

    // 光条：ma_412_uv 遮罩移植（替换原 streak）。UE 真值：amount=1/拍、
    // life 0.1、初速≈0、spread 0、velocity 对齐、mesh 22x65px；scale 曲线
    // 0.5→1.0（grow）；ColorScale 20→5 泛光用 halo 分层近似（×1.6 尺寸、
    // ×0.35 alpha、同发射点，config streak.halo 可关）。
    private void EmitStreak(Node parent, Vector2 gpos, float facing, float comp, Vector2 dir)
    {
        if (string.IsNullOrEmpty(_streakTexNew) || !ResourceLoader.Exists(_streakTexNew)) return;
        float amount = Num(_streakCfg, "amount", 1f);
        bool halo = _streakCfg.TryGetValue("halo", out var hv) ? hv.AsBool() : true;
        if (BreakerTripped("streak", amount * (halo ? 2f : 1f), _maxStreakPx)) return;
        float life = Num(_streakCfg, "life", 0.1f);
        var sz = Arr2(_streakCfg, "size", 22f, 65f);
        // size 防糊屏钳制（同 sparks）
        sz[0] = Mathf.Min(sz[0], _maxStreakPx);
        sz[1] = Mathf.Min(sz[1], _maxStreakPx);
        // 条目 43：发射点前移半长——mesh 以中心锚定，不前移则光带半截埋进
        // 枪口（钳制后、发射前计算）
        var origin = gpos + dir * (sz[1] * 0.5f * _scale * comp);
        var col = ColRgba(_streakCfg, "color", new Color(0.37f, 0.85f, 1f, 1f));
        var sc = Arr2(_streakCfg, "scale_curve", 0.5f, 1f);
        float haloMul = Num(_streakCfg, "halo_size_mul", 1.6f);
        float haloAlpha = Num(_streakCfg, "halo_alpha", 0.35f);

        var tex = GD.Load<Texture2D>(_streakTexNew);
        float baseW = Mathf.Max(1, tex.GetWidth());
        // C# 粒子只能均匀缩放：纹理已归一到 22:65 长宽比，按宽度定标即得高度
        float unit = sz[0] * _scale * comp / baseW;
        // 初速=align_y 的方向载体（config streak.align_velocity 可调，默认
        // 40px/s 观感校准值；UE 真值≈0.3px/s 近静止，但零初速时
        // particle_flag_align_y 无方向可依）
        float alignVel = Num(_streakCfg, "align_velocity", 40f);
        EmitStreakLayer(parent, tex, origin, facing, life, (int)amount, unit, col.A, col,
            sc[0], sc[1], alignVel * comp, dir);
        // halo 层同 origin 同 dir；halo 尺寸（unit×haloMul）不受 max_size_px
        // 钳制（钳制只作用 sz 本体——halo 是泛光模拟层，条目 43 核实）
        if (halo)
            EmitStreakLayer(parent, tex, origin, facing, life, (int)amount, unit * haloMul,
                            col.A * haloAlpha, col, sc[0], sc[1], alignVel * comp, dir);
    }

    private void EmitStreakLayer(Node parent, Texture2D tex, Vector2 gpos, float facing, float life,
        int amount, float scaleUnit, float alphaFrom, Color col, float sc0, float sc1, float vel, Vector2 dir)
    {
        var p = new CpuParticles2D
        {
            Texture = tex,
            OneShot = true,
            Explosiveness = 1f,
            Direction = dir, // 条目 43：速度对齐枪管轴（align_y 的方向载体随之共线）
            Spread = 0f,
            Gravity = Vector2.Zero,
            // 初速=方向载体（观感校准值，UE 真值≈0.3px/s 近静止）：
            // 零初速时 particle_flag_align_y 无方向可依
            InitialVelocityMin = vel,
            InitialVelocityMax = vel,
            Amount = Mathf.Max(1, amount),
            Lifetime = life,
        };
        parent.AddChild(p);
        p.Set("particle_flag_align_y", true); // 速度对齐（UE velocity-aligned mesh）
        p.ScaleAmountMin = scaleUnit;
        p.ScaleAmountMax = scaleUnit;
        // 条目 43：前 20% 寿命快升到满尺寸——原两点线性 (0,sc0)→(1,sc1) 在
        // 0.1s 寿命下"长出来"的过程占半生（前半程过暗）。与 UE grow 曲线形状
        // 有意差异：满尺寸时刻 0.5→0.2，其后保持满尺寸到寿命结束
        p.ScaleAmountCurve = MakeCurve(0f, sc0, 0.2f, sc1, 1f, sc1);
        var ramp = new Gradient();
        ramp.SetColor(0, new Color(col.R, col.G, col.B, alphaFrom));
        ramp.SetColor(1, new Color(col.R, col.G, col.B, 0f));
        p.ColorRamp = ramp;
        p.Material = new CanvasItemMaterial { BlendMode = CanvasItemMaterial.BlendModeEnum.Add };
        p.GlobalPosition = gpos;
        p.Emitting = true;
        FreeLater(p, life + 0.4f);
    }

    // 闪光面片：UE 真值 amount=3/拍、life 0.15 + randomness 0.33、前向偏移
    // 5.8px、mesh 87x6px、(0.401,0.740,1,a0.3)→(0.7515,0.6615,1,a0)、Add 混合；
    // 尺寸曲线 0~0.25 恒 1 → 0.25~0.75 线性落 0。
    private void EmitFlash(Node parent, Vector2 gpos, float facing, float comp, Vector2 dir)
    {
        bool enabled = _flashCfg.TryGetValue("enabled", out var fe) ? fe.AsBool() : true;
        if (!enabled) return;
        var texPath = _flashCfg.TryGetValue("texture", out var tp) ? tp.AsString() : "";
        if (string.IsNullOrEmpty(texPath) || !ResourceLoader.Exists(texPath)) return;
        float amount = Num(_flashCfg, "amount", 3f);
        if (BreakerTripped("flash", amount, _maxFlashPx)) return;
        float life = Num(_flashCfg, "life", 0.15f);
        float lr = Num(_flashCfg, "lifetime_randomness", 0.33f);
        float offX = Num(_flashCfg, "offset_x", 5.8f);
        var sz = Arr2(_flashCfg, "size", 87f, 6f);
        // size 防糊屏钳制（同 sparks）
        sz[0] = Mathf.Min(sz[0], _maxFlashPx);
        sz[1] = Mathf.Min(sz[1], _maxFlashPx);
        var cFrom = ColRgba(_flashCfg, "color_from", new Color(0.401f, 0.74f, 1f, 0.3f));
        var cTo = ColRgba(_flashCfg, "color_to", new Color(0.7515f, 0.6615f, 1f, 0f));

        var tex = GD.Load<Texture2D>(texPath);
        float baseW = Mathf.Max(1, tex.GetWidth());
        var p = new CpuParticles2D
        {
            Texture = tex,
            OneShot = true,
            Explosiveness = 1f,
            Direction = new Vector2(facing, 0),
            Spread = 0f,
            Gravity = Vector2.Zero,
            Amount = Mathf.Max(1, (int)amount),
            Lifetime = life,
            LifetimeRandomness = lr,
        };
        parent.AddChild(p);
        float unit = sz[0] * _scale * comp / baseW; // 纹理即 87:6 比例，按宽定标
        p.ScaleAmountMin = unit;
        p.ScaleAmountMax = unit;
        p.ScaleAmountCurve = MakeCurve(0f, 1f, 0.25f, 1f, 0.75f, 0f, 1f, 0f);
        var ramp = new Gradient();
        ramp.SetColor(0, cFrom);
        ramp.SetColor(1, cTo);
        p.ColorRamp = ramp;
        p.Material = new CanvasItemMaterial { BlendMode = CanvasItemMaterial.BlendModeEnum.Add };
        // 条目 43：前向偏移沿枪管轴 dir——半长+枪口帽间隙（替换原
        // facing*offX 恒水平式；offX 语义=枪口帽间隙）
        p.GlobalPosition = gpos + dir * ((sz[0] * 0.5f + offX) * _scale * comp);
        p.Emitting = true;
        FreeLater(p, life + 0.4f);
    }

    // --- 条目 44：Sprite2D 面片路线（mode="sprite"，默认）------------------
    // 旧粒子路径的三个坑一次绕开：①粒子按"整张纹理×ScaleAmount"绘制，
    // 实心遮罩无渐变形状 → 画成实心色块（打回截图实证）；②particle_flag_
    // align_y 需要初速载体（UE 真值初速≈0 → 被迫加 align_velocity 观感
    // 校准值）；③CPUParticles2D 的尺寸曲线与 UE SizeMultiplyLife（X/Y 轴
    // 独立）语义对不上。Sprite2D 面片直接给 X/Y 独立缩放 + Tween 时序。
    // 光条：UE SizeMultiplyLife Y 0.5→1.0（X 恒 1）、life 0.1；贴图局部
    // +Y == +dir（holder.Rotation = dir.Angle()-π/2，贴图长轴=纵向），
    // 第 0 行（枪口端亮核）落在枪口尖、第 129 行（全透明远端）沿枪管前伸；
    // 中心前移半长=UE PivotOffset（mesh 中心锚定）口径。
    private void EmitStreakSprite(Node parent, Vector2 gpos, float facing, float comp, Vector2 dir,
        GodotObject bone, Node2D n2)
    {
        if (string.IsNullOrEmpty(_streakTexNew) || !ResourceLoader.Exists(_streakTexNew)) return;
        float amount = Num(_streakCfg, "amount", 1f);
        bool halo = _streakCfg.TryGetValue("halo", out var hv) ? hv.AsBool() : true;
        if (BreakerTripped("streak", amount * (halo ? 2f : 1f), _maxStreakPx)) return;
        float life = Num(_streakCfg, "life", 0.1f);
        var sz = Arr2(_streakCfg, "size", 22f, 65f);
        // #14 教训：防全屏爆闪——尺寸钳制 + 面积熔断（halo 同样纳入钳制）
        sz[0] = Mathf.Min(sz[0], _maxStreakPx);
        sz[1] = Mathf.Min(sz[1], _maxStreakPx);
        // 条目 45 ★：纹理已把 UE ColorOverLife 基色 C0=(0.3698,0.8489,1.0)
        // 烘焙进 RGB，modulate 再用基色 = 颜色应用两次（打回"高亮丢失"真根因）→
        // 默认值同步为白（1,1,1,1），只由 modulate.a 承担时序。
        var col = ColRgba(_streakCfg, "color", new Color(1f, 1f, 1f, 1f));
        // grow 曲线=UE SizeMultiplyLife Y 轴（config scale_curve [0.85,1.0]）
        var grow = Arr2(_streakCfg, "scale_curve", 0.85f, 1f);
        float haloMul = Num(_streakCfg, "halo_size_mul", 1.8f);
        float haloAlpha = Num(_streakCfg, "halo_alpha", 0.40f);

        var tex = GD.Load<Texture2D>(_streakTexNew);
        float texW = Mathf.Max(1f, tex.GetWidth());
        float texH = Mathf.Max(1f, tex.GetHeight());

        // holder 局部 +Y == +dir：Rotation = dir.Angle()-π/2（旋转 (0,1)
        // 得到 angle=rot+90°=dir.Angle()）。AddChild 到粒子同一父节点。
        var holder = new Node2D();
        parent.AddChild(holder);
        holder.GlobalPosition = gpos;
        holder.Rotation = dir.Angle() - Mathf.Pi / 2f;
        var mat = new CanvasItemMaterial { BlendMode = CanvasItemMaterial.BlendModeEnum.Add };

        // 本体：屏幕 px 尺寸 sz×scale×comp；Position=(0, L(t)*0.5)——中心
        // 前移半长，尾端贴枪口尖；前移量随长度同步（同一条 Tween 时序）
        float w = sz[0] * _scale * comp;
        float hFull = sz[1] * _scale * comp;
        var core = new Sprite2D { Texture = tex, Material = mat };
        holder.AddChild(core);
        core.Scale = new Vector2(w / texW, hFull / texH * grow[0]);
        core.Position = new Vector2(0f, hFull * grow[0] * 0.5f);
        core.Modulate = new Color(col.R, col.G, col.B, col.A);
        SpriteGrowTween(core, hFull / texH, hFull * 0.5f, grow, life);

        if (halo)
        {
            // halo：同纹理放大 + 降 alpha 泛光近似；尺寸必须纳入 max_size_px
            // 钳制（#14 教训：钳制只作用本体不作用 halo=留爆闪后门）
            float hw = Mathf.Min(sz[0] * haloMul, _maxStreakPx);
            float hh = Mathf.Min(sz[1] * haloMul, _maxStreakPx);
            var haloSp = new Sprite2D { Texture = tex, Material = mat };
            holder.AddChild(haloSp);
            haloSp.Scale = new Vector2(hw / texW, hh / texH * grow[0]);
            haloSp.Position = new Vector2(0f, hh * grow[0] * 0.5f);
            haloSp.Modulate = new Color(col.R, col.G, col.B, col.A * haloAlpha);
            SpriteGrowTween(haloSp, hh / texH, hh * 0.5f, grow, life);
        }

        // 兜底：Tween 完成回调 QueueFree 之外再加定时 FreeLater（防 Tween
        // 被打断后节点泄漏）
        FreeLater(holder, life + 0.4f);
        // 条目 47→48：出生登记跟随。条目 47 的"Dir0 出生锁定、跟随期只钉位置"
        // 已被 48 推翻——手臂在 t_fire 后 0.1s 窗口内继续旋转（臂链 Δ≈-26°，
        // tools/diag_dir6.py 实测），方向锁定必然过时。hull 模式下 FollowTick
        // 每帧两点差分重算 dir(t) 并更新本 holder 的 Rotation，与 UE 原版语义
        // 对齐：UE fx_ling_attack_01 的 streak/flash 发射器挂在武器骨架的枪口
        // socket 上，发射器坐标系逐帧随 socket 姿态更新（位置+旋转全跟随），
        // 粒子面片"从枪口尖沿当前枪管轴前伸"；本实现 holder=发射器、两点差分
        // =socket 姿态，streak sprite 局部 Position=(0, L(t)·0.5) 随 holder 旋转，
        // 天然实现"从枪口尖沿当前枪管轴前伸"。
        RegisterFollower(holder, n2, bone, "streak", dir, 0f, comp, life);
    }

    // 条目 45：光条 Tween 拆成两条独立 Tween——旧实现（条目 44）把
    // scale.y/position.y/modulate:a 塞进同一条并行 Tween 且 alpha 从 t=0
    // 就线性落 0，亮核只在第一帧满亮随后立刻衰减，是"高亮丢失"的一半根因。
    //
    // ① 长度/位置：TRANS_QUAD + EASE_OUT（前段快升到接近满长，对应 UE
    //    SizeMultiplyLife Y 0.5→1.0 的上升段观感）。
    // ② 透明度：前 60% 保持、后 40% 落到 0 ——UE 真值 L(t) = AlphaOverLife
    //    (1→0) × ColorScaleOverLife (20→5)，HDR 值在 LDR 输出上被裁剪：
    //    t≲0.46 时 20×(1-t) 仍 ≫1，屏幕恒为满亮；之后才线性落到 5×0=0。
    //    "保持 60% + 后 40% QUAD/EASE_IN 落 0" 即该裁剪的 LDR 近似。
    private static void SpriteGrowTween(Sprite2D sp, float baseScaleY, float basePosY,
        float[] grow, float life)
    {
        // ① 长度/位置：前段快升到接近满长
        var tg = sp.CreateTween();
        tg.SetParallel(true);
        tg.TweenProperty(sp, "scale:y", baseScaleY * grow[1], life)
            .From(baseScaleY * grow[0])
            .SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.Out);
        tg.TweenProperty(sp, "position:y", basePosY * grow[1], life)
            .From(basePosY * grow[0])
            .SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.Out);
        // ② 透明度：前 60% 保持、后 40% 落 0（UE L(t) 的 LDR 裁剪近似）
        var ta = sp.CreateTween();
        ta.TweenInterval(life * 0.6f);
        ta.TweenProperty(sp, "modulate:a", 0f, life * 0.4f)
            .From(sp.Modulate.A)
            .SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.In);
        ta.Finished += sp.QueueFree;
    }

    // 闪光面片 Sprite2D 路线（mode="sprite"，默认）。UE 真值：amount=3/拍、
    // life 0.15×(1±lifetime_randomness 0.33)、mesh 87×6、SizeMultiplyLife
    // X 1→0、(0.401,0.740,1,α0.55)→(0.7515,0.6615,1,α0)、Add 混合；
    // 前移仅 EmitterOrigin=(20,0,0)=5.8px——UE flash 无 PivotOffset，
    // 不做半长前移（与光条 PivotOffset=中心锚定的口径差异，主日志条目 44⑦）。
    private void EmitFlashSprite(Node parent, Vector2 gpos, float facing, float comp, Vector2 dir,
        GodotObject bone, Node2D n2)
    {
        bool enabled = _flashCfg.TryGetValue("enabled", out var fe) ? fe.AsBool() : true;
        if (!enabled) return;
        var texPath = _flashCfg.TryGetValue("texture", out var tp) ? tp.AsString() : "";
        if (string.IsNullOrEmpty(texPath) || !ResourceLoader.Exists(texPath)) return;
        float amount = Num(_flashCfg, "amount", 3f);
        if (BreakerTripped("flash", amount, _maxFlashPx)) return;
        float life = Num(_flashCfg, "life", 0.15f);
        float lr = Num(_flashCfg, "lifetime_randomness", 0.33f);
        float offX = Num(_flashCfg, "offset_x", 5.8f);
        var sz = Arr2(_flashCfg, "size", 87f, 6f);
        // #14 教训：尺寸钳制（同 sparks/streak）
        sz[0] = Mathf.Min(sz[0], _maxFlashPx);
        sz[1] = Mathf.Min(sz[1], _maxFlashPx);
        // 条目 45 ★：同 streak——闪光纹理已烘焙基色 Cf=(0.401,0.740,1.0)，
        // modulate.rgb 必须是白；alpha 0.55→0.70 是观感校准豁免（UE 无
        // ColorScale 过曝项、Godot Add 无 bloom 需提亮，可调区间 0.55~0.85）。
        var cFrom = ColRgba(_flashCfg, "color_from", new Color(1f, 1f, 1f, 0.70f));
        var cTo = ColRgba(_flashCfg, "color_to", new Color(0.7515f, 0.6615f, 1f, 0f));

        var tex = GD.Load<Texture2D>(texPath);
        float texW = Mathf.Max(1f, tex.GetWidth());
        float texH = Mathf.Max(1f, tex.GetHeight());

        // holder 局部 +X == dir（Rotation = dir.Angle()，贴图长轴=横向，
        // 第 0 列=枪口侧）；前移去掉半长，仅 offX 间隙。
        // 条目 48：hull 模式下 holder 出生位置=Wf（gpos 即枪口尖，不再沿 dir
        // 世界前移），offX 改为 sprite 局部偏移 (offX×scale×comp, 0)——沿 holder
        // 局部 +X、随 holder 旋转，旋转跟随时间距自动正确（UE socket 全跟随
        // 语义：间隙偏移在发射器局部系内，随 socket 姿态同步旋转）。
        bool hullMode = _muzzleHull != null && _dirSource != "facing";
        var holder = new Node2D();
        parent.AddChild(holder);
        holder.GlobalPosition = hullMode ? gpos : gpos + dir * (offX * _scale * comp);
        holder.Rotation = dir.Angle();
        var mat = new CanvasItemMaterial { BlendMode = CanvasItemMaterial.BlendModeEnum.Add };
        float baseSx = sz[0] * _scale * comp / texW;
        float baseSy = sz[1] * _scale * comp / texH;
        int n = Mathf.Max(1, (int)amount);
        float maxLife = 0f;
        for (int i = 0; i < n; i++)
        {
            // UE lifetime randomness：每片独立 life×(1±lr)
            float l = life * (1f + ((float)_rng.NextDouble() * 2f - 1f) * lr);
            maxLife = Mathf.Max(maxLife, l);
            var sp = new Sprite2D { Texture = tex, Material = mat };
            holder.AddChild(sp);
            sp.Scale = new Vector2(baseSx, baseSy);
            // 条目 48：hull 模式把 offX 从世界偏移局部化——沿 holder 局部 +X，
            // 随 holder 旋转（FollowTick 每帧更新 Rotation 时刻距自动正确）
            sp.Position = hullMode ? new Vector2(offX * _scale * comp, 0f) : Vector2.Zero;
            sp.Modulate = new Color(cFrom.R, cFrom.G, cFrom.B, cFrom.A);
            var tw = sp.CreateTween();
            tw.SetParallel(true);
            // 条目 45：UE 真值（fx_ling_attack_01.txt:677-699）SizeMultiplyLife
            // X 是"TimeBias 0.25 之前恒 1.0、之后线性落 0"，不是从 t=0 就收拢
            // ——旧实现把整段 life 都用于收拢，闪光一出现就在缩，观感上"比 UE
            // 短"。改为：前 25% 用 SetDelay 保持满宽满亮，后 75% 线性收拢+落 0。
            tw.TweenProperty(sp, "scale:x", 0f, l * 0.75f).From(baseSx).SetDelay(l * 0.25f);
            tw.TweenProperty(sp, "modulate:a", cTo.A, l * 0.75f).From(cFrom.A).SetDelay(l * 0.25f);
            tw.Finished += sp.QueueFree;
        }
        FreeLater(holder, maxLife + 0.4f);
        // 条目 47→48：出生登记跟随。OffX 在 hull 模式下已局部化进 sprite
        // Position（FollowTick 只更新 holder 位姿，世界偏移路径不复存在）；
        // 寿命用 maxLife（每片独立 life×(1±lr) 的上限）+ 0.1 余量，保证跟随
        // 覆盖到最后一片消亡。旋转跟随语义见 EmitStreakSprite 尾注（UE socket
        // 全跟随对齐）。
        RegisterFollower(holder, n2, bone, "flash", dir, offX, comp, maxLife);
    }

    // legacy 发射路径（旧 config 键：textures 逐帧碎片 + streak_texture）——
    // 仅静默皮肤（silent profile）使用，行为保持与条目30 之前一致（含 64px
    // 硬上限与 damping×40/×60 旧换算），不做缩放补偿。
    private void BurstLegacy(Vector2 gpos, float facing)
    {
        var parent = _target.GetParent();
        if (parent == null) return;
        float life = _sparksCfg.TryGetValue("life", out var lv) && lv.VariantType == Variant.Type.Array
            ? (float)lv.AsGodotArray()[1].AsDouble() : 0.2f;
        float streakLife = _streakCfg.TryGetValue("life", out var slv) ? (float)slv.AsDouble() : 0.12f;
        float maxLife = Mathf.Max(life, streakLife);

        // sparks: sphere burst, forward cone, drag, blue->purple, fade.
        // One emitter PER spark texture (pre-cropped shard frames - no SubUV
        // dependence). config "size" = target on-screen px, scale derives
        // from each texture's width; hard-capped at 64 px so a bad config can
        // never paint the screen again.
        if (_sparkTexPaths.Count > 0)
        {
            float spdMin = _sparksCfg.TryGetValue("speed", out var sv) && sv.VariantType == Variant.Type.Array
                ? (float)sv.AsGodotArray()[0].AsDouble() : 260f;
            float spdMax = sv.VariantType == Variant.Type.Array && sv.AsGodotArray().Count > 1
                ? (float)sv.AsGodotArray()[1].AsDouble() : 560f;
            float szMin = _sparksCfg.TryGetValue("size", out var zv) && zv.VariantType == Variant.Type.Array
                ? (float)zv.AsGodotArray()[0].AsDouble() : 16f;
            float szMax = zv.VariantType == Variant.Type.Array && zv.AsGodotArray().Count > 1
                ? (float)zv.AsGodotArray()[1].AsDouble() : 36f;
            szMin = Mathf.Min(szMin, 64f);
            szMax = Mathf.Min(szMax, 64f);
            float spread = _sparksCfg.TryGetValue("spread", out var spv) ? (float)spv.AsDouble() : 14f;
            float damping = _sparksCfg.TryGetValue("damping", out var dv) ? (float)dv.AsDouble() : 7f;
            float amount = _sparksCfg.TryGetValue("amount", out var av) ? av.AsSingle() : 1f;
            foreach (var texPath in _sparkTexPaths)
            {
                if (string.IsNullOrEmpty(texPath) || !ResourceLoader.Exists(texPath)) continue;
                var sparkTex = GD.Load<Texture2D>(texPath);
                float baseW = Mathf.Max(1, sparkTex.GetWidth());
                var p = new CpuParticles2D
                {
                    Texture = sparkTex,
                    OneShot = true,
                    Explosiveness = 1f,
                    Amount = (int)amount,
                    Lifetime = life,
                    Direction = new Vector2(facing, 0),
                    Spread = spread,
                    Gravity = Vector2.Zero,
                    InitialVelocityMin = spdMin * _scale,
                    InitialVelocityMax = spdMax * _scale,
                    ScaleAmountMin = szMin * _scale / baseW,
                    ScaleAmountMax = szMax * _scale / baseW,
                    DampingMin = damping * 40f * _scale,
                    DampingMax = damping * 60f * _scale,
                    Emitting = true,
                };
                var init = new Gradient();
                init.SetColor(0, _colA);
                init.SetColor(1, _colB);
                p.ColorInitialRamp = init;
                var ramp = new Gradient();
                ramp.SetColor(0, new Color(_colA.R, _colA.G, _colA.B, 1f));
                ramp.AddPoint(0.5f, new Color(_fadeTo.R, _fadeTo.G, _fadeTo.B, 1f));
                ramp.SetColor(1, new Color(_fadeTo.R, _fadeTo.G, _fadeTo.B, 0f));
                p.ColorRamp = ramp;
                var m = new CanvasItemMaterial { BlendMode = CanvasItemMaterial.BlendModeEnum.Add };
                p.Material = m;
                parent.AddChild(p);
                p.GlobalPosition = gpos;
                FreeLater(p, maxLife + 0.4f);
            }
        }

        // streaks: velocity-aligned short muzzle flash; config "size" =
        // target on-screen px width, scale derives from the texture width
        if (!string.IsNullOrEmpty(_streakTexPath) && ResourceLoader.Exists(_streakTexPath))
        {
            var streakTex = GD.Load<Texture2D>(_streakTexPath);
            float sLife = streakLife;
            float sAmt = _streakCfg.TryGetValue("amount", out var sa) ? sa.AsSingle() : 2f;
            float sAlpha = _streakCfg.TryGetValue("alpha", out var sal) ? (float)sal.AsDouble() : 0.9f;
            float sSize = _streakCfg.TryGetValue("size", out var szv) && szv.VariantType == Variant.Type.Array
                ? (float)szv.AsGodotArray()[0].AsDouble() : 90f;
            float baseW = Mathf.Max(1, streakTex.GetWidth());
            var s = new CpuParticles2D
            {
                Texture = streakTex,
                OneShot = true,
                Explosiveness = 1f,
                Amount = (int)sAmt,
                Lifetime = sLife,
                Direction = new Vector2(facing, 0),
                Spread = 10f,
                Gravity = Vector2.Zero,
                InitialVelocityMin = 40f * _scale,
                InitialVelocityMax = 110f * _scale,
                ScaleAmountMin = sSize * 0.7f * _scale / baseW,
                ScaleAmountMax = sSize * 1.15f * _scale / baseW,
                Color = new Color(1f, 1f, 1f, sAlpha),
                Emitting = true,
            };
            s.Set("particle_flag_align_y", true);
            var sr = new Gradient();
            sr.SetColor(0, new Color(1f, 1f, 1f, sAlpha));
            sr.SetColor(1, new Color(1f, 1f, 1f, 0f));
            s.ColorRamp = sr;
            var sm = new CanvasItemMaterial { BlendMode = CanvasItemMaterial.BlendModeEnum.Add };
            s.Material = sm;
            parent.AddChild(s);
            s.GlobalPosition = gpos;
            FreeLater(s, sLife + 0.4f);
        }
    }

    // 定时释放兜底（条目 44：签名从 CpuParticles2D 放宽为 Node——Sprite2D
    // 面片 holder 共用同款兜底；原 5 处 CpuParticles2D 调用点不受影响）
    private static void FreeLater(Node p, double delay)
    {
        var t = new Timer { WaitTime = delay, OneShot = true, Autostart = true };
        p.AddChild(t);
        t.Timeout += () => { if (GodotObject.IsInstanceValid(p)) p.QueueFree(); };
    }
}
public class ShadowSilhouette : Node2D
{
    // the live instance, for cross-component pose probes (DeathWatcher)
    public static ShadowSilhouette? ActiveShadow;

    private readonly Node _target;
    private readonly float _scaleX, _opacity, _nudgeY, _feetSkelY, _obliqueDeg, _lenScale;
    private readonly string _matPath;
    private readonly bool _debugRed;
    // DRC's RT shadow lands on a GROUND PLANE, not on the skeleton's static
    // bounds - the feet are not necessarily touching the ground (shop/event
    // scenes pose the character differently). The ground line is therefore
    // MEASURED from the foot bones every tick, with the skeleton bounds as
    // fallback when the bones can't be found.
    private readonly string[] _feetBones;
    private readonly bool _groundFromBones;
    private readonly float _groundOffsetY;
    private GodotObject[]? _srcFootBones;
    private Node? _dst;
    private GodotObject? _srcSkel, _dstSkel;
    private GodotObject[]? _srcBones, _dstBones, _srcSlots, _dstSlots;
    private ShaderMaterial? _mat;
    private float _dissolve;
    private Timer? _poll, _tick, _probe, _check;
    private int _phase, _tries, _syncTries, _checks, _groundLogs;
    private ulong _groundLogMs;
    private bool _warned;

    internal static float BoneRot(GodotObject? skel, string bone)
    {
        var b = skel?.Call("find_bone", bone).AsGodotObject();
        return b != null ? b.Call("get_rotation").AsSingle() : float.NaN;
    }

    internal void PoseCheck(string tag)
    {
        try
        {
            if (_dst == null || !GodotObject.IsInstanceValid(_dst)) return;
            var sk = _target.Call("get_skeleton").AsGodotObject();
            var st = _target.Get("animation_state").AsGodotObject()
                     ?? _target.Call("get_animation_state").AsGodotObject();
            var ao = st?.Call("get_current", 0).AsGodotObject()?.Call("get_animation").AsGodotObject();
            var anim = ao != null ? ao.Call("get_name").AsString() : "";
            DyeFramework.Log($"pose[{tag}] anim={anim} " +
                     $"src(b10={BoneRot(sk, "bone10"):0.0}/b11={BoneRot(sk, "bone11"):0.0}) " +
                     $"dst(b10={BoneRot(_dstSkel, "bone10"):0.0}/b11={BoneRot(_dstSkel, "bone11"):0.0})");
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] pose check failed: " + e.Message);
        }
    }

    public ShadowSilhouette(Node target, Godot.Collections.Dictionary cfg, float feetSkelY)
    {
        _target = target;
        _feetSkelY = feetSkelY;
        // ground projection = 斜二测画法 (cabinet/oblique drawing): vertical
        // extent falls onto the ground at 45 deg with HALF length; horizontal
        // extent keeps true length. oblique_deg=90 + the old squash_y value
        // reproduces the previous straight-down mirror exactly.
        _obliqueDeg = cfg.TryGetValue("oblique_deg", out var od) ? (float)od.AsDouble() : 45f;
        float ls = cfg.TryGetValue("len_scale", out var lv) ? (float)lv.AsDouble() : -1f;
        if (ls < 0) ls = cfg.TryGetValue("squash_y", out var sq) ? (float)sq.AsDouble() : 0.5f;
        _lenScale = ls;
        _scaleX = cfg.TryGetValue("scale_x", out var sx) ? (float)sx.AsDouble() : 1.0f;
        float op = cfg.TryGetValue("opacity", out var opv) ? (float)opv.AsDouble() : -1f;
        if (op < 0) op = cfg.TryGetValue("alpha", out var al) ? (float)al.AsDouble() : 0.55f;
        _opacity = op;
        _nudgeY = cfg.TryGetValue("feet_nudge_y", out var ny) ? (float)ny.AsDouble() : 0f;
        // DRC ground-plane philosophy: the ground is SCENE geometry - the game
        // places the character node ON the floor, so the ground line defaults
        // to the node's own Y (+ small offset for the sole). Bone-based
        // measurement is opt-in only (bone origins sit at the ankle, not the
        // sole, and the trailing dress measures below the feet).
        _groundFromBones = cfg.TryGetValue("ground_from_bones", out var gfb) && gfb.AsBool();
        _groundOffsetY = cfg.TryGetValue("ground_offset_y", out var gy) ? (float)gy.AsDouble() : 4f;
        var fb = new System.Collections.Generic.List<string>();
        if (cfg.TryGetValue("feet_bones", out var fbv) && fbv.VariantType == Variant.Type.Array)
            foreach (var b in fbv.AsGodotArray()) fb.Add(b.AsString());
        if (fb.Count == 0)
        {
            fb.Add("bone43");  // zeroR_youjiao_z (right foot)
            fb.Add("bone46");  // zeroL_zuojiao_z (left foot)
        }
        _feetBones = fb.ToArray();
        _matPath = cfg.TryGetValue("material", out var mp) ? mp.AsString()
            : "res://drc_dye/profiles/ling/animations/characters/silent/ling_shadow_material_sil.tres";
        _debugRed = cfg.TryGetValue("debug_red", out var dr) && dr.AsBool();
        Visible = false;
        ZIndex = target is CanvasItem ci ? ci.ZIndex : 0;
    }

    public void Activate()
    {
        // the holder dies with the character sprite; drag the drawn node
        // (its SIBLING) along so a scene switch cannot orphan it
        TreeExiting += () =>
        {
            try
            {
                if (_dst != null && GodotObject.IsInstanceValid(_dst)) _dst.QueueFree();
            }
            catch { /* contained */ }
        };
        _poll = new Timer { WaitTime = 0.2, Autostart = true };
        AddChild(_poll);
        _poll.Timeout += Tick;
    }

    /// <summary>
    /// Dissolve-synced fade: the death tween drives this with the SAME value
    /// it feeds the character's dissolve shader, so the shadow's opacity
    /// (configured 0.8) erases linearly in step with the body's erosion.
    /// _dissolve survives a mid-death Rebuild (WireDst re-applies it).
    /// </summary>
    public void SetDissolve(float d)
    {
        _dissolve = Mathf.Clamp(d, 0f, 1f);
        if (_mat != null)
            _mat.SetShaderParameter("opacity", _opacity * (1f - _dissolve));
    }

    internal void LogPair(string tag, string anim, float sr10, float sr11)
    {
        try
        {
            DyeFramework.Log($"pose[{tag}] anim={anim} " +
                     $"src(b10={sr10:0.0}/b11={sr11:0.0}) " +
                     $"dst(b10={BoneRot(_dstSkel, "bone10"):0.0}/b11={BoneRot(_dstSkel, "bone11"):0.0})");
        }
        catch { /* contained */ }
    }

    private void Fail(string why)
    {
        if (!_warned)
        {
            _warned = true;
            GD.PrintErr("[DRCSpineDye] silhouette shadow unavailable: " + why);
        }
        Shutdown("target invalid (tick)");
    }

    private void Shutdown(string why = "unspecified")
    {
        try
        {
            if (ActiveShadow == this)
            {
                ActiveShadow = null;
                DyeFramework.Log("shadow shutdown: " + why);
            }
            _poll?.QueueFree(); _poll = null;
            _tick?.QueueFree(); _tick = null;
            _check?.QueueFree(); _check = null;
            if (_dst != null && GodotObject.IsInstanceValid(_dst)) _dst.QueueFree();
            _dst = null;
            // drop cached native wrappers immediately: they must not outlive
            // the freed skeleton into the GC finalizer (a finalizer disposing
            // a wrapper whose native the scene already freed is a process-level
            // ExecutionEngineException - crash dump 23:56, finalizer thread)
            _srcSkel = null; _dstSkel = null;
            _srcBones = null; _dstBones = null;
            _srcSlots = null; _dstSlots = null;
            QueueFree();
        }
        catch { /* contained */ }
    }

    private void Tick()
    {
        try
        {
            if (!GodotObject.IsInstanceValid(_target)) { Shutdown("target invalid (tick)"); return; }
            if (_phase == 0) CreateDst();
            else if (_phase == 1) WireDst();
            else Sync();
        }
        catch (System.Exception e)
        {
            Fail("tick: " + e.Message);
        }
    }

    private void CreateDst()
    {
        if (++_tries > 100) { Fail("source skeleton never appeared"); return; }
        var skel = _target.Call("get_skeleton").AsGodotObject();
        if (skel == null) return; // skeleton still loading
        var res = skel.Call("get_data").AsGodotObject();
        if (res == null) return;
        if (!ClassDB.ClassExists("SpineSprite")) { Fail("SpineSprite not in ClassDB"); return; }
        var parent = _target.GetParent();
        if (parent == null) { Fail("sprite has no parent"); return; }
        var dstObj = ClassDB.Instantiate("SpineSprite").AsGodotObject();
        if (dstObj is not Node dstNode) { Fail("instantiate SpineSprite failed"); return; }
        // our own sweep must never dye-attach this sprite
        dstNode.SetMeta("drc_dye_attached", true);
        parent.AddChild(dstNode);
        // immediately before the character in tree order: drawn above the
        // arena, below the character
        parent.MoveChild(dstNode, _target.GetIndex());
        dstNode.Set("visible", false);
        dstNode.Call("set_skeleton_data_res", res);
        _dst = dstNode;
        _phase = 1;
        _tries = 0;
        if (_poll != null) _poll.WaitTime = 0.05;
        GD.Print("[DRCSpineDye] silhouette shadow sprite created, waiting for skeleton");
    }

    private void WireDst()
    {
        if (_dst == null || ++_tries > 100) { Fail("dst skeleton never appeared"); return; }
        var dskel = _dst.Call("get_skeleton").AsGodotObject();
        if (dskel == null) return;
        var sskel = _target.Call("get_skeleton").AsGodotObject();
        if (sskel == null) { Fail("src skeleton vanished"); return; }
        var sb = sskel.Call("get_bones").AsGodotArray();
        var db = dskel.Call("get_bones").AsGodotArray();
        var ss = sskel.Call("get_slots").AsGodotArray();
        var ds = dskel.Call("get_slots").AsGodotArray();
        if (sb.Count != db.Count || ss.Count != ds.Count || sb.Count == 0)
        {
            Fail($"bone/slot count mismatch src=({sb.Count},{ss.Count}) dst=({db.Count},{ds.Count})");
            return;
        }
        _srcSkel = sskel; _dstSkel = dskel;
        _srcBones = ObjArray(sb); _dstBones = ObjArray(db);
        _srcSlots = ObjArray(ss); _dstSlots = ObjArray(ds);
        // ground-line measurement bones (src side only - the mirror line is
        // computed from where the character's feet actually ARE)
        var footList = new System.Collections.Generic.List<GodotObject>();
        foreach (var fbName in _feetBones)
        {
            var fbObj = sskel.Call("find_bone", fbName).AsGodotObject();
            if (fbObj != null) footList.Add(fbObj);
        }
        _srcFootBones = footList.ToArray();
        // slots: attachment/deform are copied ONCE here. Per-tick getters
        // returning non-trivial Variants (Object refs, PackedFloat32Array)
        // leak native buffers - nothing disposes them, 50 slots x 60 Hz grew
        // unbounded until the game crashed on a long session (log: repeated
        // '_internal_spine_objects_invalidated already connected' from the
        // same calls). This skin never swaps attachments mid-battle, so the
        // one-shot copy is exact; the per-tick sync only pushes inline
        // scalars (floats/colors), which live inside the Variant value.
        for (int i = 0; i < _srcSlots.Length; i++)
        {
            try
            {
                _dstSlots[i].Call("set_attachment", _srcSlots[i].Call("get_attachment"));
                _dstSlots[i].Call("set_deform", _srcSlots[i].Call("get_deform"));
            }
            catch (System.Exception se)
            {
                GD.PrintErr($"[DRCSpineDye] slot {i} initial attachment copy failed: {se.Message}");
            }
        }
        // silhouette material: the fresh sprite's own materials may be null
        // (the game always sets them through the MegaSpine pipeline) - null
        // materials could mean nothing drawn at all. All four slots families
        // get the same flat-tint material, like the mobile RT shadow which
        // renders the lit units as-is.
        try
        {
            var mat = GD.Load<ShaderMaterial>(_matPath);
            if (mat != null)
            {
                _mat = mat;
                mat.SetShaderParameter("tint", _debugRed ? new Color(1f, 0f, 0f, 1f) : new Color(0f, 0f, 0f, 1f));
                mat.SetShaderParameter("opacity", (_debugRed ? 1.0f : _opacity) * (1f - _dissolve));
                _dst.Set("normal_material", mat);
                _dst.Set("additive_material", mat);
                _dst.Set("multiply_material", mat);
                _dst.Set("screen_material", mat);
            }
            else
            {
                Fail("silhouette material not found: " + _matPath);
                return;
            }
        }
        catch (System.Exception me)
        {
            Fail("silhouette material load failed: " + me.Message);
            return;
        }
        // the character's z - the arena floor is drawn ABOVE z=0 canvas items,
        // a shadow left at the default 0 gets swallowed (same lesson as the
        // old blob's ZIndex=-1 incident)
        if (_dst is CanvasItem dc && _target is CanvasItem tc) dc.ZIndex = tc.ZIndex;
        if (_poll != null) _poll.Stop();
        _tick = new Timer { WaitTime = 1.0 / 60.0, Autostart = true };
        AddChild(_tick);
        _tick.Timeout += Sync;
        ActiveShadow = this;
        // baseline follow check: do the copied bone values track the source
        // during plain idle breathing? (first ~16 s, then quiet)
        _check = new Timer { WaitTime = 2.0, Autostart = true };
        AddChild(_check);
        _check.Timeout += () =>
        {
            if (_checks >= 8) { _check?.Stop(); return; }
            _checks++;
            PoseCheck($"idle-check-{_checks}");
        };
        // one-shot probe: transforms as the scene sees them, for occlusion triage
        _probe = new Timer { WaitTime = 3.0, OneShot = true, Autostart = true };
        AddChild(_probe);
        _probe.Timeout += () =>
        {
            try
            {
                if (_dst == null || !GodotObject.IsInstanceValid(_dst)) return;
                var d2 = _dst as Node2D; var t2 = _target as Node2D;
                GD.Print($"[DRCSpineDye] silhouette probe: dst_gpos={d2?.GlobalPosition} dst_gscale={d2?.GlobalScale} " +
                         $"dst_z={( _dst as CanvasItem)?.ZIndex} dst_visible={d2?.Visible} dst_in_tree={_dst.IsInsideTree()} " +
                         $"src_z={( _target as CanvasItem)?.ZIndex} src_gpos={t2?.GlobalPosition} src_visible={t2?.Visible}");
            }
            catch (System.Exception pe) { GD.PrintErr("[DRCSpineDye] silhouette probe failed: " + pe.Message); }
        };
        DyeFramework.Log($"silhouette shadow ready: bones={_srcBones.Length} slots={_srcSlots.Length} " +
                 $"oblique_deg={_obliqueDeg:0} len_scale={_lenScale:0.00} scale_x={_scaleX:0.00} opacity={(_debugRed ? 1f : _opacity):0.00} " +
                 $"feet_skel_y={_feetSkelY:0.0} mat={_matPath} debug_red={_debugRed}");
    }

    private static GodotObject[] ObjArray(Godot.Collections.Array a)
    {
        var r = new GodotObject[a.Count];
        for (int i = 0; i < a.Count; i++) r[i] = a[i].AsGodotObject();
        return r;
    }

    // dst was freed out from under us (container teardown at death): drop the
    // dead references and re-run the create/wire state machine against the
    // character's CURRENT parent
    private void Rebuild()
    {
        try
        {
            DyeFramework.Log("shadow dst lost - rebuilding");
            if (_tick != null && GodotObject.IsInstanceValid(_tick)) _tick.Stop();
            _dst = null; _dstSkel = null; _dstBones = null; _dstSlots = null;
            _phase = 0; _tries = 0; _syncTries = 0;
            if (_poll == null || !GodotObject.IsInstanceValid(_poll))
            {
                _poll = new Timer { WaitTime = 0.05, Autostart = true };
                AddChild(_poll);
                _poll.Timeout += Tick;
            }
            else
            {
                _poll.Start();
            }
        }
        catch (System.Exception e)
        {
            Fail("rebuild: " + e.Message);
        }
    }

    private void Sync()
    {
        if (_dst == null || !GodotObject.IsInstanceValid(_dst) || !GodotObject.IsInstanceValid(_target))
        {
            // at death the game frees the character's original container - our
            // sibling dst dies with it while the character itself survives
            // (dsample log: sprite_valid=True at the same moment). Rebuild.
            if (GodotObject.IsInstanceValid(_target))
            {
                Rebuild();
                return;
            }
            Shutdown("dst/target invalid (sync)");
            return;
        }
        try
        {
            if (++_syncTries >= 120)
            {
                _syncTries = 0;
                if (_dst.GetParent() == null || !_dst.IsInsideTree()) { Shutdown("dst not in tree (watchdog)"); return; }
            }
            bool vis = _target.Get("visible").AsBool();
            // the DRAWN node is _dst (a sibling), not this holder - the first
            // build lost exactly here: the holder's visibility was synced and
            // the shadow sprite stayed visible=false forever (probe: dst_visible=False)
            if (_dst is Node2D d2v && d2v.Visible != vis) d2v.Visible = vis;
            if (!vis) return;
            if (_srcBones == null || _dstBones == null || _srcSlots == null || _dstSlots == null) return;

            // full pose: local values (what timelines write) AND applied values
            // (what constraints write) - whichever family the runtime's
            // update_world_transform consumes, the copied pose takes effect
            for (int i = 0; i < _srcBones.Length; i++)
            {
                var s = _srcBones[i]; var d = _dstBones[i];
                d.Call("set_x", s.Call("get_x"));
                d.Call("set_y", s.Call("get_y"));
                d.Call("set_rotation", s.Call("get_rotation"));
                d.Call("set_scale_x", s.Call("get_scale_x"));
                d.Call("set_scale_y", s.Call("get_scale_y"));
                d.Call("set_shear_x", s.Call("get_shear_x"));
                d.Call("set_shear_y", s.Call("get_shear_y"));
                d.Call("set_a_x", s.Call("get_a_x"));
                d.Call("set_a_y", s.Call("get_a_y"));
                d.Call("set_applied_rotation", s.Call("get_applied_rotation"));
                d.Call("set_a_scale_x", s.Call("get_a_scale_x"));
                d.Call("set_a_scale_y", s.Call("get_a_scale_y"));
                d.Call("set_a_shear_x", s.Call("get_a_shear_x"));
                d.Call("set_a_shear_y", s.Call("get_a_shear_y"));
            }
            // slots: color only (inline Color Variant - no native heap).
            // debug_red: fully opaque (nothing may dim or fade the
            // diagnostic). final look: black rgb is ignored by the material
            // (it flattens tint anyway), slot alpha carries the die fade so
            // the shadow dissolves with the character. attachments/deforms
            // were copied once at wire time (see WireDst).
            for (int i = 0; i < _srcSlots.Length; i++)
            {
                var s = _srcSlots[i]; var d = _dstSlots[i];
                if (_debugRed)
                {
                    d.Call("set_color", new Color(1f, 1f, 1f, 1f));
                }
                else
                {
                    float a = s.Call("get_color").AsColor().A;
                    d.Call("set_color", new Color(0f, 0f, 0f, a));
                }
            }
            // skeleton-level alpha: carries the game's hit-flash color alpha
            // (rgb=1 no-ops on the flattened tint)
            float sa = _srcSkel!.Call("get_color").AsColor().A;
            _dstSkel!.Call("set_color", new Color(1f, 1f, 1f, _debugRed ? 1f : sa));
            // bake world transforms + redraw in case this build's SpineSprite
            // does not self-update an idle animation state
            _dstSkel.Call("update_world_transform", 0);
            _dst.Call("queue_redraw");
            // keep the character's z (the game may raise it mid-battle)
            if (_dst is CanvasItem dc2 && _target is CanvasItem tc2 && dc2.ZIndex != tc2.ZIndex)
                dc2.ZIndex = tc2.ZIndex;

            // ground projection, 斜二测画法: a point at offset (ex, ey) from
            // the feet line maps to (ex, 0) + len_scale*(-ey)*(cosθ, sinθ) -
            // vertical extent falls at θ=45° with half length, horizontal
            // stays true. The feet line = the LOWEST VISUAL POINT of the
            // DRC ground-plane: the ground is SCENE geometry, not a property
            // of the pose. The game places the character node ON the floor,
            // so the ground line is simply the node's own Y (+ sole offset).
            // Guessing from the pose (foot bones / bounds / dress hem) always
            // breaks somewhere - the dress hem alone anchors the mirror line
            // half a body behind the feet.
            if (_target is Node2D t2 && _dst is Node2D d2)
            {
                var nsc = t2.Scale;
                float th = _obliqueDeg * Mathf.Pi / 180f;
                float kx = _lenScale * Mathf.Cos(th);
                float ky = _lenScale * Mathf.Sin(th);
                float feetLocal = _groundOffsetY;
                if (_groundFromBones && _srcFootBones != null && _srcFootBones.Length > 0)
                {
                    float best = float.NaN;
                    foreach (var fb in _srcFootBones)
                    {
                        float fy = fb.Call("get_world_y").AsSingle() * nsc.Y;
                        if (float.IsNaN(best) || fy > best) best = fy; // lowest on screen
                    }
                    if (!float.IsNaN(best)) feetLocal = best;
                }
                d2.Transform = new Transform2D(
                    new Vector2(nsc.X * _scaleX, 0f),
                    new Vector2(-kx * nsc.Y, -ky * nsc.Y),
                    new Vector2(t2.Position.X + kx * feetLocal, t2.Position.Y + feetLocal + ky * feetLocal));
            }
        }
        catch (System.Exception e)
        {
            Fail("sync: " + e.Message);
        }
    }
}


/// <summary>
/// Hit-on-target FX: the game's OWN attack vfx is the authoritative "a hit
/// landed here, now" signal - every player attack spawns a vfx_flying_slash
/// spine that flies TO the target. This watcher tracks one such slash (polling
/// its global position) and, when the slash node is freed (= it landed), bursts
/// blue-purple shards at its last position (UE fx_ling_attack_01_hit styling:
/// blue-white sparks, drag, short life). Causally exact: no hurt-animation
/// guessing, no false positives from poison/status/other monsters, and nothing
/// when Zero attacks without the game showing a hit.
/// Timer-driven (no source generators in this assembly).
/// </summary>
public class SlashImpactWatcher : Node
{
    private readonly Node _slash;
    private readonly System.Collections.Generic.List<string> _texPaths;
    private readonly Color _colA, _colB, _fadeTo;
    private readonly Godot.Collections.Dictionary _sparks;
    private readonly float _scale;
    private Timer? _poll;
    private Vector2 _lastGpos;
    private bool _hadPos;

    public SlashImpactWatcher(Node slash, Godot.Collections.Dictionary cfg)
    {
        _slash = slash;
        _scale = cfg.TryGetValue("scale", out var sc) ? (float)sc.AsDouble() : 1f;
        _texPaths = new System.Collections.Generic.List<string>();
        if (cfg.TryGetValue("textures", out var tv) && tv.VariantType == Variant.Type.Array)
            foreach (var t in tv.AsGodotArray()) _texPaths.Add(t.AsString());
        _colA = Col(cfg, "color_a", new Color(0.29f, 0.69f, 1f));
        _colB = Col(cfg, "color_b", new Color(0.54f, 0.37f, 1f));
        _fadeTo = Col(cfg, "fade_to", new Color(0.37f, 0.85f, 1f));
        _sparks = cfg.TryGetValue("sparks", out var sv) && sv.VariantType == Variant.Type.Dictionary
            ? sv.AsGodotDictionary() : new Godot.Collections.Dictionary();
    }

    private static Color Col(Godot.Collections.Dictionary d, string key, Color def)
    {
        if (!d.TryGetValue(key, out var v) || v.VariantType != Variant.Type.Array) return def;
        var a = v.AsGodotArray();
        return a.Count >= 3
            ? new Color((float)a[0].AsDouble(), (float)a[1].AsDouble(), (float)a[2].AsDouble())
            : def;
    }

    public void Activate()
    {
        _poll = new Timer { WaitTime = 1.0 / 60.0, Autostart = true };
        AddChild(_poll);
        _poll.Timeout += Poll;
    }

    private void Poll()
    {
        try
        {
            if (!GodotObject.IsInstanceValid(_slash) || !_slash.IsInsideTree())
            {
                // the slash just landed / got cleaned up: burst where it was
                _poll?.QueueFree();
                _poll = null;
                if (_hadPos)
                    Burst(_lastGpos);
                QueueFree();
                return;
            }
            if (_slash is Node2D n2)
            {
                _lastGpos = n2.GlobalPosition;
                _hadPos = true;
            }
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] slash watch error (contained): " + e.Message);
            QueueFree();
        }
    }

    private void Burst(Vector2 gpos)
    {
        try
        {
            var parent = GetParent();
            if (parent == null) return;
            float life = _sparks.TryGetValue("life", out var lv) ? (float)lv.AsDouble() : 0.3f;
            float spdMin = _sparks.TryGetValue("speed", out var sv) && sv.VariantType == Variant.Type.Array
                ? (float)sv.AsGodotArray()[0].AsDouble() : 200f;
            float spdMax = sv.VariantType == Variant.Type.Array && sv.AsGodotArray().Count > 1
                ? (float)sv.AsGodotArray()[1].AsDouble() : 430f;
            float szMin = _sparks.TryGetValue("size", out var zv) && zv.VariantType == Variant.Type.Array
                ? (float)zv.AsGodotArray()[0].AsDouble() : 14f;
            float szMax = zv.VariantType == Variant.Type.Array && zv.AsGodotArray().Count > 1
                ? (float)zv.AsGodotArray()[1].AsDouble() : 32f;
            float amount = _sparks.TryGetValue("amount", out var av) ? av.AsSingle() : 1f;
            float damping = _sparks.TryGetValue("damping", out var dv) ? (float)dv.AsDouble() : 6f;
            szMin = Mathf.Min(szMin, 64f);
            szMax = Mathf.Min(szMax, 64f);
            foreach (var texPath in _texPaths)
            {
                if (string.IsNullOrEmpty(texPath) || !ResourceLoader.Exists(texPath)) continue;
                var tex = GD.Load<Texture2D>(texPath);
                float baseW = Mathf.Max(1, tex.GetWidth());
                var p = new CpuParticles2D
                {
                    Texture = tex,
                    OneShot = true,
                    Explosiveness = 1f,
                    Amount = (int)amount,
                    Lifetime = life,
                    Spread = 180f,
                    Direction = new Vector2(0, -1),
                    Gravity = new Vector2(0, 160f),
                    InitialVelocityMin = spdMin * _scale,
                    InitialVelocityMax = spdMax * _scale,
                    ScaleAmountMin = szMin * _scale / baseW,
                    ScaleAmountMax = szMax * _scale / baseW,
                    DampingMin = damping * 40f * _scale,
                    DampingMax = damping * 60f * _scale,
                    Emitting = true,
                };
                var init = new Gradient();
                init.SetColor(0, _colA);
                init.SetColor(1, _colB);
                p.ColorInitialRamp = init;
                var ramp = new Gradient();
                ramp.SetColor(0, new Color(_colA.R, _colA.G, _colA.B, 1f));
                ramp.AddPoint(0.5f, new Color(_fadeTo.R, _fadeTo.G, _fadeTo.B, 1f));
                ramp.SetColor(1, new Color(_fadeTo.R, _fadeTo.G, _fadeTo.B, 0f));
                p.ColorRamp = ramp;
                var m = new CanvasItemMaterial { BlendMode = CanvasItemMaterial.BlendModeEnum.Add };
                p.Material = m;
                parent.AddChild(p);
                p.GlobalPosition = gpos;
                var t = new Timer { WaitTime = life + 0.4f, OneShot = true, Autostart = true };
                p.AddChild(t);
                t.Timeout += () => { if (GodotObject.IsInstanceValid(p)) p.QueueFree(); };
            }
        }
        catch (System.Exception e)
        {
            GD.PrintErr("[DRCSpineDye] slash impact error (contained): " + e.Message);
        }
    }
}

