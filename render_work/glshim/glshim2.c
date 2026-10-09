// GLES interposer v2 - authoritative dye-constant capture for the Spine hologram
// material family (Dragon Raja, MuMu x86_64, LD_PRELOAD via wrap property).
// Upgrades over v1:
//   * uniform array submissions logged IN FULL (MixColor & co. live past vec4[0])
//   * vertex attrib streams dumped at draw time via driver state queries
//     (UV0/UV1/COLOR - settles the uv1.zw generation rule and the node color)
//   * large RGBA/compressed texture uploads dumped once per texture (MASK truth)
// Everything else forwards to the real libGLESv2 by dlsym fallthrough.
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <fcntl.h>
#include <unistd.h>
#include <GLES3/gl31.h>

typedef unsigned int GLenum, GLuint, GLbitfield;
typedef int GLint;
typedef float GLfloat;
typedef int GLsizei;
typedef char GLchar;
typedef unsigned char GLboolean;
typedef ptrdiff_t GLsizeiptr;
typedef intptr_t GLintptr;

static void* real_lib = 0;
static int logfd = -1;
static pthread_mutex_t logmu = PTHREAD_MUTEX_INITIALIZER;

#define MAXPROG 512
static char prog_holo[MAXPROG];
static unsigned int prog_hits[MAXPROG];       // holo draws per program
static GLuint cur_prog = 0;
static unsigned long long seq = 0;            // draw sequence
static int dumps_left = 600;                  // global vertex-draw dump budget
#define MAXTEX 65536
static unsigned char tex_dumped[MAXTEX >> 3];
static int tex_wh[MAXTEX][2];                 // [texid] = {w, h}, 0 = unknown

static void ensure_real(void) {
    if (!real_lib) {
        real_lib = dlopen("/data/local/tmp/libGLESv2.real.so", RTLD_NOW | RTLD_LOCAL);
        if (!real_lib) real_lib = dlopen("libGLESv2.so", RTLD_NOW | RTLD_LOCAL);
        if (!real_lib) real_lib = dlopen("/vendor/lib64/egl/libGLESv2_kona.so", RTLD_NOW | RTLD_LOCAL);
    }
}
static void log_open(void) {
    if (logfd < 0) {
        logfd = open("/data/data/com.zulong.drc.gw/files/glshim2.log",
                     O_WRONLY | O_CREAT | O_APPEND, 0666);
    }
}
static void log_str(const char* s, int n) {
    log_open();
    if (logfd >= 0) { pthread_mutex_lock(&logmu); write(logfd, s, n); pthread_mutex_unlock(&logmu); }
}
static void log_big(const char* hdr, int hn, const void* data, int n) {
    // one line: header + hex payload + '\n'
    log_open();
    if (logfd < 0) return;
    char* buf = (char*)malloc((size_t)n * 2 + hn + 2);
    if (!buf) return;
    memcpy(buf, hdr, hn);
    static const char hx[] = "0123456789abcdef";
    const unsigned char* p = (const unsigned char*)data;
    for (int i = 0; i < n; i++) {
        buf[hn + 2 * i] = hx[p[i] >> 4];
        buf[hn + 2 * i + 1] = hx[p[i] & 15];
    }
    buf[hn + 2 * n] = '\n';
    pthread_mutex_lock(&logmu);
    write(logfd, buf, hn + 2 * n + 1);
    pthread_mutex_unlock(&logmu);
    free(buf);
}

__attribute__((constructor))
static void shim_init(void) {
    setenv("LD_PRELOAD", "", 1);   // scrub preload marker (zeus anti-tamper scans env)
    log_open();
    if (logfd >= 0) {
        char b[128];
        int n = snprintf(b, sizeof(b), "SHIM2-LOADED pid=%d\n", (int)getpid());
        pthread_mutex_lock(&logmu); write(logfd, b, n); pthread_mutex_unlock(&logmu);
    }
}

static int prog_idx(GLuint p) { return (int)(p % MAXPROG); }

static char* last_src = 0;
static int    last_src_len = 0;
static GLuint last_shader = 0;
// ring cache so glAttachShader can log the source of the shader being
// attached (UE4 sources all shaders before attaching any of them).
#define SRING 64
static char*  ring_src[SRING];
static int    ring_len[SRING];
static char   ring_holo[SRING];

void glShaderSource(GLuint shader, GLsizei count, const GLchar* const* string, const GLint* length) {
    ensure_real();
    void (*p)(GLuint, GLsizei, const GLchar* const*, const GLint*) =
        dlsym(real_lib, "glShaderSource");
    int total = 0;
    for (GLsizei i = 0; i < count; i++)
        total += (length && length[i] >= 0) ? length[i] : (int)strlen(string[i]);
    if (total > 0 && total < (1 << 22)) {
        char* buf = (char*)malloc(total + 1);
        int at = 0;
        for (GLsizei i = 0; i < count; i++) {
            int n = (length && length[i] >= 0) ? length[i] : (int)strlen(string[i]);
            memcpy(buf + at, string[i], n); at += n;
        }
        buf[total] = 0;
        int slot = shader & (SRING - 1);
        pthread_mutex_lock(&logmu);
        if (ring_src[slot]) free(ring_src[slot]);
        ring_src[slot] = buf;
        ring_len[slot] = total;
        ring_holo[slot] =
            (strstr(buf, "pc2_h") || strstr(buf, "MixColor") ||
             strstr(buf, "ORIGINAL_POSITION") || strstr(buf, "pu_m")) ? 1 : 0;
        pthread_mutex_unlock(&logmu);
    }
    if (p) p(shader, count, string, length);
}

void glAttachShader(GLuint program, GLuint shader) {
    ensure_real();
    void (*p)(GLuint, GLuint) = dlsym(real_lib, "glAttachShader");
    int slot = shader & (SRING - 1);
    pthread_mutex_lock(&logmu);
    if (ring_src[slot]) {
        int i = prog_idx(program);
        if (ring_holo[slot]) prog_holo[i] = 1;
        char hdr[96];
        int n = snprintf(hdr, sizeof(hdr), "SRC %u %u %d\n", program, shader, ring_len[slot]);
        log_open();
        if (logfd >= 0) {
            write(logfd, hdr, n);
            write(logfd, ring_src[slot], ring_len[slot]);
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

static int cur_holo(void) { return prog_holo[prog_idx(cur_prog)]; }

// texture-bind trace for the active program: answers "which texture is ps0"
static void trace_bindtex(GLenum target, GLuint tex) {
    if (target != GL_TEXTURE_2D || tex == 0 || tex >= MAXTEX) return;
    if (!cur_holo()) return;
    void (*gi)(GLenum, GLint*) = dlsym(real_lib, "glGetIntegerv");
    int act = 0;
    if (gi) { GLint a = 0; gi(GL_ACTIVE_TEXTURE, &a); act = a - GL_TEXTURE0; }
    if (act > 3) return;                      // only sampler units 0..3
    int w = 0, h = 0;
    if (tex_wh[tex][0] == 0) {
        void (*gp)(GLenum, GLint, GLenum, GLint*) = dlsym(real_lib, "glGetTexLevelParameteriv");
        if (gp) {
            GLint W = 0, H = 0;
            gp(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &W);
            gp(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &H);
            tex_wh[tex][0] = W; tex_wh[tex][1] = H;
        }
    }
    w = tex_wh[tex][0]; h = tex_wh[tex][1];
    static GLuint last_prog = 0, last_tex = 0; static int last_act = -1, rep = 0;
    if (cur_prog == last_prog && tex == last_tex && act == last_act) { rep++; return; }
    char b[96]; int n = snprintf(b, 96, "BINDTEX %u u%d tex %u %dx%d\n", cur_prog, act, tex, w, h);
    log_str(b, n);
    if (rep > 0) { char r[48]; int rn = snprintf(r, 48, "  (+%d repeats)\n", rep); log_str(r, rn); rep = 0; }
    last_prog = cur_prog; last_tex = tex; last_act = act;
}

// ---- uniforms: full array logging for holo programs ----
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
    if (cur_holo() && v && c > 0) {
        int k = c > 96 ? 96 : c;
        char b[8192]; int n = snprintf(b, 8192, "FV1 %u %d %d", cur_prog, loc, c);
        for (int i = 0; i < k; i++) n += snprintf(b + n, 8192 - n, " %.6g", v[i]);
        n += snprintf(b + n, 8192 - n, "\n");
        log_str(b, n);
    }
    if (p) p(loc, c, v);
}
void glUniform2fv(GLint loc, GLsizei c, const GLfloat* v) {
    ensure_real(); void (*p)(GLint, GLsizei, const GLfloat*) = dlsym(real_lib, "glUniform2fv");
    if (cur_holo() && v && c > 0) {
        int k = c > 48 ? 48 : c;
        char b[8192]; int n = snprintf(b, 8192, "FV2 %u %d %d", cur_prog, loc, c);
        for (int i = 0; i < 2 * k; i++) n += snprintf(b + n, 8192 - n, " %.6g", v[i]);
        n += snprintf(b + n, 8192 - n, "\n");
        log_str(b, n);
    }
    if (p) p(loc, c, v);
}
void glUniform3fv(GLint loc, GLsizei c, const GLfloat* v) {
    ensure_real(); void (*p)(GLint, GLsizei, const GLfloat*) = dlsym(real_lib, "glUniform3fv");
    if (cur_holo() && v && c > 0) {
        int k = c > 32 ? 32 : c;
        char b[8192]; int n = snprintf(b, 8192, "FV3 %u %d %d", cur_prog, loc, c);
        for (int i = 0; i < 3 * k; i++) n += snprintf(b + n, 8192 - n, " %.6g", v[i]);
        n += snprintf(b + n, 8192 - n, "\n");
        log_str(b, n);
    }
    if (p) p(loc, c, v);
}
void glUniform4fv(GLint loc, GLsizei c, const GLfloat* v) {
    ensure_real(); void (*p)(GLint, GLsizei, const GLfloat*) = dlsym(real_lib, "glUniform4fv");
    if (cur_holo() && v && c > 0) {
        int k = c > 32 ? 32 : c;
        char b[8192]; int n = snprintf(b, 8192, "FV4 %u %d %d", cur_prog, loc, c);
        for (int i = 0; i < 4 * k; i++) n += snprintf(b + n, 8192 - n, " %.6g", v[i]);
        n += snprintf(b + n, 8192 - n, "\n");
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

// ---- draws: sequence marker + one-shot vertex attrib dumps ----
static int map_broken = 0;                    // set when a driver map fails/hangs
static void dump_vertex_attribs(GLuint prog, GLsizei count) {
    static unsigned char first_done[MAXPROG];
    int first = !first_done[prog_idx(prog)];
    static unsigned int first_budget = 96;    // separate budget for first dumps
    if (first) {
        if (first_budget == 0) { first_done[prog_idx(prog)] = 1; return; }
    } else {
        if (dumps_left <= 0 || map_broken) return;
        if (count < 24 || count > 60000) return;
    }
    unsigned int hits = ++prog_hits[prog_idx(prog)];
    // per-program first draw dumps unconditionally (battle programs must not
    // depend on the %400 lottery), repeats stay sparse
    if (!first) {
        if ((hits % 400) != 3) return;
    } else {
        first_done[prog_idx(prog)] = 1;
    }
    void (*gi)(GLenum, GLint*) = dlsym(real_lib, "glGetIntegerv");
    void (*gvai)(GLuint, GLenum, GLint*) = dlsym(real_lib, "glGetVertexAttribiv");
    void (*gvap)(GLuint, GLenum, void**) = dlsym(real_lib, "glGetVertexAttribPointerv");
    void (*bb)(GLenum, GLuint) = dlsym(real_lib, "glBindBuffer");
    void* (*mbr)(GLenum, GLintptr, GLsizeiptr, GLbitfield) = dlsym(real_lib, "glMapBufferRange");
    GLboolean (*ub)(GLenum) = dlsym(real_lib, "glUnmapBuffer");
    void (*gbsi)(GLenum, GLenum, GLint*) = dlsym(real_lib, "glGetBufferParameteriv");
    if (!gvai || !gvap || !gi) return;
    if (!first) dumps_left--;
    for (int idx = 0; idx < 16; idx++) {
        GLint en = 0, size = 0, type = 0, stride = 0, buf = 0;
        gvai(idx, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &en);
        if (!en) continue;
        gvai(idx, GL_VERTEX_ATTRIB_ARRAY_SIZE, &size);
        gvai(idx, GL_VERTEX_ATTRIB_ARRAY_TYPE, &type);
        gvai(idx, GL_VERTEX_ATTRIB_ARRAY_STRIDE, &stride);
        gvai(idx, GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING, &buf);
        void* ptr = 0;
        gvap(idx, GL_VERTEX_ATTRIB_ARRAY_POINTER, &ptr);
        int elem = size * (type == GL_FLOAT ? 4 : type == GL_UNSIGNED_BYTE ? 1 :
                           type == GL_HALF_FLOAT ? 2 : type == GL_UNSIGNED_SHORT ? 2 : 4);
        int eff = stride > 0 ? stride : elem;
        long long total = (long long)eff * (count - 1) + elem;
        if (total > 1200000) total = 1200000;
        char hdr[160];
        int hn = snprintf(hdr, sizeof(hdr), "VATTR %u %llu %d s%d t%d n%d st%d b%u o%zu c%d n%lld ",
                          prog, seq, idx, size, type, 0, stride, (unsigned)buf, (size_t)ptr, count, total);
        if (buf != 0 && mbr && bb && ub && gbsi) {
            GLint cur = 0, bsize = 0;
            gi(GL_ARRAY_BUFFER_BINDING, &cur);
            bb(GL_ARRAY_BUFFER, (GLuint)buf);
            gbsi(GL_ARRAY_BUFFER, GL_BUFFER_SIZE, &bsize);
            long long off = (long long)(size_t)ptr;
            long long need = off + total;
            if (bsize <= 0) {
                map_broken = 1;                    // size query failed: stop mapping
            } else if (need <= bsize && need <= (16 << 20)) {
                // MuMu's GL frontend wedges on mid-buffer map offsets:
                // map from 0 and slice client-side instead.
                void* m = mbr(GL_ARRAY_BUFFER, 0, (GLsizeiptr)need, GL_MAP_READ_BIT);
                if (m) {
                    log_big(hdr, hn, (const char*)m + (size_t)off, (int)total);
                    ub(GL_ARRAY_BUFFER);
                    if (first) first_budget--;
                } else {
                    if (!first) map_broken = 1;
                    hn = snprintf(hdr, sizeof(hdr), "VMAPFAIL %u %llu %d b%u\n", prog, seq, idx, (unsigned)buf);
                    log_str(hdr, hn);
                }
            }
            bb(GL_ARRAY_BUFFER, (GLuint)cur);
        } else if (buf == 0 && ptr) {
            log_big(hdr, hn, ptr, (int)total);
        }
    }
}

void glBindTexture(GLenum target, GLuint texture) {
    ensure_real();
    void (*p)(GLenum, GLuint) = dlsym(real_lib, "glBindTexture");
    trace_bindtex(target, texture);
    if (p) p(target, texture);
}

void glDrawArrays(GLenum mode, GLint first, GLsizei count) {
    ensure_real(); void (*p)(GLenum, GLint, GLsizei) = dlsym(real_lib, "glDrawArrays");
    if (cur_holo()) {
        char b[96]; int n = snprintf(b, 96, "DRAW %u %d %d %d\n", cur_prog, mode, first, count);
        log_str(b, n);
        dump_vertex_attribs(cur_prog, count);
    }
    seq++;
    if (p) p(mode, first, count);
}
void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void* idx) {
    ensure_real(); void (*p)(GLenum, GLsizei, GLenum, const void*) = dlsym(real_lib, "glDrawElements");
    if (cur_holo()) {
        char b[96]; int n = snprintf(b, 96, "DRAWE %u %d %d\n", cur_prog, mode, count);
        log_str(b, n);
        dump_vertex_attribs(cur_prog, count);
    }
    seq++;
    if (p) p(mode, count, type, idx);
}

// ---- texture uploads: one dump per texture object for big CPU-side images ----
static void maybe_dump_texture(GLsizei w, GLsizei h, GLenum fmt, GLenum type, const void* pixels, int compressed, GLsizei imgsize) {
    if (!pixels) return;
    long long npx = (long long)w * h;
    int interesting = 0;
    GLsizei nbytes = 0;
    if (!compressed && type == GL_UNSIGNED_BYTE &&
        (fmt == GL_RGBA || fmt == GL_RGB) && npx >= 262144 && npx <= 4194304) {
        interesting = 1;
        nbytes = (GLsizei)npx * (fmt == GL_RGBA ? 4 : 3);
    } else if (compressed && imgsize >= 131072 && imgsize <= 4194304) {
        interesting = 1;
        nbytes = imgsize;
    }
    if (!interesting) return;
    void (*gi)(GLenum, GLint*) = dlsym(real_lib, "glGetIntegerv");
    if (!gi) return;
    GLint tex = 0;
    gi(GL_TEXTURE_BINDING_2D, &tex);
    if (tex <= 0 || tex >= MAXTEX) return;
    if (tex_dumped[tex >> 3] & (1 << (tex & 7))) return;
    tex_dumped[tex >> 3] |= (unsigned char)(1 << (tex & 7));
    if (nbytes > 3000000) nbytes = 3000000;
    char hdr[160];
    int hn = snprintf(hdr, sizeof(hdr), "TEX %u %d %d f%u t%u c%d n%d ", (unsigned)tex, w, h, fmt, type, compressed, nbytes);
    log_big(hdr, hn, pixels, nbytes);
}

void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei w, GLsizei h,
                  GLint border, GLenum fmt, GLenum type, const void* pixels) {
    ensure_real();
    void (*p)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void*) =
        dlsym(real_lib, "glTexImage2D");
    if (p && pixels && target == GL_TEXTURE_2D && level == 0)
        maybe_dump_texture(w, h, fmt, type, pixels, 0, 0);
    if (p) p(target, level, internalformat, w, h, border, fmt, type, pixels);
}
void glTexSubImage2D(GLenum target, GLint level, GLint xo, GLint yo, GLsizei w, GLsizei h,
                     GLenum fmt, GLenum type, const void* pixels) {
    ensure_real();
    void (*p)(GLenum, GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, const void*) =
        dlsym(real_lib, "glTexSubImage2D");
    if (p && pixels && target == GL_TEXTURE_2D && level == 0 && xo == 0 && yo == 0)
        maybe_dump_texture(w, h, fmt, type, pixels, 0, 0);
    if (p) p(target, level, xo, yo, w, h, fmt, type, pixels);
}
void glCompressedTexImage2D(GLenum target, GLint level, GLenum internalformat, GLsizei w, GLsizei h,
                            GLint border, GLsizei imgsize, const void* pixels) {
    ensure_real();
    void (*p)(GLenum, GLint, GLenum, GLsizei, GLsizei, GLint, GLsizei, const void*) =
        dlsym(real_lib, "glCompressedTexImage2D");
    if (p && pixels && target == GL_TEXTURE_2D && level == 0)
        maybe_dump_texture(w, h, internalformat, 0, pixels, 1, imgsize);
    if (p) p(target, level, internalformat, w, h, border, imgsize, pixels);
}
void glCompressedTexSubImage2D(GLenum target, GLint level, GLint xo, GLint yo,
                               GLsizei w, GLsizei h, GLenum fmt, GLsizei imgsize, const void* pixels) {
    ensure_real();
    void (*p)(GLenum, GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLsizei, const void*) =
        dlsym(real_lib, "glCompressedTexSubImage2D");
    if (p && pixels && target == GL_TEXTURE_2D && level == 0 && xo == 0 && yo == 0)
        maybe_dump_texture(w, h, fmt, 0, pixels, 1, imgsize);
    if (p) p(target, level, xo, yo, w, h, fmt, imgsize, pixels);
}
