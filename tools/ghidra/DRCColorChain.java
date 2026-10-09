// Color value chain: refs/callers of given functions, decompile callers.
// args: <outDir> <addr;addr;...>   (semicolon-separated, batch-safe)
//@category DRC
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import java.io.*;
import java.util.*;

public class DRCColorChain extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        String outDir = a[0];
        new File(outDir).mkdirs();
        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);

        for (int i = 1; i < a.length; i++) {
            long target = Long.parseLong(a[i], 16);
            Address ad = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(target);
            Function fn = getFunctionAt(ad);
            if (fn == null) { println("no function at " + a[i]); continue; }
            String hex = Long.toHexString(target);

            // 1) all references to the function entry (call sites + pointer take-ups)
            PrintWriter pw = new PrintWriter(new FileWriter(outDir + "/refs_" + hex + ".txt"));
            int ncall = 0, nref = 0;
            List<Address> callerAddrs = new ArrayList<>();
            for (Reference r : getReferencesTo(ad)) {
                RefType t = r.getReferenceType();
                pw.println(r.getFromAddress() + " " + t);
                nref++;
                if (t.isCall()) { callerAddrs.add(r.getFromAddress()); ncall++; }
            }
            pw.close();
            println("refs to " + hex + ": total=" + nref + " calls=" + ncall);

            // 2) decompile containing function of each call site (dedup)
            Set<Long> done = new HashSet<>();
            PrintWriter pw2 = new PrintWriter(new FileWriter(outDir + "/callerfns_" + hex + ".txt"));
            for (Address cs : callerAddrs) {
                Function cf = getFunctionContaining(cs);
                if (cf == null) continue;
                long e = cf.getEntryPoint().getOffset();
                if (!done.add(e)) continue;
                pw2.println(Long.toHexString(e) + " " + cf.getName());
                DecompileResults res = di.decompileFunction(cf, 300, monitor);
                if (res != null && res.decompileCompleted()) {
                    PrintWriter pw3 = new PrintWriter(new FileWriter(outDir + "/cl_" + hex + "_" + Long.toHexString(e) + ".c"));
                    pw3.print(res.getDecompiledFunction().getC());
                    pw3.close();
                }
            }
            pw2.close();
            println("caller fns of " + hex + ": " + done.size());
        }
        di.dispose();
    }
}
