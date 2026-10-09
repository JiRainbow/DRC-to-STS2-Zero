// GLES interposer for uniform-value capture (x86_64 Android, LD_PRELOAD via wrap property)
// Interposes a minimal set of gl* symbols; everything else resolves to the real
// libGLESv2 by normal symbol fallthrough. Values are logged to the app-writable
// game data dir for programs whose shader source contains the hologram signature.
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <GLES3/gl31.h>

typedef unsigned int GLenum, GLuint;
typedef int GLint;
typedef float GLfloat;
typedef int GLsizei;
typedef char GLchar;
typedef unsigned char GLboolean;

static void* real_lib = 0;
static int logfd = -1;
static pthread_mutex_t logmu = PTHREAD_MUTEX_INITIALIZER;

// program -> has holo signature
#define MAXPROG 512
static GLuint prog_shader[MAXPROG];   // shader id per program slot (only 1 shader tracked per program is enough for signature)
static char prog_holo[MAXPROG];
static GLuint cur_prog = 0;

static void ensure_real(void) {
    if (!real_lib) {
        // preferred: the stashed copy of the original driver lib
        real_lib = dlopen("/data/local/tmp/libGLESv2.real.so", RTLD_NOW | RTLD_LOCAL);
        // fallback: the system GLES wrapper (MuMu: redirects to the kona driver)
        if (!real_lib) real_lib = dlopen("libGLESv2.so", RTLD_NOW | RTLD_LOCAL);
        // last resort: the vendor EGL driver directly
        if (!real_lib) real_lib = dlopen("/vendor/lib64/egl/libGLESv2_kona.so", RTLD_NOW | RTLD_LOCAL);
    }
}
static void log_open(void) {
    if (logfd < 0) {
        logfd = open("/data/data/com.zulong.drc.gw/files/glshim.log",
                     O_WRONLY | O_CREAT | O_APPEND, 0666);
    }
}
static int passthrough_only = 0; // set 1 for pure passthrough build
static void log_str(const char* s, int n) {
    if (passthrough_only) return;
    log_open();
    if (logfd >= 0) { pthread_mutex_lock(&logmu); write(logfd, s, n); pthread_mutex_unlock(&logmu); }
}

__attribute__((constructor))
static void shim_init(void) {
    // scrub the preload marker so environment-based checks don't see us
    setenv("LD_PRELOAD", "", 1);
    log_open();
    if (logfd >= 0) {
        char b[128];
        int n = snprintf(b, sizeof(b), "SHIM-LOADED pid=%d\n", (int)getpid());
        pthread_mutex_lock(&logmu); write(logfd, b, n); pthread_mutex_unlock(&logmu);
    }
}

static int prog_idx(GLuint p) { return (int)(p % MAXPROG); }

// ---- intercepted: shader source / program tracking ----
static char* last_src = 0;
static int    last_src_len = 0;
static GLuint last_shader = 0;

void glShaderSource(GLuint shader, GLsizei count, const GLchar* const* string, const GLint* length) {
    ensure_real();
    void (*p)(GLuint, GLsizei, const GLchar* const*, const GLint*) =
        dlsym(real_lib, "glShaderSource");
    int total = 0;
    for (GLsizei i = 0; i < count; i++) {
        total += (length && length[i] >= 0) ? length[i] : (int)strlen(string[i]);
    }
    if (total > 0 && total < (1 << 22)) {
        char* buf = (char*)malloc(total + 1);
        int at = 0;
        for (GLsizei i = 0; i < count; i++) {
            int n = (length && length[i] >= 0) ? length[i] : (int)strlen(string[i]);
            memcpy(buf + at, string[i], n); at += n;
        }
        buf[total] = 0;
        pthread_mutex_lock(&logmu);
        if (last_src) free(last_src);
        last_src = buf; last_src_len = total; last_shader = shader;
        pthread_mutex_unlock(&logmu);
    }
    if (p) p(shader, count, string, length);
}

void glAttachShader(GLuint program, GLuint shader) {
    ensure_real();
    void (*p)(GLuint, GLuint) = dlsym(real_lib, "glAttachShader");
    pthread_mutex_lock(&logmu);
    int i = prog_idx(program);
    if (last_src && last_shader == shader) {
        prog_shader[i] = shader;
        if (strstr(last_src, "pc2_h") || strstr(last_src, "MixColor"))
            prog_holo[i] = 1;
        // persist source once per shader for offline reference
        log_open();
        if (logfd >= 0) {
            char hdr[128];
            int n = snprintf(hdr, sizeof(hdr), "SRC %u %u %d\n", program, shader, last_src_len);
            write(logfd, hdr, n);
            write(logfd, last_src, last_src_len);
            write(logfd, "\n", 1);
        }
    }
    pthread_mutex_unlock(&logmu);
    if (p) p(program, shader);
}

void glUseProgram(GLuint program) {
    ensure_real();
    void (*p)(GLuint) = dlsym(real_lib, "glUseProgram");
    cur_prog = program;
    if (p) p(program);
}

// ---- intercepted: uniforms (log only for holo-flagged programs) ----
static int cur_holo(void) { return prog_holo[prog_idx(cur_prog)]; }

#define UNIFORM_BODY_LOGF(fmt) \
    if (cur_holo()) { \
        char b[256]; int n = snprintf(b, sizeof(b), fmt, cur_prog, __VA_ARGS__); \
        log_str(b, n); \
    }

void glUniform1f(GLint loc, GLfloat v0) {
    ensure_real(); void (*p)(GLint, GLfloat) = dlsym(real_lib, "glUniform1f");
    if (cur_holo()) { char b[128]; int n = snprintf(b, 128, "F %u %d %.6g\n", cur_prog, loc, v0); log_str(b, n); }
    if (p) p(loc, v0);
}
void glUniform2f(GLint loc, GLfloat v0, GLfloat v1) {
    ensure_real(); void (*p)(GLint, GLfloat, GLfloat) = dlsym(real_lib, "glUniform2f");
    if (cur_holo()) { char b[160]; int n = snprintf(b, 160, "F2 %u %d %.6g %.6g\n", cur_prog, loc, v0, v1); log_str(b, n); }
    if (p) p(loc, v0, v1);
}
void glUniform3f(GLint loc, GLfloat v0, GLfloat v1, GLfloat v2) {
    ensure_real(); void (*p)(GLint, GLfloat, GLfloat, GLfloat) = dlsym(real_lib, "glUniform3f");
    if (cur_holo()) { char b[192]; int n = snprintf(b, 192, "F3 %u %d %.6g %.6g %.6g\n", cur_prog, loc, v0, v1, v2); log_str(b, n); }
    if (p) p(loc, v0, v1, v2);
}
void glUniform4f(GLint loc, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3) {
    ensure_real(); void (*p)(GLint, GLfloat, GLfloat, GLfloat, GLfloat) = dlsym(real_lib, "glUniform4f");
    if (cur_holo()) { char b[224]; int n = snprintf(b, 224, "F4 %u %d %.6g %.6g %.6g %.6g\n", cur_prog, loc, v0, v1, v2, v3); log_str(b, n); }
    if (p) p(loc, v0, v1, v2, v3);
}
void glUniform1fv(GLint loc, GLsizei c, const GLfloat* v) {
    ensure_real(); void (*p)(GLint, GLsizei, const GLfloat*) = dlsym(real_lib, "glUniform1fv");
    if (cur_holo() && v) { char b[256]; int n = snprintf(b, 256, "FV1 %u %d %d %.6g %.6g %.6g %.6g\n", cur_prog, loc, c, v[0], (c>1?v[1]:0), (c>2?v[2]:0), (c>3?v[3]:0)); log_str(b, n); }
    if (p) p(loc, c, v);
}
void glUniform2fv(GLint loc, GLsizei c, const GLfloat* v) {
    ensure_real(); void (*p)(GLint, GLsizei, const GLfloat*) = dlsym(real_lib, "glUniform2fv");
    if (cur_holo() && v) { char b[256]; int n = snprintf(b, 256, "FV2 %u %d %d %.6g %.6g\n", cur_prog, loc, c, v[0], v[1]); log_str(b, n); }
    if (p) p(loc, c, v);
}
void glUniform3fv(GLint loc, GLsizei c, const GLfloat* v) {
    ensure_real(); void (*p)(GLint, GLsizei, const GLfloat*) = dlsym(real_lib, "glUniform3fv");
    if (v && c >= 1) {
        char b[256]; int n = snprintf(b, 256, "FV3 %u %d %d %.6g %.6g %.6g\n", cur_prog, loc, c, v[0], v[1], v[2]); log_str(b, n);
    }
    if (p) p(loc, c, v);
}
void glUniform4fv(GLint loc, GLsizei c, const GLfloat* v) {
    ensure_real(); void (*p)(GLint, GLsizei, const GLfloat*) = dlsym(real_lib, "glUniform4fv");
    if (v && c >= 1) {
        char b[256]; int n = snprintf(b, 256, "FV4 %u %d %d %.6g %.6g %.6g %.6g\n", cur_prog, loc, c, v[0], v[1], v[2], v[3]);
        log_str(b, n);
    }
    if (p) p(loc, c, v);
}
void glUniformMatrix4fv(GLint loc, GLsizei c, GLboolean t, const GLfloat* v) {
    ensure_real(); void (*p)(GLint, GLsizei, GLboolean, const GLfloat*) = dlsym(real_lib, "glUniformMatrix4fv");
    if (p) p(loc, c, t, v);
}
void glUniform1i(GLint loc, GLint v0) {
    ensure_real(); void (*p)(GLint, GLint) = dlsym(real_lib, "glUniform1i");
    if (cur_holo()) { char b[128]; int n = snprintf(b, 128, "I %u %d %d\n", cur_prog, loc, v0); log_str(b, n); }
    if (p) p(loc, v0);
}

// ---- intercepted: draws (mark frame boundaries for value freshness) ----
void glDrawArrays(GLenum mode, GLint first, GLsizei count) {
    ensure_real(); void (*p)(GLenum, GLint, GLsizei) = dlsym(real_lib, "glDrawArrays");
    if (cur_holo()) { char b[96]; int n = snprintf(b, 96, "DRAW %u %d %d %d\n", cur_prog, mode, first, count); log_str(b, n); }
    if (p) p(mode, first, count);
}
void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void* idx) {
    ensure_real(); void (*p)(GLenum, GLsizei, GLenum, const void*) = dlsym(real_lib, "glDrawElements");
    if (cur_holo()) { char b[96]; int n = snprintf(b, 96, "DRAWE %u %d %d\n", cur_prog, mode, count); log_str(b, n); }
    if (p) p(mode, count, type, idx);
}

// ---- debug: log all glEnable/glDisable enums (goldfish encoder rejects some) ----
static int dbg_on = -1;
void glEnable(GLenum what) {
    ensure_real(); void (*p)(GLenum) = dlsym(real_lib, "glEnable");
    if (dbg_on < 0) {
        dbg_on = access("/data/local/tmp/glshim_dbg", F_OK) == 0 ? 1 : 0;
        log_open();
    }
    if (dbg_on) { char b[96]; int n = snprintf(b, 96, "EN 1 %u\n", what); log_str(b, n); }
    if (p) p(what);
}
void glDisable(GLenum what) {
    ensure_real(); void (*p)(GLenum) = dlsym(real_lib, "glDisable");
    if (dbg_on < 0) {
        dbg_on = access("/data/local/tmp/glshim_dbg", F_OK) == 0 ? 1 : 0;
    }
    if (dbg_on) { char b[96]; int n = snprintf(b, 96, "EN 0 %u\n", what); log_str(b, n); }
    if (p) p(what);
}
