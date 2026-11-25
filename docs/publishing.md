# Publishing

The four packages are released together from this repository. Pushing a `v*` tag triggers all four GitHub Actions workflows:

| Workflow | Publishes to |
|----------|--------------|
| `publish-npm.yml` | npm — `mocklane-sdk` |
| `publish-dart.yml` | pub.dev — `mocklane` |
| `publish-kotlin.yml` | Maven Central — `io.github.mocklane:mocklane-core`, `-okhttp`, `-ktor` |
| `release-swift.yml` | GitHub Release for the SPM tag |

Tags must point to a `main` commit with a green CI run.

## Versioning and tags

- Package versions live in `packages/js/package.json`, `packages/dart/pubspec.yaml`, and `packages/kotlin/build.gradle.kts`. Swift has no version file; the tag is the version.
- `v0.1.1` triggers every workflow.
- To release one platform at a time, use `npm-v0.1.1`, `dart-v0.1.1`, or `kotlin-v0.1.1`. Swift only reacts to `v*`.

## One-time setup

### Release environment (all publish jobs)

Every publish job declares `environment: release`. A repository admin must create that environment once (**Settings → Environments → New environment**) and add **required reviewers** (and, optionally, a deployment branch/tag rule that only allows `v*` tags). Without the environment, the jobs still run, but there is no approval gate between a pushed tag and an immutable registry release.

### npm

The package is unscoped (`mocklane-sdk`), so no npm organization is needed. The release workflow uses npm **Trusted Publishing** (OIDC): GitHub Actions proves its identity to npm with a short-lived token, so no long-lived npm credential is stored in the repository.

Requirements:

- npm CLI 11.5.1+ on Node 22.14.0+, on a GitHub-hosted runner. `publish-npm.yml` runs Node 24, which satisfies both.
- `permissions.id-token: write` in the workflow (already set) and `environment: release` on the publish job.
- `repository.url` in `packages/js/package.json` must match `https://github.com/mocklane/mocklane-sdk` exactly.

#### First publish (token fallback)

Trusted publishers can be configured only for a package that already exists on npm, so the first publish uses a token. Every later release uses OIDC.

1. Sign in to the npm account that will own the package.
2. Create a granular token with publish rights for `mocklane-sdk` and **Bypass two-factor authentication** enabled. With 2FA on the account, a token without the bypass is rejected at publish time: `E403 ... Two-factor authentication or granular access token with bypass 2fa enabled is required to publish packages`.
3. Add it to the GitHub repo as the `NPM_TOKEN` secret (**Settings → Secrets and variables → Actions**) and run the workflow. The workflow adds the token to `.npmrc` only when the secret is set; an absent secret leaves the job on OIDC.

Alternatively, publish the first version locally with `npm login` and `npm publish` (see **Publish locally**).

#### Configure trusted publishing

1. Publish the package once (previous section) so it exists on npm.
2. On npmjs.com open **mocklane-sdk → Settings → Trusted Publisher**, choose **GitHub Actions**, and enter:
   - Organization or user: `mocklane`
   - Repository: `mocklane-sdk`
   - Workflow filename: `publish-npm.yml` (filename only, case-sensitive)
   - Environment: `release`
3. Allow **npm publish**; only staged publishing is permitted by default, so a direct `npm publish` is rejected without this opt-in.
4. Push a tag or run the workflow within two days. The first successful OIDC publish validates the configuration; an unused configuration expires after two days and must be deleted and recreated.
5. Delete the `NPM_TOKEN` secret.

The workflow publishes with `--provenance`, so npm links each release to the workflow run and commit. Provenance works for public repositories; for a private repo, npm drops the attestation.

### pub.dev

1. Sign in at https://pub.dev with the publishing account.
2. A **verified publisher** requires the `mocklane.io` domain (DNS TXT record). Without it, publish as a normal uploader; consumers see an "unverified publisher" label.
3. Run a local `dart pub publish` once so `~/.config/dart/pub-credentials.json` (Linux) or `~/Library/Application Support/dart/pub-credentials.json` (macOS) exists.
4. Add that file's contents as the `PUB_CREDENTIALS` secret.

### Kotlin / Maven Central (Sonatype Central Portal)

GroupId is **`io.github.mocklane`**, verified through the `mocklane` GitHub organization; no domain is required.

One-time setup:

1. Sign in at [central.sonatype.com](https://central.sonatype.com) with the publishing account and verify the `io.github.mocklane` namespace via the GitHub organization (the Portal walks you through it; takes minutes).
2. Generate a **Portal User Token** (avatar → View User Tokens). This is the credential for uploads, not your login password.
3. Create a PGP key pair, publish the public key to a keyserver (e.g. `keyserver.ubuntu.com`), and keep the ASCII-armored private key + passphrase.
4. Add the GitHub repo secrets:
   - `MAVEN_CENTRAL_USERNAME` / `MAVEN_CENTRAL_PASSWORD` — the Portal user token
   - `SIGNING_KEY` — ASCII-armored private key
   - `SIGNING_PASSWORD` — its passphrase

   `SIGNING_KEY` must be the exact output of `gpg --armor --export-secret-keys <KEY_ID>` with real line breaks. Store it from a file so nothing mangles it: `gpg --armor --export-secret-keys <KEY_ID> | gh secret set SIGNING_KEY`. The workflow fails fast with a shape report when the secret is malformed (binary export, public key, or escaping), because Gradle only says `Could not read PGP secret key`.

The workflow runs `publishAndReleaseToMavenCentral`: artifacts land in the Portal as a validated deployment and are released automatically. To review before release, switch the task to `publishToMavenCentral` and click Publish in the Portal UI.

Versions on Maven Central are **immutable**: a released version cannot be changed or removed, so bump the version before every publish.

### Swift

Nothing to upload: SPM distributes from the git tag. The `v*` workflow runs `swift test` and creates a GitHub Release with generated notes.

## Publish via GitHub Actions

Push the tag:

```bash
git tag v0.1.1
git push origin v0.1.1
```

Or run a workflow manually from **Actions** (`workflow_dispatch`).

## Publish locally

### npm

```bash
cd packages/js
pnpm install
pnpm build
pnpm test

npm login       # once per machine
npm publish     # prepublishOnly re-runs build + test
```

Verify: https://www.npmjs.com/package/mocklane-sdk

### pub.dev

```bash
cd packages/dart
dart pub get

dart analyze
dart test

dart pub publish --dry-run
dart pub publish        # opens a Google OAuth flow the first time
```

### Kotlin

```bash
cd packages/kotlin
./gradlew test

export ORG_GRADLE_PROJECT_mavenCentralUsername=...   # Portal user token username
export ORG_GRADLE_PROJECT_mavenCentralPassword=...   # Portal user token password
export ORG_GRADLE_PROJECT_signingInMemoryKey="$(cat private-key.asc)"   # armored PGP key
export ORG_GRADLE_PROJECT_signingInMemoryKeyPassword=...   # key passphrase

./gradlew publishAndReleaseToMavenCentral   # core, okhttp, and ktor
# or ./gradlew publishToMavenCentral and release from the Portal UI
```

Verify: https://central.sonatype.com/artifact/io.github.mocklane/mocklane-core

### Swift

The root `Package.swift` exists because SPM resolves a package by URL only when the manifest is at the repository root; it exposes the sources in `packages/swift/`. The nested `packages/swift/Package.swift` remains the source of truth for package-local development. Both manifests must stay in sync (platforms, products, resources).

```bash
swift test        # from the repo root
git tag v0.1.1
git push origin v0.1.1
```

## Checklist before publishing

- [ ] Versions bumped in all package manifests; `CHANGELOG.md` updated
- [ ] `pnpm --filter mocklane-sdk test` and `build` pass
- [ ] `dart analyze --fatal-warnings`, `dart test`, and `dart pub publish --dry-run` pass
- [ ] `./gradlew test` passes
- [ ] `swift test` passes from the repo root
- [ ] `main` CI run is green on the tag commit
- [ ] `release` environment exists
- [ ] npm trusted publisher configured for `mocklane-sdk` (`mocklane/mocklane-sdk`, `publish-npm.yml`, `release`); `NPM_TOKEN` exists only for the first publish
- [ ] `PUB_CREDENTIALS` secret is configured
- [ ] Tag pushed; all four workflows green
- [ ] Consumer smoke test from each registry (npm, pub.dev, SPM, Gradle)
