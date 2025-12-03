#!/usr/bin/env perl

# Admin Panel Sub-Application
#
# This file defines the admin panel sub-application that gets mounted under /admin
# It demonstrates a protected sub-application with authentication middleware.

use strict;
use warnings;
use experimental 'signatures';

use PAGI::Simple;

sub get_admin_app {
    my $app = PAGI::Simple->new(name => 'Admin Panel');

    # Admin dashboard
    $app->get('/' => sub ($c) {
        my $html = <<'HTML';
<!DOCTYPE html>
<html>
<head>
    <title>Admin Dashboard</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 50px auto; padding: 0 20px; background: #1a1a2e; color: #eee; }
        h1 { color: #e94560; }
        .card { background: #16213e; padding: 20px; margin: 15px 0; border-radius: 8px; border-left: 4px solid #e94560; }
        a { color: #0f3460; background: #e94560; padding: 8px 15px; border-radius: 5px; text-decoration: none; display: inline-block; margin: 5px; }
        a:hover { background: #ff6b6b; }
        .stat { font-size: 2em; font-weight: bold; color: #e94560; }
        .stat-label { color: #aaa; font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>Admin Dashboard</h1>
    <p>Welcome to the admin panel. This app is mounted at <code>/admin</code> with authentication middleware.</p>

    <div class="card">
        <div class="stat">1,234</div>
        <div class="stat-label">Total Users</div>
    </div>

    <div class="card">
        <div class="stat">567</div>
        <div class="stat-label">Active Sessions</div>
    </div>

    <div class="card">
        <div class="stat">89%</div>
        <div class="stat-label">System Health</div>
    </div>

    <div class="card">
        <h3>Quick Actions</h3>
        <a href="/admin/stats">View Stats</a>
        <a href="/admin/users">Manage Users</a>
        <a href="/admin/logs">View Logs</a>
    </div>

    <div class="card">
        <h3>Mount Information</h3>
        <p>This app demonstrates middleware applied at mount time.</p>
        <p>The <code>admin_auth</code> middleware runs before any admin route.</p>
    </div>
</body>
</html>
HTML
        $c->html($html);
    });

    # Alias for dashboard
    $app->get('/dashboard' => sub ($c) {
        # Redirect to root
        $c->redirect($c->mount_path . '/');
    });

    # System stats
    $app->get('/stats' => sub ($c) {
        $c->json({
            system => {
                cpu_usage => '23%',
                memory_usage => '45%',
                disk_usage => '67%',
                uptime => '15 days, 4 hours',
            },
            app => {
                requests_today => 12345,
                average_response_time => '45ms',
                error_rate => '0.1%',
            },
            database => {
                connections => 42,
                queries_per_second => 156,
                cache_hit_rate => '94%',
            },
            mount_path => $c->mount_path,
            local_path => $c->local_path,
        });
    });

    # User management
    $app->get('/users' => sub ($c) {
        $c->json({
            users => [
                { id => 1, name => 'Admin User', role => 'super_admin', status => 'active' },
                { id => 2, name => 'Moderator', role => 'moderator', status => 'active' },
                { id => 3, name => 'Suspended User', role => 'user', status => 'suspended' },
            ],
            total => 3,
            note => 'This is a simulated user list',
        });
    });

    # Logs endpoint
    $app->get('/logs' => sub ($c) {
        $c->json({
            logs => [
                { timestamp => '2024-12-03T10:00:00Z', level => 'INFO', message => 'User login: admin@example.com' },
                { timestamp => '2024-12-03T10:05:00Z', level => 'WARN', message => 'Failed login attempt' },
                { timestamp => '2024-12-03T10:10:00Z', level => 'INFO', message => 'Settings updated by admin' },
            ],
            mount_path => $c->mount_path,
        });
    });

    return $app;
}

1;
