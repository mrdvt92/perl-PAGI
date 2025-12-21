# PAGI::Request Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a convenience Request class that wraps raw PAGI scope/receive with friendly methods for headers, query params, body parsing, cookies, and file uploads.

**Architecture:** PAGI::Request wraps `$scope` and `$receive`, providing lazy async accessors. Uses HTTP::MultiPartParser for multipart parsing with our async wrapper. Upload objects handle temp file spooling. All body parsing is cached after first read. Hash::MultiValue used for multi-value params. Raw PAGI apps continue to work unchanged.

**Tech Stack:** Perl 5.16+, Hash::MultiValue, HTTP::MultiPartParser, Cookie::Baker, Future::AsyncAwait, IO::Async

---

## Dependencies

Add to `cpanfile`:
```perl
requires 'Hash::MultiValue', '0.16';
requires 'HTTP::MultiPartParser', '0.02';
```

---

## Task 1: Core PAGI::Request with Basic Properties

**Files:**
- Create: `lib/PAGI/Request.pm`
- Create: `t/request/01-basic.t`

**Step 1: Create test file with basic property tests**

Create `t/request/01-basic.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;

use lib 'lib';
use PAGI::Request;

subtest 'constructor and basic properties' => sub {
    my $scope = {
        type         => 'http',
        method       => 'GET',
        path         => '/users/42',
        raw_path     => '/users/42',
        query_string => 'foo=bar&baz=qux',
        scheme       => 'https',
        http_version => '1.1',
        headers      => [
            ['host', 'example.com'],
            ['content-type', 'application/json'],
            ['accept', 'text/html'],
            ['accept', 'application/json'],
        ],
        client => ['127.0.0.1', 54321],
    };

    my $req = PAGI::Request->new($scope);

    is($req->method, 'GET', 'method');
    is($req->path, '/users/42', 'path');
    is($req->raw_path, '/users/42', 'raw_path');
    is($req->query_string, 'foo=bar&baz=qux', 'query_string');
    is($req->scheme, 'https', 'scheme');
    is($req->host, 'example.com', 'host from headers');
    is($req->content_type, 'application/json', 'content_type');
    is_deeply($req->client, ['127.0.0.1', 54321], 'client');
};

subtest 'predicate methods' => sub {
    my $get_scope = { type => 'http', method => 'GET', headers => [] };
    my $post_scope = { type => 'http', method => 'POST', headers => [] };

    my $get_req = PAGI::Request->new($get_scope);
    my $post_req = PAGI::Request->new($post_scope);

    ok($get_req->is_get, 'is_get true for GET');
    ok(!$get_req->is_post, 'is_post false for GET');
    ok($post_req->is_post, 'is_post true for POST');
    ok(!$post_req->is_get, 'is_get false for POST');
};

done_testing;
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/01-basic.t`
Expected: FAIL with "Can't locate PAGI/Request.pm"

**Step 3: Create minimal PAGI::Request module**

Create `lib/PAGI/Request.pm`:
```perl
package PAGI::Request;
use strict;
use warnings;

sub new {
    my ($class, $scope, $receive) = @_;
    return bless {
        scope   => $scope,
        receive => $receive,
        _body_read => 0,
    }, $class;
}

# Basic properties from scope
sub method       { shift->{scope}{method} }
sub path         { shift->{scope}{path} }
sub raw_path     { shift->{scope}{raw_path} // shift->{scope}{path} }
sub query_string { shift->{scope}{query_string} // '' }
sub scheme       { shift->{scope}{scheme} // 'http' }
sub http_version { shift->{scope}{http_version} // '1.1' }
sub client       { shift->{scope}{client} }
sub raw          { shift->{scope} }

# Host from headers
sub host {
    my $self = shift;
    return $self->header('host');
}

# Content-Type shortcut
sub content_type {
    my $self = shift;
    my $ct = $self->header('content-type') // '';
    # Strip parameters like charset
    $ct =~ s/;.*//;
    return $ct;
}

# Content-Length shortcut
sub content_length {
    my $self = shift;
    return $self->header('content-length');
}

# Single header lookup (case-insensitive, returns last value)
sub header {
    my ($self, $name) = @_;
    $name = lc($name);
    my $value;
    for my $pair (@{$self->{scope}{headers} // []}) {
        if (lc($pair->[0]) eq $name) {
            $value = $pair->[1];
        }
    }
    return $value;
}

# Method predicates
sub is_get     { uc(shift->method // '') eq 'GET' }
sub is_post    { uc(shift->method // '') eq 'POST' }
sub is_put     { uc(shift->method // '') eq 'PUT' }
sub is_patch   { uc(shift->method // '') eq 'PATCH' }
sub is_delete  { uc(shift->method // '') eq 'DELETE' }
sub is_head    { uc(shift->method // '') eq 'HEAD' }
sub is_options { uc(shift->method // '') eq 'OPTIONS' }

1;

__END__

=head1 NAME

PAGI::Request - Convenience wrapper for PAGI request scope

=head1 SYNOPSIS

    use PAGI::Request;

    async sub app {
        my ($scope, $receive, $send) = @_;
        my $req = PAGI::Request->new($scope, $receive);

        my $method = $req->method;
        my $path = $req->path;
        my $ct = $req->content_type;
    }

=cut
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/01-basic.t`
Expected: All tests pass

**Step 5: Run full test suite to ensure no regressions**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/01-basic.t
git commit -m "feat(request): add PAGI::Request with basic properties

- Constructor takes scope and optional receive
- Basic properties: method, path, raw_path, query_string, scheme, host
- Content-Type and Content-Length shortcuts
- Case-insensitive header lookup
- Method predicates: is_get, is_post, etc."
```

---

## Task 2: Headers with Hash::MultiValue

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Modify: `t/request/01-basic.t`
- Modify: `cpanfile`

**Step 1: Add Hash::MultiValue to cpanfile**

Add to `cpanfile` after the Cookie::Baker line:
```perl
requires 'Hash::MultiValue', '0.16';
```

**Step 2: Add header tests to test file**

Add to `t/request/01-basic.t` before `done_testing`:
```perl
subtest 'headers as Hash::MultiValue' => sub {
    my $scope = {
        type    => 'http',
        method  => 'GET',
        headers => [
            ['Accept', 'text/html'],
            ['Accept', 'application/json'],
            ['Content-Type', 'text/plain'],
            ['X-Custom', 'value1'],
        ],
    };

    my $req = PAGI::Request->new($scope);

    # headers returns Hash::MultiValue
    my $headers = $req->headers;
    isa_ok($headers, 'Hash::MultiValue', 'headers returns Hash::MultiValue');

    # Single value access (last value)
    is($headers->get('accept'), 'application/json', 'get returns last value');
    is($headers->get('Accept'), 'application/json', 'case insensitive');

    # Multi-value access
    my @accepts = $headers->get_all('accept');
    is_deeply(\@accepts, ['text/html', 'application/json'], 'get_all returns all values');

    # header_all method
    my @accepts2 = $req->header_all('accept');
    is_deeply(\@accepts2, ['text/html', 'application/json'], 'header_all works');
};
```

**Step 3: Run test to verify it fails**

Run: `prove -l t/request/01-basic.t`
Expected: FAIL - headers method doesn't return Hash::MultiValue

**Step 4: Implement headers with Hash::MultiValue**

Add to `lib/PAGI/Request.pm` after `use warnings;`:
```perl
use Hash::MultiValue;
```

Add method to `lib/PAGI/Request.pm`:
```perl
# All headers as Hash::MultiValue (cached, case-insensitive keys)
sub headers {
    my $self = shift;
    return $self->{_headers} if $self->{_headers};

    my @pairs;
    for my $pair (@{$self->{scope}{headers} // []}) {
        push @pairs, lc($pair->[0]), $pair->[1];
    }

    $self->{_headers} = Hash::MultiValue->new(@pairs);
    return $self->{_headers};
}

# All values for a header
sub header_all {
    my ($self, $name) = @_;
    return $self->headers->get_all(lc($name));
}
```

**Step 5: Run test to verify it passes**

Run: `prove -l t/request/01-basic.t`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/01-basic.t cpanfile
git commit -m "feat(request): add headers as Hash::MultiValue

- headers() returns Hash::MultiValue for multi-value header access
- header_all() returns list of all values for a header
- Headers are cached after first access
- Case-insensitive header names"
```

---

## Task 3: Query Parameters with Hash::MultiValue

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Create: `t/request/02-query-params.t`

**Step 1: Create query params test file**

Create `t/request/02-query-params.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;

use lib 'lib';
use PAGI::Request;

subtest 'query_params returns Hash::MultiValue' => sub {
    my $scope = {
        type         => 'http',
        method       => 'GET',
        query_string => 'foo=bar&baz=qux&foo=second',
        headers      => [],
    };

    my $req = PAGI::Request->new($scope);
    my $params = $req->query_params;

    isa_ok($params, 'Hash::MultiValue', 'returns Hash::MultiValue');
    is($params->get('foo'), 'second', 'get returns last value');
    is($params->get('baz'), 'qux', 'single value works');

    my @foos = $params->get_all('foo');
    is_deeply(\@foos, ['bar', 'second'], 'get_all returns all values');
};

subtest 'query() shortcut method' => sub {
    my $scope = {
        type         => 'http',
        method       => 'GET',
        query_string => 'page=5&tags=perl&tags=async',
        headers      => [],
    };

    my $req = PAGI::Request->new($scope);

    is($req->query('page'), '5', 'query returns single value');
    is($req->query('tags'), 'async', 'query returns last for multi');
    is($req->query('missing'), undef, 'query returns undef for missing');
};

subtest 'percent-decoding' => sub {
    my $scope = {
        type         => 'http',
        method       => 'GET',
        query_string => 'name=John%20Doe&emoji=%F0%9F%94%A5',
        headers      => [],
    };

    my $req = PAGI::Request->new($scope);

    is($req->query('name'), 'John Doe', 'spaces decoded');
    is($req->query('emoji'), "\x{1F525}", 'UTF-8 emoji decoded');
};

subtest 'empty and missing query string' => sub {
    my $scope1 = { type => 'http', method => 'GET', query_string => '', headers => [] };
    my $scope2 = { type => 'http', method => 'GET', headers => [] };

    my $req1 = PAGI::Request->new($scope1);
    my $req2 = PAGI::Request->new($scope2);

    isa_ok($req1->query_params, 'Hash::MultiValue', 'empty string returns empty HMV');
    isa_ok($req2->query_params, 'Hash::MultiValue', 'missing returns empty HMV');

    is($req1->query('foo'), undef, 'missing key returns undef');
};

done_testing;
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/02-query-params.t`
Expected: FAIL - query_params method not implemented

**Step 3: Implement query_params**

Add to `lib/PAGI/Request.pm`:
```perl
use URI::Escape qw(uri_unescape);
use Encode qw(decode_utf8);

# Query params as Hash::MultiValue (cached)
sub query_params {
    my $self = shift;
    return $self->{_query_params} if $self->{_query_params};

    my $qs = $self->query_string;
    my @pairs;

    for my $part (split /&/, $qs) {
        next unless length $part;
        my ($key, $val) = split /=/, $part, 2;
        $key //= '';
        $val //= '';

        # Decode percent-encoding and UTF-8
        $key = decode_utf8(uri_unescape($key));
        $val = decode_utf8(uri_unescape($val));

        push @pairs, $key, $val;
    }

    $self->{_query_params} = Hash::MultiValue->new(@pairs);
    return $self->{_query_params};
}

# Shortcut for single query param
sub query {
    my ($self, $name) = @_;
    return $self->query_params->get($name);
}
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/02-query-params.t`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/02-query-params.t
git commit -m "feat(request): add query_params with Hash::MultiValue

- query_params() returns Hash::MultiValue
- query() shortcut for single param access
- Percent-decoding with UTF-8 support
- Cached after first access"
```

---

## Task 4: Cookie Parsing

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Create: `t/request/03-cookies.t`

**Step 1: Create cookies test file**

Create `t/request/03-cookies.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;

use lib 'lib';
use PAGI::Request;

subtest 'cookies parsing' => sub {
    my $scope = {
        type    => 'http',
        method  => 'GET',
        headers => [
            ['cookie', 'session=abc123; user=john; theme=dark'],
        ],
    };

    my $req = PAGI::Request->new($scope);
    my $cookies = $req->cookies;

    is(ref($cookies), 'HASH', 'cookies returns hashref');
    is($cookies->{session}, 'abc123', 'session cookie');
    is($cookies->{user}, 'john', 'user cookie');
    is($cookies->{theme}, 'dark', 'theme cookie');
};

subtest 'cookie() shortcut' => sub {
    my $scope = {
        type    => 'http',
        method  => 'GET',
        headers => [
            ['cookie', 'token=xyz789'],
        ],
    };

    my $req = PAGI::Request->new($scope);

    is($req->cookie('token'), 'xyz789', 'cookie() returns value');
    is($req->cookie('missing'), undef, 'missing cookie returns undef');
};

subtest 'no cookies' => sub {
    my $scope = { type => 'http', method => 'GET', headers => [] };
    my $req = PAGI::Request->new($scope);

    is_deeply($req->cookies, {}, 'empty cookies returns empty hash');
    is($req->cookie('anything'), undef, 'missing returns undef');
};

subtest 'cookies with special characters' => sub {
    my $scope = {
        type    => 'http',
        method  => 'GET',
        headers => [
            ['cookie', 'data=hello%20world; encoded=%3D%26'],
        ],
    };

    my $req = PAGI::Request->new($scope);

    # Cookie::Baker handles URL decoding
    is($req->cookie('data'), 'hello%20world', 'preserves encoding (Cookie::Baker behavior)');
};

done_testing;
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/03-cookies.t`
Expected: FAIL - cookies method not implemented

**Step 3: Implement cookies**

Add to `lib/PAGI/Request.pm`:
```perl
use Cookie::Baker qw(crush_cookie);

# All cookies as hashref (cached)
sub cookies {
    my $self = shift;
    return $self->{_cookies} if exists $self->{_cookies};

    my $cookie_header = $self->header('cookie') // '';
    $self->{_cookies} = crush_cookie($cookie_header);
    return $self->{_cookies};
}

# Single cookie value
sub cookie {
    my ($self, $name) = @_;
    return $self->cookies->{$name};
}
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/03-cookies.t`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/03-cookies.t
git commit -m "feat(request): add cookie parsing with Cookie::Baker

- cookies() returns hashref of all cookies
- cookie() shortcut for single cookie
- Uses Cookie::Baker for parsing
- Cached after first access"
```

---

## Task 5: Content-Type Predicates

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Create: `t/request/04-predicates.t`

**Step 1: Create predicates test file**

Create `t/request/04-predicates.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;

use lib 'lib';
use PAGI::Request;

subtest 'is_json predicate' => sub {
    my $json_scope = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', 'application/json']],
    };
    my $json_charset = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', 'application/json; charset=utf-8']],
    };
    my $html_scope = {
        type    => 'http',
        method  => 'GET',
        headers => [['content-type', 'text/html']],
    };

    ok(PAGI::Request->new($json_scope)->is_json, 'application/json is json');
    ok(PAGI::Request->new($json_charset)->is_json, 'with charset is json');
    ok(!PAGI::Request->new($html_scope)->is_json, 'text/html is not json');
};

subtest 'is_form predicate' => sub {
    my $urlencoded = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', 'application/x-www-form-urlencoded']],
    };
    my $multipart = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', 'multipart/form-data; boundary=----abc']],
    };
    my $json = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', 'application/json']],
    };

    ok(PAGI::Request->new($urlencoded)->is_form, 'urlencoded is form');
    ok(PAGI::Request->new($multipart)->is_form, 'multipart is form');
    ok(!PAGI::Request->new($json)->is_form, 'json is not form');
};

subtest 'is_multipart predicate' => sub {
    my $multipart = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', 'multipart/form-data; boundary=----abc']],
    };
    my $urlencoded = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', 'application/x-www-form-urlencoded']],
    };

    ok(PAGI::Request->new($multipart)->is_multipart, 'multipart/form-data');
    ok(!PAGI::Request->new($urlencoded)->is_multipart, 'urlencoded is not multipart');
};

subtest 'accepts predicate' => sub {
    my $scope = {
        type    => 'http',
        method  => 'GET',
        headers => [
            ['accept', 'text/html'],
            ['accept', 'application/json'],
        ],
    };

    my $req = PAGI::Request->new($scope);

    ok($req->accepts('text/html'), 'accepts text/html');
    ok($req->accepts('application/json'), 'accepts application/json');
    ok(!$req->accepts('text/plain'), 'does not accept text/plain');
    ok($req->accepts('text/*'), 'accepts text/* wildcard');
    ok($req->accepts('*/*'), 'accepts */* wildcard');
};

done_testing;
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/04-predicates.t`
Expected: FAIL - is_json, is_form, etc. not implemented

**Step 3: Implement content-type predicates**

Add to `lib/PAGI/Request.pm`:
```perl
# Content-type predicates
sub is_json {
    my $self = shift;
    my $ct = $self->content_type;
    return $ct eq 'application/json';
}

sub is_form {
    my $self = shift;
    my $ct = $self->content_type;
    return $ct eq 'application/x-www-form-urlencoded'
        || $ct =~ m{^multipart/form-data};
}

sub is_multipart {
    my $self = shift;
    my $ct = $self->content_type;
    return $ct =~ m{^multipart/form-data};
}

# Accept header check
sub accepts {
    my ($self, $mime_type) = @_;
    my @accepts = $self->header_all('accept');

    for my $accept (@accepts) {
        # Handle wildcards
        if ($accept eq '*/*' || $mime_type eq '*/*') {
            return 1;
        }
        if ($accept =~ m{^([^/]+)/\*$}) {
            my $type = $1;
            return 1 if $mime_type =~ m{^\Q$type\E/};
        }
        if ($mime_type =~ m{^([^/]+)/\*$}) {
            my $type = $1;
            return 1 if $accept =~ m{^\Q$type\E/};
        }
        # Exact match
        return 1 if $accept eq $mime_type;
    }

    return 0;
}
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/04-predicates.t`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/04-predicates.t
git commit -m "feat(request): add content-type predicates

- is_json, is_form, is_multipart predicates
- accepts() checks Accept header with wildcard support"
```

---

## Task 6: Auth Helpers (bearer_token, basic_auth)

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Create: `t/request/05-auth.t`

**Step 1: Create auth helpers test file**

Create `t/request/05-auth.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;

use lib 'lib';
use PAGI::Request;
use MIME::Base64 qw(encode_base64);

subtest 'bearer_token' => sub {
    my $scope = {
        type    => 'http',
        method  => 'GET',
        headers => [['authorization', 'Bearer abc123xyz']],
    };

    my $req = PAGI::Request->new($scope);
    is($req->bearer_token, 'abc123xyz', 'extracts bearer token');
};

subtest 'bearer_token missing' => sub {
    my $scope1 = { type => 'http', method => 'GET', headers => [] };
    my $scope2 = {
        type    => 'http',
        method  => 'GET',
        headers => [['authorization', 'Basic dXNlcjpwYXNz']],
    };

    is(PAGI::Request->new($scope1)->bearer_token, undef, 'no auth header');
    is(PAGI::Request->new($scope2)->bearer_token, undef, 'basic auth not bearer');
};

subtest 'basic_auth' => sub {
    my $encoded = encode_base64('john:secret123', '');
    my $scope = {
        type    => 'http',
        method  => 'GET',
        headers => [['authorization', "Basic $encoded"]],
    };

    my $req = PAGI::Request->new($scope);
    my ($user, $pass) = $req->basic_auth;

    is($user, 'john', 'username extracted');
    is($pass, 'secret123', 'password extracted');
};

subtest 'basic_auth with colon in password' => sub {
    my $encoded = encode_base64('user:pass:with:colons', '');
    my $scope = {
        type    => 'http',
        method  => 'GET',
        headers => [['authorization', "Basic $encoded"]],
    };

    my ($user, $pass) = PAGI::Request->new($scope)->basic_auth;

    is($user, 'user', 'username correct');
    is($pass, 'pass:with:colons', 'password with colons preserved');
};

subtest 'basic_auth missing' => sub {
    my $scope = { type => 'http', method => 'GET', headers => [] };
    my ($user, $pass) = PAGI::Request->new($scope)->basic_auth;

    is($user, undef, 'no user');
    is($pass, undef, 'no pass');
};

done_testing;
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/05-auth.t`
Expected: FAIL - bearer_token, basic_auth not implemented

**Step 3: Implement auth helpers**

Add to `lib/PAGI/Request.pm`:
```perl
use MIME::Base64 qw(decode_base64);

# Extract Bearer token from Authorization header
sub bearer_token {
    my $self = shift;
    my $auth = $self->header('authorization') // '';
    if ($auth =~ /^Bearer\s+(.+)$/i) {
        return $1;
    }
    return undef;
}

# Extract Basic auth credentials
sub basic_auth {
    my $self = shift;
    my $auth = $self->header('authorization') // '';
    if ($auth =~ /^Basic\s+(.+)$/i) {
        my $decoded = decode_base64($1);
        my ($user, $pass) = split /:/, $decoded, 2;
        return ($user, $pass);
    }
    return (undef, undef);
}
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/05-auth.t`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/05-auth.t
git commit -m "feat(request): add auth helpers

- bearer_token() extracts Bearer token from Authorization header
- basic_auth() decodes Basic auth and returns (user, pass)"
```

---

## Task 7: Stash (Per-Request State)

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Create: `t/request/06-stash.t`

**Step 1: Create stash test file**

Create `t/request/06-stash.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;

use lib 'lib';
use PAGI::Request;

subtest 'stash basic usage' => sub {
    my $scope = { type => 'http', method => 'GET', headers => [] };
    my $req = PAGI::Request->new($scope);

    # Starts empty
    is_deeply($req->stash, {}, 'stash starts empty');

    # Can set values
    $req->stash->{user} = { id => 42, name => 'John' };
    $req->stash->{authenticated} = 1;

    # Can read values
    is($req->stash->{user}{id}, 42, 'read nested value');
    is($req->stash->{authenticated}, 1, 'read simple value');
};

subtest 'stash persists on same request' => sub {
    my $scope = { type => 'http', method => 'GET', headers => [] };
    my $req = PAGI::Request->new($scope);

    $req->stash->{counter} = 1;
    $req->stash->{counter}++;
    $req->stash->{counter}++;

    is($req->stash->{counter}, 3, 'modifications persist');
};

subtest 'stash isolated between requests' => sub {
    my $scope = { type => 'http', method => 'GET', headers => [] };
    my $req1 = PAGI::Request->new($scope);
    my $req2 = PAGI::Request->new($scope);

    $req1->stash->{value} = 'first';
    $req2->stash->{value} = 'second';

    is($req1->stash->{value}, 'first', 'req1 has its own stash');
    is($req2->stash->{value}, 'second', 'req2 has its own stash');
};

done_testing;
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/06-stash.t`
Expected: FAIL - stash method not implemented

**Step 3: Implement stash**

Add to `lib/PAGI/Request.pm`:
```perl
# Per-request storage for middleware/handlers
sub stash {
    my $self = shift;
    $self->{_stash} //= {};
    return $self->{_stash};
}
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/06-stash.t`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/06-stash.t
git commit -m "feat(request): add stash for per-request state

- stash() returns hashref for middleware to store data
- Isolated between request instances"
```

---

## Task 8: Path Params (Router Integration)

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Create: `t/request/07-params.t`

**Step 1: Create path params test file**

Create `t/request/07-params.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;

use lib 'lib';
use PAGI::Request;

subtest 'params from scope' => sub {
    my $scope = {
        type    => 'http',
        method  => 'GET',
        path    => '/users/42/posts/100',
        headers => [],
        # Router would set this
        path_params => { user_id => '42', post_id => '100' },
    };

    my $req = PAGI::Request->new($scope);

    is_deeply($req->params, { user_id => '42', post_id => '100' }, 'params returns hashref');
    is($req->param('user_id'), '42', 'param() gets single value');
    is($req->param('post_id'), '100', 'param() another value');
    is($req->param('missing'), undef, 'missing param is undef');
};

subtest 'set_params for router integration' => sub {
    my $scope = { type => 'http', method => 'GET', headers => [] };
    my $req = PAGI::Request->new($scope);

    # Router calls this after matching
    $req->set_params({ id => '123', slug => 'hello-world' });

    is($req->param('id'), '123', 'param after set_params');
    is($req->param('slug'), 'hello-world', 'another param');
};

subtest 'no params' => sub {
    my $scope = { type => 'http', method => 'GET', headers => [] };
    my $req = PAGI::Request->new($scope);

    is_deeply($req->params, {}, 'empty params by default');
    is($req->param('anything'), undef, 'missing returns undef');
};

done_testing;
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/07-params.t`
Expected: FAIL - params, param, set_params not implemented

**Step 3: Implement path params**

Add to `lib/PAGI/Request.pm`:
```perl
# Path params (set by router)
sub params {
    my $self = shift;
    return $self->{_path_params} // $self->{scope}{path_params} // {};
}

sub param {
    my ($self, $name) = @_;
    return $self->params->{$name};
}

# Called by router to set matched params
sub set_params {
    my ($self, $params) = @_;
    $self->{_path_params} = $params;
}
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/07-params.t`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/07-params.t
git commit -m "feat(request): add path params for router integration

- params() returns path parameters hashref
- param() gets single path parameter
- set_params() for router to set matched params"
```

---

## Task 9: Async Body Reading

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Create: `t/request/08-body.t`

**Step 1: Create body reading test file**

Create `t/request/08-body.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;
use Future::AsyncAwait;

use lib 'lib';
use PAGI::Request;

# Helper to create a mock receive that returns body in chunks
sub mock_receive {
    my (@chunks) = @_;
    my $index = 0;
    return async sub {
        if ($index < @chunks) {
            my $chunk = $chunks[$index++];
            return {
                type => 'http.request',
                body => $chunk,
                more => ($index < @chunks),
            };
        }
        return { type => 'http.disconnect' };
    };
}

subtest 'body reads entire content' => sub {
    my $scope = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-length', '11']],
    };
    my $receive = mock_receive('Hello', ' ', 'World');
    my $req = PAGI::Request->new($scope, $receive);

    my $body = (async sub { await $req->body })->();
    $body = $body->get;  # Resolve Future

    is($body, 'Hello World', 'body concatenates all chunks');
};

subtest 'body caches result' => sub {
    my $call_count = 0;
    my $scope = { type => 'http', method => 'POST', headers => [] };
    my $receive = async sub {
        $call_count++;
        return { type => 'http.request', body => 'data', more => 0 };
    };

    my $req = PAGI::Request->new($scope, $receive);

    my $body1 = (async sub { await $req->body })->()->get;
    my $body2 = (async sub { await $req->body })->()->get;

    is($body1, 'data', 'first read works');
    is($body2, 'data', 'second read works');
    is($call_count, 1, 'receive only called once (cached)');
};

subtest 'text decodes as UTF-8' => sub {
    my $utf8_bytes = "Caf\xc3\xa9";  # "Café" in UTF-8
    my $scope = { type => 'http', method => 'POST', headers => [] };
    my $receive = mock_receive($utf8_bytes);
    my $req = PAGI::Request->new($scope, $receive);

    my $text = (async sub { await $req->text })->()->get;

    is($text, "Café", 'text decodes UTF-8');
};

subtest 'json parses body' => sub {
    my $json_body = '{"name":"John","age":30}';
    my $scope = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', 'application/json']],
    };
    my $receive = mock_receive($json_body);
    my $req = PAGI::Request->new($scope, $receive);

    my $data = (async sub { await $req->json })->()->get;

    is_deeply($data, { name => 'John', age => 30 }, 'json parses correctly');
};

subtest 'json dies on invalid JSON' => sub {
    my $bad_json = '{"broken":';
    my $scope = { type => 'http', method => 'POST', headers => [] };
    my $receive = mock_receive($bad_json);
    my $req = PAGI::Request->new($scope, $receive);

    my $died = 0;
    eval {
        (async sub { await $req->json })->()->get;
    };
    $died = 1 if $@;

    ok($died, 'json dies on invalid JSON');
};

subtest 'empty body' => sub {
    my $scope = { type => 'http', method => 'GET', headers => [] };
    my $receive = mock_receive();
    my $req = PAGI::Request->new($scope, $receive);

    my $body = (async sub { await $req->body })->()->get;

    is($body, '', 'empty body returns empty string');
};

done_testing;
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/08-body.t`
Expected: FAIL - body, text, json not implemented

**Step 3: Implement async body reading**

Add to `lib/PAGI/Request.pm` after `use MIME::Base64`:
```perl
use Future::AsyncAwait;
use JSON::PP qw(decode_json);
```

Add methods:
```perl
# Read raw body bytes (async, cached)
async sub body {
    my $self = shift;

    # Return cached body if already read
    return $self->{_body} if $self->{_body_read};

    my $receive = $self->{receive};
    die "No receive callback provided" unless $receive;

    my $body = '';
    while (1) {
        my $message = await $receive->();
        last unless $message && $message->{type};
        last if $message->{type} eq 'http.disconnect';

        $body .= $message->{body} // '';
        last unless $message->{more};
    }

    $self->{_body} = $body;
    $self->{_body_read} = 1;
    return $body;
}

# Read body as decoded UTF-8 text (async)
async sub text {
    my $self = shift;
    my $body = await $self->body;
    return decode_utf8($body);
}

# Parse body as JSON (async, dies on error)
async sub json {
    my $self = shift;
    my $body = await $self->body;
    return decode_json($body);
}
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/08-body.t`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/08-body.t
git commit -m "feat(request): add async body reading

- body() reads and caches raw bytes
- text() decodes as UTF-8
- json() parses as JSON (dies on error)
- All are async methods using Future::AsyncAwait"
```

---

## Task 10: Form Data Parsing (URL-encoded)

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Create: `t/request/09-form.t`

**Step 1: Create form parsing test file**

Create `t/request/09-form.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;
use Future::AsyncAwait;

use lib 'lib';
use PAGI::Request;

sub mock_receive {
    my (@chunks) = @_;
    my $index = 0;
    return async sub {
        if ($index < @chunks) {
            my $chunk = $chunks[$index++];
            return { type => 'http.request', body => $chunk, more => ($index < @chunks) };
        }
        return { type => 'http.disconnect' };
    };
}

subtest 'form parses urlencoded' => sub {
    my $body = 'name=John%20Doe&email=john%40example.com&tags=perl&tags=async';
    my $scope = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', 'application/x-www-form-urlencoded']],
    };
    my $receive = mock_receive($body);
    my $req = PAGI::Request->new($scope, $receive);

    my $form = (async sub { await $req->form })->()->get;

    isa_ok($form, 'Hash::MultiValue', 'returns Hash::MultiValue');
    is($form->get('name'), 'John Doe', 'name decoded');
    is($form->get('email'), 'john@example.com', 'email decoded');

    my @tags = $form->get_all('tags');
    is_deeply(\@tags, ['perl', 'async'], 'multi-value works');
};

subtest 'form with UTF-8' => sub {
    my $body = 'message=%E4%BD%A0%E5%A5%BD';  # 你好 URL-encoded
    my $scope = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', 'application/x-www-form-urlencoded']],
    };
    my $receive = mock_receive($body);
    my $req = PAGI::Request->new($scope, $receive);

    my $form = (async sub { await $req->form })->()->get;

    is($form->get('message'), '你好', 'UTF-8 decoded');
};

subtest 'form caches result' => sub {
    my $call_count = 0;
    my $scope = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', 'application/x-www-form-urlencoded']],
    };
    my $receive = async sub {
        $call_count++;
        return { type => 'http.request', body => 'x=1', more => 0 };
    };
    my $req = PAGI::Request->new($scope, $receive);

    (async sub { await $req->form })->()->get;
    (async sub { await $req->form })->()->get;

    is($call_count, 1, 'receive only called once');
};

subtest 'empty form' => sub {
    my $scope = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', 'application/x-www-form-urlencoded']],
    };
    my $receive = mock_receive('');
    my $req = PAGI::Request->new($scope, $receive);

    my $form = (async sub { await $req->form })->()->get;

    isa_ok($form, 'Hash::MultiValue');
    is_deeply([$form->keys], [], 'empty form has no keys');
};

done_testing;
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/09-form.t`
Expected: FAIL - form method not implemented

**Step 3: Implement form parsing**

Add to `lib/PAGI/Request.pm`:
```perl
# Parse URL-encoded form body (async, returns Hash::MultiValue)
async sub form {
    my ($self, %opts) = @_;

    # Return cached if available
    return $self->{_form} if $self->{_form};

    # For multipart, delegate to uploads handling
    if ($self->is_multipart) {
        return await $self->_parse_multipart_form(%opts);
    }

    # URL-encoded form
    my $body = await $self->body;
    my @pairs;

    for my $part (split /&/, $body) {
        next unless length $part;
        my ($key, $val) = split /=/, $part, 2;
        $key //= '';
        $val //= '';

        # Decode + as space, then percent-decoding
        $key =~ s/\+/ /g;
        $val =~ s/\+/ /g;
        $key = decode_utf8(uri_unescape($key));
        $val = decode_utf8(uri_unescape($val));

        push @pairs, $key, $val;
    }

    $self->{_form} = Hash::MultiValue->new(@pairs);
    return $self->{_form};
}

# Placeholder for multipart - will be implemented in next task
async sub _parse_multipart_form {
    my ($self, %opts) = @_;
    die "Multipart form parsing not yet implemented";
}
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/09-form.t`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/09-form.t
git commit -m "feat(request): add URL-encoded form parsing

- form() parses application/x-www-form-urlencoded
- Returns Hash::MultiValue for multi-value support
- Decodes percent-encoding and UTF-8
- Cached after first parse"
```

---

## Task 11: PAGI::Request::Upload Class

**Files:**
- Create: `lib/PAGI/Request/Upload.pm`
- Create: `t/request/10-upload-class.t`

**Step 1: Create Upload class test file**

Create `t/request/10-upload-class.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;
use File::Temp qw(tempfile tempdir);
use Future::AsyncAwait;

use lib 'lib';
use PAGI::Request::Upload;

subtest 'upload from memory buffer' => sub {
    my $upload = PAGI::Request::Upload->new(
        field_name   => 'avatar',
        filename     => 'photo.jpg',
        content_type => 'image/jpeg',
        data         => 'fake image data here',
    );

    is($upload->field_name, 'avatar', 'field_name');
    is($upload->filename, 'photo.jpg', 'filename');
    is($upload->basename, 'photo.jpg', 'basename');
    is($upload->content_type, 'image/jpeg', 'content_type');
    is($upload->size, 20, 'size');
    ok(!$upload->is_empty, 'not empty');
    ok($upload->is_in_memory, 'is in memory');
    ok(!$upload->is_on_disk, 'not on disk');
    is($upload->slurp, 'fake image data here', 'slurp');
};

subtest 'upload from temp file' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my ($fh, $temp_path) = tempfile(DIR => $dir);
    print $fh "file content here";
    close $fh;

    my $upload = PAGI::Request::Upload->new(
        field_name   => 'document',
        filename     => 'report.pdf',
        content_type => 'application/pdf',
        temp_path    => $temp_path,
        size         => 17,
    );

    ok(!$upload->is_in_memory, 'not in memory');
    ok($upload->is_on_disk, 'is on disk');
    is($upload->temp_path, $temp_path, 'temp_path');
    is($upload->slurp, 'file content here', 'slurp from file');
};

subtest 'basename strips path' => sub {
    my $upload = PAGI::Request::Upload->new(
        field_name   => 'file',
        filename     => 'C:\Users\John\Documents\file.txt',
        content_type => 'text/plain',
        data         => 'x',
    );

    is($upload->basename, 'file.txt', 'Windows path stripped');

    my $upload2 = PAGI::Request::Upload->new(
        field_name   => 'file',
        filename     => '/home/john/photos/vacation.jpg',
        content_type => 'image/jpeg',
        data         => 'x',
    );

    is($upload2->basename, 'vacation.jpg', 'Unix path stripped');
};

subtest 'is_empty' => sub {
    my $empty = PAGI::Request::Upload->new(
        field_name   => 'file',
        filename     => '',
        content_type => 'application/octet-stream',
        data         => '',
    );

    ok($empty->is_empty, 'empty upload detected');
    is($empty->size, 0, 'size is 0');
};

subtest 'copy_to async' => sub {
    my $upload = PAGI::Request::Upload->new(
        field_name   => 'file',
        filename     => 'test.txt',
        content_type => 'text/plain',
        data         => 'test content 123',
    );

    my $dir = tempdir(CLEANUP => 1);
    my $dest = "$dir/copied.txt";

    (async sub { await $upload->copy_to($dest) })->()->get;

    ok(-f $dest, 'file created');
    open my $fh, '<', $dest;
    my $content = do { local $/; <$fh> };
    close $fh;
    is($content, 'test content 123', 'content matches');

    # Original still accessible
    is($upload->slurp, 'test content 123', 'original still readable');
};

subtest 'move_to async' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my ($fh, $temp_path) = tempfile(DIR => $dir);
    print $fh "moveable content";
    close $fh;

    my $upload = PAGI::Request::Upload->new(
        field_name   => 'file',
        filename     => 'doc.txt',
        content_type => 'text/plain',
        temp_path    => $temp_path,
        size         => 16,
    );

    my $dest = "$dir/moved.txt";
    (async sub { await $upload->move_to($dest) })->()->get;

    ok(-f $dest, 'destination exists');
    ok(!-f $temp_path, 'temp file removed');

    open $fh, '<', $dest;
    my $content = do { local $/; <$fh> };
    close $fh;
    is($content, 'moveable content', 'content correct');
};

subtest 'filehandle access' => sub {
    my $upload = PAGI::Request::Upload->new(
        field_name   => 'file',
        filename     => 'data.txt',
        content_type => 'text/plain',
        data         => "line1\nline2\nline3\n",
    );

    my $fh = $upload->fh;
    my @lines = <$fh>;
    is(scalar(@lines), 3, 'three lines');
    is($lines[0], "line1\n", 'first line');
};

done_testing;
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/10-upload-class.t`
Expected: FAIL - Can't locate PAGI/Request/Upload.pm

**Step 3: Create PAGI::Request::Upload module**

Create `lib/PAGI/Request/Upload.pm`:
```perl
package PAGI::Request::Upload;
use strict;
use warnings;

use Future::AsyncAwait;
use File::Copy qw(copy move);
use File::Basename qw(basename);
use IO::File;

sub new {
    my ($class, %args) = @_;

    my $self = bless {
        field_name   => $args{field_name},
        filename     => $args{filename} // '',
        content_type => $args{content_type} // 'application/octet-stream',
        temp_path    => $args{temp_path},
        data         => $args{data},
        size         => $args{size},
    }, $class;

    # Calculate size if not provided
    if (!defined $self->{size}) {
        if (defined $self->{data}) {
            $self->{size} = length($self->{data});
        } elsif ($self->{temp_path} && -f $self->{temp_path}) {
            $self->{size} = -s $self->{temp_path};
        } else {
            $self->{size} = 0;
        }
    }

    return $self;
}

# Accessors
sub field_name   { shift->{field_name} }
sub filename     { shift->{filename} }
sub content_type { shift->{content_type} }
sub size         { shift->{size} }
sub temp_path    { shift->{temp_path} }

# Basename strips directory path (handles both Unix and Windows paths)
sub basename {
    my $self = shift;
    my $name = $self->{filename} // '';
    # Handle Windows paths
    $name =~ s{.*\\}{};
    # Handle Unix paths
    $name =~ s{.*/}{};
    return $name;
}

# Predicates
sub is_empty {
    my $self = shift;
    return $self->{size} == 0;
}

sub is_in_memory {
    my $self = shift;
    return defined $self->{data};
}

sub is_on_disk {
    my $self = shift;
    return defined $self->{temp_path} && !defined $self->{data};
}

# Read entire content
sub slurp {
    my $self = shift;

    if (defined $self->{data}) {
        return $self->{data};
    }

    if ($self->{temp_path} && -f $self->{temp_path}) {
        open my $fh, '<:raw', $self->{temp_path}
            or die "Cannot open $self->{temp_path}: $!";
        local $/;
        my $content = <$fh>;
        close $fh;
        return $content;
    }

    return '';
}

# Get filehandle for reading
sub fh {
    my $self = shift;

    if (defined $self->{data}) {
        open my $fh, '<', \$self->{data};
        return $fh;
    }

    if ($self->{temp_path} && -f $self->{temp_path}) {
        open my $fh, '<:raw', $self->{temp_path}
            or die "Cannot open $self->{temp_path}: $!";
        return $fh;
    }

    # Empty filehandle
    my $empty = '';
    open my $fh, '<', \$empty;
    return $fh;
}

# Async copy to destination
async sub copy_to {
    my ($self, $dest_path) = @_;

    if (defined $self->{data}) {
        open my $fh, '>:raw', $dest_path
            or die "Cannot write to $dest_path: $!";
        print $fh $self->{data};
        close $fh;
    } elsif ($self->{temp_path}) {
        copy($self->{temp_path}, $dest_path)
            or die "Cannot copy to $dest_path: $!";
    }

    return $dest_path;
}

# Async move to destination (more efficient)
async sub move_to {
    my ($self, $dest_path) = @_;

    if (defined $self->{data}) {
        # Must write out
        await $self->copy_to($dest_path);
    } elsif ($self->{temp_path}) {
        # Try rename first (fast if same filesystem)
        unless (rename($self->{temp_path}, $dest_path)) {
            # Different filesystem - copy then delete
            copy($self->{temp_path}, $dest_path)
                or die "Cannot copy to $dest_path: $!";
            unlink $self->{temp_path};
        }
        $self->{temp_path} = undef;
    }

    return $dest_path;
}

# Alias for move_to
async sub save_to {
    my ($self, $dest_path) = @_;
    return await $self->move_to($dest_path);
}

# Explicitly discard temp file
sub discard {
    my $self = shift;
    if ($self->{temp_path} && -f $self->{temp_path}) {
        unlink $self->{temp_path};
        $self->{temp_path} = undef;
    }
}

# Cleanup temp file on destroy
sub DESTROY {
    my $self = shift;
    $self->discard;
}

1;

__END__

=head1 NAME

PAGI::Request::Upload - Represents an uploaded file

=head1 SYNOPSIS

    my $upload = await $req->upload('avatar');

    if (!$upload->is_empty) {
        my $safe_name = $upload->basename;
        $safe_name =~ s/[^\w.-]/_/g;

        await $upload->save_to("/uploads/$safe_name");
    }

=cut
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/10-upload-class.t`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request/Upload.pm t/request/10-upload-class.t
git commit -m "feat(request): add PAGI::Request::Upload class

- Handles both in-memory and temp file storage
- Metadata: field_name, filename, basename, content_type, size
- Predicates: is_empty, is_in_memory, is_on_disk
- Content access: slurp, fh
- Async persistence: copy_to, move_to, save_to
- Auto-cleanup of temp files on DESTROY"
```

---

## Task 12: Multipart Parser Wrapper

**Files:**
- Create: `lib/PAGI/Request/MultiPartHandler.pm`
- Create: `t/request/11-multipart-handler.t`
- Modify: `cpanfile`

**Step 1: Add HTTP::MultiPartParser to cpanfile**

Add to `cpanfile`:
```perl
requires 'HTTP::MultiPartParser', '0.02';
```

**Step 2: Create multipart handler test file**

Create `t/request/11-multipart-handler.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;
use Future::AsyncAwait;

use lib 'lib';
use PAGI::Request::MultiPartHandler;

# Helper to build multipart body
sub build_multipart {
    my ($boundary, @parts) = @_;
    my $body = '';
    for my $part (@parts) {
        $body .= "--$boundary\r\n";
        $body .= "Content-Disposition: form-data; name=\"$part->{name}\"";
        if ($part->{filename}) {
            $body .= "; filename=\"$part->{filename}\"";
        }
        $body .= "\r\n";
        if ($part->{content_type}) {
            $body .= "Content-Type: $part->{content_type}\r\n";
        }
        $body .= "\r\n";
        $body .= $part->{data};
        $body .= "\r\n";
    }
    $body .= "--$boundary--\r\n";
    return $body;
}

sub mock_receive {
    my ($body) = @_;
    my $sent = 0;
    return async sub {
        if (!$sent) {
            $sent = 1;
            return { type => 'http.request', body => $body, more => 0 };
        }
        return { type => 'http.disconnect' };
    };
}

subtest 'parse simple form fields' => sub {
    my $boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW';
    my $body = build_multipart($boundary,
        { name => 'title', data => 'Hello World' },
        { name => 'count', data => '42' },
    );

    my $receive = mock_receive($body);
    my $handler = PAGI::Request::MultiPartHandler->new(
        boundary => $boundary,
        receive  => $receive,
    );

    my ($form, $uploads) = (async sub { await $handler->parse })->()->get;

    isa_ok($form, 'Hash::MultiValue', 'form is Hash::MultiValue');
    is($form->get('title'), 'Hello World', 'title field');
    is($form->get('count'), '42', 'count field');
    is_deeply([$uploads->keys], [], 'no uploads');
};

subtest 'parse file upload' => sub {
    my $boundary = '----TestBoundary';
    my $body = build_multipart($boundary,
        { name => 'name', data => 'John' },
        {
            name         => 'avatar',
            filename     => 'photo.jpg',
            content_type => 'image/jpeg',
            data         => 'fake image bytes',
        },
    );

    my $receive = mock_receive($body);
    my $handler = PAGI::Request::MultiPartHandler->new(
        boundary => $boundary,
        receive  => $receive,
    );

    my ($form, $uploads) = (async sub { await $handler->parse })->()->get;

    is($form->get('name'), 'John', 'form field');

    my $upload = $uploads->get('avatar');
    isa_ok($upload, 'PAGI::Request::Upload', 'upload object');
    is($upload->filename, 'photo.jpg', 'filename');
    is($upload->content_type, 'image/jpeg', 'content_type');
    is($upload->slurp, 'fake image bytes', 'content');
};

subtest 'parse multiple files same field' => sub {
    my $boundary = '----Multi';
    my $body = build_multipart($boundary,
        { name => 'files', filename => 'a.txt', content_type => 'text/plain', data => 'AAA' },
        { name => 'files', filename => 'b.txt', content_type => 'text/plain', data => 'BBB' },
    );

    my $receive = mock_receive($body);
    my $handler = PAGI::Request::MultiPartHandler->new(
        boundary => $boundary,
        receive  => $receive,
    );

    my ($form, $uploads) = (async sub { await $handler->parse })->()->get;

    my @files = $uploads->get_all('files');
    is(scalar(@files), 2, 'two files');
    is($files[0]->filename, 'a.txt', 'first file');
    is($files[1]->filename, 'b.txt', 'second file');
};

done_testing;
```

**Step 3: Run test to verify it fails**

Run: `prove -l t/request/11-multipart-handler.t`
Expected: FAIL - Can't locate PAGI/Request/MultiPartHandler.pm

**Step 4: Create MultiPartHandler module**

Create `lib/PAGI/Request/MultiPartHandler.pm`:
```perl
package PAGI::Request::MultiPartHandler;
use strict;
use warnings;

use Future::AsyncAwait;
use HTTP::MultiPartParser;
use Hash::MultiValue;
use PAGI::Request::Upload;
use File::Temp qw(tempfile);

# Default limits
our $MAX_PART_SIZE    = 10 * 1024 * 1024;  # 10MB per part
our $SPOOL_THRESHOLD  = 64 * 1024;          # 64KB before spooling to disk
our $MAX_FILES        = 20;
our $MAX_FIELDS       = 1000;

sub new {
    my ($class, %args) = @_;

    return bless {
        boundary        => $args{boundary},
        receive         => $args{receive},
        max_part_size   => $args{max_part_size}   // $MAX_PART_SIZE,
        spool_threshold => $args{spool_threshold} // $SPOOL_THRESHOLD,
        max_files       => $args{max_files}       // $MAX_FILES,
        max_fields      => $args{max_fields}      // $MAX_FIELDS,
        temp_dir        => $args{temp_dir}        // $ENV{TMPDIR} // '/tmp',
    }, $class;
}

async sub parse {
    my $self = shift;

    my @form_pairs;
    my @upload_pairs;
    my $file_count = 0;
    my $field_count = 0;

    # Current part state
    my $current_headers;
    my $current_data = '';
    my $current_fh;
    my $current_temp_path;
    my $current_size = 0;

    my $finish_part = sub {
        return unless $current_headers;

        my $disposition = _parse_content_disposition($current_headers);
        my $name = $disposition->{name} // '';
        my $filename = $disposition->{filename};
        my $content_type = $current_headers->{'content-type'} // 'text/plain';

        if (defined $filename) {
            # File upload
            $file_count++;
            die "Too many files (max $self->{max_files})"
                if $file_count > $self->{max_files};

            my $upload;
            if ($current_fh) {
                close $current_fh;
                $upload = PAGI::Request::Upload->new(
                    field_name   => $name,
                    filename     => $filename,
                    content_type => $content_type,
                    temp_path    => $current_temp_path,
                    size         => $current_size,
                );
            } else {
                $upload = PAGI::Request::Upload->new(
                    field_name   => $name,
                    filename     => $filename,
                    content_type => $content_type,
                    data         => $current_data,
                );
            }
            push @upload_pairs, $name, $upload;
        } else {
            # Regular form field
            $field_count++;
            die "Too many fields (max $self->{max_fields})"
                if $field_count > $self->{max_fields};

            push @form_pairs, $name, $current_data;
        }

        # Reset state
        $current_headers = undef;
        $current_data = '';
        $current_fh = undef;
        $current_temp_path = undef;
        $current_size = 0;
    };

    my $parser = HTTP::MultiPartParser->new(
        boundary => $self->{boundary},

        on_header => sub {
            my ($headers) = @_;
            $finish_part->();  # Finish previous part if any

            # Parse headers into hash
            $current_headers = {};
            for my $line (split /\r?\n/, $headers) {
                if ($line =~ /^([^:]+):\s*(.*)$/) {
                    $current_headers->{lc($1)} = $2;
                }
            }
        },

        on_body => sub {
            my ($chunk) = @_;
            $current_size += length($chunk);

            die "Part too large (max $self->{max_part_size} bytes)"
                if $current_size > $self->{max_part_size};

            # Check if we need to spool to disk
            if (!$current_fh && $current_size > $self->{spool_threshold}) {
                # Spool to temp file
                ($current_fh, $current_temp_path) = tempfile(
                    DIR    => $self->{temp_dir},
                    UNLINK => 0,
                );
                binmode($current_fh);
                print $current_fh $current_data;
                $current_data = '';
            }

            if ($current_fh) {
                print $current_fh $chunk;
            } else {
                $current_data .= $chunk;
            }
        },

        on_error => sub {
            my ($error) = @_;
            die "Multipart parse error: $error";
        },
    );

    # Feed chunks from receive
    my $receive = $self->{receive};
    while (1) {
        my $message = await $receive->();
        last unless $message && $message->{type};
        last if $message->{type} eq 'http.disconnect';

        if (defined $message->{body} && length $message->{body}) {
            $parser->parse($message->{body});
        }

        last unless $message->{more};
    }

    $parser->finish;
    $finish_part->();  # Handle last part

    return (
        Hash::MultiValue->new(@form_pairs),
        Hash::MultiValue->new(@upload_pairs),
    );
}

sub _parse_content_disposition {
    my ($headers) = @_;
    my $cd = $headers->{'content-disposition'} // '';

    my %result;

    # Parse name="value" pairs
    while ($cd =~ /(\w+)="([^"]*)"/g) {
        $result{$1} = $2;
    }
    # Also handle unquoted values
    while ($cd =~ /(\w+)=([^;\s"]+)/g) {
        $result{$1} //= $2;
    }

    return \%result;
}

1;

__END__

=head1 NAME

PAGI::Request::MultiPartHandler - Async multipart/form-data parser

=head1 SYNOPSIS

    my $handler = PAGI::Request::MultiPartHandler->new(
        boundary => $boundary,
        receive  => $receive,
    );

    my ($form, $uploads) = await $handler->parse;

=cut
```

**Step 5: Run test to verify it passes**

Run: `prove -l t/request/11-multipart-handler.t`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request/MultiPartHandler.pm t/request/11-multipart-handler.t cpanfile
git commit -m "feat(request): add async multipart parser wrapper

- PAGI::Request::MultiPartHandler wraps HTTP::MultiPartParser
- Async integration with PAGI receive callback
- Spools large uploads to temp files (configurable threshold)
- Size and count limits for DoS protection
- Returns (form, uploads) as Hash::MultiValue"
```

---

## Task 13: Integrate Multipart into PAGI::Request

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Create: `t/request/12-uploads.t`

**Step 1: Create uploads integration test**

Create `t/request/12-uploads.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;
use Future::AsyncAwait;

use lib 'lib';
use PAGI::Request;

sub build_multipart {
    my ($boundary, @parts) = @_;
    my $body = '';
    for my $part (@parts) {
        $body .= "--$boundary\r\n";
        $body .= "Content-Disposition: form-data; name=\"$part->{name}\"";
        if ($part->{filename}) {
            $body .= "; filename=\"$part->{filename}\"";
        }
        $body .= "\r\n";
        if ($part->{content_type}) {
            $body .= "Content-Type: $part->{content_type}\r\n";
        }
        $body .= "\r\n";
        $body .= $part->{data};
        $body .= "\r\n";
    }
    $body .= "--$boundary--\r\n";
    return $body;
}

sub mock_receive {
    my ($body) = @_;
    my $sent = 0;
    return async sub {
        if (!$sent) {
            $sent = 1;
            return { type => 'http.request', body => $body, more => 0 };
        }
        return { type => 'http.disconnect' };
    };
}

subtest 'uploads() returns Hash::MultiValue of Upload objects' => sub {
    my $boundary = '----Test';
    my $body = build_multipart($boundary,
        { name => 'title', data => 'My Document' },
        { name => 'file', filename => 'doc.pdf', content_type => 'application/pdf', data => 'PDF data' },
    );

    my $scope = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', "multipart/form-data; boundary=$boundary"]],
    };
    my $receive = mock_receive($body);
    my $req = PAGI::Request->new($scope, $receive);

    my $uploads = (async sub { await $req->uploads })->()->get;

    isa_ok($uploads, 'Hash::MultiValue');
    my $file = $uploads->get('file');
    isa_ok($file, 'PAGI::Request::Upload');
    is($file->filename, 'doc.pdf');
};

subtest 'upload() shortcut for single file' => sub {
    my $boundary = '----Test';
    my $body = build_multipart($boundary,
        { name => 'avatar', filename => 'me.jpg', content_type => 'image/jpeg', data => 'JPEG' },
    );

    my $scope = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', "multipart/form-data; boundary=$boundary"]],
    };
    my $receive = mock_receive($body);
    my $req = PAGI::Request->new($scope, $receive);

    my $avatar = (async sub { await $req->upload('avatar') })->()->get;

    isa_ok($avatar, 'PAGI::Request::Upload');
    is($avatar->filename, 'me.jpg');

    my $missing = (async sub { await $req->upload('nonexistent') })->()->get;
    is($missing, undef, 'missing upload returns undef');
};

subtest 'form() works with multipart' => sub {
    my $boundary = '----Test';
    my $body = build_multipart($boundary,
        { name => 'name', data => 'John' },
        { name => 'email', data => 'john@example.com' },
        { name => 'photo', filename => 'pic.jpg', content_type => 'image/jpeg', data => 'IMG' },
    );

    my $scope = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', "multipart/form-data; boundary=$boundary"]],
    };
    my $receive = mock_receive($body);
    my $req = PAGI::Request->new($scope, $receive);

    my $form = (async sub { await $req->form })->()->get;

    is($form->get('name'), 'John', 'form field from multipart');
    is($form->get('email'), 'john@example.com', 'another form field');
    is($form->get('photo'), undef, 'file not in form');
};

subtest 'upload_all() for multiple files' => sub {
    my $boundary = '----Test';
    my $body = build_multipart($boundary,
        { name => 'docs', filename => 'a.pdf', content_type => 'application/pdf', data => 'A' },
        { name => 'docs', filename => 'b.pdf', content_type => 'application/pdf', data => 'B' },
        { name => 'docs', filename => 'c.pdf', content_type => 'application/pdf', data => 'C' },
    );

    my $scope = {
        type    => 'http',
        method  => 'POST',
        headers => [['content-type', "multipart/form-data; boundary=$boundary"]],
    };
    my $receive = mock_receive($body);
    my $req = PAGI::Request->new($scope, $receive);

    my @docs = (async sub { await $req->upload_all('docs') })->()->get;

    is(scalar(@docs), 3, 'three uploads');
    is($docs[0]->filename, 'a.pdf');
    is($docs[1]->filename, 'b.pdf');
    is($docs[2]->filename, 'c.pdf');
};

done_testing;
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/12-uploads.t`
Expected: FAIL - uploads method not working

**Step 3: Implement uploads integration**

Add to `lib/PAGI/Request.pm`:
```perl
use PAGI::Request::MultiPartHandler;
use PAGI::Request::Upload;
```

Replace `_parse_multipart_form` and add upload methods:
```perl
# Parse multipart form (internal)
async sub _parse_multipart_form {
    my ($self, %opts) = @_;

    # Already parsed?
    return $self->{_form} if $self->{_form} && $self->{_uploads};

    # Extract boundary from content-type
    my $ct = $self->header('content-type') // '';
    my ($boundary) = $ct =~ /boundary=([^;\s]+)/;
    $boundary =~ s/^["']|["']$//g if $boundary;  # Strip quotes

    die "No boundary found in Content-Type" unless $boundary;

    my $handler = PAGI::Request::MultiPartHandler->new(
        boundary        => $boundary,
        receive         => $self->{receive},
        max_part_size   => $opts{max_part_size},
        spool_threshold => $opts{spool_threshold},
        max_files       => $opts{max_files},
        max_fields      => $opts{max_fields},
        temp_dir        => $opts{temp_dir},
    );

    my ($form, $uploads) = await $handler->parse;

    $self->{_form} = $form;
    $self->{_uploads} = $uploads;
    $self->{_body_read} = 1;  # Body has been consumed

    return $form;
}

# Get all uploads as Hash::MultiValue
async sub uploads {
    my ($self, %opts) = @_;

    return $self->{_uploads} if $self->{_uploads};

    if ($self->is_multipart) {
        await $self->_parse_multipart_form(%opts);
        return $self->{_uploads};
    }

    # Not multipart - return empty
    $self->{_uploads} = Hash::MultiValue->new();
    return $self->{_uploads};
}

# Get single upload by field name
async sub upload {
    my ($self, $name, %opts) = @_;
    my $uploads = await $self->uploads(%opts);
    return $uploads->get($name);
}

# Get all uploads for a field name
async sub upload_all {
    my ($self, $name, %opts) = @_;
    my $uploads = await $self->uploads(%opts);
    return $uploads->get_all($name);
}
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/12-uploads.t`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/12-uploads.t
git commit -m "feat(request): integrate multipart uploads into Request

- uploads() returns Hash::MultiValue of Upload objects
- upload() shortcut for single file
- upload_all() for multiple files with same name
- form() works with both urlencoded and multipart
- Configurable limits passed through to handler"
```

---

## Task 14: is_disconnected Check

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Modify: `t/request/04-predicates.t`

**Step 1: Add is_disconnected test**

Add to `t/request/04-predicates.t` before `done_testing`:
```perl
subtest 'is_disconnected' => sub {
    my $scope = { type => 'http', method => 'GET', headers => [] };

    # Test with client still connected
    my $connected_receive = async sub {
        return { type => 'http.request', body => '', more => 1 };
    };
    my $req1 = PAGI::Request->new($scope, $connected_receive);
    my $disconnected1 = (async sub { await $req1->is_disconnected })->()->get;
    ok(!$disconnected1, 'client connected');

    # Test with disconnected client
    my $disconnected_receive = async sub {
        return { type => 'http.disconnect' };
    };
    my $req2 = PAGI::Request->new($scope, $disconnected_receive);
    my $disconnected2 = (async sub { await $req2->is_disconnected })->()->get;
    ok($disconnected2, 'client disconnected');
};
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/04-predicates.t`
Expected: FAIL - is_disconnected not implemented

**Step 3: Implement is_disconnected**

Add to `lib/PAGI/Request.pm`:
```perl
# Check if client has disconnected (async)
async sub is_disconnected {
    my $self = shift;

    return 0 unless $self->{receive};

    # Peek at receive - if we get disconnect, client is gone
    my $message = await $self->{receive}->();

    if ($message && $message->{type} eq 'http.disconnect') {
        return 1;
    }

    return 0;
}
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/04-predicates.t`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/04-predicates.t
git commit -m "feat(request): add is_disconnected check

- Async method to check if client is still connected
- Useful for long-running operations"
```

---

## Task 15: Class-Level Configuration

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Create: `t/request/13-config.t`

**Step 1: Create configuration test**

Create `t/request/13-config.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;

use lib 'lib';
use PAGI::Request;

subtest 'default configuration' => sub {
    my $config = PAGI::Request->config;

    is(ref($config), 'HASH', 'config returns hashref');
    ok($config->{max_body_size} > 0, 'has max_body_size');
    ok($config->{spool_threshold} > 0, 'has spool_threshold');
};

subtest 'configure class defaults' => sub {
    # Save original
    my $original = { %{PAGI::Request->config} };

    PAGI::Request->configure(
        max_body_size   => 5 * 1024 * 1024,
        spool_threshold => 128 * 1024,
    );

    my $config = PAGI::Request->config;
    is($config->{max_body_size}, 5 * 1024 * 1024, 'max_body_size updated');
    is($config->{spool_threshold}, 128 * 1024, 'spool_threshold updated');

    # Restore
    PAGI::Request->configure(%$original);
};

done_testing;
```

**Step 2: Run test to verify it fails**

Run: `prove -l t/request/13-config.t`
Expected: FAIL - config, configure not implemented

**Step 3: Implement class configuration**

Add to `lib/PAGI/Request.pm` near top after `use` statements:
```perl
# Class-level configuration defaults
our %CONFIG = (
    max_body_size   => 10 * 1024 * 1024,   # 10MB
    max_upload_size => 10 * 1024 * 1024,   # 10MB per file
    max_files       => 20,
    max_fields      => 1000,
    spool_threshold => 64 * 1024,           # 64KB
    temp_dir        => $ENV{TMPDIR} // '/tmp',
);

sub configure {
    my ($class, %opts) = @_;
    for my $key (keys %opts) {
        $CONFIG{$key} = $opts{$key} if exists $CONFIG{$key};
    }
}

sub config {
    my $class = shift;
    return \%CONFIG;
}
```

**Step 4: Run test to verify it passes**

Run: `prove -l t/request/13-config.t`
Expected: All tests pass

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm t/request/13-config.t
git commit -m "feat(request): add class-level configuration

- PAGI::Request->configure() sets defaults
- PAGI::Request->config() returns current config
- Configurable: max_body_size, max_upload_size, max_files, etc."
```

---

## Task 16: Documentation

**Files:**
- Modify: `lib/PAGI/Request.pm`
- Modify: `lib/PAGI/Request/Upload.pm`

**Step 1: Add comprehensive POD to PAGI::Request**

Update `lib/PAGI/Request.pm` `__END__` section:
```perl
__END__

=head1 NAME

PAGI::Request - Convenience wrapper for PAGI request scope

=head1 SYNOPSIS

    use PAGI::Request;
    use Future::AsyncAwait;

    async sub app {
        my ($scope, $receive, $send) = @_;
        my $req = PAGI::Request->new($scope, $receive);

        # Basic properties
        my $method = $req->method;        # GET, POST, etc.
        my $path   = $req->path;          # /users/42
        my $host   = $req->host;          # example.com

        # Query parameters (Hash::MultiValue)
        my $page = $req->query('page');
        my @tags = $req->query_params->get_all('tags');

        # Headers
        my $ct = $req->content_type;
        my $auth = $req->header('authorization');

        # Cookies
        my $session = $req->cookie('session');

        # Body parsing (async)
        my $json = await $req->json;      # Parse JSON body
        my $form = await $req->form;      # Parse form data

        # File uploads (async)
        my $avatar = await $req->upload('avatar');
        if ($avatar && !$avatar->is_empty) {
            await $avatar->save_to('/uploads/avatar.jpg');
        }

        # Auth helpers
        my $token = $req->bearer_token;
        my ($user, $pass) = $req->basic_auth;

        # Per-request storage
        $req->stash->{user} = $current_user;
    }

=head1 DESCRIPTION

PAGI::Request provides a friendly interface to PAGI request data. It wraps
the raw C<$scope> hashref and C<$receive> callback with convenient methods
for accessing headers, query parameters, cookies, request body, and file
uploads.

This is an optional convenience layer. Raw PAGI applications continue to
work with C<$scope> and C<$receive> directly.

=head1 CLASS METHODS

=head2 configure

    PAGI::Request->configure(
        max_body_size   => 10 * 1024 * 1024,  # 10MB
        spool_threshold => 64 * 1024,          # 64KB
    );

Set class-level defaults for body/upload handling.

=head2 config

    my $config = PAGI::Request->config;

Returns the current configuration hashref.

=head1 CONSTRUCTOR

=head2 new

    my $req = PAGI::Request->new($scope, $receive);

Creates a new request object. C<$scope> is required. C<$receive> is optional
but required for body/upload methods.

=head1 PROPERTIES

=head2 method

HTTP method (GET, POST, PUT, etc.)

=head2 path

Request path, UTF-8 decoded.

=head2 raw_path

Request path as raw bytes (percent-encoded).

=head2 query_string

Raw query string (without leading ?).

=head2 scheme

C<http> or C<https>.

=head2 host

Host from the Host header.

=head2 client

Arrayref of C<[host, port]> or undef.

=head2 content_type

Content-Type header value (without parameters).

=head2 content_length

Content-Length header value.

=head1 HEADER METHODS

=head2 header

    my $value = $req->header('Content-Type');

Get a single header value (case-insensitive). Returns the last value if
the header appears multiple times.

=head2 header_all

    my @values = $req->header_all('Accept');

Get all values for a header.

=head2 headers

    my $headers = $req->headers;  # Hash::MultiValue

Get all headers as a L<Hash::MultiValue> object.

=head1 QUERY PARAMETERS

=head2 query_params

    my $params = $req->query_params;  # Hash::MultiValue

Get query parameters as L<Hash::MultiValue>.

=head2 query

    my $value = $req->query('page');

Shortcut for C<< $req->query_params->get($name) >>.

=head1 PATH PARAMETERS

=head2 params

    my $params = $req->params;  # hashref

Get path parameters (set by router).

=head2 param

    my $id = $req->param('id');

Get a single path parameter.

=head2 set_params

    $req->set_params({ id => 42 });

Set path parameters (called by router).

=head1 COOKIES

=head2 cookies

    my $cookies = $req->cookies;  # hashref

Get all cookies.

=head2 cookie

    my $session = $req->cookie('session');

Get a single cookie value.

=head1 BODY METHODS (ASYNC)

=head2 body

    my $bytes = await $req->body;

Read raw body bytes. Cached after first read.

=head2 text

    my $text = await $req->text;

Read body as UTF-8 decoded text.

=head2 json

    my $data = await $req->json;

Parse body as JSON. Dies on parse error.

=head2 form

    my $form = await $req->form;  # Hash::MultiValue

Parse URL-encoded or multipart form data.

=head1 UPLOAD METHODS (ASYNC)

=head2 uploads

    my $uploads = await $req->uploads;  # Hash::MultiValue

Get all uploads as L<Hash::MultiValue> of L<PAGI::Request::Upload> objects.

=head2 upload

    my $file = await $req->upload('avatar');

Get a single upload by field name.

=head2 upload_all

    my @files = await $req->upload_all('photos');

Get all uploads for a field name.

=head1 PREDICATES

=head2 is_get, is_post, is_put, is_patch, is_delete, is_head, is_options

    if ($req->is_post) { ... }

Check HTTP method.

=head2 is_json

True if Content-Type is C<application/json>.

=head2 is_form

True if Content-Type is form-urlencoded or multipart.

=head2 is_multipart

True if Content-Type is C<multipart/form-data>.

=head2 accepts

    if ($req->accepts('text/html')) { ... }

Check Accept header (supports wildcards).

=head2 is_disconnected (async)

    if (await $req->is_disconnected) { ... }

Check if client has disconnected.

=head1 AUTH HELPERS

=head2 bearer_token

    my $token = $req->bearer_token;

Extract Bearer token from Authorization header.

=head2 basic_auth

    my ($user, $pass) = $req->basic_auth;

Decode Basic auth credentials.

=head1 STATE

=head2 stash

    $req->stash->{user} = $user;
    my $user = $req->stash->{user};

Per-request hashref for middleware to store data.

=head1 SEE ALSO

L<PAGI::Request::Upload>, L<Hash::MultiValue>

=cut
```

**Step 2: Verify POD syntax**

Run: `podchecker lib/PAGI/Request.pm`
Expected: No errors

**Step 3: Add comprehensive POD to Upload.pm**

Update `lib/PAGI/Request/Upload.pm` `__END__` section with full documentation.

**Step 4: Verify Upload POD syntax**

Run: `podchecker lib/PAGI/Request/Upload.pm`
Expected: No errors

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/PAGI/Request.pm lib/PAGI/Request/Upload.pm
git commit -m "docs(request): add comprehensive POD documentation

- Full API documentation for PAGI::Request
- Full API documentation for PAGI::Request::Upload
- Usage examples and method descriptions"
```

---

## Task 17: Example Application - Contact Form

**Files:**
- Create: `examples/13-contact-form/app.pl`
- Create: `examples/13-contact-form/public/index.html`

**Step 1: Create example directory structure**

Run: `mkdir -p examples/13-contact-form/public examples/13-contact-form/uploads`

**Step 2: Create HTML form**

Create `examples/13-contact-form/public/index.html`:
```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Contact Form - PAGI::Request Demo</title>
    <style>
        body { font-family: sans-serif; max-width: 600px; margin: 2em auto; padding: 0 1em; }
        label { display: block; margin-top: 1em; font-weight: bold; }
        input, textarea, select { width: 100%; padding: 0.5em; margin-top: 0.25em; }
        input[type="file"] { padding: 0.25em 0; }
        button { margin-top: 1.5em; padding: 0.75em 2em; background: #007bff; color: white; border: none; cursor: pointer; }
        button:hover { background: #0056b3; }
        .error { color: #dc3545; background: #f8d7da; padding: 0.75em; margin-top: 1em; border-radius: 4px; }
        .success { color: #155724; background: #d4edda; padding: 0.75em; margin-top: 1em; border-radius: 4px; }
        .info { color: #666; font-size: 0.9em; margin-top: 0.25em; }
    </style>
</head>
<body>
    <h1>Contact Form</h1>
    <p>This example demonstrates PAGI::Request with form handling and file uploads.</p>

    <form method="POST" action="/submit" enctype="multipart/form-data">
        <label for="name">Name *</label>
        <input type="text" id="name" name="name" required>

        <label for="email">Email *</label>
        <input type="email" id="email" name="email" required>

        <label for="subject">Subject</label>
        <select id="subject" name="subject">
            <option value="general">General Inquiry</option>
            <option value="support">Technical Support</option>
            <option value="feedback">Feedback</option>
        </select>

        <label for="message">Message *</label>
        <textarea id="message" name="message" rows="5" required></textarea>

        <label for="attachment">Attachment (optional)</label>
        <input type="file" id="attachment" name="attachment">
        <p class="info">Max 5MB. Allowed: PDF, images, text files.</p>

        <label>
            <input type="checkbox" name="subscribe" value="yes">
            Subscribe to newsletter
        </label>

        <button type="submit">Send Message</button>
    </form>
</body>
</html>
```

**Step 3: Create app.pl**

Create `examples/13-contact-form/app.pl`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;

use Future::AsyncAwait;
use File::Basename qw(dirname);
use File::Spec;
use Encode qw(encode_utf8);
use JSON::PP qw(encode_json);

use lib 'lib';
use PAGI::Request;

# Configure upload limits
PAGI::Request->configure(
    max_upload_size => 5 * 1024 * 1024,  # 5MB
    spool_threshold => 64 * 1024,
);

my $PUBLIC_DIR = File::Spec->catdir(dirname(__FILE__), 'public');
my $UPLOAD_DIR = File::Spec->catdir(dirname(__FILE__), 'uploads');

# Allowed MIME types for attachments
my %ALLOWED_TYPES = (
    'application/pdf' => 'pdf',
    'image/jpeg'      => 'jpg',
    'image/png'       => 'png',
    'image/gif'       => 'gif',
    'text/plain'      => 'txt',
);

my $app = async sub {
    my ($scope, $receive, $send) = @_;

    return await _handle_lifespan($scope, $receive, $send)
        if $scope->{type} eq 'lifespan';

    die "Unsupported: $scope->{type}" unless $scope->{type} eq 'http';

    my $req = PAGI::Request->new($scope, $receive);
    my $path = $req->path;
    my $method = $req->method;

    # Route: GET / - serve form
    if ($method eq 'GET' && $path eq '/') {
        return await _serve_file($send, "$PUBLIC_DIR/index.html", 'text/html');
    }

    # Route: POST /submit - handle form
    if ($method eq 'POST' && $path eq '/submit') {
        return await _handle_submit($req, $send);
    }

    # 404
    return await _send_error($send, 404, 'Not Found');
};

async sub _handle_submit {
    my ($req, $send) = @_;

    my $form = await $req->form;
    my @errors;

    # Validate required fields
    my $name = $form->get('name') // '';
    my $email = $form->get('email') // '';
    my $message = $form->get('message') // '';
    my $subject = $form->get('subject') // 'general';
    my $subscribe = $form->get('subscribe') // '';

    push @errors, 'Name is required' unless length $name;
    push @errors, 'Email is required' unless length $email;
    push @errors, 'Invalid email format' unless $email =~ /@/;
    push @errors, 'Message is required' unless length $message;

    # Handle file upload
    my $attachment = await $req->upload('attachment');
    my $saved_file;

    if ($attachment && !$attachment->is_empty) {
        my $ct = $attachment->content_type;
        my $size = $attachment->size;

        # Validate type
        unless (exists $ALLOWED_TYPES{$ct}) {
            push @errors, "File type not allowed: $ct";
        }

        # Validate size (already enforced by Request, but double-check)
        if ($size > 5 * 1024 * 1024) {
            push @errors, "File too large (max 5MB)";
        }

        # Save file if valid
        unless (@errors) {
            my $ext = $ALLOWED_TYPES{$ct} // 'bin';
            my $safe_name = time() . '-' . int(rand(10000)) . ".$ext";
            my $dest = "$UPLOAD_DIR/$safe_name";

            eval {
                await $attachment->save_to($dest);
                $saved_file = $safe_name;
            };
            push @errors, "Failed to save file: $@" if $@;
        }
    }

    # Return errors if any
    if (@errors) {
        return await _send_json($send, 400, {
            success => 0,
            errors  => \@errors,
        });
    }

    # Success response
    my $response = {
        success => 1,
        message => 'Thank you for your message!',
        data    => {
            name      => $name,
            email     => $email,
            subject   => $subject,
            message   => substr($message, 0, 100) . (length($message) > 100 ? '...' : ''),
            subscribe => ($subscribe eq 'yes' ? 1 : 0),
            attachment => $saved_file,
        },
    };

    return await _send_json($send, 200, $response);
}

async sub _serve_file {
    my ($send, $path, $content_type) = @_;

    open my $fh, '<:raw', $path or return await _send_error($send, 404, 'Not Found');
    local $/;
    my $content = <$fh>;
    close $fh;

    await $send->({
        type    => 'http.response.start',
        status  => 200,
        headers => [
            ['content-type', $content_type],
            ['content-length', length($content)],
        ],
    });
    await $send->({
        type => 'http.response.body',
        body => $content,
        more => 0,
    });
}

async sub _send_json {
    my ($send, $status, $data) = @_;

    my $body = encode_json($data);

    await $send->({
        type    => 'http.response.start',
        status  => $status,
        headers => [
            ['content-type', 'application/json'],
            ['content-length', length($body)],
        ],
    });
    await $send->({
        type => 'http.response.body',
        body => $body,
        more => 0,
    });
}

async sub _send_error {
    my ($send, $status, $message) = @_;
    return await _send_json($send, $status, { error => $message });
}

async sub _handle_lifespan {
    my ($scope, $receive, $send) = @_;

    while (1) {
        my $event = await $receive->();
        if ($event->{type} eq 'lifespan.startup') {
            # Ensure upload directory exists
            mkdir $UPLOAD_DIR unless -d $UPLOAD_DIR;
            print STDERR "[lifespan] Contact form app started\n";
            print STDERR "[lifespan] Upload directory: $UPLOAD_DIR\n";
            await $send->({ type => 'lifespan.startup.complete' });
        }
        elsif ($event->{type} eq 'lifespan.shutdown') {
            print STDERR "[lifespan] Shutting down\n";
            await $send->({ type => 'lifespan.shutdown.complete' });
            last;
        }
    }
}

$app;

__END__

=head1 NAME

Contact Form Example - PAGI::Request Demo

=head1 SYNOPSIS

    pagi-server examples/13-contact-form/app.pl --port 5000

Then visit http://localhost:5000/

=head1 DESCRIPTION

Demonstrates PAGI::Request features:

=over

=item * Form parsing with validation

=item * File upload handling

=item * Content-type validation

=item * JSON responses

=back

=cut
```

**Step 4: Test the example runs**

Run: `perl -c examples/13-contact-form/app.pl`
Expected: "examples/13-contact-form/app.pl syntax OK"

**Step 5: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 6: Commit**

```bash
git add examples/13-contact-form/
git commit -m "feat(examples): add contact form example

Demonstrates PAGI::Request features:
- Form parsing with Hash::MultiValue
- File upload with validation
- Content-type checking
- JSON responses
- Error handling"
```

---

## Task 18: Integration Test

**Files:**
- Create: `t/request/14-integration.t`

**Step 1: Create integration test**

Create `t/request/14-integration.t`:
```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;
use Future::AsyncAwait;
use IO::Async::Loop;
use Net::Async::HTTP;

use lib 'lib';
use PAGI::Server;
use PAGI::Request;

# Skip if not running integration tests
plan skip_all => 'Set INTEGRATION_TEST=1 to run' unless $ENV{INTEGRATION_TEST};

my $loop = IO::Async::Loop->new;

subtest 'full request/response cycle with PAGI::Request' => sub {
    my $app = async sub {
        my ($scope, $receive, $send) = @_;

        if ($scope->{type} eq 'lifespan') {
            while (1) {
                my $event = await $receive->();
                if ($event->{type} eq 'lifespan.startup') {
                    await $send->({ type => 'lifespan.startup.complete' });
                }
                elsif ($event->{type} eq 'lifespan.shutdown') {
                    await $send->({ type => 'lifespan.shutdown.complete' });
                    last;
                }
            }
            return;
        }

        my $req = PAGI::Request->new($scope, $receive);

        my $response = {
            method       => $req->method,
            path         => $req->path,
            content_type => $req->content_type,
            is_json      => $req->is_json ? 1 : 0,
            query        => $req->query('foo'),
        };

        if ($req->is_post && $req->is_json) {
            my $json = await $req->json;
            $response->{body} = $json;
        }

        my $body = JSON::PP::encode_json($response);

        await $send->({
            type    => 'http.response.start',
            status  => 200,
            headers => [['content-type', 'application/json']],
        });
        await $send->({
            type => 'http.response.body',
            body => $body,
            more => 0,
        });
    };

    my $server = PAGI::Server->new(
        app   => $app,
        port  => 0,
        quiet => 1,
    );
    $loop->add($server);
    $server->listen->get;

    my $port = $server->port;
    my $http = Net::Async::HTTP->new;
    $loop->add($http);

    # Test GET with query params
    my $res1 = $http->GET("http://127.0.0.1:$port/test?foo=bar")->get;
    is($res1->code, 200);
    my $data1 = JSON::PP::decode_json($res1->content);
    is($data1->{method}, 'GET');
    is($data1->{path}, '/test');
    is($data1->{query}, 'bar');

    # Test POST with JSON body
    my $req2 = HTTP::Request->new(
        POST => "http://127.0.0.1:$port/api",
        ['Content-Type' => 'application/json'],
        '{"name":"John","age":30}',
    );
    my $res2 = $http->do_request(request => $req2)->get;
    is($res2->code, 200);
    my $data2 = JSON::PP::decode_json($res2->content);
    is($data2->{is_json}, 1);
    is_deeply($data2->{body}, { name => 'John', age => 30 });

    $server->shutdown->get;
    $loop->remove($server);
    $loop->remove($http);
};

done_testing;
```

**Step 2: Run integration test (optional)**

Run: `INTEGRATION_TEST=1 prove -l t/request/14-integration.t`
Expected: All tests pass

**Step 3: Run full test suite (skips integration by default)**

Run: `prove -l t/`
Expected: All tests pass

**Step 4: Update MANIFEST.SKIP if needed**

Ensure test files are properly included.

**Step 5: Final verification**

Run: `prove -l t/request/`
Expected: All Request tests pass

**Step 6: Commit**

```bash
git add t/request/14-integration.t
git commit -m "test(request): add integration test

- Tests PAGI::Request with real PAGI::Server
- Covers GET with query params
- Covers POST with JSON body
- Skipped by default (INTEGRATION_TEST=1 to run)"
```

---

## Task 19: Final Cleanup and Summary

**Files:**
- Modify: `lib/PAGI.pm` (add mention of PAGI::Request)
- Run final tests

**Step 1: Update PAGI.pm to mention Request**

Add to `lib/PAGI.pm` in the SEE ALSO section:
```perl
=item * L<PAGI::Request> - Convenience wrapper for request handling
```

**Step 2: Run full test suite**

Run: `prove -l t/`
Expected: All tests pass

**Step 3: Check POD**

Run: `podchecker lib/PAGI/Request.pm lib/PAGI/Request/Upload.pm lib/PAGI/Request/MultiPartHandler.pm`
Expected: No errors

**Step 4: Verify example syntax**

Run: `perl -c examples/13-contact-form/app.pl`
Expected: Syntax OK

**Step 5: Git status check**

Run: `git status`
Expected: Working tree clean or only expected changes

**Step 6: Final commit**

```bash
git add lib/PAGI.pm
git commit -m "docs: add PAGI::Request to PAGI.pm SEE ALSO

Completes PAGI::Request implementation:
- PAGI::Request for convenient request handling
- PAGI::Request::Upload for file uploads
- PAGI::Request::MultiPartHandler for multipart parsing
- Full test coverage
- Contact form example"
```

---

## Summary

This plan implements PAGI::Request with:

1. **Core Properties** (Tasks 1-2): method, path, headers, etc.
2. **Query/Form Params** (Tasks 3, 10): Hash::MultiValue support
3. **Cookies** (Task 4): Using Cookie::Baker
4. **Predicates** (Tasks 5, 14): is_json, is_form, accepts, is_disconnected
5. **Auth Helpers** (Task 6): bearer_token, basic_auth
6. **State** (Task 7): Per-request stash
7. **Path Params** (Task 8): Router integration
8. **Body Reading** (Task 9): Async body, text, json
9. **File Uploads** (Tasks 11-13): Upload class, multipart handler
10. **Configuration** (Task 15): Class-level defaults
11. **Documentation** (Task 16): Comprehensive POD
12. **Example** (Task 17): Contact form with uploads
13. **Integration Test** (Task 18): Full cycle test

**Total: 19 tasks with 6+ steps each**
