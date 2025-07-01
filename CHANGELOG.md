# Changelog

## v4.0.0 - Unreleased

- `connect` and `disconnect` have been removed in favour of `start` and `supervised`.
- TODO: more flexible transactions.
- TODO: date functions changed.

## v3.3.0 - 2025-07-03

- Updated `result.then` to `result.try` to resolve deprecation warnings.

## v3.2.0 - 2025-01-16

- The `url_config` function now defaults to port (5432) when port is not specified.

## v3.1.1 - 2025-01-02

- Fixed a bug where configuring SSL would crash.

## v3.1.0 - 2024-12-22

- Updated for `gleam_stdlib` v0.51.0.

## v3.0.0 - 2024-12-22

- Updated for `gleam_stdlib` v0.50.0.
- The `decode_*` functions have been replaced with `*_decoder` functions.
- `gleam/dynamic/decode.Decoder` is now used for decoding.

## v2.0.0 - 2024-12-21

- Add support for `sslmode` in connection strings.
- Change SSL from `Bool` to `SslVerified`, `SslUnverified` and `SslDisabled` to
  match against diverse CA certificates or not.

## v1.1.0 - 2024-12-11

- Added support for timeout in pool configuration as well as queries.

## v1.0.1 - 2024-11-26

- Corrected a mistake in the `array` function type.

## v1.0.0 - 2024-11-11

- Renamed to `pog`.
- Configuration and query API redesigned.
- Introduced the `Date`, `Time`, and `Timestamp` types.
- The default connection pool size is now 10.

## v0.15.0 - Unreleased

- Ensure `ssl` and `pgo` are running before using `gleam_pgo`.

## v0.14.0 - 2024-08-15

- Add ability to return rows as maps instead of tuple.

## v0.13.0 - 2024-07-17

- Host CA certs are now used to verify SSL by default.

## v0.12.0 - 2024-07-03

- Added the `transaction` function and `TransactionError` type.

## v0.11.0 - 2024-06-22

- Provided functions for handling date values. The `date` function
  coerces a `#(Int, Int, Int)` value representing `#(year, month, day)` into a
  `Value`. The `decode_date` function can be used to decode a dynamic value
  returned from the database as a date in the same tuple format.

## v0.10.0 - 2024-05-31

- The `uri_config` function now accepts the `postgresql://` scheme as well as
  the `postgres://` scheme.

## v0.9.0 - 2024-05-20

- Provided functions for handling timestamp values. The `timestamp` function
  coerces a `#(#(Int, Int, Int), #(Int, Int, Int))` value representing
  `#(#(year, month, day), #(hour, minute, second))` into a `Value`. The
  `decode_timestamp` function can be used to decode a dynamic value returned from
  the database as a timestamp in the same nested tuple format.

## v0.8.0 - 2024-05-20

- Added `array` column handling, accepting a `List` as value.

## v0.7.0 - 2024-04-05

- The password is now optional in the `url_config` function, defaulting to no
  password if none is given.

## v0.6.1 - 2024-01-16

- Relaxed the stdlib version constraint.

## v0.6.0 - 2023-11-06

- Updated for Gleam v0.32.0.

## v0.5.0 - 2023-08-03

- Updated for Gleam v0.30.0.

## v0.4.1 - 2023-03-02

- Updated for Gleam v0.27.0.

## v0.4.0 - 2022-06-12

- IPv6 is now supported through a config option.

## v0.3.0 - 2022-02-17

- Added the `ConnectionUnavailable` error variant.

## v0.2.0 - 2022-01-26

- Migrate to the Gleam build tool.
- API redesigned.

## v0.1.1 - 2020-11-26

- Dependencies updates and versions relaxed.

## v0.1.0 - 2020-08-24

- Initial release.
