# TODO

## PAGI::Server - Ready for Release

### Completed

- ~~More logging levels and control (like Apache)~~ **DONE** - See `log_level` option (debug, info, warn, error)
- ~~Run compliance tests: HTTP/1.1, WebSocket, TLS, SSE~~ **DONE** - See `perldoc PAGI::Server::Compliance`
  - HTTP/1.1: Full compliance (10/10 tests)
  - WebSocket (Autobahn): 215/301 non-compression tests pass (71%); validation added for RSV bits, reserved opcodes, close codes, control frame sizes
- ~~Verify no memory leaks in PAGI::Server and PAGI::Simple~~ **DONE** - See `perldoc PAGI::Server::Compliance`
- ~~Max requests per worker (--max-requests) for long-running deployments~~ **DONE**
  - Workers restart after N requests via `max_requests` parameter
  - CLI: `pagi-server --workers 4 --max-requests 10000 app.pl`
  - Defense against slow memory growth (~6.5 bytes/request observed)
- ~~Worker reaping in multi-worker mode~~ **DONE** - Uses `$loop->watch_process()` for automatic respawn
- ~~Filesystem-agnostic path handling~~ **DONE** - Uses `File::Spec->catfile()` throughout
- ~~File response streaming~~ **DONE** - Supports `file` and `fh` in response body
  - Small files (≤64KB): direct in-process read
  - Large files: sendfile() when available, worker pool fallback
  - Range requests with offset/length

### Future Enhancements (Not Blockers)

- Review common server configuration options (from Uvicorn, Hypercorn, Starman)
- UTF-8 testing for text, HTML, JSON
- Middleware for handling reverse proxy / X-Forwarded-* headers
- Request/body timeouts (low priority - idle timeout handles most cases, typically nginx/HAProxy handles this in production)

## PAGI::Simple - Ready for Release

### Completed

- ~~Strong parameters (like Rails) for form param handling~~ **DONE**
  - Implemented as `PAGI::Simple::StructuredParams`
  - See `perldoc PAGI::Simple::StructuredParams` for full documentation
  - Usage: `(await $c->structured_body)->namespace('x')->permitted(...)->to_hash`
- ~~Worker pool for blocking operations~~ **DONE**
  - `$c->run_blocking(sub { ... })` runs code in worker processes
  - Opt-in via `workers => { max_workers => 4 }` config

### Future Enhancements (Not Blockers)

- Static file serving: pass-through trick for reverse proxy (like Plack)
- CSRF protection middleware/helper for Valiant form integration
- Controller pattern for larger apps
- Path param injection into handler signatures
- Form Objects (Django/Reform inspired)

## Future Ideas

### Worker Pool Enhancements

Level 2 (Worker Service Scope) and Level 3 (Named Worker Pools) are documented
in the codebase history but deemed overkill for a micro-framework. The current
`$c->run_blocking()` covers the common use case.

### Mount Enhancements

- **404 pass-through**: `$app->mount('/api' => $sub_app, { pass_through => 1 })`
- **Shared state via $scope**: `$scope->{'pagi.services'}` for composition

### PubSub / Multi-Worker

**Decision:** PubSub remains single-process (in-memory) by design.

- Industry standard: in-memory for dev, Redis for production
- For multi-worker/multi-server: use Redis or similar external broker
- MCE integration explored but adds complexity

## Documentation (Post-Release)

- Scaling guide: single-worker vs multi-worker vs multi-server
- PubSub limitations and Redis migration path
- Performance tuning guide
- Deployment guide (systemd, Docker, nginx)
