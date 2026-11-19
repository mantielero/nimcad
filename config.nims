switch("mm", "orc")
switch("threads", "on")
switch("outdir", "bin")
switch("path", "src")
when defined(release):
  switch("opt", "speed")
# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
