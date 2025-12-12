# PAGI::Simple Worker Model - Design Document

**Status**: Research & Planning
**Created**: 2025-12-08
**Purpose**: Design a worker model for PAGI::Simple to handle long-lived and blocking operations (DBI, legacy blocking libraries, CPU-intensive tasks)

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Current Architecture Analysis](#current-architecture-analysis)
3. [How Other Frameworks Handle This](#how-other-frameworks-handle-this)
4. [Proposed Approaches](#proposed-approaches)
5. [Key Design Questions](#key-design-questions)
6. [Recommended Implementation Path](#recommended-implementation-path)
7. [Code Sketches](#code-sketches)
8. [Testing Strategy](#testing-strategy)
9. [Migration & Compatibility](#migration--compatibility)
10. [References](#references)

---

## Problem Statement

### The Challenge

PAGI::Simple is built on an async/await model using `Future::AsyncAwait` and `IO::Async`. This works beautifully for I/O-bound operations that have async APIs, but presents challenges for:

1. **Database Operations (DBI)**: Standard DBI is blocking. Each query blocks the event loop, preventing other requests from being handled.

2. **Legacy Libraries**: Many CPAN modules were written before async Perl and use blocking I/O internally.

3. **CPU-Intensive Work**: Parsing large files, image processing, cryptographic operations — these block the event loop even though they're not I/O.

4. **External Process Calls**: Shelling out to external commands, which may take unpredictable time.

### Why This Matters

In a single-process async server, blocking the event loop means:
- No new connections can be accepted
- Existing WebSocket/SSE connections stall
- Timeouts may fire incorrectly
- Overall throughput collapses to serial execution

### Goals

- Provide a clean API for running blocking code without blocking the event loop
- Support connection pooling for databases (don't reconnect every query)
- Handle errors gracefully with proper propagation to the caller
- Integrate naturally with the existing service system
- Minimal overhead for simple cases
- Configurable for high-throughput scenarios

---

## Current Architecture Analysis

### Async Foundation

PAGI::Simple is already fully async-native:

**Event Loop Integration** (`lib/PAGI/Simple/Context.pm:218`):
```perl
sub loop ($self) {
    return $self->{scope}{pagi}{loop} // ($self->{app}->loop);
}
```

Every request handler has access to the `IO::Async::Loop` via `$c->loop`.

**Request Handling Pipeline** (`lib/PAGI/Simple.pm:1166-1322`):
```
Raw PAGI Event (scope, receive, send)
    ↓
_handle_request() [async]
    ├── Lifespan events (startup/shutdown)
    ├── HTTP requests → _handle_http()
    ├── WebSocket → _handle_websocket()
    └── SSE → _handle_sse()

_handle_http() [async]
    ├── Match route via Router
    ├── Create Context ($c)
    ├── Run before hooks
    ├── Run middleware chain
    ├── Execute route handler (async sub)
    ├── Run after hooks
    └── Service cleanup
```

All route handlers are `async sub` and use `await` for non-blocking operations.

### Existing Worker Infrastructure

**PAGI::Util::AsyncFile** (`lib/PAGI/Util/AsyncFile.pm`) already implements a worker pool pattern:

```perl
# Singleton function pool per loop (keyed by loop address)
my %_function_pools;

sub _get_function ($class, $loop) {
    my $loop_id = blessed($loop) ? "$loop" : 'default';

    unless ($_function_pools{$loop_id}) {
        my $function = IO::Async::Function->new(
            code => sub ($op, @args) {
                return _worker_operation($op, @args);
            },
            min_workers => 1,
            max_workers => 4,
            idle_timeout => 30,
        );

        $loop->add($function);
        $_function_pools{$loop_id} = $function;
    }

    return $_function_pools{$loop_id};
}
```

Key characteristics:
- **Singleton per loop**: Avoids creating multiple pools
- **Operation dispatch**: Workers receive operation name + args
- **Configurable pool size**: min/max workers, idle timeout
- **Automatic lifecycle**: Workers forked on demand, reaped when idle

**Worker Operation Pattern** (`lib/PAGI/Util/AsyncFile.pm:81-123`):
```perl
sub _worker_operation ($op, @args) {
    if ($op eq 'read_file') {
        my ($path) = @args;
        open my $fh, '<:raw', $path or die "Cannot open $path: $!";
        local $/;
        my $content = <$fh>;
        close $fh;
        return $content;
    }
    elsif ($op eq 'read_chunk') {
        # ... chunked reading
    }
    elsif ($op eq 'write_file') {
        # ... file writing
    }
    # ... more operations
}
```

This pattern:
- Named operations for type safety
- All data passed as serializable arguments
- Results returned (serialized back to parent)
- Errors propagate via `die`

### Service System

**Three service scopes** available:

1. **Factory** (`lib/PAGI/Simple/Service/Factory.pm`): New instance every `$c->service()` call
2. **PerRequest** (`lib/PAGI/Simple/Service/PerRequest.pm`): Cached per request, cleanup hook available
3. **PerApp** (`lib/PAGI/Simple/Service/PerApp.pm`): Singleton, created at startup

**PerApp is ideal for worker pools** because:
- Created once at startup (expensive initialization)
- Shared across all requests (connection reuse)
- Lifecycle tied to application (clean shutdown)

**Service Base Class** (`lib/PAGI/Simple/Service/_Base.pm`):
```perl
sub new ($class, %args) {
    return bless \%args, $class;
}

sub c ($self) { return $self->{c}; }      # Request context (undef for PerApp)
sub app ($self) { return $self->{app}; }  # App instance

sub on_request_end ($self, $c) {
    # Override for cleanup
}

sub init_service ($class, $app, $config) {
    die "Subclass must implement init_service";
}
```

### Multi-Worker Server Mode

`PAGI::Server` (`lib/PAGI/Server.pm:86-102`) supports pre-fork workers:
```perl
workers => $count  # 0 = single process (default)
```

Each server worker:
- Gets own event loop
- Runs lifespan startup independently
- Would need its own worker pool (separate process space)

**Implication**: Worker pools are per-server-process, not shared across pre-fork workers.

### Context Object Capabilities

**Full context available in handlers** (`lib/PAGI/Simple/Context.pm`):
```perl
$c->loop          # IO::Async::Loop
$c->app           # PAGI::Simple instance
$c->service($n)   # Get service by name
$c->stash         # Per-request storage
$c->req           # Request object
$c->scope         # Raw PAGI scope
```

**Response methods are async**:
```perl
await $c->text($body);
await $c->json($data);
await $c->html($content);
await $c->render($template, %vars);
```

---

## How Other Frameworks Handle This

### Python asyncio — `run_in_executor()`

**Documentation**: https://docs.python.org/3/library/asyncio-eventloop.html

**Pattern**:
```python
import asyncio
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor

async def handler():
    loop = asyncio.get_event_loop()

    # Thread pool (default) - good for I/O blocking
    result = await loop.run_in_executor(None, blocking_io_func, arg1, arg2)

    # Process pool - good for CPU-bound (bypasses GIL)
    with ProcessPoolExecutor() as pool:
        result = await loop.run_in_executor(pool, cpu_intensive_func, data)
```

**Key characteristics**:
- **Two executor types**: ThreadPoolExecutor (default), ProcessPoolExecutor
- **Thread pool for I/O**: Blocking I/O in threads doesn't block event loop
- **Process pool for CPU**: Bypasses Python's GIL for true parallelism
- **Simple API**: `await loop.run_in_executor(executor, func, *args)`
- **Default pool size**: `min(32, os.cpu_count() + 4)`

**Thread safety warning**: Shared state between threads needs synchronization. The async event loop itself is NOT thread-safe.

**When to use which**:
- ThreadPoolExecutor: Blocking I/O (database, file, network)
- ProcessPoolExecutor: CPU-bound (parsing, compression, crypto)

**Limitations**:
- Functions must be picklable for ProcessPoolExecutor
- Thread pool shares GIL — CPU-bound work still serialized
- No built-in connection pooling

### Node.js — Worker Threads

**Documentation**: https://nodejs.org/api/worker_threads.html

**Pattern**:
```javascript
const { Worker, isMainThread, parentPort, workerData } = require('worker_threads');

if (isMainThread) {
  // Main thread - spawn workers
  async function runWorker(data) {
    return new Promise((resolve, reject) => {
      const worker = new Worker(__filename, { workerData: data });
      worker.on('message', resolve);
      worker.on('error', reject);
    });
  }

  const result = await runWorker({ task: 'parse', file: 'large.json' });
} else {
  // Worker thread
  const result = heavyComputation(workerData);
  parentPort.postMessage(result);
}
```

**Key characteristics**:
- **Explicit worker creation**: Not a pool by default
- **Message passing**: Structured clone algorithm (like JSON but better)
- **SharedArrayBuffer**: Can share memory between threads
- **Different from child_process**: Threads, not processes

**Best practices from Node.js docs**:
- Use workers for CPU-intensive JavaScript
- Don't use workers for I/O — Node's async I/O is more efficient
- Don't block workers with sync operations
- Create worker pools for reuse (many npm packages available)

**Worker pool pattern** (recommended):
```javascript
// Use a pool library like 'workerpool' or 'piscina'
const Piscina = require('piscina');

const pool = new Piscina({
  filename: './worker.js',
  minThreads: 2,
  maxThreads: 8,
});

const result = await pool.run({ data }, { name: 'processData' });
```

### Mojolicious — `Mojo::IOLoop::Subprocess`

**Documentation**: https://mojolicious.org/perldoc/Mojo/IOLoop/Subprocess

**Pattern**:
```perl
use Mojo::IOLoop::Subprocess;

my $subprocess = Mojo::IOLoop::Subprocess->new;

# Non-blocking execution
$subprocess->run(
  sub ($subprocess) {
    # This runs in a forked child process
    my $dbh = DBI->connect($dsn);
    return $dbh->selectall_arrayref($sql);
  },
  sub ($subprocess, $err, @results) {
    # This runs in parent when child completes
    return app->log->error("Subprocess error: $err") if $err;
    # Use @results...
  }
);
```

**Key characteristics**:
- **Fork-based**: Each call forks a new process
- **Callback style**: Not promise/async-await (though `run_p` returns promise)
- **Progress reporting**: Can send progress updates during execution
- **Isolation**: Child crash doesn't affect parent

**Progress reporting**:
```perl
$subprocess->run(
  sub ($subprocess) {
    for my $i (1..100) {
      do_work($i);
      $subprocess->progress({ percent => $i });  # Send to parent
    }
    return $result;
  },
  sub ($subprocess, $err, @results) { ... }
);

$subprocess->on(progress => sub ($subprocess, $data) {
  say "Progress: $data->{percent}%";
});
```

**Related modules**:
- `Mojo::IOLoop::ReadWriteFork`: Follow STDOUT/STDERR of subprocess
- `Mojo::IOLoop::ForkCall`: Execute arbitrary Perl async (deprecated in favor of Subprocess)

**Limitations**:
- Fork overhead per call (no persistent worker pool)
- No connection reuse (each fork gets fresh state)
- Can't use non-blocking Mojo::UserAgent inside subprocess (event loop issues)

### IO::Async::Function (Perl)

**Documentation**: https://metacpan.org/pod/IO::Async::Function

**Pattern**:
```perl
use IO::Async::Function;
use IO::Async::Loop;

my $loop = IO::Async::Loop->new;

my $function = IO::Async::Function->new(
  code => sub {
    my ($x, $y) = @_;
    return $x + $y;  # Blocking computation
  },
  min_workers => 1,
  max_workers => 8,
  idle_timeout => 30,
);

$loop->add($function);

# Call returns a Future
my $result = await $function->call(args => [10, 20]);
```

**Key characteristics**:
- **Worker pool**: Persistent workers, reused across calls
- **Future-based**: Returns `Future` object, works with `await`
- **Configurable pool**: min/max workers, idle timeout, max calls per worker
- **Pure function model**: Args in, result out, no side effects expected

**Advanced configuration**:
```perl
my $function = IO::Async::Function->new(
  code => sub { ... },

  min_workers => 2,           # Always keep 2 workers alive
  max_workers => 16,          # Scale up to 16 under load
  idle_timeout => 60,         # Kill idle workers after 60s
  max_worker_calls => 1000,   # Restart worker after 1000 calls (memory leaks)

  setup => [                  # Run in worker before first call
    chdir => '/tmp',
    nice => 10,
  ],
);
```

**Worker state persistence**:
```perl
# State persists within a worker across calls
my $function = IO::Async::Function->new(
  code => sub {
    my ($op, @args) = @_;

    # $dbh persists across calls in this worker
    state $dbh = DBI->connect($dsn);

    if ($op eq 'query') {
      return $dbh->selectall_arrayref($args[0]);
    }
  },
);
```

**Error handling**:
```perl
try {
  my $result = await $function->call(args => [@args]);
} catch ($e) {
  # $e contains the die message from worker
  warn "Worker failed: $e";
}
```

### Comparison Summary

| Framework | Mechanism | Pool? | State? | Error Handling | API Style |
|-----------|-----------|-------|--------|----------------|-----------|
| Python asyncio | Thread/Process | Yes (default) | No | Exception propagation | `await run_in_executor()` |
| Node.js | Worker threads | Manual/lib | SharedArrayBuffer | Promise rejection | `worker.postMessage()` |
| Mojolicious | Fork | No (per-call) | No | Callback error arg | `$sp->run($code, $cb)` |
| IO::Async::Function | Fork pool | Yes | state variables | Future failure | `await $fn->call()` |

---

## Proposed Approaches

### Option A: Generic Worker Pool Service

**Concept**: A PerApp service that wraps `IO::Async::Function` to run arbitrary coderefs.

**Implementation Sketch**:
```perl
package PAGI::Simple::Service::WorkerPool;
use parent 'PAGI::Simple::Service::PerApp';
use IO::Async::Function;
use Future::AsyncAwait;

sub init_service ($class, $app, $config) {
    my $self = $class->new(%$config, app => $app);

    $self->{function} = IO::Async::Function->new(
        code => sub {
            my ($serialized_code, @args) = @_;
            my $code = eval $serialized_code;  # Deserialize
            return $code->(@args);
        },
        min_workers => $config->{min_workers} // 2,
        max_workers => $config->{max_workers} // 8,
        idle_timeout => $config->{idle_timeout} // 60,
    );

    # Will be added to loop at startup
    $self->{_pending_add} = 1;

    return $self;
}

sub on_app_start ($self, $app) {
    $app->loop->add($self->{function});
}

async sub run ($self, $code, @args) {
    # Serialize the coderef (limited - no closures!)
    my $serialized = _serialize_code($code);
    return await $self->{function}->call(args => [$serialized, @args]);
}
```

**Usage**:
```perl
$app->add_service('Workers', 'PAGI::Simple::Service::WorkerPool', {
    min_workers => 2,
    max_workers => 16,
});

$app->get('/compute' => async sub ($c) {
    my $workers = $c->service('Workers');

    my $result = await $workers->run(sub {
        my ($n) = @_;
        # CPU-intensive work
        return fibonacci($n);
    }, 40);

    $c->json({ result => $result });
});
```

**Pros**:
- Most flexible — any code can be offloaded
- Familiar pattern from Python's `run_in_executor`
- Single pool for all blocking work

**Cons**:
- **Code serialization is problematic**: Closures don't serialize across fork
- **No state persistence**: Can't keep DB connections in workers
- **Security concerns**: Executing arbitrary code in workers
- **Debugging difficulty**: Stack traces span processes

**When to use**: Ad-hoc blocking operations, legacy code wrapping, CPU-bound pure functions.

---

### Option B: Named Operations Pattern (Recommended)

**Concept**: Pre-define operations that workers understand. Workers can maintain state (connections, caches).

**Implementation Sketch**:
```perl
package PAGI::Simple::Service::DBWorker;
use parent 'PAGI::Simple::Service::PerApp';
use IO::Async::Function;
use Future::AsyncAwait;
use DBI;

# Operations run in worker processes
sub _worker_dispatch ($dsn, $op, @args) {
    # Connection persists across calls in this worker
    state $dbh;
    $dbh //= DBI->connect($dsn, '', '', {
        RaiseError => 1,
        AutoCommit => 1,
        mysql_auto_reconnect => 1,
    });

    if ($op eq 'select_all') {
        my ($sql, @bind) = @args;
        return $dbh->selectall_arrayref($sql, { Slice => {} }, @bind);
    }
    elsif ($op eq 'select_row') {
        my ($sql, @bind) = @args;
        return $dbh->selectrow_hashref($sql, undef, @bind);
    }
    elsif ($op eq 'do') {
        my ($sql, @bind) = @args;
        return $dbh->do($sql, undef, @bind);
    }
    elsif ($op eq 'insert_id') {
        my ($sql, @bind) = @args;
        $dbh->do($sql, undef, @bind);
        return $dbh->last_insert_id(undef, undef, undef, undef);
    }
    elsif ($op eq 'transaction') {
        my ($statements) = @args;  # Array of [sql, @bind]
        eval {
            $dbh->begin_work;
            for my $stmt (@$statements) {
                my ($sql, @bind) = @$stmt;
                $dbh->do($sql, undef, @bind);
            }
            $dbh->commit;
        };
        if ($@) {
            $dbh->rollback;
            die $@;
        }
        return 1;
    }
    else {
        die "Unknown DB operation: $op";
    }
}

sub init_service ($class, $app, $config) {
    my $self = $class->new(%$config, app => $app);

    my $dsn = $config->{dsn} or die "DBWorker requires 'dsn' config";

    $self->{function} = IO::Async::Function->new(
        code => sub { _worker_dispatch($dsn, @_) },
        min_workers => $config->{min_workers} // 2,
        max_workers => $config->{max_workers} // 4,
        idle_timeout => $config->{idle_timeout} // 300,
        max_worker_calls => $config->{max_worker_calls} // 10000,
    );

    return $self;
}

# High-level async API
async sub select_all ($self, $sql, @bind) {
    return await $self->{function}->call(args => ['select_all', $sql, @bind]);
}

async sub select_row ($self, $sql, @bind) {
    return await $self->{function}->call(args => ['select_row', $sql, @bind]);
}

async sub do ($self, $sql, @bind) {
    return await $self->{function}->call(args => ['do', $sql, @bind]);
}

async sub insert ($self, $sql, @bind) {
    return await $self->{function}->call(args => ['insert_id', $sql, @bind]);
}

async sub transaction ($self, @statements) {
    return await $self->{function}->call(args => ['transaction', \@statements]);
}
```

**Usage**:
```perl
$app->add_service('DB', 'PAGI::Simple::Service::DBWorker', {
    dsn => 'dbi:mysql:database=myapp;host=localhost',
    min_workers => 2,
    max_workers => 8,
});

$app->get('/users' => async sub ($c) {
    my $db = $c->service('DB');
    my $users = await $db->select_all(
        "SELECT * FROM users WHERE active = ? ORDER BY name",
        1
    );
    $c->json($users);
});

$app->post('/users' => async sub ($c) {
    my $db = $c->service('DB');
    my $data = await $c->req->json_body;

    my $id = await $db->insert(
        "INSERT INTO users (name, email) VALUES (?, ?)",
        $data->{name}, $data->{email}
    );

    $c->json({ id => $id });
});
```

**Pros**:
- **Connection pooling**: Each worker maintains a persistent connection
- **Type safety**: Operations are predefined, validated
- **Testable**: Each operation can be unit tested
- **Follows existing pattern**: Same as `PAGI::Util::AsyncFile`
- **Efficient**: No code serialization, minimal IPC overhead
- **Debuggable**: Clear operation names in stack traces

**Cons**:
- **Less flexible**: Must define operations upfront
- **More code**: Each operation needs a handler
- **Service-specific**: Need different services for different backends

**When to use**: Database access, well-defined blocking APIs, any case where operations are known at compile time.

---

### Option C: Operation Registry (Hybrid)

**Concept**: Combine flexibility of Option A with structure of Option B. Apps register operations at startup.

**Implementation Sketch**:
```perl
package PAGI::Simple::Worker;
use strict;
use warnings;
use experimental 'signatures';

# Global operation registry (populated at compile time)
my %operations;

sub register ($class, $name, $code, %opts) {
    $operations{$name} = {
        code => $code,
        %opts,
    };
}

sub _dispatch ($op, @args) {
    my $handler = $operations{$op}
        or die "Unknown worker operation: $op";
    return $handler->{code}->(@args);
}

# ---

package PAGI::Simple::Service::Workers;
use parent 'PAGI::Simple::Service::PerApp';
use IO::Async::Function;
use Future::AsyncAwait;

sub init_service ($class, $app, $config) {
    my $self = $class->new(%$config, app => $app);

    $self->{function} = IO::Async::Function->new(
        code => \&PAGI::Simple::Worker::_dispatch,
        min_workers => $config->{min_workers} // 2,
        max_workers => $config->{max_workers} // 8,
        idle_timeout => $config->{idle_timeout} // 60,
    );

    return $self;
}

async sub call ($self, $op, @args) {
    return await $self->{function}->call(args => [$op, @args]);
}
```

**App-level registration**:
```perl
# In app startup or a separate module
use PAGI::Simple::Worker;

# Database operations
PAGI::Simple::Worker->register('db.connect' => sub ($dsn) {
    state %connections;
    return $connections{$dsn} //= DBI->connect($dsn);
});

PAGI::Simple::Worker->register('db.query' => sub ($dsn, $sql, @bind) {
    state %connections;
    my $dbh = $connections{$dsn} //= DBI->connect($dsn);
    return $dbh->selectall_arrayref($sql, { Slice => {} }, @bind);
});

# Legacy library wrapper
PAGI::Simple::Worker->register('legacy.parse_xml' => sub ($xml_string) {
    require XML::LibXML;
    my $doc = XML::LibXML->load_xml(string => $xml_string);
    return $doc->toString;
});

# CPU-intensive operations
PAGI::Simple::Worker->register('crypto.hash' => sub ($algorithm, $data) {
    require Digest;
    return Digest->new($algorithm)->add($data)->hexdigest;
});
```

**Usage**:
```perl
$app->add_service('Workers', 'PAGI::Simple::Service::Workers');

$app->get('/users' => async sub ($c) {
    my $w = $c->service('Workers');
    my $users = await $w->call('db.query', $dsn,
        "SELECT * FROM users WHERE active = ?", 1);
    $c->json($users);
});
```

**Pros**:
- **Flexible**: Apps define their own operations
- **Organized**: Namespaced operations (`db.*`, `legacy.*`, `cpu.*`)
- **State persistence**: Workers can use `state` variables
- **Single service**: One worker pool, many operations
- **Extensible**: Plugins can register operations

**Cons**:
- **Global registry**: Operations must be registered before workers fork
- **Less type safety**: Operation names are strings
- **Ordering dependency**: Registration must happen before `init_service`

**When to use**: Applications with diverse blocking needs, plugin systems, gradual migration of legacy code.

---

### Option D: Subprocess Model (One-shot Fork)

**Concept**: Fork a new process for each blocking operation. Maximum isolation, no state persistence.

**Implementation Sketch**:
```perl
package PAGI::Simple::Subprocess;
use strict;
use warnings;
use experimental 'signatures';
use IO::Async::Process;
use Future::AsyncAwait;
use Storable qw(nfreeze thaw);
use MIME::Base64;

async sub run ($class, $loop, $code, @args) {
    my $result_future = $loop->new_future;

    # Serialize code and args
    my $payload = encode_base64(nfreeze([$code, \@args]));

    my $stdout = '';
    my $stderr = '';

    my $process = IO::Async::Process->new(
        command => [$^X, '-e', q{
            use Storable qw(nfreeze thaw);
            use MIME::Base64;

            my $input = do { local $/; <STDIN> };
            my ($code, $args) = @{thaw(decode_base64($input))};

            my $result = eval { $code->(@$args) };
            my $error = $@;

            print encode_base64(nfreeze({ result => $result, error => $error }));
        }],
        stdin => { from => $payload },
        stdout => { into => \$stdout },
        stderr => { into => \$stderr },
        on_finish => sub ($process, $exitcode) {
            if ($exitcode != 0) {
                $result_future->fail("Subprocess exited with $exitcode: $stderr");
                return;
            }

            my $response = thaw(decode_base64($stdout));
            if ($response->{error}) {
                $result_future->fail($response->{error});
            } else {
                $result_future->done($response->{result});
            }
        },
    );

    $loop->add($process);

    return await $result_future;
}
```

**Usage**:
```perl
$app->get('/risky' => async sub ($c) {
    my $result = await PAGI::Simple::Subprocess->run(
        $c->loop,
        sub {
            # This runs in complete isolation
            # If it crashes, main process is unaffected
            require Some::Flaky::Library;
            return Some::Flaky::Library->do_stuff();
        }
    );
    $c->json({ result => $result });
});
```

**Pros**:
- **Complete isolation**: Crashes don't affect main process
- **Clean slate**: No state leakage between calls
- **Good for untrusted code**: Sandboxing potential
- **Simple mental model**: Fork, run, return

**Cons**:
- **Fork overhead**: New process per call (~10-50ms on Linux)
- **No connection reuse**: Each call reconnects to DB
- **Serialization limits**: Code and data must serialize
- **Resource intensive**: Many concurrent calls = many processes

**When to use**: Untrusted or flaky code, operations that might crash, infrequent but expensive operations.

---

### Option E: Context Helper Method

**Concept**: Add a convenience method directly to the Context object for simple cases.

**Implementation Sketch**:
```perl
# In PAGI::Simple::Context

async sub run_blocking ($self, $code_or_op, @args) {
    my $workers = $self->service('Workers');

    if (ref($code_or_op) eq 'CODE') {
        # Ad-hoc coderef (Option A style)
        return await $workers->run_code($code_or_op, @args);
    } else {
        # Named operation (Option B/C style)
        return await $workers->call($code_or_op, @args);
    }
}
```

**Usage**:
```perl
$app->get('/users' => async sub ($c) {
    # Named operation
    my $users = await $c->run_blocking('db.query', $sql, @bind);

    # Or ad-hoc code
    my $hash = await $c->run_blocking(sub {
        require Digest::SHA;
        return Digest::SHA::sha256_hex($_[0]);
    }, $data);

    $c->json({ users => $users, hash => $hash });
});
```

**Pros**:
- **Ergonomic**: Clean API, no service lookup boilerplate
- **Flexible**: Supports both patterns
- **Discoverable**: Method on $c is easy to find

**Cons**:
- **Implicit dependency**: Requires Workers service to be configured
- **Magic**: Hides which worker pool is used

---

## Key Design Questions

### 1. Connection Persistence

**Question**: Should database connections live in workers?

**Option: Yes (Persistent)**
```perl
# Worker maintains connection
state $dbh = DBI->connect($dsn);
```
- Pros: Fast (no connect overhead), connection pooling
- Cons: Connections held even when idle, reconnect logic needed

**Option: No (Per-Call)**
```perl
# New connection each call
my $dbh = DBI->connect($dsn);
# ... use it ...
$dbh->disconnect;
```
- Pros: Simple, no stale connections
- Cons: Slow (connect overhead), no pooling

**Recommendation**: Persistent connections with `max_worker_calls` to cycle workers periodically.

### 2. Worker State Model

**Question**: Pure functions or stateful workers?

**Pure Functions**:
```perl
code => sub ($op, @args) {
    # No state between calls
    return process($op, @args);
}
```
- Pros: Predictable, can retry safely, easy to test
- Cons: No caching, no connection reuse

**Stateful Workers**:
```perl
code => sub ($op, @args) {
    state $cache = {};
    state $dbh = DBI->connect(...);
    # State persists across calls
}
```
- Pros: Caching, connection pools, efficient
- Cons: Memory leaks possible, harder to reason about

**Recommendation**: Stateful workers with `max_worker_calls` limit to prevent memory leaks.

### 3. Error Handling Strategy

**Question**: How should worker errors surface?

**Options**:

1. **Rethrow in main process**:
```perl
try {
    my $result = await $workers->call('db.query', $sql);
} catch ($e) {
    # $e is the die message from worker
}
```

2. **Structured error objects**:
```perl
my $result = await $workers->call('db.query', $sql);
if ($result->is_error) {
    my $err = $result->error;
    # { type => 'db_error', message => '...', code => 1045 }
}
```

3. **Error callbacks**:
```perl
$workers->on(error => sub ($worker, $op, $error) {
    $app->log->error("Worker error in $op: $error");
});
```

**Recommendation**: Rethrow with structured error wrapping. Errors should include operation name, original message, and worker PID for debugging.

### 4. Pool Granularity

**Question**: One pool for everything or specialized pools?

**Single Pool**:
```perl
$app->add_service('Workers', ...);
await $c->service('Workers')->call('db.query', ...);
await $c->service('Workers')->call('parse.xml', ...);
```
- Pros: Simple configuration, shared resources
- Cons: Can't tune separately, one slow operation blocks others

**Multiple Pools**:
```perl
$app->add_service('DB', 'DBWorker', { max_workers => 8 });
$app->add_service('CPU', 'CPUWorker', { max_workers => 4 });

await $c->service('DB')->query(...);
await $c->service('CPU')->hash(...);
```
- Pros: Tune each pool for its workload, isolation
- Cons: More configuration, more resources

**Recommendation**: Start with single pool, add specialized pools as needed. DB operations typically need different tuning than CPU operations.

### 5. Context Passing to Workers

**Question**: How much request context goes to workers?

**None (Pure)**:
```perl
# Only explicit args
await $workers->call('db.query', $sql, @bind);
```
- Pros: Safe, no serialization issues
- Cons: Verbose, must pass everything explicitly

**Serialized Stash**:
```perl
# Pass request context
await $workers->call('operation', {
    user_id => $c->stash->{user_id},
    request_id => $c->req->header('X-Request-ID'),
});
```
- Pros: Convenient, workers have context
- Cons: Must serialize carefully, can't pass coderefs/objects

**Recommendation**: Explicit argument passing. Context is the caller's responsibility to serialize what's needed.

### 6. Timeout Handling

**Question**: What happens when a worker operation takes too long?

**Options**:

1. **No timeout**: Worker runs until done
2. **Global timeout**: All operations get same timeout
3. **Per-operation timeout**: Each call specifies timeout

```perl
# Per-call timeout
my $result = await $workers->call('slow.operation', @args, timeout => 30);
```

**Recommendation**: Per-call timeout with sensible default (30s). Timeout should cancel the Future but NOT kill the worker (let it finish or timeout via `idle_timeout`).

### 7. Startup Initialization

**Question**: When/how are workers initialized?

**Options**:

1. **Lazy**: First call spawns workers
2. **Eager**: Spawn workers at app startup
3. **Warm-up**: Spawn and run init code at startup

```perl
# Warm-up pattern
$self->{function} = IO::Async::Function->new(
    code => sub { ... },
    setup => [
        # Run in each worker at spawn time
        sub {
            require DBI;
            require JSON::XS;
        },
    ],
);
```

**Recommendation**: Eager spawning with warm-up. Avoids latency spike on first request.

---

## Recommended Implementation Path

### Phase 1: Core Worker Service

Implement Option B (Named Operations) as `PAGI::Simple::Service::Workers`:

1. Create `lib/PAGI/Simple/Service/Workers.pm`
   - Wrap `IO::Async::Function`
   - Support operation registration
   - Handle lifecycle (startup, shutdown)

2. Create `lib/PAGI/Simple/Worker/Operations.pm`
   - Default operations (noop, echo for testing)
   - Registration API

3. Add tests in `t/simple/worker/`
   - Basic operations
   - Error handling
   - Timeout behavior
   - Pool scaling

### Phase 2: Database Worker

Build on Phase 1 for DBI-specific needs:

1. Create `lib/PAGI/Simple/Service/DBWorker.pm`
   - Subclass or wrap Workers service
   - DBI-specific operations
   - Connection management

2. Add `lib/PAGI/Simple/Worker/DB.pm`
   - register db.select_all, db.select_row, db.do, db.insert, db.transaction

3. Documentation and examples

### Phase 3: Context Integration

Add ergonomic helpers:

1. Add `$c->run_blocking()` helper
2. Add `$c->db` shortcut (if DB service configured)
3. Update documentation

### Phase 4: Advanced Features

Based on usage feedback:

1. Progress reporting
2. Worker health monitoring
3. Metrics integration
4. Multiple named pools

---

## Code Sketches

### Complete DBWorker Service

```perl
package PAGI::Simple::Service::DBWorker;

use strict;
use warnings;
use experimental 'signatures';

our $VERSION = '0.01';

use parent 'PAGI::Simple::Service::PerApp';
use IO::Async::Function;
use Future::AsyncAwait;
use Scalar::Util qw(blessed);

=head1 NAME

PAGI::Simple::Service::DBWorker - Non-blocking database operations via worker pool

=head1 SYNOPSIS

    # In app setup
    $app->add_service('DB', 'PAGI::Simple::Service::DBWorker', {
        dsn => 'dbi:mysql:database=myapp',
        username => 'user',
        password => 'pass',
        min_workers => 2,
        max_workers => 8,
    });

    # In route handlers
    $app->get('/users' => async sub ($c) {
        my $db = $c->service('DB');
        my $users = await $db->select_all(
            "SELECT * FROM users WHERE active = ?", 1
        );
        $c->json($users);
    });

=cut

# Worker-side code (runs in forked processes)
sub _worker_code {
    my ($dsn, $username, $password, $options, $op, @args) = @_;

    # Persistent connection within this worker
    state $dbh;
    unless ($dbh && $dbh->ping) {
        $dbh = DBI->connect($dsn, $username, $password, {
            RaiseError => 1,
            AutoCommit => 1,
            PrintError => 0,
            %{ $options // {} },
        }) or die "DBI connect failed: $DBI::errstr";
    }

    return _dispatch_operation($dbh, $op, @args);
}

sub _dispatch_operation ($dbh, $op, @args) {
    if ($op eq 'select_all') {
        my ($sql, @bind) = @args;
        return $dbh->selectall_arrayref($sql, { Slice => {} }, @bind);
    }
    elsif ($op eq 'select_row') {
        my ($sql, @bind) = @args;
        return $dbh->selectrow_hashref($sql, undef, @bind);
    }
    elsif ($op eq 'select_col') {
        my ($sql, @bind) = @args;
        return $dbh->selectcol_arrayref($sql, undef, @bind);
    }
    elsif ($op eq 'select_value') {
        my ($sql, @bind) = @args;
        my ($value) = $dbh->selectrow_array($sql, undef, @bind);
        return $value;
    }
    elsif ($op eq 'do') {
        my ($sql, @bind) = @args;
        return $dbh->do($sql, undef, @bind);
    }
    elsif ($op eq 'insert') {
        my ($sql, @bind) = @args;
        $dbh->do($sql, undef, @bind);
        return $dbh->last_insert_id(undef, undef, undef, undef);
    }
    elsif ($op eq 'transaction') {
        my ($statements) = @args;
        my @results;
        eval {
            $dbh->begin_work;
            for my $stmt (@$statements) {
                my ($sql, @bind) = @$stmt;
                push @results, $dbh->do($sql, undef, @bind);
            }
            $dbh->commit;
        };
        if (my $err = $@) {
            eval { $dbh->rollback };
            die $err;
        }
        return \@results;
    }
    elsif ($op eq 'ping') {
        return $dbh->ping ? 1 : 0;
    }
    else {
        die "Unknown DB operation: $op";
    }
}

sub init_service ($class, $app, $config) {
    my $self = $class->new(
        app => $app,
        dsn => $config->{dsn},
        username => $config->{username} // '',
        password => $config->{password} // '',
        db_options => $config->{db_options} // {},
        config => $config,
    );

    die "DBWorker requires 'dsn' configuration" unless $self->{dsn};

    # Capture connection params for worker code
    my ($dsn, $username, $password, $options) =
        @{$self}{qw(dsn username password db_options)};

    $self->{function} = IO::Async::Function->new(
        code => sub (@args) {
            _worker_code($dsn, $username, $password, $options, @args);
        },
        min_workers => $config->{min_workers} // 1,
        max_workers => $config->{max_workers} // 4,
        idle_timeout => $config->{idle_timeout} // 300,
        max_worker_calls => $config->{max_worker_calls} // 10000,
    );

    return $self;
}

sub attach_to_loop ($self, $loop) {
    return if $self->{_attached};
    $loop->add($self->{function});
    $self->{_attached} = 1;
}

# Ensure attached to loop before calls
sub _ensure_ready ($self) {
    unless ($self->{_attached}) {
        my $loop = $self->app->loop
            or die "No event loop available";
        $self->attach_to_loop($loop);
    }
}

async sub _call ($self, $op, @args) {
    $self->_ensure_ready;
    return await $self->{function}->call(args => [$op, @args]);
}

# Public API methods

async sub select_all ($self, $sql, @bind) {
    return await $self->_call('select_all', $sql, @bind);
}

async sub select_row ($self, $sql, @bind) {
    return await $self->_call('select_row', $sql, @bind);
}

async sub select_col ($self, $sql, @bind) {
    return await $self->_call('select_col', $sql, @bind);
}

async sub select_value ($self, $sql, @bind) {
    return await $self->_call('select_value', $sql, @bind);
}

async sub do ($self, $sql, @bind) {
    return await $self->_call('do', $sql, @bind);
}

async sub insert ($self, $sql, @bind) {
    return await $self->_call('insert', $sql, @bind);
}

async sub transaction ($self, @statements) {
    return await $self->_call('transaction', \@statements);
}

async sub ping ($self) {
    return await $self->_call('ping');
}

# Cleanup on shutdown
sub DESTROY ($self) {
    if ($self->{function} && $self->{_attached}) {
        # Workers will be cleaned up when loop is destroyed
    }
}

1;

__END__

=head1 CONFIGURATION

=over 4

=item dsn (required)

DBI data source name, e.g., 'dbi:mysql:database=myapp;host=localhost'

=item username, password

Database credentials

=item db_options

Hashref of DBI connection options

=item min_workers (default: 1)

Minimum worker processes to keep alive

=item max_workers (default: 4)

Maximum concurrent worker processes

=item idle_timeout (default: 300)

Seconds before idle workers are terminated

=item max_worker_calls (default: 10000)

Restart worker after this many calls (prevents memory leaks)

=back

=head1 METHODS

=head2 select_all($sql, @bind)

Returns arrayref of hashrefs

=head2 select_row($sql, @bind)

Returns single hashref or undef

=head2 select_col($sql, @bind)

Returns arrayref of first column values

=head2 select_value($sql, @bind)

Returns single scalar value

=head2 do($sql, @bind)

Executes statement, returns affected rows

=head2 insert($sql, @bind)

Executes INSERT, returns last_insert_id

=head2 transaction(\@statements)

Executes statements in transaction. Each element is [$sql, @bind].
Returns arrayref of results. Rolls back on error.

=cut
```

### Generic Worker Service

```perl
package PAGI::Simple::Service::Workers;

use strict;
use warnings;
use experimental 'signatures';

our $VERSION = '0.01';

use parent 'PAGI::Simple::Service::PerApp';
use IO::Async::Function;
use Future::AsyncAwait;

# Operation registry
my %_operations;

sub register_operation ($class, $name, $code, %opts) {
    $_operations{$name} = {
        code => $code,
        description => $opts{description} // '',
        timeout => $opts{timeout},
    };
}

sub _worker_dispatch ($op, @args) {
    my $handler = $_operations{$op}
        or die "Unknown worker operation: $op";
    return $handler->{code}->(@args);
}

sub init_service ($class, $app, $config) {
    my $self = $class->new(
        app => $app,
        config => $config,
    );

    $self->{function} = IO::Async::Function->new(
        code => \&_worker_dispatch,
        min_workers => $config->{min_workers} // 2,
        max_workers => $config->{max_workers} // 8,
        idle_timeout => $config->{idle_timeout} // 60,
        max_worker_calls => $config->{max_worker_calls} // 5000,
    );

    return $self;
}

sub attach_to_loop ($self, $loop) {
    return if $self->{_attached};
    $loop->add($self->{function});
    $self->{_attached} = 1;
}

async sub call ($self, $op, @args) {
    unless ($self->{_attached}) {
        $self->attach_to_loop($self->app->loop);
    }

    return await $self->{function}->call(args => [$op, @args]);
}

sub list_operations ($class) {
    return keys %_operations;
}

1;
```

---

## Testing Strategy

### Unit Tests

```perl
# t/simple/worker/01-basic.t
use Test2::V0;
use PAGI::Simple::Service::Workers;

# Register test operations
PAGI::Simple::Service::Workers->register_operation(
    'test.echo' => sub (@args) { return [@args] }
);

PAGI::Simple::Service::Workers->register_operation(
    'test.add' => sub ($a, $b) { return $a + $b }
);

PAGI::Simple::Service::Workers->register_operation(
    'test.die' => sub { die "Intentional error" }
);

# ... test each operation
```

### Integration Tests

```perl
# t/simple/worker/02-integration.t
use Test2::V0;
use IO::Async::Loop;
use Future::AsyncAwait;

my $loop = IO::Async::Loop->new;

# Create mock app
my $app = MockApp->new(loop => $loop);

# Initialize service
my $workers = PAGI::Simple::Service::Workers->init_service($app, {
    min_workers => 1,
    max_workers => 2,
});
$workers->attach_to_loop($loop);

# Test async operations
my $result = $loop->run_until(async sub {
    return await $workers->call('test.add', 2, 3);
});

is($result, 5, 'Worker returned correct result');
```

### Load Tests

```perl
# t/simple/worker/03-load.t
use Test2::V0;
use Future::Utils qw(fmap_concurrent);

# Spawn many concurrent operations
my @futures = map {
    $workers->call('test.echo', $_)
} 1..100;

my @results = await Future->wait_all(@futures);
# Verify all completed
```

---

## Migration & Compatibility

### For Existing Blocking Code

```perl
# Before: Blocking DBI in handler
$app->get('/users' => sub ($c) {
    my $dbh = DBI->connect($dsn);  # BLOCKS!
    my $users = $dbh->selectall_arrayref($sql);  # BLOCKS!
    $c->json($users);
});

# After: Non-blocking via worker
$app->get('/users' => async sub ($c) {
    my $db = $c->service('DB');
    my $users = await $db->select_all($sql);
    $c->json($users);
});
```

### For Legacy Libraries

```perl
# Register operation for legacy code
PAGI::Simple::Worker->register('legacy.parse' => sub ($data) {
    require Legacy::Parser;
    return Legacy::Parser->parse($data);
});

# Use in handlers
$app->post('/parse' => async sub ($c) {
    my $data = await $c->req->body;
    my $result = await $c->service('Workers')->call('legacy.parse', $data);
    $c->json($result);
});
```

---

## References

### Documentation

- IO::Async::Function: https://metacpan.org/pod/IO::Async::Function
- IO::Async::Loop: https://metacpan.org/pod/IO::Async::Loop
- Future::AsyncAwait: https://metacpan.org/pod/Future::AsyncAwait
- DBI: https://metacpan.org/pod/DBI

### Other Frameworks

- Python asyncio executors: https://docs.python.org/3/library/asyncio-eventloop.html
- Node.js Worker Threads: https://nodejs.org/api/worker_threads.html
- Mojo::IOLoop::Subprocess: https://mojolicious.org/perldoc/Mojo/IOLoop/Subprocess

### Related PAGI Code

- `lib/PAGI/Util/AsyncFile.pm` - Existing worker pattern for file I/O
- `lib/PAGI/Simple/Service/PerApp.pm` - Singleton service scope
- `lib/PAGI/Simple/Context.pm` - Request context with loop access

---

## Open Questions for Future Discussion

1. Should workers support WebSocket/SSE progress reporting?
2. How to handle worker crashes mid-operation?
3. Should there be a "fire and forget" mode for background jobs?
4. Integration with external job queues (Redis, RabbitMQ)?
5. Metrics/monitoring hooks (Prometheus, StatsD)?
6. Should there be SQL query building helpers?

---

*Last updated: 2025-12-08*
