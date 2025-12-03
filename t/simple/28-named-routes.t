use strict;
use warnings;
use experimental 'signatures';
use Test2::V0;
use Future;

# Test: PAGI::Simple named routes and URL generation

use PAGI::Simple;
use PAGI::Simple::Router;

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
# Router unit tests
#---------------------------------------------------------------------------

subtest 'Router - find_by_name' => sub {
    my $router = PAGI::Simple::Router->new;

    $router->add('GET', '/', sub {}, name => 'home');
    $router->add('GET', '/users', sub {}, name => 'users_list');
    $router->add('GET', '/users/:id', sub {}, name => 'user_show');

    my $home = $router->find_by_name('home');
    ok($home, 'found home route');
    is($home->path, '/', 'correct path');

    my $users = $router->find_by_name('users_list');
    ok($users, 'found users_list route');
    is($users->path, '/users', 'correct path');

    my $user_show = $router->find_by_name('user_show');
    ok($user_show, 'found user_show route');
    is($user_show->path, '/users/:id', 'correct path');

    my $not_found = $router->find_by_name('nonexistent');
    ok(!$not_found, 'returns undef for unknown route');
};

subtest 'Router - url_for static route' => sub {
    my $router = PAGI::Simple::Router->new;
    $router->add('GET', '/', sub {}, name => 'home');
    $router->add('GET', '/about', sub {}, name => 'about');

    is($router->url_for('home'), '/', 'url_for home');
    is($router->url_for('about'), '/about', 'url_for about');
    is($router->url_for('nonexistent'), undef, 'url_for unknown returns undef');
};

subtest 'Router - url_for with path params' => sub {
    my $router = PAGI::Simple::Router->new;
    $router->add('GET', '/users/:id', sub {}, name => 'user_show');
    $router->add('GET', '/posts/:year/:month/:slug', sub {}, name => 'post_show');

    is($router->url_for('user_show', id => 42), '/users/42', 'single param');
    is($router->url_for('user_show', id => 'abc'), '/users/abc', 'string param');

    is(
        $router->url_for('post_show', year => 2025, month => 12, slug => 'hello-world'),
        '/posts/2025/12/hello-world',
        'multiple params'
    );

    # Missing required param
    is($router->url_for('user_show'), undef, 'missing required param returns undef');
};

subtest 'Router - url_for with query params' => sub {
    my $router = PAGI::Simple::Router->new;
    $router->add('GET', '/search', sub {}, name => 'search');
    $router->add('GET', '/users/:id', sub {}, name => 'user_show');

    # Extra params become query string
    my $url = $router->url_for('search', q => 'perl', page => 1);
    like($url, qr/^\/search\?/, 'has query string');
    like($url, qr/page=1/, 'has page param');
    like($url, qr/q=perl/, 'has q param');

    # Using query hashref
    $url = $router->url_for('search', query => { q => 'hello', limit => 10 });
    like($url, qr/^\/search\?/, 'has query string');
    like($url, qr/limit=10/, 'has limit param');
    like($url, qr/q=hello/, 'has q param');

    # Path params + query params
    $url = $router->url_for('user_show', id => 42, format => 'json');
    like($url, qr/^\/users\/42\?/, 'path param substituted');
    like($url, qr/format=json/, 'extra param in query');
};

subtest 'Router - url_for with URL encoding' => sub {
    my $router = PAGI::Simple::Router->new;
    $router->add('GET', '/users/:name', sub {}, name => 'user_by_name');
    $router->add('GET', '/search', sub {}, name => 'search');

    # Special characters in path param
    my $url = $router->url_for('user_by_name', name => 'john doe');
    like($url, qr/john%20doe/, 'space encoded');

    # Special characters in query param
    $url = $router->url_for('search', q => 'hello world');
    like($url, qr/q=hello%20world/, 'query value encoded');

    $url = $router->url_for('search', q => 'a&b=c');
    like($url, qr/q=a%26b%3Dc/, 'special chars encoded');
};

subtest 'Router - named_routes' => sub {
    my $router = PAGI::Simple::Router->new;
    $router->add('GET', '/', sub {}, name => 'home');
    $router->add('GET', '/users', sub {}, name => 'users');

    my @names = sort $router->named_routes;
    is(\@names, ['home', 'users'], 'lists all named routes');
};

subtest 'Router - register_name after creation' => sub {
    my $router = PAGI::Simple::Router->new;
    my $route = $router->add('GET', '/late', sub {});

    ok(!$router->find_by_name('late_route'), 'not named yet');

    $router->register_name('late_route', $route);

    my $found = $router->find_by_name('late_route');
    ok($found, 'found after registration');
    is($found->path, '/late', 'correct route');
};

#---------------------------------------------------------------------------
# App DSL tests
#---------------------------------------------------------------------------

subtest 'App - chained name()' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub ($c) { $c->text('home') })->name('home');
    $app->get('/users/:id' => sub ($c) { $c->text('user') })->name('user_show');

    is($app->url_for('home'), '/', 'url_for from app');
    is($app->url_for('user_show', id => 42), '/users/42', 'url_for with params');
};

subtest 'App - chained routes after name()' => sub {
    my $app = PAGI::Simple->new;

    # Chaining should continue to work
    $app->get('/' => sub ($c) { $c->text('home') })->name('home')
        ->get('/about' => sub ($c) { $c->text('about') })->name('about')
        ->get('/contact' => sub ($c) { $c->text('contact') });

    is($app->url_for('home'), '/', 'first route named');
    is($app->url_for('about'), '/about', 'second route named');

    # Unnamed routes still work
    my $sent = simulate_request($app, path => '/contact');
    is($sent->[1]{body}, 'contact', 'unnamed route works');
};

subtest 'App - named_routes' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub {})->name('home');
    $app->get('/users' => sub {})->name('users');
    $app->get('/about' => sub {});  # unnamed

    my @names = sort $app->named_routes;
    is(\@names, ['home', 'users'], 'only named routes listed');
};

#---------------------------------------------------------------------------
# Context helper tests
#---------------------------------------------------------------------------

subtest 'Context - url_for' => sub {
    my $app = PAGI::Simple->new;
    my $generated_url;

    $app->get('/' => sub {})->name('home');
    $app->get('/users/:id' => sub {})->name('user_show');

    $app->get('/test' => sub ($c) {
        $generated_url = $c->url_for('user_show', id => 123);
        $c->text('ok');
    });

    simulate_request($app, path => '/test');

    is($generated_url, '/users/123', 'url_for from context');
};

subtest 'Context - redirect_to' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub {})->name('home');
    $app->get('/users/:id' => sub {})->name('user_show');

    $app->get('/go-home' => sub ($c) {
        $c->redirect_to('home');
    });

    $app->get('/go-user' => sub ($c) {
        $c->redirect_to('user_show', id => 42);
    });

    # Test redirect to home
    my $sent = simulate_request($app, path => '/go-home');
    is($sent->[0]{status}, 302, 'redirect status');
    my @loc = grep { $_->[0] eq 'location' } @{$sent->[0]{headers}};
    is($loc[0][1], '/', 'redirected to home');

    # Test redirect to user
    $sent = simulate_request($app, path => '/go-user');
    is($sent->[0]{status}, 302, 'redirect status');
    @loc = grep { $_->[0] eq 'location' } @{$sent->[0]{headers}};
    is($loc[0][1], '/users/42', 'redirected to user with param');
};

subtest 'Context - redirect_to with custom status' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/' => sub {})->name('home');

    $app->get('/permanent' => sub ($c) {
        $c->redirect_to('home', status => 301);
    });

    my $sent = simulate_request($app, path => '/permanent');
    is($sent->[0]{status}, 301, 'custom status 301');
};

subtest 'Context - redirect_to with query params' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/search' => sub {})->name('search');

    $app->get('/go-search' => sub ($c) {
        $c->redirect_to('search', q => 'perl', page => 1);
    });

    my $sent = simulate_request($app, path => '/go-search');
    my @loc = grep { $_->[0] eq 'location' } @{$sent->[0]{headers}};
    like($loc[0][1], qr/^\/search\?/, 'redirected with query');
    like($loc[0][1], qr/q=perl/, 'has q param');
    like($loc[0][1], qr/page=1/, 'has page param');
};

#---------------------------------------------------------------------------
# Edge cases
#---------------------------------------------------------------------------

subtest 'routes in groups maintain names' => sub {
    my $app = PAGI::Simple->new;

    $app->group('/api' => sub ($app) {
        $app->get('/users' => sub {})->name('api_users');
        $app->get('/users/:id' => sub {})->name('api_user');
    });

    is($app->url_for('api_users'), '/api/users', 'group prefix applied');
    is($app->url_for('api_user', id => 5), '/api/users/5', 'group prefix with param');
};

subtest 'url_for with array query param' => sub {
    my $router = PAGI::Simple::Router->new;
    $router->add('GET', '/filter', sub {}, name => 'filter');

    my $url = $router->url_for('filter', query => { tags => ['perl', 'web'] });
    like($url, qr/tags=perl/, 'first array value');
    like($url, qr/tags=web/, 'second array value');
};

subtest 'wildcard route url_for' => sub {
    my $router = PAGI::Simple::Router->new;
    $router->add('GET', '/files/*path', sub {}, name => 'file');

    my $url = $router->url_for('file', path => 'docs/readme.txt');
    is($url, '/files/docs/readme.txt', 'wildcard substitution');

    # Empty wildcard
    $url = $router->url_for('file');
    is($url, '/files/', 'empty wildcard');
};

done_testing;
