{
  system,
  writeShellApplication,
  formatterInputs,
}:
writeShellApplication {
  name = "formatter";
  runtimeInputs = formatterInputs system;
  text = builtins.readFile ./../scripts/format.sh;
}
