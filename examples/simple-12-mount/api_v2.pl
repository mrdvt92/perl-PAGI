#!/usr/bin/env perl

# API v2 Sub-Application
#
# This file defines the API v2 sub-application that gets mounted under /api/v2
# It demonstrates an evolved API with enhanced response format including metadata.

use strict;
use warnings;
use experimental 'signatures';

use PAGI::Simple;

sub get_api_v2 {
    my $app = PAGI::Simple->new(name => 'API v2');

    # Sample data (same as v1, but different response format)
    my @users = (
        { id => 1, name => 'Alice', email => 'alice@example.com', role => 'admin', created_at => '2024-01-15' },
        { id => 2, name => 'Bob', email => 'bob@example.com', role => 'user', created_at => '2024-02-20' },
        { id => 3, name => 'Charlie', email => 'charlie@example.com', role => 'user', created_at => '2024-03-10' },
    );

    # API root
    $app->get('/' => sub ($c) {
        $c->json({
            version => 'v2',
            message => 'Welcome to API v2',
            endpoints => ['/users', '/users/:id', '/info'],
            deprecation_notice => 'v1 will be deprecated in 2025',
        });
    });

    # List users (v2 format - with metadata wrapper)
    $app->get('/users' => sub ($c) {
        $c->json({
            data => \@users,
            meta => {
                total => scalar(@users),
                page  => 1,
                per_page => 20,
            },
            links => {
                self => '/api/v2/users',
                first => '/api/v2/users?page=1',
            },
        });
    });

    # Get single user (v2 format - expanded with related data)
    $app->get('/users/:id' => sub ($c) {
        my $id = $c->path_params->{id};
        my ($user) = grep { $_->{id} == $id } @users;

        if ($user) {
            $c->json({
                data => $user,
                links => {
                    self => "/api/v2/users/$id",
                    posts => "/api/v2/users/$id/posts",
                },
            });
        }
        else {
            $c->status(404)->json({
                error => {
                    code => 'NOT_FOUND',
                    message => 'User not found',
                    details => { id => $id },
                },
            });
        }
    });

    # Create user
    $app->post('/users' => sub ($c) {
        my $body = $c->req->json_body->get;
        my $new_user = {
            id         => scalar(@users) + 1,
            name       => $body->{name} // 'Unknown',
            email      => $body->{email} // '',
            role       => $body->{role} // 'user',
            created_at => '2024-12-03',
        };
        push @users, $new_user;
        $c->status(201)->json({
            data => $new_user,
            links => {
                self => "/api/v2/users/$new_user->{id}",
            },
        });
    });

    # Mount path info endpoint
    $app->get('/info' => sub ($c) {
        $c->json({
            mount_path => $c->mount_path,
            local_path => $c->local_path,
            full_path  => $c->full_path,
            version    => 'v2',
            note       => 'V2 uses enhanced response format with metadata',
        });
    });

    return $app;
}

1;
