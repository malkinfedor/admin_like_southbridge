#!/usr/bin/env perl

# unicornstat.pl SNMP parser bond@southbridge.ru
# Mark Round, Email : cacti@markround.com
# Based heavily on the awesome Bind9 stats parser written by Cory Powers
#
# NOTE: the .1.3.6.1.3.1 OID in this script uses an "experimental" sequence,
# which may not be unique in your organisation[1]. You should probably change
# this to something else, perhaps using your own private OID.
#
# [1]=http://www.alvestrand.no/objectid/1.3.6.1.3.html
#
# USAGE
# -----
# See the README which should have been included with this file.
#
# CHANGES
# -------
# 22/06/2009 - Version 1.4 - Added FreeBSD license
# 19/03/2009 - Version 1.3 - Added patch from Marwan Shaher and Eric Schoeller
#			     to support Solaris
# 10/03/2009 - Version 1.1 - Added patch from Viktor Sokolov to work with 
#                            older sysstat found on Debian Etch and other 
#                            distros.
# 14/10/2008 - Version 1.0 - Initial release, Linux iostat only. Solaris etc.
#                            coming in next revision!
#
# Copyright 2009 Mark Round and others. All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without modification, 
# are permitted provided that the following conditions are met:
# 
#  1. Redistributions of source code must retain the above copyright notice, 
#     this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright notice, 
#     this list of conditions and the following disclaimer in the documentation 
#     and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, 
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
# FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHORS 
# OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, 
# OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE 
# GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR 
# TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use strict;

use constant debug => 0;
my $base_oid = ".1.3.6.1.3.2";
my $file_cache = "/tmp/unicorn.stat";
my $req;
my %stats;
my $i;

my $debug=1;

process();

my $mode = shift(@ARGV);
if ( $mode eq "-g" ) {
    $req = shift(@ARGV);
    getoid($req);
}
elsif ( $mode eq "-n" ) {
    $req = shift(@ARGV);
    my $next = getnextoid($req);
    getoid($next);
}
else {
    $req = $mode;
    getoid($req);
}

sub process {
    open( IOSTAT, $file_cache )
      or die("Could not open file cache $file_cache : $!");
    $i=1;
    while (<IOSTAT>) {
        /^(\d+)/;
        $stats{"$base_oid.$i"}=$1;
        $i++;
    }

}

sub getoid {
    my $oid = shift(@_);
    print "Fetching oid : $oid\n" if (debug);
    if ( $oid =~ /^$base_oid\.(\d+)\.*/ && exists( $stats{$oid} ) ) {
        print $oid. "\n";
        print "integer\n";
        print $stats{$oid} . "\n";
    }
}

sub getnextoid {
    my $first_oid = shift(@_);
    my $next_oid  = '';
    my $count_id;
    my $index;

    if ( $first_oid =~ /$base_oid\.(\d+).*/ ) {
        print("getnextoid($first_oid): index: $1\n") if (debug);
        $index    = $1 + 1;
        print(
            "getnextoid($first_oid): NEW - index: $index, count_id: $count_id\n"
        ) if (debug);
        $next_oid = "$base_oid.$index";
    }
    elsif ( $first_oid eq $base_oid ) {
        $next_oid = "$base_oid.1";
    }
    print("getnextoid($first_oid): returning $next_oid\n") if (debug);
    return $next_oid;
}
