db.runCommand({fsync:1,lock:1}); // sync and lock
runProgram("rsync", "-avz", "--delete", "/var/lib/mongodb/", "/var/lib/mongodb.backup/");
db.$cmd.sys.unlock.findOne(); //unlock

