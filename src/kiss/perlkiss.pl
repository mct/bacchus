#!/usr/bin/perl
# vim:set ts=4 sw=4 ai:
# mct, Sun Nov  1 21:48:53 EST 2009

use Device::SerialPort;
use Getopt::Long;

use strict;
use warnings;

my ($tty, $baud, $debug, $nopause);
GetOptions("baud=i" => \$baud, "tty=s" => \$tty, "debug" => \$debug, "nopause" => \$nopause)
	and $tty
		or die "Usage: $0 --tty <serial_device> [--baud <baud_rate>] [--debug]\n";

$baud ||= 9600;

my $port = new Device::SerialPort $tty
	or die "$tty: $!\n";
$port->baudrate($baud);
$port->databits(8);
$port->parity("none");
$port->stopbits(1);
$|++;

my $count;

while (1) {
	$count++;

	# KISS constants defined in http://www.ka9q.net/papers/kiss.html
	my $FEND  = chr 0xC0; # Frame End
	my $FESC  = chr 0xDB; # Frame Escape
	my $TFEND = chr 0xDC; # Transposed Frame End
	my $TFESC = chr 0xDD; # Transposed Frame Escape

	# AX.25 address information of the packet we're sending, which is composed of
	# the destination, source, and repeater path.  Addresses are six alpha-numeric
	# characters followed by an SSID.  SSIDs are 4-bit integers.  The octet that
	# contains the SSID also contains some bits that have been reserved by the
	# AX.25 protocol.  Those reserved bits should be set to 1.
	my @address;

	# In APRS, the destination address is used to encode the software version of
	# the sender; its prefix "APZ" is used to encode a software version that is
	# "experimental", or otherwise has not yet been assigned a prefix by the APRS
	# governing body.  We're going to send with "APZ111-0"
	push @address, map { ord } split //, "APZ111";
	push @address, 0 | 0x30;

	#11100000 # Receiver SSID
	# 1100000 # sender SSID
	# 110000_ # sender SSID

	# Source is the callsign of the operator.  SSID 11 is a weather balloon.
	push @address, map { ord } split //, "KJ6AOD";
	push @address, 11 | 0x30;

	# WIDE2-2 is a commonly used repeater path.
	push @address, map { ord } split //, "WIDE2 ";
	push @address, 2 | 0x30;

	# Encode the addresses.  Shift each byte one bit to the left.  If the least
	# significant bit is 0, the next byte contains more addressing information. 
	# If the the least significant bit is 1, this is the last byte of address
	# information.
	$_ <<= 1 for (@address);
	$address[-1] |= 0x1;

	# Set the C-bit for the destination address; MSB of the SSID octet
	$address[6] |= 0x80;

	# Confirm address length
	die "Unexpected address length?\n" unless @address % 7 == 0;

	# The APRS payload we want to send.  Just a silly "status" string (indicated
	# by the ">" character) for now.  Later, this will be replaced with NMEA data.
	# Must be less than 256 bytes.
	my $aprs = ">Project Bacchus Test Packet\r\n";

	# Build up the packet buffer
	my $buf = "";
	$buf .= chr 0x00; # KISS port0 data
	$buf .= chr $_ for (@address);
	$buf .= chr 0x03; # AX.25 UI frame
	$buf .= chr 0xF0; # Protocol ID -- no layer3 protocol
	$buf .= $aprs;    # payload

	# Escape any bytes we need, then surround the frame packet in FRAME END markers
	$buf =~ s/$FESC/$FESC$TFESC/g;
	$buf =~ s/$FEND/$FESC$TFEND/g;
	$buf = $FEND . $buf . $FEND;

	print "Sending $count at $baud\n";
	print "Raw frame: <",$buf,">\n" if $debug;

	my $len = length $buf;
	my $sent_len = $port->write($buf);
	die "Tried to send $len, but really sent $sent_len?\n"
		unless $len == $sent_len;

	until ($port->write_drain) {
		select(undef, undef, undef, 0.1);
	}

	select(undef, undef, undef, .1);

	scalar <>
		unless $nopause;
}
