import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;

import unluac.Configuration;
import unluac.Main;

/** Batch Lua 5.1 decompiler driver: one JVM for the whole corpus.
 *  args: <listfile> where each line is "<input.uexp path>\t<output.lua path>" */
public class LuaBatch {
    public static void main(String[] args) throws Exception {
        List<String> lines = Files.readAllLines(Paths.get(args[0]), StandardCharsets.UTF_8);
        Configuration config = new Configuration();
        int ok = 0, fail = 0, n = 0;
        for (String line : lines) {
            if (line.isBlank()) continue;
            int tab = line.indexOf('\t');
            Path in = Paths.get(line.substring(0, tab));
            Path out = Paths.get(line.substring(tab + 1));
            n++;
            try {
                Files.createDirectories(out.getParent());
                Main.decompile(in.toString(), out.toString(), config);
                ok++;
            } catch (Throwable t) {
                fail++;
                String msg = String.valueOf(t.getMessage()).replace('\n', ' ').replace('\t', ' ');
                if (msg.length() > 140) msg = msg.substring(0, 140);
                System.out.println("FAIL\t" + in + "\t" + t.getClass().getSimpleName() + ": " + msg);
            }
            if (n % 2000 == 0) {
                System.out.println("progress " + n + " ok=" + ok + " fail=" + fail);
            }
        }
        System.out.println("DONE n=" + n + " ok=" + ok + " fail=" + fail);
    }
}
