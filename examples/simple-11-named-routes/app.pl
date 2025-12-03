#!/usr/bin/env perl

# Named Routes Example
#
# This example demonstrates named routes and URL generation:
# - Naming routes with ->name()
# - Generating URLs with $app->url_for() and $c->url_for()
# - Redirecting to named routes with $c->redirect_to()
# - URL generation with path and query parameters
#
# Run with:
#   pagi-server --port 3000 app.pl
#
# Then visit:
#   http://localhost:3000/

use strict;
use warnings;
use experimental 'signatures';

use PAGI::Simple;

my $app = PAGI::Simple->new;

# --- Named Routes ---

# Home page - named 'home'
$app->get('/' => sub ($c) {
    my $html = <<'HTML';
<!DOCTYPE html>
<html>
<head>
    <title>Named Routes Demo</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 50px auto; }
        h1 { color: #333; }
        .section { margin: 20px 0; padding: 15px; background: #f5f5f5; border-radius: 5px; }
        a { color: #0066cc; }
        code { background: #eee; padding: 2px 6px; border-radius: 3px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { text-align: left; padding: 8px; border-bottom: 1px solid #ddd; }
    </style>
</head>
<body>
    <h1>Named Routes Demo</h1>

    <div class="section">
        <h2>Route Registry</h2>
        <table>
            <tr><th>Route Name</th><th>Generated URL</th></tr>
            <tr><td>home</td><td><a href="/">/</a></td></tr>
            <tr><td>about</td><td><a href="/about">/about</a></td></tr>
            <tr><td>users_list</td><td><a href="/users">/users</a></td></tr>
            <tr><td>user_show</td><td><a href="/users/42">/users/42</a> (id=42)</td></tr>
            <tr><td>user_edit</td><td><a href="/users/42/edit">/users/42/edit</a> (id=42)</td></tr>
            <tr><td>search</td><td><a href="/search?q=perl&amp;page=1">/search?q=perl&page=1</a></td></tr>
            <tr><td>post_show</td><td><a href="/blog/2025/12/hello-world">/blog/2025/12/hello-world</a></td></tr>
        </table>
    </div>

    <div class="section">
        <h2>Redirect Examples</h2>
        <ul>
            <li><a href="/go-home">Redirect to home</a> - uses <code>$c->redirect_to('home')</code></li>
            <li><a href="/go-user/123">Redirect to user 123</a> - uses <code>$c->redirect_to('user_show', id => 123)</code></li>
            <li><a href="/go-search">Redirect to search</a> - with query params</li>
            <li><a href="/moved">Permanent redirect (301)</a> - uses <code>status => 301</code></li>
        </ul>
    </div>

    <div class="section">
        <h2>API Routes</h2>
        <ul>
            <li><a href="/api/users">/api/users</a> - returns URLs as JSON</li>
        </ul>
    </div>
</body>
</html>
HTML
    $c->html($html);
})->name('home');

# About page
$app->get('/about' => sub ($c) {
    $c->html('<h1>About</h1><p>This is the about page.</p><p><a href="/">Back to home</a></p>');
})->name('about');

# User routes
$app->get('/users' => sub ($c) {
    my @users = (
        { id => 1, name => 'Alice' },
        { id => 2, name => 'Bob' },
        { id => 3, name => 'Charlie' },
    );

    my $html = '<h1>Users</h1><ul>';
    for my $user (@users) {
        # Use url_for from context to generate user URLs
        my $url = $c->url_for('user_show', id => $user->{id});
        $html .= qq{<li><a href="$url">$user->{name}</a></li>};
    }
    $html .= '</ul><p><a href="/">Back to home</a></p>';

    $c->html($html);
})->name('users_list');

$app->get('/users/:id' => sub ($c) {
    my $id = $c->path_params->{id};

    # Generate related URLs
    my $edit_url = $c->url_for('user_edit', id => $id);
    my $list_url = $c->url_for('users_list');

    $c->html(qq{
        <h1>User #$id</h1>
        <p><a href="$edit_url">Edit this user</a></p>
        <p><a href="$list_url">Back to users</a></p>
        <p><a href="/">Back to home</a></p>
    });
})->name('user_show');

$app->get('/users/:id/edit' => sub ($c) {
    my $id = $c->path_params->{id};
    my $show_url = $c->url_for('user_show', id => $id);

    $c->html(qq{
        <h1>Edit User #$id</h1>
        <p>Edit form would go here...</p>
        <p><a href="$show_url">Cancel</a></p>
    });
})->name('user_edit');

# Search with query params
$app->get('/search' => sub ($c) {
    my $q = $c->req->query_param('q') // '';
    my $page = $c->req->query_param('page') // 1;

    my $next_url = $c->url_for('search', q => $q, page => $page + 1);
    my $prev_url = $page > 1 ? $c->url_for('search', q => $q, page => $page - 1) : undef;

    my $html = qq{
        <h1>Search Results</h1>
        <p>Query: <strong>$q</strong> (Page $page)</p>
        <p>Pagination:
    };
    $html .= qq{<a href="$prev_url">Previous</a> | } if $prev_url;
    $html .= qq{<a href="$next_url">Next</a></p>};
    $html .= '<p><a href="/">Back to home</a></p>';

    $c->html($html);
})->name('search');

# Blog post with multiple params
$app->get('/blog/:year/:month/:slug' => sub ($c) {
    my $p = $c->path_params;

    $c->html(qq{
        <h1>Blog Post</h1>
        <p>Year: $p->{year}, Month: $p->{month}</p>
        <p>Slug: $p->{slug}</p>
        <p><a href="/">Back to home</a></p>
    });
})->name('post_show');

# --- Redirect Examples ---

$app->get('/go-home' => sub ($c) {
    $c->redirect_to('home');
});

$app->get('/go-user/:id' => sub ($c) {
    my $id = $c->path_params->{id};
    $c->redirect_to('user_show', id => $id);
});

$app->get('/go-search' => sub ($c) {
    $c->redirect_to('search', q => 'perl web', page => 1);
});

$app->get('/moved' => sub ($c) {
    $c->redirect_to('about', status => 301);
});

# --- API Example ---

$app->group('/api' => sub ($app) {
    $app->get('/users' => sub ($c) {
        # Demonstrate URL generation in API responses
        $c->json({
            routes => {
                home      => $c->url_for('home'),
                users     => $c->url_for('users_list'),
                user_42   => $c->url_for('user_show', id => 42),
                search    => $c->url_for('search', q => 'example', page => 1),
                post      => $c->url_for('post_show',
                    year  => 2025,
                    month => 12,
                    slug  => 'named-routes'
                ),
            },
            all_named_routes => [$app->named_routes],
        });
    })->name('api_users');
});

$app->to_app;
