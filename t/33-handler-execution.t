#!/usr/bin/env perl
use strict;
use warnings;
use experimental 'signatures';
use Test2::V0;
use Future::AsyncAwait;

use lib 'lib';
use PAGI::Simple;
use PAGI::Simple::Handler;

# Create a test handler with actual route handlers
{
    package TestApp::API;
    use parent 'PAGI::Simple::Handler';
    use experimental 'signatures';
    use Future::AsyncAwait;

    our @calls;

    sub routes ($class, $app, $r) {
        $r->get('/' => '#index');
        $r->get('/:id' => '#load' => '#show');
    }

    async sub index ($self, $c) {
        push @calls, 'index';
        $c->text('api index');
    }

    async sub load ($self, $c) {
        my $id = await $c->param('id');
        push @calls, 'load:' . $id;
        $c->stash->{item} = { id => $id };
    }

    async sub show ($self, $c) {
        push @calls, 'show';
        $c->json($c->stash->{item});
    }

    $INC{'TestApp/API.pm'} = 1;
}

# Helper to simulate request
sub make_request ($app, $method, $path) {
    my $response_body;
    my $response_status;

    my $scope = {
        type => 'http',
        method => $method,
        path => $path,
        headers => [],
        query_string => '',
    };

    my $receive = async sub { { type => 'http.request', body => '' } };
    my $send = async sub ($event) {
        if ($event->{type} eq 'http.response.start') {
            $response_status = $event->{status};
        }
        elsif ($event->{type} eq 'http.response.body') {
            $response_body .= $event->{body} // '';
        }
    };

    $app->to_app->($scope, $receive, $send)->get;

    return ($response_status, $response_body);
}

subtest 'single #method handler executes' => sub {
    @TestApp::API::calls = ();

    my $app = PAGI::Simple->new(name => 'Main', quiet => 1);
    $app->mount('/api' => 'TestApp::API');

    my ($status, $body) = make_request($app, 'GET', '/api/');

    is($status, 200, 'status is 200');
    is($body, 'api index', 'body is correct');
    is(\@TestApp::API::calls, ['index'], 'index handler called');
};

subtest 'chained #method handlers execute in order' => sub {
    @TestApp::API::calls = ();

    my $app = PAGI::Simple->new(name => 'Main', quiet => 1);
    $app->mount('/api' => 'TestApp::API');

    my ($status, $body) = make_request($app, 'GET', '/api/42');

    is($status, 200, 'status is 200');
    like($body, qr/"id"/, 'body contains id field');
    like($body, qr/42/, 'body contains id value');
    is(\@TestApp::API::calls, ['load:42', 'show'], 'handlers called in order');
};

done_testing;
