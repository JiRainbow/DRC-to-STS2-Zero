// Search memory for float32 constants; list containing function
// args: <outFile> <float;float;...>
//@category DRC
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.*;
import java.io.*;

public class DRCFloatScan extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        String outFile = a[0];
        String[] fs = a[1].split(";");
        int[] bits = new int[fs.length];
        for (int i = 0; i < fs.length; i++)
            bits[i] = Float.floatToIntBits(Float.parseFloat(fs[i]));

        Memory mem = currentProgram.getMemory();
        PrintWriter pw = new PrintWriter(new FileWriter(outFile));
        long n = 0;
        for (MemoryBlock blk : mem.getBlocks()) {
            if (!blk.isInitialized()) continue;
            long sz = blk.getSize();
            Address base = blk.getStart();
            byte[] b = new byte[(int) Math.min(sz, 64L * 1024 * 1024)];
            for (long off = 0; off < sz; off += b.length) {
                int len = (int) Math.min(b.length, sz - off);
                try {
                    mem.getBytes(base.add(off), b, 0, len);
                } catch (Exception e) { break; }
                for (int i = 0; i + 4 <= len; i += 4) {
                    int v = (b[i] & 0xff) | ((b[i + 1] & 0xff) << 8) | ((b[i + 2] & 0xff) << 16) | ((b[i + 3] & 0xff) << 24);
                    for (int t : bits) {
                        if (v == t) {
                            Address ad = base.add(off + i);
                            Function fn = getFunctionContaining(ad);
                            pw.println(ad + " val=" + Float.intBitsToFloat(v) + " blk=" + blk.getName() +
                                " fn=" + (fn == null ? "?" : Long.toHexString(fn.getEntryPoint().getOffset())));
                            n++;
                            break;
                        }
                    }
                }
            }
            println("scanned " + blk.getName());
        }
        pw.close();
        println("float hits: " + n);
    }
}
