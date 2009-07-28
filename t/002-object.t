use strict;
use warnings;

use Test::More tests => 25;
use Scalar::Util 'refaddr';
use Test::Exception;

use Arena::Compact -all => { -prefix => 'b' };

my $obj1 = bnew();
my $obj2 = bnew();

pass("created two objects");

isnt(refaddr($obj1), refaddr($obj2), "two _different_ objects_");

my $kx = bkey('x');
my $ky = bkey('y');
my $kz = bkey('z');

pass("and three keys");

lives_ok { bput($obj1, $kx, 12.0); } "set first x";
lives_ok { bput($obj1, $ky, 23.0); } "set first y";
lives_ok { bput($obj2, $kx, 34.0); } "set second x";
lives_ok { bput($obj2, $ky, 45.0); } "set second y";

is(bget($obj1, $kx), 12.0, "first x preserved");
is(bget($obj1, $ky), 23.0, "first y preserved");
is(bget($obj2, $kx), 34.0, "second x preserved");
is(bget($obj2, $ky), 45.0, "second y preserved");

lives_ok { bput($obj1, $ky, 99.0); } "resetting first y";

is(bget($obj1, $kx), 12.0, "first x still preserved");
is(bget($obj1, $ky), 99.0, " y updated");
is(bget($obj2, $kx), 34.0, "second x still preserved");
is(bget($obj2, $ky), 45.0, "second y still preserved");

lives_ok { undef $obj1; } "deleting out of order works";

is(bget($obj2, $kx), 34.0, "second x _still_ preserved");
is(bget($obj2, $ky), 45.0, "second y _still_ preserved");

ok(bexists($obj2, $kx), "second has x");
ok(bexists($obj2, $ky), "second has y");
ok(not(bexists($obj2, $kz)), "second has not is");

lives_ok { bdelete($obj2, $kx) } "deleting fields works";

ok(not(bexists($obj2, $kx)), "second no longer has x");
ok(bexists($obj2, $ky), "second still has y");
