# Jarvis Changelog

![logo](https://www.nsquared.co.nz/assets/images/nsquared-logo-big.png) 

The Jarvis Web Framework. More information can be found at https://www.nsquared.co.nz/tech/jarvis.html

## [7.2.1] - 2022-03-31
### Added

### Changed
- 14606: Extend the Single login module with the ability to set oauth_permissions.

### Fixed


## [7.1.0] - 2021-09-11
### Added
- 14574: Add support for HTTP `PATCH` operations as dataset &lg;merge&gt; operations.
- 14592: Add OAuth2 login module.
- 14596: Add support for JSON encoding of complex bind variables using !json.
- 14595: Add the ability for core login modules to accept usernames and passwords through JSON POST data.

### Changed
- 14598: Extend the OAuth2 login module.
- 14597: Replace XML::Smart with XML::LibXML for RHEL 8 support.

### Fixed
- 14600: Ensure JSON dataset `returned` property is a number.
- 14599: Ensure changes made to safe params in dataset_prestore hooks are persisted.


## [6.5.0] - 2018-08-10
### Added
- 10493: Add support for FastCGI (better performance).

### Changed

### Fixed
