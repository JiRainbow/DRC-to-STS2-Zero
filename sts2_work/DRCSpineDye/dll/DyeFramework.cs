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
    private Timer? _poll;
    private string _prevAnim = "";
    private int _fireSeq;

    public AttackFxWatcher(Node target, Godot.Collections.Dictionary cfg)
    {
        _target = target;
        _boneName = cfg.TryGetValue("bone", out var bn) ? bn.AsString() : "bone9";
        _muzzleLen = cfg.TryGetValue("muzzle_len", out var ml) ? (float)ml.AsDouble() : 0f;
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
            var bone = skel?.Call("find_bone", _boneName).AsGodotObject();
            if (bone == null || _target is not Node2D n2) return;
            float wx = bone.Call("get_world_x").AsSingle();
            float wy = bone.Call("get_world_y").AsSingle();
            if (_muzzleLen != 0f)
            {
                float wr = bone.Call("get_world_rotation_x").AsSingle();
                wx += Mathf.Cos(wr) * _muzzleLen;
                wy += Mathf.Sin(wr) * _muzzleLen;
            }
            // skeleton -> parent mapping. spine-godot's bone world getters
            // return NODE-convention coords (y-down, facing-flipped) - proven
            // by muzzle logs: negating them put the muzzle below the floor.
            var sc = n2.Scale;
            float facing = Mathf.Sign(sc.X == 0 ? 1 : sc.X);
            var gpos = n2.GlobalPosition + new Vector2(wx * sc.X, wy * sc.Y);
            DyeFramework.Log($"attack fx: muzzle_gpos={gpos} facing={facing} sc={sc} bone={_boneName}");
            int seq = ++_fireSeq;
            for (int i = 0; i < _burstTimes.Length; i++)
            {
                if (_burstTimes[i] <= 0f)
                {
                    Burst(gpos, facing);
                }
                else
                {
                    float delay = _burstTimes[i];
                    var t = new Timer { WaitTime = delay, OneShot = true, Autostart = true };
                    DyeFramework.Tree?.Root.AddChild(t);
                    int captured = seq;
                    t.Timeout += () =>
                    {
                        try
                        {
                            if (captured == _fireSeq && GodotObject.IsInstanceValid(n2))
                            {
                                // re-read the bone: the arm moves between shots
                                var sk2 = _target.Call("get_skeleton").AsGodotObject();
                                var b2 = sk2?.Call("find_bone", _boneName).AsGodotObject();
                                Vector2 g2 = gpos;
                                if (b2 != null)
                                {
                                    float mx = b2.Call("get_world_x").AsSingle();
                                    float my = b2.Call("get_world_y").AsSingle();
                                    g2 = n2.GlobalPosition + new Vector2(mx * n2.Scale.X, my * n2.Scale.Y);
                                }
                                Burst(g2, facing);
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

    private void Burst(Vector2 gpos, float facing)
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

    private static void FreeLater(CpuParticles2D p, double delay)
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

