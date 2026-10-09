// Locate the actual in-memory address of the spine strings and their refs.
//@category DRC
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.symbol.*;
import ghidra.program.model.mem.*;
import java.util.*;

public class DRCFindStr extends GhidraScript {
    @Override
    public void run() throws Exception {
        Memory mem = currentProgram.getMemory();
        Address start = currentProgram.getMinAddress();
        Address end = currentProgram.getMaxAddress();
        String needle = "SpineSkeletonRendererComponent must be non-null";
        Address found = mem.findBytes(start, needle.getBytes(), null, true, monitor);
        println("bytes at: " + found);
        if (found == null) return;

        ReferenceIterator rit = currentProgram.getReferenceManager().getReferencesTo(found);
        int c = 0;
        while (rit.hasNext()) { c++; rit.next(); }
        println("direct refs: " + c);

        long v = found.getOffset();
        byte[] ptr = new byte[8];
        for (int i = 0; i < 8; i++) ptr[i] = (byte) ((v >> (8 * i)) & 0xFF);
        Address s2 = found.add(needle.length());
        Address pfound = mem.findBytes(s2, ptr, null, true, monitor);
        println("pointer slot at: " + pfound);
        if (pfound != null) {
            ReferenceIterator rit2 = currentProgram.getReferenceManager().getReferencesTo(pfound);
            int c2 = 0;
            StringBuilder sb = new StringBuilder();
            while (rit2.hasNext()) {
                Reference r = rit2.next();
                c2++;
                if (c2 <= 8) sb.append(r.getFromAddress()).append(" ");
            }
            println("ptr-slot refs: " + c2 + " : " + sb);
        }
    }
}
