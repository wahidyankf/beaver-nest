# Problem Statement

## Objective

Create a continuously available private family application that can be improved frequently with Codex while safely handling shared personal data and documents.

## Users

- Family members using approved devices.
- An administrator who operates the service and develops it with Codex.

## Core needs

- Private access from family devices, including away from home.
- Shared data with per-user or per-role permissions.
- Document uploads and processing with visible progress and recoverable failures.
- Frequent updates without manual, error-prone operating procedures.
- A dependable recovery path for faulty application changes, worker failures, and data mistakes.

## Constraints

- The app is private; public-internet access is not an initial requirement.
- The application and data run on an always-on home host.
- Live data must not be committed to Git or stored in the Dropbox-synchronised repository workspace.
- Browser clients must not receive private records, file paths, credentials, or host-control capabilities beyond their authorisation.

## Success criteria

1. An authorised family member can reach the app through a stable private HTTPS URL.
2. The app persists shared data and documents across application restarts and releases.
3. A document job reports queued, running, complete, or failed state to the submitting user.
4. A permitted administrator can safely restart a failed document worker without exposing a shell or host-control API.
5. A code change is tested and can be reverted without losing production data.
