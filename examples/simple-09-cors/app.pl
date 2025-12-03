#!/usr/bin/env perl

# CORS (Cross-Origin Resource Sharing) Example
#
# This example demonstrates CORS support for APIs:
# - Global CORS with use_cors()
# - Manual CORS with $c->cors()
# - Origin whitelisting
# - Credentials support
# - Preflight OPTIONS handling
#
# Run with:
#   pagi-server --port 3000 app.pl
#
# Test with:
#   curl -H "Origin: https://example.com" http://localhost:3000/api/data

use strict;
use warnings;
use experimental 'signatures';

use PAGI::Simple;

my $app = PAGI::Simple->new;

# Enable CORS globally for the app
# This automatically:
# - Handles OPTIONS preflight requests
# - Adds CORS headers to all responses
# - Validates origins if a whitelist is provided
$app->use_cors(
    # Allow these origins (use ['*'] for any origin)
    origins => ['*'],

    # Allowed HTTP methods
    methods => [qw(GET POST PUT DELETE PATCH)],

    # Allowed request headers
    headers => [qw(Content-Type Authorization X-Request-ID)],

    # Response headers to expose to JavaScript
    expose => [qw(X-Request-ID X-RateLimit-Remaining)],

    # Allow credentials (cookies, auth headers)
    credentials => 0,  # Set to 1 if you need cookies

    # Preflight cache time (seconds)
    max_age => 86400,
);

# --- Demo page ---

$app->get('/' => sub ($c) {
    my $html = <<'HTML';
<!DOCTYPE html>
<html>
<head>
    <title>CORS Demo</title>
    <style>
        body { font-family: sans-serif; max-width: 900px; margin: 50px auto; padding: 0 20px; }
        h1 { color: #333; }
        .section { margin: 20px 0; padding: 15px; background: #f5f5f5; border-radius: 5px; }
        pre { background: #222; color: #0f0; padding: 15px; border-radius: 5px; overflow-x: auto; }
        code { background: #eee; padding: 2px 6px; border-radius: 3px; }
        button { padding: 10px 20px; margin: 5px; cursor: pointer; }
        #result { margin-top: 15px; padding: 10px; border: 1px solid #ccc; min-height: 50px; }
    </style>
</head>
<body>
    <h1>CORS Demo</h1>

    <div class="section">
        <h2>Test CORS with JavaScript</h2>
        <p>Click the buttons to make cross-origin requests:</p>
        <button onclick="testGET()">GET /api/data</button>
        <button onclick="testPOST()">POST /api/data</button>
        <button onclick="testPUT()">PUT /api/data/1</button>
        <button onclick="testDELETE()">DELETE /api/data/1</button>
        <div id="result">Results will appear here...</div>
    </div>

    <div class="section">
        <h2>Test with curl</h2>
        <pre># Simple GET request
curl -H "Origin: https://example.com" http://localhost:3000/api/data

# Check preflight
curl -X OPTIONS \
  -H "Origin: https://example.com" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: Content-Type" \
  -i http://localhost:3000/api/data

# POST with JSON
curl -X POST \
  -H "Origin: https://example.com" \
  -H "Content-Type: application/json" \
  -d '{"name":"test"}' \
  http://localhost:3000/api/data</pre>
    </div>

    <div class="section">
        <h2>Expected CORS Headers</h2>
        <table border="1" cellpadding="5">
            <tr><th>Header</th><th>Value</th><th>Purpose</th></tr>
            <tr>
                <td>Access-Control-Allow-Origin</td>
                <td>* or specific origin</td>
                <td>Which origins can access the resource</td>
            </tr>
            <tr>
                <td>Access-Control-Allow-Methods</td>
                <td>GET, POST, PUT, DELETE, PATCH</td>
                <td>Allowed HTTP methods (preflight only)</td>
            </tr>
            <tr>
                <td>Access-Control-Allow-Headers</td>
                <td>Content-Type, Authorization, X-Request-ID</td>
                <td>Allowed request headers (preflight only)</td>
            </tr>
            <tr>
                <td>Access-Control-Expose-Headers</td>
                <td>X-Request-ID, X-RateLimit-Remaining</td>
                <td>Response headers JS can read</td>
            </tr>
            <tr>
                <td>Access-Control-Max-Age</td>
                <td>86400</td>
                <td>Preflight cache time in seconds</td>
            </tr>
            <tr>
                <td>Vary</td>
                <td>Origin</td>
                <td>Tells caches to vary by Origin header</td>
            </tr>
        </table>
    </div>

    <script>
    async function makeRequest(method, url, body = null) {
        const resultDiv = document.getElementById('result');
        try {
            const options = { method };
            if (body) {
                options.headers = { 'Content-Type': 'application/json' };
                options.body = JSON.stringify(body);
            }

            const response = await fetch(url, options);
            const data = await response.json();

            // Show response
            resultDiv.innerHTML = `<strong>${method} ${url}</strong><br>
                Status: ${response.status}<br>
                <pre>${JSON.stringify(data, null, 2)}</pre>`;
        } catch (e) {
            resultDiv.innerHTML = `<strong>Error:</strong> ${e.message}`;
        }
    }

    function testGET() { makeRequest('GET', '/api/data'); }
    function testPOST() { makeRequest('POST', '/api/data', { name: 'test' }); }
    function testPUT() { makeRequest('PUT', '/api/data/1', { name: 'updated' }); }
    function testDELETE() { makeRequest('DELETE', '/api/data/1'); }
    </script>
</body>
</html>
HTML
    $c->html($html);
});

# --- API Routes ---

$app->get('/api/data' => sub ($c) {
    $c->res_header('X-Request-ID', '12345');
    $c->res_header('X-RateLimit-Remaining', '99');
    $c->json({
        status => 'ok',
        data   => [
            { id => 1, name => 'Item 1' },
            { id => 2, name => 'Item 2' },
            { id => 3, name => 'Item 3' },
        ],
    });
});

$app->post('/api/data' => sub ($c) {
    $c->status(201)->json({
        status  => 'created',
        id      => 4,
        message => 'Item created successfully',
    });
});

$app->put('/api/data/:id' => sub ($c) {
    my $id = $c->path_params->{id};
    $c->json({
        status  => 'updated',
        id      => $id,
        message => "Item $id updated",
    });
});

$app->del('/api/data/:id' => sub ($c) {
    my $id = $c->path_params->{id};
    $c->json({
        status  => 'deleted',
        id      => $id,
        message => "Item $id deleted",
    });
});

# --- Manual CORS Example ---
# Use $c->cors() for per-route CORS configuration

$app->get('/api/special' => sub ($c) {
    # This route has custom CORS settings
    $c->cors(
        origin      => 'https://trusted-app.example.com',
        credentials => 1,  # Allow cookies from this origin
    )->json({
        message => 'This endpoint has custom CORS settings',
    });
});

# --- Origin Whitelist Example ---
# To restrict origins, use a whitelist instead of '*'
#
# $app->use_cors(
#     origins => [
#         'https://app.example.com',
#         'https://admin.example.com',
#         'http://localhost:3001',  # Development frontend
#     ],
#     credentials => 1,  # When using whitelist, credentials often needed
# );

$app->to_app;
