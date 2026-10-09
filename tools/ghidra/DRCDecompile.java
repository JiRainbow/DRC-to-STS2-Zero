// Decompile given addresses + list callers of given functions.
// args: <outDir> <addr1,addr2,...> <callerOf1,callerOf2,...>
//@category DRC
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import java.io.*;
import java.util.*;

public class DRCDecompile extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        String outDir = a[0];
        new File(outDir).mkdirs();
        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);

        if (a.length > 1 && !a[1].isEmpty()) {
            for (String s : a[1].split(",")) {
                Address ad = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(Long.parseLong(s, 16));
                Function fn = getFunctionAt(ad);
                if (fn == null) fn = getFunctionContaining(ad);
                if (fn == null) { println("no function at " + s); continue; }
                DecompileResults res = di.decompileFunction(fn, 300, monitor);
                if (res != null && res.decompileCompleted()) {
                    PrintWriter pw = new PrintWriter(new FileWriter(outDir + "/dec_" + Long.toHexString(ep(fn)) + ".c"));
                    pw.print(res.getDecompiledFunction().getC());
                    pw.close();
                    println("decompiled " + s);
                } else println("decompile FAILED " + s);
            }
        }
        if (a.length > 2 && !a[2].isEmpty()) {
            for (String s : a[2].split(",")) {
                Address ad = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(Long.parseLong(s, 16));
                Function fn = getFunctionAt(ad);
                if (fn == null) { println("no function " + s); continue; }
                Set<Function> callers = fn.getCallingFunctions(monitor);
                PrintWriter pw = new PrintWriter(new FileWriter(outDir + "/callers_" + Long.toHexString(ep(fn)) + ".txt"));
                for (Function cf : callers) pw.println(cf.getEntryPoint().toString() + " " + cf.getName());
                pw.close();
                println("callers of " + s + ": " + callers.size());
            }
        }
        di.dispose();
    }
    long ep(Function f) { return f.getEntryPoint().getOffset(); }
}
