# ``WebScreenVCKit``

## Overview

`WebScreenVCKit` provides a reusable `WebScreenViewController` with the original UI and logic, while moving app-specific integrations to typed adapters.

Use the new SDK entrypoint:

- ``WebScreenViewController/init(configuration:environment:)``

Main configuration and integration types:

- ``WebScreenConfiguration``
- ``WebScreenEnvironment``
- ``WebScreenEnvironmentValues``
- ``WebScreenCapabilities``

Core adapters:

- ``WebScreenURLPolicy``
- ``WebScreenRouting``
- ``WebScreenDeepLinkHandling``
- ``WebScreenStateStore``
- ``WebScreenPushService``
- ``WebScreenTokenProvider``

## Behavior Model

The controller keeps UI responsibilities and delegates business flow to the internal SDK coordinator.

Flow summary:

1. On `viewDidLoad`, SDK starts coordinator and resolves initial source (`configuration.initialURL` or `stateStore.pushURL`).
2. URL enrichment adds query parameters (`app_type`, optional `app_id`, `a_ssid`, `mb_uuid`) when enabled.
3. Navigation policy is decided by `WebScreenURLPolicy`.
4. JS bridge events are parsed and routed (`agreement`, `dismiss`, `deeplink`, `isHideHeader`).
5. Optional branches (push sync, debug token alert, deeplink execution) depend on `WebScreenCapabilities`.

If required adapters are missing, SDK skips optional branches and logs warnings.

## Migration Guidance

Map old project dependencies to adapters:

- URLRouter -> `WebScreenURLPolicy`
- Router navigation -> `WebScreenRouting`
- AppSettings state -> `WebScreenStateStore`
- DeeplinkManager -> `WebScreenDeepLinkHandling`
- Push interactor -> `WebScreenPushService`
- Token providers -> `WebScreenTokenProvider`

## Topics

### Setup

- ``WebScreenConfiguration``
- ``WebScreenEnvironmentValues``
- ``WebScreenCapabilities``

### Adapters

- ``WebScreenURLPolicy``
- ``WebScreenRouting``
- ``WebScreenDeepLinkHandling``
- ``WebScreenStateStore``
- ``WebScreenPushService``
- ``WebScreenTokenProvider``
