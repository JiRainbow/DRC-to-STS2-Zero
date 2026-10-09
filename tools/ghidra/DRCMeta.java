// Print program metadata + function stats for build-identity checks.
//@category DRC
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;

public class DRCMeta extends GhidraScript {
    @Override
    public void run() throws Exception {
        Program p = currentProgram;
        java.util.Map<String, String> props = p.getMetadata();
        println("META executablePath = " + p.getExecutablePath());
        println("META domainName = " + p.getDomainFile().getName());
        println("META name = " + p.getName());
        FunctionIterator it = p.getFunctionManager().getFunctions(true);
        long n = 0;
        while (it.hasNext()) { it.next(); n++; }
        println("META functionCount = " + n);
    }
}
