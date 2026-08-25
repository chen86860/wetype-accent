# Security Policy

Please report vulnerabilities through GitHub private vulnerability reporting rather than a public issue.

The patcher intentionally modifies and ad-hoc signs an installed input method. Its safeguards are part of the security boundary:

- exact supported version and original `Assets.car` SHA-256;
- exact expected occurrence counts for every serialized color record;
- a complete Tencent-signed backup;
- CoreUI catalog and deep code-signature validation;
- automatic rollback if signing or runtime verification fails.

Do not weaken these checks to support a new WeType release. Add and test a new version profile instead.
