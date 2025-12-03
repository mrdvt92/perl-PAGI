#!/usr/bin/env perl

# API v1 Sub-Application
#
# This file defines the API v1 sub-application that gets mounted under /api/v1
# It demonstrates a simple REST API with the original response format.

use strict;
use warnings;
use experimental 'signatures';

use PAGI::Simple;

sub get_api_v1 {
    my $app = PAGI::Simple->new(name => 'API v1');

    # Sample data
    my @users = (
        { id => 1, name => 'Alice', email => 'alice@example.com' },
        { id => 2, name => 'Bob', email => 'bob@example.com' },
        { id => 3, name => 'Charlie', email => 'charlie@example.com' },
    );

    # API root
    $app->get('/' => sub ($c) {
        $c->json({
            version => 'v1',
            message => 'Welcome to API v1',
            endpoints => ['/users', '/users/:id', '/info'],
        });
    });

    # List users (v1 format - simple array)
    $app->get('/users' => sub ($c) {
        $c->json(\@users);
    });

    # Get single user
    $app->get('/users/:id' => sub ($c) {
        my $id = $c->path_params->{id};
        my ($user) = grep { $_->{id} == $id } @users;

        if ($user) {
            $c->json($user);
        }
        else {
            $c->status(404)->json({ error => 'User not found' });
        }
    });

    # Create user
    $app->post('/users' => sub ($c) {
        my $body = $c->req->json_body->get;
        my $new_user = {
            id    => scalar(@users) + 1,
            name  => $body->{name} // 'Unknown',
            email => $body->{email} // '',
        };
        push @users, $new_user;
        $c->status(201)->json($new_user);
    });

    # Mount path info endpoint
    $app->get('/info' => sub ($c) {
        $c->json({
            mount_path => $c->mount_path,
            local_path => $c->local_path,
            full_path  => $c->full_path,
            note       => 'This shows how path rewriting works',
        });
    });

    return $app;
}

1;
