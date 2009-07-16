use strict;
use warnings;

use Test::More tests => 6;
use Test::Exception;

use Arena::BIBOP;

my $kx = Arena::BIBOP::key('x');
my $ky = Arena::BIBOP::key('y');

throws_ok { Arena::BIBOP::get('foo', $kx) } qr/node handle must be a reference/,
    "detected non-ref node handle";

throws_ok { Arena::BIBOP::get(\2, $kx) } qr/node handle has incorrect magic/,
    "detected bad ref node handle";

throws_ok { Arena::BIBOP::get(2) } qr/Usage/, "usage for bget / too few";
throws_ok { Arena::BIBOP::new(2) } qr/Usage/, "usage for bnew / too many";

my $x = Arena::BIBOP::new();

throws_ok { Arena::BIBOP::get($x, $ky) } qr/not found/, "noticed missing on get";
throws_ok { Arena::BIBOP::delete($x, $ky) } qr/not found/, "noticed missing on del";
