// Find spine property strings in memory (correct vaddrs) and dump referencing
// functions' decompiled C.
//@category DRC
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.*;
import ghidra.program.model.symbol.*;
import java.io.*;
import java.util.*;

public class DRCSpineRefs2 extends GhidraScript {

    static final String[] NAMES = {
            "SpineSkeletonRendererComponent must be non-null",
            "\0SlotColor\0", "\0maxDarkenAlpha\0", "\0colorParamType\0",
            "\0SpineMeshUpdateRate\0", "\0SpineOpacityCurve\0",
    };

    @Override
    public void run() throws Exception {
        String outDir = getScriptArgs().length > 0 ? getScriptArgs()[0] : "D:/dragonraja_cap/ghidra_out";
        Memory mem = currentProgram.getMemory();
        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);

        Set<Long> funcs = new HashSet<Long>();
        for (String nm : NAMES) {
            byte[] pat = nm.getBytes();
            Address s = currentProgram.getMinAddress();
            int foundCount = 0;
            while (s != null && foundCount < 4) {
                Address a = mem.findBytes(s, pat, null, true, monitor);
                if (a == null) break;
                foundCount++;
                println("str \"" + nm.replace("\0", "") + "\" at " + a);
                ReferenceIterator rit = currentProgram.getReferenceManager().getReferencesTo(a);
                int rc = 0;
                while (rit.hasNext()) {
                    Reference r = rit.next();
                    rc++;
                    Function fn = getFunctionContaining(r.getFromAddress());
                    if (fn != null) funcs.add(fn.getEntryPoint().getOffset());
                }
                println("   refs=" + rc);
                s = a.add(1);
            }
        }
        println("containing functions: " + funcs.size());
        for (long ep : funcs) {
            Function fn = getFunctionAt(currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(ep));
            if (fn == null) continue;
            DecompileResults res = di.decompileFunction(fn, 180, monitor);
            if (res != null && res.decompileCompleted()) {
                PrintWriter pw = new PrintWriter(new FileWriter(
                        outDir + "/spine_fn_" + Long.toHexString(ep) + ".c"));
                pw.print(res.getDecompiledFunction().getC());
                pw.close();
            }
        }
        println("decompiled to " + outDir);
        di.dispose();
    }
}
