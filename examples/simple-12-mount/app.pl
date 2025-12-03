#!/usr/bin/env perl

# Mounting Sub-Applications Example
#
# This example demonstrates how to mount sub-applications under path prefixes:
# - Mount multiple PAGI::Simple apps under different paths
# - Versioned API pattern (v1, v2)
# - Admin panel with authentication middleware
# - Path rewriting and mount_path/local_path accessors
#
# Run with:
#   pagi-server --port 3000 app.pl
#
# Test with:
#   curl http://localhost:3000/
#   curl http://localhost:3000/api/v1/users
#   curl http://localhost:3000/api/v2/users
#   curl http://localhost:3000/admin/dashboard

use strict;
use warnings;
use experimental 'signatures';

use PAGI::Simple;

# Load sub-applications
require './api_v1.pl';
require './api_v2.pl';
require './admin.pl';

my $app = PAGI::Simple->new(name => 'Mount Demo');

# --- Main app routes ---

$app->get('/' => sub ($c) {
    my $html = <<'HTML';
<!DOCTYPE html>
<html>
<head>
    <title>Mount Sub-Applications Demo</title>
    <style>
        body { font-family: sans-serif; max-width: 900px; margin: 50px auto; padding: 0 20px; }
        h1 { color: #333; }
        .section { margin: 20px 0; padding: 20px; background: #f5f5f5; border-radius: 5px; }
        a { color: #007bff; text-decoration: none; }
        a:hover { text-decoration: underline; }
        ul { list-style: none; padding: 0; }
        li { margin: 10px 0; }
        code { background: #e9e9e9; padding: 2px 6px; border-radius: 3px; font-family: monospace; }
        pre { background: #222; color: #0f0; padding: 15px; border-radius: 5px; overflow-x: auto; }
        .app-box { display: inline-block; padding: 10px 15px; margin: 5px; background: #007bff; color: white; border-radius: 5px; }
        .app-box.v2 { background: #28a745; }
        .app-box.admin { background: #dc3545; }
    </style>
</head>
<body>
    <h1>Mount Sub-Applications Demo</h1>
    <p>This demo shows how to mount multiple PAGI::Simple applications under different path prefixes.</p>

    <div class="section">
        <h2>Mounted Applications</h2>
        <div>
            <span class="app-box">API v1 @ /api/v1</span>
            <span class="app-box v2">API v2 @ /api/v2</span>
            <span class="app-box admin">Admin @ /admin</span>
        </div>
    </div>

    <div class="section">
        <h2>API v1 Routes</h2>
        <ul>
            <li><a href="/api/v1/">/api/v1/</a> - API v1 root</li>
            <li><a href="/api/v1/users">/api/v1/users</a> - List users (v1 format)</li>
            <li><a href="/api/v1/users/1">/api/v1/users/1</a> - Get user 1</li>
        </ul>
    </div>

    <div class="section">
        <h2>API v2 Routes</h2>
        <ul>
            <li><a href="/api/v2/">/api/v2/</a> - API v2 root</li>
            <li><a href="/api/v2/users">/api/v2/users</a> - List users (v2 format with metadata)</li>
            <li><a href="/api/v2/users/1">/api/v2/users/1</a> - Get user 1 (expanded format)</li>
        </ul>
    </div>

    <div class="section">
        <h2>Admin Panel Routes</h2>
        <ul>
            <li><a href="/admin/">/admin/</a> - Admin dashboard</li>
            <li><a href="/admin/stats">/admin/stats</a> - System statistics</li>
        </ul>
        <p><em>Note: Admin routes run through auth middleware (simulated)</em></p>
    </div>

    <div class="section">
        <h2>Mount Path Information</h2>
        <ul>
            <li><a href="/api/v1/info">/api/v1/info</a> - Shows mount_path, local_path, full_path</li>
            <li><a href="/api/v2/info">/api/v2/info</a> - Shows mount info for v2</li>
        </ul>
    </div>

    <div class="section">
        <h2>Test with curl</h2>
        <pre>
# Main app
curl http://localhost:3000/

# API v1
curl http://localhost:3000/api/v1/users
curl http://localhost:3000/api/v1/users/42

# API v2 (different response format)
curl http://localhost:3000/api/v2/users
curl http://localhost:3000/api/v2/users/42

# Admin (with middleware)
curl http://localhost:3000/admin/dashboard
curl http://localhost:3000/admin/stats

# Mount path info
curl http://localhost:3000/api/v1/info
        </pre>
    </div>
</body>
</html>
HTML
    $c->html($html);
});

$app->get('/health' => sub ($c) {
    $c->json({ status => 'ok', app => 'main' });
});

# --- Mount sub-applications ---

# Get sub-applications
my $api_v1 = get_api_v1();
my $api_v2 = get_api_v2();
my $admin  = get_admin_app();

# Simple auth middleware for admin (simulation)
$app->middleware(admin_auth => sub ($c, $next) {
    # In a real app, check session/token here
    # For demo, just add a header indicating auth happened
    $c->res_header('X-Admin-Auth' => 'simulated');
    return $next->();
});

# Mount the sub-applications
$app->mount('/api/v1' => $api_v1);
$app->mount('/api/v2' => $api_v2);
$app->mount('/admin' => $admin, [qw(admin_auth)]);

$app->to_app;
