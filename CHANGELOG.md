# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial implementation ([#1])
- Document usage of infra nodes ([#2])
- Configure user workload monitoring defaults ([#4])
- Configure AlertManager ([#6])
- Ability to manage alert rules ([#10])
- Ensure silence in Alertmanager using a CronJob ([#14])
- Add how-to for sending alerts to OpsGenie ([#17])
- Annotate all alerts with the Syn component name ([#18])
- Allow configuring custom annotations via inventory ([#18])

### Changed

- Remove usage of deprecated parameters ([#5])
- Enable Kapitan secrets ([#7])
- Enable storage for AlertManager ([#8])

## Fixed

- Detection of component presence ([#13])

[Unreleased]: https://github.com/appuio/component-openshift4-monitoring/compare/d503a46ca74c912d7599da47a6bb2910dc484d23...HEAD
[#1]: https://github.com/appuio/component-openshift4-monitoring/pull/1
[#2]: https://github.com/appuio/component-openshift4-monitoring/pull/2
[#4]: https://github.com/appuio/component-openshift4-monitoring/pull/4
[#5]: https://github.com/appuio/component-openshift4-monitoring/pull/5
[#6]: https://github.com/appuio/component-openshift4-monitoring/pull/6
[#7]: https://github.com/appuio/component-openshift4-monitoring/pull/7
[#8]: https://github.com/appuio/component-openshift4-monitoring/pull/8
[#10]: https://github.com/appuio/component-openshift4-monitoring/pull/10
[#13]: https://github.com/appuio/component-openshift4-monitoring/pull/13
[#14]: https://github.com/appuio/component-openshift4-monitoring/pull/14
[#17]: https://github.com/appuio/component-openshift4-monitoring/pull/17
[#18]: https://github.com/appuio/component-openshift4-monitoring/pull/18
