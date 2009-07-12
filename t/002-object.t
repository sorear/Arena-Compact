use strict;
use warnings;

use Test::More tests => 18;
use Scalar::Util 'refaddr';
use Test::Exception;

use BIBOP;

my $obj1 = BIBOP::bnew();
my $obj2 = BIBOP::bnew();

pass("created two objects");

isnt(refaddr($obj1), refaddr($obj2), "two _different_ objects_");

lives_ok { BIBOP::bput($obj1, *x, 12.0); } "set first x";
lives_ok { BIBOP::bput($obj1, *y, 23.0); } "set first y";
lives_ok { BIBOP::bput($obj2, *x, 34.0); } "set second x";
lives_ok { BIBOP::bput($obj2, *y, 45.0); } "set second y";

is(BIBOP::bget($obj1, *x), 12.0, "first x preserved");
is(BIBOP::bget($obj1, *y), 23.0, "first y preserved");
is(BIBOP::bget($obj2, *x), 34.0, "second x preserved");
is(BIBOP::bget($obj2, *y), 45.0, "second y preserved");

lives_ok { BIBOP::bput($obj1, *y, 99.0); } "resetting first y";

is(BIBOP::bget($obj1, *x), 12.0, "first x still preserved");
is(BIBOP::bget($obj1, *y), 99.0, " y updated");
is(BIBOP::bget($obj2, *x), 34.0, "second x still preserved");
is(BIBOP::bget($obj2, *y), 45.0, "second y still preserved");

lives_ok { undef $obj1; } "deleting out of order works";

is(BIBOP::bget($obj2, *x), 34.0, "second x _still_ preserved");
is(BIBOP::bget($obj2, *y), 45.0, "second y _still_ preserved");

1;

