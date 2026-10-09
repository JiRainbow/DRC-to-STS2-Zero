"""Build the LuaBatch decompiler driver: javac LuaBatch.java with unluac.jar on classpath."""
import subprocess
import sys
from pathlib import Path

TOOLS = Path(r"D:\项目\dragonraja\tools")
JAVAC = r"C:\Program Files\Java\jdk-25\bin\javac.exe"
JAVA = r"C:\Program Files\Java\jdk-25\bin\java.exe"

r = subprocess.run(
    [JAVAC, "-encoding", "UTF-8", "-cp", str(TOOLS / "unluac.jar"),
     "-d", str(TOOLS / "luabatch_build"), str(TOOLS / "LuaBatch.java")],
    capture_output=True, text=True)
print(r.stdout)
print(r.stderr)
if r.returncode != 0:
    sys.exit(r.returncode)
print("COMPILED")
