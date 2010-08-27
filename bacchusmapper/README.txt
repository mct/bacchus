So you'll need a webserver.  I tried my best to avoid any dependencies but
stupid javascript security rules prevent this from working with just file:///
URLs.  It doesn't need to do anything special though--no CGI is involved, and
all paths are relative.  Pick a directory under the web root path that you have
access to.  Let's call it $ROOTDIR.  Pick another directory that's preferably
not web accessible for running the perl scripts out of.  Let's call it
$TOOLSDIR.

You should grab the tile sets:
    http://bacchusmapdata.s3.amazonaws.com/tiles-osm-california-20100711-zoom0-15.tar.bz2
    http://bacchusmapdata.s3.amazonaws.com/hillshadedtiles-california-zoom0-13.tar.bz2

PLAN AHEAD: These will take 1-2 hours to download and nearly as long to unpack.
Although the tars are only a couple gigs uncompressed, they will take up 5-15GB
on disk depending on your filesystem cluster size.  The first one is absolutely
required, the second mostly makes it look pretty and is also substantially
larger.  But you should get it! It's fun.

These will untar their own directories, leaving you with:
  $ROOTDIR/tiles
  $ROOTDIR/hillshadedtiles

Then go get the ground station tools and web stuff:
    http://bacchusmapdata.s3.amazonaws.com/bacchusmapper-0.1.tar.bz2

Untar this anywhere.  It has two directories.  The contents of the web/
directory should move to $ROOTDIR (so you have $ROOTDIR/index.html and
$ROOTDIR/tiles, etc).  You should now able able to load that in your browser
and have it sit there all pretty.

Mv the tools/ subdir to $TOOLSDIR.  There are two scripts and a KML template.
You shouldn't need to touch the KML template, just make sure it's in the same
directory as the scripts.

*** Local GPS ***

To start generating a live KML from a local gpsd stream, start gpsd, and then do:
   bacchusmapper-gpsd.pl $ROOTDIR/gpsd.kml

By default it updates the location in the KML every 30 seconds, but you can
edit that at the top.  Since you're running gpsd, you can also just run more
than one with different frequencies if you're really crazy about it (eg mct).
Just make sure to specify different kml files on the command line.  


*** Watching an APRS station ***

To start generating a live KML based on APRS position packets, first you'll
need to pick a method of getting packets.  This involves uncommenting the right
line at the top of bacchusmapper-aprs.pl.  It should be obvious.  (If you want
to do this on OS X, you'll need to get a copy of sox and multimon from me,
separately.)

Then do:
   bacchusmapper-aprs.pl $ROOTDIR/aprs.kml KJ6DYS-11

If you chose aprsmon, it'll ask you for your sudo password, since aprsmon must
run as root.

If you're running multimon you can only do one of these, since you only have
one sound card.  But if you're running the full Linux AX.25 stack you can start
as many of these as you want with different call signs; again just make sure
you specify a different output kml for each.  


*** Adding KMLs to the map ***

If you're just doing the two things above, the command lines I just gave will
produce files already set to load on the map.  If you do other stuff or if you
choose other filenames, you'll need to edit $ROOTDIR/index.html.  Right at the
top is a big comment that tells you where to edit.  Just add a line for each
layer you want, setting the right filename and color.  The file *must* be
within the same directory (or n subdirectories) as index.html, or your browser
will silently refuse to load it.  

Also if you want more colors than red, yellow, and blue, you'll need to define
it.  Copy and paste the obvious section and change the numbers/names.

Obviously after you touch anything you'll need to do a heavy reload (the reload
button).  If just the data is changing, you can just hit the refresh button at
the top (or just let it auto-refresh every 10sec, which it does if the checkbox
at the top is marked).

The measure distance checkbox is great: check it, and then click to draw a
multisegment line on the map (double-click to end drawing).  The measurement at
the top should be roughly correct (sorry, it's in kilometers).  Uncheck the
measure distance box to go back to normal pan/select mode.  Also note that your
cursor's current latlon is always displayed at the bottom right corner.
Obviously you can also click on points to view the coordinates and other info.
The "scale" is a ratio of unknown units.  I don't know how to interpret it, but
it's still useful for telling another person what zoom level you're at.
Speaking of units, unless they're specifically labelled, I have no idea what
units most of the numbers are in (particularly speed, but also occasionally
altitude).  Good luck.

asf.

