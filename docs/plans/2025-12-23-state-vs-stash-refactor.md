# State vs Stash Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Clean separation of worker-level state from request-level stash, with stash living in scope for automatic flow through middleware and subrouters.

**Architecture:**
- `$self->state` - per-worker instance state (router level, isolated per worker)
- `$req->stash` / `$ws->stash` / `$sse->stash` - per-request, lives in `$scope->{'pagi.stash'}`, shared across all handlers/middleware/subrouters in the request chain
- No automatic copying of state to stash - completely independent

**Key Simplifications:**
- Remove `set()` / `get()` methods - just use `stash`
- Remove `set_stash()` methods - stash auto-creates in scope
- Stash flows naturally through shallow copies to subrouters

**Tech Stack:** Perl, PAGI framework

---

## Task 1: Update PAGI::Request to use scope-based stash

**Files:**
- Modify: `lib/PAGI/Request.pm`

**Step 1: Change stash() to read/write from scope**

```perl
sub stash {
    my ($self) = @_;
    return $self->{scope}{'pagi.stash'} //= {};
}
```

**Step 2: Remove set_stash() method**

Delete the `set_stash` method entirely - no longer needed.

**Step 3: Remove set() and get() methods**

Delete these methods - stash handles all request-scoped data sharing now.

**Step 4: Update POD to reflect changes**

Remove documentation for removed methods, update stash docs.

**Step 5: Verify syntax**

Run: `perl -Ilib -c lib/PAGI/Request.pm`

---

## Task 2: Update PAGI::WebSocket to use scope-based stash

**Files:**
- Modify: `lib/PAGI/WebSocket.pm`

**Step 1: Change stash() to read/write from scope**

```perl
sub stash {
    my ($self) = @_;
    return $self->{scope}{'pagi.stash'} //= {};
}
```

**Step 2: Remove set_stash() method and _stash attribute**

- Remove `set_stash` method
- Remove `_stash => {}` from constructor

**Step 3: Update POD**

**Step 4: Verify syntax**

Run: `perl -Ilib -c lib/PAGI/WebSocket.pm`

---

## Task 3: Update PAGI::SSE to use scope-based stash

**Files:**
- Modify: `lib/PAGI/SSE.pm`

**Step 1: Change stash() to read/write from scope**

```perl
sub stash {
    my ($self) = @_;
    return $self->{scope}{'pagi.stash'} //= {};
}
```

**Step 2: Remove set_stash() method and _stash attribute**

- Remove `set_stash` method
- Remove `_stash => {}` from constructor

**Step 3: Update POD**

**Step 4: Verify syntax**

Run: `perl -Ilib -c lib/PAGI/SSE.pm`

---

## Task 4: Rename Router stash to state and remove copying

**Files:**
- Modify: `lib/PAGI/Endpoint/Router.pm`

**Step 1: Rename _stash to _state and stash() to state()**

```perl
sub new {
    my ($class, %args) = @_;
    return bless {
        _state => {},  # Changed from _stash
    }, $class;
}

sub state {
    my ($self) = @_;
    return $self->{_state} //= {};
}
```

**Step 2: Remove the scope stash copying in to_app**

Remove this block entirely:
```perl
# REMOVE:
$scope->{'pagi.stash'} = {
    %{$scope->{'pagi.stash'} // {}},
    %{$instance->stash},
};
```

**Step 3: Remove stash copying in handler wrappers**

Remove all instances of:
```perl
# REMOVE from HTTP wrapper:
$req->set_stash($scope->{'pagi.stash'} // {});

# REMOVE from WebSocket wrapper:
my $router_stash = $scope->{'pagi.stash'} // {};
for my $key (keys %$router_stash) {
    $ws->stash->{$key} = $router_stash->{$key};
}

# REMOVE from SSE wrapper:
my $router_stash = $scope->{'pagi.stash'} // {};
for my $key (keys %$router_stash) {
    $sse->stash->{$key} = $router_stash->{$key};
}
```

**Step 4: Verify syntax**

Run: `perl -Ilib -c lib/PAGI/Endpoint/Router.pm`

---

## Task 5: Update PAGI::Endpoint::Router POD documentation

**Files:**
- Modify: `lib/PAGI/Endpoint/Router.pm`

**Step 1: Update SYNOPSIS**

```perl
=head1 SYNOPSIS

    package MyApp;
    use parent 'PAGI::Endpoint::Router';
    use Future::AsyncAwait;

    async sub on_startup {
        my ($self) = @_;
        # Worker-local state - NOT shared across workers/nodes
        $self->state->{db} = DBI->connect(...);
    }

    sub routes {
        my ($self, $r) = @_;
        $r->get('/users/:id' => ['auth'] => 'get_user');
    }

    # Middleware sets stash - visible to all downstream handlers
    async sub auth {
        my ($self, $req, $res, $next) = @_;
        my $user = authenticate($req);
        $req->stash->{user} = $user;  # Flows to handler and subrouters
        await $next->();
    }

    async sub get_user {
        my ($self, $req, $res) = @_;
        my $db = $self->state->{db};           # Worker state via $self
        my $current_user = $req->stash->{user}; # Set by middleware

        my $user = $db->get_user($req->param('id'));
        await $res->json($user);
    }
```

**Step 2: Add comprehensive STATE VS STASH section**

```perl
=head1 STATE VS STASH

PAGI::Endpoint::Router provides two separate storage mechanisms with
different scopes and lifetimes.

=head2 state - Worker-Local Instance State

    $self->state->{db} = $connection;

The C<state> hashref is attached to the router instance. Use it for
resources initialized in C<on_startup> like database connections,
cache clients, or configuration.

B<IMPORTANT: Worker Isolation>

In a multi-worker or clustered deployment, each worker process has its
own isolated copy of C<state>:

    Master Process
      └─ fork() ─┬─ Worker 1 (own $self->state)
                 ├─ Worker 2 (own $self->state)
                 └─ Worker 3 (own $self->state)

Changes to C<state> in one worker do NOT affect other workers. For
truly shared application state (counters, sessions, feature flags),
use external storage:

=over 4

=item * B<Redis> - Fast in-memory shared state

=item * B<Database> - Persistent shared state

=item * B<Memcached> - Distributed caching

=back

=head2 stash - Per-Request Shared Scratch Space

    $req->stash->{user} = $current_user;

The C<stash> lives in the request scope and is shared across ALL
handlers, middleware, and subrouters processing the same request.

    Middleware A
        └─ sets $req->stash->{user}
            └─ Middleware B
                └─ reads $req->stash->{user}
                    └─ Subrouter Handler
                        └─ reads $req->stash->{user}  ✓ Still visible!

This enables middleware to pass data downstream without explicit
parameter passing:

    # Auth middleware
    async sub require_auth {
        my ($self, $req, $res, $next) = @_;
        my $user = verify_token($req->header('Authorization'));
        $req->stash->{user} = $user;  # Available to ALL downstream
        await $next->();
    }

    # Handler in subrouter - sees stash from parent middleware
    async sub get_profile {
        my ($self, $req, $res) = @_;
        my $user = $req->stash->{user};  # Set by middleware above
        await $res->json($user);
    }

=head2 Summary

    ┌─────────────────────────────────────────────────────────────┐
    │                        $self->state                         │
    │  Per-worker, set in on_startup, access via $self in handler │
    │  DB connections, config, caches                             │
    └─────────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────────┐
    │                        $req->stash                          │
    │  Per-request, shared across middleware/handlers/subrouters  │
    │  Current user, request timing, computed values              │
    └─────────────────────────────────────────────────────────────┘

=cut
```

---

## Task 6: Update tests for PAGI::Request

**Files:**
- Modify: `t/request/06-stash.t`
- Modify: `t/request-stash.t` (if exists)

**Step 1: Update stash tests to use scope-based stash**

```perl
subtest 'stash lives in scope' => sub {
    my $scope = { type => 'http', method => 'GET', headers => [] };
    my $req = PAGI::Request->new($scope);

    $req->stash->{user} = 'alice';

    is($req->stash->{user}, 'alice', 'stash persists');
    is($scope->{'pagi.stash'}{user}, 'alice', 'stash lives in scope');
};

subtest 'stash shared via scope' => sub {
    my $scope = { type => 'http', method => 'GET', headers => [] };
    my $req1 = PAGI::Request->new($scope);
    my $req2 = PAGI::Request->new($scope);  # Same scope

    $req1->stash->{foo} = 'bar';

    is($req2->stash->{foo}, 'bar', 'same scope = same stash');
};
```

**Step 2: Remove tests for set_stash, set, get**

Delete any tests for removed methods.

**Step 3: Run tests**

Run: `prove -l t/request/`

---

## Task 7: Update PAGI::Endpoint::Router tests

**Files:**
- Modify: `t/endpoint-router.t`

**Step 1: Update class structure test**

```perl
subtest 'basic class structure' => sub {
    ok(PAGI::Endpoint::Router->can('state'), 'has state');
    # ... rest of tests
};

subtest 'state is a hashref' => sub {
    my $router = PAGI::Endpoint::Router->new;
    is(ref($router->state), 'HASH', 'state is hashref');
    $router->state->{test} = 'value';
    is($router->state->{test}, 'value', 'state persists values');
};
```

**Step 2: Update lifespan test**

Change `$self->stash` to `$self->state`, verify stash flows through middleware.

**Step 3: Add test for stash flowing through middleware**

```perl
subtest 'stash flows through middleware to handler' => sub {
    {
        package TestApp::StashFlow;
        use parent 'PAGI::Endpoint::Router';
        use Future::AsyncAwait;

        our $handler_saw_user;

        sub routes {
            my ($self, $r) = @_;
            $r->get('/test' => ['set_user'] => 'check_user');
        }

        async sub set_user {
            my ($self, $req, $res, $next) = @_;
            $req->stash->{user} = 'alice';
            await $next->();
        }

        async sub check_user {
            my ($self, $req, $res) = @_;
            $handler_saw_user = $req->stash->{user};
            await $res->text('ok');
        }
    }

    my $app = TestApp::StashFlow->to_app;

    (async sub {
        my @sent;
        await $app->(
            { type => 'http', method => 'GET', path => '/test', headers => [] },
            sub { Future->done({ type => 'http.request', body => '' }) },
            sub { push @sent, $_[0]; Future->done }
        );

        is($TestApp::StashFlow::handler_saw_user, 'alice',
           'handler sees stash set by middleware');
    })->()->get;
};
```

**Step 4: Run tests**

Run: `prove -l t/endpoint-router.t`

---

## Task 8: Update example application

**Files:**
- Modify: `examples/endpoint-router-demo/lib/MyApp/Main.pm`
- Modify: `examples/endpoint-router-demo/lib/MyApp/API.pm`

**Step 1: Update to use state instead of stash for app-level data**

```perl
async sub on_startup {
    my ($self) = @_;
    $self->state->{config} = { ... };
    $self->state->{worker_metrics} = { ... };
}

async sub home {
    my ($self, $req, $res) = @_;
    my $config = $self->state->{config};  # Via $self
    # ...
}

async sub ws_echo {
    my ($self, $ws) = @_;
    my $metrics = $self->state->{worker_metrics};  # Via $self
    $ws->stash->{connected_at} = time();  # Per-connection
    # ...
}
```

**Step 2: Verify syntax**

Run: `perl -Ilib -Iexamples/endpoint-router-demo/lib -c examples/endpoint-router-demo/app.pl`

---

## Task 9: Update integration tests

**Files:**
- Modify: `t/integration-endpoint-router-demo.t`

Update any tests that relied on state being copied to stash.

Run: `prove -l t/integration-endpoint-router-demo.t`

---

## Task 10: Run full test suite and fix failures

**Step 1: Run all tests**

Run: `prove -lr t/`

**Step 2: Fix any failures**

Search for and fix:
- Uses of `->set_stash`, `->set`, `->get` on Request
- Uses of `->stash` on router instances (change to `->state`)
- Tests expecting state values in stash

---

## Task 11: Create CHANGES entry

**Files:**
- Create or modify: `Changes`

```
## [Unreleased]

### Changed

- **BREAKING**: Renamed `$router->stash` to `$router->state` in PAGI::Endpoint::Router
- **BREAKING**: `$req->stash`, `$ws->stash`, `$sse->stash` now live in scope
  (`$scope->{'pagi.stash'}`) and are shared across all middleware, handlers,
  and subrouters processing the same request
- **BREAKING**: Removed `$req->set_stash()`, `$req->set()`, `$req->get()` methods
  - Just use `$req->stash->{key}` for all request-scoped data sharing
- Removed automatic copying of router state into request stash

### Migration Guide

**Router state:**
```perl
# Before
$self->stash->{db} = DBI->connect(...);

# After
$self->state->{db} = DBI->connect(...);
```

**Accessing state in handlers:**
```perl
# Before (state was copied to request stash)
my $db = $req->stash->{db};

# After (access via $self)
my $db = $self->state->{db};
```

**Middleware data sharing:**
```perl
# Before
$req->set('user', $user);
my $user = $req->get('user');

# After (just use stash)
$req->stash->{user} = $user;
my $user = $req->stash->{user};
```

### Important Notes

**Worker Isolation:** `$self->state` is per-worker. In multi-worker deployments,
each worker has isolated state. For shared state across workers or cluster nodes,
use external storage (Redis, database, etc.).

**Stash Flows Downstream:** `$req->stash` is shared across all middleware, handlers,
and subrouters for the same request. Middleware can set values that downstream
handlers will see.
```

---

## Task 12: Final verification

**Step 1: Run full recursive test suite**

Run: `prove -lr t/`

**Step 2: Syntax check all modified files**

```bash
perl -Ilib -c lib/PAGI/Request.pm
perl -Ilib -c lib/PAGI/WebSocket.pm
perl -Ilib -c lib/PAGI/SSE.pm
perl -Ilib -c lib/PAGI/Endpoint/Router.pm
```

**Step 3: Test example app**

Run: `perl -Ilib examples/endpoint-router-demo/app.pl`

**Step 4: Review changes**

Run: `git diff`
