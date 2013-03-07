#!/usr/bin/perl
use PGPLOT;

#################################################################################################
#												#
#	find_shield_rate.perl: extract HRC shield rate as predicitons for HRC background rate	#
#												#
#	author: t. isobe (tisobe@cfa.harvard.edu)						#
#												#
#	last update: Mar 07, 2013								#
#												#
#################################################################################################

#
#--- check whether this is a test case
#
$comp_test = $ARGV[0];
chomp $comp_test;

#
#--- prep for test
#
if($comp_test =~ /test/i){
	system("mkdir ./Test_out");
}

#
#--- extract orbital data so that we can select proper shield rate later
#

open(FH, '/data/mta/DataSeeker/data/repository/aorbital.rdb');
@otime = ();
@dist  = ();
$tot++;
while(<FH>){
	@atemp = split(/\s+/, $_);
	if($atemp[0] =~ /\d/){
#
#--- compute a geo-centric distance (in km)
#
		$sum = sqrt($atemp[1]*$atemp[1] + $atemp[2]*$atemp[2] + $atemp[3] * $atemp[4]);
		push(@otime, $atemp[0]);
		push(@dist,  $sum);
		$tot++;
	}
}
close(FH);
$tot--;

#
#--- set available data range in time
#

$otime_min = $otime[0];
$otime_max = $otime[$tot-1];

if($comp_test =~ /test/i){

#
#--- set dataseeker input file
#

	open(OUT, '>./ds_file');
	print OUT 'columns=mtahrc..hrcveto_avg',"\n";
	print OUT 'timestart=2010:001:00:00:00',"\n";
	print OUT 'timestop=2010:60:00:00:00',"\n";
	close(OUT);
}else{
#
#--- find today's date
#

	($usec, $umin, $uhour, $umday, $umon, $uyear, $uwday, $uyday, $uisdst)= localtime(time);
	$year = $uyear + 1900;
	$month = $umon + 1;
	$today = "$year:$uyday:00:00:00";

#
#--- set dataseeker input file
#

	open(OUT, '>./ds_file');
	print OUT 'columns=mtahrc..hrcveto_avg',"\n";
	print OUT 'timestart=1999:202:00:00:00',"\n";
	print OUT 'timestop='."$today\n";
	close(OUT);
}

#
#--- call dataseeker
#

system("punlearn dataseeker; dataseeker.pl infile=ds_file print=yes outfile=veto.fits");
system("dmlist \"veto.fits[cols time,shevart_avg]\" outfile=sheild_events.dat opt=data");

@time = ();
@veto = ();
$count = 0;

open(FH, "./sheild_events.dat");

$kstart = 0;
OUTER:
while(<FH>){
	chomp $_;
	$string = $_;
	$string =~ s/^\s+//;

	@atemp = split(/\s+/, $string);

	if($atemp[0] !~ /\d/){
		next OUTER;
	}

	if($atemp[1] < $otime_min){
		next OUTER;
	}elsif($atemp[1] > $otime_max){
		last OUTER;
	}
	for($k = $kstart; $k < $tot; $k++){
		if($atemp[1] > $otime[$k-1] && $atemp[1] <= $otime[$k]){
#
#---- only data the geo-centric distance larger than 80,0000 km used
#
			if($dist[$k] > 80000){
#
#--- modify date to DOM
#
				$date = $atemp[1] - 48902399;
				$date /= 86400;
				push(@time, $date);
				push(@veto, $atemp[2]);
				$count++;
				$kstart = $k -4;
				if($kstart < 0){
					$kstart =0;
				}
				next OUTER;
			}
		}
	}
}
close(FH);

@temp = sort{$a<=>$b} @time;
if($comp_test =~ /test/i){
	$xmin = $temp[0];
}else{
	$xmin = 0;
}
$xmax = $temp[$count -1];
$diff = int($xmax - $xmin);
$xmax = $xmax + 0.05 * $diff;

$sum   = 0;
$scnt  = 0;
@avg   = ();
@day   = ();
$start = 0;
$end   = 1;
$dtot  = 0;

#
#---- modify data interval from 5 min to one day to reduce # of data points
#

$start = int($time[0]);
$end   = $start + 1;
OUTER:
for($i = 0; $i < $count; $i++){
	if($time[$i] > $start && $time[$i] <= $end){
		$sum += $veto[$i];
		$scnt++;
	}elsif($time[$i] < $start){
		next OUTER;	
	}elsif($time[$i] > $xmax){
		last OUTER;
	}elsif($time[$i] > $end){
		if($scnt > 0){
			$sum /= $scnt;
		}else{
			$sum = 0;
		}
		push(@day, $start);
		push(@avg, $sum);
		$dtot++;
		$sum = $veto[$i];
		$scnt = 1;
		$start++;
		$end++;
	}
}


#
#--- plotting start here
#

@temp = sort{$a<=>$b} @avg;
$ymin = $temp[0];
$ymax = $temp[$dtot-1];
$diff = $ymax - $ymin;
$ymin = $ymin - 0.05 * $diff;
$ymin = 0;
$ymax = $ymax + 0.05 * $diff;

$symbol = 2;

pgbegin(0, '"./pgplot.ps"/cps',1,1);
pgsubp(1,1);
pgsch(1);
pgslw(4);
pgenv($xmin, $xmax, $ymin, $ymax, 0, 0);

for($m = 0; $m < $dtot; $m++){
	pgpt(1, $day[$m], $avg[$m], $symbol);
}
pglab("Time (DOM)", "HRC Shield Rate (per Sec)", 'HRC Shield Rate Averaged Over One Day');
pgclos();

if($comp_test =~ /test/i){
	$out_plot = './Test_out/shiled_rate.gif';
}else{
	$out_plot = '/data/mta/www/mta_hrc/Trending/Bkg_data/shiled_rate.gif';
}

system("echo ''|/opt/local/bin/gs -sDEVICE=ppmraw  -r256x256 -q -NOPAUSE -sOutputFile=-  ./pgplot.ps|pnmcrop|pnmflip -r270 |ppmtogif > $out_plot");

if($comp_test =~ /test/i){
	system("mv sheild_events.dat ./Test_out/");
	system("rm ds_file memo pgplot.ps veto.fits");
}else{
	system("rm ds_file memo pgplot.ps veto.fits sheild_events.dat");
}


if($comp_test =~ /test/i){
	open(OUT, "> ./Test_out/hrc_bkg.html");
}else{
	open(OUT, '> /data/mta/www/mta_hrc/Trending/hrc_bkg.html');
}

print OUT "<!DOCTYPE html>\n";
print OUT '<html>',"\n";
print OUT "<head>\n";
print OUT "<title>HRC SIB</title>\n";
print OUT "<meta http-equiv='Content-Type' content='text/html; charset=utf-8' />\n";
print OUT "</head>\n";
print OUT '<body style="color:#000000;background-color:#FFFFFF">',"\n";
print OUT '<div style="txt-align:center;margin-left:auto;margin-right:auto;padding-bottom:20px">',"\n";
print OUT '<h2>Time History of HRC Istrument Background </h2>',"\n";
print OUT '',"\n";
print OUT "<img src ='./Bkg_data/shiled_rate.gif' alt='shield rate' style='width:500px;height:500px'>\n";
print OUT '',"\n";
print OUT '</div>',"\n";

if($month < 10){
	$month = '0'."$month";
}
if($umday < 10){
	$umday = '0'."$umday";
}

print OUT '<p>',"\n";
print OUT 'Last Update:',"$month/$umday/$year\n";
print OUT '</p>',"\n";

print OUT "</body>\n";
print OUT "</html>\n";

close(OUT);

#
#---- update the main hrc trending page
#

open(FH, '/data/mta_www/mta_hrc/Trending/hrc_trend.html');
open(OUT, '>./temp_out.html');

$chk = 0;
while(<FH>){
        chomp $_;
        if($_ =~ /Time History of the HRC Background/ && $chk == 0){
                print OUT '<li><a href = "#bkg">Time History of the HRC Background</a>';
                print OUT " (last update: $month-$umday-$year)\n";
                $chk++;
        }else{
                print OUT "$_\n";
        }
}
close(OUT);
close(FH);

if($comp_test =~ /test/i){
	system("mv ./temp_out.html ./Test_out/hrc_trend.html");
}else{
	system("mv ./temp_out.html /data/mta_www/mta_hrc/Trending/hrc_trend.html");
}

