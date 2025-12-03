use strict;
use warnings;
use experimental 'signatures';
use Test2::V0;
use Future;

# Test: PAGI::Simple request logging with Apache::LogFormat::Compiler

use PAGI::Simple;
use PAGI::Simple::Logger;

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
        client       => ['127.0.0.1', 12345],
        http_version => '1.1',
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

#---------------------------------------------------------------------------
# Logger unit tests
#---------------------------------------------------------------------------

subtest 'Logger - new with defaults' => sub {
    my $logger = PAGI::Simple::Logger->new;
    ok($logger, 'logger created');
};

subtest 'Logger - combined format' => sub {
    my $output = '';
    my $logger = PAGI::Simple::Logger->new(
        format => 'combined',
        output => sub { $output .= $_[0] },
    );

    $logger->log(
        scope => {
            method => 'GET',
            path => '/test',
            query_string => '',
            headers => [['User-Agent', 'TestBot'], ['Referer', 'http://example.com']],
            client => ['192.168.1.1', 8080],
            http_version => '1.1',
        },
        status => 200,
        response_size => 1234,
        duration => 0.005,
        response_headers => [],
    );

    like($output, qr/192\.168\.1\.1/, 'has client IP');
    like($output, qr/GET \/test HTTP\/1\.1/, 'has request line');
    like($output, qr/200/, 'has status');
    like($output, qr/1234/, 'has size');
    like($output, qr/TestBot/, 'has user-agent');
    like($output, qr/http:\/\/example\.com/, 'has referer');
    like($output, qr/0\.005s/, 'has duration');
};

subtest 'Logger - common format' => sub {
    my $output = '';
    my $logger = PAGI::Simple::Logger->new(
        format => 'common',
        output => sub { $output .= $_[0] },
    );

    $logger->log(
        scope => {
            method => 'POST',
            path => '/users',
            query_string => '',
            headers => [],
            client => ['10.0.0.1', 80],
            http_version => '1.1',
        },
        status => 201,
        response_size => 50,
        duration => 0.010,
        response_headers => [],
    );

    like($output, qr/10\.0\.0\.1/, 'has client IP');
    like($output, qr/POST \/users HTTP\/1\.1/, 'has request line');
    like($output, qr/201/, 'has status');
    like($output, qr/50/, 'has size');
    unlike($output, qr/0\.010s/, 'no duration in common format');
};

subtest 'Logger - tiny format' => sub {
    my $output = '';
    my $logger = PAGI::Simple::Logger->new(
        format => 'tiny',
        output => sub { $output .= $_[0] },
    );

    $logger->log(
        scope => {
            method => 'DELETE',
            path => '/item/42',
            query_string => '',
            headers => [],
            client => ['127.0.0.1', 80],
            http_version => '1.1',
        },
        status => 204,
        response_size => 0,
        duration => 0.002,
        response_headers => [],
    );

    like($output, qr/DELETE \/item\/42 204 0\.002s/, 'tiny format');
};

subtest 'Logger - custom format string' => sub {
    my $output = '';
    my $logger = PAGI::Simple::Logger->new(
        format => '%m %U %>s %b',
        output => sub { $output .= $_[0] },
    );

    $logger->log(
        scope => { method => 'PUT', path => '/update', query_string => '', headers => [], client => ['127.0.0.1'], http_version => '1.1' },
        status => 200,
        response_size => 100,
        duration => 0.001,
        response_headers => [],
    );

    like($output, qr/PUT \/update 200 100/, 'custom format');
};

subtest 'Logger - request header format specifier' => sub {
    my $output = '';
    my $logger = PAGI::Simple::Logger->new(
        format => '%{Authorization}i',
        output => sub { $output .= $_[0] },
    );

    $logger->log(
        scope => {
            method => 'GET',
            path => '/',
            query_string => '',
            headers => [['Authorization', 'Bearer token123']],
            client => ['127.0.0.1'],
            http_version => '1.1',
        },
        status => 200,
        response_size => 0,
        duration => 0,
        response_headers => [],
    );

    like($output, qr/Bearer token123/, 'request header extracted');
};

subtest 'Logger - response header format specifier' => sub {
    my $output = '';
    my $logger = PAGI::Simple::Logger->new(
        format => '%{Content-Type}o',
        output => sub { $output .= $_[0] },
    );

    $logger->log(
        scope => { method => 'GET', path => '/', query_string => '', headers => [], client => ['127.0.0.1'], http_version => '1.1' },
        status => 200,
        response_size => 0,
        duration => 0,
        response_headers => [['Content-Type', 'application/json']],
    );

    like($output, qr/application\/json/, 'response header extracted');
};

subtest 'Logger - skip paths' => sub {
    my $output = '';
    my $logger = PAGI::Simple::Logger->new(
        format => 'tiny',
        output => sub { $output .= $_[0] },
        skip => ['/health', '/metrics'],
    );

    # Should be skipped
    $logger->log(
        scope => { method => 'GET', path => '/health', query_string => '', headers => [], client => ['127.0.0.1'], http_version => '1.1' },
        status => 200,
        response_size => 0,
        duration => 0,
        response_headers => [],
    );

    is($output, '', 'health path skipped');

    # Should be logged
    $logger->log(
        scope => { method => 'GET', path => '/api', query_string => '', headers => [], client => ['127.0.0.1'], http_version => '1.1' },
        status => 200,
        response_size => 0,
        duration => 0,
        response_headers => [],
    );

    like($output, qr/\/api/, 'non-skipped path logged');
};

subtest 'Logger - skip_if callback' => sub {
    my $output = '';
    my $logger = PAGI::Simple::Logger->new(
        format => 'tiny',
        output => sub { $output .= $_[0] },
        skip_if => sub ($path, $status) {
            return $status == 204;  # Skip 204 responses
        },
    );

    $logger->log(
        scope => { method => 'DELETE', path => '/item', query_string => '', headers => [], client => ['127.0.0.1'], http_version => '1.1' },
        status => 204,
        response_size => 0,
        duration => 0,
        response_headers => [],
    );

    is($output, '', '204 status skipped');

    $logger->log(
        scope => { method => 'DELETE', path => '/item', query_string => '', headers => [], client => ['127.0.0.1'], http_version => '1.1' },
        status => 200,
        response_size => 10,
        duration => 0,
        response_headers => [],
    );

    like($output, qr/200/, '200 status not skipped');
};

subtest 'Logger - query string in path' => sub {
    my $output = '';
    my $logger = PAGI::Simple::Logger->new(
        format => '%r',
        output => sub { $output .= $_[0] },
    );

    $logger->log(
        scope => {
            method => 'GET',
            path => '/search',
            query_string => 'q=perl&page=1',
            headers => [],
            client => ['127.0.0.1'],
            http_version => '1.1',
        },
        status => 200,
        response_size => 0,
        duration => 0,
        response_headers => [],
    );

    like($output, qr/GET \/search\?q=perl&page=1 HTTP\/1\.1/, 'query string in request line');
};

#---------------------------------------------------------------------------
# App integration tests
#---------------------------------------------------------------------------

subtest 'App - enable_logging basic' => sub {
    my @logs;
    my $app = PAGI::Simple->new;

    $app->enable_logging(
        format => 'tiny',
        output => sub { push @logs, $_[0] },
    );

    $app->get('/' => sub ($c) { $c->text('Hello') });

    simulate_request($app, path => '/');

    is(scalar @logs, 1, 'one log entry');
    like($logs[0], qr/GET \/ 200/, 'log content');
};

subtest 'App - logging captures status' => sub {
    my @logs;
    my $app = PAGI::Simple->new;

    $app->enable_logging(
        format => 'tiny',
        output => sub { push @logs, $_[0] },
    );

    $app->get('/ok' => sub ($c) { $c->text('OK') });
    $app->get('/not-found' => sub ($c) { $c->status(404)->text('Not Found') });
    $app->post('/created' => sub ($c) { $c->status(201)->text('Created') });

    simulate_request($app, path => '/ok');
    simulate_request($app, path => '/not-found');
    simulate_request($app, method => 'POST', path => '/created');

    is(scalar @logs, 3, 'three log entries');
    like($logs[0], qr/GET \/ok 200/, 'first request');
    like($logs[1], qr/GET \/not-found 404/, 'second request');
    like($logs[2], qr/POST \/created 201/, 'third request');
};

subtest 'App - logging measures duration' => sub {
    my @logs;
    my $app = PAGI::Simple->new;

    $app->enable_logging(
        format => '%m %U %Ts',
        output => sub { push @logs, $_[0] },
    );

    $app->get('/slow' => sub ($c) {
        $c->text('Done');
    });

    simulate_request($app, path => '/slow');

    is(scalar @logs, 1, 'one log entry');
    # Duration should be a decimal number followed by 's'
    like($logs[0], qr/\d+\.\d+s/, 'measured duration');
};

subtest 'App - logging with path skip' => sub {
    my @logs;
    my $app = PAGI::Simple->new;

    $app->enable_logging(
        format => 'tiny',
        output => sub { push @logs, $_[0] },
        skip => ['/health'],
    );

    $app->get('/health' => sub ($c) { $c->text('OK') });
    $app->get('/api' => sub ($c) { $c->text('API') });

    simulate_request($app, path => '/health');
    simulate_request($app, path => '/api');

    is(scalar @logs, 1, 'only one log (health skipped)');
    like($logs[0], qr/\/api/, 'logged /api');
};

subtest 'App - enable_logging returns app for chaining' => sub {
    my $app = PAGI::Simple->new;

    my $result = $app
        ->enable_logging(output => sub {})
        ->get('/' => sub ($c) { $c->text('Hi') });

    ok($result->can('get'), 'chaining works');
};

subtest 'App - response size tracking' => sub {
    my @logs;
    my $app = PAGI::Simple->new;

    $app->enable_logging(
        format => '%b',
        output => sub { push @logs, $_[0] },
    );

    $app->get('/small' => sub ($c) { $c->text('Hi') });           # 2 bytes
    $app->get('/larger' => sub ($c) { $c->text('Hello World!') }); # 12 bytes

    simulate_request($app, path => '/small');
    simulate_request($app, path => '/larger');

    is(scalar @logs, 2, 'two log entries');
    like($logs[0], qr/^2/, 'small response size');
    like($logs[1], qr/^12/, 'larger response size');
};

done_testing;
