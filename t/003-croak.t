use strict;
use warnings;

use Test::More tests => 6;
use Test::Exception;

use Arena::BIBOP;

my $kx = Arena::BIBOP::knamed('x');
my $ky = Arena::BIBOP::knamed('y');

throws_ok { Arena::BIBOP::bget('foo', $kx) } qr/node handle must be a reference/,
    "detected non-ref node handle";

throws_ok { Arena::BIBOP::bget(\2, $kx) } qr/node handle has incorrect magic/,
    "detected bad ref node handle";

throws_ok { Arena::BIBOP::bget(2) } qr/Usage/, "usage for bget / too few";
throws_ok { Arena::BIBOP::bnew(2) } qr/Usage/, "usage for bnew / too many";

my $x = Arena::BIBOP::bnew();

throws_ok { Arena::BIBOP::bget($x, $ky) } qr/not found/, "noticed missing on get";
throws_ok { Arena::BIBOP::bdelete($x, $ky) } qr/not found/, "noticed missing on del";
