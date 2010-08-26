#!/usr/bin/perl 

# seconds
my $FREQ = 30;

use strict;
use warnings;

exit main();


# this only works with specially tagged KMLs... 'cause I don't wanna parse XML.
# write out both a point and append to the polyline
sub addCoordToKML {
	my $fn = shift;
	my ($zulu, $lat, $long, $alt, $speed) = @_;
	my $hostname = qx[uname -n];
	chomp $hostname;

	# these are effectively optional
	$alt = "" unless defined $alt;  # kml should be blank if unknown
	$speed = "unknown" unless defined $speed;

	open(KMLNEW, ">$fn.new") || die "unable to open $fn.new for writing";
	open(KML, "<$fn") || die "unable to open $fn for reading";
	while (my $line = <KML>) {
		# obviously make sure you put the tag back in when you're done...
		$line =~ s/(<!--\s*ADDPLACEMARK\s*-->)/<Placemark><name>GPS on $hostname<\/name><description><![CDATA[$zulu<br\/>($long, $lat, $alt) @ $speed]]><\/description><styleUrl>#t266254<\/styleUrl><Point><altitudeMode>absolute<\/altitudeMode><coordinates>$long, $lat, $alt<\/coordinates><\/Point><\/Placemark>\n$1/;
		$line =~ s/(<!--\s*ADDTOLINE\s*-->)/$long,$lat,$alt   $1/;
		print KMLNEW $line;
	}
	close KML;
	close KMLNEW;

	rename("$fn.new", "$fn");
}

sub createBlankKML {
	my $fn = shift;
	my $hostname = qx[uname -n];
	chomp $hostname;

	open(OUT, ">$fn") || die "unable to open $fn for writing";
	open(TEMPL, "<bacchusmapper-kml-template.kml") || die "unable to open bacchusmapper-kml-template.kml to create new KML";
	while (my $line = <TEMPL>) {
		$line =~ s/<!--\s*STATIONNAME\s*-->/GPS on $hostname/;
		$line =~ s/<!--\s*STATIONDESCRIPTION\s*-->/GPS locally attached to gpsd on $hostname/;
		print OUT $line;
	}
	close TEMPL; close OUT;
	return;
}

sub connectToGPS {
	use IO::Handle;
	use Socket;

	my $sock;

	socket($sock, PF_INET, SOCK_STREAM, (getprotobyname('tcp'))[2]) || die "socket() failed";
	connect($sock, sockaddr_in(2947, inet_aton("127.0.0.1"))) || die "unable to connect to gpsd";
	$sock->autoflush(1);

	return $sock;
}

sub parsedict {
	my $ind = shift;
	my %dict;

	$ind =~ s/^\{(.*)\}$/$1/;
	while ($ind ne '') {
		my ($key, $value);
		if ($ind =~ /^"/) { $ind =~ s/^\"(.*?)\"\:(.*)$/$2/; $key = $1; } else { $ind =~ s/^(.*?)\:(.*)$/$2/; $key = $1; }
		die "invalid dictionary -- no key" unless defined $key;
		if ($ind =~ /^\[/) { return \%dict; } # XXX heh.
		if ($ind =~ /^"/) { $ind =~ s/^\"(.*?)\"(\,|$)(.*)$/$3/; $value = $1; } else { $ind =~ s/^(.*?)(\,|$)(.*)$/$3/; $value = $1; }
		die "invalid dictionary -- no value for key '$key'" unless defined $value; # may be empty string though
		$dict{$key} = $value;
	}
	return \%dict;
}

sub main {
	die "need output KML filename" unless defined $ARGV[0];
	my $OUTFN = $ARGV[0];

	createBlankKML($OUTFN) if not -e $OUTFN;

	my $gpsd = connectToGPS();

	my $initdone = 0;
	my $lastts = 0;
	while (my $line = <$gpsd>) {
		$line =~ tr/\r//d; $line =~ tr/\n//d;
		print STDERR "in: '$line'\n";
		my $d = parsedict($line);
		die "no class in packet from gpsd" unless defined $d->{'class'};
		if (!$initdone && $d->{'class'} eq "VERSION") {
			print $gpsd "?WATCH={\"enable\":true,\"json\":true}\r\n";
			$initdone = 1;
		} elsif (($d->{'class'} eq 'TPV') && ($d->{'tag'} eq 'GLL')) {
			# {"class":"TPV","tag":"GLL","device":"/dev/tty.usbserial","time":1280012402.000,"ept":0.005,"lat":37.762366667,"lon":-122.419180000,"alt":25.000,"epx":27.271,"epy":24.113,"epv":23.000,"track":0.0000,"speed":0.000,"climb":0.000,"mode":3}
			print "" . $d->{'time'} . ": (" . $d->{'lat'} . ", " . $d->{'lon'} . ", " . $d->{'alt'} . ") @ " . $d->{'speed'} . "\n";
			next unless defined $d->{'time'} && defined $d->{'lat'} && defined $d->{'lon'} && defined $d->{'alt'} && defined $d->{'speed'};
			next unless (time - $lastts >= $FREQ);
			addCoordToKML($OUTFN, $d->{'time'}, $d->{'lat'}, $d->{'lon'}, $d->{'alt'}, $d->{'speed'});
			$lastts = time + 0;
		}

	}
	close $gpsd;
	return 0;
}

