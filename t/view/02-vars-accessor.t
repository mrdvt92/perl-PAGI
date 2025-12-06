#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;
use File::Temp qw(tempdir);

use lib 'lib';
use PAGI::Simple::View;
use PAGI::Simple::View::Vars;

#-------------------------------------------------------------------------
# Test: PAGI::Simple::View::Vars basic functionality
#-------------------------------------------------------------------------
subtest 'Vars class basic operations' => sub {
    my $vars = PAGI::Simple::View::Vars->new({
        title   => 'Hello World',
        count   => 42,
        items   => [1, 2, 3],
        user    => { name => 'Alice', email => 'alice@example.com' },
        empty   => '',
        zero    => 0,
        defined_undef => undef,
    });

    # Method access
    is($vars->title, 'Hello World', 'Method access returns correct value');
    is($vars->count, 42, 'Numeric value via method');
    is($vars->empty, '', 'Empty string via method');
    is($vars->zero, 0, 'Zero value via method');
    is($vars->defined_undef, undef, 'Undef value via method');

    # Array access
    is($vars->items, [1, 2, 3], 'Array ref via method');
    is($vars->{items}[0], 1, 'Array element via hash access');

    # Hash access (fallback)
    is($vars->{title}, 'Hello World', 'Hash access still works');
    is($vars->{user}{name}, 'Alice', 'Nested hash access');
};

#-------------------------------------------------------------------------
# Test: has() method
#-------------------------------------------------------------------------
subtest 'has() method checks key existence' => sub {
    my $vars = PAGI::Simple::View::Vars->new({
        exists_with_value => 'hello',
        exists_with_undef => undef,
        exists_with_zero  => 0,
        exists_with_empty => '',
    });

    ok($vars->has('exists_with_value'), 'has() true for key with value');
    ok($vars->has('exists_with_undef'), 'has() true for key with undef');
    ok($vars->has('exists_with_zero'), 'has() true for key with zero');
    ok($vars->has('exists_with_empty'), 'has() true for key with empty string');
    ok(!$vars->has('does_not_exist'), 'has() false for missing key');
};

#-------------------------------------------------------------------------
# Test: keys() method
#-------------------------------------------------------------------------
subtest 'keys() method lists all variables' => sub {
    my $vars = PAGI::Simple::View::Vars->new({
        alpha => 1,
        beta  => 2,
        gamma => 3,
    });

    my @keys = sort $vars->keys;
    is(\@keys, [qw(alpha beta gamma)], 'keys() returns all variable names');
};

#-------------------------------------------------------------------------
# Test: Error on missing keys
#-------------------------------------------------------------------------
subtest 'Error thrown for missing keys' => sub {
    my $vars = PAGI::Simple::View::Vars->new({
        title => 'Test',
        name  => 'Alice',
    });

    like(
        dies { $vars->typo },
        qr/Unknown template variable 'typo'/,
        'Throws error for missing key'
    );

    like(
        dies { $vars->typo },
        qr/Available variables:.*name.*title/,
        'Error message lists available variables'
    );
};

#-------------------------------------------------------------------------
# Test: Constructor validation
#-------------------------------------------------------------------------
subtest 'Constructor requires hashref' => sub {
    like(
        dies { PAGI::Simple::View::Vars->new('not a hash') },
        qr/Vars requires a hashref/,
        'Dies on non-hashref'
    );

    like(
        dies { PAGI::Simple::View::Vars->new([1, 2, 3]) },
        qr/Vars requires a hashref/,
        'Dies on arrayref'
    );

    ok(
        lives { PAGI::Simple::View::Vars->new({}) },
        'Empty hashref is OK'
    );
};

#-------------------------------------------------------------------------
# Test: AUTOLOAD caching (method should be installed)
#-------------------------------------------------------------------------
subtest 'AUTOLOAD installs methods for caching' => sub {
    my $vars = PAGI::Simple::View::Vars->new({
        cached_key => 'value',
    });

    # First access - hits AUTOLOAD
    is($vars->cached_key, 'value', 'First access works');

    # Check that can() now reports the method
    ok($vars->can('cached_key'), 'can() reports installed method');

    # Second access - should use cached method
    is($vars->cached_key, 'value', 'Second access works');
};

#-------------------------------------------------------------------------
# Test: can() method override
#-------------------------------------------------------------------------
subtest 'can() method reports available keys' => sub {
    my $vars = PAGI::Simple::View::Vars->new({
        title => 'Test',
    });

    # can() should return a coderef for existing keys
    ok($vars->can('title'), 'can() true for existing key');
    ok(!$vars->can('missing'), 'can() false for missing key');

    # Built-in methods
    ok($vars->can('has'), 'can() true for built-in has method');
    ok($vars->can('keys'), 'can() true for built-in keys method');
    ok($vars->can('new'), 'can() true for constructor');
};

#-------------------------------------------------------------------------
# Test: Integration with View - method syntax
#-------------------------------------------------------------------------
subtest 'View integration - method syntax' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
    );

    # Test basic method access
    my $output = $view->render_string(
        '<%= $v->title %>',
        title => 'Hello World'
    );
    is($output, 'Hello World', 'Method access works in template');

    # Test multiple variables
    $output = $view->render_string(
        '<%= $v->greeting %>, <%= $v->name %>!',
        greeting => 'Hello',
        name     => 'Alice'
    );
    is($output, 'Hello, Alice!', 'Multiple method accesses work');
};

#-------------------------------------------------------------------------
# Test: Integration with View - error on missing
#-------------------------------------------------------------------------
subtest 'View integration - error on missing variable' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
    );

    like(
        dies {
            $view->render_string(
                '<%= $v->typo %>',
                title => 'Test'
            );
        },
        qr/Unknown template variable 'typo'/,
        'Error thrown for typo in template'
    );
};

#-------------------------------------------------------------------------
# Test: Integration with View - hash access fallback
#-------------------------------------------------------------------------
subtest 'View integration - hash access fallback' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
    );

    # Hash access for dynamic keys
    my $output = $view->render_string(
        '<% my $key = "title"; %><%= $v->{$key} %>',
        title => 'Dynamic!'
    );
    is($output, 'Dynamic!', 'Hash access works for dynamic keys');

    # Hash access for loops
    $output = $view->render_string(
        '<% for my $item (@{$v->{items}}) { %><%= $item %>,<% } %>',
        items => [1, 2, 3]
    );
    is($output, '1,2,3,', 'Hash access works in loops');
};

#-------------------------------------------------------------------------
# Test: Integration with View - has() in template
#-------------------------------------------------------------------------
subtest 'View integration - has() in template' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
    );

    my $output = $view->render_string(
        '<% if ($v->has("title")) { %>YES<% } else { %>NO<% } %>',
        title => 'Test'
    );
    is($output, 'YES', 'has() returns true for existing key');

    $output = $view->render_string(
        '<% if ($v->has("missing")) { %>YES<% } else { %>NO<% } %>',
        title => 'Test'
    );
    is($output, 'NO', 'has() returns false for missing key');
};

#-------------------------------------------------------------------------
# Test: Nested objects still work
#-------------------------------------------------------------------------
subtest 'Nested objects and hashrefs' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
    );

    my $output = $view->render_string(
        '<%= $v->user->{name} %>',
        user => { name => 'Alice', email => 'alice@test.com' }
    );
    is($output, 'Alice', 'Nested hashref access works');

    # Array of hashrefs
    $output = $view->render_string(
        '<% for my $u (@{$v->users}) { %><%= $u->{name} %>,<% } %>',
        users => [ { name => 'Alice' }, { name => 'Bob' } ]
    );
    is($output, 'Alice,Bob,', 'Array of hashrefs works');
};

done_testing;
