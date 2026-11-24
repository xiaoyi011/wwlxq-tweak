// AWJ Android tweak core: il2cpp runtime calls for the GM panel
#include <jni.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <dirent.h>
#include <pthread.h>
#include <unistd.h>
#include <android/log.h>

#define TAG "AWJ"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// ---------------- il2cpp ----------------
static void* (*x_domain_get)(void);
static void** (*x_domain_get_assemblies)(void*, size_t*);
static void* (*x_assembly_get_image)(void*);
static const char* (*x_image_get_name)(void*);
static void* (*x_class_from_name)(void*, const char*, const char*);
static void* (*x_class_get_method_from_name)(void*, const char*, int);
static void* (*x_object_get_class)(void*);
static void* (*x_class_get_field_from_name)(void*, const char*);
static size_t (*x_field_get_offset)(void*);
static const char* (*x_class_get_namespace)(void*);
static const char* (*x_method_get_param_name)(void*, uint32_t);
static void (*x_field_static_get_value)(void*, void*);
static void (*x_field_get_value)(void*, void*, void*);
static void (*x_field_set_value)(void*, void*, void*);
static void* (*x_runtime_invoke)(void*, void*, void**, void**);
static void* (*x_string_new)(const char*);
static void* (*x_thread_attach)(void*);
static void* (*x_domain_assembly_open)(void*, const char*);
static void* (*x_class_get_methods)(void*, void**);
static const char* (*x_method_get_name)(void*);
static void* (*x_class_get_fields)(void*, void**);
static const char* (*x_field_get_name)(void*);
static size_t (*x_image_get_class_count)(void*);
static void* (*x_image_get_class)(void*, size_t);
static const char* (*x_class_get_name)(void*);
static void* (*x_field_get_type)(void*);
static void* (*x_method_get_pointer)(void*);
static uint32_t (*x_field_get_flags)(void*);
static const char* (*x_type_get_name)(void*);
static uint32_t (*x_method_get_param_count)(void*);
static void* (*x_method_get_param)(void*, uint32_t);
static void* (*x_class_from_type)(void*);

static void* g_lib;

static void* sym(const char* n) {
    if (!g_lib) g_lib = dlopen("libil2cpp.so", RTLD_NOW);
    if (!g_lib) return NULL;
    return dlsym(g_lib, n);
}

#define RESOLVE(v, n) do { v = (void*)sym(n); if (!v) LOGE("missing %s", n); } while (0)

static int resolve_api(void) {
    RESOLVE(x_domain_get, "il2cpp_domain_get");
    RESOLVE(x_domain_get_assemblies, "il2cpp_domain_get_assemblies");
    RESOLVE(x_assembly_get_image, "il2cpp_assembly_get_image");
    RESOLVE(x_image_get_name, "il2cpp_image_get_name");
    RESOLVE(x_class_from_name, "il2cpp_class_from_name");
    RESOLVE(x_class_get_method_from_name, "il2cpp_class_get_method_from_name");
    RESOLVE(x_object_get_class, "il2cpp_object_get_class");
    RESOLVE(x_class_get_field_from_name, "il2cpp_class_get_field_from_name");
    RESOLVE(x_field_get_offset, "il2cpp_field_get_offset");
    RESOLVE(x_class_get_namespace, "il2cpp_class_get_namespace");
    RESOLVE(x_method_get_param_name, "il2cpp_method_get_param_name");
    RESOLVE(x_field_static_get_value, "il2cpp_field_static_get_value");
    RESOLVE(x_field_get_value, "il2cpp_field_get_value");
    RESOLVE(x_field_set_value, "il2cpp_field_set_value");
    RESOLVE(x_runtime_invoke, "il2cpp_runtime_invoke");
    RESOLVE(x_string_new, "il2cpp_string_new");
    RESOLVE(x_thread_attach, "il2cpp_thread_attach");
    RESOLVE(x_domain_assembly_open, "il2cpp_domain_assembly_open");
    RESOLVE(x_class_get_methods, "il2cpp_class_get_methods");
    RESOLVE(x_method_get_name, "il2cpp_method_get_name");
    RESOLVE(x_class_get_fields, "il2cpp_class_get_fields");
    RESOLVE(x_field_get_name, "il2cpp_field_get_name");
    RESOLVE(x_image_get_class_count, "il2cpp_image_get_class_count");
    RESOLVE(x_image_get_class, "il2cpp_image_get_class");
    RESOLVE(x_class_get_name, "il2cpp_class_get_name");
    RESOLVE(x_field_get_type, "il2cpp_field_get_type");
    RESOLVE(x_method_get_pointer, "il2cpp_method_get_pointer");
    RESOLVE(x_field_get_offset, "il2cpp_field_get_offset");
    RESOLVE(x_class_get_namespace, "il2cpp_class_get_namespace");
    RESOLVE(x_method_get_param_name, "il2cpp_method_get_param_name");
    RESOLVE(x_field_get_flags, "il2cpp_field_get_flags");
    RESOLVE(x_type_get_name, "il2cpp_type_get_name");
    RESOLVE(x_method_get_param_count, "il2cpp_method_get_param_count");
    RESOLVE(x_method_get_param, "il2cpp_method_get_param");
    RESOLVE(x_class_from_type, "il2cpp_class_from_type");
    return x_domain_get && x_runtime_invoke && x_class_from_name;
}

// ---------------- game objects ----------------
static void* g_image;
static void* g_dv_class;
static void* g_main_panel_field;
static void* g_view_field;
static void* g_m_kill_monster;
static void* g_m_cheat;
static void* g_m_kill_robot;
static void* g_m_exec_lua;
static void* g_m_sp;
static void* g_m_inv;
static void* g_m_brute;
static void* g_ts_setter;
static void* g_m_fastfwd;
static void* g_ff_input;
static void* g_m_set_sp;
static void* g_sp_input;
static void* g_m_change_attr_name;
static void* g_m_change_attr_slot;
static void* g_debug_view_field;
static void* g_m_open_debug;
static void* g_f_is_battle;
static void* g_m_place_hero;
static void* g_hero_input;
static void* g_lua_input_field;
static void* g_bpvp_field;
static void* g_m_set_result;
static void* g_m_check_result;
static void* g_m_set_result;
static void* g_m_check_result;
static void* g_bproxy_field;
static void* g_m_is_pvp;
static void* g_level_field;
static void* g_maxround_field;
static void* g_round_field;
static void* g_ls_field;
static void* g_m_set_speed;
static void* g_maxframes_field;

static void* class_of(void* image, const char* name) {
    return x_class_from_name(image, "Game.Bussiness", name);
}

static void* g_domain;

static void* find_image(const char* prefix) {
    void* d = g_domain;
    LOGI("find_image d=%p", d);
    if (!d) return NULL;
    if (x_domain_assembly_open) {
        LOGI("opening assembly by name");
        void* a = x_domain_assembly_open(d, "Assembly-CSharp");
        LOGI("assembly=%p", a);
        if (a) {
            void* img = x_assembly_get_image(a);
            LOGI("image=%p", img);
            if (img) return img;
        }
    }
    LOGI("assembly open failed");
    (void)prefix;
    return NULL;
}

static int resolve_game(void) {
    if (!g_image) {
        g_image = find_image("Assembly-CSharp");
        if (!g_image) return 0;
        LOGI("image found");
    }
    void* dv = class_of(g_image, "BattleDebugActionView");
    void* bd = class_of(g_image, "BattleDefine");
    void* mp = class_of(g_image, "BattleMainPanel");
    void* bve = class_of(g_image, "BaseViewExtend");
    void* bpp = class_of(g_image, "BattlePvpProxy");
    if (bpp && x_class_get_method_from_name) { g_m_set_result = x_class_get_method_from_name(bpp, "SetBattleResult", 2); g_m_check_result = x_class_get_method_from_name(bpp, "CheckResult", 0); LOGI("SetBattleResult=%p CheckResult=%p", g_m_set_result, g_m_check_result); }
    void* bp  = class_of(g_image, "BattleProxy");
    void* blp = class_of(g_image, "BattleLevelProxy");
    void* lsc = class_of(g_image, "BattleLockStepCtrl");
    if (!dv || !bd || !mp || !bve || !bpp) return 0;

    g_dv_class = dv;
    g_main_panel_field = x_class_get_field_from_name(bd, "mainPanel");
    g_view_field = x_class_get_field_from_name(mp, "battleDebugActionView");
    g_m_kill_monster = x_class_get_method_from_name(dv, "OnKillMonster", 0);
    g_m_cheat = x_class_get_method_from_name(dv, "OnCheatClick", 0);
    g_m_kill_robot = x_class_get_method_from_name(dv, "OnKillRobotClick", 1);
    g_m_exec_lua = x_class_get_method_from_name(dv, "OnExecuteLuaClick", 0);
    g_m_sp = x_class_get_method_from_name(dv, "OnSpClick", 0);
    g_m_inv = x_class_get_method_from_name(dv, "OnSelfInvulnerableStationClick", 0);
    g_m_brute = x_class_get_method_from_name(dv, "OnBruteForceTestClick", 0);
    {
        void* bdv = class_of(g_image, "BattleDebugView");
        if (bdv && mp) {
            g_debug_view_field = x_class_get_field_from_name(mp, "battleDebugView");
            g_m_open_debug = x_class_get_method_from_name(bdv, "OnOpenClick", 0);
        }
        LOGI("native gm entry: field=%p open=%p", g_debug_view_field, g_m_open_debug);
        void* bpc = class_of(g_image, "BattleProxy");
        if (bpc) {
            g_f_is_battle = x_class_get_field_from_name(bpc, "isBattle");
            if (!g_f_is_battle) g_f_is_battle = x_class_get_field_from_name(bpc, "isBeginBattle");
        }
        LOGI("isBattle field=%p", g_f_is_battle);
        if (bdv && x_class_get_methods && x_method_get_name) {
            void* it = NULL;
            void* m;
            int n = 0;
            while ((m = x_class_get_methods(bdv, &it)) != NULL && n < 200) {
                const char* mn = x_method_get_name(m);
                if (mn && (strstr(mn, "Star") || strstr(mn, "Win") || strstr(mn, "Pass") ||
                           strstr(mn, "Kill") || strstr(mn, "Result")))
                    LOGI("BDV %s", mn);
                n++;
            }
        }
    }
    g_m_fastfwd = x_class_get_method_from_name(dv, "OnFastForwardClicked", 0);
    g_m_place_hero = x_class_get_method_from_name(dv, "OnPlaceHeroClick", 0);
    g_hero_input = x_class_get_field_from_name(dv, "placeHeroInput");
    g_ff_input = x_class_get_field_from_name(dv, "fastForwardInput");
    g_m_set_sp = x_class_get_method_from_name(dv, "OnSetSp", 0);
    g_sp_input = x_class_get_field_from_name(dv, "setSpInput");
    if (x_domain_assembly_open && g_domain) {
        void* core_asm = x_domain_assembly_open(g_domain, "UnityEngine.CoreModule");
        void* core_img = core_asm ? x_assembly_get_image(core_asm) : NULL;
        void* time_cls = core_img ? x_class_from_name(core_img, "UnityEngine", "Time") : NULL;
        if (time_cls) {
            g_ts_setter = x_class_get_method_from_name(time_cls, "set_timeScale", 1);
            LOGI("timeScale setter=%p", g_ts_setter);
        } else {
            LOGE("Time class not found");
        }
    }
    g_lua_input_field = x_class_get_field_from_name(dv, "luaCodeInput");
    g_bpvp_field = x_class_get_field_from_name(bve, "battlePvpProxy");
    if (bpp) {
        g_m_set_result = x_class_get_method_from_name(bpp, "SetBattleResult", 2);
        g_bproxy_field = x_class_get_field_from_name(bpp, "battleProxy");
        g_round_field = x_class_get_field_from_name(bpp, "round");
    }
    if (bp) g_m_is_pvp = x_class_get_method_from_name(bp, "IsPvp", 0);
    if (bve) g_level_field = x_class_get_field_from_name(bve, "battleLevelProxy");
    if (blp) g_maxround_field = x_class_get_field_from_name(blp, "maxRound");
    if (bve) g_ls_field = x_class_get_field_from_name(bve, "battleLockStepCtrl");
    if (lsc) {
        g_m_set_speed = x_class_get_method_from_name(lsc, "SetSpeedUpRate", 1);
        g_maxframes_field = x_class_get_field_from_name(lsc, "maxLogicFramesPerTick");
    }
    if (x_class_get_methods && x_method_get_name) {
        void* it = NULL;
        void* m;
        int n = 0;
        while ((m = x_class_get_methods(dv, &it)) != NULL && n < 80) {
            const char* nm = x_method_get_name(m);
            if (nm) LOGI("GMM %s", nm);
            n++;
        }
    }
    if (x_class_get_fields && x_field_get_name) {
        void* it = NULL;
        void* f;
        int n = 0;
        while ((f = x_class_get_fields(dv, &it)) != NULL && n < 60) {
            const char* nm = x_field_get_name(f);
            if (nm) LOGI("GMF %s", nm);
            n++;
        }
    }
    if (0 && x_image_get_class_count && x_image_get_class && x_class_get_name &&
        x_class_get_fields && x_field_get_name) {
        static const char* keys[] = {"crit", "Crit", "attack", "Attack", "atk", "Atk",
                                     "hp", "Hp", "def", "Def", "speed", "Speed"};
        size_t cc = x_image_get_class_count(g_image);
        int found = 0;
        for (size_t i = 0; i < cc && found < 30; i++) {
            void* c = x_image_get_class(g_image, i);
            if (!c) continue;
            const char* cn2 = x_class_get_name(c);
            if (!cn2) continue;
            int hits = 0;
            void* it = NULL;
            void* f;
            while ((f = x_class_get_fields(c, &it)) != NULL) {
                const char* fn = x_field_get_name(f);
                if (!fn) continue;
                for (int k = 0; k < 12; k++) {
                    if (strstr(fn, keys[k])) { hits++; break; }
                }
            }
            if (hits < 2) continue;
            found++;
            LOGI("ATTRCLS %s hits=%d", cn2, hits);
            it = NULL;
            int n = 0;
            while ((f = x_class_get_fields(c, &it)) != NULL && n < 24) {
                const char* fn = x_field_get_name(f);
                if (!fn) continue;
                for (int k = 0; k < 12; k++) {
                    if (strstr(fn, keys[k])) { LOGI("   %s", fn); break; }
                }
                n++;
            }
        }
        LOGI("attrscan found=%d total=%d", found, (int)cc);
    }
    if (0 && x_field_get_type && x_type_get_name && x_method_get_name &&
        x_image_get_class_count && x_image_get_class && x_class_get_name) {
        size_t cc2 = x_image_get_class_count(g_image);
        int refs = 0;
        for (size_t i = 0; i < cc2 && refs < 30; i++) {
            void* c = x_image_get_class(g_image, i);
            if (!c) continue;
            const char* cn3 = x_class_get_name(c);
            if (!cn3 || strcmp(cn3, "AttrSlot") == 0) continue;
            if (!x_class_get_fields || !x_field_get_name) continue;
            void* it = NULL;
            void* f;
            while ((f = x_class_get_fields(c, &it)) != NULL) {
                void* t = x_field_get_type(f);
                const char* tn = t ? x_type_get_name(t) : NULL;
                if (tn && strstr(tn, "AttrSlot")) {
                    const char* fn = x_field_get_name(f);
                    LOGI("SLOTREF %s.%s", cn3, fn ? fn : "?");
                    refs++;
                    if (refs >= 30) break;
                }
            }
        }
        LOGI("slotref holders=%d", refs);
        static const char* mnames[] = {"ChangeAttr", "OnSetEntityBaseAttr", "ChangeHeroAttribute",
                                       "SetHeroEchoAttribute", "GetRoleAttr", "ChangeRoleAttr",
                                       "ChangeSpecAttr", "SetSpecAttr", "AddSpecialAttr"};
        int mhits = 0;
        for (size_t i = 0; i < cc2 && mhits < 30; i++) {
            void* c = x_image_get_class(g_image, i);
            if (!c) continue;
            const char* cn4 = x_class_get_name(c);
            if (!cn4) continue;
            if (!x_class_get_methods || !x_method_get_name) continue;
            void* it = NULL;
            void* m;
            while ((m = x_class_get_methods(c, &it)) != NULL) {
                const char* mn = x_method_get_name(m);
                if (!mn) continue;
                int hit = 0;
                for (int k = 0; k < 9; k++) if (strcmp(mn, mnames[k]) == 0) { hit = 1; break; }
                if (!hit) continue;
                uint32_t pc = x_method_get_param_count ? x_method_get_param_count(m) : 0;
                char sig[192];
                sig[0] = 0;
                for (uint32_t p = 0; p < pc && p < 6; p++) {
                    void* pt = x_method_get_param ? x_method_get_param(m, p) : NULL;
                    const char* ptn = pt ? x_type_get_name(pt) : NULL;
                    strncat(sig, ptn ? ptn : "?", sizeof(sig) - strlen(sig) - 1);
                    if (p + 1 < pc) strncat(sig, ",", sizeof(sig) - strlen(sig) - 1);
                }
                LOGI("MSIG %s.%s(%s)", cn4, mn, sig);
                mhits++;
                if (mhits >= 30) break;
            }
        }
        LOGI("msig hits=%d", mhits);
    }
    if (0 && x_image_get_class_count && x_image_get_class && x_class_get_name &&
        x_class_get_fields && x_field_get_name) {
        size_t cc3 = x_image_get_class_count(g_image);
        for (size_t i = 0; i < cc3; i++) {
            void* c = x_image_get_class(g_image, i);
            const char* n = c ? x_class_get_name(c) : NULL;
            if (!n) continue;
            int want = 0;
            if (strstr(n, "AttrType")) want = 1;
            else if (strcmp(n, "BattleProxy") == 0 || strcmp(n, "BattleEntityProxy") == 0 ||
                     strcmp(n, "BattleBaseEntity") == 0 || strcmp(n, "BattleHeroEntity") == 0 ||
                     strcmp(n, "KvData") == 0) want = 2;
            if (!want) continue;
            LOGI("PROBE cls %s", n);
            void* it = NULL;
            void* f;
            int k = 0;
            while ((f = x_class_get_fields(c, &it)) != NULL && k < 40) {
                const char* fn = x_field_get_name(f);
                void* t = x_field_get_type(f);
                const char* tn = t ? x_type_get_name(t) : NULL;
                LOGI("  F %s : %s", fn ? fn : "?", tn ? tn : "?");
                if (want == 1 && fn && x_field_static_get_value) {
                    int64_t val = 0;
                    x_field_static_get_value(f, &val);
                    LOGI("    V %s=%lld", fn, (long long)val);
                }
                k++;
            }
            if (x_class_get_methods && x_method_get_name) {
                it = NULL;
                void* m;
                k = 0;
                while ((m = x_class_get_methods(c, &it)) != NULL && k < 60) {
                    const char* mn = x_method_get_name(m);
                    if (mn && (strstr(mn, "Entity") || strstr(mn, "Attr") ||
                               strstr(mn, "Role") || strstr(mn, "Hero"))) {
                        LOGI("  M %s", mn);
                    }
                    k++;
                }
            }
        }
        LOGI("probe done");
    }
    if (0) {
        static const char* tnames[] = {"AttrType", "BattleBaseEntity", "BattleHeroEntity",
                                       "BattleEntityProxy", "BattleProxy", "BattleReduceHpCtrl",
                                       "BattleMainPanel"};
        for (int ti = 0; ti < 7; ti++) {
            void* c = class_of(g_image, tnames[ti]);
            if (!c) c = x_class_from_name(g_image, "Game.BussinessData", tnames[ti]);
            if (!c) { LOGI("TGT %s missing", tnames[ti]); continue; }
            LOGI("TGT %s", tnames[ti]);
            if (x_class_get_fields && x_field_get_name) {
                void* it = NULL;
                void* f;
                int k = 0;
                while ((f = x_class_get_fields(c, &it)) != NULL && k < 40) {
                    const char* fn = x_field_get_name(f);
                    LOGI("  F %s", fn ? fn : "?");
                    if (strcmp(tnames[ti], "AttrType") == 0 && fn && x_field_static_get_value) {
                        int64_t val = 0;
                        x_field_static_get_value(f, &val);
                        LOGI("    V %s=%lld", fn, (long long)val);
                    }
                    k++;
                }
            }
            if (x_class_get_methods && x_method_get_name) {
                void* it = NULL;
                void* m;
                int k = 0;
                while ((m = x_class_get_methods(c, &it)) != NULL && k < 60) {
                    const char* mn = x_method_get_name(m);
                    if (mn && (strstr(mn, "Attr") || strstr(mn, "Entity") || strstr(mn, "Hero") ||
                               strstr(mn, "Role") || strstr(mn, "Get") || strstr(mn, "Set")))
                        LOGI("  M %s", mn);
                    k++;
                }
            }
        }
        void* e = class_of(g_image, "BattleBaseEntity");
        if (e && x_class_get_methods && x_method_get_name && x_method_get_param_count &&
            x_method_get_param && x_type_get_name) {
            void* it = NULL;
            void* m;
            int found = 0;
            while ((m = x_class_get_methods(e, &it)) != NULL && found < 6) {
                const char* mn = x_method_get_name(m);
                if (!mn || strcmp(mn, "ChangeAttr") != 0) continue;
                uint32_t pc = x_method_get_param_count(m);
                if (pc != 3) continue;
                void* p0 = x_method_get_param(m, 0);
                void* p2 = x_method_get_param(m, 2);
                const char* t0 = p0 ? x_type_get_name(p0) : NULL;
                const char* t2 = p2 ? x_type_get_name(p2) : NULL;
                LOGI("ChangeAttr sig (%s,?,%s)", t0 ? t0 : "?", t2 ? t2 : "?");
                if (t2 && strstr(t2, "AttrType") && x_class_from_type && x_field_static_get_value) {
                    void* et = x_class_from_type(p2);
                    if (et && x_class_get_fields && x_field_get_name) {
                        void* it2 = NULL;
                        void* ef;
                        int k2 = 0;
                        while ((ef = x_class_get_fields(et, &it2)) != NULL && k2 < 80) {
                            const char* efn = x_field_get_name(ef);
                            if (efn) {
                                int64_t ev = 0;
                                x_field_static_get_value(ef, &ev);
                                LOGI("ENUM %s=%lld", efn, (long long)ev);
                            }
                            k2++;
                        }
                    }
                }
                if (t0 && strstr(t0, "String") && t2 && strstr(t2, "AttrType")) g_m_change_attr_name = m;
                if (t0 && strstr(t0, "AttrSlot")) g_m_change_attr_slot = m;
                found++;
            }
            LOGI("changeAttr name=%p slot=%p", g_m_change_attr_name, g_m_change_attr_slot);
        }
        void* epx = class_of(g_image, "BattleEntityProxy");
        if (epx && x_class_get_methods && x_method_get_name && x_method_get_param_count &&
            x_method_get_param && x_type_get_name) {
            void* it = NULL;
            void* m;
            int n = 0;
            while ((m = x_class_get_methods(epx, &it)) != NULL && n < 90) {
                const char* mn = x_method_get_name(m);
                if (mn && (strcmp(mn, "GetEntity") == 0 || strcmp(mn, "GetHeroEntityByBaseId") == 0 ||
                           strcmp(mn, "GetHeroListByGroupIndex") == 0 ||
                           strcmp(mn, "GetEntityListByGroupIndex") == 0)) {
                    uint32_t pc = x_method_get_param_count(m);
                    char sig[128];
                    sig[0] = 0;
                    for (uint32_t p = 0; p < pc && p < 4; p++) {
                        void* pt = x_method_get_param(m, p);
                        const char* tn = pt ? x_type_get_name(pt) : NULL;
                        strncat(sig, tn ? tn : "?", sizeof(sig) - strlen(sig) - 1);
                        if (p + 1 < pc) strncat(sig, ",", sizeof(sig) - strlen(sig) - 1);
                    }
                    LOGI("EPX %s(%s)", mn, sig);
                }
                n++;
            }
        }
        LOGI("tgt done");
    }
    if (0 && x_image_get_class_count && x_image_get_class && x_class_get_name &&
        x_class_get_fields && x_field_get_name) {
        size_t cw = x_image_get_class_count(g_image);
        int shown = 0;
        for (size_t i = 0; i < cw && shown < 40; i++) {
            void* c = x_image_get_class(g_image, i);
            const char* n = c ? x_class_get_name(c) : NULL;
            if (!n) continue;
            if (!strstr(n, "Rampart") && !strstr(n, "Station") &&
                !strstr(n, "Wall") && !strstr(n, "Castle")) continue;
            shown++;
            LOGI("WCLS %s", n);
            void* it = NULL;
            void* f;
            int k = 0;
            while ((f = x_class_get_fields(c, &it)) != NULL && k < 20) {
                const char* fn = x_field_get_name(f);
                if (fn) LOGI("  WF %s", fn);
                k++;
            }
            if (x_class_get_methods && x_method_get_name) {
                it = NULL;
                void* m;
                k = 0;
                while ((m = x_class_get_methods(c, &it)) != NULL && k < 25) {
                    const char* mn = x_method_get_name(m);
                    if (mn && (strstr(mn, "Hp") || strstr(mn, "Attr") || strstr(mn, "Set") ||
                               strstr(mn, "Get") || strstr(mn, "Change") || strstr(mn, "Add")))
                        LOGI("  WM %s", mn);
                    k++;
                }
            }
        }
        LOGI("wallscan shown=%d", shown);
    }
    if (0) {
        static const char* w2[] = {"EntityData", "BattleRampartStrategyEntity", "BattleRampartEntity"};
        for (int i = 0; i < 3; i++) {
            void* c = class_of(g_image, w2[i]);
            if (!c) c = x_class_from_name(g_image, "Game.BussinessData", w2[i]);
            if (!c) { LOGI("W2 %s missing", w2[i]); continue; }
            LOGI("W2 %s", w2[i]);
            if (x_class_get_fields && x_field_get_name) {
                void* it = NULL;
                void* f;
                int k = 0;
                while ((f = x_class_get_fields(c, &it)) != NULL && k < 30) {
                    const char* fn = x_field_get_name(f);
                    if (fn) LOGI("  W2F %s", fn);
                    k++;
                }
            }
        }
        void* ep = class_of(g_image, "BattleEntityProxy");
        if (ep && x_class_get_methods && x_method_get_name) {
            void* it = NULL;
            void* m;
            int k = 0;
            while ((m = x_class_get_methods(ep, &it)) != NULL && k < 120) {
                const char* mn = x_method_get_name(m);
                if (mn && (strstr(mn, "Rampart") || strstr(mn, "Wall") ||
                           strstr(mn, "Station") || strstr(mn, "Tower")))
                    LOGI("W2M %s", mn);
                k++;
            }
        }
        LOGI("w2 done");
    }
    if (0) {
        void* rctrl = class_of(g_image, "BattleReduceHpCtrl");
        (void)rctrl;
        if (rctrl && x_class_get_field_from_name) {
            void* f = x_class_get_field_from_name(rctrl, "battleEntityProxy");
            if (f && x_field_static_get_value) {
                void* v = NULL;
                x_field_static_get_value(f, &v);
                LOGI("PROBE proxy static=%p", v);
            }
        }
        void* ed = class_of(g_image, "EntityData");
        if (!ed && x_class_from_name) ed = x_class_from_name(g_image, "Game.BussinessData", "EntityData");
        if (ed && x_class_get_field_from_name) {
            void* fa = x_class_get_field_from_name(ed, "attr");
            LOGI("PROBE EntityData attr field=%p", fa);
            if (fa && x_field_get_type && x_class_from_type) {
                void* ac = x_class_from_type(x_field_get_type(fa));
                LOGI("PROBE attr class=%p", ac);
                if (ac) {
                    const char* need[] = {"base_crit", "add_crit", "base_crit_dmg", "add_crit_dmg",
                                          "base_phy_atk", "add_phy_atk", "final_mult_phy_atk",
                                          "final_mult_atk_speed", "base_atk_speed", "add_atk_speed",
                                          "base_hit", "add_hit"};
                    for (int i = 0; i < 12; i++) {
                        void* af = x_class_get_field_from_name(ac, need[i]);
                        LOGI("PROBE AF %s=%p", need[i], af);
                    }
                }
            }
        }
        void* ep = class_of(g_image, "BattleEntityProxy");
        if (ep && x_class_get_methods && x_method_get_name && x_method_get_param_count &&
            x_method_get_param && x_type_get_name) {
            void* it = NULL;
            void* m;
            int n = 0;
            while ((m = x_class_get_methods(ep, &it)) != NULL && n < 120) {
                const char* mn = x_method_get_name(m);
                if (mn && (strstr(mn, "HeroEntity") || strcmp(mn, "GetEntity") == 0 ||
                           strstr(mn, "GetEntityList"))) {
                    uint32_t pc = x_method_get_param_count(m);
                    char sig[128];
                    sig[0] = 0;
                    for (uint32_t p = 0; p < pc && p < 4; p++) {
                        void* pt = x_method_get_param(m, p);
                        const char* tn = pt ? x_type_get_name(pt) : NULL;
                        strncat(sig, tn ? tn : "?", sizeof(sig) - strlen(sig) - 1);
                        if (p + 1 < pc) strncat(sig, ",", sizeof(sig) - strlen(sig) - 1);
                    }
                    LOGI("PROBE EP %s(%s)", mn, sig);
                }
                n++;
            }
        }
    }
    if (0) {
        void* rc = class_of(g_image, "BattleReduceHpCtrl");
        void* v1 = NULL;
        void* v2 = NULL;
        if (rc && x_class_get_field_from_name) {
            void* f1 = x_class_get_field_from_name(rc, "battleEntityProxy");
            void* f2 = x_class_get_field_from_name(rc, "battleProxy");
            if (f1 && x_field_static_get_value) x_field_static_get_value(f1, &v1);
            if (f2 && x_field_static_get_value) x_field_static_get_value(f2, &v2);
        }
        LOGI("P3 proxy=%p battle=%p", v1, v2);
        void* ep = class_of(g_image, "BattleEntityProxy");
        if (ep && x_class_get_methods && x_method_get_name && x_method_get_param_count &&
            x_method_get_param && x_type_get_name) {
            void* it = NULL;
            void* m;
            int n = 0;
            while ((m = x_class_get_methods(ep, &it)) != NULL && n < 120) {
                const char* mn = x_method_get_name(m);
                if (mn && (strstr(mn, "HeroEntity") || strcmp(mn, "GetEntity") == 0 ||
                           strstr(mn, "GetEntityList"))) {
                    uint32_t pc = x_method_get_param_count(m);
                    char sig[128];
                    sig[0] = 0;
                    for (uint32_t p = 0; p < pc && p < 4; p++) {
                        void* pt = x_method_get_param(m, p);
                        const char* tn = pt ? x_type_get_name(pt) : NULL;
                        strncat(sig, tn ? tn : "?", sizeof(sig) - strlen(sig) - 1);
                        if (p + 1 < pc) strncat(sig, ",", sizeof(sig) - strlen(sig) - 1);
                    }
                    LOGI("P3M %s(%s)", mn, sig);
                }
                n++;
            }
        }
    }
    LOGI("resolved: kill=%d cheat=%d win=%d lua=%d speed=%d",
         g_m_kill_monster != NULL, g_m_cheat != NULL, g_m_kill_robot != NULL,
         g_m_exec_lua != NULL, g_m_set_speed != NULL);
    return g_m_kill_monster && g_m_cheat && g_main_panel_field && g_view_field;
}

static void* view(void) {
    if (!g_main_panel_field) return NULL;
    void* panel = NULL;
    x_field_static_get_value(g_main_panel_field, &panel);
    if (!panel) return NULL;
    void* v = NULL;
    x_field_get_value(panel, g_view_field, &v);
    return v;
}

static void invoke0(void* m, void* obj) {
    if (!m || !obj) return;
    void* exc = NULL;
    x_runtime_invoke(m, obj, NULL, &exc);
    if (exc) LOGE("invoke exception");
}

static int is_pvp(void) {
    if (!g_bpvp_field || !g_bproxy_field || !g_m_is_pvp) return -1;
    void* proxy = NULL;
    x_field_static_get_value(g_bpvp_field, &proxy);
    if (!proxy) return -1;
    void* bp = NULL;
    x_field_get_value(proxy, g_bproxy_field, &bp);
    if (!bp) return -1;
    void* exc = NULL;
    void* r = x_runtime_invoke(g_m_is_pvp, bp, NULL, &exc);
    if (exc || !r) return -1;
    return *(uint8_t*)r ? 1 : 0;
}

static void do_clear(void) {
    int32_t cur = 0, maxr = 0;
    if (g_bpvp_field && g_round_field && x_field_static_get_value && x_field_get_value) {
        void* pp = NULL;
        x_field_static_get_value(g_bpvp_field, &pp);
        if (pp) x_field_get_value(pp, g_round_field, &cur);
    }
    if (g_level_field && g_maxround_field && x_field_static_get_value && x_field_get_value) {
        void* lp = NULL;
        x_field_static_get_value(g_level_field, &lp);
        if (lp) x_field_get_value(lp, g_maxround_field, &maxr);
    }
    if (cur <= 0 || maxr <= 0) {
        LOGI("clear skip round=%d max=%d", cur, maxr);
        return;
    }
    LOGI("clear round=%d/%d", cur, maxr);
    invoke0(g_m_kill_monster, view());
}

static void do_win(void) {
    int pvp = is_pvp();
    LOGI("win pvp=%d", pvp);
    if (pvp != 0) {
        void* proxy = NULL;
        x_field_static_get_value(g_bpvp_field, &proxy);
        if (proxy && g_m_set_result) {
            int32_t r = 1;
            uint8_t force = 1;
            void* params[2] = { &r, &force };
            void* exc = NULL;
            x_runtime_invoke(g_m_set_result, proxy, params, &exc);
            if (!exc) return;
        }
    }
    // PVE: 把当前回合设为最后一回合再清场
    if (g_level_field && g_maxround_field && g_round_field && x_field_set_value) {
        void* pp = NULL, *lp = NULL;
        x_field_static_get_value(g_bpvp_field, &pp);
        x_field_static_get_value(g_level_field, &lp);
        if (pp && lp) {
            int32_t cur = 0;
            x_field_get_value(pp, g_round_field, &cur);
            if (cur > 0) x_field_set_value(lp, g_maxround_field, &cur);
        }
    }
    do_clear();
}

static void do_speed(float rate) {
    if (rate < 1) rate = 1;
    if (rate > 10) rate = 10;
    if (!g_ls_field || !g_m_set_speed) return;
    void* ls = NULL;
    x_field_static_get_value(g_ls_field, &ls);
    if (!ls) return;
    float r = rate;
    void* params[1] = { &r };
    void* exc = NULL;
    x_runtime_invoke(g_m_set_speed, ls, params, &exc);
    if (g_maxframes_field && x_field_set_value) {
        int32_t mf = (int)(rate * 8);
        if (mf < 8) mf = 8;
        if (mf > 64) mf = 64;
        x_field_set_value(ls, g_maxframes_field, &mf);
    }
}

// 通过游戏命令台修改属性 / 怪物血量
static int exec_cmd(const char* cmd) {
    void* v = view();
    if (!v || !g_lua_input_field || !g_m_exec_lua || !x_string_new) return 0;
    void* inp = NULL;
    x_field_get_value(v, g_lua_input_field, &inp);
    if (!inp) return 0;
    void* cls = x_object_get_class(inp);
    void* setter = cls ? x_class_get_method_from_name(cls, "set_text", 1) : NULL;
    if (!setter) return 0;
    void* s = x_string_new(cmd);
    void* params[1] = { s };
    void* exc = NULL;
    x_runtime_invoke(setter, inp, params, &exc);
    if (exc) return 0;
    exc = NULL;
    x_runtime_invoke(g_m_exec_lua, v, NULL, &exc);
    return exc == NULL;
}

// ---------------- JNI ----------------
static void* g_java_vm;

static __thread int t_attached = 0;

static void ensure_thread(void) {
    if (t_attached || !g_domain || !x_thread_attach) return;
    x_thread_attach(g_domain);
    t_attached = 1;
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_java_vm = vm;
    return JNI_VERSION_1_6;
}

static int unity_ready(void) {
    DIR* d = opendir("/proc/self/task");
    if (!d) return 0;
    struct dirent* e;
    int ok = 0;
    char path[256], buf[64];
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        snprintf(path, sizeof(path), "/proc/self/task/%s/comm", e->d_name);
        FILE* f = fopen(path, "r");
        if (!f) continue;
        if (fgets(buf, sizeof(buf), f) && strstr(buf, "UnityMain")) ok = 1;
        fclose(f);
        if (ok) break;
    }
    closedir(d);
    return ok;
}

static void probe_param_types(const char* cn) {
    void* c = class_of(g_image, cn);
    if (!c) { LOGI("P4 %s: null", cn); return; }
    void* it = NULL; void* m; int n = 0;
    while ((m = x_class_get_methods(c, &it)) != NULL && n < 40) {
        const char* nm = x_method_get_name(m);
        uint32_t pc = x_method_get_param_count ? x_method_get_param_count(m) : 0;
        int interesting = nm && (strstr(nm,"Settle")||strstr(nm,"Over")||strstr(nm,"Result")||strstr(nm,"Execute")||strstr(nm,"Update"));
        if (interesting) {
            LOGI("P4M %s::%s pc=%u ptr=%p", cn, nm, pc, x_method_get_pointer ? x_method_get_pointer(m) : NULL);
            for (uint32_t pi = 0; pi < pc && pi < 5; pi++) {
                void* pt = x_method_get_param ? x_method_get_param(m, pi) : NULL;
                const char* pn = x_method_get_param_name ? x_method_get_param_name(m, pi) : NULL;
                const char* tn = pt && x_type_get_name ? x_type_get_name(pt) : "?";
                LOGI("P4P %s::%s param%d %s : %s", cn, nm, pi, pn ? pn : "?", tn ? tn : "?");
            }
            n++;
        }
    }
    LOGI("P4 %s done=%d", cn, n);
}

static void dump_cls_fields(void* c, const char* tag) {
    if (!c) { LOGI("P5 %s class null", tag); return; }
    const char* nm = x_class_get_name ? x_class_get_name(c) : "?";
    const char* ns = x_class_get_namespace ? x_class_get_namespace(c) : "?";
    LOGI("P5 %s = %s.%s", tag, ns ? ns : "?", nm ? nm : "?");
    if (!x_class_get_fields || !x_field_get_name) return;
    void* it = NULL; void* f; int n = 0;
    while ((f = x_class_get_fields(c, &it)) != NULL && n < 80) {
        const char* fn = x_field_get_name(f);
        void* ft = x_field_get_type ? x_field_get_type(f) : NULL;
        const char* tn = ft && x_type_get_name ? x_type_get_name(ft) : "?";
        size_t off = x_field_get_offset ? x_field_get_offset(f) : 0;
        LOGI("P5F %s::%s : %s off=%zu", tag, fn ? fn : "?", tn ? tn : "?", off);
        n++;
    }
    LOGI("P5 %s fields=%d", tag, n);
}

static void probe_names(void* c, const char* tag) {
    if (!c) { LOGI("P6 %s null", tag); return; }
    void* it = NULL; void* m; int n = 0;
    while (x_class_get_methods && (m = x_class_get_methods(c, &it)) != NULL && n < 260) {
        const char* nm = x_method_get_name(m);
        uint32_t pc = x_method_get_param_count ? x_method_get_param_count(m) : 0;
        LOGI("P6 %s::%s pc=%u", tag, nm ? nm : "?", pc);
        n++;
    }
    LOGI("P6 %s methods=%d", tag, n);
}

static void probe_level_flow(void) {
    probe_names(class_of(g_image, "BattleLevelProxy"), "BattleLevelProxy");
    probe_names(class_of(g_image, "BattleProxy"), "BattleProxy");
    probe_names(class_of(g_image, "BattleMainPanel"), "BattleMainPanel");
    // level/next 相关类
    if (x_image_get_class_count && x_image_get_class && x_class_get_name) {
        size_t cnt = x_image_get_class_count(g_image);
        int hits = 0;
        for (size_t i = 0; i < cnt && hits < 30; i++) {
            void* c = x_image_get_class(g_image, i);
            if (!c) continue;
            const char* nm = x_class_get_name(c);
            if (nm && (strstr(nm, "LevelProxy") || strstr(nm, "LevelData") || strstr(nm, "Stage"))) { LOGI("P6C %s", nm); hits++; }
        }
    }
}
static void probe_result_type(void) {
    void* bpp = class_of(g_image, "BattlePvpProxy");
    if (bpp && x_class_get_method_from_name) { g_m_set_result = x_class_get_method_from_name(bpp, "SetBattleResult", 2); g_m_check_result = x_class_get_method_from_name(bpp, "CheckResult", 0); LOGI("SetBattleResult=%p CheckResult=%p", g_m_set_result, g_m_check_result); }
    if (!bpp) { LOGI("P5 BattlePvpProxy null"); return; }
    void* rf = x_class_get_field_from_name ? x_class_get_field_from_name(bpp, "result") : NULL;
    LOGI("P5 result field=%p", rf);
    void* rt = rf && x_field_get_type ? x_field_get_type(rf) : NULL;
    void* rc = rt && x_class_from_type ? x_class_from_type(rt) : NULL;
    LOGI("P5 result type=%p class=%p", rt, rc);
    dump_cls_fields(rc, "BattleResult");
    if (rc && x_class_get_methods) {
        void* it = NULL; void* m; int n = 0;
        while ((m = x_class_get_methods(rc, &it)) != NULL && n < 30) {
            const char* mn = x_method_get_name(m);
            uint32_t pc = x_method_get_param_count ? x_method_get_param_count(m) : 0;
            LOGI("P5M BattleResult::%s pc=%u ptr=%p", mn ? mn : "?", pc, x_method_get_pointer ? x_method_get_pointer(m) : NULL);
            n++;
        }
    }
    dump_cls_fields(class_of(g_image, "Sc16510"), "Sc16510");
}
static void probe_result_obj(void) {
    void* c = class_of(g_image, "BattleResult");
    if (!c) { LOGI("P4 BattleResult: null"); return; }
    const char* ns = x_class_get_namespace ? x_class_get_namespace(c) : NULL;
    LOGI("P4 BattleResult ns=%s name=%s", ns ? ns : "?", x_class_get_name(c));
    if (x_class_get_fields && x_field_get_name) {
        void* it = NULL; void* f; int n = 0;
        while ((f = x_class_get_fields(c, &it)) != NULL && n < 80) {
            const char* fn = x_field_get_name(f);
            void* ft = x_field_get_type ? x_field_get_type(f) : NULL;
            const char* tn = ft && x_type_get_name ? x_type_get_name(ft) : "?";
            size_t off = x_field_get_offset ? x_field_get_offset(f) : 0;
            LOGI("P4R %s : %s off=%zu", fn ? fn : "?", tn ? tn : "?", off);
            n++;
        }
    }
    void* it2 = NULL; void* m2; int k = 0;
    while (x_class_get_methods && (m2 = x_class_get_methods(c, &it2)) != NULL && k < 40) {
        const char* nm = x_method_get_name(m2);
        uint32_t pc = x_method_get_param_count ? x_method_get_param_count(m2) : 0;
        LOGI("P4RM %s pc=%u ptr=%p", nm ? nm : "?", pc, x_method_get_pointer ? x_method_get_pointer(m2) : NULL);
        k++;
    }
}
static void probe_dump_class(const char* cn) {
    void* c = class_of(g_image, cn);
    if (!c) { LOGI("P3 %s: null", cn); return; }
    void* it = NULL; void* m; int n = 0;
    if (x_class_get_methods && x_method_get_name) {
        while ((m = x_class_get_methods(c, &it)) != NULL && n < 200) {
            const char* nm = x_method_get_name(m);
            uint32_t pc = x_method_get_param_count ? x_method_get_param_count(m) : 0;
            LOGI("P3M %s::%s pc=%u ptr=%p", cn, nm ? nm : "?", pc, x_method_get_pointer ? x_method_get_pointer(m) : NULL);
            n++;
        }
    }
    LOGI("P3 %s methods=%d", cn, n);
    if (x_class_get_fields && x_field_get_name && x_field_get_type && x_type_get_name) {
        void* fit = NULL; void* fld; int fn = 0;
        while ((fld = x_class_get_fields(c, &fit)) != NULL && fn < 120) {
            const char* fname = x_field_get_name(fld);
            void* ft = x_field_get_type(fld);
            const char* tname = ft && x_type_get_name ? x_type_get_name(ft) : "?";
            LOGI("P3F %s::%s : %s", cn, fname ? fname : "?", tname ? tname : "?");
            fn++;
        }
        LOGI("P3 %s fields=%d", cn, fn);
    }
}

static void probe_scan_classes(void) {
    if (!x_image_get_class_count || !x_image_get_class || !x_class_get_name) { LOGI("P3 scan: no api"); return; }
    size_t cnt = x_image_get_class_count(g_image);
    LOGI("P3 scan total=%zu", cnt);
    int hits = 0;
    for (size_t i = 0; i < cnt && hits < 40; i++) {
        void* c = x_image_get_class(g_image, i);
        if (!c) continue;
        const char* nm = x_class_get_name(c);
        if (!nm) continue;
        if (strstr(nm, "Result") || strstr(nm, "Settle")) { LOGI("P3C %s", nm); hits++; }
    }
    LOGI("P3 scan hits=%d", hits);
}
static void probe_settle_api(void) {
    if (!x_class_get_methods || !x_method_get_name) { LOGI("P2 no api"); return; }
    const char* names[] = {"BattleResultProxy","BattleResultCtrl","BattleResultView","BattleLevelProxy",
                           "BattleProxy","BattleOverResultParam","BattleResultDataParam","BattleDefine",
                           "BattleMainPanel","BattleResultData","BattleResultWindow"};
    for (int i = 0; i < 11; i++) {
        void* c = class_of(g_image, names[i]);
        if (!c) { LOGI("P2 %s: null", names[i]); continue; }
        int n = 0;
        void* it = NULL; void* m;
        while ((m = x_class_get_methods(c, &it)) != NULL && n < 120) {
            const char* nm = x_method_get_name(m);
            if (nm && (strstr(nm,"Result")||strstr(nm,"Settle")||strstr(nm,"Win")||strstr(nm,"Star")||strstr(nm,"Reward")||strstr(nm,"Finish")||strstr(nm,"Close")||strstr(nm,"Create")||strstr(nm,"Check"))) {
                uint32_t pc = x_method_get_param_count ? x_method_get_param_count(m) : 0;
                LOGI("P2 %s::%s pc=%u m=%p", names[i], nm, pc, m);
                n++;
            }
        }
        LOGI("P2 %s end n=%d", names[i], n);
    }
}
static void probe_update_ptrs(void) {
    if (!x_method_get_pointer || !x_class_get_methods) { LOGI("probe: no pointer api"); return; }
    const char* cls_names[] = {"BattleLockStepCtrl", "BattleProxy", "BattleMainPanel", "BattleReduceHpCtrl", "BattleLogicCtrl"};
    for (int ci = 0; ci < 5; ci++) {
        void* c = class_of(g_image, cls_names[ci]);
        if (!c) { LOGI("probe %s: null", cls_names[ci]); continue; }
        void* it = NULL;
        const void* ms = x_class_get_methods(c, &it);
        int shown = 0;
        while (ms && shown < 16) {
            void* m = (void*)ms;
            const char* nm = x_method_get_name ? x_method_get_name(m) : NULL;
            if (nm && strstr(nm, "Update")) {
                uint32_t pc = x_method_get_param_count ? x_method_get_param_count(m) : 0;
                LOGI("probe %s.%s pc=%u ptr=%p", cls_names[ci], nm, pc, x_method_get_pointer(m));
                shown++;
            }
            ms = x_class_get_methods(c, &it);
        }
        LOGI("probe %s shown=%d", cls_names[ci], shown);
    }
}

JNIEXPORT jint JNICALL
Java_com_awj_Native_init(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    static time_t g_ready_at = 0;
    if (!unity_ready()) { g_ready_at = 0; return -3; }
    if (g_ready_at == 0) { g_ready_at = time(NULL); LOGI("unity main seen"); }
    if (time(NULL) - g_ready_at < 5) return -4;
    LOGI("resolving api");
    if (!resolve_api()) { LOGE("api resolve failed"); return -1; }
    LOGI("api ok");
    void* dom = x_domain_get();
    if (!dom) { LOGE("domain null"); return -2; }
    LOGI("domain ok %p", dom);
    g_domain = dom;
    if (x_thread_attach) { x_thread_attach(dom); LOGI("thread attached"); }
    int r = resolve_game() ? 1 : 0;
    LOGI("game resolve r=%d", r);
    if (r) {
        probe_update_ptrs();
        probe_settle_api();
        probe_result_type();
        probe_level_flow();
        probe_param_types("SettleBattleEvent");
        probe_param_types("BattlePvpProxy");
        probe_scan_classes();
    }
    return r;
}

JNIEXPORT void JNICALL
Java_com_awj_Native_finishWin(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    if (!g_bpvp_field || !g_m_set_result || !x_runtime_invoke) { LOGE("finishWin: no api"); return; }
    void* proxy = NULL;
    x_field_static_get_value(g_bpvp_field, &proxy);
    if (!proxy) { LOGE("finishWin: no proxy"); return; }
    int32_t res = 2;      // BattleResult.win
    uint8_t force = 1;
    void* args[2]; args[0] = &res; args[1] = &force;
    void* exc = NULL;
    x_runtime_invoke(g_m_set_result, proxy, args, &exc);
    LOGI("finishWin proxy=%p exc=%p", proxy, exc);
}
JNIEXPORT void JNICALL
Java_com_awj_Native_checkResult(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    if (!g_bpvp_field || !g_m_check_result || !x_runtime_invoke) { LOGE("checkResult: no api"); return; }
    void* proxy = NULL;
    x_field_static_get_value(g_bpvp_field, &proxy);
    if (!proxy) { LOGE("checkResult: no proxy"); return; }
    void* exc = NULL;
    x_runtime_invoke(g_m_check_result, proxy, NULL, &exc);
    LOGI("checkResult proxy=%p exc=%p", proxy, exc);
}
JNIEXPORT void JNICALL
Java_com_awj_Native_probeCompiled(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    const char* names[] = {"BattleLockStepCtrl","BattleMainPanel","BattleProxy","BattlePvpProxy",
                           "BattleResultCtrl","BattleReduceHpCtrl","BattleLogicCtrl","BattleMainView"};
    for (int i = 0; i < 8; i++) {
        void* c = class_of(g_image, names[i]);
        if (!c) { LOGI("PC %s: null", names[i]); continue; }
        void* it = NULL; void* m; int n = 0, live = 0;
        while ((m = x_class_get_methods(c, &it)) != NULL && n < 300) {
            const char* nm = x_method_get_name(m);
            void* p = x_method_get_pointer ? x_method_get_pointer(m) : NULL;
            if (p) {
                LOGI("PC %s::%s ptr=%p", names[i], nm ? nm : "?", p);
                live++;
            }
            n++;
        }
        LOGI("PC %s live=%d total=%d", names[i], live, n);
    }
}

JNIEXPORT void JNICALL
Java_com_awj_Native_sendOver(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    void* proxy = NULL;
    if (!g_bpvp_field || !x_runtime_invoke) { LOGE("sendOver: no api"); return; }
    x_field_static_get_value(g_bpvp_field, &proxy);
    if (!proxy) { LOGE("sendOver: no proxy"); return; }
    void* c = x_object_get_class(proxy);
    void* m = x_class_get_method_from_name(c, "SendOver", 0);
    if (!m) { LOGE("sendOver: no method"); return; }
    void* exc = NULL;
    x_runtime_invoke(m, proxy, NULL, &exc);
    LOGI("sendOver exc=%p", exc);
}
JNIEXPORT jint JNICALL
Java_com_awj_Native_ready(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    return (g_main_panel_field && g_m_kill_monster) ? 1 : 0;
}

static int in_battle(void) {
    if (!g_bpvp_field || !g_bproxy_field || !g_f_is_battle) return 0;
    if (!x_field_static_get_value || !x_field_get_value || !x_field_get_flags) return 0;
    // battlePvpProxy 必须是静态字段，否则跳过（避免误读导致崩溃）
    if ((x_field_get_flags(g_bpvp_field) & 0x10) == 0) return 0;
    void* pp = NULL;
    x_field_static_get_value(g_bpvp_field, &pp);
    if (!pp) return 0;
    void* bp = NULL;
    x_field_get_value(pp, g_bproxy_field, &bp);
    if (!bp) return 0;
    uint8_t v = 0;
    x_field_get_value(bp, g_f_is_battle, &v);
    return v ? 1 : 0;
}

JNIEXPORT jint JNICALL
Java_com_awj_Native_inBattle(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    return in_battle();
}

JNIEXPORT void JNICALL
Java_com_awj_Native_clear(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    static int cnt = 0;
    cnt++;
    void* v = view();
    if (cnt <= 5 || (cnt % 30) == 0) LOGI("clear #%d view=%p method=%p", cnt, v, g_m_kill_monster);
    do_clear();
    if (cnt <= 5) LOGI("clear #%d done", cnt);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_cheat(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    invoke0(g_m_cheat, view());
}

JNIEXPORT void JNICALL
Java_com_awj_Native_win(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    do_win();
}

JNIEXPORT void JNICALL
Java_com_awj_Native_speed(JNIEnv* env, jclass cls, jfloat rate) {
    (void)env; (void)cls;
    ensure_thread();
    do_speed(rate);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_timeScale(JNIEnv* env, jclass cls, jfloat v) {
    (void)env; (void)cls;
    ensure_thread();
    if (!g_ts_setter) { LOGE("timeScale setter missing"); return; }
    float r = v;
    void* params[1] = { &r };
    void* exc = NULL;
    x_runtime_invoke(g_ts_setter, NULL, params, &exc);
    LOGI("timeScale=%.2f exc=%p", r, exc);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_fastForward(JNIEnv* env, jclass cls, jint sec) {
    (void)env; (void)cls;
    ensure_thread();
    void* v = view();
    if (!v || !g_ff_input || !g_m_fastfwd || !x_string_new) { LOGE("ff missing"); return; }
    void* inp = NULL;
    x_field_get_value(v, g_ff_input, &inp);
    if (!inp) return;
    void* cls2 = x_object_get_class(inp);
    void* setter = cls2 ? x_class_get_method_from_name(cls2, "set_text", 1) : NULL;
    if (!setter) return;
    char buf[32];
    snprintf(buf, sizeof(buf), "%d", (int)sec);
    void* params[1] = { x_string_new(buf) };
    void* exc = NULL;
    x_runtime_invoke(setter, inp, params, &exc);
    if (exc) { LOGI("ff set_text exc"); return; }
    exc = NULL;
    x_runtime_invoke(g_m_fastfwd, v, NULL, &exc);
    LOGI("fastForward %d exc=%p", (int)sec, exc);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_setSp(JNIEnv* env, jclass cls, jlong v) {
    (void)env; (void)cls;
    ensure_thread();
    void* vv = view();
    if (!vv || !g_m_set_sp || !g_sp_input) { LOGE("setSp missing"); return; }
    void* inp = NULL;
    x_field_get_value(vv, g_sp_input, &inp);
    if (!inp) return;
    void* c2 = x_object_get_class(inp);
    void* setter = c2 ? x_class_get_method_from_name(c2, "set_text", 1) : NULL;
    if (!setter) return;
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", (long long)v);
    void* params[1] = { x_string_new(buf) };
    void* exc = NULL;
    x_runtime_invoke(setter, inp, params, &exc);
    if (exc) return;
    exc = NULL;
    x_runtime_invoke(g_m_set_sp, vv, NULL, &exc);
    LOGI("setSp %lld exc=%p", (long long)v, exc);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_sp(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    invoke0(g_m_sp, view());
}

JNIEXPORT void JNICALL
Java_com_awj_Native_inv(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    invoke0(g_m_inv, view());
}

JNIEXPORT void JNICALL
Java_com_awj_Native_starWin(JNIEnv* env, jclass cls, jint stars) {
    (void)env; (void)cls;
    ensure_thread();
    if (!g_m_kill_robot) { LOGE("starWin missing"); return; }
    int32_t s = (int32_t)stars;
    void* params[1] = { &s };
    void* exc = NULL;
    x_runtime_invoke(g_m_kill_robot, view(), params, &exc);
    LOGI("starWin %d exc=%p", (int)stars, exc);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_placeHero(JNIEnv* env, jclass cls, jstring name) {
    (void)env; (void)cls;
    ensure_thread();
    void* v = view();
    if (!v || !g_m_place_hero || !g_hero_input || !x_string_new) { LOGE("placeHero missing"); return; }
    void* inp = NULL;
    x_field_get_value(v, g_hero_input, &inp);
    if (!inp) { LOGE("placeHero no input"); return; }
    const char* txt = "雷神 4";
    const char* n = NULL;
    if (name) {
        n = (*env)->GetStringUTFChars(env, name, NULL);
        if (n) txt = n;
    }
    void* c2 = x_object_get_class(inp);
    void* setter = c2 ? x_class_get_method_from_name(c2, "set_text", 1) : NULL;
    if (!setter) { LOGE("placeHero no setter"); if (n) (*env)->ReleaseStringUTFChars(env, name, n); return; }
    void* params[1] = { x_string_new(txt) };
    void* exc = NULL;
    x_runtime_invoke(setter, inp, params, &exc);
    if (n) (*env)->ReleaseStringUTFChars(env, name, n);
    if (exc) { LOGE("placeHero set exc"); return; }
    exc = NULL;
    x_runtime_invoke(g_m_place_hero, v, NULL, &exc);
    LOGI("placeHero exc=%p", exc);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_openGm(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    if (!g_main_panel_field || !g_debug_view_field || !g_m_open_debug) {
        LOGE("openGm missing");
        return;
    }
    void* panel = NULL;
    x_field_static_get_value(g_main_panel_field, &panel);
    if (!panel) { LOGE("openGm no panel"); return; }
    void* v = NULL;
    x_field_get_value(panel, g_debug_view_field, &v);
    if (!v) { LOGE("openGm no view"); return; }
    void* exc = NULL;
    x_runtime_invoke(g_m_open_debug, v, NULL, &exc);
    LOGI("openGm exc=%p", exc);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_wallHp(JNIEnv* env, jclass cls, jlong v) {
    (void)env; (void)cls;
    ensure_thread();
    LOGI("wallHp %lld (pending)", (long long)v);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_brute(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    LOGI("brute click");
    invoke0(g_m_brute, view());
}

JNIEXPORT void JNICALL
Java_com_awj_Native_stopMove(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    ensure_thread();
    exec_cmd("停止怪物移动");
}

JNIEXPORT void JNICALL
Java_com_awj_Native_monsterHp(JNIEnv* env, jclass cls, jint pct) {
    (void)env; (void)cls;
    ensure_thread();
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "设置怪物血量百分比 %d", (int)pct);
    exec_cmd(cmd);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_lua(JNIEnv* env, jclass cls, jstring code) {
    (void)cls;
    ensure_thread();
    if (!code) return;
    const char* c = (*env)->GetStringUTFChars(env, code, NULL);
    if (!c) return;
    LOGI("lua: %s", c);
    exec_cmd(c);
    (*env)->ReleaseStringUTFChars(env, code, c);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_attr(JNIEnv* env, jclass cls, jstring name, jlong value) {
    if (!name) return;
    const char* n = (*env)->GetStringUTFChars(env, name, NULL);
    if (!n) return;
    char cmd[128];
    snprintf(cmd, sizeof(cmd), "修改英雄属性 %s %lld", n, (long long)value);
    exec_cmd(cmd);
    (*env)->ReleaseStringUTFChars(env, name, n);
}

// ---------------- 无 smali 注入：由 libmain.so 的 DT_NEEDED 自动加载 ----------------
static JavaVM* g_vm;

static int ensure_vm(void) {
    if (g_vm) return 1;
    jint (*getvms)(JavaVM**, jsize, jsize*) = (void*)dlsym(RTLD_DEFAULT, "JNI_GetCreatedJavaVMs");
    if (!getvms) {
        const char* libs[] = {"libart.so", "libnativehelper.so", "libnativebridge.so"};
        for (int i = 0; i < 3 && !getvms; i++) {
            void* h = dlopen(libs[i], RTLD_NOW);
            if (h) getvms = (void*)dlsym(h, "JNI_GetCreatedJavaVMs");
            LOGI("vm lib %s handle=%p sym=%p", libs[i], h, getvms);
        }
    }
    if (!getvms) { LOGE("no JNI_GetCreatedJavaVMs"); return 0; }
    JavaVM* vm = NULL;
    jsize n = 0;
    if (getvms(&vm, 1, &n) != 0 || !vm) { LOGE("no vm yet n=%d", (int)n); return 0; }
    g_vm = vm;
    LOGI("vm acquired");
    return 1;
}

static jobject current_app(JNIEnv* env) {
    jclass at = (*env)->FindClass(env, "android/app/ActivityThread");
    if (!at) return NULL;
    jmethodID m = (*env)->GetStaticMethodID(env, at, "currentApplication", "()Landroid/app/Application;");
    if (!m) return NULL;
    return (*env)->CallStaticObjectMethod(env, at, m);
}

static void* boot_thread(void* arg) {
    (void)arg;
    LOGI("boot thread start");
    for (int i = 0; i < 600; i++) {
        if ((i % 20) == 0) LOGI("boot tick %d", i);
        if (ensure_vm()) {
            JNIEnv* env = NULL;
            if ((*g_vm)->AttachCurrentThread(g_vm, &env, NULL) == JNI_OK && env) {
                jobject app = current_app(env);
                if (app) {
                    jclass ac = (*env)->GetObjectClass(env, app);
                    jmethodID gl = (*env)->GetMethodID(env, ac, "getClassLoader", "()Ljava/lang/ClassLoader;");
                    jobject cl = gl ? (*env)->CallObjectMethod(env, app, gl) : NULL;
                    if (cl) {
                        jclass clc = (*env)->FindClass(env, "java/lang/ClassLoader");
                        jmethodID load = (*env)->GetMethodID(env, clc, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;");
                        jstring nm = (*env)->NewStringUTF(env, "com.awj.Launcher");
                        jclass launcher = load ? (jclass)(*env)->CallObjectMethod(env, cl, load, nm) : NULL;
                        if (launcher) {
                            jmethodID mi = (*env)->GetStaticMethodID(env, launcher, "init", "(Landroid/content/Context;)V");
                            if (mi) {
                                (*env)->CallStaticVoidMethod(env, launcher, mi, app);
                                LOGI("launcher invoked");
                                (*g_vm)->DetachCurrentThread(g_vm);
                                return NULL;
                            }
                        }
                    }
                }
                (*g_vm)->DetachCurrentThread(g_vm);
            }
        }
        usleep(500 * 1000);
    }
    LOGE("boot timeout");
    return NULL;
}

__attribute__((constructor)) static void awj_ctor(void) {
    LOGI("ctor fired");
    pthread_t t;
    if (pthread_create(&t, NULL, boot_thread, NULL) == 0) pthread_detach(t);
    else LOGE("boot thread create failed");
}
