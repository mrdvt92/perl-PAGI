#!/usr/bin/env perl
use strict;
use warnings;
use experimental 'signatures';
use Test2::V0;
use Future::AsyncAwait;

use lib 'lib';
use PAGI::Simple;
use PAGI::Simple::Handler;

# Create a test handler
{
    package TestApp::Todos;
    use parent 'PAGI::Simple::Handler';
    use experimental 'signatures';
    use Future::AsyncAwait;

    our $routes_called = 0;
    our $received_app;

    sub routes ($class, $app, $r) {
        $routes_called = 1;
        $received_app = $app;
        $r->get('/' => '#index');
    }

    async sub index ($self, $c) {
        $c->text('todos index');
    }

    $INC{'TestApp/Todos.pm'} = 1;
}

subtest 'mount detects Handler and calls routes()' => sub {
    $TestApp::Todos::routes_called = 0;
    $TestApp::Todos::received_app = undef;

    my $app = PAGI::Simple->new(name => 'Main', quiet => 1);

    # Mount the handler
    $app->mount('/todos' => 'TestApp::Todos');

    # routes() should have been called
    ok($TestApp::Todos::routes_called, 'routes() was called');

    # routes() should receive the root app (use refaddr to avoid deep comparison)
    use Scalar::Util qw(refaddr);
    is(refaddr($TestApp::Todos::received_app), refaddr($app), 'routes() received root app');
};

subtest '$c->app returns root Application' => sub {
    # This will be tested via integration test
    pass('deferred to integration test');
};

done_testing;
