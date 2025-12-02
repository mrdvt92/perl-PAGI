# FIXFORK: Plan to Fix Multi-Worker Fork Handling in PAGI::Server

## Problem Summary

PAGI::Server's multi-worker mode uses POSIX `fork()` directly instead of `IO::Async::Loop->fork()`. This causes:

1. **`$ONE_TRUE_LOOP` not cleared**: Child processes may receive the parent's cached loop singleton instead of a fresh loop
2. **`post_fork()` not called**: Loop subclasses using kernel resources (epoll, kqueue) won't reinitialize properly
3. **Non-idiomatic code**: Manual `select()` loop and `$SIG{}` handlers instead of IO::Async's `watch_process` and `watch_signal`

## Solution Overview

Refactor `_listen_multiworker`, `_spawn_worker`, `_run_as_worker`, and `_parent_monitor_loop` to use IO::Async idiomatically:

- Use `$loop->fork()` instead of POSIX `fork()`
- Use `$loop->watch_process()` instead of manual SIGCHLD handling
- Use `$loop->watch_signal()` instead of `$SIG{TERM/INT}` handlers
- Parent runs `$loop->run()` instead of manual `select()` loop

## Pre-Implementation: Test Baseline

Before any changes, establish that all 106 existing tests pass.

---

## Step 1: Create Diagnostic Test to Prove the Bug

**Goal**: Write a test that demonstrates `$ONE_TRUE_LOOP` is incorrectly shared with child processes.

**File**: `t/12-fork-loop-isolation.t`

**Test Strategy**:
1. Create a multi-worker server (workers => 2)
2. In the worker, capture `refaddr($ONE_TRUE_LOOP)` before and after creating a "new" loop
3. Verify that the child gets a DIFFERENT loop instance than what `$ONE_TRUE_LOOP` pointed to
4. This test should FAIL with current code (proving the bug)

**Acceptance Criteria**:
- Test exists and runs
- Test FAILS with current implementation (expected - proves bug exists)
- Document the failure for reference

---

## Step 2: Create Loop Backend Isolation Tests

**Goal**: Test that fork works correctly with different loop backends.

**File**: `t/12-fork-loop-isolation.t` (extend from Step 1)

**Test Strategy**:
```perl
# Skip if backend not available
BEGIN {
    eval { require IO::Async::Loop::Epoll };
    plan skip_all => "IO::Async::Loop::Epoll not installed" if $@;
}
```

**Backends to test** (each skipped if not installed):
- `IO::Async::Loop::Poll` (always available)
- `IO::Async::Loop::Select` (always available)
- `IO::Async::Loop::Epoll` (Linux only, optional)
- `IO::Async::Loop::EV` (optional)

**Acceptance Criteria**:
- Tests skip gracefully when backend not installed
- Tests should FAIL for epoll/EV with current code (if installed)

---

## Step 3: Refactor `_spawn_worker` to use `$loop->fork()`

**Goal**: Replace POSIX `fork()` with `$loop->fork()`.

**Changes to `lib/PAGI/Server.pm`**:

```perl
# OLD:
sub _spawn_worker ($self, $listen_socket, $worker_num) {
    my $pid = fork();
    die "Fork failed: $!" unless defined $pid;
    if ($pid == 0) {
        $self->_run_as_worker($listen_socket, $worker_num);
        exit(0);
    }
    # ... track worker
}

# NEW:
sub _spawn_worker ($self, $listen_socket, $worker_num) {
    my $loop = $self->loop;

    my $pid = $loop->fork(
        code => sub {
            $self->_run_as_worker($listen_socket, $worker_num);
            return 0;  # Exit code
        },
    );

    die "Fork failed" unless defined $pid;
    # ... track worker (moved to Step 4)
}
```

**Acceptance Criteria**:
- All existing tests pass
- Workers still spawn and function correctly
- `$ONE_TRUE_LOOP` is now properly cleared in children

---

## Step 4: Refactor Worker Tracking to use `watch_process`

**Goal**: Replace manual SIGCHLD handling with `$loop->watch_process()`.

**Changes**:

```perl
# OLD (in _setup_parent_signals):
$SIG{CHLD} = sub {
    while ((my $pid = waitpid(-1, WNOHANG)) > 0) {
        # respawn logic
    }
};

# NEW (in _spawn_worker):
$loop->watch_process($pid => sub {
    my ($pid, $exitcode) = @_;
    delete $self->{worker_pids}{$pid};

    # Respawn if still running and not shutting down
    if ($self->{running} && !$self->{shutting_down}) {
        $self->_spawn_worker($listen_socket, $worker_num);
    }
});
```

**Acceptance Criteria**:
- All existing tests pass
- Worker respawn on crash still works
- No manual SIGCHLD handler needed

---

## Step 5: Refactor Signal Handling to use `watch_signal`

**Goal**: Replace `$SIG{TERM/INT}` with `$loop->watch_signal()`.

**Changes**:

```perl
# OLD (in _setup_parent_signals):
$SIG{TERM} = sub {
    $self->{shutting_down} = 1;
    for my $pid (keys %{$self->{worker_pids}}) {
        kill 'TERM', $pid;
    }
};

# NEW (in _listen_multiworker):
$loop->watch_signal(TERM => sub {
    $self->_initiate_shutdown();
});
$loop->watch_signal(INT => sub {
    $self->_initiate_shutdown();
});
```

**Acceptance Criteria**:
- All existing tests pass
- Graceful shutdown still works (SIGTERM/SIGINT)
- Signal handling is more reliable

---

## Step 6: Replace Manual Select Loop with `$loop->run()`

**Goal**: Parent process uses IO::Async event loop instead of manual `select()`.

**Changes**:

```perl
# OLD:
sub _parent_monitor_loop ($self, $listen_socket) {
    # ... 70+ lines of manual select() loop with self-pipe trick
}

# NEW:
sub _listen_multiworker ($self) {
    # ... setup code ...

    # Fork workers
    for my $i (1 .. $workers) {
        $self->_spawn_worker($listen_socket, $i);
    }

    # Parent runs event loop (handles signals, process exits via watches)
    $self->loop->run;

    # Cleanup after loop exits
    close($listen_socket);
}
```

**Acceptance Criteria**:
- All existing tests pass
- Parent properly monitors workers
- Shutdown is clean and complete
- `_parent_monitor_loop` method can be removed

---

## Step 7: Clean Up `_run_as_worker`

**Goal**: Simplify worker initialization now that `$loop->fork()` handles cleanup.

**Changes**:
- Remove manual signal reset (now handled by `$loop->fork()` with `keep_signals => 0`)
- Remove `$loop_class->new` workaround (now gets fresh loop automatically)
- Simplify to just use `IO::Async::Loop->new` which returns fresh instance

```perl
# OLD:
sub _run_as_worker ($self, $listen_socket, $worker_num) {
    $SIG{CHLD} = 'DEFAULT';
    $SIG{TERM} = 'DEFAULT';
    $SIG{INT}  = 'DEFAULT';

    my $loop_class = $self->{loop_class} || 'IO::Async::Loop';
    my $loop = $loop_class->new;
    # ...
}

# NEW:
sub _run_as_worker ($self, $listen_socket, $worker_num) {
    # $loop->fork() already cleared $ONE_TRUE_LOOP and reset signals
    my $loop = IO::Async::Loop->new;  # Gets fresh loop
    # ...
}
```

**Acceptance Criteria**:
- All existing tests pass
- Workers get fresh loop instances
- Code is simpler and cleaner

---

## Step 8: Remove Dead Code

**Goal**: Remove methods that are no longer needed.

**Methods to remove or simplify**:
- `_setup_parent_signals` - replaced by `watch_signal`
- `_parent_monitor_loop` - replaced by `$loop->run()`
- `$self->{loop_class}` tracking - no longer needed

**Acceptance Criteria**:
- All existing tests pass
- No unused code remains
- Code is cleaner and more maintainable

---

## Step 9: Verify Bug Fix Tests Now Pass

**Goal**: The diagnostic tests from Steps 1-2 should now PASS.

**Verification**:
1. Run `t/12-fork-loop-isolation.t`
2. All subtests should pass
3. Loop isolation is confirmed working

**Acceptance Criteria**:
- All tests in `t/12-fork-loop-isolation.t` pass
- Tests pass with Poll, Select, Epoll (if available), EV (if available)

---

## Step 10: Add Regression Test for Worker Respawn

**Goal**: Ensure worker respawn still works correctly with new implementation.

**File**: `t/11-multiworker.t` (extend existing)

**Test Strategy**:
1. Start multi-worker server
2. Kill one worker process
3. Verify it respawns
4. Verify server still handles requests

**Acceptance Criteria**:
- Test exists and passes
- Worker respawn is reliable

---

## Step 11: Documentation Updates

**Goal**: Update documentation to reflect new implementation.

**Files to update**:
- `lib/PAGI/Server.pm` POD - document multi-worker behavior
- `CLAUDE.md` - if any development workflow changes

**Acceptance Criteria**:
- Documentation is accurate
- No references to old implementation

---

## Step 12: Final Verification

**Goal**: Complete test suite passes, code review.

**Verification**:
1. Run full test suite: `prove -l t/`
2. All 106+ tests pass
3. New tests pass
4. Manual testing of multi-worker mode

**Acceptance Criteria**:
- All tests pass
- Code is clean and well-documented
- Fork handling follows IO::Async best practices

---

## Rollback Plan

If issues arise that cannot be resolved:

1. `git checkout lib/PAGI/Server.pm` to restore original
2. Keep diagnostic tests for future reference
3. Document what went wrong for future attempts

---

## Files Changed

| File | Action |
|------|--------|
| `lib/PAGI/Server.pm` | Major refactor of multi-worker code |
| `t/12-fork-loop-isolation.t` | New test file |
| `t/11-multiworker.t` | Extended with respawn tests |
| `FIXFORK-progress.md` | Progress tracking |

---

## Estimated Complexity

- **Lines added**: ~50 (new tests, cleaner implementation)
- **Lines removed**: ~100 (manual select loop, signal handlers)
- **Net change**: Simpler, more correct code
