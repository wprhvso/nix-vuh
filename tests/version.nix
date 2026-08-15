{ testers, vuh }:

# `vuh --version` prints "vuh version: <x.y.z>"; make sure the version the
# derivation claims is the version the script actually reports.
testers.testVersion {
  package = vuh;
  command = "vuh --version";
}
