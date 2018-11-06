#!/usr/bin/perl
BEGIN {
push @INC,"/srv/southbridge/scripts";
};


#use strict;
#use XML::Simple;
#use Data::Dumper;
use Encode;
use utf8;
use open ':utf8';
use Time::Local;
use Time::localtime;
use ISSUE;
use DBI;

my $CURDIR = '/srv/southbridge/scripts';
my $PID=$$;
my $DELTA=60*60*24*365; 
my $MAX_ISSUE=10;
my $iter=0;
my $currtime=time;

my %projects=();
my %projects_id=();
my %projects_member=();

open (IN,"<:utf8","$CURDIR/domain.project");
while (<IN>) {
  chomp;
  ($key,$name,$id,$member)=split /:/;
  $projects{ $key }=$name;
  $projects_id{ $name }=$id;
  $projects_member{ $name }=$member;
};
close IN;

my $mysql_host='localhost';
my $mysql_db='dbname';
my $mysql_user='login';
my $mysql_password='password';

$dbh = DBI->connect("DBI:mysql:$mysql_db:$mysql_host",$mysql_user, $mysql_password)
            or die "Error connecting to database";

my $sql_server='localhost';
my $sql_database='database';
my $sql_username='login';
my $sql_password='password';

$dbh_m = DBI->connect("DBI:mysql:$sql_database:$sql_server","$sql_username","$sql_password")
            or die "Error connecting to database";

#      port <12000 and
my $q="select concat(if(ds,' ds',''),if(cl,' vds',''),if(vs,' vs','')) as t, name,port,service,state from servicefin,hostfin where hostfin.id=id_host and
    (( vs=1 and port!=21 and port!=22 and port!=80 and port!=443 and port!=25 and port!=48022 and (port<49900 or port>50000)) or (vs=0 and port!=48022) ) and state='open' order by t,name";
my $sth=$dbh->prepare($q);
$sth->execute() or die "Не могу выполнить: ".$sth->errstr;
$pn="";
##
print $sth->rows;
if ($sth->rows == 0) {
  $q="select concat(if(ds,' ds',''),if(cl,' vds',''),if(vs,' vs','')) as t, name,port,service,state from servicefin,hostfin where hostfin.id=id_host and
    (( vs=1 and port!=21 and port!=22 and port!=80 and port!=443 and port!=25 and port!=48022 and (port<49900 or port>50000)) or (vs=0 and port!=48022) ) and state='open' order by t,name";
  $sth=$dbh->prepare($q);
  $sth->execute() or die "Не могу выполнить: ".$sth->errstr;
};

while (my @row = $sth -> fetchrow_array) {
  $type=$row[0];
  $host=$row[1];
  $port=$row[2];
  $service=$row[3];
  $q="select issue,state,issuedate from openports where host='$host' and port=$port";
##print "$q\n";
  my $sth_m=$dbh_m->prepare($q);
  $sth_m->execute() or die "Не могу выполнить: ".$sth_m->errstr;
  $update_issue=0;
  while (my @row_m = $sth_m -> fetchrow_array) {
    $update_issue=1;
##print "$host:$port == $row_m[0] $row_m[1]\n";
    if (($row_m[1]==5) and ($currtime-$row_m[2] > $DELTA ) ){
      #Reopen issue
##print "Reopen $row_m[0] $row_m[1]\n";
       $iter++;
       if ( $row_m[0] >0 ) {
	  ISSUE::update($row_m[0],"Порт открыт. Проверьте правильность закрытия задачи!","");
          $q="update openports set state=-3 where issue=?";
          my $sth_m1=$dbh_m->prepare($q);
          $sth_m1->execute($row_m[0]) or die "Не могу выполнить: ".$sth_m1->errstr;
       } else {
          my $q="insert into openports (issue,state,issuedate,host,port,service) values (0,1,?,?,?,?)";
          my $sth_m1=$dbh_m->prepare($q);
          $sth_m1->execute($currtime,$host,$port,$service) or die "Не могу выполнить: ".$sth_m1->errstr;
          ISSUE::issue($PROJECT,'Нормальный','Администраторы',
            "Проверка открытого порта $host $port $service",
            'openport',"Проверьте открытый порт. Перенастройте сервис на localhost, закройте фаерволлом.
Если порт должен быть открыт - поставьте задаче статус \"Отменена\" и опишите в комментарии к этой задаче причины исключения.
Тип сервера: $type.
Ссылка на КБ: https://example.com
","");
       };
    };
    if ((($row_m[1]==6) or ($row_m[1]==8) or ($row_m[1]==10)) and
       ($currtime-$row_m[2] > $DELTA ) ) {
      #Reopen issue
       $iter++;
       if ( $row_m[0] >0 ) {
	  ISSUE::update($row_m[0],"Проверьте правильность закрытия задачи","");
          $q="update openports set state=1 where issue=?";
          my $sth_m1=$dbh_m->prepare($q);
          $sth_m1->execute($row_m[0]) or die "Не могу выполнить: ".$sth_m1->errstr;
       } else {
          my $q="insert into openports (issue,state,issuedate,host,port,service) values (0,1,?,?,?,?)";
          my $sth_m1=$dbh_m->prepare($q);
          $sth_m1->execute($currtime,$host,$port,$service) or die "Не могу выполнить: ".$sth_m1->errstr;
          ISSUE::issue($PROJECT,'Нормальный','Администраторы',
          "Проверка открытого порта $host $port $service",
           'openport',"Проверьте открытый порт. Перенастройте сервис на localhost, закройте фаерволлом.
Если порт должен быть открыт - поставьте задаче статус \"Отменена\" и опишите в комментарии к этой задаче причины исключения.
Тип сервера: $type.
Ссылка на КБ: https://example.com
","");
       };
    };
  };
  if ($update_issue==0) {
    #create Issue
print "Create $host, $port, $service\n";
    while ( my ($key, $value) = each(%projects) ) {
      if ( $host =~ /$key/ ) { $PROJECT=$value; break; };
    }
    my $q="insert into openports (issue,state,issuedate,host,port,service) values (0,1,?,?,?,?)";
    my $sth_m1=$dbh_m->prepare($q);
    $sth_m1->execute($currtime,$host,$port,$service) or die "Не могу выполнить: ".$sth_m1->errstr;
    ISSUE::issue($PROJECT,'Нормальный','Администраторы',
        "Проверка открытого порта $host $port $service",
         'openport',"Проверьте открытый порт. Перенастройте сервис на localhost, закройте фаерволлом.
Если порт должен быть открыт - поставьте задаче статус \"Отменена\" и опишите в комментарии к этой задаче причины исключения.
Тип сервера: $type.
Ссылка на КБ: https://example.com
","");

    $iter++;
  };
  if ( $iter > $MAX_ISSUE ) {
    exit;
  };
};

