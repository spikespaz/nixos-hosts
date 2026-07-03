{ writeShellApplication, coreutils, util-linux, cryptsetup, gawk }:

writeShellApplication {
  name = "brdboot-verify-self";
  runtimeInputs = [ coreutils util-linux cryptsetup gawk ];
  text = builtins.readFile ./brdboot-verify-self.sh;
}
