{ writeShellApplication, coreutils, util-linux, jq, cryptsetup, systemdUkify
, mtools, findutils }:

writeShellApplication {
  name = "brdboot-verify-image";
  runtimeInputs =
    [ coreutils util-linux jq cryptsetup systemdUkify mtools findutils ];
  text = builtins.readFile ./brdboot-verify-image.sh;
}
