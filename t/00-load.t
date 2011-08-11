#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Heart::Domain::API' ) || print "Bail out!\n";
}

diag( "Testing Heart::Domain::API $Heart::Domain::API::VERSION, Perl $], $^X" );
