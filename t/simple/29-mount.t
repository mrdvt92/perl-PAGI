use strict;
use warnings;
use experimental 'signatures';
use Test2::V0;
use Future;

# Test: Mounting sub-applications in PAGI::Simple

use PAGI::Simple;

# Helper to simulate a PAGI HTTP request
sub simulate_request ($app, %opts) {
    my $method  = $opts{method} // 'GET';
    my $path    = $opts{path} // '/';
    my $body    = $opts{body} // '';
    my $headers = $opts{headers} // [];

    my @sent;
    my $scope = {
        type    => 'http',
        method  => $method,
        path    => $path,
        headers => $headers,
    };

    my $receive = sub { Future->done({ type => 'http.request', body => $body, more => 0 }) };
    my $send = sub ($event) {
        push @sent, $event;
        return Future->done;
    };

    my $pagi_app = $app->to_app;
    $pagi_app->($scope, $receive, $send)->get;

    return \@sent;
}

# Helper to extract response body
sub get_body ($sent) {
    for my $event (@$sent) {
        if ($event->{type} eq 'http.response.body') {
            return $event->{body};
        }
    }
    return '';
}

# Test 1: mount method exists
subtest 'mount method exists' => sub {
    my $app = PAGI::Simple->new;
    ok($app->can('mount'), 'app has mount method');
};

# Test 2: Mount a PAGI::Simple sub-app
subtest 'mount PAGI::Simple app' => sub {
    my $sub_app = PAGI::Simple->new(name => 'API');
    $sub_app->get('/users' => sub ($c) {
        $c->text('users list');
    });

    my $app = PAGI::Simple->new;
    $app->get('/' => sub ($c) {
        $c->text('home');
    });
    $app->mount('/api' => $sub_app);

    # Request to main app
    my $sent = simulate_request($app, path => '/');
    is($sent->[0]{status}, 200, 'main app responds');
    like(get_body($sent), qr/home/, 'main app returns home');

    # Request to mounted app
    $sent = simulate_request($app, path => '/api/users');
    is($sent->[0]{status}, 200, 'mounted app responds');
    like(get_body($sent), qr/users list/, 'mounted app returns users');
};

# Test 3: Mount path rewriting works
subtest 'mount path rewriting' => sub {
    my $received_path;

    my $sub_app = PAGI::Simple->new;
    $sub_app->get('/items/:id' => sub ($c) {
        $received_path = $c->local_path;
        $c->text('item');
    });

    my $app = PAGI::Simple->new;
    $app->mount('/store' => $sub_app);

    my $sent = simulate_request($app, path => '/store/items/123');
    is($sent->[0]{status}, 200, 'mounted route matched');
    is($received_path, '/items/123', 'path rewritten correctly');
};

# Test 4: mount_path accessor
subtest 'mount_path accessor' => sub {
    my $mount_path_value;

    my $sub_app = PAGI::Simple->new;
    $sub_app->get('/' => sub ($c) {
        $mount_path_value = $c->mount_path;
        $c->text('ok');
    });

    my $app = PAGI::Simple->new;
    $app->mount('/api/v1' => $sub_app);

    simulate_request($app, path => '/api/v1');
    is($mount_path_value, '/api/v1', 'mount_path returns correct prefix');
};

# Test 5: local_path accessor
subtest 'local_path accessor' => sub {
    my $local_path_value;

    my $sub_app = PAGI::Simple->new;
    $sub_app->get('/data' => sub ($c) {
        $local_path_value = $c->local_path;
        $c->text('ok');
    });

    my $app = PAGI::Simple->new;
    $app->mount('/api' => $sub_app);

    simulate_request($app, path => '/api/data');
    is($local_path_value, '/data', 'local_path returns path without prefix');
};

# Test 6: full_path accessor
subtest 'full_path accessor' => sub {
    my $full_path_value;

    my $sub_app = PAGI::Simple->new;
    $sub_app->get('/resource' => sub ($c) {
        $full_path_value = $c->full_path;
        $c->text('ok');
    });

    my $app = PAGI::Simple->new;
    $app->mount('/prefix' => $sub_app);

    simulate_request($app, path => '/prefix/resource');
    is($full_path_value, '/prefix/resource', 'full_path returns original path');
};

# Test 7: Mount raw PAGI app (coderef)
subtest 'mount raw PAGI app' => sub {
    my $raw_app = sub ($scope, $receive, $send) {
        return $send->({
            type    => 'http.response.start',
            status  => 200,
            headers => [['content-type', 'text/plain']],
        })->then(sub {
            return $send->({
                type => 'http.response.body',
                body => 'raw pagi response',
            });
        });
    };

    my $app = PAGI::Simple->new;
    $app->mount('/raw' => $raw_app);

    my $sent = simulate_request($app, path => '/raw/anything');
    is($sent->[0]{status}, 200, 'raw PAGI app responds');
    like(get_body($sent), qr/raw pagi/, 'raw app returns expected body');
};

# Test 8: Mounted app 404 handling
subtest 'mounted app 404' => sub {
    my $sub_app = PAGI::Simple->new;
    $sub_app->get('/exists' => sub ($c) {
        $c->text('found');
    });

    my $app = PAGI::Simple->new;
    $app->mount('/sub' => $sub_app);

    # Route that doesn't exist in mounted app
    my $sent = simulate_request($app, path => '/sub/notfound');
    is($sent->[0]{status}, 404, 'mounted app returns 404 for unknown path');
};

# Test 9: Mount with middleware
subtest 'mount with middleware' => sub {
    my $middleware_ran = 0;

    my $sub_app = PAGI::Simple->new;
    $sub_app->get('/protected' => sub ($c) {
        $c->text('secret');
    });

    my $app = PAGI::Simple->new;
    $app->middleware(auth => sub ($c, $next) {
        $middleware_ran = 1;
        return $next->();
    });
    $app->mount('/admin' => $sub_app, [qw(auth)]);

    my $sent = simulate_request($app, path => '/admin/protected');
    ok($middleware_ran, 'middleware was executed');
    is($sent->[0]{status}, 200, 'request succeeded after middleware');
};

# Test 10: Mount at root of prefix
subtest 'mount at exact prefix' => sub {
    my $root_handler_called = 0;

    my $sub_app = PAGI::Simple->new;
    $sub_app->get('/' => sub ($c) {
        $root_handler_called = 1;
        $c->text('api root');
    });

    my $app = PAGI::Simple->new;
    $app->mount('/api' => $sub_app);

    my $sent = simulate_request($app, path => '/api');
    ok($root_handler_called, 'root handler called for exact prefix');
    is($sent->[0]{status}, 200, 'responds 200');
};

# Test 11: Multiple mounted apps
subtest 'multiple mounts' => sub {
    my $api_v1 = PAGI::Simple->new;
    $api_v1->get('/users' => sub ($c) { $c->text('v1 users') });

    my $api_v2 = PAGI::Simple->new;
    $api_v2->get('/users' => sub ($c) { $c->text('v2 users') });

    my $app = PAGI::Simple->new;
    $app->mount('/api/v1' => $api_v1);
    $app->mount('/api/v2' => $api_v2);

    my $sent = simulate_request($app, path => '/api/v1/users');
    like(get_body($sent), qr/v1 users/, 'v1 mount works');

    $sent = simulate_request($app, path => '/api/v2/users');
    like(get_body($sent), qr/v2 users/, 'v2 mount works');
};

# Test 12: Nested mounts
subtest 'nested mounts' => sub {
    my $inner = PAGI::Simple->new;
    $inner->get('/data' => sub ($c) { $c->text('inner data') });

    my $outer = PAGI::Simple->new;
    $outer->mount('/nested' => $inner);

    my $app = PAGI::Simple->new;
    $app->mount('/outer' => $outer);

    my $sent = simulate_request($app, path => '/outer/nested/data');
    is($sent->[0]{status}, 200, 'nested mount responds');
    like(get_body($sent), qr/inner data/, 'nested route returns data');
};

# Test 13: Mount does not affect main app routes
subtest 'mount isolation from main app' => sub {
    my $sub_app = PAGI::Simple->new;
    $sub_app->get('/item' => sub ($c) { $c->text('mounted item') });

    my $app = PAGI::Simple->new;
    $app->get('/item' => sub ($c) { $c->text('main item') });
    $app->mount('/api' => $sub_app);

    # Main app route should work
    my $sent = simulate_request($app, path => '/item');
    like(get_body($sent), qr/main item/, 'main app route works');

    # Mounted app route should work
    $sent = simulate_request($app, path => '/api/item');
    like(get_body($sent), qr/mounted item/, 'mounted app route works');
};

# Test 14: Mount returns app for chaining
subtest 'mount returns app for chaining' => sub {
    my $sub_app = PAGI::Simple->new;

    my $app = PAGI::Simple->new;
    my $result = $app->mount('/api' => $sub_app);

    is($result, $app, 'mount returns app for chaining');
};

# Test 15: Mount handles trailing slash in prefix
subtest 'mount normalizes trailing slash' => sub {
    my $sub_app = PAGI::Simple->new;
    $sub_app->get('/test' => sub ($c) { $c->text('ok') });

    my $app = PAGI::Simple->new;
    $app->mount('/api/' => $sub_app);  # Trailing slash

    my $sent = simulate_request($app, path => '/api/test');
    is($sent->[0]{status}, 200, 'mount with trailing slash works');
};

# Test 16: POST request to mounted app
subtest 'POST to mounted app' => sub {
    my $sub_app = PAGI::Simple->new;
    $sub_app->post('/create' => sub ($c) { $c->status(201)->text('created') });

    my $app = PAGI::Simple->new;
    $app->mount('/api' => $sub_app);

    my $sent = simulate_request($app, method => 'POST', path => '/api/create');
    is($sent->[0]{status}, 201, 'POST to mounted app works');
};

# Test 17: Path params in mounted app
subtest 'path params in mounted app' => sub {
    my $param_value;

    my $sub_app = PAGI::Simple->new;
    $sub_app->get('/users/:id' => sub ($c) {
        $param_value = $c->path_params->{id};
        $c->text("user $param_value");
    });

    my $app = PAGI::Simple->new;
    $app->mount('/api' => $sub_app);

    my $sent = simulate_request($app, path => '/api/users/42');
    is($sent->[0]{status}, 200, 'path param route matched');
    is($param_value, '42', 'path param extracted correctly');
};

# Test 18: Mount prefix without leading slash
subtest 'mount adds leading slash if missing' => sub {
    my $sub_app = PAGI::Simple->new;
    $sub_app->get('/test' => sub ($c) { $c->text('ok') });

    my $app = PAGI::Simple->new;
    $app->mount('api' => $sub_app);  # No leading slash

    my $sent = simulate_request($app, path => '/api/test');
    is($sent->[0]{status}, 200, 'mount without leading slash works');
};

# Test 19: mount_path is empty for non-mounted context
subtest 'mount_path empty for non-mounted' => sub {
    my $mount_path_value;

    my $app = PAGI::Simple->new;
    $app->get('/' => sub ($c) {
        $mount_path_value = $c->mount_path;
        $c->text('ok');
    });

    simulate_request($app, path => '/');
    is($mount_path_value, '', 'mount_path is empty for non-mounted app');
};

# Test 20: Mounted app middleware chain stops request
subtest 'mount middleware can stop request' => sub {
    my $handler_called = 0;

    my $sub_app = PAGI::Simple->new;
    $sub_app->get('/blocked' => sub ($c) {
        $handler_called = 1;
        $c->text('should not reach');
    });

    my $app = PAGI::Simple->new;
    $app->middleware(blocker => sub ($c, $next) {
        $c->status(403)->text('blocked');
        # Don't call $next
    });
    $app->mount('/protected' => $sub_app, [qw(blocker)]);

    my $sent = simulate_request($app, path => '/protected/blocked');
    is($sent->[0]{status}, 403, 'middleware blocked request');
    ok(!$handler_called, 'handler was not called');
};

done_testing;
