use strict;
use warnings;
use experimental 'signatures';
use Test2::V0;
use Future;

# Test: PAGI::Simple cookie handling with Cookie::Baker

use PAGI::Simple;
use PAGI::Simple::CookieUtil;

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

# Helper to extract Set-Cookie headers from response
sub get_set_cookies ($sent) {
    my @cookies;
    for my $header (@{$sent->[0]{headers} // []}) {
        if (lc($header->[0]) eq 'set-cookie') {
            push @cookies, $header->[1];
        }
    }
    return @cookies;
}

#---------------------------------------------------------------------------
# PAGI::Simple::CookieUtil function tests
#---------------------------------------------------------------------------

subtest 'CookieUtil - parse_cookie_header' => sub {
    # Simple cookies
    my $cookies = PAGI::Simple::CookieUtil::parse_cookie_header('foo=bar');
    is($cookies->{foo}, 'bar', 'single cookie parsed');

    # Multiple cookies
    $cookies = PAGI::Simple::CookieUtil::parse_cookie_header('foo=bar; baz=qux');
    is($cookies->{foo}, 'bar', 'first cookie');
    is($cookies->{baz}, 'qux', 'second cookie');

    # Quoted values
    $cookies = PAGI::Simple::CookieUtil::parse_cookie_header('name="John Doe"');
    is($cookies->{name}, 'John Doe', 'quoted value parsed');

    # Empty value
    $cookies = PAGI::Simple::CookieUtil::parse_cookie_header('empty=');
    is($cookies->{empty}, '', 'empty value');

    # Standard semicolon-separated format (browsers don't add extra whitespace)
    $cookies = PAGI::Simple::CookieUtil::parse_cookie_header('foo=bar; baz=qux');
    is($cookies->{foo}, 'bar', 'first of multiple');
    is($cookies->{baz}, 'qux', 'second of multiple');

    # Empty/undefined header
    $cookies = PAGI::Simple::CookieUtil::parse_cookie_header('');
    is(scalar keys %$cookies, 0, 'empty header returns empty hashref');

    $cookies = PAGI::Simple::CookieUtil::parse_cookie_header(undef);
    is(scalar keys %$cookies, 0, 'undef header returns empty hashref');
};

subtest 'CookieUtil - format_set_cookie' => sub {
    # Simple cookie
    my $str = PAGI::Simple::CookieUtil::format_set_cookie('foo', 'bar');
    like($str, qr/^foo=bar/, 'basic cookie format');
    like($str, qr/path=\//i, 'default path is /');

    # With expires (epoch timestamp)
    my $future_time = time() + 3600;
    $str = PAGI::Simple::CookieUtil::format_set_cookie('foo', 'bar', expires => $future_time);
    like($str, qr/expires=/i, 'has expires');
    like($str, qr/GMT/i, 'expires is HTTP date');

    # With max_age
    $str = PAGI::Simple::CookieUtil::format_set_cookie('foo', 'bar', max_age => 3600);
    like($str, qr/max-age=3600/i, 'has max-age');

    # With domain
    $str = PAGI::Simple::CookieUtil::format_set_cookie('foo', 'bar', domain => '.example.com');
    like($str, qr/domain=\.example\.com/i, 'has domain');

    # With custom path
    $str = PAGI::Simple::CookieUtil::format_set_cookie('foo', 'bar', path => '/app');
    like($str, qr/path=\/app/i, 'custom path');

    # With secure
    $str = PAGI::Simple::CookieUtil::format_set_cookie('foo', 'bar', secure => 1);
    like($str, qr/secure/i, 'has secure');

    # With httponly
    $str = PAGI::Simple::CookieUtil::format_set_cookie('foo', 'bar', httponly => 1);
    like($str, qr/httponly/i, 'has httponly');

    # With samesite
    $str = PAGI::Simple::CookieUtil::format_set_cookie('foo', 'bar', samesite => 'Strict');
    like($str, qr/samesite=strict/i, 'has SameSite=Strict');

    $str = PAGI::Simple::CookieUtil::format_set_cookie('foo', 'bar', samesite => 'Lax');
    like($str, qr/samesite=lax/i, 'has SameSite=Lax');

    $str = PAGI::Simple::CookieUtil::format_set_cookie('foo', 'bar', samesite => 'None', secure => 1);
    like($str, qr/samesite=none/i, 'has SameSite=None');
    like($str, qr/secure/i, 'SameSite=None with secure');
};

subtest 'CookieUtil - format_removal_cookie' => sub {
    my $str = PAGI::Simple::CookieUtil::format_removal_cookie('session');
    like($str, qr/^session=/, 'has cookie name');
    like($str, qr/expires=.*1970/i, 'has expired date');
};

#---------------------------------------------------------------------------
# Request cookie reading tests
#---------------------------------------------------------------------------

subtest 'reading single cookie from request' => sub {
    my $app = PAGI::Simple->new;
    my $captured_cookie;

    $app->get('/' => sub ($c) {
        $captured_cookie = $c->req->cookie('session_id');
        $c->text('ok');
    });

    simulate_request($app,
        path    => '/',
        headers => [['Cookie', 'session_id=abc123']],
    );

    is($captured_cookie, 'abc123', 'cookie value read correctly');
};

subtest 'reading multiple cookies from request' => sub {
    my $app = PAGI::Simple->new;
    my $captured_cookies;

    $app->get('/' => sub ($c) {
        $captured_cookies = $c->req->cookies;
        $c->text('ok');
    });

    simulate_request($app,
        path    => '/',
        headers => [['Cookie', 'foo=bar; baz=qux; session=123']],
    );

    is($captured_cookies->{foo}, 'bar', 'first cookie');
    is($captured_cookies->{baz}, 'qux', 'second cookie');
    is($captured_cookies->{session}, '123', 'third cookie');
};

subtest 'missing cookie returns undef' => sub {
    my $app = PAGI::Simple->new;
    my $captured_cookie;
    my $checked = 0;

    $app->get('/' => sub ($c) {
        $captured_cookie = $c->req->cookie('nonexistent');
        $checked = 1;
        $c->text('ok');
    });

    simulate_request($app,
        path    => '/',
        headers => [['Cookie', 'other=value']],
    );

    ok($checked, 'handler ran');
    is($captured_cookie, undef, 'missing cookie is undef');
};

subtest 'no Cookie header - empty cookies' => sub {
    my $app = PAGI::Simple->new;
    my $captured_cookies;

    $app->get('/' => sub ($c) {
        $captured_cookies = $c->req->cookies;
        $c->text('ok');
    });

    simulate_request($app, path => '/');

    is(scalar keys %$captured_cookies, 0, 'no cookies when header missing');
};

#---------------------------------------------------------------------------
# Response cookie setting tests
#---------------------------------------------------------------------------

subtest 'setting simple cookie' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) {
        $c->cookie('theme' => 'dark');
        $c->text('ok');
    });

    my $sent = simulate_request($app, path => '/');
    my @cookies = get_set_cookies($sent);

    is(scalar @cookies, 1, 'one Set-Cookie header');
    like($cookies[0], qr/^theme=dark/, 'cookie name=value');
    like($cookies[0], qr/path=\//i, 'has default path');
};

subtest 'setting cookie with all attributes' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) {
        $c->cookie('session_id' => 'xyz789',
            expires  => time() + 3600,
            path     => '/',
            domain   => '.example.com',
            secure   => 1,
            httponly => 1,
            samesite => 'Strict',
        );
        $c->text('ok');
    });

    my $sent = simulate_request($app, path => '/');
    my @cookies = get_set_cookies($sent);

    is(scalar @cookies, 1, 'one Set-Cookie header');
    like($cookies[0], qr/^session_id=xyz789/, 'name=value');
    like($cookies[0], qr/expires=.*GMT/i, 'has expires');
    like($cookies[0], qr/path=\//i, 'has path');
    like($cookies[0], qr/domain=\.example\.com/i, 'has domain');
    like($cookies[0], qr/secure/i, 'has secure');
    like($cookies[0], qr/httponly/i, 'has httponly');
    like($cookies[0], qr/samesite=strict/i, 'has samesite');
};

subtest 'setting cookie with max_age' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) {
        $c->cookie('remember' => 'yes', max_age => 86400);
        $c->text('ok');
    });

    my $sent = simulate_request($app, path => '/');
    my @cookies = get_set_cookies($sent);

    like($cookies[0], qr/max-age=86400/i, 'has max-age');
};

subtest 'setting multiple cookies' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) {
        $c->cookie('foo' => 'bar')
          ->cookie('baz' => 'qux')
          ->cookie('session' => '123');
        $c->text('ok');
    });

    my $sent = simulate_request($app, path => '/');
    my @cookies = get_set_cookies($sent);

    is(scalar @cookies, 3, 'three Set-Cookie headers');
    like($cookies[0], qr/^foo=bar/, 'first cookie');
    like($cookies[1], qr/^baz=qux/, 'second cookie');
    like($cookies[2], qr/^session=123/, 'third cookie');
};

subtest 'cookie method is chainable' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) {
        $c->cookie('a' => '1')
          ->cookie('b' => '2')
          ->status(201)
          ->json({ ok => 1 });
    });

    my $sent = simulate_request($app, path => '/');
    my @cookies = get_set_cookies($sent);

    is($sent->[0]{status}, 201, 'status set correctly');
    is(scalar @cookies, 2, 'cookies set');
};

#---------------------------------------------------------------------------
# remove_cookie tests
#---------------------------------------------------------------------------

subtest 'remove_cookie sets expired cookie' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/logout' => sub ($c) {
        $c->remove_cookie('session_id');
        $c->text('logged out');
    });

    my $sent = simulate_request($app, path => '/logout');
    my @cookies = get_set_cookies($sent);

    is(scalar @cookies, 1, 'one Set-Cookie header');
    like($cookies[0], qr/^session_id=/, 'cookie name');
    like($cookies[0], qr/expires=.*01.Jan.1970/i, 'expired date');
};

subtest 'remove_cookie with path and domain' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/logout' => sub ($c) {
        $c->remove_cookie('session_id',
            path   => '/app',
            domain => '.example.com',
        );
        $c->text('logged out');
    });

    my $sent = simulate_request($app, path => '/logout');
    my @cookies = get_set_cookies($sent);

    like($cookies[0], qr/path=\/app/i, 'has path');
    like($cookies[0], qr/domain=\.example\.com/i, 'has domain');
    like($cookies[0], qr/expires=.*1970/i, 'expired');
};

subtest 'remove_cookie is chainable' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/logout' => sub ($c) {
        $c->remove_cookie('session')
          ->remove_cookie('remember_me')
          ->text('logged out');
    });

    my $sent = simulate_request($app, path => '/logout');
    my @cookies = get_set_cookies($sent);

    is(scalar @cookies, 2, 'two removal cookies');
};

#---------------------------------------------------------------------------
# Edge cases
#---------------------------------------------------------------------------

subtest 'empty cookie value' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) {
        $c->cookie('empty' => '');
        $c->text('ok');
    });

    my $sent = simulate_request($app, path => '/');
    my @cookies = get_set_cookies($sent);

    like($cookies[0], qr/^empty=;/, 'empty value cookie');
};

subtest 'cookies caching in request' => sub {
    my $app = PAGI::Simple->new;
    my ($first_call, $second_call);

    $app->get('/' => sub ($c) {
        $first_call = $c->req->cookies;
        $second_call = $c->req->cookies;
        $c->text('ok');
    });

    simulate_request($app,
        path    => '/',
        headers => [['Cookie', 'foo=bar']],
    );

    is($first_call, $second_call, 'cookies hashref is cached (same reference)');
};

done_testing;
