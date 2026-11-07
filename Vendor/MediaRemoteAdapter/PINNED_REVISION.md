# Native adapter provenance

The files under `Upstream/` are vendored from
[`ungive/mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter)
at commit `0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd`.

They are licensed under BSD-3-Clause; see `Upstream/LICENSE`. Run
`./Vendor/MediaRemoteAdapter/build-framework.sh` from the repository root to
reproduce the universal `arm64` + `x86_64` framework-format resource bundle
used by the app. Its `.bundle` extension prevents Xcode from linking it into
the host process.

The framework uses Apple's private MediaRemote framework and is loaded into
`/usr/bin/perl`; it is never linked into the app target. This is not suitable
for Mac App Store distribution and may stop working on a future macOS release.

