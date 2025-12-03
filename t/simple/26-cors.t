use strict;
use warnings;
use experimental 'signatures';
use Test2::V0;
use Future;

# Test: PAGI::Simple CORS support

use PAGI::Simple;

# Helper to simulate a PAGI HTTP request
sub simulate_request ($app, %opts) {
    my $method = $opts{method} // 'GET';
    my $path   = $opts{path} // '/';
    my $query  = $opts{query_string} // '';
    my $headers = $opts{headers} // [];

    my @sent;
    my $scope = {
        type         => 'http',
        method       => $method,
        path         => $path,
        query_string => $query,
        headers      => $headers,
    };

    my $receive = sub { Future->done({ type => 'http.request' }) };
    my $send = sub ($event) {
        push @sent, $event;
        return Future->done;
    };

    my $pagi_app = $app->to_app;
    $pagi_app->($scope, $receive, $send)->get;

    return \@sent;
}

# Helper to get a header from response
sub get_header ($sent, $name) {
    my $headers = $sent->[0]{headers} // [];
    $name = lc($name);
    for my $h (@$headers) {
        return $h->[1] if lc($h->[0]) eq $name;
    }
    return undef;
}

#---------------------------------------------------------------------------
# Context cors() method tests
#---------------------------------------------------------------------------

subtest 'Context - cors with defaults' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/api' => sub ($c) {
        $c->cors->json({ status => 'ok' });
    });

    my $sent = simulate_request($app,
        path => '/api',
        headers => [['Origin', 'https://example.com']],
    );

    is(get_header($sent, 'Access-Control-Allow-Origin'), '*', 'default allows all origins');
    is(get_header($sent, 'Vary'), 'Origin', 'has Vary header');
};

subtest 'Context - cors with specific origin' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/api' => sub ($c) {
        $c->cors(origin => 'https://allowed.com')->json({ ok => 1 });
    });

    my $sent = simulate_request($app,
        path => '/api',
        headers => [['Origin', 'https://allowed.com']],
    );

    is(get_header($sent, 'Access-Control-Allow-Origin'), 'https://allowed.com', 'specific origin set');
};

subtest 'Context - cors with credentials' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/api' => sub ($c) {
        $c->cors(origin => '*', credentials => 1)->json({ ok => 1 });
    });

    my $sent = simulate_request($app,
        path => '/api',
        headers => [['Origin', 'https://client.com']],
    );

    # With credentials and wildcard, should echo origin
    is(get_header($sent, 'Access-Control-Allow-Origin'), 'https://client.com', 'echoes origin with credentials');
    is(get_header($sent, 'Access-Control-Allow-Credentials'), 'true', 'credentials header set');
};

subtest 'Context - cors with expose headers' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/api' => sub ($c) {
        $c->cors(expose => [qw(X-Custom X-Another)])
            ->res_header('X-Custom', 'value')
            ->json({ ok => 1 });
    });

    my $sent = simulate_request($app,
        path => '/api',
        headers => [['Origin', 'https://example.com']],
    );

    is(get_header($sent, 'Access-Control-Expose-Headers'), 'X-Custom, X-Another', 'expose headers set');
};

subtest 'Context - cors for OPTIONS preflight' => sub {
    my $app = PAGI::Simple->new;

    $app->any('/api' => sub ($c) {
        $c->cors(
            methods => [qw(GET POST)],
            headers => [qw(Content-Type Authorization)],
            max_age => 3600,
        );
        if ($c->method eq 'OPTIONS') {
            $c->status(204)->text('');
        } else {
            $c->json({ ok => 1 });
        }
    });

    my $sent = simulate_request($app,
        method => 'OPTIONS',
        path => '/api',
        headers => [['Origin', 'https://example.com']],
    );

    is(get_header($sent, 'Access-Control-Allow-Methods'), 'GET, POST', 'allowed methods set');
    is(get_header($sent, 'Access-Control-Allow-Headers'), 'Content-Type, Authorization', 'allowed headers set');
    is(get_header($sent, 'Access-Control-Max-Age'), '3600', 'max-age set');
};

#---------------------------------------------------------------------------
# App use_cors() method tests
#---------------------------------------------------------------------------

subtest 'App - use_cors with defaults' => sub {
    my $app = PAGI::Simple->new;
    $app->use_cors;

    $app->get('/api' => sub ($c) { $c->json({ ok => 1 }) });

    my $sent = simulate_request($app,
        path => '/api',
        headers => [['Origin', 'https://example.com']],
    );

    is(get_header($sent, 'Access-Control-Allow-Origin'), '*', 'allows all origins');
    is(get_header($sent, 'Vary'), 'Origin', 'has Vary header');
};

subtest 'App - use_cors automatic preflight' => sub {
    my $app = PAGI::Simple->new;
    $app->use_cors;

    $app->get('/api' => sub ($c) { $c->json({ ok => 1 }) });

    my $sent = simulate_request($app,
        method => 'OPTIONS',
        path => '/api',
        headers => [['Origin', 'https://example.com']],
    );

    is($sent->[0]{status}, 204, 'preflight returns 204');
    is(get_header($sent, 'Access-Control-Allow-Origin'), '*', 'has allow-origin');
    like(get_header($sent, 'Access-Control-Allow-Methods'), qr/GET/, 'has allow-methods');
    like(get_header($sent, 'Access-Control-Allow-Headers'), qr/Content-Type/, 'has allow-headers');
};

subtest 'App - use_cors with origin whitelist' => sub {
    my $app = PAGI::Simple->new;
    $app->use_cors(
        origins => ['https://allowed.com', 'https://also-allowed.com'],
    );

    $app->get('/api' => sub ($c) { $c->json({ ok => 1 }) });

    # Allowed origin
    my $sent = simulate_request($app,
        path => '/api',
        headers => [['Origin', 'https://allowed.com']],
    );
    is(get_header($sent, 'Access-Control-Allow-Origin'), 'https://allowed.com', 'allowed origin works');

    # Also allowed
    $sent = simulate_request($app,
        path => '/api',
        headers => [['Origin', 'https://also-allowed.com']],
    );
    is(get_header($sent, 'Access-Control-Allow-Origin'), 'https://also-allowed.com', 'second allowed origin works');

    # Disallowed origin - no CORS headers
    $sent = simulate_request($app,
        path => '/api',
        headers => [['Origin', 'https://evil.com']],
    );
    ok(!get_header($sent, 'Access-Control-Allow-Origin'), 'disallowed origin gets no CORS headers');
};

subtest 'App - use_cors with credentials' => sub {
    my $app = PAGI::Simple->new;
    $app->use_cors(credentials => 1);

    $app->get('/api' => sub ($c) { $c->json({ ok => 1 }) });

    my $sent = simulate_request($app,
        path => '/api',
        headers => [['Origin', 'https://example.com']],
    );

    # With credentials + wildcard, should echo origin
    is(get_header($sent, 'Access-Control-Allow-Origin'), 'https://example.com', 'echoes origin with credentials');
    is(get_header($sent, 'Access-Control-Allow-Credentials'), 'true', 'credentials header set');
};

subtest 'App - use_cors with custom methods and headers' => sub {
    my $app = PAGI::Simple->new;
    $app->use_cors(
        methods => [qw(GET POST PUT)],
        headers => [qw(Content-Type X-Custom-Header)],
    );

    $app->get('/api' => sub ($c) { $c->json({ ok => 1 }) });

    my $sent = simulate_request($app,
        method => 'OPTIONS',
        path => '/api',
        headers => [['Origin', 'https://example.com']],
    );

    like(get_header($sent, 'Access-Control-Allow-Methods'), qr/GET, POST, PUT/, 'custom methods');
    like(get_header($sent, 'Access-Control-Allow-Headers'), qr/X-Custom-Header/, 'custom headers');
};

subtest 'App - use_cors with expose headers' => sub {
    my $app = PAGI::Simple->new;
    $app->use_cors(expose => [qw(X-Request-ID X-RateLimit-Remaining)]);

    $app->get('/api' => sub ($c) {
        $c->res_header('X-Request-ID', '12345');
        $c->json({ ok => 1 });
    });

    my $sent = simulate_request($app,
        path => '/api',
        headers => [['Origin', 'https://example.com']],
    );

    is(get_header($sent, 'Access-Control-Expose-Headers'), 'X-Request-ID, X-RateLimit-Remaining', 'expose headers set');
};

subtest 'App - use_cors with max_age' => sub {
    my $app = PAGI::Simple->new;
    $app->use_cors(max_age => 7200);

    $app->get('/api' => sub ($c) { $c->json({ ok => 1 }) });

    my $sent = simulate_request($app,
        method => 'OPTIONS',
        path => '/api',
        headers => [['Origin', 'https://example.com']],
    );

    is(get_header($sent, 'Access-Control-Max-Age'), '7200', 'custom max-age');
};

subtest 'App - use_cors no Origin header' => sub {
    my $app = PAGI::Simple->new;
    $app->use_cors;

    $app->get('/api' => sub ($c) { $c->json({ ok => 1 }) });

    # Request without Origin header (same-origin or non-browser)
    my $sent = simulate_request($app, path => '/api');

    ok(!get_header($sent, 'Access-Control-Allow-Origin'), 'no CORS headers without Origin');
};

subtest 'App - use_cors chaining' => sub {
    my $app = PAGI::Simple->new;

    my $result = $app
        ->use_cors
        ->get('/api' => sub ($c) { $c->json({ ok => 1 }) });

    ok($result->can('get'), 'chaining works');
};

#---------------------------------------------------------------------------
# Edge cases
#---------------------------------------------------------------------------

subtest 'context cors returns $c for chaining' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/api' => sub ($c) {
        my $result = $c->cors(origin => 'https://example.com');
        is($result, $c, 'cors returns $c');
        $c->json({ ok => 1 });
    });

    simulate_request($app, path => '/api', headers => [['Origin', 'https://example.com']]);
    pass('test completed');
};

done_testing;
