// Ghidra post-script: after headless analysis of libUE4.so, extract the pieces
// needed for the dye-constant RE:
//   1. full function listing (addr, size, name)
//   2. decompiled C for every function inside the address windows listed below
// Run: analyzeHeadless <proj> DRC -process libUE4.so -noanalysis -postScript DRCExtract.java <outDir>
//@category DRC
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import java.io.*;
import java.util.*;

public class DRCExtract extends GhidraScript {

    // address windows of interest (inclusive-exclusive), vaddrs
    static final long[][] WINDOWS = {
            {0xaa11000L, 0xaa18000L},  // GLES3 RHI vertex/uniform state layer
    };

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        String outDir = args.length > 0 ? args[0] : "D:/dragonraja_cap/ghidra_out";
        new File(outDir).mkdirs();

        DecompInterface di = new DecompInterface();
        DecompileOptions opts = new DecompileOptions();
        di.setOptions(opts);
        di.openProgram(currentProgram);

        // 1. function listing
        PrintWriter listing = new PrintWriter(new FileWriter(outDir + "/functions.txt"));
        FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
        int n = 0;
        while (it.hasNext()) {
            Function fn = it.next();
            listing.println(fn.getEntryPoint().toString() + " " +
                    fn.getBody().getNumAddresses() + " " + fn.getName());
            n++;
        }
        listing.close();
        println("functions listed: " + n);

        // 2. decompile windows
        int done = 0;
        FunctionIterator it2 = currentProgram.getFunctionManager().getFunctions(true);
        while (it2.hasNext()) {
            Function fn = it2.next();
            long ep = fn.getEntryPoint().getOffset();
            boolean in = false;
            for (long[] w : WINDOWS)
                if (ep >= w[0] && ep < w[1]) { in = true; break; }
            if (!in) continue;
            DecompileResults res = di.decompileFunction(fn, 180, monitor);
            if (res != null && res.decompileCompleted()) {
                PrintWriter pw = new PrintWriter(
                        new FileWriter(outDir + "/fn_" + Long.toHexString(ep) + ".c"));
                pw.print(res.getDecompiledFunction().getC());
                pw.close();
                done++;
            }
        }
        println("decompiled in-window functions: " + done);
        di.dispose();
    }
}
