// Full-corpus decompiler export for libUE4.so (416k functions).
// Output: chunked .c files + functions index CSV + callgraph edges CSV + failures CSV.
// args: <outDir> <threads>
//@category DRC
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

public class DRCDecompileAll extends GhidraScript {

    static final int MAX_FN_BYTES = 3_000_000;   // cap pathological outputs
    static final int CHUNK_BYTES = 8_000_000;    // rotate chunk after ~8MB

    PrintWriter idxW, cgW, failW;
    final Object lock = new Object();
    final AtomicInteger chunkCounter = new AtomicInteger(0);
    final AtomicInteger done = new AtomicInteger(0);
    final AtomicInteger failed = new AtomicInteger(0);
    final AtomicInteger skipped = new AtomicInteger(0);
    File outDir;
    long t0;
    List<Function> fns;

    class ChunkWriter {
        final int id;
        final PrintWriter pw;
        int bytes = 0;
        ChunkWriter(int id) throws IOException {
            this.id = id;
            this.pw = new PrintWriter(new BufferedWriter(new OutputStreamWriter(
                    new FileOutputStream(new File(outDir, String.format("part_%06d.c", id))),
                    StandardCharsets.UTF_8)));
        }
        void write(String s) { pw.print(s); bytes += s.length(); pw.flush(); }
        boolean full() { return bytes >= CHUNK_BYTES; }
        void close() { pw.close(); }
    }

    class Worker implements Runnable {
        final int tid;
        DecompInterface di;
        ChunkWriter cw;
        Worker(int tid) { this.tid = tid; }
        @Override public void run() {
            try {
                di = new DecompInterface();
                di.setOptions(new DecompileOptions());
                di.openProgram(currentProgram);
                synchronized (lock) { cw = new ChunkWriter(chunkCounter.getAndIncrement()); }
                int n = fns.size();
                while (true) {
                    int i = cursor.getAndIncrement();
                    if (i >= n) break;
                    try {
                        processOne(fns.get(i));
                    } catch (Throwable th) {
                        Function f = fns.get(i);
                        recordFailure(f, "exc:" + th.getClass().getSimpleName(), "exception");
                    }
                    int d = done.incrementAndGet();
                    if (d % 5000 == 0) {
                        long el = (System.currentTimeMillis() - t0) / 1000;
                        println("progress " + d + "/" + n + " fail=" + failed.get()
                                + " skip=" + skipped.get() + " " + el + "s");
                    }
                }
                synchronized (lock) { cw.close(); }
                di.dispose();
            } catch (Throwable fatal) {
                println("worker " + tid + " fatal: " + fatal);
            }
        }
        void rotate() throws IOException {
            synchronized (lock) { cw.close(); }
            synchronized (lock) { cw = new ChunkWriter(chunkCounter.getAndIncrement()); }
        }
        void recordFailure(Function f, String reason, String status) {
            String addr = "0x" + Long.toHexString(f.getEntryPoint().getOffset());
            String nm = csv(f.getName());
            synchronized (lock) {
                failW.println(addr + "," + nm + "," + reason.replace(",", " "));
                idxW.println(addr + "," + nm + "," + f.getBody().getNumAddresses() + ",0,,0," + status);
                failed.incrementAndGet();
            }
        }
        void processOne(Function f) throws Exception {
            long addr = f.getEntryPoint().getOffset();
            long size = f.getBody().getNumAddresses();
            String name = f.getName();
            String ahex = "0x" + Long.toHexString(addr);

            Set<Function> callees = f.getCalledFunctions(monitor);
            if (!callees.isEmpty()) {
                StringBuilder sb = new StringBuilder();
                for (Function c : callees) {
                    sb.append(ahex).append(',').append(csv(name)).append(",0x")
                      .append(Long.toHexString(c.getEntryPoint().getOffset())).append(',')
                      .append(csv(c.getName())).append('\n');
                }
                synchronized (lock) { cgW.print(sb); }
            }

            if (f.isThunk()) {
                synchronized (lock) {
                    idxW.println(ahex + "," + csv(name) + "," + size + ",1,,0,thunk");
                    skipped.incrementAndGet();
                }
                return;
            }
            if (f.isExternal()) {
                synchronized (lock) {
                    idxW.println(ahex + "," + csv(name) + "," + size + ",0,,0,external");
                    skipped.incrementAndGet();
                }
                return;
            }

            DecompileResults res = di.decompileFunction(f, 90, monitor);
            if (res == null || !res.decompileCompleted()) {
                String rsn = res == null ? "null_result" : ("timeout:" + res.getErrorMessage());
                if (rsn.length() > 120) rsn = rsn.substring(0, 120);
                recordFailure(f, rsn.replace(",", " "), "failed");
                return;
            }
            DecompileResults r2 = res;
            String code = r2.getDecompiledFunction() == null ? "" : r2.getDecompiledFunction().getC();
            if (code.isEmpty()) {
                recordFailure(f, "empty_output", "empty");
                return;
            }
            String status = "ok";
            if (code.length() > MAX_FN_BYTES) {
                code = code.substring(0, MAX_FN_BYTES) + "\n// [truncated]\n";
                status = "truncated";
            }
            String entry = header(f, ahex, name, size) + code;
            int blen = entry.length();
            if (cw.full()) rotate();
            cw.write(entry);
            String chunkName = String.format("part_%06d.c", cw.id);
            synchronized (lock) {
                idxW.println(ahex + "," + csv(name) + "," + size + ",0," + chunkName + "," + blen + "," + status);
            }
        }
    }

    AtomicInteger cursor = new AtomicInteger(0);

    String header(Function f, String ahex, String name, long size) {
        return "// ==== FUNC addr=" + ahex + " name=" + f.getName()
                + " size=" + size + "\n";
    }
    String csv(String s) { return s.replace(",", "_").replace("\n", " ").replace("\"", "'"); }

    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        outDir = new File(a[0]);
        int nthreads = a.length > 1 ? Integer.parseInt(a[1]) : 8;
        int limit = a.length > 2 ? Integer.parseInt(a[2]) : Integer.MAX_VALUE;
        outDir.mkdirs();
        idxW = new PrintWriter(new BufferedWriter(new OutputStreamWriter(
                new FileOutputStream(new File(outDir, "functions_index.csv")), StandardCharsets.UTF_8)));
        cgW = new PrintWriter(new BufferedWriter(new OutputStreamWriter(
                new FileOutputStream(new File(outDir, "callgraph_edges.csv")), StandardCharsets.UTF_8)));
        failW = new PrintWriter(new BufferedWriter(new OutputStreamWriter(
                new FileOutputStream(new File(outDir, "failures.csv")), StandardCharsets.UTF_8)));
        idxW.println("addr,name,size,thunk,chunk,decompiled_bytes,status");
        cgW.println("caller_addr,caller_name,callee_addr,callee_name");
        failW.println("addr,name,reason");

        fns = new ArrayList<>(440000);
        FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
        while (it.hasNext()) fns.add(it.next());
        if (limit < fns.size()) fns = fns.subList(0, limit);
        println("TOTAL functions: " + fns.size());
        t0 = System.currentTimeMillis();

        ExecutorService pool = Executors.newFixedThreadPool(nthreads);
        for (int t = 0; t < nthreads; t++) pool.submit(new Worker(t));
        pool.shutdown();
        pool.awaitTermination(48, TimeUnit.HOURS);
        idxW.close(); cgW.close(); failW.close();
        long el = (System.currentTimeMillis() - t0) / 1000;
        println("DONE total=" + fns.size() + " done=" + done.get() + " fail=" + failed.get()
                + " skip=" + skipped.get() + " chunks=" + chunkCounter.get() + " " + el + "s");
    }
}
