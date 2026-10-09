// Probe: what does Ghidra see at given addresses (listing + refs from/to)
// args: <addr;addr;...>
//@category DRC
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import ghidra.program.model.mem.*;

public class DRCProbe extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] a = getScriptArgs();
        for (int i = 0; i < a.length; i++) {
            long t = Long.parseLong(a[i], 16);
            Address ad = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(t);
            println("=== 0x" + Long.toHexString(t));
            Instruction ins = getInstructionAt(ad);
            if (ins != null) println("INS: " + ins.toString());
            Data d = getDataAt(ad);
            if (d != null) println("DATA: " + d.getDataType().getName() + " = " + d.getValue());
            Memory mem = currentProgram.getMemory();
            byte[] b = new byte[16];
            mem.getBytes(ad, b);
            StringBuilder sb = new StringBuilder("BYTES:");
            for (byte x : b) sb.append(String.format(" %02x", x));
            println(sb.toString());
            println("-- refs from:");
            for (Reference r : getReferencesFrom(ad)) println("  -> " + r.getToAddress() + " " + r.getReferenceType());
            println("-- refs to:");
            for (Reference r : getReferencesTo(ad)) println("  <- " + r.getFromAddress() + " " + r.getReferenceType());
        }
    }
}
