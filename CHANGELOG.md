# Jarvis Changelog

![logo](https://www.nsquared.nz/img/nsquared-logo-big.png)

The Jarvis Web Framework. More information can be found at https://www.nsquared.nz/tech/jarvis.html

## [7.7.2] - 2024-07-25

### Changed

* JVS-14647: Replace custom !NOW placeholder for Mongo with official $$NOW.

### Added

* JVS-14652: Support exporting user ID and principle for AD and basic auth modules.
* JVS-14651: Support RHEL9 as a build target for Jarvis.

## [7.7.1] - 2024-04-18

### Changed

* JVS-14644: Prevent leaking path details to the browser on failed configuration load.
* JVS-14648: Use count_documents or estimated_document_count conditionally based on whether there is a filter defined.

## [7.7.0] - 2024-03-22

### Added

* JVS-14645: Migrate DB support MongoDB 7, deprecating MongoDB 4.

## [7.6.4] - 2023-11-01

### Added

* JVS-14642: Add support for JWT pass-through authentication.

## [7.6.3] - 2023-09-06

### Added

* ACD-12767: Add improved handling for UTF-8 wide characters.

## [7.6.2] - 2023-07-10

### Added

* JVS-14638: Return login expiration time information in status requests.

## [7.6.1] - 2023-06-26

### Added

* JVS-14637: Add support for PosixGroup UID binds on member lookups.

## [7.6.0] - 2023-06-26

### Changed

* JVS-14637: Expand configuration of OpenLDAP implementations to support group searching via DN.

### Fixed

* ACD-12585: Fixed querying of database elements that contain wide characters.

## [7.5.2] - 2023-06-07

### Changed

- JVS-14635: Allow OAuth configuration to specify arbitrary SSL options.

### Added

- JVS-14634: Add missing SystemD path definitions to build file.
- JVS-14637: Add support for TLS and OpenLDAP implementations.

## [7.5.1] - 2022-12-29
### Fixed

- JVS-14633: When using fastcgi, do not include the date & script name in errors. Jarvis does it's own error string generation.

## [7.5.0] - 2022-12-16

### Changed

- JVS-14604: Respond with a HTTP code on database failure.
- N2-10430: Update documentation to use nsquared.nz domain.

## [7.4.0] - 2022-10-26

### Fixed

- JVS-14631: Use a substring match, not a regex match for dataset dir prefix check.

## [7.3.0] - 2022-04-27

### Changed
- 14574: Rework the "varname?" modifier.

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
