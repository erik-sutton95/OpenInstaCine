# Repository settings

The configuration for OpenInstaCine matches the public OpenPocketCine
repository. Verify the applied settings with read-only GitHub queries.

## Main branch

Require a pull request, one approving review, dismissal of stale reviews,
conversation resolution and linear history. Require only **CI gate**, with
checks up to date with `main`. Do not require individual native, Android or
handbook job names: those jobs deliberately skip when their paths do not
change. The simulator conformance suite and the iPad storage oracle run only in
the nightly full suite, which tracks failures on `main` in one issue
([`ci.md`](ci.md)).

Use squash merges only and delete the merged head branch. Disable force
pushes and branch deletion on `main`. Admin enforcement follows Pocket and
remains off for the solo maintainer; enabling additional write access needs
review of that exception.

## Actions

Enable Actions and require SHA pinning. Default `GITHUB_TOKEN` permissions
are read-only; workflows cannot create or approve pull requests. Use
Pocket's `first_time_contributors` approval policy for fork pull requests.
The repository is public, so fork approval applies to outside contributors.

Use hosted runners. The CI workflow handles `pull_request`, pushes to `main`
and manual dispatch. Its untrusted pull-request jobs receive no application
secrets. The `pull_request_target` labeler has no source checkout. The Play
workflow uses its `play-closed` environment only on main pushes or manual
dispatch; the handbook deploy hook runs only after a main handbook change.
Do not expose release or deployment secrets to pull-request code.

## Security and community

Enable Dependabot alerts and security updates. Enable
secret scanning, secret-scanning push protection and private
vulnerability reporting. Verify the private report link in
[`../SECURITY.md`](../SECURITY.md).

Keep issues and discussions enabled and the wiki disabled. Weekly Actions,
Gradle and handbook dependency updates are declared in
`.github/dependabot.yml`. Existing issue/discussion templates, the PR
template and Code of Conduct remain the community entry points.

The sponsor button comes from `.github/FUNDING.yml`:
`buy_me_a_coffee: eriksutton`. The README already links the same optional
support page. Preserve the app's description, homepage and manufacturer-
appropriate topics.
