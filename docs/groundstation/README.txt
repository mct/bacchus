This directory contains notes, and data for operating a groundstation

On mct's laptop, to restore the sound settings to something sane, and start up
soundmodem to create the AX.25 network interface:

	alsactl restore -f alsactl.store.mct.20091119.txt
	sudo /etc/init.d/avahi-daemon stop
	sudo soundmodem

(Sometimes soundmodem complains about the sound device and refuses to start.
It's annoying, but rebooting fixes that problem.)

In another window, to record the APRS packets we're receiving:

	sudo aprsmon -r | tai64n | tai64nlocal | tee aprsmon.$(date +%Y-%m-%d-%H%M%S)

To startup gpsd, which communicates with an NMEA GPS over the serial port, and
makes that information available over the network:

	gpsd -b  -G -n -N /dev/ttyUSB0 -D 2

In another window, to record where we've been:

	gpspipe -r | gpspipe.$(date +%Y-%m-%d-%H%M%S)
