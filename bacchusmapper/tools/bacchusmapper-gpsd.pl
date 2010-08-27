#!/usr/bin/perl 
# vim:set ts=4 sw=4 ai:

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

	open my $gpsd, "gpspipe -r |" or die "fork: $!";
	my $lastts = 0;

	while (my $line = <$gpsd>) {
		$line =~ s/\r?\n$//;
		warn "in: '$line'\n";

		# $GPGGA,172134.84,3747.0852,N,12223.3278,W,1,03,22.4,00008,M,,,,*04
		# $GPGGA,210948.48,3748.9736,N,12107.6101,W,1,08,1.1,00014,M,,,,*34

		if ($line =~ /^\$GPGGA,(\d{2})(\d{2})(\d{2}).\d{2},([\d\.]+),N,([\d\.]+),W,(\d+),(\d+),([\d.]+),([\d\.]+),M,/) {
			my ($hour, $min, $sec, $long, $lat, $fixtype, $num_sats, $horizontal_dilution, $alt) =
				($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);

			my $fraction;
			$lat *= -1 / 100;
			$long /= 100;

			$fraction = $lat - int $lat;
			$lat = int($lat) + $fraction/60 * 100;

			$fraction = $long - int $long;
			$long = int($long) + $fraction/60 * 100;

			$alt = 0 if ($alt <= 0);
			my $feet = $alt * 3.2808399;
			my $speed = 0;

			unless (time - $lastts >= $FREQ) {
				warn "Position: $lat $long $feet $speed (too soon)\n";
				next;
			} else {
				warn "Position: $lat $long $feet $speed\n";
			}

			addCoordToKML($OUTFN, scalar(localtime), $long, $lat, $feet, $speed);
			$lastts = time;
		}
	}
	warn "EOF\n";
	close $gpsd;
	return 0;
}

