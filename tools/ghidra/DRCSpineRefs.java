// Find functions referencing the Spine component strings and dump them.
//@category DRC
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import java.io.*;
import java.util.*;

public class DRCSpineRefs extends GhidraScript {

    static final long[] TARGETS = {
            0x4afe2d8L,  // "SpineSkeletonRendererComponent must be non-null" (rodata literal)
            0x4b6b862L,  // pool copy
            0x4b6b8a0L,  // "UpdateWorldTransform"
            0x4add1a2L,  // "SlotColor"
            0x4bc0742L,  // "maxDarkenAlpha"
    };

    @Override
    public void run() throws Exception {
        String outDir = getScriptArgs().length > 0 ? getScriptArgs()[0] : "D:/dragonraja_cap/ghidra_out";
        ReferenceManager rm = currentProgram.getReferenceManager();
        FunctionIterator fit = currentProgram.getFunctionManager().getFunctions(true);

        // map: target -> set of function entry points containing refs
        Map<Long, Set<Long>> found = new HashMap<>();
        for (long t : TARGETS) found.put(t, new HashSet<Long>());

        Function f = fit.next();
        // iterate all instructions is too slow (91MB); instead use getReferencesTo
        for (long t : TARGETS) {
            Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(t);
            ReferenceIterator rit = rm.getReferencesTo(a);
            int c = 0;
            while (rit.hasNext()) {
                Reference r = rit.next();
                Function fn = getFunctionContaining(r.getFromAddress());
                if (fn != null) {
                    found.get(t).add(fn.getEntryPoint().getOffset());
                    c++;
                }
            }
            println("target " + Long.toHexString(t) + " refs=" + c +
                    " functions=" + found.get(t));
        }

        // decompile the union of containing functions
        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);
        Set<Long> all = new HashSet<Long>();
        for (Set<Long> s : found.values()) all.addAll(s);
        for (long ep : all) {
            Function fn = getFunctionAt(currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(ep));
            if (fn == null) fn = getFunctionContaining(currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(ep));
            if (fn == null) continue;
            DecompileResults res = di.decompileFunction(fn, 180, monitor);
            if (res != null && res.decompileCompleted()) {
                PrintWriter pw = new PrintWriter(new FileWriter(
                        outDir + "/spine_fn_" + Long.toHexString(ep) + ".c"));
                pw.print(res.getDecompiledFunction().getC());
                pw.close();
            }
        }
        println("decompiled " + all.size() + " functions to " + outDir);
        di.dispose();
    }
}
