# Changelog

Econia Move source code adheres to [Semantic Versioning] and [Keep a Changelog] standards.

## [Unreleased]

### Added

- Assorted view functions ([#287], [#301]).
- Fill events with common order ID ([#314]).

### Deprecated

- [`market::OrderBook.taker_events`](https://github.com/econia-labs/econia/blob/v4.0.2-audited/src/move/econia/sources/market.move#L587) ([#314])
- [`market::Orders`](https://github.com/econia-labs/econia/blob/v4.0.2-audited/src/move/econia/sources/market.move#L3337) ([#301])
- [`market::TakerEvent`](https://github.com/econia-labs/econia/blob/v4.0.2-audited/src/move/econia/sources/market.move#L600) ([#314])
- [`market::index_orders_sdk()`](https://github.com/econia-labs/econia/blob/v4.0.2-audited/src/move/econia/sources/market.move#L3362) ([#287])
- [`move-to-ts`](https://github.com/hippospace/move-to-ts) attributes ([#292])

[#287]: https://github.com/econia-labs/econia/pull/287
[#292]: https://github.com/econia-labs/econia/pull/292
[#301]: https://github.com/econia-labs/econia/pull/301
[#314]: https://github.com/econia-labs/econia/pull/314
[keep a changelog]: https://keepachangelog.com/en/1.0.0/
[semantic versioning]: https://semver.org/spec/v2.0.0.html
[unreleased]: https://github.com/econia-labs/econia/compare/v4.0.2-audited...HEAD
