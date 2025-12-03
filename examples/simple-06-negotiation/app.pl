#!/usr/bin/env perl
use strict;
use warnings;
use experimental 'signatures';
use Future::AsyncAwait;

# PAGI::Simple Content Negotiation Example
# Demonstrates automatic content type selection based on Accept headers
# Run with: pagi-server --app examples/simple-06-negotiation/app.pl

use PAGI::Simple;

my $app = PAGI::Simple->new(name => 'Content Negotiation Demo');

# Sample data
my @users = (
    { id => 1, name => 'Alice', email => 'alice@example.com' },
    { id => 2, name => 'Bob', email => 'bob@example.com' },
    { id => 3, name => 'Charlie', email => 'charlie@example.com' },
);

#---------------------------------------------------------------------------
# Home page - explains the demo
#---------------------------------------------------------------------------
$app->get('/' => sub ($c) {
    $c->html(<<'HTML');
<!DOCTYPE html>
<html>
<head>
    <title>Content Negotiation Demo</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 20px auto; padding: 0 20px; }
        code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; }
        pre { background: #f4f4f4; padding: 10px; border-radius: 5px; overflow-x: auto; }
        .endpoint { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        h3 { margin-top: 0; }
    </style>
</head>
<body>
    <h1>Content Negotiation Demo</h1>
    <p>This demo shows how PAGI::Simple automatically selects the response format
       based on the client's <code>Accept</code> header.</p>

    <div class="endpoint">
        <h3>GET /users</h3>
        <p>Returns user list in JSON or HTML format based on Accept header.</p>
        <pre>
# Request JSON (curl default or explicit)
curl http://localhost:8080/users
curl -H "Accept: application/json" http://localhost:8080/users

# Request HTML
curl -H "Accept: text/html" http://localhost:8080/users

# Browser will typically get HTML</pre>
    </div>

    <div class="endpoint">
        <h3>GET /users/:id</h3>
        <p>Returns single user in JSON, HTML, or XML.</p>
        <pre>
curl http://localhost:8080/users/1
curl -H "Accept: text/html" http://localhost:8080/users/1
curl -H "Accept: application/xml" http://localhost:8080/users/1</pre>
    </div>

    <div class="endpoint">
        <h3>GET /status</h3>
        <p>Simple status endpoint with respond_to().</p>
        <pre>
curl http://localhost:8080/status
curl -H "Accept: text/plain" http://localhost:8080/status</pre>
    </div>

    <div class="endpoint">
        <h3>GET /detect</h3>
        <p>Shows what the server detects about your request.</p>
        <pre>
curl http://localhost:8080/detect
# Open in browser to see browser detection</pre>
    </div>

    <p><a href="/users">View Users</a></p>
</body>
</html>
HTML
});

#---------------------------------------------------------------------------
# Users list - JSON or HTML based on Accept
#---------------------------------------------------------------------------
$app->get('/users' => sub ($c) {
    $c->respond_to(
        json => sub {
            $c->json({
                users => \@users,
                count => scalar @users,
            });
        },
        html => sub {
            my $rows = join '', map {
                "<tr><td>$_->{id}</td><td>$_->{name}</td><td>$_->{email}</td></tr>"
            } @users;

            $c->html(<<"HTML");
<!DOCTYPE html>
<html>
<head><title>Users</title>
<style>
    body { font-family: Arial, sans-serif; padding: 20px; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    th { background: #4CAF50; color: white; }
    tr:nth-child(even) { background: #f2f2f2; }
</style>
</head>
<body>
    <h1>Users</h1>
    <table>
        <tr><th>ID</th><th>Name</th><th>Email</th></tr>
        $rows
    </table>
    <p><a href="/">Back to Home</a></p>
</body>
</html>
HTML
        },
        any => sub {
            $c->text("Users: " . join(', ', map { $_->{name} } @users));
        },
    );
});

#---------------------------------------------------------------------------
# Single user - JSON, HTML, or XML
#---------------------------------------------------------------------------
$app->get('/users/:id' => sub ($c) {
    my $id = $c->path_params->{id};
    my ($user) = grep { $_->{id} == $id } @users;

    unless ($user) {
        $c->abort(404, "User $id not found");
    }

    $c->respond_to(
        json => { json => $user },

        html => sub {
            $c->html(<<"HTML");
<!DOCTYPE html>
<html>
<head><title>User: $user->{name}</title>
<style>
    body { font-family: Arial, sans-serif; padding: 20px; }
    .card { border: 1px solid #ddd; padding: 20px; border-radius: 8px; max-width: 300px; }
    .card h2 { margin-top: 0; }
</style>
</head>
<body>
    <div class="card">
        <h2>$user->{name}</h2>
        <p><strong>ID:</strong> $user->{id}</p>
        <p><strong>Email:</strong> $user->{email}</p>
    </div>
    <p><a href="/users">Back to Users</a></p>
</body>
</html>
HTML
        },

        xml => sub {
            $c->content_type('application/xml');
            $c->text(<<"XML");
<?xml version="1.0" encoding="UTF-8"?>
<user>
    <id>$user->{id}</id>
    <name>$user->{name}</name>
    <email>$user->{email}</email>
</user>
XML
        },

        any => { text => "User: $user->{name} <$user->{email}>" },
    );
});

#---------------------------------------------------------------------------
# Status endpoint - simple respond_to with hash refs
#---------------------------------------------------------------------------
$app->get('/status' => sub ($c) {
    $c->respond_to(
        json => { json => { status => 'healthy', timestamp => time() } },
        text => { text => "Status: healthy\n" },
        html => { html => '<html><body><h1>Status: Healthy</h1></body></html>' },
        any  => { text => 'OK' },
    );
});

#---------------------------------------------------------------------------
# Detection endpoint - shows what was detected
#---------------------------------------------------------------------------
$app->get('/detect' => sub ($c) {
    my $accept = $c->req->header('accept') // '';
    my $ua = $c->req->user_agent // '';
    my @accepts = $c->req->accepts;
    my $preferred = $c->req->preferred_type('json', 'html', 'xml', 'text') // 'none';

    # Detect client type
    my $client_type = 'Unknown';
    if ($ua =~ /curl/i) {
        $client_type = 'curl';
    }
    elsif ($ua =~ /Mozilla|Chrome|Safari|Firefox|Edge/i) {
        $client_type = 'Browser';
    }
    elsif ($ua =~ /wget/i) {
        $client_type = 'wget';
    }

    my $accepts_list = join("\n", map {
        sprintf("  - %s (q=%.2f)", $_->[0], $_->[1])
    } @accepts);

    $c->respond_to(
        json => sub {
            $c->json({
                client_type     => $client_type,
                user_agent      => $ua,
                accept_header   => $accept,
                parsed_accepts  => \@accepts,
                preferred_type  => $preferred,
                accepts_json    => $c->req->accepts_type('json') ? 1 : 0,
                accepts_html    => $c->req->accepts_type('html') ? 1 : 0,
            });
        },
        html => sub {
            $c->html(<<"HTML");
<!DOCTYPE html>
<html>
<head><title>Request Detection</title>
<style>
    body { font-family: Arial, sans-serif; padding: 20px; }
    .info { background: #f5f5f5; padding: 15px; border-radius: 5px; margin: 10px 0; }
    code { background: #e0e0e0; padding: 2px 6px; }
</style>
</head>
<body>
    <h1>Request Detection</h1>

    <div class="info">
        <h3>Client Type: $client_type</h3>
        <p><strong>User-Agent:</strong> <code>$ua</code></p>
    </div>

    <div class="info">
        <h3>Accept Header</h3>
        <p><code>$accept</code></p>
    </div>

    <div class="info">
        <h3>Parsed Accepts (sorted by preference)</h3>
        <pre>$accepts_list</pre>
    </div>

    <div class="info">
        <h3>Content Negotiation Results</h3>
        <p><strong>Preferred type from [json, html, xml, text]:</strong> $preferred</p>
        <p><strong>Accepts JSON:</strong> @{[$c->req->accepts_type('json') ? 'Yes' : 'No']}</p>
        <p><strong>Accepts HTML:</strong> @{[$c->req->accepts_type('html') ? 'Yes' : 'No']}</p>
    </div>

    <p><a href="/">Back to Home</a></p>
</body>
</html>
HTML
        },
        any => sub {
            $c->text(<<"TEXT");
Client Detection
================
Client Type: $client_type
User-Agent: $ua
Accept Header: $accept
Preferred Type: $preferred
TEXT
        },
    );
});

#---------------------------------------------------------------------------
# API that only supports JSON - returns 406 for other types
#---------------------------------------------------------------------------
$app->get('/api/data' => sub ($c) {
    # Only JSON supported - no 'any' fallback
    $c->respond_to(
        json => { json => { data => 'secret', version => '1.0' } },
    );
});

#---------------------------------------------------------------------------
# Error handlers
#---------------------------------------------------------------------------
$app->error(404 => sub ($c, $msg = undef) {
    $c->respond_to(
        json => { json => { error => 'Not Found', message => $msg }, status => 404 },
        html => { html => "<html><body><h1>404 Not Found</h1><p>$msg</p></body></html>", status => 404 },
        any  => { text => "Not Found: $msg", status => 404 },
    );
});

$app->error(406 => sub ($c, $msg = undef) {
    $c->status(406)->json({
        error => 'Not Acceptable',
        message => 'The requested format is not supported',
        supported => ['application/json'],
    });
});

# Return the PAGI app
$app->to_app;
