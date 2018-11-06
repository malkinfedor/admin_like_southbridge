#!/usr/bin/perl

$host=`hostname`;
chomp $host;

if ( -x "/usr/sbin/hpssacli" ) {
  open (REP,"/usr/sbin/hpssacli ctrl all show config |");
} elsif ( -x "/opt/compaq/hpacucli/bld/hpacucli" ) {
  open (REP,"/opt/compaq/hpacucli/bld/hpacucli ctrl all show config |");
} else {
  if ( -e "/tmp/hpssacli.install" ) {
    if ( -M "/tmp/hpssacli.install" < 0.25 ) {
      exit;
    }; 
  };
  `(touch /tmp/hpssacli.install; echo "HP RAID ERROR \n No cli program installed\nTry to install: yum install -y hpssacli"; LD_LIBRARY_PATH=/lib:/usr/lib:/lib64:/usr/lib64 yum install -y hpssacli )| /usr/bin/tr -d '\015' | mail -s "HP RAID ERROR $host raid problem" root`;
  exit;
};

$ok=1;
$err="";
while (<REP>) {
   if ( /^\s*logicaldrive/ ) {
     if (! /OK\)/) {
	 $err.=$_;
	 $err.="\n"; 
	 $ok=0;
     };	 
   next;
   }
   if ( /^\s*physicaldrive/ ) {
     if (! /OK\)/) {
	 $err.=$_;
	 $err.="\n"; 
	 $ok=0;
     };	 
   next;
   }
};
close REP;
if ($ok == 0) {
  `echo "HP RAID ERROR \n $err" | mail -s "HP RAID ERROR $host raid problem" root`;
};
