// Repair pass: decompile exactly the addresses listed in a text file (one 0x... per line).
// Writes one .c per function into <outDir>/patch/ + patched_index.csv + patched_failures.csv
// args: <outDir> <addrListFile>
//@category DRC
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.address.Address;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class DRCDecompilePatch extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        File outDir = new File(a[0], "patch");
        outDir.mkdirs();
        List<String> lines = new ArrayList<>();
        for (String ln : Files_readLines(new File(a[1]))) {
            ln = ln.trim();
            if (!ln.isEmpty()) lines.add(ln);
        }
        println("PATCH targets: " + lines.size());
        DecompInterface di = new DecompInterface();
        di.setOptions(new DecompileOptions());
        di.openProgram(currentProgram);
        PrintWriter idx = new PrintWriter(new BufferedWriter(new OutputStreamWriter(
                new FileOutputStream(new File(outDir, "patched_index.csv")), StandardCharsets.UTF_8)));
        PrintWriter fails = new PrintWriter(new BufferedWriter(new OutputStreamWriter(
                new FileOutputStream(new File(outDir, "patched_failures.csv")), StandardCharsets.UTF_8)));
        idx.println("addr,name,size,status,file,bytes");
        int ok = 0, bad = 0;
        for (int i = 0; i < lines.size(); i++) {
            Address ad = currentProgram.getAddressFactory().getDefaultAddressSpace()
                    .getAddress(Long.parseLong(lines.get(i).replace("0x", ""), 16));
            Function fn = getFunctionAt(ad);
            if (fn == null) fn = getFunctionContaining(ad);
            String ahex = lines.get(i);
            if (fn == null) { fails.println(ahex + ",no_function"); bad++; continue; }
            DecompileResults res = di.decompileFunction(fn, 240, monitor);
            if (res == null || !res.decompileCompleted() || res.getDecompiledFunction() == null) {
                String rsn = res == null ? "null" : String.valueOf(res.getErrorMessage());
                if (rsn.length() > 120) rsn = rsn.substring(0, 120);
                fails.println(ahex + "," + rsn.replace(",", " "));
                bad++;
                continue;
            }
            String code = res.getDecompiledFunction().getC();
            if (code.isEmpty()) { fails.println(ahex + ",empty"); bad++; continue; }
            String fname = "fn_" + ahex.replace("0x", "") + ".c";
            String entry = "// ==== FUNC addr=" + ahex + " name=" + fn.getName()
                    + " size=" + fn.getBody().getNumAddresses() + "\n" + code;
            PrintWriter pw = new PrintWriter(new BufferedWriter(new OutputStreamWriter(
                    new FileOutputStream(new File(outDir, fname)), StandardCharsets.UTF_8)));
            pw.print(entry);
            pw.close();
            idx.println(ahex + "," + fn.getName().replace(",", "_") + ","
                    + fn.getBody().getNumAddresses() + ",ok," + fname + "," + entry.length());
            ok++;
            if ((i + 1) % 500 == 0) println("patch progress " + (i + 1) + "/" + lines.size());
        }
        idx.close(); fails.close();
        di.dispose();
        println("PATCH DONE ok=" + ok + " fail=" + bad);
    }

    List<String> Files_readLines(File f) throws IOException {
        List<String> out = new ArrayList<>();
        try (BufferedReader br = new BufferedReader(new InputStreamReader(
                new FileInputStream(f), StandardCharsets.UTF_8))) {
            String ln;
            while ((ln = br.readLine()) != null) out.add(ln);
        }
        return out;
    }
}
