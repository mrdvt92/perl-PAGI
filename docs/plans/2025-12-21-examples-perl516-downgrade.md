# Examples Perl 5.16 Downgrade Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Downgrade all examples from Perl 5.32/5.36 to Perl 5.16 compatibility by removing version pragmas and converting any remaining signature syntax.

**Architecture:** Replace `use v5.32;` and `use v5.36;` with explicit `use strict; use warnings;` statements. Convert any subroutine signatures to traditional `my (@args) = @_;` unpacking. Most files already use the correct pattern - only one signature needs conversion.

**Tech Stack:** Perl 5.16+, no special modules required

---

## Files to Modify

| File | Current | Signature Conversion Needed |
|------|---------|---------------------------|
| `examples/12-utf8/app.pl` | v5.36 | No |
| `examples/10-chat-showcase/app.pl` | v5.32 | Yes (line 72) |
| `examples/10-chat-showcase/lib/ChatApp/HTTP.pm` | v5.32 | No |
| `examples/10-chat-showcase/lib/ChatApp/WebSocket.pm` | v5.32 | No |
| `examples/10-chat-showcase/lib/ChatApp/SSE.pm` | v5.32 | No |
| `examples/10-chat-showcase/lib/ChatApp/State.pm` | v5.32 | No |
| `examples/11-job-runner/app.pl` | v5.32 | No |
| `examples/11-job-runner/lib/JobRunner/HTTP.pm` | v5.32 | No |
| `examples/11-job-runner/lib/JobRunner/WebSocket.pm` | v5.32 | No |
| `examples/11-job-runner/lib/JobRunner/SSE.pm` | v5.32 | No |
| `examples/11-job-runner/lib/JobRunner/Queue.pm` | v5.32 | No |
| `examples/11-job-runner/lib/JobRunner/Worker.pm` | v5.32 | No |
| `examples/11-job-runner/lib/JobRunner/Jobs.pm` | v5.32 | No |

---

### Task 1: Downgrade examples/12-utf8/app.pl

**Files:**
- Modify: `examples/12-utf8/app.pl:1-4`

**Step 1: Replace version pragma**

Change:
```perl
use v5.36;
utf8;
```

To:
```perl
use strict;
use warnings;
use utf8;
```

Note: `use v5.36;` enables strict, warnings, and signatures. This file doesn't use signatures, so just need strict/warnings.

**Step 2: Run tests to verify nothing broke**

Run: `prove -l t/`
Expected: All tests pass (this example isn't directly tested but ensures no syntax errors in codebase)

**Step 3: Commit**

```bash
git add examples/12-utf8/app.pl
git commit -m "chore: downgrade examples/12-utf8 to Perl 5.16"
```

---

### Task 2: Downgrade examples/10-chat-showcase/app.pl (with signature conversion)

**Files:**
- Modify: `examples/10-chat-showcase/app.pl:17-19,72`

**Step 1: Replace version pragma**

Change line 17:
```perl
use v5.32;
```

To:
```perl
use strict;
use warnings;
```

And remove lines 18-19 (`use strict;` and `use warnings;`) since they're now redundant.

**Step 2: Convert signature on line 72**

Change:
```perl
my $app = with_logging(async sub ($scope, $receive, $send) {
```

To:
```perl
my $app = with_logging(async sub {
    my ($scope, $receive, $send) = @_;
```

**Step 3: Run tests**

Run: `prove -l t/`
Expected: All tests pass

**Step 4: Commit**

```bash
git add examples/10-chat-showcase/app.pl
git commit -m "chore: downgrade examples/10-chat-showcase/app.pl to Perl 5.16"
```

---

### Task 3: Downgrade examples/10-chat-showcase/lib/*.pm files

**Files:**
- Modify: `examples/10-chat-showcase/lib/ChatApp/HTTP.pm:3-5`
- Modify: `examples/10-chat-showcase/lib/ChatApp/WebSocket.pm:3-5`
- Modify: `examples/10-chat-showcase/lib/ChatApp/SSE.pm:3-5`
- Modify: `examples/10-chat-showcase/lib/ChatApp/State.pm:3-5`

**Step 1: Replace version pragma in each file**

In each file, change:
```perl
use v5.32;
use strict;
use warnings;
```

To:
```perl
use strict;
use warnings;
```

(Just remove the `use v5.32;` line - strict/warnings are already present)

**Step 2: Run tests**

Run: `prove -l t/`
Expected: All tests pass

**Step 3: Commit**

```bash
git add examples/10-chat-showcase/lib/ChatApp/*.pm
git commit -m "chore: downgrade examples/10-chat-showcase/lib to Perl 5.16"
```

---

### Task 4: Downgrade examples/11-job-runner/app.pl

**Files:**
- Modify: `examples/11-job-runner/app.pl:3-5`

**Step 1: Replace version pragma**

Change:
```perl
use v5.32;
use strict;
use warnings;
```

To:
```perl
use strict;
use warnings;
```

**Step 2: Run tests**

Run: `prove -l t/`
Expected: All tests pass

**Step 3: Commit**

```bash
git add examples/11-job-runner/app.pl
git commit -m "chore: downgrade examples/11-job-runner/app.pl to Perl 5.16"
```

---

### Task 5: Downgrade examples/11-job-runner/lib/*.pm files

**Files:**
- Modify: `examples/11-job-runner/lib/JobRunner/HTTP.pm:3-5`
- Modify: `examples/11-job-runner/lib/JobRunner/WebSocket.pm:3-5`
- Modify: `examples/11-job-runner/lib/JobRunner/SSE.pm:3-5`
- Modify: `examples/11-job-runner/lib/JobRunner/Queue.pm:3-5`
- Modify: `examples/11-job-runner/lib/JobRunner/Worker.pm:3-5`
- Modify: `examples/11-job-runner/lib/JobRunner/Jobs.pm:3-5`

**Step 1: Replace version pragma in each file**

In each file, change:
```perl
use v5.32;
use strict;
use warnings;
```

To:
```perl
use strict;
use warnings;
```

**Step 2: Run tests**

Run: `prove -l t/`
Expected: All tests pass

**Step 3: Commit**

```bash
git add examples/11-job-runner/lib/JobRunner/*.pm
git commit -m "chore: downgrade examples/11-job-runner/lib to Perl 5.16"
```

---

### Task 6: Final verification

**Step 1: Verify no v5.32/v5.36 remains in examples**

Run: `grep -r "use v5\." examples/`
Expected: No output (all version pragmas removed)

**Step 2: Run full test suite**

Run: `prove -l t/`
Expected: All 32 tests pass

**Step 3: Commit any stragglers and push**

```bash
git status
git push origin main
```
