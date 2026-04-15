# ADR-0005: Key-pair auth for programmatic Snowflake access

- **Status:** accepted
- **Date:** 2026-04-15
- **Deciders:** Eric Silinda

## Context

Terraform, dbt, and any future CI/CD pipeline need to authenticate to Snowflake non-interactively. The initial scaffold assumed `authenticator = "ExternalBrowser"` (SSO via browser popup), but `terraform plan` failed with Snowflake error `390190: There was an error related to the SAML Identity Provider account parameter` — the account does not have SAML federation configured, so there is nothing for the external-browser flow to redirect to. What looks like "SSO" in Snowsight is Snowflake's native username+password+MFA flow, not SAML.

A decision is needed for how programmatic tooling authenticates to Snowflake for the duration of this project.

## Options considered

1. **Username + password + MFA (`USERNAME_PASSWORD_MFA`).** Works without Snowflake-side changes, but forces an MFA prompt on every `terraform plan`/`apply`, requires storing the password in `.env`, and breaks in non-interactive CI/CD.
2. **Key-pair auth (`SNOWFLAKE_JWT`).** Generate an RSA key pair, register the public key on the Snowflake user with `ALTER USER ... SET RSA_PUBLIC_KEY`, and configure Terraform/dbt to sign JWTs with the private key. No prompts, no passwords in state or config, works identically on a laptop and in a GitHub Actions runner.
3. **Configure SAML federation between Snowflake and Microsoft Entra ID.** Stand Snowflake up as a service provider in Entra, exchange metadata, `ALTER ACCOUNT SET SAML_IDENTITY_PROVIDER`. Provides a polished interactive-user story but does nothing for headless workloads — a CI pipeline still cannot complete a browser redirect, so key-pair would still be needed alongside it.

## Decision

Chose **key-pair auth** as the primary authentication mechanism for all programmatic access: Terraform, dbt, and future GitHub Actions jobs. Interactive access through Snowsight continues to use username+password+MFA in the browser — that is untouched.

SAML federation (option 3) is explicitly deferred as a separate "enterprise identity integration" chapter of the portfolio. If attempted later, it supplements key-pair rather than replacing it.

## Consequences

- Every tool that hits Snowflake reads the **same** private key file from a path stored in an env var (`SNOWFLAKE_PRIVATE_KEY_PATH`). One key, one rotation procedure, one story.
- The private key lives **outside** the repo, in `~/.snowflake/keys/` (or the Windows equivalent `%USERPROFILE%\.snowflake\keys\`). It is chmod-protected (600 on Unix). `.gitignore` additionally blocks `*.p8`, `*.pem`, and `*.key` as a defensive backstop.
- The key is generated **unencrypted (PKCS#8, no passphrase)** for simplicity. Acceptable tradeoff for a portfolio project on a personal laptop; in a real production setting the key would be encrypted with a passphrase stored in a secret manager. Call this out explicitly in the portfolio writeup.
- Registering the public key on `LSILINDA` is a **one-time manual step** run in Snowsight as `ACCOUNTADMIN` (or any role that can `ALTER USER LSILINDA`). Documented in the action log.
- Key rotation is a documented chore: generate new pair → `ALTER USER LSILINDA SET RSA_PUBLIC_KEY_2 = '<new>'` → switch Terraform to the new key → `UNSET RSA_PUBLIC_KEY` (old one). Snowflake supports two simultaneous public keys on a user specifically to enable zero-downtime rotation.
- Snowflake provider config uses `authenticator = "SNOWFLAKE_JWT"` + `private_key = file(var.snowflake_private_key_path)`. The `file()` function reads content at plan time; nothing secret ends up in `terraform.tfvars`.
- `.env` gains a `SNOWFLAKE_PRIVATE_KEY_PATH` entry and loses `SNOWFLAKE_AUTHENTICATOR=externalbrowser`.
