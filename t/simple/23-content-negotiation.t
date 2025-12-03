use strict;
use warnings;
use experimental 'signatures';
use Test2::V0;
use Future;

# Test: PAGI::Simple content negotiation

use PAGI::Simple;
use PAGI::Simple::Negotiate;

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

#---------------------------------------------------------------------------
# PAGI::Simple::Negotiate class tests
#---------------------------------------------------------------------------

subtest 'Negotiate - parse_accept basic' => sub {
    my @types = PAGI::Simple::Negotiate->parse_accept('text/html');
    is(scalar @types, 1, 'one type');
    is($types[0][0], 'text/html', 'correct type');
    is($types[0][1], 1, 'default quality is 1');
};

subtest 'Negotiate - parse_accept multiple' => sub {
    my @types = PAGI::Simple::Negotiate->parse_accept(
        'text/html, application/json, text/plain'
    );
    is(scalar @types, 3, 'three types');
    # All have quality 1, so order preserved
    is($types[0][0], 'text/html', 'first type');
    is($types[1][0], 'application/json', 'second type');
    is($types[2][0], 'text/plain', 'third type');
};

subtest 'Negotiate - parse_accept with quality values' => sub {
    my @types = PAGI::Simple::Negotiate->parse_accept(
        'text/html, application/json;q=0.9, text/plain;q=0.5'
    );
    is(scalar @types, 3, 'three types');
    # Sorted by quality
    is($types[0][0], 'text/html', 'html first (q=1)');
    is($types[0][1], 1, 'html quality 1');
    is($types[1][0], 'application/json', 'json second (q=0.9)');
    is($types[1][1], 0.9, 'json quality 0.9');
    is($types[2][0], 'text/plain', 'plain third (q=0.5)');
    is($types[2][1], 0.5, 'plain quality 0.5');
};

subtest 'Negotiate - parse_accept with wildcards' => sub {
    my @types = PAGI::Simple::Negotiate->parse_accept(
        'text/html, text/*, */*;q=0.1'
    );
    is(scalar @types, 3, 'three types');
    # text/html is most specific, then text/*, then */*
    is($types[0][0], 'text/html', 'specific type first');
    is($types[1][0], 'text/*', 'type wildcard second');
    is($types[2][0], '*/*', 'full wildcard last');
};

subtest 'Negotiate - parse_accept empty/undef' => sub {
    my @types = PAGI::Simple::Negotiate->parse_accept('');
    is(scalar @types, 1, 'empty returns */*');
    is($types[0][0], '*/*', 'wildcard');

    @types = PAGI::Simple::Negotiate->parse_accept(undef);
    is(scalar @types, 1, 'undef returns */*');
    is($types[0][0], '*/*', 'wildcard');
};

subtest 'Negotiate - parse_accept with parameters' => sub {
    my @types = PAGI::Simple::Negotiate->parse_accept(
        'text/html; charset=utf-8; q=0.8, application/json'
    );
    is(scalar @types, 2, 'two types');
    is($types[0][0], 'application/json', 'json first (q=1)');
    is($types[1][0], 'text/html', 'html second (q=0.8)');
    is($types[1][1], 0.8, 'html quality extracted correctly');
};

subtest 'Negotiate - type_matches' => sub {
    my $n = 'PAGI::Simple::Negotiate';

    # Exact match
    ok($n->type_matches('text/html', 'text/html'), 'exact match');
    ok(!$n->type_matches('text/html', 'text/plain'), 'exact non-match');

    # Wildcard
    ok($n->type_matches('text/html', '*/*'), 'wildcard matches');
    ok($n->type_matches('application/json', '*/*'), 'wildcard matches any');

    # Type wildcard
    ok($n->type_matches('text/html', 'text/*'), 'type wildcard matches');
    ok($n->type_matches('text/plain', 'text/*'), 'type wildcard matches');
    ok(!$n->type_matches('application/json', 'text/*'), 'type wildcard no match');

    # Case insensitive
    ok($n->type_matches('TEXT/HTML', 'text/html'), 'case insensitive');
};

subtest 'Negotiate - normalize_type' => sub {
    my $n = 'PAGI::Simple::Negotiate';

    is($n->normalize_type('html'), 'text/html', 'html shortcut');
    is($n->normalize_type('json'), 'application/json', 'json shortcut');
    is($n->normalize_type('xml'), 'application/xml', 'xml shortcut');
    is($n->normalize_type('text'), 'text/plain', 'text shortcut');
    is($n->normalize_type('text/html'), 'text/html', 'full type unchanged');

    # Unknown shortcut gets application/ prefix
    is($n->normalize_type('unknown'), 'application/unknown', 'unknown type');
};

subtest 'Negotiate - best_match' => sub {
    my $n = 'PAGI::Simple::Negotiate';

    # Simple match
    my $best = $n->best_match(['json', 'html'], 'application/json');
    is($best, 'json', 'json matched');

    # Quality-based selection
    $best = $n->best_match(['json', 'html'], 'text/html, application/json;q=0.5');
    is($best, 'html', 'html preferred due to quality');

    # Wildcard
    $best = $n->best_match(['json'], '*/*');
    is($best, 'json', 'wildcard matches');

    # No match
    $best = $n->best_match(['json'], 'text/html');
    is($best, undef, 'no match returns undef');

    # Full MIME types
    $best = $n->best_match(
        ['application/json', 'text/html'],
        'text/html;q=0.9, application/json'
    );
    is($best, 'application/json', 'full MIME type match');
};

subtest 'Negotiate - accepts_type' => sub {
    my $n = 'PAGI::Simple::Negotiate';

    ok($n->accepts_type('*/*', 'json'), 'wildcard accepts json');
    ok($n->accepts_type('application/json', 'json'), 'exact match');
    ok($n->accepts_type('application/*', 'json'), 'type wildcard');
    ok(!$n->accepts_type('text/html', 'json'), 'no match');

    # With quality 0 (rejected)
    ok(!$n->accepts_type('application/json;q=0', 'json'), 'q=0 rejects');
};

subtest 'Negotiate - quality_for_type' => sub {
    my $n = 'PAGI::Simple::Negotiate';

    is($n->quality_for_type('application/json', 'json'), 1, 'exact match q=1');
    is($n->quality_for_type('application/json;q=0.5', 'json'), 0.5, 'explicit quality');
    is($n->quality_for_type('*/*;q=0.1', 'json'), 0.1, 'wildcard quality');
    is($n->quality_for_type('text/html', 'json'), 0, 'no match q=0');

    # More specific wins
    is(
        $n->quality_for_type('*/*;q=0.1, application/json;q=0.9', 'json'),
        0.9,
        'specific type quality wins'
    );
};

#---------------------------------------------------------------------------
# Request content negotiation methods
#---------------------------------------------------------------------------

subtest 'Request - accepts()' => sub {
    my $app = PAGI::Simple->new;
    my @captured;

    $app->get('/' => sub ($c) {
        @captured = $c->req->accepts;
        $c->text('ok');
    });

    simulate_request($app,
        path    => '/',
        headers => [['Accept', 'text/html, application/json;q=0.9']],
    );

    is(scalar @captured, 2, 'two types');
    is($captured[0][0], 'text/html', 'html first');
    is($captured[1][0], 'application/json', 'json second');
};

subtest 'Request - accepts_type()' => sub {
    my $app = PAGI::Simple->new;
    my ($accepts_json, $accepts_xml);

    $app->get('/' => sub ($c) {
        $accepts_json = $c->req->accepts_type('json');
        $accepts_xml = $c->req->accepts_type('xml');
        $c->text('ok');
    });

    simulate_request($app,
        path    => '/',
        headers => [['Accept', 'application/json, text/html']],
    );

    ok($accepts_json, 'accepts json');
    ok(!$accepts_xml, 'does not accept xml');
};

subtest 'Request - preferred_type()' => sub {
    my $app = PAGI::Simple->new;
    my $best;

    $app->get('/' => sub ($c) {
        $best = $c->req->preferred_type('html', 'json', 'xml');
        $c->text('ok');
    });

    # JSON preferred
    simulate_request($app,
        path    => '/',
        headers => [['Accept', 'application/json, text/html;q=0.5']],
    );
    is($best, 'json', 'json preferred');

    # HTML preferred
    simulate_request($app,
        path    => '/',
        headers => [['Accept', 'text/html, application/json;q=0.5']],
    );
    is($best, 'html', 'html preferred');

    # None acceptable
    simulate_request($app,
        path    => '/',
        headers => [['Accept', 'image/png']],
    );
    is($best, undef, 'no match');
};

subtest 'Request - no Accept header accepts everything' => sub {
    my $app = PAGI::Simple->new;
    my $best;

    $app->get('/' => sub ($c) {
        $best = $c->req->preferred_type('json', 'html');
        $c->text('ok');
    });

    simulate_request($app, path => '/');  # No Accept header

    ok(defined $best, 'something matched');
};

#---------------------------------------------------------------------------
# Context respond_to() tests
#---------------------------------------------------------------------------

subtest 'respond_to with callbacks' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) {
        $c->respond_to(
            json => sub { $c->json({ format => 'json' }) },
            html => sub { $c->html('<p>html</p>') },
        );
    });

    # Request JSON
    my $sent = simulate_request($app,
        path    => '/',
        headers => [['Accept', 'application/json']],
    );

    like($sent->[1]{body}, qr/"format"/, 'JSON response');

    # Request HTML
    $sent = simulate_request($app,
        path    => '/',
        headers => [['Accept', 'text/html']],
    );

    like($sent->[1]{body}, qr/<p>html<\/p>/, 'HTML response');
};

subtest 'respond_to with hash references' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) {
        $c->respond_to(
            json => { json => { status => 'ok' } },
            html => { html => '<h1>OK</h1>' },
        );
    });

    # Request JSON
    my $sent = simulate_request($app,
        path    => '/',
        headers => [['Accept', 'application/json']],
    );

    like($sent->[1]{body}, qr/"status"/, 'JSON from hash');

    # Request HTML
    $sent = simulate_request($app,
        path    => '/',
        headers => [['Accept', 'text/html']],
    );

    like($sent->[1]{body}, qr/<h1>OK<\/h1>/, 'HTML from hash');
};

subtest 'respond_to with any fallback' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) {
        $c->respond_to(
            json => { json => { format => 'json' } },
            any  => { text => 'fallback' },
        );
    });

    # Request something not supported
    my $sent = simulate_request($app,
        path    => '/',
        headers => [['Accept', 'image/png']],
    );

    is($sent->[0]{status}, 200, 'status 200');
    is($sent->[1]{body}, 'fallback', 'any fallback used');
};

subtest 'respond_to 406 when no match and no any' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) {
        $c->respond_to(
            json => { json => { format => 'json' } },
            html => { html => 'html' },
        );
    });

    # Request something not supported
    my $sent = simulate_request($app,
        path    => '/',
        headers => [['Accept', 'image/png']],
    );

    is($sent->[0]{status}, 406, 'status 406 Not Acceptable');
};

subtest 'respond_to with custom status' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) {
        $c->respond_to(
            json => { json => { created => 1 }, status => 201 },
        );
    });

    my $sent = simulate_request($app,
        path    => '/',
        headers => [['Accept', 'application/json']],
    );

    is($sent->[0]{status}, 201, 'custom status');
};

subtest 'respond_to respects quality values' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) {
        $c->respond_to(
            json => { json => { format => 'json' } },
            html => { html => '<p>html</p>' },
        );
    });

    # Prefer HTML over JSON
    my $sent = simulate_request($app,
        path    => '/',
        headers => [['Accept', 'text/html, application/json;q=0.5']],
    );

    like($sent->[1]{body}, qr/<p>html<\/p>/, 'HTML selected due to quality');

    # Prefer JSON over HTML
    $sent = simulate_request($app,
        path    => '/',
        headers => [['Accept', 'application/json, text/html;q=0.5']],
    );

    like($sent->[1]{body}, qr/"format"/, 'JSON selected due to quality');
};

#---------------------------------------------------------------------------
# Edge cases
#---------------------------------------------------------------------------

subtest 'browser-like Accept header' => sub {
    my $app = PAGI::Simple->new;
    my $best;

    $app->get('/' => sub ($c) {
        $best = $c->req->preferred_type('json', 'html');
        $c->text('ok');
    });

    # Typical browser Accept header
    simulate_request($app,
        path    => '/',
        headers => [[
            'Accept',
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
        ]],
    );

    is($best, 'html', 'HTML preferred from browser Accept');
};

subtest 'curl-like Accept header (*/*)' => sub {
    my $app = PAGI::Simple->new;
    my $best;

    $app->get('/' => sub ($c) {
        $best = $c->req->preferred_type('json', 'html');
        $c->text('ok');
    });

    # curl default Accept
    simulate_request($app,
        path    => '/',
        headers => [['Accept', '*/*']],
    );

    ok(defined $best, 'something matched with */*');
};

done_testing;
