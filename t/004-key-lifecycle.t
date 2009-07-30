use strict;
use warnings;

use Test::More tests => 14;
use Scalar::Util 'refaddr';
use Test::Exception;

use Arena::Compact -all => { -prefix => 'b' };

my ($k1, $k2, $k3, $k4, $k5);

lives_ok { $k1 = bkey("A"); } "created first key";
lives_ok { $k2 = bkey("B"); } "created second key";
lives_ok { $k3 = bkey("A"); } "created new name for first key";

is(refaddr $k1, refaddr $k3, "first key is the same");
lives_ok { undef $k1; } "deleted first name of first key";
lives_ok { $k4 = bkey("A"); } "created third name";
is(refaddr $k4, refaddr $k3, "still the same key");

my $rak2 = refaddr($k2);
my $ob = bnew();
bput($ob, $k2, 42);

lives_ok { undef $k2 } "deleted key with object in scope";
my $foo = [ 1 .. 200 ]; # make some garbage
lives_ok { $k4 = bkey("B"); } "recreated it";
is($rak2, refaddr $k4, "with same refaddr");
is(bget($ob, $k4), 42, "and points to same contents");

lives_ok { undef $k3 } "deleted last name of first key";
lives_ok { $k3 = bkey("B"); } "another name for second key";
is(refaddr $k3, $rak2, "and still the same");

