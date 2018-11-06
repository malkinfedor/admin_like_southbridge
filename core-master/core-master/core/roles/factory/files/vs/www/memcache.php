<?php

error_reporting(E_ALL & ~E_NOTICE);

function sendMemcacheCommand($server,$port,$command){

	$s = @fsockopen($server,$port);
	if (!$s){
		die("Cant connect to:".$server.':'.$port);
	}

	fwrite($s, $command."\r\n");

	$buf='';
	while ((!feof($s))) {
		$buf .= fgets($s, 256);
		if (strpos($buf,"END\r\n")!==false){ // stat says end
		    break;
		}
		if (strpos($buf,"DELETED\r\n")!==false || strpos($buf,"NOT_FOUND\r\n")!==false){ // delete says these
		    break;
		}
		if (strpos($buf,"OK\r\n")!==false){ // flush_all says ok
		    break;
		}
		if (strpos($buf,"RESET\r\n")!==false){ // reset stats ok
		    break;
		}
		if (strpos($buf,"VERSION ")!==false){ // version answer
		    break;
		}
	}
    fclose($s);
    return parseMemcacheResults($buf);
}
function parseMemcacheResults($str){
	$res = array();
	$lines = explode("\r\n",$str);
	$cnt = count($lines);
	for($i=0; $i< $cnt; $i++){
	    $line = $lines[$i];
		$l = explode(' ',$line,3);
		if (count($l)==3){
			$res[$l[0]][$l[1]]=$l[2];
			if ($l[0]=='VALUE'){ // next line is the value
			    $res[$l[0]][$l[1]] = array();
			    list ($flag,$size)=explode(' ',$l[2]);
			    $res[$l[0]][$l[1]]['stat']=array('flag'=>$flag,'size'=>$size);
			    $res[$l[0]][$l[1]]['value']=$lines[++$i];
			}
		}elseif( $l[0] == 'VERSION' ){
		    return $l[1];
		}elseif($line=='DELETED' || $line=='NOT_FOUND' || $line=='OK' || $line=='RESET'){
		    return $line;
		}
	}
	return $res;
}


$server = $_GET['server'];
$port   = $_GET['port'];
if( $server == '' ){
    $server = 'localhost';
}
if( (int)$port == 0 ){
    $port = 11211;
}

$stats = sendMemcacheCommand($server, $port, "stats");
$stats = $stats['STAT'];

// calc the amount of memory designated to items of certain size
$stats_slabs = sendMemcacheCommand($server, $port, "stats slabs");
$stats_slabs = $stats_slabs['STAT'];
$slabs = array();
$below1mb  = 0;
$below200k = 0;
$below50k  = 0;
$below4k   = 0;
$below1k   = 0;
$below400b = 0;
foreach( $stats_slabs as $name => $value ){
    $parts = explode(':', $name);
    $slabs[ $parts[0] ][ $parts[1] ] = $value;
}
foreach( $slabs as $slab => $values ){
    if( $values["chunk_size"] <= 400 ){
        $below400b += $values["total_pages"] * 1024 * 1024;
    }elseif( $values["chunk_size"] <= 1000 ){
        $below1k   += $values["total_pages"] * 1024 * 1024;
    }elseif( $values["chunk_size"] <= 4000 ){
        $below4k   += $values["total_pages"] * 1024 * 1024;
    }elseif( $values["chunk_size"] <= 10000 ){
        $below10k  += $values["total_pages"] * 1024 * 1024;
    }elseif( $values["chunk_size"] <= 50000 ){
        $below50k  += $values["total_pages"] * 1024 * 1024;
    }elseif( $values["chunk_size"] <= 200000 ){
        $below200k += $values["total_pages"] * 1024 * 1024;
    }else{
        $below1mb  += $values["total_pages"] * 1024 * 1024;
    }
}

//ratio of evictions evictions/sets
if( $stats["cmd_set"] > 0){
    $evict_ratio = round($stats["evictions"] / $stats["cmd_set"],4);
}else{
    $evict_ratio = 0;
}

//ratio of hits
if( $stats["cmd_get"] > 0){
    $hit_ratio = round($stats["get_hits"] / $stats["cmd_get"],4);
}else{
    $hit_ratio = 0;
}

// load number of open file descriptors
#$memcached_pid = shell_exec( 'pidof memcached' );
#$cmd = dirname(__FILE__).'/ls /proc/'.((int)$memcached_pid).'/fd | wc -l';
#$fds = (int)shell_exec( $cmd );

$fds = 0;

$results = array(
    "total_items"           => $stats["total_items"],
    "get_hits"              => $stats["get_hits"],
    "uptime"                => $stats["uptime"],
    "cmd_get"               => $stats["cmd_get"],
    "time"                  => $stats["time"],
    "bytes"                 => $stats["bytes"],
    "curr_connections"      => $stats["curr_connections"],
    "connection_structures" => $stats["connection_structures"],
    "bytes_written"         => $stats["bytes_written"],
    "limit_maxbytes"        => $stats["limit_maxbytes"],
    "cmd_set"               => $stats["cmd_set"],
    "curr_items"            => $stats["curr_items"],
    "rusage_user"           => round($stats["rusage_user"],3),
    "get_misses"            => $stats["get_misses"],
    "rusage_system"         => round($stats["rusage_system"],3),
    "bytes_read"            => $stats["bytes_read"],
    "total_connections"     => $stats["total_connections"],
    "evictions"             => $stats["evictions"],
    "eviction_ratio"        => $evict_ratio,
    "hit_ratio"             => $hit_ratio,
    "bytes_total_transfer"  => $stats["bytes_written"] + $stats["bytes_read"],
    "bits_read"             => $stats["bytes_read"] * 8,
    "bits_written"          => $stats["bytes_written"] * 8,

    "open_file_descriptors" => $fds,

//    "1mb"                   => $below1mb,
//    "200kb"                 => $below200k,
//    "50kb"                  => $below50k,
//    "10kb"                  => $below10k,
//    "4kb"                   => $below4k,
//    "1kb"                   => $below1k,
//    "400b"                  => $below400b,
);

foreach( $results as $name => $value ){
    echo $name.':'.$value.' ';
}


?>