#!/usr/bin/env perl
use strict;
use warnings;
use experimental 'signatures';
use Future::AsyncAwait;

# PAGI::Simple Cookies Example
# Demonstrates cookie handling: preferences, login, flash messages
# Run with: pagi-server --app examples/simple-08-cookies/app.pl

use PAGI::Simple;

my $app = PAGI::Simple->new(name => 'Cookie Demo');

# Simulated user database
my %users = (
    'demo' => { password => 'secret', name => 'Demo User' },
);

#---------------------------------------------------------------------------
# Helper: Get current theme from cookie (default: light)
#---------------------------------------------------------------------------
sub get_theme ($c) {
    return $c->req->cookie('theme') // 'light';
}

#---------------------------------------------------------------------------
# Helper: Get flash message and clear it
#---------------------------------------------------------------------------
sub get_flash ($c) {
    my $message = $c->req->cookie('flash');
    if ($message) {
        # Clear the flash cookie
        $c->remove_cookie('flash', path => '/');
    }
    return $message;
}

#---------------------------------------------------------------------------
# Helper: Check if user is logged in
#---------------------------------------------------------------------------
sub get_user ($c) {
    return $c->req->cookie('user');
}

#---------------------------------------------------------------------------
# Home page - shows current state
#---------------------------------------------------------------------------
$app->get('/' => sub ($c) {
    my $theme = get_theme($c);
    my $user = get_user($c);
    my $flash = get_flash($c);

    my $bg = $theme eq 'dark' ? '#1a1a2e' : '#ffffff';
    my $fg = $theme eq 'dark' ? '#eaeaea' : '#333333';
    my $link = $theme eq 'dark' ? '#00d9ff' : '#0066cc';

    my $user_section = $user
        ? qq{<p>Welcome, <strong>$user</strong>! <a href="/logout">Logout</a></p>}
        : qq{<p>Not logged in. <a href="/login">Login</a></p>};

    my $flash_html = $flash
        ? qq{<div style="background:#4caf50;color:white;padding:10px;margin:10px 0;border-radius:4px">$flash</div>}
        : '';

    my $remember_checked = $c->req->cookie('remember_me') ? 'checked' : '';

    $c->html(<<"HTML");
<!DOCTYPE html>
<html>
<head>
    <title>Cookie Demo</title>
    <style>
        body { font-family: Arial, sans-serif; padding: 20px; background: $bg; color: $fg; }
        a { color: $link; }
        .section { border: 1px solid #ccc; padding: 15px; margin: 15px 0; border-radius: 8px; }
        button, input[type=submit] { padding: 8px 16px; cursor: pointer; }
        h2 { margin-top: 0; }
    </style>
</head>
<body>
    <h1>PAGI::Simple Cookie Demo</h1>

    $flash_html
    $user_section

    <div class="section">
        <h2>Theme Preference</h2>
        <p>Current theme: <strong>$theme</strong></p>
        <form method="POST" action="/preferences" style="display:inline">
            <input type="hidden" name="theme" value="light">
            <button type="submit">Light Theme</button>
        </form>
        <form method="POST" action="/preferences" style="display:inline">
            <input type="hidden" name="theme" value="dark">
            <button type="submit">Dark Theme</button>
        </form>
    </div>

    <div class="section">
        <h2>Language Preference</h2>
        <p>Current language: <strong>@{[ $c->req->cookie('lang') // 'en' ]}</strong></p>
        <form method="POST" action="/preferences">
            <select name="lang">
                <option value="en">English</option>
                <option value="es">Español</option>
                <option value="fr">Français</option>
                <option value="de">Deutsch</option>
            </select>
            <button type="submit">Save</button>
        </form>
    </div>

    <div class="section">
        <h2>All Cookies</h2>
        <p><a href="/cookies">View all cookies as JSON</a></p>
    </div>

    <div class="section">
        <h2>API Examples</h2>
        <ul>
            <li><code>GET /cookies</code> - View all request cookies</li>
            <li><code>POST /preferences</code> - Set theme/lang cookies</li>
            <li><code>POST /login</code> - Login (sets session cookie)</li>
            <li><code>GET /logout</code> - Logout (removes session cookie)</li>
            <li><code>GET /secure-data</code> - Protected endpoint (requires login)</li>
        </ul>
    </div>
</body>
</html>
HTML
});

#---------------------------------------------------------------------------
# View all cookies as JSON
#---------------------------------------------------------------------------
$app->get('/cookies' => sub ($c) {
    $c->json({
        cookies => $c->req->cookies,
    });
});

#---------------------------------------------------------------------------
# Set preferences (theme, language)
#---------------------------------------------------------------------------
$app->post('/preferences' => async sub ($c) {
    my $theme = await $c->param('theme');
    my $lang = await $c->param('lang');

    if ($theme) {
        $c->cookie('theme' => $theme,
            expires  => time() + 30*24*60*60,  # 30 days
            path     => '/',
            samesite => 'Lax',
        );
    }

    if ($lang) {
        $c->cookie('lang' => $lang,
            expires  => time() + 365*24*60*60,  # 1 year
            path     => '/',
            samesite => 'Lax',
        );
    }

    # Set flash message
    $c->cookie('flash' => 'Preferences saved!',
        path     => '/',
        samesite => 'Lax',
    );

    $c->redirect('/');
});

#---------------------------------------------------------------------------
# Login page
#---------------------------------------------------------------------------
$app->get('/login' => sub ($c) {
    my $theme = get_theme($c);
    my $bg = $theme eq 'dark' ? '#1a1a2e' : '#ffffff';
    my $fg = $theme eq 'dark' ? '#eaeaea' : '#333333';

    my $error = $c->req->query_param('error');
    my $error_html = $error
        ? qq{<div style="background:#f44336;color:white;padding:10px;margin:10px 0;border-radius:4px">$error</div>}
        : '';

    $c->html(<<"HTML");
<!DOCTYPE html>
<html>
<head>
    <title>Login - Cookie Demo</title>
    <style>
        body { font-family: Arial, sans-serif; padding: 20px; background: $bg; color: $fg; }
        .login-box { max-width: 300px; margin: 50px auto; padding: 20px; border: 1px solid #ccc; border-radius: 8px; }
        input { width: 100%; padding: 8px; margin: 5px 0 15px 0; box-sizing: border-box; }
        button { width: 100%; padding: 10px; background: #4caf50; color: white; border: none; cursor: pointer; }
        button:hover { background: #45a049; }
    </style>
</head>
<body>
    <div class="login-box">
        <h2>Login</h2>
        $error_html
        <form method="POST" action="/login">
            <label>Username:
                <input type="text" name="username" value="demo" required>
            </label>
            <label>Password:
                <input type="password" name="password" value="secret" required>
            </label>
            <label>
                <input type="checkbox" name="remember" value="1"> Remember me
            </label>
            <button type="submit">Login</button>
        </form>
        <p style="margin-top:15px"><a href="/">Back to home</a></p>
        <p><small>Hint: username=demo, password=secret</small></p>
    </div>
</body>
</html>
HTML
});

#---------------------------------------------------------------------------
# Handle login POST
#---------------------------------------------------------------------------
$app->post('/login' => async sub ($c) {
    my $username = await $c->param('username');
    my $password = await $c->param('password');
    my $remember = await $c->param('remember');

    # Validate credentials
    my $user = $users{$username};
    unless ($user && $user->{password} eq $password) {
        $c->redirect('/login?error=Invalid+username+or+password');
        return;
    }

    # Set session cookie
    my %cookie_opts = (
        path     => '/',
        httponly => 1,
        samesite => 'Lax',
    );

    # If "remember me" is checked, set longer expiration
    if ($remember) {
        $cookie_opts{expires} = time() + 30*24*60*60;  # 30 days
        $c->cookie('remember_me' => '1',
            expires  => time() + 30*24*60*60,  # 30 days
            path     => '/',
            samesite => 'Lax',
        );
    }

    $c->cookie('user' => $user->{name}, %cookie_opts);

    # Flash message
    $c->cookie('flash' => "Welcome back, $user->{name}!",
        path     => '/',
        samesite => 'Lax',
    );

    $c->redirect('/');
});

#---------------------------------------------------------------------------
# Logout
#---------------------------------------------------------------------------
$app->get('/logout' => sub ($c) {
    $c->remove_cookie('user', path => '/')
      ->remove_cookie('remember_me', path => '/')
      ->cookie('flash' => 'You have been logged out.',
          path     => '/',
          samesite => 'Lax',
      )
      ->redirect('/');
});

#---------------------------------------------------------------------------
# Protected endpoint - requires login
#---------------------------------------------------------------------------
$app->get('/secure-data' => sub ($c) {
    my $user = get_user($c);

    unless ($user) {
        $c->abort(401, 'Please log in to access this resource');
    }

    $c->json({
        message => "Hello, $user! This is protected data.",
        secret => 'The answer is 42.',
        timestamp => time(),
    });
});

#---------------------------------------------------------------------------
# API: Set a custom cookie
#---------------------------------------------------------------------------
$app->post('/api/cookie' => async sub ($c) {
    my $body = await $c->req->json_body;

    unless ($body->{name} && defined $body->{value}) {
        $c->abort(400, 'name and value required');
    }

    $c->cookie($body->{name} => $body->{value},
        expires  => $body->{expires} // (time() + 3600),  # 1 hour default
        path     => $body->{path} // '/',
        secure   => $body->{secure} // 0,
        httponly => $body->{httponly} // 0,
        samesite => $body->{samesite} // 'Lax',
    );

    $c->json({
        success => 1,
        message => "Cookie '$body->{name}' set",
    });
});

#---------------------------------------------------------------------------
# API: Delete a cookie
#---------------------------------------------------------------------------
$app->delete('/api/cookie/:name' => sub ($c) {
    my $name = $c->path_params->{name};
    $c->remove_cookie($name, path => '/');
    $c->json({
        success => 1,
        message => "Cookie '$name' removed",
    });
});

#---------------------------------------------------------------------------
# Error handlers
#---------------------------------------------------------------------------
$app->error(401 => sub ($c, $msg = undef) {
    $c->status(401)->json({
        error => 'Unauthorized',
        message => $msg // 'Authentication required',
    });
});

$app->error(400 => sub ($c, $msg = undef) {
    $c->status(400)->json({
        error => 'Bad Request',
        message => $msg,
    });
});

# Return the PAGI app
$app->to_app;
