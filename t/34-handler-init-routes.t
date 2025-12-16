#!/usr/bin/env perl
use strict;
use warnings;
use experimental 'signatures';
use Test2::V0;
use Future::AsyncAwait;

use lib 'lib';

# Test subclassing PAGI::Simple with init() and routes()
{
    package MyTestApp;
    use parent 'PAGI::Simple';
    use experimental 'signatures';
    use Future::AsyncAwait;

    our $init_called = 0;
    our $routes_called = 0;

    sub init ($class) {
        $init_called = 1;
        return (
            name  => 'MyTestApp',
            quiet => 1,
        );
    }

    sub routes ($class, $app, $r) {
        $routes_called = 1;
        $r->get('/' => '#home');
    }

    async sub home ($self, $c) {
        $c->text('home');
    }
}

subtest 'init() provides defaults' => sub {
    $MyTestApp::init_called = 0;

    my $app = MyTestApp->new;

    ok($MyTestApp::init_called, 'init() was called');
    is($app->name, 'MyTestApp', 'name from init()');
};

subtest 'constructor args override init()' => sub {
    my $app = MyTestApp->new(name => 'Override');

    is($app->name, 'Override', 'constructor arg wins');
};

subtest 'routes() called after construction' => sub {
    $MyTestApp::routes_called = 0;

    my $app = MyTestApp->new;

    ok($MyTestApp::routes_called, 'routes() was called');
};

done_testing;
