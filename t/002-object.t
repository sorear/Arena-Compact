use strict;
use warnings;

use Test::More tests => 24;
use Scalar::Util 'refaddr';
use Test::Exception;

use Arena::BIBOP;

my $obj1 = Arena::BIBOP::bnew();
my $obj2 = Arena::BIBOP::bnew();

pass("created two objects");

isnt(refaddr($obj1), refaddr($obj2), "two _different_ objects_");

lives_ok { Arena::BIBOP::bput($obj1, *x, 12.0); } "set first x";
lives_ok { Arena::BIBOP::bput($obj1, *y, 23.0); } "set first y";
lives_ok { Arena::BIBOP::bput($obj2, *x, 34.0); } "set second x";
lives_ok { Arena::BIBOP::bput($obj2, *y, 45.0); } "set second y";

is(Arena::BIBOP::bget($obj1, *x), 12.0, "first x preserved");
is(Arena::BIBOP::bget($obj1, *y), 23.0, "first y preserved");
is(Arena::BIBOP::bget($obj2, *x), 34.0, "second x preserved");
is(Arena::BIBOP::bget($obj2, *y), 45.0, "second y preserved");

lives_ok { Arena::BIBOP::bput($obj1, *y, 99.0); } "resetting first y";

is(Arena::BIBOP::bget($obj1, *x), 12.0, "first x still preserved");
is(Arena::BIBOP::bget($obj1, *y), 99.0, " y updated");
is(Arena::BIBOP::bget($obj2, *x), 34.0, "second x still preserved");
is(Arena::BIBOP::bget($obj2, *y), 45.0, "second y still preserved");

lives_ok { undef $obj1; } "deleting out of order works";

is(Arena::BIBOP::bget($obj2, *x), 34.0, "second x _still_ preserved");
is(Arena::BIBOP::bget($obj2, *y), 45.0, "second y _still_ preserved");

ok(Arena::BIBOP::bexists($obj2, *x), "second has x");
ok(Arena::BIBOP::bexists($obj2, *y), "second has y");
ok(not(Arena::BIBOP::bexists($obj2, *is)), "second has not is");

lives_ok { Arena::BIBOP::bdelete($obj2, *x) } "deleting fields works";

ok(not(Arena::BIBOP::bexists($obj2, *x)), "second no longer has x");
ok(Arena::BIBOP::bexists($obj2, *y), "second still has y");
