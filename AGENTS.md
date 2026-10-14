# AGENTS.md

This file provides guidance to AI coding agents working with code in this repository.

## What this is

`pdns` is a small Ruby gem wrapping the PowerDNS Authoritative HTTP API (v1). It is a DNS
"module" for the ComputeStacks controller, which loads it and drives it through a fixed
interface (see "Module contract" below). Runtime deps are only `httparty` and `json`.

## Commands

Ruby 3.4 (pinned in `.tool-versions`, matching the ComputeStacks controller).

- `bin/setup` / `bundle install` — install dependencies.
- `bundle exec rake` — run the test suite (minitest; default task).
- `bundle exec ruby -Itest test/pdns/zone_test.rb -n test_find_groups_records_by_type` — run
  one test.
- `bin/console` — IRB with the gem loaded, for poking at a live PowerDNS server (see README
  for the required `api=yes` / `webserver=yes` server config).
- `bundle exec rake build` — build the gem into `pkg/`.

Tests never touch the network: WebMock blocks real connections. `test/test_helper.rb` has the
shared stubs (`build_client`, `stub_zone_get`, `stub_zone_patch`, `patch_body`).
`test/fixtures/legacy_zone_21a31b9.marshal` is a zone dumped by the gem at 21a31b9
(`legacy_zone_21a31b9.rb` regenerates it); `test/pdns/marshal_test.rb` keeps it loading.

## Architecture

- **`Pdns` module config** (`lib/pdns.rb`): global, process-wide `Pdns.config` hash —
  `zone_type` (`Native` or `Master`), `masters`, `nameservers`, `server` (the PowerDNS
  server id, default `localhost`). Set via `Pdns.configure(hash)` / `configure_with(yaml)`;
  unknown keys are silently dropped.
- **`Pdns::Client`** (`lib/pdns/client.rb`): all HTTP goes through `exec!(method, path, data)`.
  - The endpoint is `.../api/v1/servers` (a trailing `/<server>` is tolerated and stripped);
    `exec!` prefixes paths with `"#{Pdns.config[:server]}/"` unless they already start with it.
  - Sends both basic auth (webserver password) and `X-API-Key`; TLS verification is off.
  - The `'put'` verb actually issues an HTTP **PATCH** (what PowerDNS uses for rrset changes).
  - 404 → `UnknownObject`, 401 → `AuthenticationFailed`, any other non-2xx → `GeneralError`
    with the response body; timeouts → `ConnectionTimeout`, refused/unreachable/DNS/SSL →
    `ConnectionFailed` (both subclasses of `GeneralError`).
  - `Client.new` makes no request; `version` asks the server, and `api_version` memoizes it.
- **`Pdns::Auth`**: plain credential holder, `(user_id, username, password, api_key)`.
- **`Pdns::Dns::Zone`**: zone ids/names are fully-qualified with a trailing dot. Records are
  held as a hash grouped by type (`{'A' => [ZoneRecord, ...], ...}`). `save` either creates
  the zone (then re-`find`s it) or calls `update!`, which does a **whole-zone sync**: it
  fetches the live rrsets and sends `REPLACE` for every name/type still present locally,
  `DELETE` for every one that isn't, plus `REPLACE` for new ones — so the local record set is
  authoritative and anything omitted is removed from the server. Per rrset, the TTL is the first
  local TTL that differs from the server's (Strings parsed base 10), and each record's `disabled`
  is its own flag, else the server's for identical content, else false.
- **`Pdns::Dns::ZoneRecord`**: maps PowerDNS `content` strings to typed fields per record
  type (`ip` for A/AAAA, `hostname` for CNAME/NS, `priority`+`hostname` for MX, `value`
  otherwise); `raw_value` serializes back, wrapping TXT values in quotes if not already quoted.

## Module contract with ComputeStacks

The controller `Marshal.dump`s live `Zone`/`ZoneRecord` objects into `dns_zones.saved_state`
(with the zone's client cleared) and re-attaches one with `Zone#client=` after `Marshal.load`;
zone I/O without a client raises `MissingParameter`. Old dumps (client included) are still in
the wild, so never rename/remove classes or ivars, treat a missing new ivar (`nil`) as the old
default, and never add `marshal_dump`/`_dump` (older gem versions could not load the result).
The controller addresses records by index within `records[type]`, so never reorder them.

`Pdns.module_kind` (`'DNS'`) and the class methods on `Pdns::Settings` (`host_settings`,
`available_actions` → `update_by_zone`, `allow_unknown_zones?`, `supports_dnssec?`, etc.) are
read by the controller to decide how to use this module. Treat their names and return shapes
as a public API; the error classes in `lib/pdns/errors.rb` are part of it too.

## Release

- Version lives in `lib/pdns/version.rb`.
- The gem is pushed to GitHub Packages (`allowed_push_host` in the gemspec), not RubyGems.
- CI (`.github/workflows/test.yml`) runs `bundle exec rake` on every push and pull request,
  with the Ruby version from `.tool-versions`.
