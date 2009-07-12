use strict;
use warnings;

use Test::More tests => 6;
use Test::Exception;

use BIBOP;

throws_ok { BIBOP::bget('foo', *x) } qr/node handle must be a reference/,
    "detected non-ref node handle";

throws_ok { BIBOP::bget(\2, *x) } qr/node handle has incorrect magic/,
    "detected bad ref node handle";

throws_ok { BIBOP::bget(2) } qr/Usage/, "usage for bget / too few";
throws_ok { BIBOP::bnew(2) } qr/Usage/, "usage for bnew / too many";

my $x = BIBOP::bnew();

throws_ok { BIBOP::bget($x, *y) } qr/not found/, "noticed missing on get";
throws_ok { BIBOP::bdelete($x, *y) } qr/not found/, "noticed missing on del";
