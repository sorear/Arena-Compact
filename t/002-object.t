use strict;
use warnings;

use Test::More tests => 25;
use Scalar::Util 'refaddr';
use Test::Exception;

use Arena::BIBOP;

my $obj1 = Arena::BIBOP::bnew();
my $obj2 = Arena::BIBOP::bnew();

pass("created two objects");

isnt(refaddr($obj1), refaddr($obj2), "two _different_ objects_");

my $kx = Arena::BIBOP::knamed('x');
my $ky = Arena::BIBOP::knamed('y');
my $kz = Arena::BIBOP::knamed('z');

pass("and three keys");

lives_ok { Arena::BIBOP::bput($obj1, $kx, 12.0); } "set first x";
lives_ok { Arena::BIBOP::bput($obj1, $ky, 23.0); } "set first y";
lives_ok { Arena::BIBOP::bput($obj2, $kx, 34.0); } "set second x";
lives_ok { Arena::BIBOP::bput($obj2, $ky, 45.0); } "set second y";

is(Arena::BIBOP::bget($obj1, $kx), 12.0, "first x preserved");
is(Arena::BIBOP::bget($obj1, $ky), 23.0, "first y preserved");
is(Arena::BIBOP::bget($obj2, $kx), 34.0, "second x preserved");
is(Arena::BIBOP::bget($obj2, $ky), 45.0, "second y preserved");

lives_ok { Arena::BIBOP::bput($obj1, $ky, 99.0); } "resetting first y";

is(Arena::BIBOP::bget($obj1, $kx), 12.0, "first x still preserved");
is(Arena::BIBOP::bget($obj1, $ky), 99.0, " y updated");
is(Arena::BIBOP::bget($obj2, $kx), 34.0, "second x still preserved");
is(Arena::BIBOP::bget($obj2, $ky), 45.0, "second y still preserved");

lives_ok { undef $obj1; } "deleting out of order works";

is(Arena::BIBOP::bget($obj2, $kx), 34.0, "second x _still_ preserved");
is(Arena::BIBOP::bget($obj2, $ky), 45.0, "second y _still_ preserved");

ok(Arena::BIBOP::bexists($obj2, $kx), "second has x");
ok(Arena::BIBOP::bexists($obj2, $ky), "second has y");
ok(not(Arena::BIBOP::bexists($obj2, $kz)), "second has not is");

lives_ok { Arena::BIBOP::bdelete($obj2, $kx) } "deleting fields works";

ok(not(Arena::BIBOP::bexists($obj2, $kx)), "second no longer has x");
ok(Arena::BIBOP::bexists($obj2, $ky), "second still has y");
