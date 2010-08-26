#!/usr/bin/perl 
my $CMD;

# this automatically detects whether its reading from multimon or aprsmon, but you'll need to launch the right thing:
#my $CMD = "sudo aprsmon|";
# this only works with a multimon that's been modified to fflush(stdout) a lot...
#my $CMD = "rec -q -s -4 -r 44100 -c 2 -t wav - | sox -t wav - -t raw -c 1 -2 -s -r 22050 - | multimon -s ZVEI -s POCSAG512 -s POCSAG1200 -s POCSAG2400 -s AFSK2400 -s AFSK2400_2 -s HAPN4800 -s FSK9600 -s DTMF -t raw - |";

die "you didn't configure me" unless defined $CMD;

use strict;
use warnings;

use IPC::Open3;

die "need output KML filename" unless defined $ARGV[0];
my $OUTFN = shift @ARGV;
die "need station call sign to monitor" unless defined $ARGV[0];
my $STATION = shift @ARGV;
print STDERR "writing to $OUTFN, listening for $STATION\n";

exit main();


sub splitAPRSTime {
	my $ts = shift;

	if ($ts =~ /^(\d{2})(\d{2})(\d{2})(h|)$/) {  # works with six-digit NMEA time as well (always zulu)
		return "$1:$2:$3Z";
	} elsif ($ts =~ /^(\d{2})(\d{2})(\d{2})(z|\/)$/) {
		return "$2:$3:00" . ($4 eq 'z' ? "Z" : " local") . " (day $1)";
	}
	return "";
}


# this only works with specially tagged KMLs... 'cause I don't wanna parse XML.
# write out both a point and append to the polyline
sub addCoordToKML {
	my ($station, $zulu, $lat, $long, $alt, $speed, $heading, $extra) = @_;
	my $hostname = qx[uname -n];
	chomp $hostname;

	# these are effectively optional
	$alt = "" unless defined $alt; # in kml, blank is unknown, but put two commas in anyway
	$speed = "unknown" unless defined $speed;
	$heading = "unknown" unless defined $heading;

	# XXX this should just be sent as a json dict and let the webapp render it
	my $desc = "<![CDATA[";
	if (defined $zulu) {
		$desc .= splitAPRSTime($zulu) . " ($zulu)<br/>"; # XXX also print in reasonable units / local time
	}
	$desc .= "($long, $lat, $alt) @ $speed<br/>"; # XXX what are the units?
	foreach (sort keys %{$extra}) { # sort for predictable order
		$desc .= "$_: " . $extra->{$_} . "<br/>";
	}
	$desc .= "]]>";

	my $outdata = "";
	open(KML, "<$OUTFN") || die "unable to open $OUTFN for reading";
	while (my $line = <KML>) {
		# obviously make sure you put the tag back in when you're done...
		$line =~ s/(<!--\s*ADDPLACEMARK\s*-->)/<Placemark><name>$station (received by APRS on $hostname)<\/name><description>$desc<\/description><styleUrl>#t266254<\/styleUrl><Point><altitudeMode>absolute<\/altitudeMode><coordinates>$long, $lat, $alt<\/coordinates><\/Point><\/Placemark>\n$1/;
		$line =~ s/(<!--\s*ADDTOLINE\s*-->)/$long,$lat,$alt   $1/;
		$outdata .= $line;
	}
	close KML;

	open(KML, ">$OUTFN.new") || die "unable to open $OUTFN.new for writing";
	print KML $outdata;
	close KML;

	rename("$OUTFN.new", $OUTFN);
}

sub createBlankKML {
	my $fn = shift;
	my $hostname = qx[uname -n];
	chomp $hostname;

	open(OUT, ">$fn") || die "unable to open $fn for writing";
	open(TEMPL, "<bacchusmapper-kml-template.kml") || die "unable to open bacchusmapper-kml-template.kml to create new KML";
	while (my $line = <TEMPL>) {
		$line =~ s/<!--\s*STATIONNAME\s*-->/APRS receiving on $hostname/;
		$line =~ s/<!--\s*STATIONDESCRIPTION\s*-->/APRS receiving on $hostname/;
		print OUT $line;
	}
	close TEMPL; close OUT;
	return;
}

sub handleNMEA {
	my ($from, $to, $path, $data) = @_;

	if ($data =~ /^\$GPGGA,(\d{6}),(\d{2})(\d{2}\.\d{4}),(N|S),(\d{3})(\d{2}\.\d{4}),(E|W),(\d),(\d{2}),([\d\.]+),([\d\.]+),M/) {
		my $extra = {"Received" => "". localtime(time)};
		my $zulu = $1;
		my $lat = $2 + ($3 / 60); $lat = -$lat if ($4 eq 'S');
		my $long = $5 + ($6 / 60); $long = -$long if ($7 eq 'W');
		$extra->{'Fix Quality'} = ("invalid", "GPS", "DGPS", "PPS", "RTK (integer)", "RTK (float)", "Estimated", "Manual", "Simulator")[$8 > 8 ? 0 : $8];
		$extra->{'Satellites for fix'} = $9;
		$extra->{'HDOP'} = $10;
		my $alt = $11;

		addCoordToKML($from, $zulu, $lat, $long, $alt, undef, undef, $extra);

	} else {
		# XXX should probably do GPRMC and GPLL as well
		return;
	}

	return;
}

# APRS required position reports:
#    !3746.74N/12224.06W>274/021/A=000000
#    @281856z3749.28N/12017.11WR069/023/A=001868 Ken - Calaveras County, CA {UIV32N}
#    @281852z3803.00N/12010.00W_148/007g012t060r000p000P000h27b10486.DsVP
#    =3746.42N112226.00W# {UIV32N}
#      (code does not support thte compressed variations.)
# NMEA, optional in APRS, rarely used in wild, but used for Bacchus II-VI:
#     $GPGGA,185525.00,3743.22160,N,12132.01335,W,2,12,0.90,82.0,M,-28.9,M,,0000*5E
#   APRS recommends supporting GGA, GLL, RMC, VTG, and WPT.
sub handleAPRS {
	my ($from, $to, $path, $data) = @_;

	print "APRS: $from>$to,$path:$data\n";

	# do this here to minimize risk of barfing on other peoples' broken packets
	return unless $from =~ /$STATION/;

	$data =~ s/^.*?([\!\$\/\=\@].*)$/$1/ if ($data =~ /^[A-Za-z]/); # not clear how this X1J thing is supposed to work.
	if ($data =~ /^\$/) { # very different format
		handleNMEA($from, $to, $path, $data);
		return;
	}
	return unless $data =~ /^([\!\/\=\@])/;

	# @281856z3749.28N/12017.11WR069/023/A=001868 Ken - Calaveras County, CA {UIV32N}
	my ($long, $lat, $alt, $speed, $heading, $zulu, $symbol, $comment);
	if ($data =~ /^(\@|\/)(\d{6})(z|\/|h)([0-9\ ]{4}\.[0-9\ ]{2}(N|S))(.)([0-9\ ]{5}\.[0-9\ ]{2}(E|W))(.)(.*)$/) {
		$zulu = $2.$3;
		$lat = $4;
		$symbol = $6.$9;
		$long = $7;
		$comment = $10;
	} elsif ($data =~ /^(\!|\=)([0-9\ ]{4}\.[0-9\ ]{2}(N|S))(.)([0-9\ ]{5}\.[0-9\ ]{2}(E|W))(.)(.*)$/) {
		$lat = $2;
		$symbol = $4.$7;
		$long = $5;
		$comment = $8;
	} else {
		print "XXX unknown format! '$data'\n";
		return;
	}
	if ($comment =~ s/^(\d{3})\/(\d{3})//) { # the only "data extension" we support/care about
		$heading = $1;
		$speed = $2;
	}
	if ($comment =~ s/\/A=(\d{6})//) { # way to be consistent about extensions there, APRS.
		$alt = $1;
	}

	# lose the knowledge of lack of accuracy
	$lat =~ tr/\ /0/; $long =~ tr/\ /0/;

	# de-stupidify.
	$long =~ s/^(\d{3})(\d{2}\.\d{2})(E|W)$//; $long = $1 + ($2 / 60); $long = -$long if ($3 eq 'W');
	$lat =~ s/^(\d{2})(\d{2}\.\d{2})(N|S)$//; $lat = $1 + ($2 / 60); $lat = -$lat if ($3 eq 'S');
	$alt = $alt * 0.3048 if defined $alt; # the metric system!
	$speed = $speed + 0 if defined $speed; # it scales!

	addCoordToKML($from, $zulu, $lat, $long, $alt, $speed, $heading, { "APRS comment" => $comment, "Repeater path" => $path, "APRS symbol" => $symbol, "Received" => "". localtime(time)  } );
}

sub main {

	createBlankKML($OUTFN, $STATION) if not -e $OUTFN;

	my ($multimon);
	# this only works with a multimon that's been modified to fflush(stdout) a lot...
	open($multimon, $CMD) || die "unable to start aprs receiver";
	my $header;
	while (my $line = <$multimon>) {
		$line =~ tr/\r//d; $line =~ tr/\n//d;
		print "in: '$line'\n";

		# multimon samples (multiline)
		#   AFSK1200: fm KA6BQF-8 to APT311-0 via N6WKZ-3,WIDE2-2 UI  pid=F0
		#   !3746.74N/12224.06W>274/021/A=000000
		if (!defined $header && $line =~ /AFSK1200:\s+fm\s+([A-Z0-9\-]+)\s+to\s+([A-Z0-9\-]+)(\s*via\s+([A-Z0-9\-\,]+))/) {
			$header->{'from'} = $1;
			$header->{'to'} = $2;
			$header->{'path'} = $4;
			next;  # finish on the next line
		} elsif (defined $header) {
			handleAPRS($header->{'from'}, $header->{'to'}, $header->{'path'}, $line);
			$header = undef; # only support one line to avoid getting out of sync. is more than one data line possible?
			next;
		}

		# aprsmon samples (single line)
		#   KJ6AOD-11>APZ111,WIDE2-2:>ProjectBacchus.org Uptime=00:57:39 Temp=99F,84F,83F (271,246,244) Acc=471,499,329
		#   KJ6AOD-11>APZ111,WARD*,WIDE2-1:>ProjectBacchus.org Uptime=00:57:39 Temp=99F,84F,83F (271,246,244) Acc=471,499,329
		if ($line =~ /([A-Z0-9\-]+)>([A-Z0-9\-]+)(,(.*?))\:(.*)$/) {
			handleAPRS($1, $2, $4 || "", $5);
		}
			
	}
	print STDERR "multimon died\n";
	return 0;
}

