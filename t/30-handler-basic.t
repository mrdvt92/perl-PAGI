#!/usr/bin/env perl
use strict;
use warnings;
use experimental 'signatures';
use Test2::V0;

use lib 'lib';

# Test that Handler can be loaded
my $loaded = eval { require PAGI::Simple::Handler; 1 };
ok($loaded, 'PAGI::Simple::Handler loaded') or diag($@);

# Test basic instantiation
subtest 'Handler instantiation' => sub {
    my $handler = PAGI::Simple::Handler->new;
    ok($handler, 'can create handler');
    isa_ok($handler, 'PAGI::Simple::Handler');
};

# Test that Handler has expected methods
subtest 'Handler interface' => sub {
    my $handler = PAGI::Simple::Handler->new;

    can_ok($handler, 'app');
    can_ok($handler, 'routes');
};

done_testing;
